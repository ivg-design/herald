import { describe, expect, it } from "vitest";
import { handleMcp } from "../src/mcp";

/** A forward that answers like the mailbox does and records every request that would count against the budget. */
function harness(validKey = true) {
  const paths: string[] = [];
  const forward = async (path: string) => {
    paths.push(path);
    if (!validKey) return new Response('{"error":"unauthorized"}', { status: 401 });
    if (path.startsWith("/v1/events")) return Response.json({ result: { ok: true } });
    return Response.json({ ok: true });
  };
  const call = (body: unknown) => handleMcp(new Request("https://relay.test/mcp", { method: "POST", body: JSON.stringify(body) }), forward);
  return { paths, call };
}
const rpc = (method: string, params?: unknown) => ({ jsonrpc: "2.0", id: 1, method, params });

describe("MCP calls cost one mailbox request when they reach the mailbox anyway", () => {
  it("tools/call and events/subscribe use their own request to authenticate", async () => {
    const h = harness();
    expect((await h.call(rpc("tools/call", { name: "send_notification", arguments: { title: "t" } }))).status).toBe(200);
    expect(h.paths).toEqual(["/v1/notify"]);
    h.paths.length = 0;
    await h.call(rpc("tools/call", { name: "get_receipt", arguments: { notificationId: "n1" } }));
    expect(h.paths).toEqual(["/v1/receipts/n1"]);
    h.paths.length = 0;
    await h.call(rpc("tools/call", { name: "herald_status" }));
    expect(h.paths).toEqual(["/v1/status"]);
    h.paths.length = 0;
    await h.call({ ...rpc("events/subscribe", { events: [] }) });
    expect(h.paths.length).toBe(1);
  });

  it("calls answered locally still need the key, with a single probe", async () => {
    for (const m of ["initialize", "tools/list", "ping"]) {
      const h = harness();
      expect((await h.call(rpc(m, { protocolVersion: "2025-06-18" }))).status, m).toBe(200);
      expect(h.paths, m).toEqual(["/v1/status"]);
    }
    const h = harness();
    await h.call(rpc("tools/call", { name: "get_receipt", arguments: {} }));   // a tool error answered locally
    expect(h.paths).toEqual(["/v1/status"]);
    const u = harness();
    await u.call(rpc("tools/call", { name: "nope" }));
    expect(u.paths).toEqual(["/v1/status"]);
  });

  it("a bad key is refused in every case", async () => {
    for (const body of [rpc("tools/list"), rpc("initialize", {}), rpc("tools/call", { name: "send_notification", arguments: { title: "t" } }),
                        rpc("tools/call", { name: "get_receipt", arguments: {} }), rpc("tools/call", { name: "nope" }), rpc("events/subscribe", {})]) {
      const h = harness(false);
      expect((await h.call(body)).status, JSON.stringify(body)).toBe(401);
      expect(h.paths.length).toBeLessThanOrEqual(2);
    }
  });
});
