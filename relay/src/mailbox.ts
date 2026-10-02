import { DurableObject } from "cloudflare:workers";
import { agentKey, parseToken, type Principal } from "./ids";
import { DAY_MS, bearer, err, hmacHex, json, randomHex, safeEqual, sha256Hex } from "./util";
import { MAX_BODY_BYTES, validateNotification } from "./validate";

export const RATE_LIMIT = 60;
export const RATE_WINDOW_MS = 10 * 60 * 1000;
export const QUEUE_MAX = 200;
export const TTL_MS = DAY_MS;
export const MAX_LONG_POLL_S = 60;
const MAX_KEYS = 20;
// Herald pings every 5 minutes (auto-response, free), so "online" tolerates two missed pings.
const ONLINE_WINDOW_MS = 11 * 60_000;
export const MAX_AUDIO_BYTES = 1024 * 1024;
export const AUDIO_URL_TTL_S = 3600;
// Free-plan budget guards (docs/CLOUD.md "Free plan budget").
export const DAILY_NOTIFICATIONS = 2000;
export const READ_LIMIT = 600;          // receipt / reply reads per 10 min per key
export const SOFT_REQUEST_LIMIT = 90_000; // of the free plan's 100,000 DO requests per UTC day
export const DAILY_POLL_SECONDS = 6000;   // long-poll time per day (the DO is awake while it waits)

type KeyRow = { id: string; name: string; client: string; scope: string; hash: string; created_at: number; revoked_at: number | null; last_used_at: number | null }
type NoteRow = {
  rid: string; key_id: string; nid: string; payload: string; expect_reply: number; created_at: number;
  sent_at: number | null; acked_at: number | null; displayed_at: number | null; spoken_at: number | null;
  replied_at: number | null; reply: string | null; transcript: string | null; audio_key: string | null;
  audio_seconds: number | null; audio_bytes: number | null; suppressed_reason: string | null; suppressed_scope: string | null;
}

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
    `);
  }


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
    if (p.kind !== want) {
      return err(403, "wrong_credential", want === "device"
        ? "agent keys cannot use device endpoints"
        : "the device token cannot be used on agent endpoints; use an agent key");
    }
    if (p.kind === "device") {
      const hash = this.getMeta("device_hash");
      if (!hash || !safeEqual(hash, await sha256Hex(p.secret))) return err(401, "unauthorized", "invalid device token");
      return { p };
    }
    const row = this.sql<KeyRow>("SELECT * FROM keys WHERE id = ?", p.keyId)[0];
    const good = row && !row.revoked_at && safeEqual(row.hash, await sha256Hex(p.secret));
    if (!good) return err(401, "unauthorized", "invalid or revoked agent key");
    if (row.scope !== "notify") return err(403, "scope", "this key has no notify scope");
    this.sql("UPDATE keys SET last_used_at = ? WHERE id = ?", Date.now(), row.id);
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
        if (path === "/v1/device/keys" && m === "GET") return json(200, { keys: this.listKeys() });
        if (path === "/v1/device/keys" && m === "POST") return this.createKey(req, a.p as Extract<Principal, { kind: "device" }>);
        const km = /^\/v1\/device\/keys\/([0-9a-f]{8})$/.exec(path);
        if (km && m === "DELETE") return this.revokeKey(km[1]);
        if (path === "/v1/device" && m === "DELETE") return this.unpair();
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
      id: k.id, name: k.name, client: k.client, scope: k.scope, createdAt: iso(k.created_at),
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
    this.sql("INSERT INTO keys (id, name, client, scope, hash, created_at) VALUES (?, ?, ?, 'notify', ?, ?)", id, name, client, await sha256Hex(secret), now);
    return json(201, { id, name, client, scope: "notify", key: agentKey(p.deviceId, id, secret), createdAt: iso(now) });
  }

  private revokeKey(id: string): Response {
    const row = this.sql<KeyRow>("SELECT * FROM keys WHERE id = ?", id)[0];
    if (!row) return err(404, "not_found", "no such key");
    if (!row.revoked_at) this.sql("UPDATE keys SET revoked_at = ? WHERE id = ?", Date.now(), id);
    return json(200, { revoked: true, id });
  }

  private async unpair(): Promise<Response> {
    const id = this.getMeta("device_id");
    await this.internalWipe();
    if (id) await this.env.REGISTRY.get(this.env.REGISTRY.idFromName("registry")).fetch("https://registry/internal/remove", { method: "POST", body: JSON.stringify({ deviceId: id }) });
    return json(200, { unpaired: true });
  }

  // ---------- usage and free-plan guards

  private today(): string { return new Date().toISOString().slice(0, 10); }

  private bump(field: string, n = 1) {
    const k = "usage:" + this.today();
    let row: Record<string, number> = {};
    try { row = JSON.parse(this.getMeta(k) ?? "{}"); } catch { /* reset */ }
    row[field] = (row[field] ?? 0) + n;
    this.setMeta(k, JSON.stringify(row));
  }

  private usage() {
    let row: Record<string, number> = {};
    try { row = JSON.parse(this.getMeta("usage:" + this.today()) ?? "{}"); } catch { /* none */ }
    const requests = row.requests ?? 0;
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
        requestsPerDay: SOFT_REQUEST_LIMIT, freePlanRequestsPerDay: 100_000, notificationsPerDay: DAILY_NOTIFICATIONS,
        pollSecondsPerDay: DAILY_POLL_SECONDS, queueMax: QUEUE_MAX,
      },
      requestsPercent: Math.round((requests / SOFT_REQUEST_LIMIT) * 100),
      budgetExhausted: requests >= SOFT_REQUEST_LIMIT,
    };
  }

  private secondsToMidnight(): number {
    const n = new Date();
    return Math.max(1, Math.ceil((Date.UTC(n.getUTCFullYear(), n.getUTCMonth(), n.getUTCDate() + 1) - n.getTime()) / 1000));
  }

  /** The relay's own cap, below the free plan's, so Cloudflare never has to cut the Mac off mid-day. */
  private budgetGuard(): Response | null {
    const u = JSON.parse(this.getMeta("usage:" + this.today()) ?? "{}") as Record<string, number>;
    if ((u.requests ?? 0) < SOFT_REQUEST_LIMIT) return null;
    const retry = this.secondsToMidnight();
    return json(503, { error: "budget_exhausted", message: "the relay's daily request budget is used up; nothing queued is lost", retryAfterSeconds: retry }, { "retry-after": String(retry) });
  }

  private readLimit(key: KeyRow, isNotify: boolean): Response | null {
    if (isNotify) return null; // notify has its own, tighter limit
    const now = Date.now(), id = "r:" + key.id;
    const n = this.sql<{ n: number }>("SELECT COUNT(*) AS n FROM rate WHERE key_id = ? AND at > ?", id, now - RATE_WINDOW_MS)[0].n;
    if (n >= READ_LIMIT) {
      return json(429, { error: "rate_limited", message: `at most ${READ_LIMIT} receipt/reply reads per 10 minutes per key`, retryAfterSeconds: 60 }, { "retry-after": "60" });
    }
    this.sql("INSERT INTO rate (key_id, at) VALUES (?, ?)", id, now);
    return null;
  }

  // ---------- status

  private sockets(): WebSocket[] { return this.ctx.getWebSockets(); }

  private lastSeenMs(): number {
    let t = Number(this.getMeta("last_seen") ?? 0);
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
    this.setMeta("status", JSON.stringify(clean));
  }

  private async httpStatus(req: Request): Promise<Response> {
    let b: Record<string, unknown>;
    try { b = (await req.json()) as Record<string, unknown>; } catch { return err(400, "invalid_request", "body must be JSON"); }
    this.applyStatus(b);
    this.setMeta("last_seen", String(Date.now()));
    return json(200, { ok: true });
  }

  // ---------- notify

  private expireSweep(now: number) {
    this.sql(
      "UPDATE notes SET suppressed_reason = 'expired', suppressed_scope = 'all' WHERE acked_at IS NULL AND suppressed_reason IS NULL AND created_at < ?",
      now - TTL_MS,
    );
  }

  private pending(): NoteRow[] {
    return this.sql<NoteRow>(
      "SELECT * FROM notes WHERE acked_at IS NULL AND displayed_at IS NULL AND suppressed_reason IS NULL AND created_at >= ? ORDER BY created_at, rowid",
      Date.now() - TTL_MS,
    );
  }

  private async notify(req: Request, key: KeyRow): Promise<Response> {
    const declared = Number(req.headers.get("content-length") ?? 0);
    if (declared > MAX_BODY_BYTES) return err(413, "too_large", `body is larger than ${MAX_BODY_BYTES} bytes`);
    const text = await req.text();
    if (new TextEncoder().encode(text).length > MAX_BODY_BYTES) return err(413, "too_large", `body is larger than ${MAX_BODY_BYTES} bytes`);
    let input: unknown;
    try { input = JSON.parse(text); } catch { return err(400, "invalid_request", "body must be JSON"); }
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
    if (used.n >= RATE_LIMIT) {
      const retry = Math.max(1, Math.ceil((used.oldest + RATE_WINDOW_MS - now) / 1000));
      return json(429, { error: "rate_limited", message: `at most ${RATE_LIMIT} notifications per 10 minutes per key`, retryAfterSeconds: retry }, { "retry-after": String(retry) });
    }
    const today = JSON.parse(this.getMeta("usage:" + this.today()) ?? "{}") as Record<string, number>;
    if ((today.notifications ?? 0) >= DAILY_NOTIFICATIONS) {
      const retry = this.secondsToMidnight();
      return json(429, { error: "daily_cap", message: `at most ${DAILY_NOTIFICATIONS} notifications per day`, retryAfterSeconds: retry }, { "retry-after": String(retry) });
    }
    this.expireSweep(now);
    if (this.pending().length >= QUEUE_MAX) {
      return err(429, "queue_full", `the Mac has ${QUEUE_MAX} undelivered notifications waiting; it has been offline too long`);
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
    pair[1].send(JSON.stringify({ type: "welcome", ttlSeconds: TTL_MS / 1000 }));
    this.expireSweep(Date.now());
    this.flush(true);
    return new Response(null, { status: 101, webSocket: pair[0] });
  }

  async webSocketMessage(ws: WebSocket, message: string | ArrayBuffer): Promise<void> {
    if (typeof message !== "string" || message.length > 16 * 1024) return;
    let m: Record<string, unknown>;
    try { m = JSON.parse(message); } catch { return; }
    this.setMeta("last_seen", String(Date.now()));
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
    try { ws.close(code, reason); } catch { /* already closed */ }
  }

  async webSocketError(): Promise<void> { this.setMeta("last_seen", String(Date.now())); }

  // ---------- receipts from Herald

  private async httpReceipt(req: Request, forceKind?: string): Promise<Response> {
    let b: Record<string, unknown>;
    try { b = (await req.json()) as Record<string, unknown>; } catch { return err(400, "invalid_request", "body must be JSON"); }
    this.setMeta("last_seen", String(Date.now()));
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
    const spent = (JSON.parse(this.getMeta("usage:" + this.today()) ?? "{}") as Record<string, number>).pollSeconds ?? 0;
    if (spent >= DAILY_POLL_SECONDS) seconds = 0; // the DO is awake while it waits; stop holding polls when the day's allowance is gone
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
    const body = await req.arrayBuffer();
    if (body.byteLength === 0) return err(400, "invalid_request", "empty audio");
    if (body.byteLength > MAX_AUDIO_BYTES) return err(413, "too_large", `audio is larger than ${MAX_AUDIO_BYTES} bytes`);
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
    this.expireSweep(now);
    this.sql("DELETE FROM notes WHERE created_at < ?", now - TTL_MS - 60 * 60 * 1000);
    this.sql("DELETE FROM rate WHERE at < ?", now - RATE_WINDOW_MS);
    this.sql("DELETE FROM meta WHERE k LIKE 'usage:%' AND k < ?", "usage:" + new Date(now - 7 * DAY_MS).toISOString().slice(0, 10));
    const left = this.sql<{ n: number }>("SELECT COUNT(*) AS n FROM notes")[0].n;
    if (left > 0) await this.ctx.storage.setAlarm(now + 60 * 60 * 1000);
  }
}
