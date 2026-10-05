import { env, runInDurableObject } from "cloudflare:test";
import { describe, expect, it } from "vitest";
import { Mailbox } from "../src/mailbox";
import { cleanHost, publicHost } from "../src/events";
import { auth, connect, f, mintKey, notify, pair } from "./helpers";

const M = "2026-07-28";
const PV = "io.modelcontextprotocol/protocolVersion";
const CAPS = "io.modelcontextprotocol/clientCapabilities";
const SECRET = "whsec_" + btoa(String.fromCharCode(...new Uint8Array(32).map((_, i) => i + 1)));
const HOST = "receiver.example.com";
const CB = `https://${HOST}/mcp-events/cb_1`;

let rpc = 1000;
async function modern(token: string, method: string, params: Record<string, unknown> = {}, headers: Record<string, string> = {}, meta: Record<string, unknown> | null = { [PV]: M, [CAPS]: {} }) {
  const body = { jsonrpc: "2.0", id: ++rpc, method, params: meta === null ? params : { ...params, _meta: meta } };
  const r = await f("/mcp", { method: "POST", headers: auth(token, { "mcp-protocol-version": M, "mcp-method": method, ...headers }), body: JSON.stringify(body) });
  return { status: r.status, body: (await r.json()) as any };
}
async function legacy(token: string, method: string, params: Record<string, unknown> = {}) {
  const r = await f("/mcp", { method: "POST", headers: auth(token), body: JSON.stringify({ jsonrpc: "2.0", id: ++rpc, method, params }) });
  return { status: r.status, body: (await r.json()) as any };
}

type Call = { url: string; headers: Headers; body: any };
function receiver(respond: (c: Call) => Response = echo) {
  const calls: Call[] = [];
  const fn = async (url: string, init: RequestInit) => {
    const c = { url, headers: new Headers(init.headers), body: JSON.parse(String(init.body)) };
    calls.push(c);
    return respond(c);
  };
  return { calls, fn };
}
function echo(c: Call): Response {
  return c.body.type === "verification" ? Response.json({ challenge: c.body.challenge }) : new Response(null, { status: 204 });
}
const stub = (deviceId: string) => env.MAILBOX.get(env.MAILBOX.idFromName(deviceId));
const install = (id: string, fn: Mailbox["outbound"]) => runInDurableObject(stub(id), async (o: Mailbox) => { o.outbound = fn; });
const deliver = (id: string, at = Date.now()) => runInDurableObject(stub(id), async (o: Mailbox) => { await o.deliverDue(at); });
const sql = <T>(id: string, q: string, ...a: unknown[]) => runInDurableObject(stub(id), async (_o, state) => state.storage.sql.exec(q, ...a).toArray() as T[]);
const view = async (token: string) => (await (await f("/v1/device/events", { headers: auth(token) })).json()) as any;
const subscribe = (key: string, extra: Record<string, unknown> = {}) =>
  modern(key, "events/subscribe", { name: "notification.reply", arguments: {}, delivery: { mode: "webhook", url: CB, secret: SECRET }, cursor: null, ...extra });

async function validSignature(c: Call): Promise<boolean> {
  const k = await crypto.subtle.importKey("raw", Uint8Array.from(atob(SECRET.slice(6)), (x) => x.charCodeAt(0)), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const signed = `${c.headers.get("webhook-id")}.${c.headers.get("webhook-timestamp")}.${JSON.stringify(c.body)}`;
  const sig = btoa(String.fromCharCode(...new Uint8Array(await crypto.subtle.sign("HMAC", k, new TextEncoder().encode(signed)))));
  return c.headers.get("webhook-signature") === "v1," + sig;
}

/** A paired Mac with one agent key and a receiver installed. Nothing else is set up: the key alone authorises a subscription. */
async function setup(respond?: (c: Call) => Response) {
  const dev = await pair();
  const { key, id: keyId } = await mintKey(dev.token);
  const rx = receiver(respond);
  await install(dev.deviceId, rx.fn);
  return { ...dev, key, keyId, rx };
}
/** Sends a notification that expects a reply and answers it from the Mac. Returns the relay id. */
async function ask(s: { token: string; key: string; deviceId: string }, nid: string, body: Record<string, unknown> = { text: "main" }) {
  expect((await notify(s.key, { title: "Which branch?", notificationId: nid, expectReply: true })).status).toBe(202);
  const rid = (await sql<{ rid: string }>(s.deviceId, "SELECT rid FROM notes WHERE nid = ?", nid))[0].rid;
  const r = await f("/v1/device/reply", { method: "POST", headers: auth(s.token), body: JSON.stringify({ id: rid, ...body }) });
  expect(r.status).toBe(200);
  return rid;
}

describe("dual-era MCP", () => {
  it("advertises events to modern clients and keeps the legacy handshake unchanged", async () => {
    const s = await setup();
    const d = await modern(s.key, "server/discover");
    expect(d.status).toBe(200);
    expect(d.body.result).toMatchObject({ resultType: "complete", capabilities: { tools: {}, events: {} } });
    expect(d.body.result.supportedVersions).toContain(M);
    const l = await legacy(s.key, "initialize", { protocolVersion: "2025-06-18" });
    expect(l.body.result.protocolVersion).toBe("2025-06-18");
    expect(l.body.result.capabilities.events).toBeUndefined();
    expect((await legacy(s.key, "events/list")).body.error.code).toBe(-32601);
    const tools = await modern(s.key, "tools/list");
    expect(tools.body.result.tools.map((t: any) => t.name)).toEqual(["send_notification", "get_receipt", "wait_for_reply", "herald_status"]);
    const ev = await modern(s.key, "events/list");
    expect(ev.body.result.events).toHaveLength(1);
    expect(ev.body.result.events[0]).toMatchObject({ name: "notification.reply", delivery: ["webhook"] });
  });

  it("rejects bad version metadata with the modern error codes", async () => {
    const s = await setup();
    const unknown = await modern(s.key, "server/discover", {}, { "mcp-protocol-version": "1900-01-01" });
    expect([unknown.status, unknown.body.error.code]).toEqual([400, -32022]);
    const noMeta = await modern(s.key, "tools/list", {}, {}, { [CAPS]: {} });
    expect([noMeta.status, noMeta.body.error.code]).toEqual([400, -32602]);
    const mismatch = await modern(s.key, "tools/list", {}, { "mcp-method": "tools/call" });
    expect([mismatch.status, mismatch.body.error.code]).toEqual([400, -32020]);
    const noName = await modern(s.key, "tools/call", { name: "herald_status", arguments: {} });
    expect([noName.status, noName.body.error.code]).toEqual([400, -32020]);
    const missing = await modern(s.key, "nope/nope");
    expect([missing.status, missing.body.error.code]).toEqual([404, -32601]);
  });

  it("runs tools for a modern client and still needs a valid key", async () => {
    const s = await setup();
    const call = await modern(s.key, "tools/call", { name: "herald_status", arguments: {} }, { "mcp-name": "herald_status" });
    expect(call.body.result.resultType).toBe("complete");
    expect(call.body.result.structuredContent).toHaveProperty("online");
    const bad = await f("/mcp", { method: "POST", headers: auth(s.key.slice(0, -4) + "0000", { "mcp-protocol-version": M, "mcp-method": "events/list" }),
      body: JSON.stringify({ jsonrpc: "2.0", id: 1, method: "events/list", params: { _meta: { [PV]: M, [CAPS]: {} } } }) });
    expect(bad.status).toBe(401);
  });
});

describe("subscribing", () => {
  it("needs nothing from the user beyond the connector's approval: one call and it is live", async () => {
    const s = await setup();
    const mac = await connect(s.token);
    const r = await subscribe(s.key);
    expect(r.body.result.id).toMatch(/^sub_[0-9a-f]{20}$/);
    expect(mac.msgs.filter((m: any) => m.type !== "welcome")).toEqual([]); // no question is put to the Mac
    expect((await view(s.token)).restrictedTo).toEqual([]);
  });

  it("verifies the callback with a signed challenge before the subscription is active", async () => {
    const s = await setup();
    const r = await subscribe(s.key);
    expect(r.body.result).toMatchObject({ cursor: "0", truncated: false });
    expect(s.rx.calls).toHaveLength(1);
    expect(s.rx.calls[0].body.type).toBe("verification");
    expect(await validSignature(s.rx.calls[0])).toBe(true);
    expect(s.rx.calls[0].headers.get("x-mcp-subscription-id")).toBe(r.body.result.id);
    const v = await view(s.token);
    expect(v.subscriptions).toHaveLength(1);
    expect(v.subscriptions[0]).toMatchObject({ id: r.body.result.id, event: "notification.reply", host: HOST, key: { name: "bot" }, pending: 0 });
    expect(JSON.stringify(v)).not.toContain("whsec_");
    expect(JSON.stringify(v)).not.toContain("cb_1"); // only the host is shown, never the path
  });

  it("fails with a reason when the callback does not answer the challenge", async () => {
    for (const [respond, reason] of [
      [() => new Response("no", { status: 500 }), "bad_status"],
      [() => Response.json({ challenge: "wrong" }), "challenge_mismatch"],
      [() => { throw new Error("down"); }, "unreachable"],
    ] as const) {
      const s = await setup(respond as never);
      const r = await subscribe(s.key);
      expect(r.body.error).toMatchObject({ code: -32015, data: { reason } });
      expect((await view(s.token)).subscriptions).toEqual([]);
    }
  });

  it("validates the request", async () => {
    const s = await setup();
    const bad = async (extra: Record<string, unknown>) => (await subscribe(s.key, extra)).body.error?.code;
    expect(await bad({ name: "other.event" })).toBe(-32602);
    expect(await bad({ arguments: { x: 1 } })).toBe(-32602);
    expect(await bad({ delivery: { mode: "sse", url: CB, secret: SECRET } })).toBe(-32602);
    expect(await bad({ delivery: { mode: "webhook", url: "http://" + HOST + "/x", secret: SECRET } })).toBe(-32602);
    expect(await bad({ delivery: { mode: "webhook", url: `https://${HOST}:8443/x`, secret: SECRET } })).toBe(-32602);
    expect(await bad({ delivery: { mode: "webhook", url: `https://u:p@${HOST}/x`, secret: SECRET } })).toBe(-32602);
    expect(await bad({ delivery: { mode: "webhook", url: "https://127.0.0.1/x", secret: SECRET } })).toBe(-32602);
    expect(await bad({ delivery: { mode: "webhook", url: CB, secret: "short" } })).toBe(-32602);
    expect(await bad({ ttlMs: -5 })).toBe(-32602);
    expect(s.rx.calls).toHaveLength(0);
  });

  it("is durable: no lapse with time, ttlMs is ignored, and subscribing again keeps the id without re-verifying", async () => {
    const s = await setup();
    const a = await subscribe(s.key, { ttlMs: 1000 });
    const years = Date.parse(a.body.result.refreshBefore) - Date.now();
    expect(years).toBeGreaterThan(9 * 365 * 86400_000);
    const b = await subscribe(s.key);
    expect(b.body.result.id).toBe(a.body.result.id);
    expect(s.rx.calls.filter((c) => c.body.type === "verification")).toHaveLength(1);
    // five years on, a reply is still delivered
    const real = Date.now;
    Date.now = () => real() + 5 * 365 * 86400_000;
    try {
      await ask(s, "later");
      await deliver(s.deviceId);
    } finally { Date.now = real; }
    expect(s.rx.calls.filter((c) => c.body.name === "notification.reply")).toHaveLength(1);
  });

  it("caps subscriptions per connector", async () => {
    const s = await setup();
    for (let i = 0; i < 5; i++) expect((await subscribe(s.key, { delivery: { mode: "webhook", url: `${CB}_${i}`, secret: SECRET } })).body.result.id).toBeTruthy();
    expect((await subscribe(s.key, { delivery: { mode: "webhook", url: `${CB}_x`, secret: SECRET } })).body.error.code).toBe(-32602);
  });
});

describe("delivery", () => {
  it("sends a signed event with ids only when the user replies, to the sender's subscription alone", async () => {
    const s = await setup();
    const other = await mintKey(s.token, "other", "codex");
    const sub = await subscribe(s.key);
    await subscribe(other.key, { delivery: { mode: "webhook", url: `https://${HOST}/other`, secret: SECRET } });
    const rid = await ask(s, "ask-1", { text: "ship the hotfix" });
    await deliver(s.deviceId);
    const events = s.rx.calls.filter((c) => c.body.name === "notification.reply");
    expect(events).toHaveLength(1); // the other key's subscription got nothing
    const e = events[0];
    expect(e.url).toBe(CB);
    expect(e.body).toMatchObject({ name: "notification.reply", data: { notificationId: "ask-1", id: rid, kind: "text" }, cursor: "1" });
    expect(e.body.eventId).toMatch(/^evt_1_/);
    expect(JSON.stringify(e.body)).not.toContain("hotfix"); // never the text
    expect(await validSignature(e)).toBe(true);
    expect(e.headers.get("x-mcp-subscription-id")).toBe(sub.body.result.id);
    expect(e.headers.get("webhook-id")).toBe(e.body.eventId);
    // the agent then reads the answer the usual way
    const call = await modern(s.key, "tools/call", { name: "get_receipt", arguments: { notificationId: "ask-1" } }, { "mcp-name": "get_receipt" });
    expect(JSON.stringify(call.body.result.structuredContent)).toContain("ship the hotfix");
    expect(await sql(s.deviceId, "SELECT id FROM event_outbox")).toEqual([]);
  });

  it("fires once per notification, marks a voice reply, and also fires for a receipt sent over the socket", async () => {
    const s = await setup();
    await subscribe(s.key);
    const rid = await ask(s, "v", { transcript: "do it", durationSeconds: 2 });
    await f("/v1/device/reply", { method: "POST", headers: auth(s.token), body: JSON.stringify({ id: rid, text: "again" }) }); // a second answer: no second event
    const mac = await connect(s.token);
    await notify(s.key, { title: "q", notificationId: "ws", expectReply: true });
    const n = await mac.next("notify");
    mac.ws.send(JSON.stringify({ type: "receipt", id: n.id, kind: "replied", text: "over the socket" }));
    for (let i = 0; i < 40 && (await sql<{ n: number }>(s.deviceId, "SELECT COUNT(*) AS n FROM events"))[0].n < 2; i++) await new Promise((r) => setTimeout(r, 25));
    await deliver(s.deviceId);
    const events = s.rx.calls.filter((c) => c.body.name === "notification.reply").map((c) => c.body.data);
    expect(events).toEqual([{ notificationId: "v", id: rid, kind: "voice" }, { notificationId: "ws", id: n.id, kind: "text" }]);
  });

  it("retries transient failures in order, drops on a 4xx and ends the subscription on 410", async () => {
    let mode: number = 503;
    const s = await setup((c) => (c.body.type === "verification" ? echo(c) : new Response(null, { status: mode })));
    await subscribe(s.key);
    await ask(s, "a");
    await ask(s, "b");
    const t0 = Date.now();
    await deliver(s.deviceId, t0);
    let out = await sql<{ seq: number; attempts: number; next_at: number }>(s.deviceId, "SELECT seq, attempts, next_at FROM event_outbox ORDER BY seq");
    expect(out.map((o) => o.attempts)).toEqual([1, 0]); // only the head was tried; the later one waits behind it
    expect(out[0].next_at).toBeGreaterThanOrEqual(t0 + 59_000); // the alarm may have made the first attempt a moment before t0
    mode = 204;
    await deliver(s.deviceId, out[0].next_at + 1);
    await deliver(s.deviceId, out[0].next_at + 2);
    expect(await sql(s.deviceId, "SELECT id FROM event_outbox")).toEqual([]);
    const order = s.rx.calls.filter((c) => c.body.name === "notification.reply").map((c) => c.body.data.notificationId);
    expect(order).toEqual(["a", "a", "b"]);
    mode = 400;
    await ask(s, "c");
    await deliver(s.deviceId);
    expect(await sql(s.deviceId, "SELECT id FROM event_outbox")).toEqual([]); // dropped, subscription kept
    expect((await view(s.token)).subscriptions).toHaveLength(1);
    mode = 410;
    await ask(s, "d");
    await deliver(s.deviceId);
    expect((await view(s.token)).subscriptions).toEqual([]);
  });

  it("replays this connector's replies after a cursor", async () => {
    const s = await setup();
    await ask(s, "one");
    await ask(s, "two");
    const r = await subscribe(s.key, { cursor: "1" });
    expect(r.body.result.cursor).toBe("1"); // "two" is queued, not yet delivered: the cursor does not pass it
    await deliver(s.deviceId);
    expect(s.rx.calls.filter((c) => c.body.name === "notification.reply").map((c) => c.body.data.notificationId)).toEqual(["two"]);
    expect((await subscribe(s.key)).body.result.cursor).toBe("2");
  });
});

describe("ending a subscription", () => {
  it("unsubscribes, and stops when the connector is revoked", async () => {
    const s = await setup();
    await subscribe(s.key);
    const un = await modern(s.key, "events/unsubscribe", { name: "notification.reply", delivery: { mode: "webhook", url: CB } });
    expect(un.body.result.resultType).toBe("complete");
    expect((await view(s.token)).subscriptions).toEqual([]);

    await subscribe(s.key);
    expect((await f(`/v1/device/keys/${s.keyId}`, { method: "DELETE", headers: auth(s.token) })).status).toBe(200);
    expect((await view(s.token)).subscriptions).toEqual([]);
  });

  it("lets Herald, and only Herald, see and remove a subscription", async () => {
    const s = await setup();
    const sub = await subscribe(s.key);
    expect((await f("/v1/device/events", { headers: auth(s.key) })).status).toBe(403);
    expect((await f(`/v1/device/events/subscriptions/${sub.body.result.id}`, { method: "DELETE", headers: auth(s.key) })).status).toBe(403);
    expect((await f(`/v1/device/events/subscriptions/${sub.body.result.id}`, { method: "DELETE", headers: auth(s.token) })).status).toBe(200);
    expect((await view(s.token)).subscriptions).toEqual([]);
  });
});

describe("host rules", () => {
  it("accepts public names and rejects local or private ones", () => {
    expect(publicHost("api.example.com")).toBe(true);
    for (const h of ["localhost", "printer.local", "10.1.2.3", "192.168.1.1", "169.254.1.1", "127.0.0.1", "[::1]", "[fd00::1]", "intranet"]) expect(publicHost(h)).toBe(false);
    expect(cleanHost(" API.Example.com. ")).toBe("api.example.com");
    expect(cleanHost("a b.com")).toBeNull();
    expect(cleanHost("1.2.3.4")).toBe("1.2.3.4");
  });
});
