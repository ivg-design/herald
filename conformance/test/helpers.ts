import WebSocket from "ws";

const raw = process.env.RELAY_URL;
if (!raw) {
  throw new Error("RELAY_URL is required, e.g. RELAY_URL=http://127.0.0.1:8787 npm test -w conformance");
}
export const BASE = raw.replace(/\/+$/, "");
export const PAIRING_SECRET = process.env.PAIRING_SECRET;
export const OAUTH = process.env.OAUTH === "1";

// A relay may answer 4xx (413, 401) without reading the request body. `wrangler dev` (workerd) then fails the next
// request with a spurious 500 "Network connection lost" from its own proxy. That is a dev-server artifact, not relay
// behavior, so retry such a response once. Bodies here are strings/bytes, so replaying them is safe.
export async function f(path: string, init: RequestInit = {}): Promise<Response> {
  const go = () => fetch(BASE + path, { ...init, headers: { connection: "close", ...(init.headers as Record<string, string> | undefined) } });
  const r = await go();
  if (r.status === 500) {
    const t = await r.clone().text().catch(() => "");
    if (t.includes("Network connection lost")) return go();
  }
  return r;
}
export const auth = (t: string, extra: Record<string, string> = {}) => ({
  authorization: "Bearer " + t,
  "content-type": "application/json",
  ...extra,
});
export const j = async (r: Response) => (await r.json()) as any;
export const sleep = (ms: number) => new Promise<void>((r) => setTimeout(r, ms));

export async function pairStart(): Promise<Response> {
  const headers: Record<string, string> = {};
  if (PAIRING_SECRET) headers["x-pairing-secret"] = PAIRING_SECRET;
  return f("/v1/pair/start", { method: "POST", headers, body: "{}" });
}

export async function pair(): Promise<{ deviceId: string; token: string }> {
  const s = await pairStart();
  if (s.status !== 201) throw new Error("pair/start " + s.status + " " + (await s.text()));
  const { code } = (await s.json()) as { code: string };
  const p = await f("/v1/pair", { method: "POST", body: JSON.stringify({ code }) });
  if (p.status !== 200) throw new Error("pair " + p.status + " " + (await p.text()));
  const b = (await p.json()) as { deviceId: string; deviceToken: string };
  return { deviceId: b.deviceId, token: b.deviceToken };
}

export async function mintKey(token: string, name = "bot", client = "claude"): Promise<{ id: string; key: string }> {
  const r = await f("/v1/device/keys", { method: "POST", headers: auth(token), body: JSON.stringify({ name, client, scope: "notify" }) });
  if (r.status !== 201) throw new Error("mint key " + r.status + " " + (await r.text()));
  return (await r.json()) as { id: string; key: string };
}

export const notify = (key: string, body: unknown) =>
  f("/v1/notify", { method: "POST", headers: auth(key), body: JSON.stringify(body) });

export type Conn = Awaited<ReturnType<typeof connect>>;
const open: WebSocket[] = [];

export async function connect(token: string) {
  const url = BASE.replace(/^http/, "ws") + "/v1/device/stream";
  const ws = new WebSocket(url, { headers: { authorization: "Bearer " + token } });
  const msgs: any[] = [];
  const waiters: Array<() => void> = [];
  ws.on("message", (d) => {
    try { msgs.push(JSON.parse(d.toString())); } catch { /* ignore non-JSON */ }
    waiters.splice(0).forEach((w) => w());
  });
  await new Promise<void>((res, rej) => {
    ws.once("open", () => res());
    ws.once("error", rej);
    ws.once("unexpected-response", (_q, r) => rej(new Error("ws upgrade refused: " + r.statusCode)));
  });
  open.push(ws);
  async function next(type = "notify", ms = 5000): Promise<any> {
    const end = Date.now() + ms;
    for (;;) {
      const i = msgs.findIndex((m) => m.type === type);
      if (i >= 0) return msgs.splice(i, 1)[0];
      if (Date.now() > end) throw new Error("timeout waiting for " + type);
      await new Promise<void>((r) => { waiters.push(r); setTimeout(r, 50); });
    }
  }
  return { ws, msgs, next, send: (o: unknown) => ws.send(JSON.stringify(o)), close: () => ws.close() };
}

/** Close every WebSocket a test opened. Call from afterEach. */
export function closeAll() {
  for (const w of open.splice(0)) { try { w.terminate(); } catch { /* */ } }
}

export const audioPut = (token: string, id: string, body: Uint8Array, type = "audio/mp4") =>
  f(`/v1/device/reply/${id}/audio`, { method: "PUT", headers: { authorization: "Bearer " + token, "content-type": type }, body });

export const rpc = (key: string, body: unknown) =>
  f("/mcp", { method: "POST", headers: { ...auth(key), accept: "application/json, text/event-stream" }, body: JSON.stringify(body) });
