import { describe, expect, it } from "vitest";
import { auth, f, j, mintKey, notify, pair } from "./helpers";

describe("limits", () => {
  it("allows 60 per 10 minutes per key, then 429 with Retry-After", async () => {
    const { token } = await pair();
    const k1 = await mintKey(token, "one"), k2 = await mintKey(token, "two");
    for (let i = 0; i < 60; i++) expect((await notify(k1.key, { title: "n" + i })).status, "n" + i).toBe(202);
    const r = await notify(k1.key, { title: "over" });
    expect(r.status).toBe(429);
    expect(Number(r.headers.get("retry-after"))).toBeGreaterThan(0);
    expect((await notify(k2.key, { title: "other key is fine" })).status).toBe(202);
  });
  it("refuses with 429 queue_full at the device's queue limit (read from /v1/device/usage)", async () => {
    const { token } = await pair();
    const usage = await j(await f("/v1/device/usage", { headers: auth(token) }));
    const max: number = usage.limits.queueMax;
    expect(max).toBeGreaterThan(0);
    const perKey = 50, fillKeys = Math.ceil(max / perKey);
    const keys = await Promise.all(Array.from({ length: fillKeys + 1 }, (_, i) => mintKey(token, "k" + (i + 1))));
    let sent = 0;
    for (const k of keys.slice(0, fillKeys)) {
      const n = Math.min(perKey, max - sent);
      const rs = await Promise.all(Array.from({ length: n }, (_, i) => notify(k.key, { title: "q" + i })));
      rs.forEach((r) => expect(r.status).toBe(202));
      sent += n;
    }
    const r = await notify(keys[fillKeys].key, { title: "one too many" });
    expect(r.status).toBe(429);
    expect((await j(r)).error).toBe("queue_full");
  }, 60000);
});
