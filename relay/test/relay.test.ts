import { describe, expect, it } from "vitest";
import { env, runInDurableObject } from "cloudflare:test";
import toml from "../wrangler.toml?raw";
import lifecycle from "../r2-lifecycle.json?raw";
import r2setup from "../r2-setup.sh?raw";
import { auth, connect, f, mintKey, notify, pair } from "./helpers";

const j = async (r: Response) => (await r.json()) as any;

describe("pairing", () => {
  it("pairs once with a one-time code", async () => {
    const s = await f("/v1/pair/start", { method: "POST", body: "{}" });
    expect(s.status).toBe(201);
    const { code } = await j(s);
    expect(code).toMatch(/^[A-Z2-9]{4}-[A-Z2-9]{4}$/);
    const p = await f("/v1/pair", { method: "POST", body: JSON.stringify({ code }) });
    expect(p.status).toBe(200);
    const body = await j(p);
    expect(body.deviceToken).toMatch(/^hrd_[0-9a-f]{48}_[0-9a-f]{64}$/);
    const again = await f("/v1/pair", { method: "POST", body: JSON.stringify({ code }) });
    expect(again.status).toBe(403);
  });
  it("rejects a wrong code", async () => {
    expect((await f("/v1/pair", { method: "POST", body: JSON.stringify({ code: "AAAA-BBBB" }) })).status).toBe(403);
  });
});

describe("auth", () => {
  it("rejects missing, malformed and forged credentials", async () => {
    expect((await f("/v1/notify", { method: "POST", body: "{}" })).status).toBe(401);
    expect((await f("/v1/notify", { method: "POST", headers: auth("nope"), body: "{}" })).status).toBe(401);
    const forged = `hrk_${"a".repeat(48)}_${"b".repeat(8)}_${"c".repeat(64)}`;
    expect((await f("/v1/notify", { method: "POST", headers: auth(forged), body: "{}" })).status).toBe(401);
    const { deviceId } = await pair();
    const forged2 = `hrk_${deviceId}_${"b".repeat(8)}_${"c".repeat(64)}`;
    expect((await f("/v1/notify", { method: "POST", headers: auth(forged2), body: "{}" })).status).toBe(401);
  });
  it("keeps agent keys off device endpoints and the device token off agent endpoints", async () => {
    const { token } = await pair();
    const { key } = await mintKey(token);
    for (const [m, p] of [["GET", "/v1/device/keys"], ["POST", "/v1/device/keys"], ["DELETE", "/v1/device"], ["POST", "/v1/device/receipt"], ["GET", "/v1/device/stream"], ["GET", "/v1/device/usage"]]) {
      expect((await f(p, { method: m, headers: auth(key), body: m === "POST" ? "{}" : undefined })).status).toBe(403);
    }
    expect((await f("/v1/notify", { method: "POST", headers: auth(token), body: JSON.stringify({ title: "x" }) })).status).toBe(403);
  });
  it("a key reaches only its own device", async () => {
    const a = await pair(), b = await pair();
    const ka = await mintKey(a.token, "alpha");
    const r = await notify(ka.key, { title: "hi", notificationId: "same" });
    expect(r.status).toBe(202);
    // the other device's mailbox does not know key A
    const swapped = ka.key.replace(a.deviceId, b.deviceId);
    expect((await f("/v1/receipts/same", { headers: auth(swapped) })).status).toBe(401);
    const kb = await mintKey(b.token, "alpha");
    expect((await f("/v1/receipts/same", { headers: auth(kb.key) })).status).toBe(404);
  });
  it("revoked keys stop working immediately", async () => {
    const { token } = await pair();
    const k = await mintKey(token);
    expect((await notify(k.key, { title: "ok" })).status).toBe(202);
    expect((await f(`/v1/device/keys/${k.id}`, { method: "DELETE", headers: auth(token) })).status).toBe(200);
    expect((await notify(k.key, { title: "no" })).status).toBe(401);
  });
  it("stores keys hashed: listing never shows a secret", async () => {
    const { token } = await pair();
    const k = await mintKey(token, "one");
    const list = await j(await f("/v1/device/keys", { headers: auth(token) }));
    expect(JSON.stringify(list)).not.toContain(k.key.split("_")[3]);
    expect(list.keys[0]).toMatchObject({ name: "one", scope: "notify" });
  });
});

describe("scope and validation", () => {
  it("only mints notify-scoped keys", async () => {
    const { token } = await pair();
    for (const scope of ["admin", "device", "*", "notify,admin"]) {
      const r = await f("/v1/device/keys", { method: "POST", headers: auth(token), body: JSON.stringify({ name: "x", scope }) });
      expect(r.status).toBe(400);
    }
  });
  it("rejects command/callback/script/shortcut fields and lists them", async () => {
    const { token } = await pair();
    const { key } = await mintKey(token);
    const r = await notify(key, { title: "t", command: "rm -rf /", callback: { url: "https://x" }, script: "a", shortcut: "b", buttons: [], actions: [], foo: 1 });
    expect(r.status).toBe(400);
    const b = await j(r);
    expect(b.error).toBe("forbidden_fields");
    expect(b.fields.sort()).toEqual(["actions", "buttons", "callback", "command", "foo", "script", "shortcut"]);
  });
  it("rejects non-https links and bad speak options", async () => {
    const { token } = await pair();
    const { key } = await mintKey(token);
    expect((await notify(key, { title: "t", link: "file:///etc/passwd" })).status).toBe(400);
    expect((await notify(key, { title: "t", link: "javascript:alert(1)" })).status).toBe(400);
    expect((await notify(key, { title: "t", speak: { text: "hi", command: "x" } })).status).toBe(400);
    expect((await notify(key, { title: "t", link: "https://example.com/a", speak: true, allowVoiceReply: false })).status).toBe(202);
    expect((await notify(key, { title: "t", allowVoiceReply: "no" })).status).toBe(400);
  });
  it("caps the body at 32 KB", async () => {
    const { token } = await pair();
    const { key } = await mintKey(token);
    const r = await notify(key, { title: "t", body: "x".repeat(40_000) });
    expect(r.status).toBe(413);
  });
  it("requires a title", async () => {
    const { token } = await pair();
    const { key } = await mintKey(token);
    expect((await notify(key, { body: "x" })).status).toBe(400);
  });
});

describe("rate limit", () => {
  it("allows 60 per 10 minutes per key, then 429 with Retry-After", async () => {
    const { token } = await pair();
    const k1 = await mintKey(token, "one"), k2 = await mintKey(token, "two");
    for (let i = 0; i < 60; i++) expect((await notify(k1.key, { title: "n" + i })).status).toBe(202);
    const r = await notify(k1.key, { title: "over" });
    expect(r.status).toBe(429);
    expect(Number(r.headers.get("retry-after"))).toBeGreaterThan(0);
    expect((await notify(k2.key, { title: "other key is fine" })).status).toBe(202);
  });
});

describe("dedupe, queue and receipts", () => {
  it("dedupes ids: the second send never reaches the Mac", async () => {
    const { token } = await pair();
    const { key } = await mintKey(token);
    const c = await connect(token);
    const a = await notify(key, { title: "once", notificationId: "build-1" });
    const b = await notify(key, { title: "once", notificationId: "build-1" });
    expect(a.status).toBe(202); expect((await j(a)).duplicate).toBe(false);
    expect(b.status).toBe(200); expect((await j(b)).duplicate).toBe(true);
    const first = await c.next();
    expect(first.notificationId).toBe("build-1");
    await new Promise((r) => setTimeout(r, 150));
    expect(c.msgs.filter((m) => m.type === "notify")).toHaveLength(0);
  });
  it("queues while the Mac is offline and delivers on connect, in order", async () => {
    const { token } = await pair();
    const { key } = await mintKey(token);
    const r = await j(await notify(key, { title: "first", notificationId: "q1" }));
    expect(r.received).toBe(true); expect(r.queued).toBe(true);
    await notify(key, { title: "second", notificationId: "q2" });
    expect((await j(await f("/v1/status", { headers: auth(key) }))).online).toBe(false);
    const c = await connect(token);
    expect((await c.next()).notificationId).toBe("q1");
    expect((await c.next()).notificationId).toBe("q2");
    expect((await j(await f("/v1/status", { headers: auth(key) }))).online).toBe(true);
  });
  it("gives separate receipts: received, displayed, spoken, suppressed", async () => {
    const { token } = await pair();
    const { key } = await mintKey(token);
    const c = await connect(token);
    await notify(key, { title: "a", notificationId: "A", speak: true });
    await notify(key, { title: "b", notificationId: "B" });
    const A = await c.next(), B = await c.next();
    let r = await j(await f("/v1/receipts/A", { headers: auth(key) }));
    expect(r).toMatchObject({ received: true, displayed: false, spoken: false, replied: false, suppressed: false });
    c.send({ type: "receipt", id: A.id, kind: "displayed" });
    await new Promise((x) => setTimeout(x, 100));
    r = await j(await f("/v1/receipts/A", { headers: auth(key) }));
    expect(r).toMatchObject({ received: true, displayed: true, spoken: false });
    const hr = await f("/v1/device/receipt", { method: "POST", headers: auth(token), body: JSON.stringify({ id: A.id, kind: "spoken" }) });
    expect(hr.status).toBe(200);
    r = await j(await f("/v1/receipts/A", { headers: auth(key) }));
    expect(r).toMatchObject({ displayed: true, spoken: true, queued: false });
    const sr = await f("/v1/device/receipt", { method: "POST", headers: auth(token), body: JSON.stringify({ id: B.id, kind: "suppressed", reason: "quiet-hours" }) });
    expect(sr.status).toBe(200);
    r = await j(await f("/v1/receipts/B", { headers: auth(key) }));
    expect(r).toMatchObject({ received: true, displayed: false, suppressed: true, reason: "quiet-hours" });
  });
  it("reports quiet hours through status, and nothing else about the Mac", async () => {
    const { token } = await pair();
    const { key } = await mintKey(token);
    const c = await connect(token);
    c.send({ type: "hello", quietActive: true, quietUntil: "2026-10-03T07:30:00Z", muted: true });
    await new Promise((x) => setTimeout(x, 100));
    const s = await j(await f("/v1/status", { headers: auth(key) }));
    expect(s).toMatchObject({ online: true, quietHours: { active: true, until: "2026-10-03T07:30:00Z" } });
    expect(Object.keys(s).sort()).toEqual(["lastSeenAt", "online", "quietHours"]);
  });
  it("unacked items are redelivered on reconnect", async () => {
    const { token } = await pair();
    const { key } = await mintKey(token);
    const c1 = await connect(token);
    await notify(key, { title: "x", notificationId: "r1" });
    await c1.next();
    const c2 = await connect(token);
    const m = await c2.next();
    expect(m.notificationId).toBe("r1");
    c2.send({ type: "ack", id: m.id });
    await new Promise((r) => setTimeout(r, 100));
    const c3 = await connect(token);
    await new Promise((r) => setTimeout(r, 150));
    expect(c3.msgs.filter((x) => x.type === "notify")).toHaveLength(0);
  });
});

describe("replies and long-poll", () => {
  it("returns an inline reply to a waiting long-poll", async () => {
    const { token } = await pair();
    const { key } = await mintKey(token);
    const c = await connect(token);
    await notify(key, { title: "Which branch?", notificationId: "ask", expectReply: true });
    const n = await c.next();
    const waiting = f("/v1/replies/ask?wait=10", { headers: auth(key) });
    setTimeout(() => c.send({ type: "receipt", id: n.id, kind: "replied", text: "release/1.7" }), 300);
    const r = await j(await waiting);
    expect(r).toMatchObject({ replied: true, reply: "release/1.7", text: "release/1.7" });
    const rec = await j(await f("/v1/receipts/ask", { headers: auth(key) }));
    expect(rec).toMatchObject({ replied: true, reply: "release/1.7" });
  });
  it("times out cleanly and is capped at 60 s", async () => {
    const { token } = await pair();
    const { key } = await mintKey(token);
    await notify(key, { title: "q", notificationId: "slow", expectReply: true });
    const t0 = Date.now();
    const r = await j(await f("/v1/replies/slow?wait=1", { headers: auth(key) }));
    expect(Date.now() - t0).toBeGreaterThanOrEqual(900);
    expect(r).toMatchObject({ replied: false, timedOut: true });
    expect((await f("/v1/replies/missing", { headers: auth(key) })).status).toBe(404);
  });
  it("wakes a long-poll when the notification is suppressed", async () => {
    const { token } = await pair();
    const { key } = await mintKey(token);
    const c = await connect(token);
    await notify(key, { title: "q", notificationId: "sup", expectReply: true });
    const n = await c.next();
    setTimeout(() => c.send({ type: "receipt", id: n.id, kind: "suppressed", reason: "muted" }), 200);
    const r = await j(await f("/v1/replies/sup?wait=10", { headers: auth(key) }));
    expect(r).toMatchObject({ replied: false, suppressed: true, reason: "muted" });
  });
  it("returns voice replies with transcript and a signed audio URL", async () => {
    const { token } = await pair();
    const { key } = await mintKey(token);
    const c = await connect(token);
    await notify(key, { title: "q", notificationId: "voice", expectReply: true });
    const n = await c.next();
    const audio = new Uint8Array(5000).fill(7);
    const up = await f(`/v1/device/reply/${n.id}/audio`, { method: "PUT", headers: { authorization: "Bearer " + token, "content-type": "audio/mp4" }, body: audio });
    expect(up.status).toBe(200);
    const rep = await f("/v1/device/reply", { method: "POST", headers: auth(token), body: JSON.stringify({ id: n.id, transcript: "ship it", durationSeconds: 3.2 }) });
    expect(rep.status).toBe(200);
    const r = await j(await f("/v1/replies/voice?wait=2", { headers: auth(key) }));
    expect(r).toMatchObject({ replied: true, transcript: "ship it", durationSeconds: 3.2, reply: "ship it" });
    expect(r.text).toBeUndefined();
    expect(r.audioUrl).toMatch(/\/v1\/audio\/[0-9a-f]{48}\/r_[0-9a-f]{24}\.m4a\?exp=\d+&sig=[0-9a-f]{64}$/);
    const dl = await f(new URL(r.audioUrl).pathname + new URL(r.audioUrl).search);
    expect(dl.status).toBe(200);
    expect((await dl.arrayBuffer()).byteLength).toBe(5000);
    const bad = await f(new URL(r.audioUrl).pathname + "?exp=9999999999&sig=" + "0".repeat(64));
    expect(bad.status).toBe(403);
    const expired = await f(new URL(r.audioUrl).pathname + "?exp=1&sig=" + "0".repeat(64));
    expect(expired.status).toBe(410);
  });
  it("limits audio to 1 MB of m4a", async () => {
    const { token } = await pair();
    const { key } = await mintKey(token);
    const c = await connect(token);
    await notify(key, { title: "q", notificationId: "big" });
    const n = await c.next();
    const h = (type: string) => ({ authorization: "Bearer " + token, "content-type": type });
    expect((await f(`/v1/device/reply/${n.id}/audio`, { method: "PUT", headers: h("audio/mp4"), body: new Uint8Array(1024 * 1024 + 1) })).status).toBe(413);
    expect((await f(`/v1/device/reply/${n.id}/audio`, { method: "PUT", headers: h("text/html"), body: new Uint8Array(10) })).status).toBe(415);
    expect((await f(`/v1/device/reply/${n.id}/audio`, { method: "PUT", headers: h("audio/mp4"), body: new Uint8Array(1024 * 1024) })).status).toBe(200);
  });
});

describe("remote MCP", () => {
  const rpc = (key: string, body: unknown) => f("/mcp", { method: "POST", headers: { ...auth(key), accept: "application/json, text/event-stream" }, body: JSON.stringify(body) });
  it("requires the agent key", async () => {
    expect((await f("/mcp", { method: "POST", body: "{}" })).status).toBe(401);
    const { token } = await pair();
    expect((await rpc(token, { jsonrpc: "2.0", id: 1, method: "tools/list" })).status).toBe(403);
  });
  it("initializes and lists exactly four tools", async () => {
    const { token } = await pair();
    const { key } = await mintKey(token);
    const init = await j(await rpc(key, { jsonrpc: "2.0", id: 1, method: "initialize", params: { protocolVersion: "2025-06-18", capabilities: {}, clientInfo: { name: "t", version: "1" } } }));
    expect(init.result.protocolVersion).toBe("2025-06-18");
    expect((await rpc(key, { jsonrpc: "2.0", method: "notifications/initialized" })).status).toBe(202);
    const list = await j(await rpc(key, { jsonrpc: "2.0", id: 2, method: "tools/list" }));
    expect(list.result.tools.map((t: any) => t.name).sort()).toEqual(["get_receipt", "herald_status", "send_notification", "wait_for_reply"]);
    expect((await f("/mcp", { method: "GET", headers: auth(key) })).status).toBe(405);
  });
  it("sends, reads receipts, and refuses forbidden fields through the tool", async () => {
    const { token } = await pair();
    const { key } = await mintKey(token);
    const sent = await j(await rpc(key, { jsonrpc: "2.0", id: 3, method: "tools/call", params: { name: "send_notification", arguments: { title: "hello", notificationId: "m1" } } }));
    expect(sent.result.structuredContent).toMatchObject({ notificationId: "m1", received: true });
    const rec = await j(await rpc(key, { jsonrpc: "2.0", id: 4, method: "tools/call", params: { name: "get_receipt", arguments: { notificationId: "m1" } } }));
    expect(rec.result.structuredContent.received).toBe(true);
    const evil = await j(await rpc(key, { jsonrpc: "2.0", id: 5, method: "tools/call", params: { name: "send_notification", arguments: { title: "x", command: "ls" } } }));
    expect(evil.result.isError).toBe(true);
    expect(evil.result.structuredContent.fields).toEqual(["command"]);
    const st = await j(await rpc(key, { jsonrpc: "2.0", id: 6, method: "tools/call", params: { name: "herald_status", arguments: {} } }));
    expect(st.result.structuredContent.online).toBe(false);
    const unknown = await j(await rpc(key, { jsonrpc: "2.0", id: 7, method: "tools/call", params: { name: "run_shell", arguments: {} } }));
    expect(unknown.error.code).toBe(-32602);
  });
  it("wait_for_reply returns audio replies", async () => {
    const { token } = await pair();
    const { key } = await mintKey(token);
    const c = await connect(token);
    await notify(key, { title: "q", notificationId: "mv", expectReply: true });
    const n = await c.next();
    await f(`/v1/device/reply/${n.id}/audio`, { method: "PUT", headers: { authorization: "Bearer " + token, "content-type": "audio/mp4" }, body: new Uint8Array(100) });
    await f("/v1/device/reply", { method: "POST", headers: auth(token), body: JSON.stringify({ id: n.id, transcript: "ok", durationSeconds: 1 }) });
    const r = await j(await rpc(key, { jsonrpc: "2.0", id: 8, method: "tools/call", params: { name: "wait_for_reply", arguments: { notificationId: "mv", timeoutSeconds: 1 } } }));
    expect(r.result.structuredContent).toMatchObject({ replied: true, transcript: "ok" });
    expect(r.result.structuredContent.audioUrl).toContain("/v1/audio/");
  });
});

// The counters live in the Durable Object's memory (a request costs no row write), so the tests set them there.
async function setUsage(deviceId: string, usage: Record<string, number>) {
  const stub: any = env.MAILBOX.get(env.MAILBOX.idFromName(deviceId));
  await (runInDurableObject as any)(stub, async (inst: any) => {
    inst.loadUsage();
    Object.assign(inst.usageRow, usage);
  });
}

describe("free-plan guards", () => {
  it("answers 503 with Retry-After once the daily request budget is used, and nothing queued is lost", async () => {
    const { token, deviceId } = await pair();
    const { key } = await mintKey(token);
    await notify(key, { title: "queued before", notificationId: "keep" });
    await setUsage(deviceId, { requests: 90_000 });
    const r = await notify(key, { title: "late" });
    expect(r.status).toBe(503);
    expect(Number(r.headers.get("retry-after"))).toBeGreaterThan(0);
    expect((await j(r)).error).toBe("budget_exhausted");
    const u = await j(await f("/v1/device/usage", { headers: auth(token) }));
    expect(u.budgetExhausted).toBe(true);
    expect(u.limits.requestsPerDay).toBeGreaterThan(0);          // the Mac and relay_usage show the relay's own limits
    expect(u.limits).toHaveProperty("notificationsPerDay");
    // the Mac can still connect and drain the queue
    const c = await connect(token);
    expect((await c.next()).notificationId).toBe("keep");
  });
  it("caps notifications per day", async () => {
    const { token, deviceId } = await pair();
    const { key } = await mintKey(token);
    await setUsage(deviceId, { notifications: 2000 });
    const r = await notify(key, { title: "x" });
    expect(r.status).toBe(429);
    expect((await j(r)).error).toBe("daily_cap");
    expect(r.headers.get("retry-after")).toBeTruthy();
  });
  it("caps voice replies per day so R2 stays inside its free tier", async () => {
    const { token, deviceId } = await pair();
    const { key } = await mintKey(token);
    const c = await connect(token);
    await notify(key, { title: "q", notificationId: "a" });
    const n = await c.next();
    await setUsage(deviceId, { audioUploads: 200 });
    const r = await f(`/v1/device/reply/${n.id}/audio`, { method: "PUT", headers: { authorization: "Bearer " + token, "content-type": "audio/mp4" }, body: new Uint8Array(10) });
    expect(r.status).toBe(429);
    expect(r.headers.get("retry-after")).toBeTruthy();
  });
  it("rate-limits receipt reads per key", async () => {
    const { token, deviceId } = await pair();
    const { key, id } = await mintKey(token);
    await notify(key, { title: "x", notificationId: "n" });
    expect((await f("/v1/receipts/n", { headers: auth(key) })).status).toBe(200);
    const stub: any = env.MAILBOX.get(env.MAILBOX.idFromName(deviceId));
    await (runInDurableObject as any)(stub, async (inst: any) => {
      inst.readHits.set(id, Array(600).fill(Date.now()));
    });
    const r = await f("/v1/receipts/n", { headers: auth(key) });
    expect(r.status).toBe(429);
    expect(r.headers.get("retry-after")).toBeTruthy();
  });
  it("stops holding long-polls once the day's poll allowance is gone", async () => {
    const { token, deviceId } = await pair();
    const { key } = await mintKey(token);
    await notify(key, { title: "q", notificationId: "p", expectReply: true });
    await setUsage(deviceId, { pollSeconds: 6000 });
    const t0 = Date.now();
    await f("/v1/replies/p?wait=30", { headers: auth(key) });
    expect(Date.now() - t0).toBeLessThan(1500);
  });
});

describe("unpair, usage and config", () => {
  it("unpair wipes the mailbox", async () => {
    const { token } = await pair();
    const { key } = await mintKey(token);
    expect((await f("/v1/device", { method: "DELETE", headers: auth(token) })).status).toBe(200);
    expect((await notify(key, { title: "x" })).status).toBe(401);
    expect((await f("/v1/device/info", { headers: auth(token) })).status).toBe(401);
  });
  it("DELETE /v1/device/keys/:id?purge=1 forgets a throw-away key altogether (Herald's relay test)", async () => {
    const { token } = await pair();
    const { id, key } = await mintKey(token, "herald-test-abc123");
    await notify(key, { title: "Relay test", notificationId: "t1" });
    const r = await f("/v1/device/keys/" + id + "?purge=1", { method: "DELETE", headers: auth(token) });
    expect(r.status).toBe(200);
    expect((await j(r)).purged).toBe(true);
    const list = await j(await f("/v1/device/keys", { headers: auth(token) }));
    expect(list.keys.some((k: any) => k.id === id)).toBe(false);   // not even listed as revoked
    expect((await notify(key, { title: "x" })).status).toBe(401);
    // a plain revoke still keeps the row, marked revoked
    const b = await mintKey(token, "plain-one");
    await f("/v1/device/keys/" + b.id, { method: "DELETE", headers: auth(token) });
    const list2 = await j(await f("/v1/device/keys", { headers: auth(token) }));
    expect(list2.keys.find((k: any) => k.id === b.id)?.revokedAt).toBeTruthy();
  });
  it("reports usage for the day", async () => {
    const { token } = await pair();
    const { key } = await mintKey(token);
    await notify(key, { title: "x" });
    const u = await j(await f("/v1/device/usage", { headers: auth(token) }));
    expect(u).toMatchObject({ notifications: 1, queued: 1, budgetExhausted: false });
    expect(u.requests).toBeGreaterThan(1);
    expect(u.limits.freePlanRequestsPerDay).toBe(100000);
    expect(u.storageBytes).toBeGreaterThan(0);
  });
  it("is configured for R2 audio with a 7-day lifecycle and no cron triggers", () => {
        expect(toml).toMatch(/binding = "AUDIO"/);
    expect(toml).toMatch(/bucket_name = "herald-relay-audio"/);
    expect(toml).not.toMatch(/\[triggers\]|crons/);
    const lc = JSON.parse(lifecycle);
    expect(lc.bucket).toBe("herald-relay-audio");
    expect(lc.rules[0].expireDays).toBe(7);
    expect(r2setup).toContain("--expire-days 7");
  });
});
