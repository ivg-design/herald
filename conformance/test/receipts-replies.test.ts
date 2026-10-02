import { describe, expect, it } from "vitest";
import { auth, connect, f, j, mintKey, notify, pair, sleep } from "./helpers";

describe("receipts", () => {
  it("gives separate receipts: received, displayed, spoken, suppressed", async () => {
    const { token } = await pair();
    const { key } = await mintKey(token);
    const c = await connect(token);
    await notify(key, { title: "a", notificationId: "A", speak: true });
    await notify(key, { title: "b", notificationId: "B" });
    const A = await c.next(), B = await c.next();
    let r = await j(await f("/v1/receipts/A", { headers: auth(key) }));
    expect(r).toMatchObject({ received: true, displayed: false, spoken: false, replied: false, suppressed: false });
    c.send({ type: "receipt", id: A.id, kind: "displayed" });
    await sleep(300);
    r = await j(await f("/v1/receipts/A", { headers: auth(key) }));
    expect(r).toMatchObject({ received: true, displayed: true, spoken: false });
    const hr = await f("/v1/device/receipt", { method: "POST", headers: auth(token), body: JSON.stringify({ id: A.id, kind: "spoken" }) });
    expect(hr.status).toBe(200);
    r = await j(await f("/v1/receipts/A", { headers: auth(key) }));
    expect(r).toMatchObject({ displayed: true, spoken: true, queued: false });
    const sr = await f("/v1/device/receipt", { method: "POST", headers: auth(token), body: JSON.stringify({ id: B.id, kind: "suppressed", reason: "quiet-hours" }) });
    expect(sr.status).toBe(200);
    r = await j(await f("/v1/receipts/B", { headers: auth(key) }));
    expect(r).toMatchObject({ received: true, displayed: false, suppressed: true, reason: "quiet-hours" });
  });
});

describe("replies and long-poll", () => {
  it("returns an inline reply to a waiting long-poll", async () => {
    const { token } = await pair();
    const { key } = await mintKey(token);
    const c = await connect(token);
    await notify(key, { title: "Which branch?", notificationId: "ask", expectReply: true });
    const n = await c.next();
    const waiting = f("/v1/replies/ask?wait=10", { headers: auth(key) });
    setTimeout(() => c.send({ type: "receipt", id: n.id, kind: "replied", text: "release/1.7" }), 300);
    const r = await j(await waiting);
    expect(r).toMatchObject({ replied: true, reply: "release/1.7", text: "release/1.7" });
    const rec = await j(await f("/v1/receipts/ask", { headers: auth(key) }));
    expect(rec).toMatchObject({ replied: true, reply: "release/1.7" });
  });
  it("times out cleanly and 404s an unknown id", async () => {
    const { token } = await pair();
    const { key } = await mintKey(token);
    await notify(key, { title: "q", notificationId: "slow", expectReply: true });
    const t0 = Date.now();
    const r = await j(await f("/v1/replies/slow?wait=1", { headers: auth(key) }));
    expect(Date.now() - t0).toBeGreaterThanOrEqual(900);
    expect(r).toMatchObject({ replied: false, timedOut: true });
    expect((await f("/v1/replies/missing", { headers: auth(key) })).status).toBe(404);
  });
  it("wakes a long-poll when the notification is suppressed", async () => {
    const { token } = await pair();
    const { key } = await mintKey(token);
    const c = await connect(token);
    await notify(key, { title: "q", notificationId: "sup", expectReply: true });
    const n = await c.next();
    setTimeout(() => c.send({ type: "receipt", id: n.id, kind: "suppressed", reason: "muted" }), 200);
    const r = await j(await f("/v1/replies/sup?wait=10", { headers: auth(key) }));
    expect(r).toMatchObject({ replied: false, suppressed: true, reason: "muted" });
  });
});
