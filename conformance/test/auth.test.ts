import { describe, expect, it } from "vitest";
import { auth, f, j, mintKey, notify, pair } from "./helpers";

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
      expect((await f(p, { method: m, headers: auth(key), body: m === "POST" ? "{}" : undefined })).status, `${m} ${p}`).toBe(403);
    }
    expect((await f("/v1/notify", { method: "POST", headers: auth(token), body: JSON.stringify({ title: "x" }) })).status).toBe(403);
  });
  it("a key reaches only its own device", async () => {
    const a = await pair(), b = await pair();
    const ka = await mintKey(a.token, "alpha");
    expect((await notify(ka.key, { title: "hi", notificationId: "same" })).status).toBe(202);
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
