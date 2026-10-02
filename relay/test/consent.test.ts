import { describe, expect, it } from "vitest";
import { env, runInDurableObject } from "cloudflare:test";
import { auth, connect, f, pair } from "./helpers";

const j = async (r: Response) => (await r.json()) as any;
const GRANT = "urn:ietf:params:oauth:grant-type:device_code";
const REDIRECT = "https://agent.test/cb";
const form = (o: Record<string, string>) => ({ method: "POST", headers: { "content-type": "application/x-www-form-urlencoded" }, body: new URLSearchParams(o).toString() });
const mailboxOf = (id: string) => env.MAILBOX.get(env.MAILBOX.idFromName(id));
const reg = () => env.REGISTRY.get(env.REGISTRY.idFromName("registry"));

async function index(deviceId: string): Promise<string> {
  const { devices } = (await (await reg().fetch("https://registry/devices", { method: "POST", body: "{}" })).json()) as { devices: { id: string }[] };
  return String(devices.findIndex((d) => d.id === deviceId) + 1);
}
async function deviceClient(name = "Cloud agent") {
  const r = await f("/register", { method: "POST", body: JSON.stringify({ client_name: name, grant_types: [GRANT] }) });
  return ((await j(r)).client_id) as string;
}
async function codeClient(name = "Web agent") {
  const r = await f("/register", { method: "POST", body: JSON.stringify({ client_name: name, redirect_uris: [REDIRECT] }) });
  return ((await j(r)).client_id) as string;
}
const startDevice = async (clientId: string, deviceId: string) => j(await f("/device_authorization", form({ client_id: clientId, scope: "notify", device: await index(deviceId) })));
const consents = async (token: string) => ((await j(await f("/v1/device/consents", { headers: auth(token) }))).consents as any[]);
const pending = async (token: string) => (await consents(token)).filter((c) => c.status === "pending");
const decide = (token: string, id: string, decision: string) => f("/v1/device/consent", { method: "POST", headers: auth(token), body: JSON.stringify({ id, decision }) });
const authorize = async (clientId: string, deviceId: string) => f("/authorize?" + new URLSearchParams({
  response_type: "code", client_id: clientId, redirect_uri: REDIRECT, code_challenge: "A".repeat(43), code_challenge_method: "S256", state: "s", device: await index(deviceId),
}));
const ridOf = async (page: Response) => /name="rid" value="([0-9a-f]{72})"/.exec(await page.text())![1];
const sql = (id: string, q: string, ...b: unknown[]) => (runInDurableObject as any)(mailboxOf(id), async (_i: any, state: any) => { state.storage.sql.exec(q, ...(b as any[])); });

describe("one open consent per client and Mac", () => {
  it("the same client asking again (device flow) replaces the request: one pending, same id, a fresh code, the old device_code dead", async () => {
    const dev = await pair();
    const client = await deviceClient();
    const c = await connect(dev.token);
    const first = await startDevice(client, dev.deviceId);
    const second = await startDevice(client, dev.deviceId);
    const third = await startDevice(client, dev.deviceId);
    const list = await pending(dev.token);
    expect(list.length).toBe(1);
    expect(list[0].userCode).toBe(third.user_code);
    expect(new Set([first.user_code, second.user_code, third.user_code]).size).toBe(3);
    // the earlier device_codes no longer redeem; the latest is still waiting for the person
    for (const old of [first, second]) {
      const r = await f("/token", form({ grant_type: GRANT, client_id: client, device_code: old.device_code }));
      expect((await j(r)).error).toBe("expired_token");
    }
    const live = await f("/token", form({ grant_type: GRANT, client_id: client, device_code: third.device_code }));
    expect(["authorization_pending", "slow_down"]).toContain((await j(live)).error);   // still waiting for the person (slow_down: polled too soon)
    // never a second request, so never a second banner: the Mac saw the same id every time
    const seen = new Set<string>();
    for (let i = 0; i < 3; i++) { const m = await c.next("consent"); seen.add(m.id); }
    expect(seen.size).toBe(1);
    c.ws.close();
  });

  it("the same client asking again (browser flow) is one request too", async () => {
    const dev = await pair();
    const client = await codeClient();
    const a = await ridOf(await authorize(client, dev.deviceId));
    const b = await ridOf(await authorize(client, dev.deviceId));
    expect(b).toBe(a);
    expect((await pending(dev.token)).length).toBe(1);
  });

  it("an update of the same request reaches the Mac as a consent frame (not flagged redelivered) with the new code", async () => {
    const dev = await pair();
    const client = await deviceClient();
    const c = await connect(dev.token);
    const one = await startDevice(client, dev.deviceId);
    const m1 = await c.next("consent");
    const two = await startDevice(client, dev.deviceId);
    const m2 = await c.next("consent");
    expect(m2.id).toBe(m1.id);
    expect(m1.userCode).toBe(one.user_code); expect(m2.userCode).toBe(two.user_code);
    expect(m2.redelivered).toBeUndefined();
    c.ws.close();
  });

  it("different clients are different requests", async () => {
    const dev = await pair();
    await startDevice(await deviceClient("A"), dev.deviceId);
    await startDevice(await deviceClient("B"), dev.deviceId);
    expect((await pending(dev.token)).length).toBe(2);
  });
});

describe("a reconnect does not bring the banner back", () => {
  it("a request Herald already got is re-sent flagged redelivered; one created while it was away arrives as new, once", async () => {
    const dev = await pair();
    const client = await deviceClient();
    const other = await deviceClient("Second");
    // created while Herald is away: nothing to send yet
    await startDevice(other, dev.deviceId);
    const c1 = await connect(dev.token);
    const fresh = await c1.next("consent");
    expect(fresh.clientName).toBe("Second");
    expect(fresh.redelivered).toBeUndefined();            // first time Herald hears of it: a banner
    await startDevice(client, dev.deviceId);
    const live = await c1.next("consent");
    expect(live.redelivered).toBeUndefined();
    c1.ws.close();
    // reconnect (twice): both are in the list, neither is a new banner
    for (let i = 0; i < 2; i++) {
      const c = await connect(dev.token);
      const frames = [await c.next("consent"), await c.next("consent")];
      expect(frames.map((m) => m.clientName).sort()).toEqual(["Cloud agent", "Second"]);
      expect(frames.every((m) => m.redelivered === true)).toBe(true);
      c.ws.close();
    }
  });
});

describe("expiry", () => {
  it("an expired consent is dropped from the mailbox, the Mac is told, and the agent's code is dead", async () => {
    const dev = await pair();
    const client = await deviceClient();
    const c = await connect(dev.token);
    const d = await startDevice(client, dev.deviceId);
    const asked = await c.next("consent");
    await sql(dev.deviceId, "UPDATE oauth_requests SET expires_at = ? WHERE id = ?", Date.now() - 1000, asked.id);
    await (runInDurableObject as any)(mailboxOf(dev.deviceId), async (inst: any) => { await inst.alarm(); });
    const gone = await c.next("consent_resolved");
    expect(gone).toMatchObject({ id: asked.id, status: "expired" });
    expect((await consents(dev.token)).length).toBe(0);                       // not even listed as expired
    const rows = await (runInDurableObject as any)(mailboxOf(dev.deviceId), async (_i: any, state: any) => state.storage.sql.exec("SELECT COUNT(*) AS n FROM oauth_requests WHERE id = ?", asked.id).toArray()[0].n);
    expect(rows).toBe(0);
    const r = await f("/token", form({ grant_type: GRANT, client_id: client, device_code: d.device_code }));
    expect((await j(r)).error).toBe("expired_token");
    c.ws.close();
  });

  it("creating a consent arms an alarm for its expiry", async () => {
    const dev = await pair();
    await startDevice(await deviceClient(), dev.deviceId);
    const alarm = await (runInDurableObject as any)(mailboxOf(dev.deviceId), async (_i: any, state: any) => await state.storage.getAlarm());
    expect(alarm).not.toBeNull();
    expect(alarm as number).toBeGreaterThan(Date.now());
    expect(alarm as number).toBeLessThanOrEqual(Date.now() + 10 * 60_000 + 5000);
  });

  it("an expired consent is also gone when the Mac reconnects or reads the list (no alarm needed)", async () => {
    const dev = await pair();
    const asked = await startDevice(await deviceClient(), dev.deviceId);
    expect(asked.user_code).toBeTruthy();
    const [one] = await pending(dev.token);
    await sql(dev.deviceId, "UPDATE oauth_requests SET expires_at = ? WHERE id = ?", Date.now() - 1000, one.id);
    const c = await connect(dev.token);
    await expect(c.next("consent", 300)).rejects.toThrow();
    expect((await consents(dev.token)).length).toBe(0);
    c.ws.close();
  });
});

describe("a decision removes the request everywhere", () => {
  it("approving tells the Mac; denying revokes nothing that already works", async () => {
    const dev = await pair();
    const client = await deviceClient();
    const c = await connect(dev.token);
    await startDevice(client, dev.deviceId);
    const asked = await c.next("consent");
    expect((await decide(dev.token, asked.id, "approve")).status).toBe(200);
    expect(await c.next("consent_resolved")).toMatchObject({ id: asked.id, status: "approved" });
    expect((await pending(dev.token)).length).toBe(0);

    // the connector now works; a later request from the same client, denied, leaves its key alone
    const keysBefore = (await j(await f("/v1/device/keys", { headers: auth(dev.token) }))).keys.filter((k: any) => !k.revokedAt && k.kind === "oauth");
    expect(keysBefore.length).toBe(1);
    await startDevice(client, dev.deviceId);
    const again = await c.next("consent");
    expect((await decide(dev.token, again.id, "deny")).status).toBe(200);
    expect(await c.next("consent_resolved")).toMatchObject({ id: again.id, status: "denied" });
    const keysAfter = (await j(await f("/v1/device/keys", { headers: auth(dev.token) }))).keys.filter((k: any) => !k.revokedAt && k.kind === "oauth");
    expect(keysAfter.map((k: any) => k.id)).toEqual(keysBefore.map((k: any) => k.id));      // Deny revoked nothing
    c.ws.close();
  });

  it("a request for the same client on another Mac closes the one on the first; a decision closes the others", async () => {
    const a = await pair(), b = await pair();
    const client = await deviceClient();
    const ca = await connect(a.token), cb = await connect(b.token);
    await startDevice(client, a.deviceId);
    const onA = await ca.next("consent");
    await startDevice(client, b.deviceId);                       // the agent retried and the relay picked the other Mac
    expect(await ca.next("consent_resolved")).toMatchObject({ id: onA.id, status: "superseded" });
    expect((await pending(a.token)).length).toBe(0);
    const onB = await cb.next("consent");
    // a third request on A, then B decides: A's goes away immediately
    await startDevice(client, a.deviceId);
    const second = await ca.next("consent");
    await cb.next("consent_resolved");                           // B's was superseded by A's new one
    await startDevice(client, b.deviceId);
    const onB2 = await cb.next("consent");
    expect((await decide(b.token, onB2.id, "deny")).status).toBe(200);
    expect(await ca.next("consent_resolved")).toMatchObject({ id: second.id });
    expect((await pending(a.token)).length).toBe(0);
    expect(onB.id).not.toBe(onB2.id);
    ca.ws.close(); cb.ws.close();
  });
});
