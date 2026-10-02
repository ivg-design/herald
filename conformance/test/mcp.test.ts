import { describe, expect, it } from "vitest";
import { audioPut, auth, connect, f, j, mintKey, notify, pair, rpc } from "./helpers";

const call = (key: string, id: number, name: string, args: unknown) =>
  rpc(key, { jsonrpc: "2.0", id, method: "tools/call", params: { name, arguments: args } });

describe("remote MCP", () => {
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
    const sent = await j(await call(key, 3, "send_notification", { title: "hello", notificationId: "m1" }));
    expect(sent.result.structuredContent).toMatchObject({ notificationId: "m1", received: true });
    const rec = await j(await call(key, 4, "get_receipt", { notificationId: "m1" }));
    expect(rec.result.structuredContent.received).toBe(true);
    const evil = await j(await call(key, 5, "send_notification", { title: "x", command: "ls" }));
    expect(evil.result.isError).toBe(true);
    expect(evil.result.structuredContent.fields).toEqual(["command"]);
    const st = await j(await call(key, 6, "herald_status", {}));
    expect(st.result.structuredContent.online).toBe(false);
    const unknown = await j(await call(key, 7, "run_shell", {}));
    expect(unknown.error.code).toBe(-32602);
  });
  it("wait_for_reply returns audio replies", async () => {
    const { token } = await pair();
    const { key } = await mintKey(token);
    const c = await connect(token);
    await notify(key, { title: "q", notificationId: "mv", expectReply: true });
    const n = await c.next();
    await audioPut(token, n.id, new Uint8Array(100));
    await f("/v1/device/reply", { method: "POST", headers: auth(token), body: JSON.stringify({ id: n.id, transcript: "ok", durationSeconds: 1 }) });
    const r = await j(await call(key, 8, "wait_for_reply", { notificationId: "mv", timeoutSeconds: 1 }));
    expect(r.result.structuredContent).toMatchObject({ replied: true, transcript: "ok" });
    expect(r.result.structuredContent.audioUrl).toContain("/v1/audio/");
  });
});
