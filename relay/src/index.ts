import { deviceIdValid, parseToken } from "./ids";
import { handleMcp } from "./mcp";
import { challenge, handleOAuth } from "./oauth";
import { err, bearer, json, hmacHex, safeEqual } from "./util";

export { Mailbox } from "./mailbox";
export { Registry } from "./registry";

async function mailboxFor(env: Env, req: Request): Promise<{ stub: DurableObjectStub; token: string } | Response> {
  const token = bearer(req);
  const p = token ? parseToken(token) : null;
  if (!token || !p) return err(401, "unauthorized", "missing or malformed bearer token", { }) ;
  if (!env.RELAY_SECRET) return err(500, "misconfigured", "RELAY_SECRET is not set");
  if (!(await deviceIdValid(env.RELAY_SECRET, p.deviceId))) return err(401, "unauthorized", "invalid credential");
  return { stub: env.MAILBOX.get(env.MAILBOX.idFromName(p.deviceId)), token };
}

const AGENT_PATHS = [/^\/v1\/notify$/, /^\/v1\/status$/, /^\/v1\/receipts\/[^/]+$/, /^\/v1\/replies\/[^/]+$/];

export default {
  async fetch(req: Request, env: Env): Promise<Response> {
    const url = new URL(req.url);
    const path = url.pathname;

    if (path === "/" || path === "/healthz") return json(200, { service: "herald-relay", ok: true });

    const oauth = await handleOAuth(req, env, url);
    if (oauth) return oauth;

    // Pairing: the only unauthenticated routes. The Registry rate-limits them.
    if (req.method === "POST" && (path === "/v1/pair/start" || path === "/v1/pair")) {
      if (!env.RELAY_SECRET) return err(500, "misconfigured", "RELAY_SECRET is not set");
      const reg = env.REGISTRY.get(env.REGISTRY.idFromName("registry"));
      return reg.fetch(new Request("https://registry" + (path === "/v1/pair" ? "/pair" : "/pair/start"), {
        method: "POST", body: await req.text(), headers: { "x-pairing-secret": req.headers.get("x-pairing-secret") ?? "" },
      }));
    }

    // Signed, time-limited voice-reply downloads (no bearer: the signature is the credential).
    if (req.method === "GET" && path.startsWith("/v1/audio/")) {
      const key = decodeURIComponent(path.slice("/v1/audio/".length));
      const exp = Number(url.searchParams.get("exp"));
      const sig = url.searchParams.get("sig") ?? "";
      if (!/^[0-9a-f]{48}\/r_[0-9a-f]{24}\.m4a$/.test(key) || !Number.isFinite(exp)) return err(404, "not_found", "no such audio");
      if (exp < Date.now() / 1000) return err(410, "expired", "this audio link has expired; read the reply again for a fresh one");
      if (!safeEqual(sig, await hmacHex(env.RELAY_SECRET, `audio:${key}:${exp}`))) return err(403, "forbidden", "bad signature");
      const obj = await env.AUDIO.get(key);
      if (!obj) return err(404, "not_found", "no such audio");
      return new Response(obj.body, { headers: { "content-type": "audio/mp4", "cache-control": "private, no-store", "content-length": String(obj.size) } });
    }

    if (path === "/mcp") {
      // Unauthenticated or bad credentials: 401 with the discovery pointer, so an OAuth client knows where to start.
      const unauthorized = (r: Response) => {
        if (r.status !== 401) return r;
        const h = new Headers(r.headers);
        h.set("www-authenticate", challenge(url.origin, !!bearer(req)));
        return new Response(r.body, { status: 401, headers: h });
      };
      const m = await mailboxFor(env, req);
      if (m instanceof Response) return unauthorized(m);
      const auth = "Bearer " + m.token;
      return unauthorized(await handleMcp(req, (p, init) =>
        m.stub.fetch(new Request(url.origin + p, { ...init, headers: { authorization: auth, "content-type": "application/json" } }))));
    }

    const isDevice = path === "/v1/device" || path.startsWith("/v1/device/");
    if (isDevice || AGENT_PATHS.some((r) => r.test(path))) {
      const m = await mailboxFor(env, req);
      if (m instanceof Response) return m;
      return m.stub.fetch(req);
    }
    return err(404, "not_found", "no such endpoint");
  },
} satisfies ExportedHandler<Env>;
