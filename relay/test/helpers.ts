import { SELF } from "cloudflare:test";

export const BASE = "https://relay.test";
export const f = (path: string, init: RequestInit = {}) => SELF.fetch(BASE + path, init);
export const auth = (t: string, extra: Record<string, string> = {}) => ({ authorization: "Bearer " + t, "content-type": "application/json", ...extra });

export async function pair(): Promise<{ deviceId: string; token: string }> {
  const s = await f("/v1/pair/start", { method: "POST", body: "{}" });
  if (s.status !== 201) throw new Error("start " + s.status + await s.text());
  const { code } = (await s.json()) as { code: string };
  const p = await f("/v1/pair", { method: "POST", body: JSON.stringify({ code }) });
  if (p.status !== 200) throw new Error("pair " + p.status);
  const j = (await p.json()) as { deviceId: string; deviceToken: string };
  return { deviceId: j.deviceId, token: j.deviceToken };
}

export async function mintKey(token: string, name = "bot", client = "claude"): Promise<{ id: string; key: string }> {
  const r = await f("/v1/device/keys", { method: "POST", headers: auth(token), body: JSON.stringify({ name, client, scope: "notify" }) });
  if (r.status !== 201) throw new Error("key " + r.status + await r.text());
  return (await r.json()) as { id: string; key: string };
}

export const notify = (key: string, body: unknown) => f("/v1/notify", { method: "POST", headers: auth(key), body: JSON.stringify(body) });

export async function connect(token: string) {
  const res = await f("/v1/device/stream", { headers: { upgrade: "websocket", authorization: "Bearer " + token } });
  const ws = res.webSocket!;
  ws.accept();
  const msgs: any[] = [];
  const waiters: Array<() => void> = [];
  ws.addEventListener("message", (e) => { msgs.push(JSON.parse(e.data as string)); waiters.splice(0).forEach((w) => w()); });
  async function next(type = "notify", ms = 2000): Promise<any> {
    const end = Date.now() + ms;
    for (;;) {
      const i = msgs.findIndex((m) => m.type === type);
      if (i >= 0) return msgs.splice(i, 1)[0];
      if (Date.now() > end) throw new Error("timeout waiting for " + type);
      await new Promise<void>((r) => { waiters.push(r); setTimeout(r, 50); });
    }
  }
  return { ws, msgs, next, send: (o: unknown) => ws.send(JSON.stringify(o)) };
}
