import { describe, expect, it } from "vitest";
import { auth, f, j, mintKey, notify, pair } from "./helpers";

describe("unpair and usage", () => {
  it("unpair wipes the mailbox", async () => {
    const { token } = await pair();
    const { key } = await mintKey(token);
    expect((await f("/v1/device", { method: "DELETE", headers: auth(token) })).status).toBe(200);
    expect((await notify(key, { title: "x" })).status).toBe(401);
    expect((await f("/v1/device/info", { headers: auth(token) })).status).toBe(401);
  });
  it("reports usage for the day", async () => {
    const { token } = await pair();
    const { key } = await mintKey(token);
    await notify(key, { title: "x" });
    const u = await j(await f("/v1/device/usage", { headers: auth(token) }));
    expect(u).toMatchObject({ notifications: 1, queued: 1, budgetExhausted: false });
    expect(typeof u.day).toBe("string");
    expect(u.requests).toBeGreaterThan(1);
    expect(typeof u.limits).toBe("object");
    expect(u.limits.freePlanRequestsPerDay).toBe(100000);
    expect(u.storageBytes).toBeGreaterThan(0);
  });
});
