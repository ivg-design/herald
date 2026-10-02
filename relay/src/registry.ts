import { DurableObject } from "cloudflare:workers";
import { deviceIdValid, deviceToken, newDeviceId } from "./ids";
import { err, json, randomHex, safeEqual, sha256Hex } from "./util";

const CODE_TTL_MS = 10 * 60_000;
const ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789";
const MAX_PENDING_PER_IP = 3;
const MAX_PENDING_TOTAL = 60;
const FAILS_PER_10_MIN = 10;             // wrong codes per client address, so one noisy address cannot lock everyone else out
const DAY = 86_400_000;
const STALE_AUTO_DAYS = 30;              // a Mac that has not connected for this long is dropped by the daily alarm and by the lazy sweep
const STALE_REMOVABLE_DAYS = 7;          // another paired Mac may remove an entry only when it is this idle, same-named, or its credentials were rotated
const STARTS_PER_HOUR_TOTAL = 300;       // flood guard across all addresses (PAIR_STARTS_GLOBAL_PER_HOUR)

function newCode(): string {
  const b = crypto.getRandomValues(new Uint8Array(8));
  const c = [...b].map((x) => ALPHABET[x % ALPHABET.length]).join("");
  return c.slice(0, 4) + "-" + c.slice(4);
}
const normalize = (c: string) => c.toUpperCase().replace(/[^A-Z0-9]/g, "");

/** One global object: pairing codes and the list of paired devices. Never on the notification path. */
export class Registry extends DurableObject<Env> {
  constructor(ctx: DurableObjectState, env: Env) {
    super(ctx, env);
    ctx.storage.sql.exec(`
      CREATE TABLE IF NOT EXISTS codes (hash TEXT PRIMARY KEY, expires_at INTEGER NOT NULL, name TEXT, ip TEXT);
      CREATE TABLE IF NOT EXISTS devices (id TEXT PRIMARY KEY, name TEXT, created_at INTEGER NOT NULL, last_seen INTEGER);
      CREATE TABLE IF NOT EXISTS events (kind TEXT NOT NULL, at INTEGER NOT NULL, ip TEXT);
      CREATE TABLE IF NOT EXISTS clients (id TEXT PRIMARY KEY, name TEXT NOT NULL, redirect_uris TEXT NOT NULL, secret_hash TEXT, created_at INTEGER NOT NULL);
    `);
    try { ctx.storage.sql.exec("ALTER TABLE devices ADD COLUMN last_seen INTEGER"); } catch { /* already there */ }
    for (const t of ["codes", "events"]) {
      try { ctx.storage.sql.exec(`ALTER TABLE ${t} ADD COLUMN ip TEXT`); } catch { /* already there */ }
    }
  }

  private q<T extends Record<string, SqlStorageValue>>(sql: string, ...b: unknown[]): T[] {
    return this.ctx.storage.sql.exec<T>(sql, ...(b as SqlStorageValue[])).toArray();
  }


  // ---------- device hygiene

  private mailboxOf(id: string) { return this.env.MAILBOX.get(this.env.MAILBOX.idFromName(id)); }

  /** What a mailbox says about its Mac. A mailbox that was wiped (or never initialised) is reported as not valid. */
  private async statusOf(id: string): Promise<{ valid: boolean; online: boolean; lastSeen: number }> {
    try {
      const r = await this.mailboxOf(id).fetch("https://mailbox/internal/status", { method: "POST", body: "{}" });
      if (r.ok) return (await r.json()) as { valid: boolean; online: boolean; lastSeen: number };
    } catch { /* unreachable: treat as unknown */ }
    return { valid: true, online: false, lastSeen: 0 };
  }

  /** Drops the registry row and purges the mailbox (sockets closed, keys, queue, consents and audio deleted). */
  private async dropDevice(id: string) {
    this.q("DELETE FROM devices WHERE id = ?", id);
    try { await this.mailboxOf(id).fetch("https://mailbox/internal/wipe", { method: "POST", body: "{}" }); } catch { /* gone already */ }
  }

  private async credentialsValid(id: string): Promise<boolean> {
    return !!this.env.RELAY_SECRET && (await deviceIdValid(this.env.RELAY_SECRET, id));
  }

  /**
   * Removes entries nobody can use: credentials rotated (the id no longer verifies against RELAY_SECRET), mailbox wiped, or not
   * connected for 30 days. `keep` is never removed. Run lazily on every lookup that wants the list and by the daily alarm.
   */
  private async pruneStale(now: number, keep?: string): Promise<string[]> {
    const gone: string[] = [];
    const rows = this.q<{ id: string; created_at: number; last_seen: number | null }>("SELECT id, created_at, last_seen FROM devices");
    for (const d of rows) {
      if (d.id === keep) continue;
      let dead = !(await this.credentialsValid(d.id));
      if (!dead && now - (d.last_seen ?? d.created_at) > STALE_AUTO_DAYS * DAY) {
        // The registry only hears about connects and disconnects, so a socket that has stayed open for weeks looks idle here; ask.
        const st = await this.statusOf(d.id);
        dead = !st.valid || (!st.online && now - Math.max(st.lastSeen, d.last_seen ?? 0, d.created_at) > STALE_AUTO_DAYS * DAY);
      }
      if (dead) { await this.dropDevice(d.id); gone.push(d.id); }
    }
    return gone;
  }

  private async ensureAlarm() {
    if ((await this.ctx.storage.getAlarm()) == null) await this.ctx.storage.setAlarm(Date.now() + DAY);
  }

  async alarm(): Promise<void> {
    await this.pruneStale(Date.now());
    await this.ctx.storage.setAlarm(Date.now() + DAY);
  }

  /** The device list as one Mac may see it: every entry with its liveness, and whether this Mac may remove it. */
  private async describe(selfId: string | null, now: number) {
    const rows = this.q<{ id: string; name: string | null; created_at: number; last_seen: number | null }>("SELECT id, name, created_at, last_seen FROM devices ORDER BY created_at, rowid");
    const self = rows.find((d) => d.id === selfId);
    return Promise.all(rows.map(async (d) => {
      const st = await this.statusOf(d.id);
      const lastSeen = Math.max(st.lastSeen, d.last_seen ?? 0, d.created_at);
      const credentialsOk = await this.credentialsValid(d.id);
      const idle = !st.online && now - lastSeen > STALE_REMOVABLE_DAYS * DAY;
      const sameName = !!self && d.id !== self.id && !!self.name && self.name === d.name;
      const reason = d.id === selfId ? null : sameName ? "same_name" : !credentialsOk ? "credentials_rotated" : idle ? "idle" : null;
      return { id: d.id, name: d.name, online: st.online, lastSeenAt: new Date(lastSeen).toISOString(), createdAt: new Date(d.created_at).toISOString(),
        thisDevice: d.id === selfId, removable: reason !== null, ...(reason ? { removableReason: reason } : {}) };
    }));
  }

  async fetch(req: Request): Promise<Response> {
    const path = new URL(req.url).pathname;
    if (req.method !== "POST") return err(405, "method_not_allowed", "POST only");
    const now = Date.now();
    this.q("DELETE FROM codes WHERE expires_at < ?", now);
    this.q("DELETE FROM events WHERE at < ?", now - 3_600_000);
    await this.ensureAlarm();

    if (path === "/internal/seen") {
      const { deviceId } = (await req.json()) as { deviceId: string };
      this.q("UPDATE devices SET last_seen = ? WHERE id = ?", now, deviceId);
      return json(200, { ok: true });
    }
    // Device-authenticated hygiene, reached from the Mailbox with the caller's own id. A Mac can only touch entries that are
    // its own name, have rotated credentials, or have been idle for a week; never an active different Mac.
    if (path === "/internal/prune" || path === "/internal/list" || path === "/internal/delete") {
      const b = (await req.json()) as { deviceId: string; target?: string };
      if (!this.q("SELECT 1 FROM devices WHERE id = ?", b.deviceId).length) return err(404, "not_found", "this device is not in the registry");
      if (path === "/internal/delete") {
        const t = (await this.describe(b.deviceId, now)).find((d) => d.id === b.target);
        if (!t) return err(404, "not_found", "no such device");
        if (t.thisDevice) return err(400, "invalid_request", "use unpair to remove this Mac");
        if (!t.removable) return err(403, "not_removable", `only an entry with the same name, rotated credentials or no connection for ${STALE_REMOVABLE_DAYS} days can be removed by another Mac`);
        await this.dropDevice(t.id);
        return json(200, { removed: [t.id] });
      }
      let removed: string[] = [];
      if (path === "/internal/prune") {
        const self = this.q<{ name: string | null }>("SELECT name FROM devices WHERE id = ?", b.deviceId)[0];
        if (self.name) for (const d of this.q<{ id: string }>("SELECT id FROM devices WHERE name = ? AND id != ?", self.name, b.deviceId)) { await this.dropDevice(d.id); removed.push(d.id); }
        removed = removed.concat(await this.pruneStale(now, b.deviceId));
      }
      return json(200, { removed, devices: await this.describe(b.deviceId, now) });
    }
    if (path === "/internal/remove") {
      const { deviceId } = (await req.json()) as { deviceId: string };
      this.q("DELETE FROM devices WHERE id = ?", deviceId);
      return json(200, { ok: true });
    }

    let body: Record<string, unknown> = {};
    try { body = (await req.json()) as Record<string, unknown>; } catch { /* empty body is fine for start */ }

    // OAuth: dynamically registered clients (RFC 7591) and the device list the consent page chooses from.
    if (path === "/client/register") {
      const perHour = Number(this.env.REGISTER_PER_HOUR ?? "30") || 30;
      if (this.q<{ n: number }>("SELECT COUNT(*) AS n FROM events WHERE kind = 'register'")[0].n >= perHour) {
        return err(429, "rate_limited", "too many client registrations; try again later", { retryAfterSeconds: 3600 });
      }
      const c = body as { id: string; name: string; redirectUris: string[]; secretHash?: string | null };
      this.q("INSERT INTO events (kind, at) VALUES ('register', ?)", now);
      this.q("INSERT INTO clients (id, name, redirect_uris, secret_hash, created_at) VALUES (?, ?, ?, ?, ?)", c.id, c.name, JSON.stringify(c.redirectUris), c.secretHash ?? null, now);
      this.q("DELETE FROM clients WHERE id NOT IN (SELECT id FROM clients ORDER BY created_at DESC, rowid DESC LIMIT 200)");
      return json(201, { ok: true });
    }
    if (path === "/client/get") {
      const row = this.q<{ id: string; name: string; redirect_uris: string; secret_hash: string | null }>("SELECT id, name, redirect_uris, secret_hash FROM clients WHERE id = ?", String(body.id ?? ""))[0];
      if (!row) return err(404, "not_found", "unknown client");
      return json(200, { id: row.id, name: row.name, redirectUris: JSON.parse(row.redirect_uris), secretHash: row.secret_hash });
    }
    if (path === "/devices") {
      await this.pruneStale(now);
      const rows = this.q<{ id: string; name: string | null }>("SELECT id, name FROM devices ORDER BY created_at, rowid");
      if (!body.status) return json(200, { devices: rows });
      // With status: who is connected right now, and the Mac an agent without a `device=` should reach (connected first,
      // then most recently seen, never just the oldest entry).
      const info = await this.describe(null, now);
      const devices = rows.map((r) => { const i = info.find((x) => x.id === r.id)!; return { ...r, online: i.online, lastSeenAt: i.lastSeenAt }; });
      const best = [...devices].sort((a, b) => Number(b.online) - Number(a.online) || Date.parse(b.lastSeenAt) - Date.parse(a.lastSeenAt))[0];
      return json(200, { devices, preferred: best?.id ?? null });
    }
    // The client address, hashed (only ever compared, never stored in the clear), for per-address pairing limits.
    const ip = (await sha256Hex("ip:" + (req.headers.get("x-client-ip") || "unknown"))).slice(0, 16);

    if (path === "/pair/start") {
      const secret = this.env.PAIRING_SECRET;
      if (secret && !safeEqual(await sha256Hex(secret), await sha256Hex(String(req.headers.get("x-pairing-secret") ?? "")))) {
        return err(401, "unauthorized", "this relay requires its pairing secret (X-Pairing-Secret)");
      }
      const max = Number(this.env.MAX_DEVICES ?? "5") || 5;
      const startName = typeof body.deviceName === "string" ? body.deviceName.slice(0, 60) : null;
      const replaces = startName ? this.q<{ n: number }>("SELECT COUNT(*) AS n FROM devices WHERE name = ?", startName)[0].n : 0; // pairing again under the same name replaces
      if (this.q<{ n: number }>("SELECT COUNT(*) AS n FROM devices")[0].n - replaces >= max) {
        return err(403, "device_limit", `this relay already has ${max} paired Macs`);
      }
      if (this.q<{ n: number }>("SELECT COUNT(*) AS n FROM events WHERE kind = 'start' AND ip = ?", ip)[0].n >= (Number(this.env.PAIR_STARTS_PER_HOUR ?? "6") || 6)) {
        return err(429, "rate_limited", "too many pairing attempts from this address; try again in an hour", { retryAfterSeconds: 3600 });
      }
      if (this.q<{ n: number }>("SELECT COUNT(*) AS n FROM events WHERE kind = 'start'")[0].n >= (Number(this.env.PAIR_STARTS_GLOBAL_PER_HOUR ?? STARTS_PER_HOUR_TOTAL) || STARTS_PER_HOUR_TOTAL)) {
        return err(429, "rate_limited", "this relay is receiving too many pairing attempts; try again in an hour", { retryAfterSeconds: 3600 });
      }
      if (this.q<{ n: number }>("SELECT COUNT(*) AS n FROM codes WHERE ip = ?", ip)[0].n >= MAX_PENDING_PER_IP
        || this.q<{ n: number }>("SELECT COUNT(*) AS n FROM codes")[0].n >= MAX_PENDING_TOTAL) {
        return err(429, "rate_limited", "pairing codes are already waiting; use one or wait 10 minutes", { retryAfterSeconds: 600 });
      }
      const code = newCode();
      const name = typeof body.deviceName === "string" ? body.deviceName.slice(0, 60) : null;
      this.q("INSERT INTO codes (hash, expires_at, name, ip) VALUES (?, ?, ?, ?)", await sha256Hex(normalize(code)), now + CODE_TTL_MS, name, ip);
      this.q("INSERT INTO events (kind, at, ip) VALUES ('start', ?, ?)", now, ip);
      return json(201, { code, expiresInSeconds: CODE_TTL_MS / 1000 });
    }

    if (path === "/pair") {
      if (this.q<{ n: number }>("SELECT COUNT(*) AS n FROM events WHERE kind = 'fail' AND ip = ? AND at > ?", ip, now - 10 * 60_000)[0].n >= FAILS_PER_10_MIN) {
        return err(429, "rate_limited", "too many wrong codes from this address; try again later", { retryAfterSeconds: 600 });
      }
      const code = typeof body.code === "string" ? normalize(body.code) : "";
      const hash = await sha256Hex(code);
      const row = code.length === 8 ? this.q<{ name: string | null }>("SELECT name FROM codes WHERE hash = ?", hash)[0] : undefined;
      if (!row) {
        this.q("INSERT INTO events (kind, at, ip) VALUES ('fail', ?, ?)", now, ip);
        return err(403, "bad_code", "that pairing code is wrong, used or expired");
      }
      this.q("DELETE FROM codes WHERE hash = ?", hash); // one time
      const deviceId = await newDeviceId(this.env.RELAY_SECRET);
      const secret = randomHex(32);
      const stub = this.env.MAILBOX.get(this.env.MAILBOX.idFromName(deviceId));
      await stub.fetch("https://mailbox/internal/init", { method: "POST", body: JSON.stringify({ tokenHash: await sha256Hex(secret), deviceId }) });
      const name = typeof body.deviceName === "string" ? body.deviceName.slice(0, 60) : row.name;
      this.q("INSERT INTO devices (id, name, created_at, last_seen) VALUES (?, ?, ?, ?)", deviceId, name, now, now);
      // The same Mac pairing again (after an unpair, a reinstall, or a redeploy that rotated the secrets) replaces its old entry
      // instead of sitting next to it: a dead device first in the list is how consent requests used to go nowhere.
      if (name) for (const d of this.q<{ id: string }>("SELECT id FROM devices WHERE name = ? AND id != ?", name, deviceId)) await this.dropDevice(d.id);
      return json(200, { deviceId, deviceToken: deviceToken(deviceId, secret) });
    }
    return err(404, "not_found", "no such endpoint");
  }
}
