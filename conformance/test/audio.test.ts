import { describe, expect, it } from "vitest";
import { audioPut, auth, connect, f, j, mintKey, notify, pair } from "./helpers";

describe("voice replies", () => {
  it("returns voice replies with transcript and a signed audio URL", async () => {
    const { token } = await pair();
    const { key } = await mintKey(token);
    const c = await connect(token);
    await notify(key, { title: "q", notificationId: "voice", expectReply: true });
    const n = await c.next();
    const audio = new Uint8Array(5000).fill(7);
    expect((await audioPut(token, n.id, audio)).status).toBe(200);
    const rep = await f("/v1/device/reply", { method: "POST", headers: auth(token), body: JSON.stringify({ id: n.id, transcript: "ship it", durationSeconds: 3.2 }) });
    expect(rep.status).toBe(200);
    const r = await j(await f("/v1/replies/voice?wait=2", { headers: auth(key) }));
    expect(r).toMatchObject({ replied: true, transcript: "ship it", durationSeconds: 3.2, reply: "ship it" });
    expect(r.text).toBeUndefined();
    expect(r.audioUrl).toMatch(/\/v1\/audio\/[0-9a-f]{48}\/r_[0-9a-f]{24}\.m4a\?exp=\d+&sig=[0-9a-f]{64}$/);
    const u = new URL(r.audioUrl);
    // Download via the configured base, not whatever host the relay believes it has.
    const dl = await f(u.pathname + u.search);
    expect(dl.status).toBe(200);
    expect(dl.headers.get("content-type")).toContain("audio/mp4");
    const bytes = new Uint8Array(await dl.arrayBuffer());
    expect(bytes.byteLength).toBe(5000);
    expect(bytes.every((b) => b === 7)).toBe(true);
    expect((await f(u.pathname + "?exp=9999999999&sig=" + "0".repeat(64))).status).toBe(403);
    expect((await f(u.pathname + "?exp=1&sig=" + "0".repeat(64))).status).toBe(410);
  });
  it("limits audio to 1 MB of m4a", async () => {
    const { token } = await pair();
    const { key } = await mintKey(token);
    const c = await connect(token);
    await notify(key, { title: "q", notificationId: "big" });
    const n = await c.next();
    expect((await audioPut(token, n.id, new Uint8Array(1024 * 1024 + 1))).status).toBe(413);
    expect((await audioPut(token, n.id, new Uint8Array(10), "text/html")).status).toBe(415);
    expect((await audioPut(token, n.id, new Uint8Array(1024 * 1024))).status).toBe(200);
  });
});
