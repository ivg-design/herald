import { DurableObject } from "cloudflare:workers";
import { deviceToken, newDeviceId } from "./ids";
import { err, json, randomHex, safeEqual, sha256Hex } from "./util";

const CODE_TTL_MS = 10 * 60_000;
const ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789";
const MAX_PENDING_PER_IP = 3;
const MAX_PENDING_TOTAL = 60;
const FAILS_PER_10_MIN = 10;             // wrong codes per client address, so one noisy address cannot lock everyone else out
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
      CREATE TABLE IF NOT EXISTS devices (id TEXT PRIMARY KEY, name TEXT, created_at INTEGER NOT NULL);
      CREATE TABLE IF NOT EXISTS events (kind TEXT NOT NULL, at INTEGER NOT NULL, ip TEXT);
      CREATE TABLE IF NOT EXISTS clients (id TEXT PRIMARY KEY, name TEXT NOT NULL, redirect_uris TEXT NOT NULL, secret_hash TEXT, created_at INTEGER NOT NULL);
    `);
    for (const t of ["codes", "events"]) {
      try { ctx.storage.sql.exec(`ALTER TABLE ${t} ADD COLUMN ip TEXT`); } catch { /* already there */ }
    }
  }

  private q<T extends Record<string, SqlStorageValue>>(sql: string, ...b: unknown[]): T[] {
    return this.ctx.storage.sql.exec<T>(sql, ...(b as SqlStorageValue[])).toArray();
  }

  async fetch(req: Request): Promise<Response> {
    const path = new URL(req.url).pathname;
    if (req.method !== "POST") return err(405, "method_not_allowed", "POST only");
    const now = Date.now();
    this.q("DELETE FROM codes WHERE expires_at < ?", now);
    this.q("DELETE FROM events WHERE at < ?", now - 3_600_000);

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
      return json(200, { devices: this.q<{ id: string; name: string | null }>("SELECT id, name FROM devices ORDER BY created_at, rowid") });
    }
    // The client address, hashed (only ever compared, never stored in the clear), for per-address pairing limits.
    const ip = (await sha256Hex("ip:" + (req.headers.get("x-client-ip") || "unknown"))).slice(0, 16);

    if (path === "/pair/start") {
      const secret = this.env.PAIRING_SECRET;
      if (secret && !safeEqual(await sha256Hex(secret), await sha256Hex(String(req.headers.get("x-pairing-secret") ?? "")))) {
        return err(401, "unauthorized", "this relay requires its pairing secret (X-Pairing-Secret)");
      }
      const max = Number(this.env.MAX_DEVICES ?? "300") || 300;
      if (this.q<{ n: number }>("SELECT COUNT(*) AS n FROM devices")[0].n >= max) {
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
      this.q("INSERT INTO devices (id, name, created_at) VALUES (?, ?, ?)", deviceId, name, now);
      return json(200, { deviceId, deviceToken: deviceToken(deviceId, secret) });
    }
    return err(404, "not_found", "no such endpoint");
  }
}
