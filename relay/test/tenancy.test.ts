import { describe, expect, it } from "vitest";
import { env, runInDurableObject } from "cloudflare:test";
import { DEFAULT_LIMITS, limitsFor } from "../src/limits";
import { auth, connect, f, mintKey, notify, pair } from "./helpers";

// The hosted relay is shared by every Herald that turns on "Enable relay". Each Mac has its own Durable Object, so every cap
// below is per device; these tests prove one Mac cannot use up another's allowance and that pairing limits are per address.

const j = async (r: Response) => (await r.json()) as any;

async function setUsage(deviceId: string, usage: Record<string, number>) {
  const stub: any = env.MAILBOX.get(env.MAILBOX.idFromName(deviceId));
  await (runInDurableObject as any)(stub, async (inst: any) => { inst.loadUsage(); Object.assign(inst.usageRow, usage); });
}

async function withRegistryEnv<T>(vars: Record<string, string>, body: () => Promise<T>): Promise<T> {
  const stub: any = env.REGISTRY.get(env.REGISTRY.idFromName("registry"));
  const saved: Record<string, unknown> = {};
  await (runInDurableObject as any)(stub, async (inst: any) => { for (const k of Object.keys(vars)) { saved[k] = inst.env[k]; inst.env[k] = vars[k]; } });
  try { return await body(); } finally {
    await (runInDurableObject as any)(stub, async (inst: any) => { for (const k of Object.keys(vars)) inst.env[k] = saved[k]; });
  }
}

const start = (ip: string) => f("/v1/pair/start", { method: "POST", body: "{}", headers: { "cf-connecting-ip": ip } });
const wrong = (ip: string) => f("/v1/pair", { method: "POST", body: JSON.stringify({ code: "AAAA-BBBB" }), headers: { "cf-connecting-ip": ip } });

describe("per-device caps (not global)", () => {
  it("defaults are sized for a shared relay and can be overridden by Worker vars", () => {
    expect(limitsFor({})).toEqual(DEFAULT_LIMITS);
    expect(limitsFor({ DEVICE_QUEUE_MAX: "7", DEVICE_AUDIO_BYTES_PER_DAY: "1000" })).toMatchObject({ queueMax: 7, audioBytesPerDay: 1000 });
    expect(limitsFor({ QUEUE_TTL_HOURS: "48", MAX_BODY_BYTES: "1000", RATE_LIMIT_PER_KEY: "5" })).toMatchObject({ ttlMs: 48 * 3600_000, bodyBytes: 1000, ratePerKey: 5 });
    expect(limitsFor({ DEVICE_QUEUE_MAX: "-3", DEVICE_REQUESTS_PER_DAY: "abc" })).toEqual(DEFAULT_LIMITS);
    expect(DEFAULT_LIMITS.notificationsPerDay).toBeLessThanOrEqual(500);
    expect(DEFAULT_LIMITS.requestsPerDay).toBeLessThanOrEqual(5000);
  });

  it("a Mac that used its daily notifications gets 429 while another Mac is untouched", async () => {
    const a = await pair(), b = await pair();
    const ka = await mintKey(a.token), kb = await mintKey(b.token);
    await setUsage(a.deviceId, { notifications: DEFAULT_LIMITS.notificationsPerDay });
    const r = await notify(ka.key, { title: "over" });
    expect(r.status).toBe(429);
    expect((await j(r)).error).toBe("daily_cap");
    expect((await notify(kb.key, { title: "fine" })).status).toBe(202);
  });

  it("a Mac whose request budget is gone gets 503 while another Mac is untouched", async () => {
    const a = await pair(), b = await pair();
    const ka = await mintKey(a.token), kb = await mintKey(b.token);
    await setUsage(a.deviceId, { requests: DEFAULT_LIMITS.requestsPerDay });
    const r = await notify(ka.key, { title: "late" });
    expect(r.status).toBe(503);
    expect(r.headers.get("retry-after")).toBeTruthy();
    expect((await notify(kb.key, { title: "fine" })).status).toBe(202);
    // the budget is per Mac and the Mac itself can still read its usage and drain the queue
    expect((await j(await f("/v1/device/usage", { headers: auth(a.token) }))).budgetExhausted).toBe(true);
    expect((await j(await f("/v1/device/usage", { headers: auth(b.token) }))).budgetExhausted).toBe(false);
  });

  it("a full queue stops only that Mac", async () => {
    const a = await pair(), b = await pair();
    const keys = [await mintKey(a.token, "k1"), await mintKey(a.token, "k2")];
    const kb = await mintKey(b.token);
    for (let i = 0; i < DEFAULT_LIMITS.queueMax; i++) expect((await notify(keys[i % 2].key, { title: "n" + i })).status).toBe(202);
    const full = await notify(keys[0].key, { title: "one too many" });
    expect(full.status).toBe(429);
    expect((await j(full)).error).toBe("queue_full");
    expect((await notify(kb.key, { title: "other mac" })).status).toBe(202);
  }, 60_000);

  it("voice replies are capped by bytes per day per Mac", async () => {
    const a = await pair(), b = await pair();
    const ka = await mintKey(a.token), kb = await mintKey(b.token);
    const ca = await connect(a.token), cb = await connect(b.token);
    await notify(ka.key, { title: "q", notificationId: "q" }); await notify(kb.key, { title: "q", notificationId: "q" });
    const na = await ca.next(), nb = await cb.next();
    await setUsage(a.deviceId, { audioBytes: DEFAULT_LIMITS.audioBytesPerDay - 50 });
    const put = (token: string, rid: string, n: number) =>
      f(`/v1/device/reply/${rid}/audio`, { method: "PUT", headers: { authorization: "Bearer " + token, "content-type": "audio/mp4" }, body: new Uint8Array(n) });
    const over = await put(a.token, na.id, 100);
    expect(over.status).toBe(429);
    expect((await j(over)).error).toBe("daily_cap");
    expect((await put(a.token, na.id, 40)).status).toBe(200);
    expect((await put(b.token, nb.id, 100)).status).toBe(200);
  });

  it("usage reports this Mac's own limits", async () => {
    const { token } = await pair();
    const u = await j(await f("/v1/device/usage", { headers: auth(token) }));
    expect(u.limits).toMatchObject({
      notificationsPerDay: DEFAULT_LIMITS.notificationsPerDay, queueMax: DEFAULT_LIMITS.queueMax, requestsPerDay: DEFAULT_LIMITS.requestsPerDay,
      audioBytesPerDay: DEFAULT_LIMITS.audioBytesPerDay, audioUploadsPerDay: DEFAULT_LIMITS.audioUploadsPerDay,
    });
  });
});

describe("pairing limits are per client address", () => {
  it("one address cannot start more than the hourly limit, another address is unaffected", async () => {
    await withRegistryEnv({ PAIR_STARTS_PER_HOUR: "2" }, async () => {
      expect((await start("203.0.113.1")).status).toBe(201);
      expect((await start("203.0.113.1")).status).toBe(201);
      const third = await start("203.0.113.1");
      expect(third.status).toBe(429);
      expect((await j(third)).retryAfterSeconds).toBeGreaterThan(0);
      expect((await start("203.0.113.2")).status).toBe(201);
    });
  });

  it("wrong codes lock out the address that guessed, not everyone", async () => {
    const noisy = "203.0.113.50", other = "203.0.113.51";
    for (let i = 0; i < 10; i++) expect((await wrong(noisy)).status).toBe(403);
    expect((await wrong(noisy)).status).toBe(429);
    // a different address can still pair normally
    const s = await start(other);
    expect(s.status).toBe(201);
    const { code } = await j(s);
    const p = await f("/v1/pair", { method: "POST", body: JSON.stringify({ code }), headers: { "cf-connecting-ip": other } });
    expect(p.status).toBe(200);
  });

  it("pending codes are limited per address, so one address cannot block everyone", async () => {
    const hog = "203.0.113.60";
    for (let i = 0; i < 3; i++) expect((await start(hog)).status).toBe(201);
    expect((await start(hog)).status).toBe(429);
    expect((await start("203.0.113.61")).status).toBe(201);
  });

  it("MAX_DEVICES guards the number of paired Macs", async () => {
    await withRegistryEnv({ MAX_DEVICES: "1" }, async () => {
      const r = await start("203.0.113.70");
      expect(r.status).toBe(403);
      expect((await j(r)).error).toBe("device_limit");
    });
  });

});

describe("no cross-device paths", () => {
  it("internal mailbox and registry routes are not reachable from outside", async () => {
    for (const p of ["/internal/init", "/internal/wipe", "/internal/remove", "/pair/start", "/v1/device/../internal/wipe", "/v1/device/%2e%2e/internal/wipe"]) {
      const r = await f(p, { method: "POST", body: "{}" });
      expect([401, 404, 405]).toContain(r.status);
    }
  });

  it("a credential carries one device: swapping the device id never reaches another mailbox", async () => {
    const a = await pair(), b = await pair();
    const ka = await mintKey(a.token), kb = await mintKey(b.token, "other");
    await notify(kb.key, { title: "secret of B", notificationId: "bs" });
    // A's device token with B's id fails the signature/hash checks
    expect((await f("/v1/device/keys", { headers: auth(a.token.replace(a.deviceId, b.deviceId)) })).status).toBe(401);
    // A's key cannot read B's receipt, even with B's id in it
    expect((await f("/v1/receipts/bs", { headers: auth(ka.key) })).status).toBe(404);
    expect((await f("/v1/receipts/bs", { headers: auth(ka.key.replace(a.deviceId, b.deviceId)) })).status).toBe(401);
    // A's device cannot touch B's notifications through a receipt
    const bc = await connect(b.token);
    const n = await bc.next();
    const r = await f("/v1/device/receipt", { method: "POST", headers: auth(a.token), body: JSON.stringify({ id: n.id, kind: "displayed" }) });
    expect(r.status).toBe(404);
  });

  it("signed audio links work for their own clip only", async () => {
    const a = await pair(), b = await pair();
    const ka = await mintKey(a.token);
    const ca = await connect(a.token);
    await notify(ka.key, { title: "q", notificationId: "v", expectReply: true });
    const n = await ca.next();
    await f(`/v1/device/reply/${n.id}/audio`, { method: "PUT", headers: { authorization: "Bearer " + a.token, "content-type": "audio/mp4" }, body: new Uint8Array(20) });
    await f("/v1/device/reply", { method: "POST", headers: auth(a.token), body: JSON.stringify({ id: n.id, transcript: "x" }) });
    const r = await j(await f("/v1/replies/v?wait=1", { headers: auth(ka.key) }));
    const u = new URL(r.audioUrl);
    expect((await f(u.pathname + u.search)).status).toBe(200);
    // the same signature on another device's path is refused
    const moved = u.pathname.replace(a.deviceId, b.deviceId);
    expect((await f(moved + u.search)).status).toBe(403);
  });
});
