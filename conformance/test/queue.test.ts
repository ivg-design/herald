import { describe, expect, it } from "vitest";
import { auth, connect, f, j, mintKey, notify, pair, sleep } from "./helpers";

describe("dedupe and queue", () => {
  it("dedupes ids: the second send never reaches the Mac", async () => {
    const { token } = await pair();
    const { key } = await mintKey(token);
    const c = await connect(token);
    const a = await notify(key, { title: "once", notificationId: "build-1" });
    const b = await notify(key, { title: "once", notificationId: "build-1" });
    expect(a.status).toBe(202); expect((await j(a)).duplicate).toBe(false);
    expect(b.status).toBe(200); expect((await j(b)).duplicate).toBe(true);
    expect((await c.next()).notificationId).toBe("build-1");
    await sleep(300);
    expect(c.msgs.filter((m) => m.type === "notify")).toHaveLength(0);
  });
  it("queues while the Mac is offline and delivers on connect, in order", async () => {
    const { token } = await pair();
    const { key } = await mintKey(token);
    const r = await j(await notify(key, { title: "first", notificationId: "q1" }));
    expect(r.received).toBe(true); expect(r.queued).toBe(true);
    await notify(key, { title: "second", notificationId: "q2" });
    expect((await j(await f("/v1/status", { headers: auth(key) }))).online).toBe(false);
    const c = await connect(token);
    expect((await c.next()).notificationId).toBe("q1");
    expect((await c.next()).notificationId).toBe("q2");
    expect((await j(await f("/v1/status", { headers: auth(key) }))).online).toBe(true);
  });
  it("redelivers unacked items on reconnect until acked", async () => {
    const { token } = await pair();
    const { key } = await mintKey(token);
    const c1 = await connect(token);
    await notify(key, { title: "x", notificationId: "r1" });
    await c1.next();
    const c2 = await connect(token);
    const m = await c2.next();
    expect(m.notificationId).toBe("r1");
    c2.send({ type: "ack", id: m.id });
    await sleep(300);
    const c3 = await connect(token);
    await sleep(400);
    expect(c3.msgs.filter((x) => x.type === "notify")).toHaveLength(0);
  });
  it("reports quiet hours through status, and nothing else about the Mac", async () => {
    const { token } = await pair();
    const { key } = await mintKey(token);
    const c = await connect(token);
    c.send({ type: "hello", quietActive: true, quietUntil: "2026-10-03T07:30:00Z", muted: true });
    await sleep(300);
    const s = await j(await f("/v1/status", { headers: auth(key) }));
    expect(s).toMatchObject({ online: true, quietHours: { active: true, until: "2026-10-03T07:30:00Z" } });
    expect(Object.keys(s).sort()).toEqual(["lastSeenAt", "online", "quietHours"]);
  });
});
