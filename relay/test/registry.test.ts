import { describe, expect, it } from "vitest";
import { env, runInDurableObject } from "cloudflare:test";
import { auth, connect, f } from "./helpers";
import { newDeviceId } from "../src/ids";

const j = async (r: Response) => (await r.json()) as any;
const DAY = 86_400_000;
const GRANT = "urn:ietf:params:oauth:grant-type:device_code";
const reg = () => env.REGISTRY.get(env.REGISTRY.idFromName("registry"));
const form = (o: Record<string, string>) => ({ method: "POST", headers: { "content-type": "application/x-www-form-urlencoded" }, body: new URLSearchParams(o).toString() });

async function pairNamed(deviceName: string): Promise<{ deviceId: string; token: string }> {
  const s = await f("/v1/pair/start", { method: "POST", body: JSON.stringify({ deviceName }) });
  const { code } = await j(s);
  const p = await f("/v1/pair", { method: "POST", body: JSON.stringify({ code, deviceName }) });
  expect(p.status).toBe(200);
  const b = await j(p);
  return { deviceId: b.deviceId, token: b.deviceToken };
}
const ids = async () => ((await j(await reg().fetch("https://registry/devices", { method: "POST", body: "{}" }))).devices as { id: string }[]).map((d) => d.id);
const sql = (q: string, ...b: unknown[]) => runInDurableObject(reg(), async (_i, state) => { state.storage.sql.exec(q, ...(b as any[])); });
async function plant(name: string | null, ageDays: number, secret = "test-relay-secret"): Promise<string> {
  const id = await newDeviceId(secret);
  const t = Date.now() - ageDays * DAY;
  await sql("INSERT INTO devices (id, name, created_at, last_seen) VALUES (?, ?, ?, ?)", id, name, t, t);
  return id;
}
async function deviceClient() {
  const r = await f("/register", { method: "POST", body: JSON.stringify({ client_name: "Cloud agent", grant_types: [GRANT] }) });
  return ((await j(r)).client_id) as string;
}

describe("registry hygiene", () => {
  it("unpair removes the device from the registry and purges its mailbox", async () => {
    const a = await pairNamed("Unpair Mac");
    const key = (await j(await f("/v1/device/keys", { method: "POST", headers: auth(a.token), body: JSON.stringify({ name: "bot", client: "claude" }) }))).key;
    expect(await ids()).toContain(a.deviceId);
    expect((await f("/v1/device", { method: "DELETE", headers: auth(a.token) })).status).toBe(200);
    expect(await ids()).not.toContain(a.deviceId);
    expect((await f("/v1/notify", { method: "POST", headers: auth(key), body: JSON.stringify({ title: "x" }) })).status).toBe(401);
    const st = await j(await env.MAILBOX.get(env.MAILBOX.idFromName(a.deviceId)).fetch("https://mailbox/internal/status", { method: "POST", body: "{}" }));
    expect(st.valid).toBe(false);
  });

  it("pairing again under the same device name replaces the old entry and purges its mailbox", async () => {
    const old = await pairNamed("Replace Mac");
    const oldKey = (await j(await f("/v1/device/keys", { method: "POST", headers: auth(old.token), body: JSON.stringify({ name: "bot", client: "claude" }) }))).key;
    const fresh = await pairNamed("Replace Mac");
    const list = await ids();
    expect(list).toContain(fresh.deviceId);
    expect(list).not.toContain(old.deviceId);
    expect((await f("/v1/device/info", { headers: auth(old.token) })).status).toBe(401);
    expect((await f("/v1/notify", { method: "POST", headers: auth(oldKey), body: JSON.stringify({ title: "x" }) })).status).toBe(401);
    expect((await f("/v1/device/info", { headers: auth(fresh.token) })).status).toBe(200);
  });

  it("a different name is a different Mac and is kept", async () => {
    const a = await pairNamed("Keep A"), b = await pairNamed("Keep B");
    const list = await ids();
    expect(list).toContain(a.deviceId);
    expect(list).toContain(b.deviceId);
  });

  it("the lazy sweep drops devices idle for 30 days and those whose credentials were rotated", async () => {
    const idle = await plant("Idle Mac", 40);
    const rotated = await plant("Rotated Mac", 1, "an-older-relay-secret");
    const recent = await plant("Recent Mac", 3);
    const list = await ids();
    expect(list).not.toContain(idle);
    expect(list).not.toContain(rotated);
    expect(list).toContain(recent);
  });

  it("the daily alarm prunes the same way", async () => {
    const idle = await plant("Alarm Idle", 45);
    const rotated = await plant("Alarm Rotated", 0, "an-older-relay-secret");
    await (runInDurableObject as any)(reg(), async (inst: any) => { await inst.alarm(); });
    const rows = (await (runInDurableObject as any)(reg(), async (_i: any, state: any) => state.storage.sql.exec("SELECT id FROM devices").toArray().map((r: any) => r.id))) as string[];
    expect(rows).not.toContain(idle);
    expect(rows).not.toContain(rotated);
    expect(await (runInDurableObject as any)(reg(), async (_i: any, state: any) => await state.storage.getAlarm())).not.toBeNull();
  });

  it("a long-open socket keeps an old registry row alive", async () => {
    const d = await pairNamed("Long Open");
    const c = await connect(d.token);
    await sql("UPDATE devices SET last_seen = ?, created_at = ? WHERE id = ?", Date.now() - 60 * DAY, Date.now() - 60 * DAY, d.deviceId);
    expect(await ids()).toContain(d.deviceId);
    c.ws.close();
  });

  it("POST /v1/device/prune drops same-name siblings and stale entries, never an active different Mac", async () => {
    const me = await pairNamed("Prune Me");
    const other = await pairNamed("Prune Other");
    const twin = await plant("Prune Me", 0);       // a leftover with my name (valid credentials)
    const idle = await plant("Prune Idle", 40);
    const r = await f("/v1/device/prune", { method: "POST", headers: auth(me.token), body: "{}" });
    expect(r.status).toBe(200);
    const b = await j(r);
    expect(b.removed).toContain(twin);
    expect(b.removed).toContain(idle);
    expect(b.removed).not.toContain(other.deviceId);
    expect(b.removed).not.toContain(me.deviceId);
    expect(b.devices.find((d: any) => d.id === me.deviceId)).toMatchObject({ name: "Prune Me", thisDevice: true });
    const list = await ids();
    expect(list).toContain(other.deviceId);
    expect(list).toContain(me.deviceId);
  });

  it("prune and the device list need the device token", async () => {
    expect((await f("/v1/device/prune", { method: "POST", body: "{}" })).status).toBe(401);
    expect((await f("/v1/device/devices")).status).toBe(401);
    const d = await pairNamed("Agent key Mac");
    const key = (await j(await f("/v1/device/keys", { method: "POST", headers: auth(d.token), body: JSON.stringify({ name: "bot", client: "claude" }) }))).key;
    expect((await f("/v1/device/prune", { method: "POST", headers: auth(key), body: "{}" })).status).toBe(403);
    expect((await f("/v1/device/devices", { headers: auth(key) })).status).toBe(403);
  });

  it("lists the Macs and lets a Mac remove only same-name, rotated or idle entries", async () => {
    const me = await pairNamed("List Me");
    const active = await pairNamed("List Active");
    const idle = await plant("List Idle", 10);
    const twin = await plant("List Me", 0);
    const list = await j(await f("/v1/device/devices", { headers: auth(me.token) }));
    const by = (id: string) => list.devices.find((d: any) => d.id === id);
    expect(by(me.deviceId)).toMatchObject({ thisDevice: true, removable: false });
    expect(by(active.deviceId)).toMatchObject({ thisDevice: false, removable: false });
    expect(by(idle)).toMatchObject({ removable: true, removableReason: "idle" });
    expect(by(twin)).toMatchObject({ removable: true, removableReason: "same_name" });

    const del = (id: string) => f("/v1/device/devices/" + id, { method: "DELETE", headers: auth(me.token) });
    const refused = await del(active.deviceId);
    expect(refused.status).toBe(403);
    expect((await j(refused)).error).toBe("not_removable");
    expect((await del(me.deviceId)).status).toBe(400);
    expect((await del(idle)).status).toBe(200);
    expect((await del(twin)).status).toBe(200);
    const list2 = await ids();
    expect(list2).toContain(active.deviceId);
    expect(list2).not.toContain(idle);
  });
});

describe("device selection without device=", () => {
  it("targets the connected Mac, not the first entry, and says which one", async () => {
    const dead = await pairNamed("Sel Dead");     // paired first, never connected
    const live = await pairNamed("Sel Live");
    const c = await connect(live.token);
    const clientId = await deviceClient();
    const r = await f("/device_authorization", form({ client_id: clientId, scope: "notify" }));
    expect(r.status).toBe(200);
    const d = await j(r);
    expect(d.device_name).toBe("Sel Live");
    expect(d.device_online).toBe(true);
    expect(d.device_count).toBeGreaterThan(1);
    expect(d.device_code).toContain(live.deviceId);
    expect(d.device_code).not.toContain(dead.deviceId);
    const ask = await c.next("consent");
    expect(ask).toBeTruthy();
    c.ws.close();
    for (const t of [live.token, dead.token]) await f("/v1/device", { method: "DELETE", headers: auth(t) });
  });

  it("falls back to the most recently seen Mac when none is connected", async () => {
    const older = await pairNamed("Seen Older");
    const newer = await pairNamed("Seen Newer");
    // Every other device in the registry is older than these two.
    await sql("DELETE FROM devices WHERE id NOT IN (?, ?)", older.deviceId, newer.deviceId);
    await sql("UPDATE devices SET last_seen = ?, created_at = ? WHERE id = ?", Date.now() - 1000, Date.now() - 1000, older.deviceId);
    await sql("UPDATE devices SET last_seen = ?, created_at = ? WHERE id = ?", Date.now() - 500_000, Date.now() - 500_000, newer.deviceId);
    const clientId = await deviceClient();
    const d = await j(await f("/device_authorization", form({ client_id: clientId, scope: "notify" })));
    expect(d.device_name).toBe("Seen Older");
  });

  it("an explicit device= still wins, and /authorize names the Mac that will show the banner", async () => {
    const list = (await j(await reg().fetch("https://registry/devices", { method: "POST", body: JSON.stringify({ status: true }) }))).devices as { id: string; name: string }[];
    const idx = list.findIndex((x) => x.name === "Seen Newer") + 1;
    const clientId = await deviceClient();
    const d = await j(await f("/device_authorization", form({ client_id: clientId, scope: "notify", device: String(idx) })));
    expect(d.device_name).toBe("Seen Newer");
    expect(d.device_index).toBe(idx);

    const reg1 = await j(await f("/register", { method: "POST", body: JSON.stringify({ client_name: "Web agent", redirect_uris: ["https://agent.test/cb"] }) }));
    const challenge = "A".repeat(43);
    const q = (extra: Record<string, string> = {}) => "/authorize?" + new URLSearchParams({ response_type: "code", client_id: reg1.client_id, redirect_uri: "https://agent.test/cb", code_challenge: challenge, code_challenge_method: "S256", ...extra });
    const page = await (await f(q())).text();
    expect(page).toContain("Seen Older");
    expect(page).toContain("Not this Mac?");
    expect(await (await f(q({ device: String(idx) }))).text()).toContain("Seen Newer");
  });
});
