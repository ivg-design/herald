import { describe, expect, it } from "vitest";
import { f, j } from "./helpers";

describe("health", () => {
  for (const p of ["/health", "/healthz", "/"]) {
    it(`GET ${p} is 200 with the service banner`, async () => {
      const r = await f(p);
      expect(r.status).toBe(200);
      expect(await j(r)).toMatchObject({ service: "herald-relay", ok: true });
    });
  }
});
