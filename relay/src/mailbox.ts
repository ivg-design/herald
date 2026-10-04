import { DurableObject } from "cloudflare:workers";
import { agentKey, oauthToken, parseOAuthSecret, parseToken, type Principal } from "./ids";
import { DAY_MS, bearer, err, hmacHex, json, randomHex, safeEqual, sha256Hex } from "./util";
import { limitsFor } from "./limits";
import { ICON_BODY_ALLOWANCE, validateNotification } from "./validate";

export const RATE_WINDOW_MS = 10 * 60 * 1000;
export const MAX_LONG_POLL_S = 60;
const MAX_KEYS = 20;
// Herald pings every 5 minutes (auto-response, free), so "online" tolerates two missed pings.
const ONLINE_WINDOW_MS = 11 * 60_000;
export const MAX_AUDIO_BYTES = 1024 * 1024;
export const AUDIO_URL_TTL_S = 3600;
// Per-device daily and queue limits live in ./limits.ts (defaults for the shared hosted relay, Worker vars to change them).
export const READ_LIMIT = 600;          // receipt / reply reads per 10 min per key

type KeyRow = {
  id: string; name: string; client: string; scope: string; hash: string; created_at: number; revoked_at: number | null; last_used_at: number | null;
  kind: string | null; client_name: string | null; oauth_client: string | null;
}
type OAuthReq = {
  id: string; client_id: string; client_name: string; redirect_uri: string; challenge: string; state: string | null; scope: string; resource: string;
  user_code: string; status: string; attempts: number; code: string | null; code_hash: string | null; key_id: string | null;
  created_at: number; expires_at: number; decided_at: number | null; redeemed_at: number | null;
  flow: string | null; device_hash: string | null; device_user_code: string | null; last_poll: number | null; poll_interval: number | null;
  announced_at: number | null;
}
type OAuthTok = { hash: string; kind: string; key_id: string; client_id: string; resource: string; family: string; expires_at: number; created_at: number; used_at: number | null }

export const OAUTH_REQUEST_TTL_MS = 10 * 60_000;
export const OAUTH_CODE_TTL_MS = 5 * 60_000;
export const DEVICE_TTL_S = 600;
export const DEVICE_INTERVAL_S = 5;
/** Consonants only: no vowels (no words), no 0/O/1/I/L/5/S/U/V ambiguity beyond what is left out here. */
const USER_CODE_ALPHABET = "BCDFGHJKMNPQRTWXZ";
export const DEVICE_GRANT = "urn:ietf:params:oauth:grant-type:device_code";
/**
 * A connector approved in Herald is a durable record (its `keys` row): it works until it is revoked there. Its tokens therefore never
 * expire and are never rotated. `expires_in` is still reported, as ten years, for clients that insist on the field.
 */
export const OAUTH_ACCESS_TTL_S = 10 * 365 * 86400;
const NEVER = 253402300799000; // 9999-12-31, stored in the legacy `expires_at` column
const ACCESS_TOKENS_KEPT_PER_KEY = 50;
const OAUTH_MAX_PENDING = 3;
const OAUTH_BEGINS_PER_HOUR = 12;
const OAUTH_CODE_ATTEMPTS = 5;
type NoteRow = {
  rid: string; key_id: string; nid: string; payload: string; expect_reply: number; created_at: number;
  sent_at: number | null; acked_at: number | null; displayed_at: number | null; spoken_at: number | null;
  replied_at: number | null; reply: string | null; transcript: string | null; audio_key: string | null;
  audio_seconds: number | null; audio_bytes: number | null; suppressed_reason: string | null; suppressed_scope: string | null;
}

async function s256(v: string): Promise<string> {
  const d = new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(v)));
  return btoa(String.fromCharCode(...d)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}
const sameResource = (a: string, b: string) => a.replace(/\/+$/, "") === b.replace(/\/+$/, "");

const iso = (t: number | null) => (t == null ? undefined : new Date(t).toISOString());

/** One paired Mac: its tokens, agent keys, notification queue, receipts and the socket Herald holds open. */
export class Mailbox extends DurableObject<Env> {
  private waiters = new Map<string, Set<() => void>>();

  constructor(ctx: DurableObjectState, env: Env) {
    super(ctx, env);
    this.ensureSchema();
    ctx.setWebSocketAutoResponse(new WebSocketRequestResponsePair("ping", "pong"));
  }

  // ---------- storage helpers

  private ensureSchema() {
    this.ctx.storage.sql.exec(`
      CREATE TABLE IF NOT EXISTS meta (k TEXT PRIMARY KEY, v TEXT NOT NULL);
      CREATE TABLE IF NOT EXISTS keys (id TEXT PRIMARY KEY, name TEXT NOT NULL, client TEXT NOT NULL, scope TEXT NOT NULL,
        hash TEXT NOT NULL, created_at INTEGER NOT NULL, revoked_at INTEGER, last_used_at INTEGER);
      CREATE TABLE IF NOT EXISTS notes (rid TEXT PRIMARY KEY, key_id TEXT NOT NULL, nid TEXT NOT NULL, payload TEXT NOT NULL,
        expect_reply INTEGER NOT NULL DEFAULT 0, created_at INTEGER NOT NULL, sent_at INTEGER, acked_at INTEGER,
        displayed_at INTEGER, spoken_at INTEGER, replied_at INTEGER, reply TEXT, transcript TEXT, audio_key TEXT, audio_seconds REAL, audio_bytes INTEGER,
        suppressed_reason TEXT, suppressed_scope TEXT);
      CREATE UNIQUE INDEX IF NOT EXISTS notes_key_nid ON notes (key_id, nid);
      CREATE TABLE IF NOT EXISTS rate (key_id TEXT NOT NULL, at INTEGER NOT NULL);
      CREATE TABLE IF NOT EXISTS oauth_requests (id TEXT PRIMARY KEY, client_id TEXT NOT NULL, client_name TEXT NOT NULL, redirect_uri TEXT NOT NULL,
        challenge TEXT NOT NULL, state TEXT, scope TEXT NOT NULL, resource TEXT NOT NULL, user_code TEXT NOT NULL, status TEXT NOT NULL,
        attempts INTEGER NOT NULL DEFAULT 0, code TEXT, code_hash TEXT, key_id TEXT, created_at INTEGER NOT NULL, expires_at INTEGER NOT NULL,
        decided_at INTEGER, redeemed_at INTEGER);
      CREATE TABLE IF NOT EXISTS oauth_tokens (hash TEXT PRIMARY KEY, kind TEXT NOT NULL, key_id TEXT NOT NULL, client_id TEXT NOT NULL, resource TEXT NOT NULL,
        family TEXT NOT NULL, expires_at INTEGER NOT NULL, created_at INTEGER NOT NULL, used_at INTEGER);
    `);
    for (const col of ["kind TEXT", "client_name TEXT", "oauth_client TEXT"]) {
      try { this.ctx.storage.sql.exec(`ALTER TABLE keys ADD COLUMN ${col}`); } catch { /* already there */ }
    }
    // The device flow (RFC 8628) shares the table: flow = 'device', the hash of the device_code, the code a person matches
    // ("BDFGHJKM"), when it was last polled and the interval it is held to.
    // announced_at: when Herald was last sent this request as a banner-worthy "consent" (a reconnect re-sends it flagged `redelivered`).
    for (const col of ["flow TEXT", "device_hash TEXT", "device_user_code TEXT", "last_poll INTEGER", "poll_interval INTEGER", "announced_at INTEGER"]) {
      try { this.ctx.storage.sql.exec(`ALTER TABLE oauth_requests ADD COLUMN ${col}`); } catch { /* already there */ }
    }
  }


  /** This device's limits (per device: each Mac has its own mailbox and its own counters). */
  private get lim() { return limitsFor(this.env); }

  private sql<T extends Record<string, SqlStorageValue>>(q: string, ...b: unknown[]): T[] {
    return this.ctx.storage.sql.exec<T>(q, ...(b as SqlStorageValue[])).toArray();
  }
  private getMeta(k: string): string | undefined {
    return this.sql<{ v: string }>("SELECT v FROM meta WHERE k = ?", k)[0]?.v;
  }
  private setMeta(k: string, v: string) {
    this.sql("INSERT INTO meta (k, v) VALUES (?, ?) ON CONFLICT(k) DO UPDATE SET v = excluded.v", k, v);
  }
  private note(rid: string): NoteRow | undefined {
    return this.sql<NoteRow>("SELECT * FROM notes WHERE rid = ?", rid)[0];
  }
  private noteByNid(keyId: string, nid: string): NoteRow | undefined {
    return this.sql<NoteRow>("SELECT * FROM notes WHERE key_id = ? AND nid = ?", keyId, nid)[0];
  }

  // ---------- auth

  private async authenticate(req: Request, want: "device" | "agent"): Promise<{ p: Principal; key?: KeyRow } | Response> {
    const token = bearer(req);
    const p = token ? parseToken(token) : null;
    if (!token || !p) return err(401, "unauthorized", "missing or malformed bearer token");
    const have = p.kind === "oauth" ? "agent" : p.kind;
    if (have !== want) {
      return err(403, "wrong_credential", want === "device"
        ? "agent keys cannot use device endpoints"
        : "the device token cannot be used on agent endpoints; use an agent key");
    }
    if (p.kind === "device") {
      const hash = this.getMeta("device_hash");
      if (!hash || !safeEqual(hash, await sha256Hex(p.secret))) return err(401, "unauthorized", "invalid device token");
      return { p };
    }
    let row: KeyRow | undefined;
    let good: boolean;
    if (p.kind === "oauth") {
      const t = this.sql<OAuthTok>("SELECT * FROM oauth_tokens WHERE hash = ? AND kind = 'access'", await sha256Hex(p.secret))[0];
      // No expiry check: the approval (the key row) decides, and `row.revoked_at` below ends it. Tokens issued before this rule keep working.
      row = t ? this.sql<KeyRow>("SELECT * FROM keys WHERE id = ?", t.key_id)[0] : undefined;
      good = !!row && !row.revoked_at;
    } else {
      row = this.sql<KeyRow>("SELECT * FROM keys WHERE id = ?", p.keyId)[0];
      good = !!row && !row.revoked_at && row.kind !== "oauth" && safeEqual(row.hash, await sha256Hex(p.secret));
    }
    if (!good || !row) return err(401, "unauthorized", p.kind === "oauth" ? "invalid, expired or revoked access token" : "invalid or revoked agent key");
    if (row.scope !== "notify") return err(403, "scope", "this key has no notify scope");
    if (!row.last_used_at || Date.now() - row.last_used_at > 10 * 60_000) this.sql("UPDATE keys SET last_used_at = ? WHERE id = ?", Date.now(), row.id);
    return { p, key: row };
  }

  // ---------- routing

  async fetch(req: Request): Promise<Response> {
    const url = new URL(req.url);
    const path = url.pathname;
    const m = req.method;
    try {
      if (path === "/internal/init" && m === "POST") return this.internalInit(req);
      if (path === "/internal/wipe" && m === "POST") return this.internalWipe();
      if (path === "/internal/status" && m === "POST") return json(200, { valid: !!this.getMeta("device_hash"), online: this.online(), lastSeen: this.lastSeenMs() });
      if (path.startsWith("/internal/oauth/") && m === "POST") return this.oauthInternal(path.slice("/internal/oauth/".length), req);

      if (path.startsWith("/v1/device")) {
        const a = await this.authenticate(req, "device");
        if (a instanceof Response) return a;
        if (path !== "/v1/device/usage" && path !== "/v1/device/stream") this.bump("requests");
        if (path === "/v1/device/stream" && m === "GET") return this.stream(req);
        if (path === "/v1/device/receipt" && m === "POST") return this.httpReceipt(req);
        if (path === "/v1/device/status" && m === "POST") return this.httpStatus(req);
        if (path === "/v1/device/info" && m === "GET") return json(200, this.info());
        if (path === "/v1/device/usage" && m === "GET") return json(200, this.usage());
        if (path === "/v1/device/reply" && m === "POST") return this.httpReceipt(req, "replied");
        const am = /^\/v1\/device\/reply\/(r_[0-9a-f]{24})\/audio$/.exec(path);
        if (am && m === "PUT") return this.putAudio(req, am[1]);
        if (path === "/v1/device/consents" && m === "GET") return json(200, { consents: this.consentList() });
        if (path === "/v1/device/consent" && m === "POST") return this.deviceConsent(req);
        if (path === "/v1/device/keys" && m === "GET") return json(200, { keys: this.listKeys() });
        if (path === "/v1/device/keys" && m === "POST") return this.createKey(req, a.p as Extract<Principal, { kind: "device" }>);
        const km = /^\/v1\/device\/keys\/([0-9a-f]{8})$/.exec(path);
        if (km && m === "DELETE") return this.revokeKey(km[1], url.searchParams.get("purge") === "1");
        if (path === "/v1/device" && m === "DELETE") return this.unpair();
        // The Macs on this relay. A Mac may list them, drop its own same-name or stale siblings (prune), and remove one entry
        // that is same-name, rotated or idle. The Registry enforces that; a different active Mac is never removable from here.
        if (path === "/v1/device/devices" && m === "GET") return this.registryCall("/internal/list", {});
        if (path === "/v1/device/prune" && m === "POST") return this.registryCall("/internal/prune", {});
        const dm = /^\/v1\/device\/devices\/([0-9a-f]{48})$/.exec(path);
        if (dm && m === "DELETE") return this.registryCall("/internal/delete", { target: dm[1] });
        return err(404, "not_found", "no such device endpoint");
      }

      const a = await this.authenticate(req, "agent");
      if (a instanceof Response) return a;
      const key = a.key!;
      this.bump("requests");
      const guard = this.budgetGuard();
      if (guard) return guard;
      if (path !== "/v1/status") {
        const limited = this.readLimit(key, path === "/v1/notify");
        if (limited) return limited;
      }
      if (path === "/v1/notify" && m === "POST") return this.notify(req, key);
      if (path === "/v1/status" && m === "GET") return json(200, this.agentStatus());
      let r = /^\/v1\/receipts\/([^/]+)$/.exec(path);
      if (r && m === "GET") return this.getReceipt(key, decodeURIComponent(r[1]), url.origin);
      r = /^\/v1\/replies\/([^/]+)$/.exec(path);
      if (r && m === "GET") return this.getReply(key, decodeURIComponent(r[1]), url.searchParams.get("wait"), url.origin);
      return err(404, "not_found", "no such endpoint");
    } catch (e) {
      console.error("mailbox error", e);
      return err(500, "internal", "internal error");
    }
  }

  // ---------- pairing (internal: only the Registry reaches these through the namespace binding)

  private async internalInit(req: Request): Promise<Response> {
    const { tokenHash, deviceId } = (await req.json()) as { tokenHash: string; deviceId: string };
    this.setMeta("device_hash", tokenHash);
    this.setMeta("device_id", deviceId);
    this.setMeta("paired_at", String(Date.now()));
    return json(200, { ok: true });
  }

  private async internalWipe(): Promise<Response> {
    for (const ws of this.ctx.getWebSockets()) { try { ws.close(4001, "unpaired"); } catch { /* gone */ } }
    const id = this.getMeta("device_id");
    if (id) {
      const list = await this.env.AUDIO.list({ prefix: id + "/" });
      if (list.objects.length) await this.env.AUDIO.delete(list.objects.map((o) => o.key));
    }
    await this.ctx.storage.deleteAlarm();
    await this.ctx.storage.deleteAll();
    this.ensureSchema();
    return json(200, { ok: true });
  }

  // ---------- agent keys

  private listKeys() {
    return this.sql<KeyRow>("SELECT * FROM keys ORDER BY created_at").map((k) => ({
      id: k.id, name: k.name, client: k.client, scope: k.scope, kind: k.kind ?? "static", ...(k.client_name ? { displayName: k.client_name } : {}), createdAt: iso(k.created_at),
      lastUsedAt: iso(k.last_used_at), revokedAt: iso(k.revoked_at),
    }));
  }

  private async createKey(req: Request, p: Extract<Principal, { kind: "device" }>): Promise<Response> {
    let b: Record<string, unknown>;
    try { b = (await req.json()) as Record<string, unknown>; } catch { return err(400, "invalid_request", "body must be JSON"); }
    const extra = Object.keys(b).filter((k) => !["name", "client", "scope"].includes(k));
    if (extra.length) return err(400, "forbidden_fields", `rejected fields: ${extra.join(", ")}`, { fields: extra });
    const scope = b.scope ?? "notify";
    if (scope !== "notify") return err(400, "scope_not_allowed", 'the only scope is "notify"');
    const name = typeof b.name === "string" ? b.name.trim().toLowerCase() : "";
    if (!/^[a-z0-9][a-z0-9-]{0,31}$/.test(name)) return err(400, "invalid_request", "name must be 1-32 characters: a-z, 0-9 and -");
    const client = b.client === undefined ? "other" : b.client;
    if (client !== "claude" && client !== "codex" && client !== "other") return err(400, "invalid_request", 'client must be "claude", "codex" or "other"');
    const rows = this.sql<KeyRow>("SELECT * FROM keys WHERE revoked_at IS NULL");
    if (rows.some((k) => k.name === name)) return err(409, "name_taken", `a key named ${name} already exists`);
    if (rows.length >= MAX_KEYS) return err(429, "too_many_keys", `at most ${MAX_KEYS} active keys`);
    const id = randomHex(4), secret = randomHex(32), now = Date.now();
    this.sql("INSERT INTO keys (id, name, client, scope, hash, created_at, kind) VALUES (?, ?, ?, 'notify', ?, ?, 'static')", id, name, client, await sha256Hex(secret), now);
    return json(201, { id, name, client, scope: "notify", kind: "static", key: agentKey(p.deviceId, id, secret), createdAt: iso(now) });
  }

  /** `purge` (Herald's relay test, a throw-away key) forgets the key altogether: its row, its tokens and what it sent. */
  private revokeKey(id: string, purge = false): Response {
    const row = this.sql<KeyRow>("SELECT * FROM keys WHERE id = ?", id)[0];
    if (!row) return err(404, "not_found", "no such key");
    if (purge) {
      this.sql("DELETE FROM oauth_tokens WHERE key_id = ?", id);
      this.sql("DELETE FROM notes WHERE key_id = ?", id);
      this.sql("DELETE FROM keys WHERE id = ?", id);
      return json(200, { revoked: true, purged: true, id });
    }
    if (!row.revoked_at) this.sql("UPDATE keys SET revoked_at = ? WHERE id = ?", Date.now(), id);
    this.sql("DELETE FROM oauth_tokens WHERE key_id = ?", id); // a revoked connector's tokens die with its key
    return json(200, { revoked: true, id });
  }

  private registryCall(path: string, body: Record<string, unknown>): Promise<Response> {
    return this.env.REGISTRY.get(this.env.REGISTRY.idFromName("registry")).fetch("https://registry" + path, { method: "POST", body: JSON.stringify({ deviceId: this.getMeta("device_id"), ...body }) });
  }

  /** Tells the Registry this Mac connected or disconnected (not on every ping), so it can drop devices idle for a month. */
  private reportSeen() {
    const now = Date.now();
    if (now - this.reportedAt < 60_000) return;
    this.reportedAt = now;
    const id = this.getMeta("device_id");
    if (id) this.ctx.waitUntil(this.env.REGISTRY.get(this.env.REGISTRY.idFromName("registry")).fetch("https://registry/internal/seen", { method: "POST", body: JSON.stringify({ deviceId: id }) }).catch(() => {}));
  }
  private reportedAt = 0;

  private async unpair(): Promise<Response> {
    const id = this.getMeta("device_id");
    await this.internalWipe();
    if (id) await this.env.REGISTRY.get(this.env.REGISTRY.idFromName("registry")).fetch("https://registry/internal/remove", { method: "POST", body: JSON.stringify({ deviceId: id }) });
    return json(200, { unpaired: true });
  }

  // ---------- usage and free-plan guards

  private today(): string { return new Date().toISOString().slice(0, 10); }

  // Free-plan budget: the daily counters live in memory and are written at most once a minute (and by the hourly alarm), so a
  // request does not cost a row write. An eviction loses at most a minute of counting.
  private usageDay = "";
  private usageRow: Record<string, number> = {};
  private usagePersistedAt = 0;
  private lastSeenMem = 0;
  private readHits = new Map<string, number[]>();

  private loadUsage(): Record<string, number> {
    const day = this.today();
    if (this.usageDay !== day) {
      this.usageDay = day;
      try { this.usageRow = JSON.parse(this.getMeta("usage:" + day) ?? "{}"); } catch { this.usageRow = {}; }
    }
    return this.usageRow;
  }

  private bump(field: string, n = 1) {
    const row = this.loadUsage();
    row[field] = (row[field] ?? 0) + n;
    if (Date.now() - this.usagePersistedAt > 60_000) this.persistUsage();
  }

  private persistUsage() {
    this.setMeta("usage:" + this.usageDay, JSON.stringify(this.usageRow));
    this.usagePersistedAt = Date.now();
  }

  /** Notifications and long-poll seconds are persisted when they change the budget decisions that matter. */
  private usageField(field: string): number { return this.loadUsage()[field] ?? 0; }

  private usage() {
    const row = this.loadUsage();
    const requests = row.requests ?? 0;
    const lim = this.lim;
    return {
      day: this.today(),
      requests,
      wsMessages: row.wsMessages ?? 0,
      notifications: row.notifications ?? 0,
      pollSeconds: row.pollSeconds ?? 0,
      audioUploads: row.audioUploads ?? 0,
      audioBytes: row.audioBytes ?? 0,
      queued: this.pending().length,
      storageBytes: this.ctx.storage.sql.databaseSize,
      limits: {
        audioUploadsPerDay: lim.audioUploadsPerDay, audioBytesPerDay: lim.audioBytesPerDay, requestsPerDay: lim.requestsPerDay, freePlanRequestsPerDay: 100_000,
        notificationsPerDay: lim.notificationsPerDay, pollSecondsPerDay: lim.pollSecondsPerDay, queueMax: lim.queueMax,
      },
      requestsPercent: Math.round((requests / lim.requestsPerDay) * 100),
      budgetExhausted: requests >= lim.requestsPerDay,
    };
  }

  private secondsToMidnight(): number {
    const n = new Date();
    return Math.max(1, Math.ceil((Date.UTC(n.getUTCFullYear(), n.getUTCMonth(), n.getUTCDate() + 1) - n.getTime()) / 1000));
  }

  /** The relay's own cap, below the free plan's, so Cloudflare never has to cut the Mac off mid-day. */
  private budgetGuard(): Response | null {
    if (this.usageField("requests") < this.lim.requestsPerDay) return null;
    const retry = this.secondsToMidnight();
    return json(503, { error: "budget_exhausted", message: "this Mac's daily request budget on the relay is used up; nothing queued is lost", retryAfterSeconds: retry }, { "retry-after": String(retry) });
  }

  private readLimit(key: KeyRow, isNotify: boolean): Response | null {
    if (isNotify) return null; // notify has its own, tighter limit
    // Reads are counted in memory: no row write per poll. (A restart forgives a window; the request budget still holds.)
    const now = Date.now();
    const hits = (this.readHits.get(key.id) ?? []).filter((t) => t > now - RATE_WINDOW_MS);
    if (hits.length >= READ_LIMIT) {
      this.readHits.set(key.id, hits);
      return json(429, { error: "rate_limited", message: `at most ${READ_LIMIT} receipt/reply reads per 10 minutes per key`, retryAfterSeconds: 60 }, { "retry-after": "60" });
    }
    hits.push(now);
    this.readHits.set(key.id, hits);
    return null;
  }

  // ---------- status

  private sockets(): WebSocket[] { return this.ctx.getWebSockets(); }

  private touch() { this.lastSeenMem = Date.now(); }

  private lastSeenMs(): number {
    let t = Math.max(this.lastSeenMem, Number(this.getMeta("last_seen") ?? 0));
    for (const ws of this.sockets()) {
      const a = this.ctx.getWebSocketAutoResponseTimestamp(ws);
      if (a) t = Math.max(t, a.getTime());
    }
    return t;
  }

  private online(): boolean {
    return this.sockets().length > 0 && Date.now() - this.lastSeenMs() < ONLINE_WINDOW_MS;
  }

  private quietState(): { active: boolean; until?: string } {
    try {
      const s = JSON.parse(this.getMeta("status") ?? "{}") as { quietActive?: boolean; quietUntil?: string };
      return { active: !!s.quietActive, ...(s.quietUntil ? { until: s.quietUntil } : {}) };
    } catch { return { active: false }; }
  }

  /** What an agent may learn about the Mac: reachable or not, and whether quiet hours are on. */
  private agentStatus() {
    const seen = this.lastSeenMs();
    return { online: this.online(), ...(seen ? { lastSeenAt: new Date(seen).toISOString() } : {}), quietHours: this.quietState() };
  }

  private info() {
    const seen = this.lastSeenMs();
    const pending = this.pending().length;
    return { online: this.online(), ...(seen ? { lastSeenAt: new Date(seen).toISOString() } : {}), pending,
      quietHours: this.quietState(), keys: this.listKeys().filter((k) => !k.revokedAt).length };
  }

  private applyStatus(s: { quietActive?: unknown; quietUntil?: unknown; muted?: unknown }) {
    const clean = {
      quietActive: s.quietActive === true,
      quietUntil: typeof s.quietUntil === "string" ? s.quietUntil.slice(0, 40) : undefined,
      muted: s.muted === true,
    };
    const next = JSON.stringify(clean);
    if (this.getMeta("status") !== next) this.setMeta("status", next);
  }

  private async httpStatus(req: Request): Promise<Response> {
    let b: Record<string, unknown>;
    try { b = (await req.json()) as Record<string, unknown>; } catch { return err(400, "invalid_request", "body must be JSON"); }
    this.applyStatus(b);
    this.touch();
    return json(200, { ok: true });
  }

  // ---------- notify

  private expireSweep(now: number) {
    this.sql(
      "UPDATE notes SET suppressed_reason = 'expired', suppressed_scope = 'all' WHERE acked_at IS NULL AND suppressed_reason IS NULL AND created_at < ?",
      now - this.lim.ttlMs,
    );
  }

  private pending(): NoteRow[] {
    return this.sql<NoteRow>(
      "SELECT * FROM notes WHERE acked_at IS NULL AND displayed_at IS NULL AND suppressed_reason IS NULL AND created_at >= ? ORDER BY created_at, rowid",
      Date.now() - this.lim.ttlMs,
    );
  }

  private async notify(req: Request, key: KeyRow): Promise<Response> {
    // A data: icon (up to 256 KB) is the one thing allowed past the normal body limit; everything else still has to fit it.
    const hard = this.lim.bodyBytes + ICON_BODY_ALLOWANCE;
    const tooLarge = () => err(413, "too_large", `body is larger than ${this.lim.bodyBytes} bytes (a data: icon may add up to 256 KB)`);
    const declared = Number(req.headers.get("content-length") ?? 0);
    if (declared > hard) return tooLarge();
    const text = await req.text();
    const size = new TextEncoder().encode(text).length;
    if (size > hard) return tooLarge();
    let input: unknown;
    try { input = JSON.parse(text); } catch { return err(400, "invalid_request", "body must be JSON"); }
    if (size > this.lim.bodyBytes) {
      const icon = (input as { icon?: unknown } | null)?.icon;
      const rest = typeof icon === "string" ? size - new TextEncoder().encode(icon).length : size;
      if (rest > this.lim.bodyBytes) return tooLarge();
    }
    const v = validateNotification(input);
    if (!v.ok) return err(400, v.error, v.message, v.fields ? { fields: v.fields } : {});

    const now = Date.now();
    const nid = v.notificationId ?? "n_" + randomHex(12);

    const dup = this.noteByNid(key.id, nid);
    if (dup && dup.created_at >= now - DAY_MS) {
      return json(200, { duplicate: true, ...(await this.receiptBody(dup, new URL(req.url).origin)) });
    }
    if (dup) this.sql("DELETE FROM notes WHERE rid = ?", dup.rid);

    const used = this.sql<{ n: number; oldest: number }>("SELECT COUNT(*) AS n, MIN(at) AS oldest FROM rate WHERE key_id = ? AND at > ?", key.id, now - RATE_WINDOW_MS)[0];
    if (used.n >= this.lim.ratePerKey) {
      const retry = Math.max(1, Math.ceil((used.oldest + RATE_WINDOW_MS - now) / 1000));
      return json(429, { error: "rate_limited", message: `at most ${this.lim.ratePerKey} notifications per 10 minutes per key`, retryAfterSeconds: retry }, { "retry-after": String(retry) });
    }
    if (this.usageField("notifications") >= this.lim.notificationsPerDay) {
      const retry = this.secondsToMidnight();
      return json(429, { error: "daily_cap", message: `at most ${this.lim.notificationsPerDay} notifications per day`, retryAfterSeconds: retry }, { "retry-after": String(retry) });
    }
    this.expireSweep(now);
    if (this.pending().length >= this.lim.queueMax) {
      return err(429, "queue_full", `the Mac has ${this.lim.queueMax} undelivered notifications waiting; it has been offline too long`);
    }

    const rid = "r_" + randomHex(12);
    this.sql(
      "INSERT INTO notes (rid, key_id, nid, payload, expect_reply, created_at) VALUES (?, ?, ?, ?, ?, ?)",
      rid, key.id, nid, JSON.stringify(v.value), v.value.expectReply ? 1 : 0, now,
    );
    this.sql("INSERT INTO rate (key_id, at) VALUES (?, ?)", key.id, now);
    this.bump("notifications");
    await this.scheduleAlarm();
    this.flush();
    const row = this.note(rid)!;
    return json(202, { duplicate: false, ...(await this.receiptBody(row, new URL(req.url).origin)) });
  }

  // ---------- delivery over the socket

  private envelope(n: NoteRow) {
    const k = this.sql<KeyRow>("SELECT * FROM keys WHERE id = ?", n.key_id)[0];
    return {
      type: "notify", id: n.rid, notificationId: n.nid, createdAt: new Date(n.created_at).toISOString(),
      key: { id: n.key_id, name: k?.name ?? "unknown", client: k?.client ?? "other" },
      payload: JSON.parse(n.payload),
    };
  }

  /** `resend` sends everything not yet acknowledged (a fresh connection); otherwise only what was never sent. */
  private flush(resend = false) {
    const ws = this.sockets()[0];
    if (!ws) return;
    const now = Date.now();
    for (const n of this.pending()) {
      if (!resend && n.sent_at != null) continue;
      try {
        ws.send(JSON.stringify(this.envelope(n)));
        this.sql("UPDATE notes SET sent_at = ? WHERE rid = ?", now, n.rid);
      } catch { return; }
    }
  }

  private stream(req: Request): Response {
    if (req.headers.get("upgrade")?.toLowerCase() !== "websocket") return err(426, "upgrade_required", "WebSocket upgrade required");
    for (const old of this.sockets()) { try { old.close(4000, "replaced by a newer connection"); } catch { /* gone */ } }
    const pair = new WebSocketPair();
    this.ctx.acceptWebSocket(pair[1]);
    this.setMeta("last_seen", String(Date.now()));
    this.reportedAt = 0;
    this.reportSeen();
    pair[1].send(JSON.stringify({ type: "welcome", ttlSeconds: this.lim.ttlMs / 1000 }));
    this.expireSweep(Date.now());
    this.flush(true);
    this.expireConsents(Date.now());
    // A request Herald already got as a banner is only refreshed in its list (`redelivered`); one that arrived while it was away is new.
    for (const r of this.pendingRequests()) this.sendConsent(r, r.announced_at != null);
    return new Response(null, { status: 101, webSocket: pair[0] });
  }

  async webSocketMessage(ws: WebSocket, message: string | ArrayBuffer): Promise<void> {
    if (typeof message !== "string" || message.length > 16 * 1024) return;
    let m: Record<string, unknown>;
    try { m = JSON.parse(message); } catch { return; }
    this.touch();
    this.bump("wsMessages");
    switch (m.type) {
      case "hello":
      case "status":
        this.applyStatus(m as never);
        if (m.type === "hello") this.flush();
        break;
      case "ack":
        if (typeof m.id === "string") this.sql("UPDATE notes SET acked_at = COALESCE(acked_at, ?) WHERE rid = ?", Date.now(), m.id);
        break;
      case "receipt":
        this.applyReceipt(m);
        break;
    }
  }

  async webSocketClose(ws: WebSocket, code: number, reason: string): Promise<void> {
    this.setMeta("last_seen", String(Date.now()));
    if (this.getMeta("device_id")) this.reportSeen();
    try { ws.close(code, reason); } catch { /* already closed */ }
  }

  async webSocketError(): Promise<void> { this.setMeta("last_seen", String(Date.now())); }

  // ---------- OAuth (connector approvals). Reached only through the Worker's /authorize and /token routes.

  private pendingRequests(): OAuthReq[] {
    return this.sql<OAuthReq>("SELECT * FROM oauth_requests WHERE status = 'pending' AND expires_at > ? ORDER BY created_at", Date.now());
  }

  private redirectHost(uri: string): string {
    try { const u = new URL(uri); return u.host || u.protocol; } catch { return ""; }
  }

  private consentView(r: OAuthReq) {
    return {
      id: r.id, clientId: r.client_id, clientName: r.client_name, redirectHost: this.redirectHost(r.redirect_uri), scope: r.scope,
      code: r.user_code, status: r.status === "pending" && r.expires_at <= Date.now() ? "expired" : r.status,
      createdAt: iso(r.created_at), expiresAt: iso(r.expires_at),
      ...(r.flow === "device" && r.device_user_code ? { flow: "device", userCode: this.dashed(r.device_user_code) } : { flow: "code" }),
    };
  }

  private dashed(c: string) { return c.slice(0, 4) + "-" + c.slice(4); }

  /** `redelivered`: Herald has shown this one already (a reconnect): it updates its list and shows no banner. */
  private sendConsent(r: OAuthReq, redelivered = false) {
    const ws = this.sockets()[0];
    if (!ws) return;
    try {
      ws.send(JSON.stringify({ type: "consent", ...this.consentView(r), ...(redelivered ? { redelivered: true } : {}) }));
      if (!redelivered) this.sql("UPDATE oauth_requests SET announced_at = ? WHERE id = ?", Date.now(), r.id);
    } catch { /* socket gone: Herald lists consents on reconnect */ }
  }

  /**
   * Pending requests that ran out are dropped from the mailbox and Herald is told (`consent_resolved`, `expired`), so its banner and
   * its pending list lose them without waiting for anything. Runs from the alarm, on connect and on every consent read.
   */
  private expireConsents(now: number) {
    for (const r of this.sql<OAuthReq>("SELECT * FROM oauth_requests WHERE status = 'pending' AND expires_at <= ?", now)) {
      this.sql("DELETE FROM oauth_requests WHERE id = ?", r.id);
      this.sendResolved({ ...r, status: "expired" });
    }
  }

  /** The next time something here must wake up on its own: the earliest open consent running out (the hourly sweep is separate). */
  private async scheduleConsentAlarm() {
    const next = this.sql<{ t: number | null }>("SELECT MIN(expires_at) AS t FROM oauth_requests WHERE status = 'pending'")[0]?.t;
    if (next == null) return;
    const cur = await this.ctx.storage.getAlarm();
    if (cur == null || cur > next + 1000) await this.ctx.storage.setAlarm(next + 1000);
  }

  /**
   * Another request of this client is open on this Mac: it is the same connection attempt again. The caller reuses the row (the
   * Herald banner is updated in place with the new code). A request of the other flow is closed instead.
   */
  private openRequestOf(clientId: string, flow: "code" | "device", now: number): OAuthReq | undefined {
    let reuse: OAuthReq | undefined;
    for (const r of this.sql<OAuthReq>("SELECT * FROM oauth_requests WHERE status = 'pending' AND client_id = ? AND expires_at > ? ORDER BY created_at DESC", clientId, now)) {
      if (!reuse && (r.flow === "device" ? "device" : "code") === flow) { reuse = r; continue; }
      this.sql("UPDATE oauth_requests SET status = 'superseded', decided_at = ?, device_hash = NULL WHERE id = ?", now, r.id);
      this.sendResolved({ ...r, status: "superseded" });
    }
    return reuse;
  }

  /** The same client asked for this Mac elsewhere or was decided: its other open requests on THIS mailbox are closed. */
  private supersedeClient(clientId: string, now: number): Response {
    for (const r of this.sql<OAuthReq>("SELECT * FROM oauth_requests WHERE status = 'pending' AND client_id = ?", clientId)) {
      this.sql("UPDATE oauth_requests SET status = 'superseded', decided_at = ?, device_hash = NULL WHERE id = ?", now, r.id);
      this.sendResolved({ ...r, status: "superseded" });
    }
    return json(200, { ok: true });
  }

  /** A decision (or a newer request) on one Mac closes the same client's open requests on every other paired Mac. */
  private async supersedeOnOtherMacs(clientId: string) {
    const me = this.getMeta("device_id");
    try {
      const r = await this.env.REGISTRY.get(this.env.REGISTRY.idFromName("registry")).fetch("https://registry/devices", { method: "POST", body: "{}" });
      const { devices } = (await r.json()) as { devices: { id: string }[] };
      for (const d of devices) {
        if (d.id === me) continue;
        await this.env.MAILBOX.get(this.env.MAILBOX.idFromName(d.id)).fetch("https://mailbox/internal/oauth/supersede", { method: "POST", body: JSON.stringify({ client_id: clientId }) });
      }
    } catch { /* best effort: the other Mac's request still expires on its own */ }
  }

  private sendResolved(r: OAuthReq) {
    const ws = this.sockets()[0];
    if (!ws) return;
    try { ws.send(JSON.stringify({ type: "consent_resolved", id: r.id, status: r.status })); } catch { /* gone */ }
  }

  /** Requests of the last day, newest first (Herald shows them under Connector approvals). */
  private consentList() {
    this.expireConsents(Date.now());
    return this.sql<OAuthReq>("SELECT * FROM oauth_requests WHERE created_at > ? ORDER BY created_at DESC LIMIT 20", Date.now() - DAY_MS).map((r) => this.consentView(r));
  }

  private oauthSweep(now: number) {
    this.sql("DELETE FROM oauth_requests WHERE created_at < ?", now - DAY_MS);
    // Tokens are not swept by age: they live as long as their connector's approval.
  }

  private async oauthInternal(op: string, req: Request): Promise<Response> {
    const b = (await req.json().catch(() => ({}))) as Record<string, string | undefined>;
    const now = Date.now();
    this.oauthSweep(now);
    this.expireConsents(now);
    switch (op) {
      case "begin": return this.oauthBegin(b, now);
      case "status": return this.oauthStatus(b.id ?? "", now);
      case "code": return this.oauthCode(b.id ?? "", b.code ?? "", now);
      case "deny": return this.oauthDecide(b.id ?? "", "deny", now);
      case "token": return this.oauthTokenEndpoint(b, now);
      case "device_begin": return this.deviceBegin(b, now);
      case "supersede": return this.supersedeClient(b.client_id ?? "", now);
      case "device_lookup": return this.deviceLookup(b.user_code ?? "", now);
      case "revoke": return this.oauthRevoke(b);
    }
    return err(404, "not_found", "no such oauth operation");
  }

  private async oauthBegin(b: Record<string, string | undefined>, now: number): Promise<Response> {
    const again = this.openRequestOf(b.clientId ?? "", "code", now);
    if (again) {
      // The same client asking again is the same connection attempt: one request, one banner, a fresh code.
      const userCode = String(crypto.getRandomValues(new Uint32Array(1))[0] % 1_000_000).padStart(6, "0");
      this.sql("UPDATE oauth_requests SET client_name = ?, redirect_uri = ?, challenge = ?, state = ?, scope = ?, resource = ?, user_code = ?, attempts = 0, expires_at = ? WHERE id = ?",
        (b.clientName ?? "").slice(0, 60), b.redirectUri ?? "", b.challenge ?? "", b.state ?? null, b.scope ?? "notify", b.resource ?? "", userCode, now + OAUTH_REQUEST_TTL_MS, again.id);
      this.sendConsent(this.sql<OAuthReq>("SELECT * FROM oauth_requests WHERE id = ?", again.id)[0]);
      await this.scheduleConsentAlarm();
      await this.supersedeOnOtherMacs(b.clientId ?? "");
      return json(201, { id: again.id, expiresAt: iso(now + OAUTH_REQUEST_TTL_MS), online: this.online(), replaced: true });
    }
    if (this.pendingRequests().length >= OAUTH_MAX_PENDING) return err(429, "rate_limited", "approvals are already waiting in Herald; answer them or wait 10 minutes", { retryAfterSeconds: 600 });
    if (this.sql<{ n: number }>("SELECT COUNT(*) AS n FROM oauth_requests WHERE created_at > ?", now - 3_600_000)[0].n >= OAUTH_BEGINS_PER_HOUR) {
      return err(429, "rate_limited", "too many connector requests; try again in an hour", { retryAfterSeconds: 3600 });
    }
    const deviceId = this.getMeta("device_id");
    if (!deviceId) return err(404, "not_paired", "this relay has no paired Herald");
    const id = deviceId + randomHex(12);
    const userCode = String(crypto.getRandomValues(new Uint32Array(1))[0] % 1_000_000).padStart(6, "0");
    this.sql("INSERT INTO oauth_requests (id, client_id, client_name, redirect_uri, challenge, state, scope, resource, user_code, status, created_at, expires_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 'pending', ?, ?)",
      id, b.clientId ?? "", (b.clientName ?? "").slice(0, 60), b.redirectUri ?? "", b.challenge ?? "", b.state ?? null, b.scope ?? "notify", b.resource ?? "", userCode, now, now + OAUTH_REQUEST_TTL_MS);
    this.sendConsent(this.sql<OAuthReq>("SELECT * FROM oauth_requests WHERE id = ?", id)[0]);
    await this.scheduleConsentAlarm();
    await this.supersedeOnOtherMacs(b.clientId ?? "");
    return json(201, { id, expiresAt: iso(now + OAUTH_REQUEST_TTL_MS), online: this.online() });
  }

  // ---------- device authorization grant (RFC 8628)

  private newUserCode(): string {
    for (;;) {
      const b = crypto.getRandomValues(new Uint8Array(8));
      const c = [...b].map((x) => USER_CODE_ALPHABET[x % USER_CODE_ALPHABET.length]).join("");
      if (this.sql<{ n: number }>("SELECT COUNT(*) AS n FROM oauth_requests WHERE device_user_code = ? AND status = 'pending' AND expires_at > ?", c, Date.now())[0].n === 0) return c;
    }
  }

  private async deviceBegin(b: Record<string, string | undefined>, now: number): Promise<Response> {
    const again = this.openRequestOf(b.clientId ?? "", "device", now);
    if (again) {
      // The same client asking again: one request, the banner updated in place with the new code; the old device_code stops working.
      const approval = String(crypto.getRandomValues(new Uint32Array(1))[0] % 1_000_000).padStart(6, "0");
      const userCode = this.newUserCode();
      const deviceCode = oauthToken("hrv", this.getMeta("device_id") ?? "", randomHex(32));
      this.sql("UPDATE oauth_requests SET client_name = ?, scope = ?, resource = ?, user_code = ?, attempts = 0, expires_at = ?, device_hash = ?, device_user_code = ?, last_poll = ?, poll_interval = ? WHERE id = ?",
        (b.clientName ?? "").slice(0, 60), b.scope ?? "notify", b.resource ?? "", approval, now + DEVICE_TTL_S * 1000, await sha256Hex(deviceCode), userCode, now, DEVICE_INTERVAL_S, again.id);
      this.sendConsent(this.sql<OAuthReq>("SELECT * FROM oauth_requests WHERE id = ?", again.id)[0]);
      await this.scheduleConsentAlarm();
      await this.supersedeOnOtherMacs(b.clientId ?? "");
      return json(201, { id: again.id, deviceCode, userCode: this.dashed(userCode), expiresIn: DEVICE_TTL_S, interval: DEVICE_INTERVAL_S, online: this.online(), replaced: true });
    }
    if (this.pendingRequests().length >= OAUTH_MAX_PENDING) return err(429, "rate_limited", "approvals are already waiting in Herald; answer them or wait 10 minutes", { retryAfterSeconds: 600 });
    if (this.sql<{ n: number }>("SELECT COUNT(*) AS n FROM oauth_requests WHERE created_at > ?", now - 3_600_000)[0].n >= OAUTH_BEGINS_PER_HOUR) {
      return err(429, "rate_limited", "too many connector requests; try again in an hour", { retryAfterSeconds: 3600 });
    }
    const deviceId = this.getMeta("device_id");
    if (!deviceId) return err(404, "not_paired", "this relay has no paired Herald");
    const id = deviceId + randomHex(12);
    const approval = String(crypto.getRandomValues(new Uint32Array(1))[0] % 1_000_000).padStart(6, "0");
    const userCode = this.newUserCode();
    const deviceCode = oauthToken("hrv", deviceId, randomHex(32));
    const expires = now + DEVICE_TTL_S * 1000;
    this.sql("INSERT INTO oauth_requests (id, client_id, client_name, redirect_uri, challenge, state, scope, resource, user_code, status, created_at, expires_at, flow, device_hash, device_user_code, last_poll, poll_interval) VALUES (?, ?, ?, '', '', NULL, ?, ?, ?, 'pending', ?, ?, 'device', ?, ?, ?, ?)",
      id, b.clientId ?? "", (b.clientName ?? "").slice(0, 60), b.scope ?? "notify", b.resource ?? "", approval, now, expires, await sha256Hex(deviceCode), userCode, now, DEVICE_INTERVAL_S);
    this.sendConsent(this.sql<OAuthReq>("SELECT * FROM oauth_requests WHERE id = ?", id)[0]);
    await this.scheduleConsentAlarm();
    await this.supersedeOnOtherMacs(b.clientId ?? "");
    return json(201, { id, deviceCode, userCode: this.dashed(userCode), expiresIn: DEVICE_TTL_S, interval: DEVICE_INTERVAL_S, online: this.online() });
  }

  /** /activate: the request a typed user code belongs to (the page then asks for the approval code Herald shows). */
  private deviceLookup(userCode: string, now: number): Response {
    const code = userCode.toUpperCase().replace(/[^A-Z0-9]/g, "");
    const r = code.length === 8 ? this.sql<OAuthReq>("SELECT * FROM oauth_requests WHERE flow = 'device' AND device_user_code = ? AND status = 'pending' AND expires_at > ?", code, now)[0] : undefined;
    if (!r) return json(404, { status: "unknown" });
    return json(200, { id: r.id, clientName: r.client_name, userCode: this.dashed(code) });
  }

  private async deviceTokenGrant(b: Record<string, string | undefined>, now: number): Promise<Response> {
    const dc = b.device_code ?? "";
    if (!parseOAuthSecret(dc, "hrv")) return this.oerr("invalid_grant", "malformed device_code");
    const r = this.sql<OAuthReq>("SELECT * FROM oauth_requests WHERE device_hash = ?", await sha256Hex(dc))[0];
    if (!r) return this.oerr("expired_token", "unknown or expired device_code; start again with /device_authorization");
    if (r.client_id !== (b.client_id ?? "")) return this.oerr("invalid_grant", "device_code was issued to another client");
    if (r.redeemed_at) {
      if (r.key_id) this.sql("DELETE FROM oauth_tokens WHERE key_id = ?", r.key_id); // a code used twice is treated as stolen
      return this.oerr("invalid_grant", "device_code already used");
    }
    if (r.status === "denied") return this.oerr("access_denied", "the user denied the request");
    if (r.status === "pending") {
      if (r.expires_at <= now) return this.oerr("expired_token", "the user code expired; start again");
      const interval = r.poll_interval ?? DEVICE_INTERVAL_S;
      const last = r.last_poll ?? r.created_at;
      this.sql("UPDATE oauth_requests SET last_poll = ? WHERE id = ?", now, r.id);
      if (now - last < interval * 1000) {
        this.sql("UPDATE oauth_requests SET poll_interval = ? WHERE id = ?", interval + 5, r.id);
        return this.oerr("slow_down", `poll no faster than every ${interval} seconds; the interval is now ${interval + 5}`);
      }
      return this.oerr("authorization_pending", "waiting for the user to approve in Herald");
    }
    if (r.status !== "approved" || r.expires_at <= now) return this.oerr("expired_token", "the approval expired; start again");
    if (b.resource && !sameResource(b.resource, r.resource)) return this.oerr("invalid_target", "resource does not match the authorization request");
    this.sql("UPDATE oauth_requests SET redeemed_at = ? WHERE id = ?", now, r.id);
    const key = this.sql<KeyRow>("SELECT * FROM keys WHERE id = ?", r.key_id ?? "")[0];
    if (!key || key.revoked_at) return this.oerr("invalid_grant", "the connector was revoked");
    return this.issueTokens(key.id, r.client_id, r.resource, randomHex(8), now);
  }

  private redirectFor(r: OAuthReq): string {
    const u = new URL(r.redirect_uri);
    if (r.status === "approved" && r.code) u.searchParams.set("code", r.code);
    else u.searchParams.set("error", "access_denied");
    if (r.state) u.searchParams.set("state", r.state);
    return u.toString();
  }

  private oauthStatus(id: string, now: number): Response {
    const r = this.sql<OAuthReq>("SELECT * FROM oauth_requests WHERE id = ?", id)[0];
    if (!r) return json(404, { status: "unknown" });
    if (r.status === "superseded") return json(200, { status: "expired" });   // replaced by a newer request: nothing to redirect to
    if (r.status === "pending") return json(200, { status: r.expires_at <= now ? "expired" : "pending" });
    if (r.flow === "device") return json(200, { status: r.status === "pending" && r.expires_at <= now ? "expired" : r.status });
    if (r.status === "approved" && (!r.code || r.expires_at <= now)) return json(200, { status: "expired" });
    return json(200, { status: r.status, redirect: this.redirectFor(r) });
  }

  private async oauthCode(id: string, code: string, now: number): Promise<Response> {
    const r = this.sql<OAuthReq>("SELECT * FROM oauth_requests WHERE id = ?", id)[0];
    if (!r || r.status !== "pending" || r.expires_at <= now) return this.oauthStatus(id, now);
    const attempts = r.attempts + 1;
    this.sql("UPDATE oauth_requests SET attempts = ? WHERE id = ?", attempts, id);
    if (safeEqual(r.user_code, code.replace(/\D/g, ""))) return this.oauthDecide(id, "approve", now);
    if (attempts >= OAUTH_CODE_ATTEMPTS) return this.oauthDecide(id, "deny", now);
    return json(200, { status: "wrong_code", attemptsLeft: OAUTH_CODE_ATTEMPTS - attempts });
  }

  private async oauthDecide(id: string, decision: "approve" | "deny", now: number): Promise<Response> {
    const r = this.sql<OAuthReq>("SELECT * FROM oauth_requests WHERE id = ?", id)[0];
    if (!r) return err(404, "not_found", "no such request");
    if (r.status !== "pending") return err(409, "already_decided", `this request is already ${r.status}`, { status: r.status });
    if (r.expires_at <= now) return err(410, "expired", "this request has expired");
    if (decision === "deny") {
      this.sql("UPDATE oauth_requests SET status = 'denied', decided_at = ? WHERE id = ?", now, id);
    } else {
      const keyId = await this.createOAuthKey(r.client_id, r.client_name, now);
      if (!keyId) return err(429, "too_many_keys", `at most ${MAX_KEYS} active keys; revoke one first`);
      const code = r.flow === "device" ? null : oauthToken("hrc", this.getMeta("device_id") ?? "", randomHex(32));
      this.sql("UPDATE oauth_requests SET status = 'approved', decided_at = ?, key_id = ?, code = ?, code_hash = ?, expires_at = ? WHERE id = ?",
        now, keyId, code, code ? await sha256Hex(code) : null, now + OAUTH_CODE_TTL_MS, id);
    }
    const done = this.sql<OAuthReq>("SELECT * FROM oauth_requests WHERE id = ?", id)[0];
    this.sendResolved(done);
    await this.supersedeOnOtherMacs(done.client_id);   // gone from every other paired Mac too
    return json(200, { status: done.status, ...(done.flow === "device" ? {} : { redirect: this.redirectFor(done) }) });
  }

  /** One key per connector, kind "oauth". Re-authorizing the same client replaces its earlier key. */
  private async createOAuthKey(clientId: string, clientName: string, now: number): Promise<string | null> {
    for (const old of this.sql<KeyRow>("SELECT * FROM keys WHERE kind = 'oauth' AND oauth_client = ? AND revoked_at IS NULL", clientId)) {
      this.sql("UPDATE keys SET revoked_at = ? WHERE id = ?", now, old.id);
      this.sql("DELETE FROM oauth_tokens WHERE key_id = ?", old.id);
    }
    const active = this.sql<KeyRow>("SELECT * FROM keys WHERE revoked_at IS NULL");
    if (active.length >= MAX_KEYS) return null;
    const base = clientName.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "").slice(0, 24).replace(/-+$/, "") || "connector";
    let name = base;
    for (let i = 2; active.some((k) => k.name === name); i++) name = `${base}-${i}`;
    const id = randomHex(4);
    this.sql("INSERT INTO keys (id, name, client, scope, hash, created_at, kind, client_name, oauth_client) VALUES (?, ?, 'other', 'notify', ?, ?, 'oauth', ?, ?)",
      id, name, await sha256Hex(randomHex(32)), now, clientName, clientId);
    return id;
  }

  /** Herald approves or denies from its banner. */
  private async deviceConsent(req: Request): Promise<Response> {
    const b = (await req.json().catch(() => null)) as { id?: unknown; decision?: unknown } | null;
    if (!b || typeof b.id !== "string" || (b.decision !== "approve" && b.decision !== "deny")) return err(400, "invalid_request", "id and decision (approve|deny) are required");
    this.touch();
    return this.oauthDecide(b.id, b.decision, Date.now());
  }

  /**
   * `keepRefresh` is the refresh token the client just presented: a refresh hands back that same token with a new access token, so a
   * lost response can simply be retried and nothing the client holds is ever invalidated by using it.
   */
  private async issueTokens(keyId: string, clientId: string, resource: string, family: string, now: number, keepRefresh?: string) {
    const deviceId = this.getMeta("device_id") ?? "";
    const access = randomHex(32);
    this.sql("INSERT INTO oauth_tokens (hash, kind, key_id, client_id, resource, family, expires_at, created_at) VALUES (?, 'access', ?, ?, ?, ?, ?, ?)",
      await sha256Hex(access), keyId, clientId, resource, family, NEVER, now);
    let refreshToken = keepRefresh;
    if (!refreshToken) {
      const refresh = randomHex(32);
      this.sql("INSERT INTO oauth_tokens (hash, kind, key_id, client_id, resource, family, expires_at, created_at) VALUES (?, 'refresh', ?, ?, ?, ?, ?, ?)",
        await sha256Hex(refresh), keyId, clientId, resource, family, NEVER, now);
      refreshToken = oauthToken("hrr", deviceId, refresh);
    }
    // Bound the table for a client that refreshes often: the oldest access tokens of this connector go first.
    this.sql("DELETE FROM oauth_tokens WHERE kind = 'access' AND key_id = ? AND hash NOT IN (SELECT hash FROM oauth_tokens WHERE kind = 'access' AND key_id = ? ORDER BY created_at DESC, rowid DESC LIMIT ?)",
      keyId, keyId, ACCESS_TOKENS_KEPT_PER_KEY);
    return json(200, {
      access_token: oauthToken("hra", deviceId, access), token_type: "Bearer", expires_in: OAUTH_ACCESS_TTL_S,
      refresh_token: refreshToken, scope: "notify",
    });
  }

  private oerr(error: string, description: string): Response {
    return json(400, { error, error_description: description });
  }

  private async oauthTokenEndpoint(b: Record<string, string | undefined>, now: number): Promise<Response> {
    const clientId = b.client_id ?? "";
    if (b.grant_type === DEVICE_GRANT) return this.deviceTokenGrant(b, now);
    if (b.grant_type === "authorization_code") {
      const code = b.code ?? "";
      if (!parseOAuthSecret(code, "hrc")) return this.oerr("invalid_grant", "malformed authorization code");
      const r = this.sql<OAuthReq>("SELECT * FROM oauth_requests WHERE code_hash = ?", await sha256Hex(code))[0];
      if (!r) return this.oerr("invalid_grant", "unknown or already used authorization code");
      if (r.redeemed_at) {
        // A code used twice is treated as stolen: what it produced is revoked (OAuth 2.1, section 4.1.3).
        if (r.key_id) this.sql("DELETE FROM oauth_tokens WHERE key_id = ?", r.key_id);
        return this.oerr("invalid_grant", "authorization code already used");
      }
      if (r.status !== "approved" || r.expires_at <= now) return this.oerr("invalid_grant", "authorization code expired");
      if (r.client_id !== clientId) return this.oerr("invalid_grant", "code was issued to another client");
      if (r.redirect_uri !== (b.redirect_uri ?? "")) return this.oerr("invalid_grant", "redirect_uri does not match the authorization request");
      const v = b.code_verifier ?? "";
      if (!/^[A-Za-z0-9\-._~]{43,128}$/.test(v)) return this.oerr("invalid_grant", "code_verifier is missing or malformed");
      if (!safeEqual(await s256(v), r.challenge)) return this.oerr("invalid_grant", "PKCE verification failed");
      if (b.resource && !sameResource(b.resource, r.resource)) return this.oerr("invalid_target", "resource does not match the authorization request");
      this.sql("UPDATE oauth_requests SET redeemed_at = ?, code = NULL WHERE id = ?", now, r.id);
      const key = this.sql<KeyRow>("SELECT * FROM keys WHERE id = ?", r.key_id ?? "")[0];
      if (!key || key.revoked_at) return this.oerr("invalid_grant", "the connector was revoked");
      return this.issueTokens(key.id, clientId, r.resource, randomHex(8), now);
    }
    if (b.grant_type === "refresh_token") {
      const rt = b.refresh_token ?? "";
      if (!parseOAuthSecret(rt, "hrr")) return this.oerr("invalid_grant", "malformed refresh token");
      const t = this.sql<OAuthTok>("SELECT * FROM oauth_tokens WHERE hash = ? AND kind = 'refresh'", await sha256Hex(rt.split("_")[2]))[0];
      if (!t || t.client_id !== clientId) return this.oerr("invalid_grant", "unknown refresh token");
      // Reusable and without expiry (a token marked used or expired under the old rotating rule is accepted again).
      const key = this.sql<KeyRow>("SELECT * FROM keys WHERE id = ?", t.key_id)[0];
      if (!key || key.revoked_at) return this.oerr("invalid_grant", "the connector was revoked");
      if (b.resource && !sameResource(b.resource, t.resource)) return this.oerr("invalid_target", "resource does not match the original grant");
      if (b.scope && b.scope.split(/\s+/).some((x) => x !== "notify")) return this.oerr("invalid_scope", "the only scope is notify");
      return this.issueTokens(key.id, clientId, t.resource, t.family, now, rt);
    }
    return this.oerr("unsupported_grant_type", "grant_type must be authorization_code, refresh_token or urn:ietf:params:oauth:grant-type:device_code");
  }

  /** RFC 7009: an unknown token is not an error. A refresh token takes its whole family with it. */
  private async oauthRevoke(b: Record<string, string | undefined>): Promise<Response> {
    const tok = b.token ?? "";
    if (parseOAuthSecret(tok, "hrr") || parseOAuthSecret(tok, "hra")) {
      const t = this.sql<OAuthTok>("SELECT * FROM oauth_tokens WHERE hash = ?", await sha256Hex(tok.split("_")[2]))[0];
      if (t && t.client_id === b.client_id) {
        if (t.kind === "refresh") this.sql("DELETE FROM oauth_tokens WHERE family = ?", t.family);
        else this.sql("DELETE FROM oauth_tokens WHERE hash = ?", t.hash);
      }
    }
    return json(200, {});
  }

  // ---------- receipts from Herald

  private async httpReceipt(req: Request, forceKind?: string): Promise<Response> {
    let b: Record<string, unknown>;
    try { b = (await req.json()) as Record<string, unknown>; } catch { return err(400, "invalid_request", "body must be JSON"); }
    this.touch();
    if (forceKind) b = { ...b, kind: forceKind };
    const r = this.applyReceipt(b);
    return r === "ok" ? json(200, { ok: true }) : err(r === "unknown" ? 404 : 400, r === "unknown" ? "not_found" : "invalid_request", r === "unknown" ? "no such notification" : "invalid receipt");
  }

  private applyReceipt(m: Record<string, unknown>): "ok" | "unknown" | "invalid" {
    const id = typeof m.id === "string" ? m.id : typeof m.notificationId === "string" ? m.notificationId : "";
    const n = this.note(id);
    if (!n) return "unknown";
    const now = Date.now();
    switch (m.kind) {
      case "displayed":
        this.sql("UPDATE notes SET displayed_at = COALESCE(displayed_at, ?), acked_at = COALESCE(acked_at, ?) WHERE rid = ?", now, now, id);
        break;
      case "spoken":
        this.sql("UPDATE notes SET spoken_at = COALESCE(spoken_at, ?), acked_at = COALESCE(acked_at, ?) WHERE rid = ?", now, now, id);
        break;
      case "replied": {
        const text = typeof m.text === "string" ? m.text.trim().slice(0, 4000) : "";
        const transcript = typeof m.transcript === "string" ? m.transcript.trim().slice(0, 4000) : "";
        const secs = typeof m.durationSeconds === "number" && m.durationSeconds >= 0 && m.durationSeconds <= 600 ? m.durationSeconds : null;
        if (!text && !transcript && !n.audio_key) return "invalid";
        this.sql(
          "UPDATE notes SET replied_at = COALESCE(replied_at, ?), reply = COALESCE(reply, ?), transcript = COALESCE(transcript, ?), audio_seconds = COALESCE(?, audio_seconds), acked_at = COALESCE(acked_at, ?) WHERE rid = ?",
          now, text || null, transcript || null, secs, now, id);
        break;
      }
      case "suppressed": {
        const reason = typeof m.reason === "string" && /^[a-z0-9-]{1,40}$/.test(m.reason) ? m.reason : "suppressed";
        const scope = m.scope === "speech" ? "speech" : "all";
        this.sql("UPDATE notes SET suppressed_reason = ?, suppressed_scope = ?, acked_at = COALESCE(acked_at, ?) WHERE rid = ?", reason, scope, now, id);
        break;
      }
      default:
        return "invalid";
    }
    this.wake(id);
    return "ok";
  }

  private wake(rid: string) {
    const w = this.waiters.get(rid);
    if (w) for (const f of [...w]) f();
  }

  // ---------- receipts and replies for agents

  private async audioUrl(origin: string, n: NoteRow): Promise<string | undefined> {
    if (!n.audio_key) return undefined;
    const exp = Math.floor(Date.now() / 1000) + AUDIO_URL_TTL_S;
    const sig = await hmacHex(this.env.RELAY_SECRET, `audio:${n.audio_key}:${exp}`);
    return `${origin}/v1/audio/${n.audio_key}?exp=${exp}&sig=${sig}`;
  }

  private async replyFields(origin: string, n: NoteRow) {
    if (n.replied_at == null) return {};
    const audioUrl = await this.audioUrl(origin, n);
    return {
      repliedAt: iso(n.replied_at),
      reply: n.reply ?? n.transcript ?? undefined,
      ...(n.reply ? { text: n.reply } : {}),
      ...(n.transcript ? { transcript: n.transcript, transcriptNote: "transcribed on the user's Mac; may be imperfect" } : {}),
      ...(audioUrl ? { audioUrl, audioUrlExpiresInSeconds: AUDIO_URL_TTL_S } : {}),
      ...(n.audio_seconds != null ? { durationSeconds: n.audio_seconds } : {}),
    };
  }

  private async receiptBody(n: NoteRow, origin = "") {
    const sup = n.suppressed_reason != null;
    return {
      notificationId: n.nid,
      received: true,
      receivedAt: iso(n.created_at),
      queued: n.acked_at == null && !sup,
      displayed: n.displayed_at != null,
      ...(n.displayed_at != null ? { displayedAt: iso(n.displayed_at) } : {}),
      spoken: n.spoken_at != null,
      ...(n.spoken_at != null ? { spokenAt: iso(n.spoken_at) } : {}),
      replied: n.replied_at != null,
      ...(await this.replyFields(origin, n)),
      expectReply: n.expect_reply === 1,
      suppressed: sup,
      ...(sup ? { reason: n.suppressed_reason, suppressedScope: n.suppressed_scope } : {}),
    };
  }

  private async getReceipt(key: KeyRow, nid: string, origin: string): Promise<Response> {
    const n = this.noteByNid(key.id, nid);
    if (!n || n.created_at < Date.now() - DAY_MS) return err(404, "not_found", "no such notification (ids are kept for 24 hours)");
    return json(200, await this.receiptBody(n, origin));
  }

  private async getReply(key: KeyRow, nid: string, waitParam: string | null, origin: string): Promise<Response> {
    const first = this.noteByNid(key.id, nid);
    if (!first || first.created_at < Date.now() - DAY_MS) return err(404, "not_found", "no such notification (ids are kept for 24 hours)");
    let seconds = Math.min(MAX_LONG_POLL_S, Math.max(0, Number(waitParam ?? 0) || 0));
    if (this.usageField("pollSeconds") >= this.lim.pollSecondsPerDay) seconds = 0; // the DO is awake while it waits; stop holding polls when the day's allowance is gone
    const started = Date.now();
    const deadline = Date.now() + seconds * 1000;
    let n: NoteRow = first;
    for (;;) {
      n = this.note(n.rid) ?? n;
      const done = n.replied_at != null || (n.suppressed_reason != null && n.suppressed_scope === "all");
      const left = deadline - Date.now();
      if (done || left <= 0) {
        if (seconds > 0) this.bump("pollSeconds", Math.ceil((Date.now() - started) / 1000));
        return json(200, {
          notificationId: nid,
          replied: n.replied_at != null,
          ...(await this.replyFields(origin, n)),
          ...(n.replied_at == null && seconds > 0 && !done ? { timedOut: true } : {}),
          suppressed: n.suppressed_reason != null,
          ...(n.suppressed_reason != null ? { reason: n.suppressed_reason } : {}),
        });
      }
      await new Promise<void>((resolve) => {
        const set = this.waiters.get(n.rid) ?? new Set<() => void>();
        this.waiters.set(n.rid, set);
        const timer = setTimeout(finish, left);
        function finish() { clearTimeout(timer); set.delete(finish); resolve(); }
        set.add(finish);
      });
    }
  }

  // ---------- voice replies

  private async putAudio(req: Request, rid: string): Promise<Response> {
    const n = this.note(rid);
    if (!n) return err(404, "not_found", "no such notification");
    const declared = Number(req.headers.get("content-length") ?? 0);
    if (declared > MAX_AUDIO_BYTES) return err(413, "too_large", `audio is larger than ${MAX_AUDIO_BYTES} bytes`);
    if (this.usageField("audioUploads") >= this.lim.audioUploadsPerDay) {
      const retry = this.secondsToMidnight();
      return json(429, { error: "daily_cap", message: `at most ${this.lim.audioUploadsPerDay} voice replies per day`, retryAfterSeconds: retry }, { "retry-after": String(retry) });
    }
    const body = await req.arrayBuffer();
    if (body.byteLength === 0) return err(400, "invalid_request", "empty audio");
    if (body.byteLength > MAX_AUDIO_BYTES) return err(413, "too_large", `audio is larger than ${MAX_AUDIO_BYTES} bytes`);
    if (this.usageField("audioBytes") + body.byteLength > this.lim.audioBytesPerDay) {
      const retry = this.secondsToMidnight();
      return json(429, { error: "daily_cap", message: `at most ${Math.floor(this.lim.audioBytesPerDay / 1048576)} MB of voice replies per day`, retryAfterSeconds: retry }, { "retry-after": String(retry) });
    }
    const type = (req.headers.get("content-type") ?? "").split(";")[0].trim();
    if (type !== "audio/mp4" && type !== "audio/x-m4a" && type !== "audio/aac") return err(415, "unsupported_media_type", "audio must be audio/mp4 (m4a)");
    const id = this.getMeta("device_id") ?? "device";
    const key = `${id}/${rid}.m4a`;
    await this.env.AUDIO.put(key, body, { httpMetadata: { contentType: "audio/mp4" } });
    this.sql("UPDATE notes SET audio_key = ?, audio_bytes = ? WHERE rid = ?", key, body.byteLength, rid);
    this.bump("audioUploads");
    this.bump("audioBytes", body.byteLength);
    return json(200, { ok: true, bytes: body.byteLength });
  }

  // ---------- housekeeping

  private async scheduleAlarm() {
    if ((await this.ctx.storage.getAlarm()) == null) await this.ctx.storage.setAlarm(Date.now() + 60 * 60 * 1000);
  }

  async alarm(): Promise<void> {
    const now = Date.now();
    this.persistUsage();
    this.expireSweep(now);
    this.sql("DELETE FROM notes WHERE created_at < ?", now - this.lim.ttlMs - 60 * 60 * 1000);
    this.sql("DELETE FROM rate WHERE at < ?", now - RATE_WINDOW_MS);
    this.sql("DELETE FROM meta WHERE k LIKE 'usage:%' AND k < ?", "usage:" + new Date(now - 7 * DAY_MS).toISOString().slice(0, 10));
    this.expireConsents(now);
    const left = this.sql<{ n: number }>("SELECT COUNT(*) AS n FROM notes")[0].n;
    if (left > 0) await this.ctx.storage.setAlarm(now + 60 * 60 * 1000);
    await this.scheduleConsentAlarm();
  }
}
