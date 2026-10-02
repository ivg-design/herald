// Remote MCP (Streamable HTTP, protocol 2025-06-18), hand-rolled on purpose: the surface is four tools, every
// reply is a single JSON response (no SSE, no sessions), and there is no dependency to audit. Auth is the agent
// key; every tool call is forwarded to the key's own mailbox through the same checked HTTP endpoints.

import { MAX_LONG_POLL_S } from "./mailbox";

const PROTOCOL = "2025-06-18";
const SUPPORTED = new Set(["2025-06-18", "2025-03-26", "2024-11-05"]);

const NOTIFY_PROPS = {
  title: { type: "string", maxLength: 200, description: "Headline of the notification." },
  body: { type: "string", maxLength: 8000, description: "Message text." },
  subtitle: { type: "string", maxLength: 200, description: "A second line under the title." },
  status: { type: "string", description: "A short word shown as a badge: done, error, warning, question, info... Only a label; it changes nothing else." },
  project: { type: "string", maxLength: 100 },
  session: { type: "string", maxLength: 100 },
  task: { type: "string", maxLength: 100 },
  tool: { type: "string", maxLength: 100 },
  duration: { type: "string", description: "For example \"2m 14s\"." },
  link: { type: "string", description: "An https URL the user can open from the banner (the Open link button)." },
  group: { type: "string", maxLength: 100, description: "Notifications with the same group stack together into one banner." },
  priority: { type: "string", enum: ["low", "normal", "high", "urgent"], description: "urgent may break quiet hours only if the user allowed it." },
  persistent: { type: "boolean", description: "Default true: the banner stays until the user dismisses it. false lets Herald's own default timeout dismiss it." },
  timeoutSeconds: { type: "number", minimum: 1, maximum: 3600, description: "Dismiss the banner by itself after this many seconds (hovering pauses it). Leave out to keep it until dismissed." },
  sound: { type: "string", maxLength: 40, description: "A system sound name such as Glass or Tink, \"default\" (the sender's own sound) or \"none\" for silence. File paths are not accepted." },
  presentation: { type: "string", enum: ["banner", "voice", "both"], description: "banner (default): a banner, plus speech if speak is set. voice: speech only, no banner (implies speak: true). both: banner and speech (implies speak: true)." },
  speak: {
    description: "true speaks title then body on the Mac; a string speaks that text instead; or an object {text, voice, speed, lang}. Spoken in addition to the banner unless presentation is voice. Silenced (banner still shown) in quiet hours that silence speech.",
    oneOf: [
      { type: "boolean" },
      { type: "string", maxLength: 2000 },
      { type: "object", additionalProperties: false, properties: { text: { type: "string", maxLength: 2000 }, voice: { type: "string" }, speed: { type: "number", minimum: 0.5, maximum: 2 }, lang: { type: "string" } } },
    ],
  },
  voice: { type: "string", description: "Voice name for speech, for example af_heart. Setting it turns speak on." },
  speed: { type: "number", minimum: 0.5, maximum: 2, description: "Speech speed, 0.5 to 2. Setting it turns speak on." },
  icon: { type: "string", description: "Sender icon: an https image URL or a data:image/png|jpeg|gif|webp;base64 image up to 256 KB. Replaces the icon shown for this key's notifications (the user's own custom icon wins)." },
  imageURL: { type: "string", description: "An https URL of a preview image to show on the banner." },
  tags: { type: "array", maxItems: 10, items: { type: "string", maxLength: 32 }, description: "Short labels stored with the notification for the user's templates and search." },
  notificationId: { type: "string", pattern: "^[A-Za-z0-9._:-]{1,128}$", description: "Your own id. Sending the same id again within 24 hours never shows a second banner (idempotent)." },
  expectReply: { type: "boolean", description: "Only adds the Reply (text) and Record (voice) buttons; the title, look and persistence are unchanged. Read the answer with wait_for_reply." },
  allowVoiceReply: { type: "boolean", description: "Default true. Set false to hide the Record button on this notification." },
} as const;

const TOOLS = [
  {
    name: "send_notification",
    title: "Send a notification to the user's Mac",
    description:
      "Queue a notification for the user's Mac. Text and presentation only (persistent, timeoutSeconds, sound, speak, voice, speed, presentation, priority, group, icon, imageURL, tags): " +
      "no buttons, commands, callbacks or scripts are accepted, and a request with such fields is refused with 400 naming them. By default the banner stays until the user dismisses it. " +
      "A spoken banner that stays: {\"title\":\"Build done\",\"body\":\"All tests passed\",\"speak\":true,\"persistent\":true}. Quiet hours and mute are enforced on the Mac, " +
      "so check get_receipt: `received` means the relay has it, `displayed` that a banner was shown, `spoken` that speech finished, `suppressed` (with `reason`) that the user's settings held it back. " +
      "Limits: 60 per 10 minutes per key, 32 KB per request.",
    inputSchema: { type: "object", additionalProperties: false, required: ["title"], properties: NOTIFY_PROPS },
    annotations: { readOnlyHint: false, destructiveHint: false, idempotentHint: true, openWorldHint: false },
  },
  {
    name: "get_receipt",
    title: "Get delivery receipts",
    description: "Receipts for a notification you sent: received, displayed, spoken, replied (with the reply), suppressed (with reason). Ids are kept 24 hours.",
    inputSchema: { type: "object", additionalProperties: false, required: ["notificationId"], properties: { notificationId: { type: "string" } } },
    annotations: { readOnlyHint: true, openWorldHint: false },
  },
  {
    name: "wait_for_reply",
    title: "Wait for the user's reply",
    description:
      `Wait up to ${MAX_LONG_POLL_S - 5} seconds for the user's answer to a notification sent with expectReply. Returns {replied:false, timedOut:true} when nothing came; call again to keep waiting. ` +
      "A typed answer is `text`. A voice answer has `transcript` (made on the user's Mac, may be imperfect) and `audioUrl` (valid about an hour) with `durationSeconds`.",
    inputSchema: { type: "object", additionalProperties: false, required: ["notificationId"], properties: { notificationId: { type: "string" }, timeoutSeconds: { type: "integer", minimum: 0, maximum: MAX_LONG_POLL_S - 5 } } },
    annotations: { readOnlyHint: true, openWorldHint: false },
  },
  {
    name: "herald_status",
    title: "Is the user's Mac reachable",
    description: "Whether the user's Herald is online, when it was last seen, and whether quiet hours are active. Nothing else about the Mac is exposed.",
    inputSchema: { type: "object", additionalProperties: false, properties: {} },
    annotations: { readOnlyHint: true, openWorldHint: false },
  },
];

type Rpc = { jsonrpc?: string; id?: string | number | null; method?: string; params?: Record<string, unknown> };

const ok = (id: unknown, result: unknown) => ({ jsonrpc: "2.0", id, result });
const fail = (id: unknown, code: number, message: string) => ({ jsonrpc: "2.0", id: id ?? null, error: { code, message } });

export async function handleMcp(req: Request, forward: (path: string, init?: RequestInit) => Promise<Response>): Promise<Response> {
  const headers = { "content-type": "application/json; charset=utf-8", "cache-control": "no-store" };
  if (req.method === "GET" || req.method === "DELETE") {
    return new Response(JSON.stringify(fail(null, -32000, "this server answers POST only (no SSE stream, no sessions)")), { status: 405, headers: { ...headers, allow: "POST" } });
  }
  if (req.method !== "POST") return new Response("method not allowed", { status: 405 });

  let msg: Rpc;
  try {
    const parsed = await req.json();
    if (Array.isArray(parsed)) return new Response(JSON.stringify(fail(null, -32600, "batches are not supported in protocol 2025-06-18")), { status: 400, headers });
    msg = parsed as Rpc;
  } catch { return new Response(JSON.stringify(fail(null, -32700, "parse error")), { status: 400, headers }); }

  const reply = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers });
  if (msg.method === undefined) return reply(fail(msg.id, -32600, "not a request"), 202); // a response from the client: ignore
  // Every request, even one answered locally, must carry a valid agent key.
  const probe = await forward("/v1/status");
  if (probe.status === 401 || probe.status === 403) return probe;
  if (msg.id === undefined) return new Response(null, { status: 202 }); // notification (notifications/initialized ...)

  switch (msg.method) {
    case "initialize": {
      const asked = String((msg.params as { protocolVersion?: string } | undefined)?.protocolVersion ?? "");
      return reply(ok(msg.id, {
        protocolVersion: SUPPORTED.has(asked) ? asked : PROTOCOL,
        capabilities: { tools: { listChanged: false } },
        serverInfo: { name: "herald-relay", title: "Herald cloud relay", version: "1.0.0" },
        instructions: "Send notifications to the user's Mac with send_notification; read receipts with get_receipt; wait for an answer with wait_for_reply. Text and presentation fields only (persistent, timeoutSeconds, sound, speak, presentation...). Nothing else is exposed. " +
          "No browser to sign in with? Use the OAuth device flow instead of a key: POST /register (client_name, grant_types [\"urn:ietf:params:oauth:grant-type:device_code\"]), POST /device_authorization (client_id), tell the user the user_code, poll POST /token (grant_type urn:ietf:params:oauth:grant-type:device_code) every `interval` seconds.",
      }));
    }
    case "ping": return reply(ok(msg.id, {}));
    case "tools/list": return reply(ok(msg.id, { tools: TOOLS }));
    case "tools/call": {
      const p = (msg.params ?? {}) as { name?: string; arguments?: Record<string, unknown> };
      const a = p.arguments ?? {};
      let r: Response;
      switch (p.name) {
        case "send_notification":
          r = await forward("/v1/notify", { method: "POST", body: JSON.stringify(a) }); break;
        case "get_receipt":
          if (typeof a.notificationId !== "string") return reply(ok(msg.id, toolError("notificationId is required")));
          r = await forward(`/v1/receipts/${encodeURIComponent(a.notificationId)}`); break;
        case "wait_for_reply": {
          if (typeof a.notificationId !== "string") return reply(ok(msg.id, toolError("notificationId is required")));
          const t = Math.min(MAX_LONG_POLL_S - 5, Math.max(0, Number(a.timeoutSeconds ?? 30) || 0));
          r = await forward(`/v1/replies/${encodeURIComponent(a.notificationId)}?wait=${t}`); break;
        }
        case "herald_status":
          r = await forward("/v1/status"); break;
        default:
          return reply(fail(msg.id, -32602, `unknown tool: ${String(p.name)}`));
      }
      if (r.status === 401 || r.status === 403) return r; // a bad key is an HTTP error, not a tool result
      const data = await r.json().catch(() => ({}));
      const result = { content: [{ type: "text", text: JSON.stringify(data) }], structuredContent: data, ...(r.ok ? {} : { isError: true }) };
      return reply(ok(msg.id, result));
    }
    default:
      return reply(fail(msg.id, -32601, `method not found: ${msg.method}`));
  }
}

function toolError(message: string) {
  return { content: [{ type: "text", text: message }], isError: true };
}
