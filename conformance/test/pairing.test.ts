import { describe, expect, it } from "vitest";
import { f, j, pairStart } from "./helpers";

describe("pairing", () => {
  it("pairs once with a one-time code", async () => {
    const s = await pairStart();
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
  // Wrong codes are rate-limited globally (10 per 10 min): this is the only wrong-code attempt besides auth's none.
  it("rejects a wrong code", async () => {
    expect((await f("/v1/pair", { method: "POST", body: JSON.stringify({ code: "AAAA-BBBB" }) })).status).toBe(403);
  });
});
