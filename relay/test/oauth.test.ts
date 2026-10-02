import { describe, expect, it } from "vitest";
import { env, runInDurableObject } from "cloudflare:test";
import { auth, connect, f, mintKey, notify, pair } from "./helpers";

const j = async (r: Response) => (await r.json()) as any;
const MCP = "https://relay.test/mcp";
const REDIRECT = "https://chatgpt.example/callback";
const form = (o: Record<string, string>) => ({ method: "POST", headers: { "content-type": "application/x-www-form-urlencoded" }, body: new URLSearchParams(o).toString() });

const b64url = (b: ArrayBuffer) => btoa(String.fromCharCode(...new Uint8Array(b))).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
async function pkce() {
  const verifier = b64url(crypto.getRandomValues(new Uint8Array(32)).buffer);
  return { verifier, challenge: b64url(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(verifier))) };
}

async function register(extra: Record<string, unknown> = {}) {
  const r = await f("/register", { method: "POST", body: JSON.stringify({ client_name: "ChatGPT", redirect_uris: [REDIRECT], ...extra }) });
  return { r, body: await j(r) };
}

/** The consent page picks a Mac by position when several are paired; tests share one registry. */
async function deviceIndex(deviceId: string): Promise<number> {
  const r = await env.REGISTRY.get(env.REGISTRY.idFromName("registry")).fetch("https://registry/devices", { method: "POST", body: "{}" });
  const { devices } = (await r.json()) as { devices: { id: string }[] };
  return devices.findIndex((d) => d.id === deviceId) + 1;
}

async function startAuth(deviceId: string, clientId: string, pk: { challenge: string }, over: Record<string, string | undefined> = {}) {
  const q = new URLSearchParams({
    response_type: "code", client_id: clientId, redirect_uri: REDIRECT, code_challenge: pk.challenge, code_challenge_method: "S256",
    state: "st-1", resource: MCP, device: String(await deviceIndex(deviceId)), ...over,
  });
  for (const [k, v] of [...q]) if (v === "" || v === undefined) q.delete(k);
  return f("/authorize?" + q);
}
const ridOf = async (page: Response) => /name="rid" value="([0-9a-f]{72})"/.exec(await page.text())![1];

/** Pair, register, open the consent page; returns everything a test needs. */
async function setup() {
  const dev = await pair();
  const { body: client } = await register();
  const pk = await pkce();
  return { ...dev, client, pk };
}

async function approveViaDevice(token: string, rid: string, decision = "approve") {
  return f("/v1/device/consent", { method: "POST", headers: auth(token), body: JSON.stringify({ id: rid, decision }) });
}

async function fullGrant() {
  const s = await setup();
  const page = await startAuth(s.deviceId, s.client.client_id, s.pk);
  expect(page.status).toBe(200);
  const rid = await ridOf(page);
  expect((await approveViaDevice(s.token, rid)).status).toBe(200);
  const st = await j(await f("/authorize/status?rid=" + rid));
  expect(st.status).toBe("approved");
  const code = new URL(st.redirect).searchParams.get("code")!;
  const tok = await f("/token", form({ grant_type: "authorization_code", client_id: s.client.client_id, code, redirect_uri: REDIRECT, code_verifier: s.pk.verifier, resource: MCP }));
  expect(tok.status).toBe(200);
  return { ...s, rid, code, tokens: await j(tok) };
}

describe("oauth discovery", () => {
  it("serves protected-resource metadata (RFC 9728)", async () => {
    for (const p of ["/.well-known/oauth-protected-resource", "/.well-known/oauth-protected-resource/mcp"]) {
      const r = await f(p);
      expect(r.status).toBe(200);
      expect(await j(r)).toEqual({ resource: MCP, authorization_servers: ["https://relay.test"], scopes_supported: ["notify"], bearer_methods_supported: ["header"], resource_name: "Herald relay" });
    }
  });
  it("serves authorization-server metadata (RFC 8414)", async () => {
    const m = await j(await f("/.well-known/oauth-authorization-server"));
    expect(m.issuer).toBe("https://relay.test");
    expect(m.authorization_endpoint).toBe("https://relay.test/authorize");
    expect(m.token_endpoint).toBe("https://relay.test/token");
    expect(m.registration_endpoint).toBe("https://relay.test/register");
    expect(m.revocation_endpoint).toBe("https://relay.test/revoke");
    expect(m.code_challenge_methods_supported).toEqual(["S256"]);
    expect(m.grant_types_supported).toEqual(["authorization_code", "refresh_token", "urn:ietf:params:oauth:grant-type:device_code"]);
    expect(m.device_authorization_endpoint).toBe("https://relay.test/device_authorization");
    expect(m.scopes_supported).toEqual(["notify"]);
  });
  it("answers /mcp without credentials with 401 and WWW-Authenticate", async () => {
    const r = await f("/mcp", { method: "POST", body: "{}" });
    expect(r.status).toBe(401);
    expect(r.headers.get("www-authenticate")).toBe('Bearer resource_metadata="https://relay.test/.well-known/oauth-protected-resource"');
    const bad = await f("/mcp", { method: "POST", headers: auth("hra_" + "a".repeat(48) + "_" + "b".repeat(64)), body: "{}" });
    expect(bad.status).toBe(401);
    expect(bad.headers.get("www-authenticate")).toContain('error="invalid_token"');
  });
  it("answers CORS preflight on the public endpoints", async () => {
    const r = await f("/token", { method: "OPTIONS" });
    expect(r.status).toBe(204);
    expect(r.headers.get("access-control-allow-origin")).toBe("*");
  });
});

describe("dynamic client registration", () => {
  it("registers a public client", async () => {
    const { r, body } = await register();
    expect(r.status).toBe(201);
    expect(body.client_id).toMatch(/^hc_[0-9a-f]{32}$/);
    expect(body.client_name).toBe("ChatGPT");
    expect(body.token_endpoint_auth_method).toBe("none");
    expect(body.client_secret).toBeUndefined();
  });
  it("issues a secret to a confidential client and then requires it", async () => {
    const { r, body } = await register({ token_endpoint_auth_method: "client_secret_post" });
    expect(r.status).toBe(201);
    expect(body.client_secret).toMatch(/^[0-9a-f]{64}$/);
    const noSecret = await f("/token", form({ grant_type: "refresh_token", client_id: body.client_id, refresh_token: "x" }));
    expect(noSecret.status).toBe(401);
    expect((await j(noSecret)).error).toBe("invalid_client");
    const wrong = await f("/token", form({ grant_type: "refresh_token", client_id: body.client_id, client_secret: "nope", refresh_token: "x" }));
    expect(wrong.status).toBe(401);
    // right secret gets past client auth (then fails on the garbage grant)
    const right = await f("/token", form({ grant_type: "refresh_token", client_id: body.client_id, client_secret: body.client_secret, refresh_token: "x" }));
    expect(right.status).toBe(400);
    expect((await j(right)).error).toBe("invalid_grant");
  });
  it("rejects bad redirect URIs and metadata", async () => {
    for (const uris of [[], ["javascript:alert(1)"], ["http://evil.example/cb"], ["https://x.example/cb#frag"], ["not a url"], "https://x.example"]) {
      const { r, body } = await register({ redirect_uris: uris });
      expect(r.status).toBe(400);
      expect(body.error).toBe("invalid_redirect_uri");
    }
    expect((await register({ token_endpoint_auth_method: "private_key_jwt" })).r.status).toBe(400);
    expect((await register({ grant_types: ["password"] })).r.status).toBe(400);
    expect((await register({ redirect_uris: ["http://127.0.0.1:8123/cb", "http://localhost/cb"] })).r.status).toBe(201);
  });
  it("is rate limited", async () => {
    const reg = env.REGISTRY.get(env.REGISTRY.idFromName("registry"));
    const limit = Number((env as unknown as Record<string, string>).REGISTER_PER_HOUR ?? "30");
    await runInDurableObject(reg, async (_i, state) => {
      for (let i = 0; i < limit; i++) state.storage.sql.exec("INSERT INTO events (kind, at) VALUES ('register', ?)", Date.now());
    });
    expect((await register()).r.status).toBe(429);
    await runInDurableObject(reg, async (_i, state) => { state.storage.sql.exec("DELETE FROM events WHERE kind = 'register'"); });
    expect((await register()).r.status).toBe(201);
  });
});

describe("authorize", () => {
  it("shows a consent page naming the client, the scope and both ways to approve", async () => {
    const s = await setup();
    const r = await startAuth(s.deviceId, s.client.client_id, s.pk);
    expect(r.status).toBe(200);
    expect(r.headers.get("content-security-policy")).toContain("default-src 'none'");
    const html = await r.text();
    expect(html).toContain("ChatGPT wants to connect to Herald");
    expect(html).toContain("send notifications to your Mac");
    expect(html).toContain("read receipts and your replies");
    expect(html).toContain("Approve in Herald");
    expect(html).toContain("6-digit code");
    expect(html).toContain("chatgpt.example");
  });
  it("escapes the client name", async () => {
    const dev = await pair();
    const { body: c } = await register({ client_name: "<img src=x onerror=alert(1)>Evil" });
    const r = await startAuth(dev.deviceId, c.client_id, await pkce());
    const html = await r.text();
    expect(html).not.toContain("<img");
  });
  it("never redirects for an unknown client or a redirect_uri that does not match exactly", async () => {
    const s = await setup();
    const a = await startAuth(s.deviceId, "hc_" + "0".repeat(32), s.pk);
    expect(a.status).toBe(400);
    const b = await startAuth(s.deviceId, s.client.client_id, s.pk, { redirect_uri: REDIRECT + "/" });
    expect(b.status).toBe(400);
    expect(b.headers.get("location")).toBeNull();
  });
  it("requires PKCE S256", async () => {
    const s = await setup();
    for (const over of [{ code_challenge: "" }, { code_challenge_method: "plain" }, { code_challenge_method: "" }, { code_challenge: "short" }]) {
      const r = await startAuth(s.deviceId, s.client.client_id, s.pk, over);
      expect(r.status).toBe(302);
      const u = new URL(r.headers.get("location")!);
      expect(u.searchParams.get("error")).toBe("invalid_request");
      expect(u.searchParams.get("state")).toBe("st-1");
    }
  });
  it("rejects a resource that is not the /mcp URL (RFC 8707)", async () => {
    const s = await setup();
    const r = await startAuth(s.deviceId, s.client.client_id, s.pk, { resource: "https://evil.example/mcp" });
    expect(r.status).toBe(302);
    expect(new URL(r.headers.get("location")!).searchParams.get("error")).toBe("invalid_target");
  });
  it("rejects an unknown scope and a non-code response_type", async () => {
    const s = await setup();
    const a = await startAuth(s.deviceId, s.client.client_id, s.pk, { scope: "admin" });
    expect(new URL(a.headers.get("location")!).searchParams.get("error")).toBe("invalid_scope");
    const b = await startAuth(s.deviceId, s.client.client_id, s.pk, { response_type: "token" });
    expect(new URL(b.headers.get("location")!).searchParams.get("error")).toBe("unsupported_response_type");
  });
});

describe("consent", () => {
  it("pushes a consent item down the device socket and approves via the device route", async () => {
    const s = await setup();
    const dev = await connect(s.token);
    await dev.next("welcome");
    const page = await startAuth(s.deviceId, s.client.client_id, s.pk);
    const rid = await ridOf(page);
    const c = await dev.next("consent");
    expect(c).toMatchObject({ id: rid, clientName: "ChatGPT", scope: "notify", redirectHost: "chatgpt.example", status: "pending" });
    expect(c.code).toMatch(/^[0-9]{6}$/);
    expect((await j(await f("/authorize/status?rid=" + rid))).status).toBe("pending");
    expect((await approveViaDevice(s.token, rid)).status).toBe(200);
    expect((await dev.next("consent_resolved")).status).toBe("approved");
    const st = await j(await f("/authorize/status?rid=" + rid));
    const u = new URL(st.redirect);
    expect(u.origin + u.pathname).toBe(REDIRECT);
    expect(u.searchParams.get("state")).toBe("st-1");
    expect(u.searchParams.get("code")).toMatch(/^hrc_/);
    // a second decision is refused
    expect((await approveViaDevice(s.token, rid, "deny")).status).toBe(409);
    dev.ws.close();
  });
  it("lists pending consents for the device", async () => {
    const s = await setup();
    const rid = await ridOf(await startAuth(s.deviceId, s.client.client_id, s.pk));
    const r = await j(await f("/v1/device/consents", { headers: auth(s.token) }));
    expect(r.consents[0]).toMatchObject({ id: rid, clientName: "ChatGPT", status: "pending" });
    expect(r.consents[0].code).toMatch(/^[0-9]{6}$/);
  });
  it("sends pending consents when Herald connects later", async () => {
    const s = await setup();
    const rid = await ridOf(await startAuth(s.deviceId, s.client.client_id, s.pk));
    const dev = await connect(s.token);
    expect((await dev.next("consent")).id).toBe(rid);
    dev.ws.close();
  });
  it("deny returns access_denied to the redirect", async () => {
    const s = await setup();
    const rid = await ridOf(await startAuth(s.deviceId, s.client.client_id, s.pk));
    expect((await approveViaDevice(s.token, rid, "deny")).status).toBe(200);
    const st = await j(await f("/authorize/status?rid=" + rid));
    expect(st.status).toBe("denied");
    const u = new URL(st.redirect);
    expect(u.searchParams.get("error")).toBe("access_denied");
    expect(u.searchParams.get("state")).toBe("st-1");
    expect(u.searchParams.get("code")).toBeNull();
  });
  it("deny from the page works too", async () => {
    const s = await setup();
    const rid = await ridOf(await startAuth(s.deviceId, s.client.client_id, s.pk));
    const r = await f("/authorize/deny", form({ rid }));
    expect(r.status).toBe(302);
    expect(new URL(r.headers.get("location")!).searchParams.get("error")).toBe("access_denied");
  });
  it("approves with the 6-digit code and locks after wrong guesses", async () => {
    const s = await setup();
    const rid = await ridOf(await startAuth(s.deviceId, s.client.client_id, s.pk));
    const code = (await j(await f("/v1/device/consents", { headers: auth(s.token) }))).consents[0].code as string;
    const wrong = code === "000000" ? "111111" : "000000";
    const w = await f("/authorize/code", form({ rid, code: wrong }));
    expect(w.status).toBe(200);
    expect(await w.text()).toContain("That code is wrong");
    const ok = await f("/authorize/code", form({ rid, code: code.slice(0, 3) + " " + code.slice(3) }));
    expect(ok.status).toBe(302);
    expect(new URL(ok.headers.get("location")!).searchParams.get("code")).toMatch(/^hrc_/);

    const rid2 = await ridOf(await startAuth(s.deviceId, s.client.client_id, s.pk));
    const code2 = (await j(await f("/v1/device/consents", { headers: auth(s.token) }))).consents.find((c: any) => c.id === rid2).code as string;
    const bad = code2 === "000000" ? "111111" : "000000";
    let last: Response | undefined;
    for (let i = 0; i < 5; i++) last = await f("/authorize/code", form({ rid: rid2, code: bad }));
    expect(last!.status).toBe(302); // the fifth wrong guess denies
    expect(new URL(last!.headers.get("location")!).searchParams.get("error")).toBe("access_denied");
    expect((await f("/authorize/code", form({ rid: rid2, code: code2 }))).status).toBe(302);
    expect((await j(await f("/authorize/status?rid=" + rid2))).status).toBe("denied");
  });
  it("needs the device token to decide", async () => {
    const s = await setup();
    const rid = await ridOf(await startAuth(s.deviceId, s.client.client_id, s.pk));
    expect((await f("/v1/device/consent", { method: "POST", body: JSON.stringify({ id: rid, decision: "approve" }) })).status).toBe(401);
    const { key } = await mintKey(s.token);
    expect((await f("/v1/device/consent", { method: "POST", headers: auth(key), body: JSON.stringify({ id: rid, decision: "approve" }) })).status).toBe(403);
  });
  it("limits approvals waiting at once", async () => {
    const s = await setup();
    for (let i = 0; i < 3; i++) expect((await startAuth(s.deviceId, s.client.client_id, s.pk)).status).toBe(200);
    expect((await startAuth(s.deviceId, s.client.client_id, s.pk)).status).toBe(429);
  });
  it("ignores a status or code request for a forged request id", async () => {
    const forged = "a".repeat(72);
    expect((await j(await f("/authorize/status?rid=" + forged))).status).toBe("unknown");
    expect((await f("/authorize/code", form({ rid: forged, code: "123456" }))).status).toBe(400);
  });
});

describe("token endpoint", () => {
  it("exchanges the code (with PKCE) for tokens bound to a new oauth key", async () => {
    const g = await fullGrant();
    expect(g.tokens).toMatchObject({ token_type: "Bearer", expires_in: 3600, scope: "notify" });
    expect(g.tokens.access_token).toMatch(/^hra_[0-9a-f]{48}_[0-9a-f]{64}$/);
    expect(g.tokens.refresh_token).toMatch(/^hrr_/);
    const keys = (await j(await f("/v1/device/keys", { headers: auth(g.token) }))).keys as any[];
    expect(keys).toHaveLength(1);
    expect(keys[0]).toMatchObject({ name: "chatgpt", kind: "oauth", displayName: "ChatGPT", client: "other", scope: "notify" });
    // stored hashed: the plaintext token is nowhere in the mailbox tables
    const stub = env.MAILBOX.get(env.MAILBOX.idFromName(g.deviceId));
    const dump = await (await import("cloudflare:test")).runInDurableObject(stub, async (_i, state) =>
      JSON.stringify(state.storage.sql.exec("SELECT * FROM oauth_tokens").toArray()) + JSON.stringify(state.storage.sql.exec("SELECT * FROM oauth_requests").toArray()));
    expect(dump).not.toContain(g.tokens.access_token.split("_")[2]);
    expect(dump).not.toContain(g.tokens.refresh_token.split("_")[2]);
    expect(dump).not.toContain(g.code.split("_")[2]);
  });
  it("fails PKCE with the wrong verifier, a missing verifier or a different redirect_uri", async () => {
    const s = await setup();
    const mk = async () => {
      const rid = await ridOf(await startAuth(s.deviceId, s.client.client_id, s.pk));
      await approveViaDevice(s.token, rid);
      return new URL((await j(await f("/authorize/status?rid=" + rid))).redirect).searchParams.get("code")!;
    };
    const base = (code: string) => ({ grant_type: "authorization_code", client_id: s.client.client_id, code, redirect_uri: REDIRECT, code_verifier: s.pk.verifier });
    const wrong = await f("/token", form({ ...base(await mk()), code_verifier: (await pkce()).verifier }));
    expect(wrong.status).toBe(400);
    expect((await j(wrong)).error).toBe("invalid_grant");
    const { code_verifier: _v, ...noVerifier } = base(await mk());
    expect((await j(await f("/token", form(noVerifier)))).error).toBe("invalid_grant");
    expect((await j(await f("/token", form({ ...base(await mk()), redirect_uri: REDIRECT + "x" })))).error).toBe("invalid_grant");
    const other = (await register()).body;
    expect((await j(await f("/token", form({ ...base(await mk()), client_id: other.client_id })))).error).toBe("invalid_grant");
  });
  it("rejects a resource that differs from the authorization request", async () => {
    const s = await setup();
    const rid = await ridOf(await startAuth(s.deviceId, s.client.client_id, s.pk));
    await approveViaDevice(s.token, rid);
    const code = new URL((await j(await f("/authorize/status?rid=" + rid))).redirect).searchParams.get("code")!;
    const r = await f("/token", form({ grant_type: "authorization_code", client_id: s.client.client_id, code, redirect_uri: REDIRECT, code_verifier: s.pk.verifier, resource: "https://evil.example/mcp" }));
    expect(r.status).toBe(400);
    expect((await j(r)).error).toBe("invalid_target");
  });
  it("accepts a code once; replaying it revokes what it produced", async () => {
    const g = await fullGrant();
    const again = await f("/token", form({ grant_type: "authorization_code", client_id: g.client.client_id, code: g.code, redirect_uri: REDIRECT, code_verifier: g.pk.verifier }));
    expect(again.status).toBe(400);
    expect((await f("/v1/status", { headers: auth(g.tokens.access_token) })).status).toBe(401);
  });
  it("rejects an expired or unapproved code and unknown grant types", async () => {
    const s = await setup();
    expect((await j(await f("/token", form({ grant_type: "password", client_id: s.client.client_id })))).error).toBe("unsupported_grant_type");
    const forged = "hrc_" + s.deviceId + "_" + "a".repeat(64);
    expect((await j(await f("/token", form({ grant_type: "authorization_code", client_id: s.client.client_id, code: forged, redirect_uri: REDIRECT, code_verifier: s.pk.verifier })))).error).toBe("invalid_grant");
  });
  it("rotates refresh tokens and burns the family when one is replayed", async () => {
    const g = await fullGrant();
    const refresh = (rt: string) => f("/token", form({ grant_type: "refresh_token", client_id: g.client.client_id, refresh_token: rt, resource: MCP }));
    const r1 = await refresh(g.tokens.refresh_token);
    expect(r1.status).toBe(200);
    const t1 = await j(r1);
    expect(t1.refresh_token).not.toBe(g.tokens.refresh_token);
    expect(t1.access_token).not.toBe(g.tokens.access_token);
    expect((await f("/v1/status", { headers: auth(t1.access_token) })).status).toBe(200);
    const replay = await refresh(g.tokens.refresh_token);
    expect(replay.status).toBe(400);
    expect((await j(replay)).error).toBe("invalid_grant");
    // the replay burned the family: the newest refresh token and access token are dead too
    expect((await refresh(t1.refresh_token)).status).toBe(400);
    expect((await f("/v1/status", { headers: auth(t1.access_token) })).status).toBe(401);
  });
  it("binds the refresh grant to its resource and client", async () => {
    const g = await fullGrant();
    const bad = await f("/token", form({ grant_type: "refresh_token", client_id: g.client.client_id, refresh_token: g.tokens.refresh_token, resource: "https://evil.example/mcp" }));
    expect((await j(bad)).error).toBe("invalid_target");
    const other = (await register()).body;
    const stolen = await f("/token", form({ grant_type: "refresh_token", client_id: other.client_id, refresh_token: g.tokens.refresh_token }));
    expect((await j(stolen)).error).toBe("invalid_grant");
  });
  it("expires access tokens after an hour", async () => {
    const g = await fullGrant();
    const stub = env.MAILBOX.get(env.MAILBOX.idFromName(g.deviceId));
    await (await import("cloudflare:test")).runInDurableObject(stub, async (_i, state) => {
      state.storage.sql.exec("UPDATE oauth_tokens SET expires_at = ? WHERE kind = 'access'", Date.now() - 1000);
    });
    const r = await f("/mcp", { method: "POST", headers: auth(g.tokens.access_token), body: JSON.stringify({ jsonrpc: "2.0", id: 1, method: "ping" }) });
    expect(r.status).toBe(401);
    expect(r.headers.get("www-authenticate")).toContain("invalid_token");
  });
});

describe("using the access token", () => {
  it("works on /mcp and /v1/notify like a static key, and the static key still works", async () => {
    const g = await fullGrant();
    const dev = await connect(g.token);
    await dev.next("welcome");
    const rpc = (t: string, body: unknown) => f("/mcp", { method: "POST", headers: auth(t), body: JSON.stringify(body) });
    const tools = await j(await rpc(g.tokens.access_token, { jsonrpc: "2.0", id: 1, method: "tools/list" }));
    expect(tools.result.tools.map((t: any) => t.name)).toContain("send_notification");
    const call = await j(await rpc(g.tokens.access_token, { jsonrpc: "2.0", id: 2, method: "tools/call", params: { name: "send_notification", arguments: { title: "via oauth", notificationId: "oa-1" } } }));
    expect(call.result.isError).toBeUndefined();
    const m = await dev.next("notify");
    expect(m.payload.title).toBe("via oauth");
    expect(m.key.name).toBe("chatgpt");
    expect((await notify(g.tokens.access_token, { title: "direct" })).status).toBe(202);
    const { key } = await mintKey(g.token, "static-one");
    expect((await notify(key, { title: "static" })).status).toBe(202);
    expect((await rpc(key, { jsonrpc: "2.0", id: 3, method: "ping" })).status).toBe(200);
    dev.ws.close();
  });
  it("is notify-only: no device routes", async () => {
    const g = await fullGrant();
    const r = await f("/v1/device/keys", { headers: auth(g.tokens.access_token) });
    expect(r.status).toBe(403);
    expect((await f("/v1/device/consents", { headers: auth(g.tokens.access_token) })).status).toBe(403);
  });
  it("revoking the key in Herald kills its tokens", async () => {
    const g = await fullGrant();
    expect((await f("/v1/status", { headers: auth(g.tokens.access_token) })).status).toBe(200);
    const keys = (await j(await f("/v1/device/keys", { headers: auth(g.token) }))).keys as any[];
    expect((await f(`/v1/device/keys/${keys[0].id}`, { method: "DELETE", headers: auth(g.token) })).status).toBe(200);
    expect((await f("/v1/status", { headers: auth(g.tokens.access_token) })).status).toBe(401);
    const refresh = await f("/token", form({ grant_type: "refresh_token", client_id: g.client.client_id, refresh_token: g.tokens.refresh_token }));
    expect(refresh.status).toBe(400);
  });
  it("re-authorizing the same client replaces its earlier key", async () => {
    const g = await fullGrant();
    const rid = await ridOf(await startAuth(g.deviceId, g.client.client_id, g.pk));
    await approveViaDevice(g.token, rid);
    const keys = (await j(await f("/v1/device/keys", { headers: auth(g.token) }))).keys as any[];
    expect(keys.filter((k) => !k.revokedAt)).toHaveLength(1);
    expect((await f("/v1/status", { headers: auth(g.tokens.access_token) })).status).toBe(401);
  });
  it("an oauth key's hash can never be used as a static key", async () => {
    const g = await fullGrant();
    const keys = (await j(await f("/v1/device/keys", { headers: auth(g.token) }))).keys as any[];
    const forged = `hrk_${g.deviceId}_${keys[0].id}_${"0".repeat(64)}`;
    expect((await f("/v1/status", { headers: auth(forged) })).status).toBe(401);
  });
});

describe("revoke (RFC 7009)", () => {
  it("revokes an access token, and a refresh token takes its family", async () => {
    const g = await fullGrant();
    const rev = (token: string) => f("/revoke", form({ client_id: g.client.client_id, token }));
    expect((await rev(g.tokens.access_token)).status).toBe(200);
    expect((await f("/v1/status", { headers: auth(g.tokens.access_token) })).status).toBe(401);
    const t = await j(await f("/token", form({ grant_type: "refresh_token", client_id: g.client.client_id, refresh_token: g.tokens.refresh_token })));
    expect((await f("/v1/status", { headers: auth(t.access_token) })).status).toBe(200);
    expect((await rev(t.refresh_token)).status).toBe(200);
    expect((await f("/v1/status", { headers: auth(t.access_token) })).status).toBe(401);
  });
  it("answers 200 for unknown tokens and ignores another client's token", async () => {
    const g = await fullGrant();
    expect((await f("/revoke", form({ client_id: g.client.client_id, token: "garbage" }))).status).toBe(200);
    const other = (await register()).body;
    expect((await f("/revoke", form({ client_id: other.client_id, token: g.tokens.access_token }))).status).toBe(200);
    expect((await f("/v1/status", { headers: auth(g.tokens.access_token) })).status).toBe(200);
  });
});

// Last: it removes every device from the shared registry.
describe("unpaired relay", () => {
  it("says to pair Herald first when no Mac is paired", async () => {
    const reg = env.REGISTRY.get(env.REGISTRY.idFromName("registry"));
    const { body: c } = await register();
    // remove every device from the registry for this one request
    const list = (await (await reg.fetch("https://registry/devices", { method: "POST", body: "{}" })).json()) as { devices: { id: string }[] };
    for (const d of list.devices) await reg.fetch("https://registry/internal/remove", { method: "POST", body: JSON.stringify({ deviceId: d.id }) });
    const r = await f("/authorize?" + new URLSearchParams({ response_type: "code", client_id: c.client_id, redirect_uri: REDIRECT, code_challenge: (await pkce()).challenge, code_challenge_method: "S256" }));
    expect(await r.text()).toContain("Pair Herald first");
  });
});
