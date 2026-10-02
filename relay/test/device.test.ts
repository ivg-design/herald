import { describe, expect, it } from "vitest";
import { runInDurableObject } from "cloudflare:test";
import { env } from "cloudflare:test";
import { auth, connect, f, pair } from "./helpers";

const j = async (r: Response) => (await r.json()) as any;
const GRANT = "urn:ietf:params:oauth:grant-type:device_code";
const form = (o: Record<string, string>) => ({ method: "POST", headers: { "content-type": "application/x-www-form-urlencoded" }, body: new URLSearchParams(o).toString() });
const rpc = (token: string, body: unknown) => f("/mcp", { method: "POST", headers: auth(token), body: JSON.stringify(body) });

async function deviceClient(name = "Cloud agent") {
  const r = await f("/register", { method: "POST", body: JSON.stringify({ client_name: name, grant_types: [GRANT] }) });
  expect(r.status).toBe(201);
  return (await j(r)) as { client_id: string };
}

async function startDevice(deviceId: string, clientId: string) {
  const { env: e } = { env };
  const list = await e.REGISTRY.get(e.REGISTRY.idFromName("registry")).fetch("https://registry/devices", { method: "POST", body: "{}" });
  const { devices } = (await list.json()) as { devices: { id: string }[] };
  const idx = devices.findIndex((d) => d.id === deviceId) + 1;
  return f("/device_authorization", form({ client_id: clientId, scope: "notify", device: String(idx) }));
}

/** Rewinds the poll clock so a test does not wait the real 5 seconds. */
async function rewindPoll(deviceId: string, seconds = 6) {
  const stub = env.MAILBOX.get(env.MAILBOX.idFromName(deviceId));
  await runInDurableObject(stub, (_i, state) => { state.storage.sql.exec("UPDATE oauth_requests SET last_poll = last_poll - ? WHERE flow = 'device'", seconds * 1000); });
}

const poll = (clientId: string, code: string) => f("/token", form({ grant_type: GRANT, client_id: clientId, device_code: code }));

describe("device authorization grant (RFC 8628)", () => {
  it("advertises the endpoint and the grant", async () => {
    const m = await j(await f("/.well-known/oauth-authorization-server"));
    expect(m.device_authorization_endpoint).toBe("https://relay.test/device_authorization");
    expect(m.grant_types_supported).toContain(GRANT);
  });

  it("registers a device-only client without redirect_uris", async () => {
    const { client_id } = await deviceClient();
    expect(client_id).toMatch(/^hc_/);
    const bad = await f("/register", { method: "POST", body: JSON.stringify({ client_name: "x" }) });
    expect(bad.status).toBe(400);
  });

  it("issues a device_code and an 8-character user code without ambiguous glyphs", async () => {
    const dev = await pair();
    const { client_id } = await deviceClient();
    const r = await startDevice(dev.deviceId, client_id);
    expect(r.status).toBe(200);
    const d = await j(r);
    expect(d.user_code).toMatch(/^[BCDFGHJKMNPQRTWXZ]{4}-[BCDFGHJKMNPQRTWXZ]{4}$/);
    expect(d.device_code).toMatch(/^hrv_[0-9a-f]{48}_[0-9a-f]{64}$/);
    expect(d.verification_uri).toBe("https://relay.test/activate");
    expect(d.verification_uri_complete).toBe("https://relay.test/activate?user_code=" + encodeURIComponent(d.user_code));
    expect(d.expires_in).toBe(600);
    expect(d.interval).toBe(5);
  });

  it("pushes a consent item with userCode to the Mac immediately", async () => {
    const dev = await pair();
    const ws = await connect(dev.token);
    const { client_id } = await deviceClient("Codex cloud");
    const d = await j(await startDevice(dev.deviceId, client_id));
    const c = await ws.next("consent");
    expect(c.flow).toBe("device");
    expect(c.userCode).toBe(d.user_code);
    expect(c.clientName).toBe("Codex cloud");
    expect(c.scope).toBe("notify");
    expect(c.status).toBe("pending");
    expect(c.code).toMatch(/^[0-9]{6}$/);
    const list = await j(await f("/v1/device/consents", { headers: auth(dev.token) }));
    expect(list.consents[0].userCode).toBe(d.user_code);
  });

  it("answers authorization_pending, then slow_down when polled too fast", async () => {
    const dev = await pair();
    const { client_id } = await deviceClient();
    const d = await j(await startDevice(dev.deviceId, client_id));
    const fast = await poll(client_id, d.device_code);
    expect(fast.status).toBe(400);
    expect((await j(fast)).error).toBe("slow_down");
    await rewindPoll(dev.deviceId, 20);
    expect((await j(await poll(client_id, d.device_code))).error).toBe("authorization_pending");
    // The interval grew by 5 seconds after slow_down, and the pending poll above did not shrink it.
    await rewindPoll(dev.deviceId, 6);
    expect((await j(await poll(client_id, d.device_code))).error).toBe("slow_down");
  });

  it("approved on the Mac: tokens, an oauth key named after the client, usable on /mcp, revocable", async () => {
    const dev = await pair();
    const ws = await connect(dev.token);
    const { client_id } = await deviceClient("Cloud agent");
    const d = await j(await startDevice(dev.deviceId, client_id));
    const c = await ws.next("consent");
    const ok = await f("/v1/device/consent", { method: "POST", headers: auth(dev.token), body: JSON.stringify({ id: c.id, decision: "approve" }) });
    expect(ok.status).toBe(200);
    expect((await j(ok)).status).toBe("approved");
    expect((await ws.next("consent_resolved")).status).toBe("approved");
    await rewindPoll(dev.deviceId);
    const t = await poll(client_id, d.device_code);
    expect(t.status).toBe(200);
    const tokens = await j(t);
    expect(tokens.token_type).toBe("Bearer");
    expect(tokens.access_token).toMatch(/^hra_/);
    expect(tokens.refresh_token).toMatch(/^hrr_/);
    expect(tokens.scope).toBe("notify");

    const keys = (await j(await f("/v1/device/keys", { headers: auth(dev.token) }))).keys;
    const key = keys.find((k: any) => k.kind === "oauth");
    expect(key.client_name ?? key.clientName ?? key.displayName).toBe("Cloud agent");

    const call = await j(await rpc(tokens.access_token, { jsonrpc: "2.0", id: 1, method: "tools/call", params: { name: "send_notification", arguments: { title: "via device flow", notificationId: "dev-1" } } }));
    expect(call.result.isError).toBeUndefined();
    expect((await ws.next("notify")).payload.title).toBe("via device flow");

    // a second redemption is refused, and it takes what the first produced with it
    await rewindPoll(dev.deviceId);
    const again = await poll(client_id, d.device_code);
    expect((await j(again)).error).toBe("invalid_grant");
    const dead = await rpc(tokens.access_token, { jsonrpc: "2.0", id: 2, method: "tools/list" });
    expect(dead.status).toBe(401);
  });

  it("a refresh token from the device flow works, and revoking the key kills the tokens", async () => {
    const dev = await pair();
    const ws = await connect(dev.token);
    const { client_id } = await deviceClient();
    const d = await j(await startDevice(dev.deviceId, client_id));
    const c = await ws.next("consent");
    await f("/v1/device/consent", { method: "POST", headers: auth(dev.token), body: JSON.stringify({ id: c.id, decision: "approve" }) });
    await rewindPoll(dev.deviceId);
    const tokens = await j(await poll(client_id, d.device_code));
    const rf = await f("/token", form({ grant_type: "refresh_token", client_id, refresh_token: tokens.refresh_token }));
    expect(rf.status).toBe(200);
    const next = await j(rf);
    const keys = (await j(await f("/v1/device/keys", { headers: auth(dev.token) }))).keys;
    const key = keys.find((k: any) => k.kind === "oauth");
    expect((await f("/v1/device/keys/" + key.id, { method: "DELETE", headers: auth(dev.token) })).status).toBe(200);
    expect((await rpc(next.access_token, { jsonrpc: "2.0", id: 1, method: "tools/list" })).status).toBe(401);
  });

  it("denied on the Mac gives access_denied", async () => {
    const dev = await pair();
    const ws = await connect(dev.token);
    const { client_id } = await deviceClient();
    const d = await j(await startDevice(dev.deviceId, client_id));
    const c = await ws.next("consent");
    await f("/v1/device/consent", { method: "POST", headers: auth(dev.token), body: JSON.stringify({ id: c.id, decision: "deny" }) });
    await rewindPoll(dev.deviceId);
    const r = await poll(client_id, d.device_code);
    expect(r.status).toBe(400);
    expect((await j(r)).error).toBe("access_denied");
  });

  it("expires after 600 seconds: expired_token", async () => {
    const dev = await pair();
    const { client_id } = await deviceClient();
    const d = await j(await startDevice(dev.deviceId, client_id));
    const stub = env.MAILBOX.get(env.MAILBOX.idFromName(dev.deviceId));
    await runInDurableObject(stub, (_i, state) => { state.storage.sql.exec("UPDATE oauth_requests SET expires_at = ?, last_poll = 0 WHERE flow = 'device'", Date.now() - 1000); });
    expect((await j(await poll(client_id, d.device_code))).error).toBe("expired_token");
  });

  it("refuses a device_code for another client, a malformed one, and an unknown one", async () => {
    const dev = await pair();
    const a = await deviceClient("A");
    const b = await deviceClient("B");
    const d = await j(await startDevice(dev.deviceId, a.client_id));
    await rewindPoll(dev.deviceId);
    expect((await j(await poll(b.client_id, d.device_code))).error).toBe("invalid_grant");
    expect((await j(await poll(a.client_id, "garbage"))).error).toBe("invalid_grant");
    const unknown = "hrv_" + dev.deviceId + "_" + "a".repeat(64);
    expect((await j(await poll(a.client_id, unknown))).error).toBe("expired_token");
  });

  it("needs a registered client and a paired Mac", async () => {
    const r = await f("/device_authorization", form({ client_id: "hc_" + "0".repeat(32) }));
    expect(r.status).toBe(401);
    expect((await j(r)).error).toBe("invalid_client");
    const bad = await f("/device_authorization", form({ client_id: (await deviceClient()).client_id, scope: "admin" }));
    expect((await j(bad)).error).toBe("invalid_scope");
  });

  it("/activate: the user code finds the request and the Mac's approval code approves it", async () => {
    const dev = await pair();
    const ws = await connect(dev.token);
    const { client_id } = await deviceClient("Web agent");
    const d = await j(await startDevice(dev.deviceId, client_id));
    const c = await ws.next("consent");
    const page = await f("/activate?user_code=" + encodeURIComponent(d.user_code));
    expect(page.status).toBe(200);
    expect(await page.text()).toContain(d.user_code);
    const wrong = await f("/activate", form({ user_code: "BBBB-BBBB" }));
    expect(await wrong.text()).toContain("wrong or expired");
    const step = await f("/activate", form({ user_code: d.user_code.toLowerCase() }));
    const html = await step.text();
    expect(html).toContain("Approve Web agent?");
    const rid = /name="rid" value="([0-9a-f]{72})"/.exec(html)![1];
    expect(rid).toBe(c.id);
    const bad = await f("/activate/approve", form({ rid, code: "000000" === c.code ? "111111" : "000000" }));
    expect(await bad.text()).toContain("tries left");
    const good = await f("/activate/approve", form({ rid, code: c.code }));
    expect(await good.text()).toContain("Approved");
    await rewindPoll(dev.deviceId);
    expect((await poll(client_id, d.device_code)).status).toBe(200);
  });

  it("/activate: Deny ends the request", async () => {
    const dev = await pair();
    const ws = await connect(dev.token);
    const { client_id } = await deviceClient();
    const d = await j(await startDevice(dev.deviceId, client_id));
    const c = await ws.next("consent");
    expect(await (await f("/activate/deny", form({ rid: c.id }))).text()).toContain("Denied");
    await rewindPoll(dev.deviceId);
    expect((await j(await poll(client_id, d.device_code))).error).toBe("access_denied");
  });
});

describe("the root page", () => {
  it("is a small page, not a 404", async () => {
    const r = await f("/");
    expect(r.status).toBe(200);
    expect(r.headers.get("content-type")).toContain("text/html");
    const html = await r.text();
    expect(html).toContain("Herald relay");
    expect(html).toContain("/.well-known/oauth-authorization-server");
    expect(html).toContain('href="/activate"');
    expect((await j(await f("/health"))).ok).toBe(true);
  });
});
