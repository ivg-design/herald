var __defProp = Object.defineProperty;
var __name = (target, value) => __defProp(target, "name", { value, configurable: true });

// src/util.ts
var enc = new TextEncoder();
function bytesToHex(b) {
  return [...b].map((x) => x.toString(16).padStart(2, "0")).join("");
}
__name(bytesToHex, "bytesToHex");
function randomHex(bytes) {
  return bytesToHex(crypto.getRandomValues(new Uint8Array(bytes)));
}
__name(randomHex, "randomHex");
async function sha256Hex(text) {
  return bytesToHex(new Uint8Array(await crypto.subtle.digest("SHA-256", enc.encode(text))));
}
__name(sha256Hex, "sha256Hex");
async function hmacHex(secret, text) {
  const key = await crypto.subtle.importKey("raw", enc.encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  return bytesToHex(new Uint8Array(await crypto.subtle.sign("HMAC", key, enc.encode(text))));
}
__name(hmacHex, "hmacHex");
function safeEqual(a, b) {
  const x = enc.encode(a), y = enc.encode(b);
  let diff = x.length ^ y.length;
  const n = Math.max(x.length, y.length);
  for (let i = 0; i < n; i++) diff |= (x[i] ?? 0) ^ (y[i] ?? 0);
  return diff === 0;
}
__name(safeEqual, "safeEqual");
function json(status, body, headers = {}) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json; charset=utf-8", "cache-control": "no-store", ...headers }
  });
}
__name(json, "json");
function err(status, error, message, extra = {}) {
  return json(status, { error, message, ...extra });
}
__name(err, "err");
function bearer(req) {
  const h = req.headers.get("authorization") ?? "";
  const m = /^Bearer\s+(\S+)$/i.exec(h);
  return m ? m[1] : null;
}
__name(bearer, "bearer");
var DAY_MS = 24 * 60 * 60 * 1e3;

// src/ids.ts
async function newDeviceId(relaySecret) {
  const r = randomHex(16);
  return r + (await hmacHex(relaySecret, "device:" + r)).slice(0, 16);
}
__name(newDeviceId, "newDeviceId");
async function deviceIdValid(relaySecret, id) {
  if (!/^[0-9a-f]{48}$/.test(id)) return false;
  const mac = (await hmacHex(relaySecret, "device:" + id.slice(0, 32))).slice(0, 16);
  return safeEqual(mac, id.slice(32));
}
__name(deviceIdValid, "deviceIdValid");
function parseToken(token2) {
  const p = token2.split("_");
  if (p[0] === "hrd" && p.length === 3 && /^[0-9a-f]{48}$/.test(p[1]) && /^[0-9a-f]{64}$/.test(p[2])) {
    return { kind: "device", deviceId: p[1], secret: p[2] };
  }
  if (p[0] === "hrk" && p.length === 4 && /^[0-9a-f]{48}$/.test(p[1]) && /^[0-9a-f]{8}$/.test(p[2]) && /^[0-9a-f]{64}$/.test(p[3])) {
    return { kind: "agent", deviceId: p[1], keyId: p[2], secret: p[3] };
  }
  if (p[0] === "hra" && p.length === 3 && /^[0-9a-f]{48}$/.test(p[1]) && /^[0-9a-f]{64}$/.test(p[2])) {
    return { kind: "oauth", deviceId: p[1], secret: p[2] };
  }
  return null;
}
__name(parseToken, "parseToken");
function parseOAuthSecret(token2, prefix) {
  const p = token2.split("_");
  if (p[0] === prefix && p.length === 3 && /^[0-9a-f]{48}$/.test(p[1]) && /^[0-9a-f]{32,64}$/.test(p[2])) return { deviceId: p[1] };
  return null;
}
__name(parseOAuthSecret, "parseOAuthSecret");
var oauthToken = /* @__PURE__ */ __name((prefix, deviceId, secret) => `${prefix}_${deviceId}_${secret}`, "oauthToken");
var deviceToken = /* @__PURE__ */ __name((deviceId, secret) => `hrd_${deviceId}_${secret}`, "deviceToken");
var agentKey = /* @__PURE__ */ __name((deviceId, keyId, secret) => `hrk_${deviceId}_${keyId}_${secret}`, "agentKey");

// src/mailbox.ts
import { DurableObject } from "cloudflare:workers";

// src/limits.ts
var DEFAULT_LIMITS = {
  notificationsPerDay: 500,
  queueMax: 100,
  requestsPerDay: 5e3,
  audioUploadsPerDay: 40,
  audioBytesPerDay: 20 * 1024 * 1024,
  pollSecondsPerDay: 3e3,
  ttlMs: 24 * 36e5,
  bodyBytes: 32 * 1024,
  ratePerKey: 60
};
var VARS = {
  notificationsPerDay: "DEVICE_NOTIFICATIONS_PER_DAY",
  queueMax: "DEVICE_QUEUE_MAX",
  requestsPerDay: "DEVICE_REQUESTS_PER_DAY",
  audioUploadsPerDay: "DEVICE_AUDIO_UPLOADS_PER_DAY",
  audioBytesPerDay: "DEVICE_AUDIO_BYTES_PER_DAY",
  pollSecondsPerDay: "DEVICE_POLL_SECONDS_PER_DAY",
  ttlMs: "QUEUE_TTL_HOURS",
  bodyBytes: "MAX_BODY_BYTES",
  ratePerKey: "RATE_LIMIT_PER_KEY"
};
function limitsFor(env) {
  const e = env ?? {};
  const out = { ...DEFAULT_LIMITS };
  for (const k of Object.keys(VARS)) {
    const n = Number(e[VARS[k]]);
    if (Number.isFinite(n) && n > 0) out[k] = Math.floor(k === "ttlMs" ? n * 36e5 : n);
  }
  return out;
}
__name(limitsFor, "limitsFor");

// src/validate.ts
var MAX_BODY_BYTES = 32 * 1024;
var MAX_NOTIFICATION_ID = 128;
var DANGEROUS = /* @__PURE__ */ new Set([
  "command",
  "commands",
  "cmd",
  "script",
  "scripts",
  "shortcut",
  "shortcuts",
  "callback",
  "callbacks",
  "webhook",
  "buttons",
  "actions",
  "actionIds",
  "action",
  "reminder",
  "url",
  "audio",
  "image",
  "icon",
  "template",
  "layout",
  "app",
  "appId",
  "sound",
  "path",
  "exec",
  "run",
  "open",
  "openApp"
]);
var ALLOWED = /* @__PURE__ */ new Set([
  "notificationId",
  "title",
  "subtitle",
  "body",
  "status",
  "project",
  "session",
  "task",
  "tool",
  "duration",
  "link",
  "group",
  "priority",
  "speak",
  "expectReply",
  "allowVoiceReply"
]);
var bad = /* @__PURE__ */ __name((message, fields) => ({ ok: false, error: "invalid_request", message, fields }), "bad");
function str(v, name, max) {
  if (v === void 0 || v === null) return void 0;
  if (typeof v !== "string") return bad(`${name} must be a string`, [name]);
  const t = v.trim();
  if (t.length > max) return bad(`${name} is longer than ${max} characters`, [name]);
  return t.length ? t : void 0;
}
__name(str, "str");
var isBad = /* @__PURE__ */ __name((x) => typeof x === "object" && x !== null && "ok" in x, "isBad");
function validateNotification(input) {
  if (typeof input !== "object" || input === null || Array.isArray(input)) return bad("the body must be a JSON object");
  const o = input;
  const rejected = Object.keys(o).filter((k) => !ALLOWED.has(k));
  if (rejected.length) {
    const named = rejected.filter((k) => DANGEROUS.has(k));
    return {
      ok: false,
      error: "forbidden_fields",
      fields: rejected,
      message: `rejected fields: ${rejected.join(", ")}. Cloud notifications carry text only` + (named.length ? ` (${named.join(", ")} would run or open something on the Mac and is never accepted)` : "") + `. Accepted fields: ${[...ALLOWED].join(", ")}.`
    };
  }
  let notificationId;
  if (o.notificationId !== void 0) {
    if (typeof o.notificationId !== "string" || !/^[A-Za-z0-9._:-]{1,128}$/.test(o.notificationId)) {
      return bad(`notificationId must match [A-Za-z0-9._:-] and be at most ${MAX_NOTIFICATION_ID} characters`, ["notificationId"]);
    }
    notificationId = o.notificationId;
  }
  const title = str(o.title, "title", 200);
  if (isBad(title)) return title;
  if (!title) return bad("title is required", ["title"]);
  const out = { title, expectReply: false };
  for (const [k, max] of [["subtitle", 200], ["body", 8e3], ["project", 100], ["session", 100], ["task", 100], ["tool", 100], ["group", 100]]) {
    const v = str(o[k], k, max);
    if (isBad(v)) return v;
    if (v !== void 0) out[k] = v;
  }
  const status = str(o.status, "status", 32);
  if (isBad(status)) return status;
  if (status !== void 0) {
    if (!/^[A-Za-z0-9_-]{1,32}$/.test(status)) return bad("status must be a short word (letters, digits, - or _)", ["status"]);
    out.status = status.toLowerCase();
  }
  if (o.duration !== void 0 && o.duration !== null) {
    if (typeof o.duration === "number" && Number.isFinite(o.duration)) out.duration = String(o.duration);
    else {
      const d = str(o.duration, "duration", 40);
      if (isBad(d)) return d;
      out.duration = d;
    }
  }
  const link = str(o.link, "link", 2048);
  if (isBad(link)) return link;
  if (link !== void 0) {
    let u;
    try {
      u = new URL(link);
    } catch {
      return bad("link must be an absolute https URL", ["link"]);
    }
    if (u.protocol !== "https:") return bad("link must be an https URL", ["link"]);
    out.link = u.toString();
  }
  if (o.priority !== void 0 && o.priority !== null) {
    if (o.priority !== "normal" && o.priority !== "urgent") return bad('priority must be "normal" or "urgent"', ["priority"]);
    out.priority = o.priority;
  }
  if (o.expectReply !== void 0 && o.expectReply !== null) {
    if (typeof o.expectReply !== "boolean") return bad("expectReply must be true or false", ["expectReply"]);
    out.expectReply = o.expectReply;
  }
  if (o.allowVoiceReply !== void 0 && o.allowVoiceReply !== null) {
    if (typeof o.allowVoiceReply !== "boolean") return bad("allowVoiceReply must be true or false", ["allowVoiceReply"]);
    out.allowVoiceReply = o.allowVoiceReply;
  }
  if (o.speak !== void 0 && o.speak !== null && o.speak !== false) {
    if (o.speak === true) out.speak = true;
    else if (typeof o.speak === "object" && !Array.isArray(o.speak)) {
      const s = o.speak;
      const extra = Object.keys(s).filter((k) => !["text", "voice", "speed", "lang"].includes(k));
      if (extra.length) return { ok: false, error: "forbidden_fields", fields: extra.map((k) => "speak." + k), message: `rejected fields: ${extra.map((k) => "speak." + k).join(", ")}. speak accepts text, voice, speed, lang.` };
      const sp = {};
      const text = str(s.text, "speak.text", 2e3);
      if (isBad(text)) return text;
      if (text) sp.text = text;
      if (s.voice !== void 0) {
        if (typeof s.voice !== "string" || !/^[A-Za-z0-9_]{1,40}$/.test(s.voice)) return bad("speak.voice must be a voice name such as af_heart", ["speak.voice"]);
        sp.voice = s.voice;
      }
      if (s.speed !== void 0) {
        if (typeof s.speed !== "number" || !(s.speed >= 0.5 && s.speed <= 2)) return bad("speak.speed must be between 0.5 and 2", ["speak.speed"]);
        sp.speed = s.speed;
      }
      if (s.lang !== void 0) {
        if (typeof s.lang !== "string" || !/^[A-Za-z]{2,3}(-[A-Za-z0-9]{2,8})?$/.test(s.lang)) return bad("speak.lang must be a language code such as en-us", ["speak.lang"]);
        sp.lang = s.lang;
      }
      out.speak = sp;
    } else return bad("speak must be true or an object {text, voice, speed, lang}", ["speak"]);
  }
  return { ok: true, notificationId, value: out };
}
__name(validateNotification, "validateNotification");

// src/mailbox.ts
var RATE_WINDOW_MS = 10 * 60 * 1e3;
var MAX_LONG_POLL_S = 60;
var MAX_KEYS = 20;
var ONLINE_WINDOW_MS = 11 * 6e4;
var MAX_AUDIO_BYTES = 1024 * 1024;
var AUDIO_URL_TTL_S = 3600;
var READ_LIMIT = 600;
var OAUTH_REQUEST_TTL_MS = 10 * 6e4;
var OAUTH_CODE_TTL_MS = 5 * 6e4;
var OAUTH_ACCESS_TTL_S = 3600;
var OAUTH_REFRESH_TTL_S = 30 * 86400;
var OAUTH_MAX_PENDING = 3;
var OAUTH_BEGINS_PER_HOUR = 12;
var OAUTH_CODE_ATTEMPTS = 5;
async function s256(v) {
  const d = new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(v)));
  return btoa(String.fromCharCode(...d)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}
__name(s256, "s256");
var sameResource = /* @__PURE__ */ __name((a, b) => a.replace(/\/+$/, "") === b.replace(/\/+$/, ""), "sameResource");
var iso = /* @__PURE__ */ __name((t) => t == null ? void 0 : new Date(t).toISOString(), "iso");
var Mailbox = class extends DurableObject {
  static {
    __name(this, "Mailbox");
  }
  waiters = /* @__PURE__ */ new Map();
  constructor(ctx, env) {
    super(ctx, env);
    this.ensureSchema();
    ctx.setWebSocketAutoResponse(new WebSocketRequestResponsePair("ping", "pong"));
  }
  // ---------- storage helpers
  ensureSchema() {
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
      try {
        this.ctx.storage.sql.exec(`ALTER TABLE keys ADD COLUMN ${col}`);
      } catch {
      }
    }
  }
  /** This device's limits (per device: each Mac has its own mailbox and its own counters). */
  get lim() {
    return limitsFor(this.env);
  }
  sql(q, ...b) {
    return this.ctx.storage.sql.exec(q, ...b).toArray();
  }
  getMeta(k) {
    return this.sql("SELECT v FROM meta WHERE k = ?", k)[0]?.v;
  }
  setMeta(k, v) {
    this.sql("INSERT INTO meta (k, v) VALUES (?, ?) ON CONFLICT(k) DO UPDATE SET v = excluded.v", k, v);
  }
  note(rid) {
    return this.sql("SELECT * FROM notes WHERE rid = ?", rid)[0];
  }
  noteByNid(keyId, nid) {
    return this.sql("SELECT * FROM notes WHERE key_id = ? AND nid = ?", keyId, nid)[0];
  }
  // ---------- auth
  async authenticate(req, want) {
    const token2 = bearer(req);
    const p = token2 ? parseToken(token2) : null;
    if (!token2 || !p) return err(401, "unauthorized", "missing or malformed bearer token");
    const have = p.kind === "oauth" ? "agent" : p.kind;
    if (have !== want) {
      return err(403, "wrong_credential", want === "device" ? "agent keys cannot use device endpoints" : "the device token cannot be used on agent endpoints; use an agent key");
    }
    if (p.kind === "device") {
      const hash = this.getMeta("device_hash");
      if (!hash || !safeEqual(hash, await sha256Hex(p.secret))) return err(401, "unauthorized", "invalid device token");
      return { p };
    }
    let row;
    let good;
    if (p.kind === "oauth") {
      const t = this.sql("SELECT * FROM oauth_tokens WHERE hash = ? AND kind = 'access'", await sha256Hex(p.secret))[0];
      row = t && t.expires_at > Date.now() ? this.sql("SELECT * FROM keys WHERE id = ?", t.key_id)[0] : void 0;
      good = !!row && !row.revoked_at;
    } else {
      row = this.sql("SELECT * FROM keys WHERE id = ?", p.keyId)[0];
      good = !!row && !row.revoked_at && row.kind !== "oauth" && safeEqual(row.hash, await sha256Hex(p.secret));
    }
    if (!good || !row) return err(401, "unauthorized", p.kind === "oauth" ? "invalid, expired or revoked access token" : "invalid or revoked agent key");
    if (row.scope !== "notify") return err(403, "scope", "this key has no notify scope");
    if (!row.last_used_at || Date.now() - row.last_used_at > 10 * 6e4) this.sql("UPDATE keys SET last_used_at = ? WHERE id = ?", Date.now(), row.id);
    return { p, key: row };
  }
  // ---------- routing
  async fetch(req) {
    const url = new URL(req.url);
    const path = url.pathname;
    const m = req.method;
    try {
      if (path === "/internal/init" && m === "POST") return this.internalInit(req);
      if (path === "/internal/wipe" && m === "POST") return this.internalWipe();
      if (path.startsWith("/internal/oauth/") && m === "POST") return this.oauthInternal(path.slice("/internal/oauth/".length), req);
      if (path.startsWith("/v1/device")) {
        const a2 = await this.authenticate(req, "device");
        if (a2 instanceof Response) return a2;
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
        if (path === "/v1/device/keys" && m === "POST") return this.createKey(req, a2.p);
        const km = /^\/v1\/device\/keys\/([0-9a-f]{8})$/.exec(path);
        if (km && m === "DELETE") return this.revokeKey(km[1]);
        if (path === "/v1/device" && m === "DELETE") return this.unpair();
        return err(404, "not_found", "no such device endpoint");
      }
      const a = await this.authenticate(req, "agent");
      if (a instanceof Response) return a;
      const key = a.key;
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
  async internalInit(req) {
    const { tokenHash, deviceId } = await req.json();
    this.setMeta("device_hash", tokenHash);
    this.setMeta("device_id", deviceId);
    this.setMeta("paired_at", String(Date.now()));
    return json(200, { ok: true });
  }
  async internalWipe() {
    for (const ws of this.ctx.getWebSockets()) {
      try {
        ws.close(4001, "unpaired");
      } catch {
      }
    }
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
  listKeys() {
    return this.sql("SELECT * FROM keys ORDER BY created_at").map((k) => ({
      id: k.id,
      name: k.name,
      client: k.client,
      scope: k.scope,
      kind: k.kind ?? "static",
      ...k.client_name ? { displayName: k.client_name } : {},
      createdAt: iso(k.created_at),
      lastUsedAt: iso(k.last_used_at),
      revokedAt: iso(k.revoked_at)
    }));
  }
  async createKey(req, p) {
    let b;
    try {
      b = await req.json();
    } catch {
      return err(400, "invalid_request", "body must be JSON");
    }
    const extra = Object.keys(b).filter((k) => !["name", "client", "scope"].includes(k));
    if (extra.length) return err(400, "forbidden_fields", `rejected fields: ${extra.join(", ")}`, { fields: extra });
    const scope = b.scope ?? "notify";
    if (scope !== "notify") return err(400, "scope_not_allowed", 'the only scope is "notify"');
    const name = typeof b.name === "string" ? b.name.trim().toLowerCase() : "";
    if (!/^[a-z0-9][a-z0-9-]{0,31}$/.test(name)) return err(400, "invalid_request", "name must be 1-32 characters: a-z, 0-9 and -");
    const client = b.client === void 0 ? "other" : b.client;
    if (client !== "claude" && client !== "codex" && client !== "other") return err(400, "invalid_request", 'client must be "claude", "codex" or "other"');
    const rows = this.sql("SELECT * FROM keys WHERE revoked_at IS NULL");
    if (rows.some((k) => k.name === name)) return err(409, "name_taken", `a key named ${name} already exists`);
    if (rows.length >= MAX_KEYS) return err(429, "too_many_keys", `at most ${MAX_KEYS} active keys`);
    const id = randomHex(4), secret = randomHex(32), now = Date.now();
    this.sql("INSERT INTO keys (id, name, client, scope, hash, created_at, kind) VALUES (?, ?, ?, 'notify', ?, ?, 'static')", id, name, client, await sha256Hex(secret), now);
    return json(201, { id, name, client, scope: "notify", kind: "static", key: agentKey(p.deviceId, id, secret), createdAt: iso(now) });
  }
  revokeKey(id) {
    const row = this.sql("SELECT * FROM keys WHERE id = ?", id)[0];
    if (!row) return err(404, "not_found", "no such key");
    if (!row.revoked_at) this.sql("UPDATE keys SET revoked_at = ? WHERE id = ?", Date.now(), id);
    this.sql("DELETE FROM oauth_tokens WHERE key_id = ?", id);
    return json(200, { revoked: true, id });
  }
  async unpair() {
    const id = this.getMeta("device_id");
    await this.internalWipe();
    if (id) await this.env.REGISTRY.get(this.env.REGISTRY.idFromName("registry")).fetch("https://registry/internal/remove", { method: "POST", body: JSON.stringify({ deviceId: id }) });
    return json(200, { unpaired: true });
  }
  // ---------- usage and free-plan guards
  today() {
    return (/* @__PURE__ */ new Date()).toISOString().slice(0, 10);
  }
  // Free-plan budget: the daily counters live in memory and are written at most once a minute (and by the hourly alarm), so a
  // request does not cost a row write. An eviction loses at most a minute of counting.
  usageDay = "";
  usageRow = {};
  usagePersistedAt = 0;
  lastSeenMem = 0;
  readHits = /* @__PURE__ */ new Map();
  loadUsage() {
    const day = this.today();
    if (this.usageDay !== day) {
      this.usageDay = day;
      try {
        this.usageRow = JSON.parse(this.getMeta("usage:" + day) ?? "{}");
      } catch {
        this.usageRow = {};
      }
    }
    return this.usageRow;
  }
  bump(field, n = 1) {
    const row = this.loadUsage();
    row[field] = (row[field] ?? 0) + n;
    if (Date.now() - this.usagePersistedAt > 6e4) this.persistUsage();
  }
  persistUsage() {
    this.setMeta("usage:" + this.usageDay, JSON.stringify(this.usageRow));
    this.usagePersistedAt = Date.now();
  }
  /** Notifications and long-poll seconds are persisted when they change the budget decisions that matter. */
  usageField(field) {
    return this.loadUsage()[field] ?? 0;
  }
  usage() {
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
        audioUploadsPerDay: lim.audioUploadsPerDay,
        audioBytesPerDay: lim.audioBytesPerDay,
        requestsPerDay: lim.requestsPerDay,
        freePlanRequestsPerDay: 1e5,
        notificationsPerDay: lim.notificationsPerDay,
        pollSecondsPerDay: lim.pollSecondsPerDay,
        queueMax: lim.queueMax
      },
      requestsPercent: Math.round(requests / lim.requestsPerDay * 100),
      budgetExhausted: requests >= lim.requestsPerDay
    };
  }
  secondsToMidnight() {
    const n = /* @__PURE__ */ new Date();
    return Math.max(1, Math.ceil((Date.UTC(n.getUTCFullYear(), n.getUTCMonth(), n.getUTCDate() + 1) - n.getTime()) / 1e3));
  }
  /** The relay's own cap, below the free plan's, so Cloudflare never has to cut the Mac off mid-day. */
  budgetGuard() {
    if (this.usageField("requests") < this.lim.requestsPerDay) return null;
    const retry = this.secondsToMidnight();
    return json(503, { error: "budget_exhausted", message: "this Mac's daily request budget on the relay is used up; nothing queued is lost", retryAfterSeconds: retry }, { "retry-after": String(retry) });
  }
  readLimit(key, isNotify) {
    if (isNotify) return null;
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
  sockets() {
    return this.ctx.getWebSockets();
  }
  touch() {
    this.lastSeenMem = Date.now();
  }
  lastSeenMs() {
    let t = Math.max(this.lastSeenMem, Number(this.getMeta("last_seen") ?? 0));
    for (const ws of this.sockets()) {
      const a = this.ctx.getWebSocketAutoResponseTimestamp(ws);
      if (a) t = Math.max(t, a.getTime());
    }
    return t;
  }
  online() {
    return this.sockets().length > 0 && Date.now() - this.lastSeenMs() < ONLINE_WINDOW_MS;
  }
  quietState() {
    try {
      const s = JSON.parse(this.getMeta("status") ?? "{}");
      return { active: !!s.quietActive, ...s.quietUntil ? { until: s.quietUntil } : {} };
    } catch {
      return { active: false };
    }
  }
  /** What an agent may learn about the Mac: reachable or not, and whether quiet hours are on. */
  agentStatus() {
    const seen = this.lastSeenMs();
    return { online: this.online(), ...seen ? { lastSeenAt: new Date(seen).toISOString() } : {}, quietHours: this.quietState() };
  }
  info() {
    const seen = this.lastSeenMs();
    const pending = this.pending().length;
    return {
      online: this.online(),
      ...seen ? { lastSeenAt: new Date(seen).toISOString() } : {},
      pending,
      quietHours: this.quietState(),
      keys: this.listKeys().filter((k) => !k.revokedAt).length
    };
  }
  applyStatus(s) {
    const clean = {
      quietActive: s.quietActive === true,
      quietUntil: typeof s.quietUntil === "string" ? s.quietUntil.slice(0, 40) : void 0,
      muted: s.muted === true
    };
    const next = JSON.stringify(clean);
    if (this.getMeta("status") !== next) this.setMeta("status", next);
  }
  async httpStatus(req) {
    let b;
    try {
      b = await req.json();
    } catch {
      return err(400, "invalid_request", "body must be JSON");
    }
    this.applyStatus(b);
    this.touch();
    return json(200, { ok: true });
  }
  // ---------- notify
  expireSweep(now) {
    this.sql(
      "UPDATE notes SET suppressed_reason = 'expired', suppressed_scope = 'all' WHERE acked_at IS NULL AND suppressed_reason IS NULL AND created_at < ?",
      now - this.lim.ttlMs
    );
  }
  pending() {
    return this.sql(
      "SELECT * FROM notes WHERE acked_at IS NULL AND displayed_at IS NULL AND suppressed_reason IS NULL AND created_at >= ? ORDER BY created_at, rowid",
      Date.now() - this.lim.ttlMs
    );
  }
  async notify(req, key) {
    const declared = Number(req.headers.get("content-length") ?? 0);
    if (declared > this.lim.bodyBytes) return err(413, "too_large", `body is larger than ${this.lim.bodyBytes} bytes`);
    const text = await req.text();
    if (new TextEncoder().encode(text).length > this.lim.bodyBytes) return err(413, "too_large", `body is larger than ${this.lim.bodyBytes} bytes`);
    let input;
    try {
      input = JSON.parse(text);
    } catch {
      return err(400, "invalid_request", "body must be JSON");
    }
    const v = validateNotification(input);
    if (!v.ok) return err(400, v.error, v.message, v.fields ? { fields: v.fields } : {});
    const now = Date.now();
    const nid = v.notificationId ?? "n_" + randomHex(12);
    const dup = this.noteByNid(key.id, nid);
    if (dup && dup.created_at >= now - DAY_MS) {
      return json(200, { duplicate: true, ...await this.receiptBody(dup, new URL(req.url).origin) });
    }
    if (dup) this.sql("DELETE FROM notes WHERE rid = ?", dup.rid);
    const used = this.sql("SELECT COUNT(*) AS n, MIN(at) AS oldest FROM rate WHERE key_id = ? AND at > ?", key.id, now - RATE_WINDOW_MS)[0];
    if (used.n >= this.lim.ratePerKey) {
      const retry = Math.max(1, Math.ceil((used.oldest + RATE_WINDOW_MS - now) / 1e3));
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
      rid,
      key.id,
      nid,
      JSON.stringify(v.value),
      v.value.expectReply ? 1 : 0,
      now
    );
    this.sql("INSERT INTO rate (key_id, at) VALUES (?, ?)", key.id, now);
    this.bump("notifications");
    await this.scheduleAlarm();
    this.flush();
    const row = this.note(rid);
    return json(202, { duplicate: false, ...await this.receiptBody(row, new URL(req.url).origin) });
  }
  // ---------- delivery over the socket
  envelope(n) {
    const k = this.sql("SELECT * FROM keys WHERE id = ?", n.key_id)[0];
    return {
      type: "notify",
      id: n.rid,
      notificationId: n.nid,
      createdAt: new Date(n.created_at).toISOString(),
      key: { id: n.key_id, name: k?.name ?? "unknown", client: k?.client ?? "other" },
      payload: JSON.parse(n.payload)
    };
  }
  /** `resend` sends everything not yet acknowledged (a fresh connection); otherwise only what was never sent. */
  flush(resend = false) {
    const ws = this.sockets()[0];
    if (!ws) return;
    const now = Date.now();
    for (const n of this.pending()) {
      if (!resend && n.sent_at != null) continue;
      try {
        ws.send(JSON.stringify(this.envelope(n)));
        this.sql("UPDATE notes SET sent_at = ? WHERE rid = ?", now, n.rid);
      } catch {
        return;
      }
    }
  }
  stream(req) {
    if (req.headers.get("upgrade")?.toLowerCase() !== "websocket") return err(426, "upgrade_required", "WebSocket upgrade required");
    for (const old of this.sockets()) {
      try {
        old.close(4e3, "replaced by a newer connection");
      } catch {
      }
    }
    const pair = new WebSocketPair();
    this.ctx.acceptWebSocket(pair[1]);
    this.setMeta("last_seen", String(Date.now()));
    pair[1].send(JSON.stringify({ type: "welcome", ttlSeconds: this.lim.ttlMs / 1e3 }));
    this.expireSweep(Date.now());
    this.flush(true);
    for (const r of this.pendingRequests()) this.sendConsent(r);
    return new Response(null, { status: 101, webSocket: pair[0] });
  }
  async webSocketMessage(ws, message) {
    if (typeof message !== "string" || message.length > 16 * 1024) return;
    let m;
    try {
      m = JSON.parse(message);
    } catch {
      return;
    }
    this.touch();
    this.bump("wsMessages");
    switch (m.type) {
      case "hello":
      case "status":
        this.applyStatus(m);
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
  async webSocketClose(ws, code, reason) {
    this.setMeta("last_seen", String(Date.now()));
    try {
      ws.close(code, reason);
    } catch {
    }
  }
  async webSocketError() {
    this.setMeta("last_seen", String(Date.now()));
  }
  // ---------- OAuth (connector approvals). Reached only through the Worker's /authorize and /token routes.
  pendingRequests() {
    return this.sql("SELECT * FROM oauth_requests WHERE status = 'pending' AND expires_at > ? ORDER BY created_at", Date.now());
  }
  redirectHost(uri) {
    try {
      const u = new URL(uri);
      return u.host || u.protocol;
    } catch {
      return "";
    }
  }
  consentView(r) {
    return {
      id: r.id,
      clientId: r.client_id,
      clientName: r.client_name,
      redirectHost: this.redirectHost(r.redirect_uri),
      scope: r.scope,
      code: r.user_code,
      status: r.status === "pending" && r.expires_at <= Date.now() ? "expired" : r.status,
      createdAt: iso(r.created_at),
      expiresAt: iso(r.expires_at)
    };
  }
  sendConsent(r) {
    const ws = this.sockets()[0];
    if (!ws) return;
    try {
      ws.send(JSON.stringify({ type: "consent", ...this.consentView(r) }));
    } catch {
    }
  }
  sendResolved(r) {
    const ws = this.sockets()[0];
    if (!ws) return;
    try {
      ws.send(JSON.stringify({ type: "consent_resolved", id: r.id, status: r.status }));
    } catch {
    }
  }
  /** Requests of the last day, newest first (Herald shows them under Connector approvals). */
  consentList() {
    return this.sql("SELECT * FROM oauth_requests WHERE created_at > ? ORDER BY created_at DESC LIMIT 20", Date.now() - DAY_MS).map((r) => this.consentView(r));
  }
  oauthSweep(now) {
    this.sql("DELETE FROM oauth_requests WHERE created_at < ?", now - DAY_MS);
    this.sql("DELETE FROM oauth_tokens WHERE expires_at < ?", now - DAY_MS);
  }
  async oauthInternal(op, req) {
    const b = await req.json().catch(() => ({}));
    const now = Date.now();
    this.oauthSweep(now);
    switch (op) {
      case "begin":
        return this.oauthBegin(b, now);
      case "status":
        return this.oauthStatus(b.id ?? "", now);
      case "code":
        return this.oauthCode(b.id ?? "", b.code ?? "", now);
      case "deny":
        return this.oauthDecide(b.id ?? "", "deny", now);
      case "token":
        return this.oauthTokenEndpoint(b, now);
      case "revoke":
        return this.oauthRevoke(b);
    }
    return err(404, "not_found", "no such oauth operation");
  }
  async oauthBegin(b, now) {
    if (this.pendingRequests().length >= OAUTH_MAX_PENDING) return err(429, "rate_limited", "approvals are already waiting in Herald; answer them or wait 10 minutes", { retryAfterSeconds: 600 });
    if (this.sql("SELECT COUNT(*) AS n FROM oauth_requests WHERE created_at > ?", now - 36e5)[0].n >= OAUTH_BEGINS_PER_HOUR) {
      return err(429, "rate_limited", "too many connector requests; try again in an hour", { retryAfterSeconds: 3600 });
    }
    const deviceId = this.getMeta("device_id");
    if (!deviceId) return err(404, "not_paired", "this relay has no paired Herald");
    const id = deviceId + randomHex(12);
    const userCode = String(crypto.getRandomValues(new Uint32Array(1))[0] % 1e6).padStart(6, "0");
    this.sql(
      "INSERT INTO oauth_requests (id, client_id, client_name, redirect_uri, challenge, state, scope, resource, user_code, status, created_at, expires_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 'pending', ?, ?)",
      id,
      b.clientId ?? "",
      (b.clientName ?? "").slice(0, 60),
      b.redirectUri ?? "",
      b.challenge ?? "",
      b.state ?? null,
      b.scope ?? "notify",
      b.resource ?? "",
      userCode,
      now,
      now + OAUTH_REQUEST_TTL_MS
    );
    this.sendConsent(this.sql("SELECT * FROM oauth_requests WHERE id = ?", id)[0]);
    return json(201, { id, expiresAt: iso(now + OAUTH_REQUEST_TTL_MS), online: this.online() });
  }
  redirectFor(r) {
    const u = new URL(r.redirect_uri);
    if (r.status === "approved" && r.code) u.searchParams.set("code", r.code);
    else u.searchParams.set("error", "access_denied");
    if (r.state) u.searchParams.set("state", r.state);
    return u.toString();
  }
  oauthStatus(id, now) {
    const r = this.sql("SELECT * FROM oauth_requests WHERE id = ?", id)[0];
    if (!r) return json(404, { status: "unknown" });
    if (r.status === "pending") return json(200, { status: r.expires_at <= now ? "expired" : "pending" });
    if (r.status === "approved" && (!r.code || r.expires_at <= now)) return json(200, { status: "expired" });
    return json(200, { status: r.status, redirect: this.redirectFor(r) });
  }
  async oauthCode(id, code, now) {
    const r = this.sql("SELECT * FROM oauth_requests WHERE id = ?", id)[0];
    if (!r || r.status !== "pending" || r.expires_at <= now) return this.oauthStatus(id, now);
    const attempts = r.attempts + 1;
    this.sql("UPDATE oauth_requests SET attempts = ? WHERE id = ?", attempts, id);
    if (safeEqual(r.user_code, code.replace(/\D/g, ""))) return this.oauthDecide(id, "approve", now);
    if (attempts >= OAUTH_CODE_ATTEMPTS) return this.oauthDecide(id, "deny", now);
    return json(200, { status: "wrong_code", attemptsLeft: OAUTH_CODE_ATTEMPTS - attempts });
  }
  async oauthDecide(id, decision, now) {
    const r = this.sql("SELECT * FROM oauth_requests WHERE id = ?", id)[0];
    if (!r) return err(404, "not_found", "no such request");
    if (r.status !== "pending") return err(409, "already_decided", `this request is already ${r.status}`, { status: r.status });
    if (r.expires_at <= now) return err(410, "expired", "this request has expired");
    if (decision === "deny") {
      this.sql("UPDATE oauth_requests SET status = 'denied', decided_at = ? WHERE id = ?", now, id);
    } else {
      const keyId = await this.createOAuthKey(r.client_id, r.client_name, now);
      if (!keyId) return err(429, "too_many_keys", `at most ${MAX_KEYS} active keys; revoke one first`);
      const code = oauthToken("hrc", this.getMeta("device_id") ?? "", randomHex(32));
      this.sql(
        "UPDATE oauth_requests SET status = 'approved', decided_at = ?, key_id = ?, code = ?, code_hash = ?, expires_at = ? WHERE id = ?",
        now,
        keyId,
        code,
        await sha256Hex(code),
        now + OAUTH_CODE_TTL_MS,
        id
      );
    }
    const done = this.sql("SELECT * FROM oauth_requests WHERE id = ?", id)[0];
    this.sendResolved(done);
    return json(200, { status: done.status, redirect: this.redirectFor(done) });
  }
  /** One key per connector, kind "oauth". Re-authorizing the same client replaces its earlier key. */
  async createOAuthKey(clientId, clientName, now) {
    for (const old of this.sql("SELECT * FROM keys WHERE kind = 'oauth' AND oauth_client = ? AND revoked_at IS NULL", clientId)) {
      this.sql("UPDATE keys SET revoked_at = ? WHERE id = ?", now, old.id);
      this.sql("DELETE FROM oauth_tokens WHERE key_id = ?", old.id);
    }
    const active = this.sql("SELECT * FROM keys WHERE revoked_at IS NULL");
    if (active.length >= MAX_KEYS) return null;
    const base = clientName.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "").slice(0, 24).replace(/-+$/, "") || "connector";
    let name = base;
    for (let i = 2; active.some((k) => k.name === name); i++) name = `${base}-${i}`;
    const id = randomHex(4);
    this.sql(
      "INSERT INTO keys (id, name, client, scope, hash, created_at, kind, client_name, oauth_client) VALUES (?, ?, 'other', 'notify', ?, ?, 'oauth', ?, ?)",
      id,
      name,
      await sha256Hex(randomHex(32)),
      now,
      clientName,
      clientId
    );
    return id;
  }
  /** Herald approves or denies from its banner. */
  async deviceConsent(req) {
    const b = await req.json().catch(() => null);
    if (!b || typeof b.id !== "string" || b.decision !== "approve" && b.decision !== "deny") return err(400, "invalid_request", "id and decision (approve|deny) are required");
    this.touch();
    return this.oauthDecide(b.id, b.decision, Date.now());
  }
  async issueTokens(keyId, clientId, resource, family, now) {
    const deviceId = this.getMeta("device_id") ?? "";
    const access = randomHex(32), refresh = randomHex(32);
    this.sql(
      "INSERT INTO oauth_tokens (hash, kind, key_id, client_id, resource, family, expires_at, created_at) VALUES (?, 'access', ?, ?, ?, ?, ?, ?)",
      await sha256Hex(access),
      keyId,
      clientId,
      resource,
      family,
      now + OAUTH_ACCESS_TTL_S * 1e3,
      now
    );
    this.sql(
      "INSERT INTO oauth_tokens (hash, kind, key_id, client_id, resource, family, expires_at, created_at) VALUES (?, 'refresh', ?, ?, ?, ?, ?, ?)",
      await sha256Hex(refresh),
      keyId,
      clientId,
      resource,
      family,
      now + OAUTH_REFRESH_TTL_S * 1e3,
      now
    );
    return json(200, {
      access_token: oauthToken("hra", deviceId, access),
      token_type: "Bearer",
      expires_in: OAUTH_ACCESS_TTL_S,
      refresh_token: oauthToken("hrr", deviceId, refresh),
      scope: "notify"
    });
  }
  oerr(error, description) {
    return json(400, { error, error_description: description });
  }
  async oauthTokenEndpoint(b, now) {
    const clientId = b.client_id ?? "";
    if (b.grant_type === "authorization_code") {
      const code = b.code ?? "";
      if (!parseOAuthSecret(code, "hrc")) return this.oerr("invalid_grant", "malformed authorization code");
      const r = this.sql("SELECT * FROM oauth_requests WHERE code_hash = ?", await sha256Hex(code))[0];
      if (!r) return this.oerr("invalid_grant", "unknown or already used authorization code");
      if (r.redeemed_at) {
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
      const key = this.sql("SELECT * FROM keys WHERE id = ?", r.key_id ?? "")[0];
      if (!key || key.revoked_at) return this.oerr("invalid_grant", "the connector was revoked");
      return this.issueTokens(key.id, clientId, r.resource, randomHex(8), now);
    }
    if (b.grant_type === "refresh_token") {
      const rt = b.refresh_token ?? "";
      if (!parseOAuthSecret(rt, "hrr")) return this.oerr("invalid_grant", "malformed refresh token");
      const t = this.sql("SELECT * FROM oauth_tokens WHERE hash = ? AND kind = 'refresh'", await sha256Hex(rt.split("_")[2]))[0];
      if (!t || t.client_id !== clientId) return this.oerr("invalid_grant", "unknown refresh token");
      if (t.used_at) {
        this.sql("DELETE FROM oauth_tokens WHERE family = ?", t.family);
        return this.oerr("invalid_grant", "refresh token already used; authorize the connector again");
      }
      if (t.expires_at <= now) return this.oerr("invalid_grant", "refresh token expired");
      const key = this.sql("SELECT * FROM keys WHERE id = ?", t.key_id)[0];
      if (!key || key.revoked_at) return this.oerr("invalid_grant", "the connector was revoked");
      if (b.resource && !sameResource(b.resource, t.resource)) return this.oerr("invalid_target", "resource does not match the original grant");
      if (b.scope && b.scope.split(/\s+/).some((x) => x !== "notify")) return this.oerr("invalid_scope", "the only scope is notify");
      this.sql("UPDATE oauth_tokens SET used_at = ? WHERE hash = ?", now, t.hash);
      return this.issueTokens(key.id, clientId, t.resource, t.family, now);
    }
    return this.oerr("unsupported_grant_type", "grant_type must be authorization_code or refresh_token");
  }
  /** RFC 7009: an unknown token is not an error. A refresh token takes its whole family with it. */
  async oauthRevoke(b) {
    const tok = b.token ?? "";
    if (parseOAuthSecret(tok, "hrr") || parseOAuthSecret(tok, "hra")) {
      const t = this.sql("SELECT * FROM oauth_tokens WHERE hash = ?", await sha256Hex(tok.split("_")[2]))[0];
      if (t && t.client_id === b.client_id) {
        if (t.kind === "refresh") this.sql("DELETE FROM oauth_tokens WHERE family = ?", t.family);
        else this.sql("DELETE FROM oauth_tokens WHERE hash = ?", t.hash);
      }
    }
    return json(200, {});
  }
  // ---------- receipts from Herald
  async httpReceipt(req, forceKind) {
    let b;
    try {
      b = await req.json();
    } catch {
      return err(400, "invalid_request", "body must be JSON");
    }
    this.touch();
    if (forceKind) b = { ...b, kind: forceKind };
    const r = this.applyReceipt(b);
    return r === "ok" ? json(200, { ok: true }) : err(r === "unknown" ? 404 : 400, r === "unknown" ? "not_found" : "invalid_request", r === "unknown" ? "no such notification" : "invalid receipt");
  }
  applyReceipt(m) {
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
        const text = typeof m.text === "string" ? m.text.trim().slice(0, 4e3) : "";
        const transcript = typeof m.transcript === "string" ? m.transcript.trim().slice(0, 4e3) : "";
        const secs = typeof m.durationSeconds === "number" && m.durationSeconds >= 0 && m.durationSeconds <= 600 ? m.durationSeconds : null;
        if (!text && !transcript && !n.audio_key) return "invalid";
        this.sql(
          "UPDATE notes SET replied_at = COALESCE(replied_at, ?), reply = COALESCE(reply, ?), transcript = COALESCE(transcript, ?), audio_seconds = COALESCE(?, audio_seconds), acked_at = COALESCE(acked_at, ?) WHERE rid = ?",
          now,
          text || null,
          transcript || null,
          secs,
          now,
          id
        );
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
  wake(rid) {
    const w = this.waiters.get(rid);
    if (w) for (const f of [...w]) f();
  }
  // ---------- receipts and replies for agents
  async audioUrl(origin, n) {
    if (!n.audio_key) return void 0;
    const exp = Math.floor(Date.now() / 1e3) + AUDIO_URL_TTL_S;
    const sig = await hmacHex(this.env.RELAY_SECRET, `audio:${n.audio_key}:${exp}`);
    return `${origin}/v1/audio/${n.audio_key}?exp=${exp}&sig=${sig}`;
  }
  async replyFields(origin, n) {
    if (n.replied_at == null) return {};
    const audioUrl = await this.audioUrl(origin, n);
    return {
      repliedAt: iso(n.replied_at),
      reply: n.reply ?? n.transcript ?? void 0,
      ...n.reply ? { text: n.reply } : {},
      ...n.transcript ? { transcript: n.transcript, transcriptNote: "transcribed on the user's Mac; may be imperfect" } : {},
      ...audioUrl ? { audioUrl, audioUrlExpiresInSeconds: AUDIO_URL_TTL_S } : {},
      ...n.audio_seconds != null ? { durationSeconds: n.audio_seconds } : {}
    };
  }
  async receiptBody(n, origin = "") {
    const sup = n.suppressed_reason != null;
    return {
      notificationId: n.nid,
      received: true,
      receivedAt: iso(n.created_at),
      queued: n.acked_at == null && !sup,
      displayed: n.displayed_at != null,
      ...n.displayed_at != null ? { displayedAt: iso(n.displayed_at) } : {},
      spoken: n.spoken_at != null,
      ...n.spoken_at != null ? { spokenAt: iso(n.spoken_at) } : {},
      replied: n.replied_at != null,
      ...await this.replyFields(origin, n),
      expectReply: n.expect_reply === 1,
      suppressed: sup,
      ...sup ? { reason: n.suppressed_reason, suppressedScope: n.suppressed_scope } : {}
    };
  }
  async getReceipt(key, nid, origin) {
    const n = this.noteByNid(key.id, nid);
    if (!n || n.created_at < Date.now() - DAY_MS) return err(404, "not_found", "no such notification (ids are kept for 24 hours)");
    return json(200, await this.receiptBody(n, origin));
  }
  async getReply(key, nid, waitParam, origin) {
    const first = this.noteByNid(key.id, nid);
    if (!first || first.created_at < Date.now() - DAY_MS) return err(404, "not_found", "no such notification (ids are kept for 24 hours)");
    let seconds = Math.min(MAX_LONG_POLL_S, Math.max(0, Number(waitParam ?? 0) || 0));
    if (this.usageField("pollSeconds") >= this.lim.pollSecondsPerDay) seconds = 0;
    const started = Date.now();
    const deadline = Date.now() + seconds * 1e3;
    let n = first;
    for (; ; ) {
      n = this.note(n.rid) ?? n;
      const done = n.replied_at != null || n.suppressed_reason != null && n.suppressed_scope === "all";
      const left = deadline - Date.now();
      if (done || left <= 0) {
        if (seconds > 0) this.bump("pollSeconds", Math.ceil((Date.now() - started) / 1e3));
        return json(200, {
          notificationId: nid,
          replied: n.replied_at != null,
          ...await this.replyFields(origin, n),
          ...n.replied_at == null && seconds > 0 && !done ? { timedOut: true } : {},
          suppressed: n.suppressed_reason != null,
          ...n.suppressed_reason != null ? { reason: n.suppressed_reason } : {}
        });
      }
      await new Promise((resolve) => {
        const set = this.waiters.get(n.rid) ?? /* @__PURE__ */ new Set();
        this.waiters.set(n.rid, set);
        const timer = setTimeout(finish, left);
        function finish() {
          clearTimeout(timer);
          set.delete(finish);
          resolve();
        }
        __name(finish, "finish");
        set.add(finish);
      });
    }
  }
  // ---------- voice replies
  async putAudio(req, rid) {
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
  async scheduleAlarm() {
    if (await this.ctx.storage.getAlarm() == null) await this.ctx.storage.setAlarm(Date.now() + 60 * 60 * 1e3);
  }
  async alarm() {
    const now = Date.now();
    this.persistUsage();
    this.expireSweep(now);
    this.sql("DELETE FROM notes WHERE created_at < ?", now - this.lim.ttlMs - 60 * 60 * 1e3);
    this.sql("DELETE FROM rate WHERE at < ?", now - RATE_WINDOW_MS);
    this.sql("DELETE FROM meta WHERE k LIKE 'usage:%' AND k < ?", "usage:" + new Date(now - 7 * DAY_MS).toISOString().slice(0, 10));
    const left = this.sql("SELECT COUNT(*) AS n FROM notes")[0].n;
    if (left > 0) await this.ctx.storage.setAlarm(now + 60 * 60 * 1e3);
  }
};

// src/mcp.ts
var PROTOCOL = "2025-06-18";
var SUPPORTED = /* @__PURE__ */ new Set(["2025-06-18", "2025-03-26", "2024-11-05"]);
var NOTIFY_PROPS = {
  title: { type: "string", maxLength: 200, description: "Headline of the notification." },
  body: { type: "string", maxLength: 8e3, description: "Message text." },
  subtitle: { type: "string", maxLength: 200 },
  status: { type: "string", description: "A short word shown as a badge: done, error, warning, question, info..." },
  project: { type: "string", maxLength: 100 },
  session: { type: "string", maxLength: 100 },
  task: { type: "string", maxLength: 100 },
  tool: { type: "string", maxLength: 100 },
  duration: { type: "string", description: 'For example "2m 14s".' },
  link: { type: "string", description: "An https URL the user can open from the banner." },
  group: { type: "string", description: "Notifications with the same group stack together." },
  priority: { type: "string", enum: ["normal", "urgent"], description: "urgent may break quiet hours only if the user allowed it." },
  speak: {
    description: "true speaks title then body on the Mac; or an object to choose the text and voice.",
    oneOf: [
      { type: "boolean" },
      { type: "object", additionalProperties: false, properties: { text: { type: "string", maxLength: 2e3 }, voice: { type: "string" }, speed: { type: "number", minimum: 0.5, maximum: 2 }, lang: { type: "string" } } }
    ]
  },
  notificationId: { type: "string", pattern: "^[A-Za-z0-9._:-]{1,128}$", description: "Your own id. Sending the same id again within 24 hours never shows a second banner (idempotent)." },
  expectReply: { type: "boolean", description: "The notification asks a question and stays on screen until answered. Every banner has Reply (text) and Record (voice) buttons; read the answer with wait_for_reply." },
  allowVoiceReply: { type: "boolean", description: "Default true. Set false to hide the Record button on this notification." }
};
var TOOLS = [
  {
    name: "send_notification",
    title: "Send a notification to the user's Mac",
    description: "Queue a notification for the user's Mac. Text only: no buttons, commands, callbacks or scripts are accepted. Quiet hours and mute are enforced on the Mac, so check get_receipt: `received` means the relay has it, `displayed` that a banner was shown, `spoken` that speech finished, `suppressed` (with `reason`) that the user's settings held it back. Limits: 60 per 10 minutes per key, 32 KB per request.",
    inputSchema: { type: "object", additionalProperties: false, required: ["title"], properties: NOTIFY_PROPS },
    annotations: { readOnlyHint: false, destructiveHint: false, idempotentHint: true, openWorldHint: false }
  },
  {
    name: "get_receipt",
    title: "Get delivery receipts",
    description: "Receipts for a notification you sent: received, displayed, spoken, replied (with the reply), suppressed (with reason). Ids are kept 24 hours.",
    inputSchema: { type: "object", additionalProperties: false, required: ["notificationId"], properties: { notificationId: { type: "string" } } },
    annotations: { readOnlyHint: true, openWorldHint: false }
  },
  {
    name: "wait_for_reply",
    title: "Wait for the user's reply",
    description: `Wait up to ${MAX_LONG_POLL_S - 5} seconds for the user's answer to a notification sent with expectReply. Returns {replied:false, timedOut:true} when nothing came; call again to keep waiting. A typed answer is \`text\`. A voice answer has \`transcript\` (made on the user's Mac, may be imperfect) and \`audioUrl\` (valid about an hour) with \`durationSeconds\`.`,
    inputSchema: { type: "object", additionalProperties: false, required: ["notificationId"], properties: { notificationId: { type: "string" }, timeoutSeconds: { type: "integer", minimum: 0, maximum: MAX_LONG_POLL_S - 5 } } },
    annotations: { readOnlyHint: true, openWorldHint: false }
  },
  {
    name: "herald_status",
    title: "Is the user's Mac reachable",
    description: "Whether the user's Herald is online, when it was last seen, and whether quiet hours are active. Nothing else about the Mac is exposed.",
    inputSchema: { type: "object", additionalProperties: false, properties: {} },
    annotations: { readOnlyHint: true, openWorldHint: false }
  }
];
var ok = /* @__PURE__ */ __name((id, result) => ({ jsonrpc: "2.0", id, result }), "ok");
var fail = /* @__PURE__ */ __name((id, code, message) => ({ jsonrpc: "2.0", id: id ?? null, error: { code, message } }), "fail");
async function handleMcp(req, forward) {
  const headers = { "content-type": "application/json; charset=utf-8", "cache-control": "no-store" };
  if (req.method === "GET" || req.method === "DELETE") {
    return new Response(JSON.stringify(fail(null, -32e3, "this server answers POST only (no SSE stream, no sessions)")), { status: 405, headers: { ...headers, allow: "POST" } });
  }
  if (req.method !== "POST") return new Response("method not allowed", { status: 405 });
  let msg;
  try {
    const parsed = await req.json();
    if (Array.isArray(parsed)) return new Response(JSON.stringify(fail(null, -32600, "batches are not supported in protocol 2025-06-18")), { status: 400, headers });
    msg = parsed;
  } catch {
    return new Response(JSON.stringify(fail(null, -32700, "parse error")), { status: 400, headers });
  }
  const reply = /* @__PURE__ */ __name((body, status = 200) => new Response(JSON.stringify(body), { status, headers }), "reply");
  if (msg.method === void 0) return reply(fail(msg.id, -32600, "not a request"), 202);
  const probe = await forward("/v1/status");
  if (probe.status === 401 || probe.status === 403) return probe;
  if (msg.id === void 0) return new Response(null, { status: 202 });
  switch (msg.method) {
    case "initialize": {
      const asked = String(msg.params?.protocolVersion ?? "");
      return reply(ok(msg.id, {
        protocolVersion: SUPPORTED.has(asked) ? asked : PROTOCOL,
        capabilities: { tools: { listChanged: false } },
        serverInfo: { name: "herald-relay", title: "Herald cloud relay", version: "1.0.0" },
        instructions: "Send notifications to the user's Mac with send_notification; read receipts with get_receipt; wait for an answer with wait_for_reply. Text only. Nothing else is exposed."
      }));
    }
    case "ping":
      return reply(ok(msg.id, {}));
    case "tools/list":
      return reply(ok(msg.id, { tools: TOOLS }));
    case "tools/call": {
      const p = msg.params ?? {};
      const a = p.arguments ?? {};
      let r;
      switch (p.name) {
        case "send_notification":
          r = await forward("/v1/notify", { method: "POST", body: JSON.stringify(a) });
          break;
        case "get_receipt":
          if (typeof a.notificationId !== "string") return reply(ok(msg.id, toolError("notificationId is required")));
          r = await forward(`/v1/receipts/${encodeURIComponent(a.notificationId)}`);
          break;
        case "wait_for_reply": {
          if (typeof a.notificationId !== "string") return reply(ok(msg.id, toolError("notificationId is required")));
          const t = Math.min(MAX_LONG_POLL_S - 5, Math.max(0, Number(a.timeoutSeconds ?? 30) || 0));
          r = await forward(`/v1/replies/${encodeURIComponent(a.notificationId)}?wait=${t}`);
          break;
        }
        case "herald_status":
          r = await forward("/v1/status");
          break;
        default:
          return reply(fail(msg.id, -32602, `unknown tool: ${String(p.name)}`));
      }
      if (r.status === 401 || r.status === 403) return r;
      const data = await r.json().catch(() => ({}));
      const result = { content: [{ type: "text", text: JSON.stringify(data) }], structuredContent: data, ...r.ok ? {} : { isError: true } };
      return reply(ok(msg.id, result));
    }
    default:
      return reply(fail(msg.id, -32601, `method not found: ${msg.method}`));
  }
}
__name(handleMcp, "handleMcp");
function toolError(message) {
  return { content: [{ type: "text", text: message }], isError: true };
}
__name(toolError, "toolError");

// src/oauth.ts
var SCOPE = "notify";
var CORS = { "access-control-allow-origin": "*", "access-control-allow-headers": "authorization, content-type, mcp-protocol-version", "access-control-allow-methods": "GET, POST, OPTIONS" };
var mcpUrl = /* @__PURE__ */ __name((origin) => origin + "/mcp", "mcpUrl");
var resourceMetadataUrl = /* @__PURE__ */ __name((origin) => origin + "/.well-known/oauth-protected-resource", "resourceMetadataUrl");
function challenge(origin, invalidToken) {
  return `Bearer ${invalidToken ? 'error="invalid_token", ' : ""}resource_metadata="${resourceMetadataUrl(origin)}"`;
}
__name(challenge, "challenge");
var cors = /* @__PURE__ */ __name((r) => {
  for (const [k, v] of Object.entries(CORS)) r.headers.set(k, v);
  return r;
}, "cors");
var oerr = /* @__PURE__ */ __name((status, error, description, headers = {}) => cors(json(status, { error, error_description: description }, headers)), "oerr");
function esc(s) {
  return s.replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]);
}
__name(esc, "esc");
async function readForm(req) {
  const out = new URLSearchParams();
  try {
    for (const [k, v] of (await req.formData()).entries()) if (typeof v === "string") out.append(k, v);
  } catch {
  }
  return out;
}
__name(readForm, "readForm");
function registry(env, path, body) {
  return env.REGISTRY.get(env.REGISTRY.idFromName("registry")).fetch(new Request("https://registry" + path, { method: "POST", body: JSON.stringify(body) }));
}
__name(registry, "registry");
function mailbox(env, deviceId, path, body) {
  return env.MAILBOX.get(env.MAILBOX.idFromName(deviceId)).fetch(new Request("https://mailbox/internal/oauth/" + path, { method: "POST", body: JSON.stringify(body) }));
}
__name(mailbox, "mailbox");
function protectedResource(origin) {
  return {
    resource: mcpUrl(origin),
    authorization_servers: [origin],
    scopes_supported: [SCOPE],
    bearer_methods_supported: ["header"],
    resource_name: "Herald relay"
  };
}
__name(protectedResource, "protectedResource");
function serverMetadata(origin) {
  return {
    issuer: origin,
    authorization_endpoint: origin + "/authorize",
    token_endpoint: origin + "/token",
    registration_endpoint: origin + "/register",
    revocation_endpoint: origin + "/revoke",
    scopes_supported: [SCOPE],
    response_types_supported: ["code"],
    response_modes_supported: ["query"],
    grant_types_supported: ["authorization_code", "refresh_token"],
    code_challenge_methods_supported: ["S256"],
    token_endpoint_auth_methods_supported: ["none", "client_secret_post", "client_secret_basic"],
    revocation_endpoint_auth_methods_supported: ["none", "client_secret_post", "client_secret_basic"],
    service_documentation: "https://github.com/ivg-design/herald/blob/main/docs/CLOUD.md"
  };
}
__name(serverMetadata, "serverMetadata");
var BAD_SCHEMES = /* @__PURE__ */ new Set(["javascript:", "data:", "vbscript:", "file:", "blob:", "about:", "ftp:"]);
function redirectUriValid(raw) {
  if (typeof raw !== "string" || raw.length > 500) return false;
  let u;
  try {
    u = new URL(raw);
  } catch {
    return false;
  }
  if (u.hash || u.username || u.password || BAD_SCHEMES.has(u.protocol)) return false;
  if (u.protocol === "https:") return true;
  if (u.protocol === "http:") return ["localhost", "127.0.0.1", "[::1]"].includes(u.hostname);
  return /^[a-z][a-z0-9+.-]*:$/.test(u.protocol) && u.protocol !== "http:";
}
__name(redirectUriValid, "redirectUriValid");
async function register(env, req) {
  let b;
  try {
    b = await req.json();
  } catch {
    return oerr(400, "invalid_client_metadata", "body must be JSON");
  }
  if (!Array.isArray(b.redirect_uris) || b.redirect_uris.length < 1 || b.redirect_uris.length > 10 || !b.redirect_uris.every(redirectUriValid)) {
    return oerr(400, "invalid_redirect_uri", "redirect_uris must be 1-10 https (or loopback http) URLs without a fragment");
  }
  const method = b.token_endpoint_auth_method ?? "none";
  if (method !== "none" && method !== "client_secret_post" && method !== "client_secret_basic") {
    return oerr(400, "invalid_client_metadata", "token_endpoint_auth_method must be none, client_secret_post or client_secret_basic");
  }
  const grants = b.grant_types ?? ["authorization_code"];
  if (!Array.isArray(grants) || !grants.every((g) => g === "authorization_code" || g === "refresh_token")) {
    return oerr(400, "invalid_client_metadata", "grant_types may only be authorization_code and refresh_token");
  }
  if (b.response_types !== void 0 && !(Array.isArray(b.response_types) && b.response_types.every((t) => t === "code"))) {
    return oerr(400, "invalid_client_metadata", "response_types may only be code");
  }
  const name = (typeof b.client_name === "string" ? b.client_name : "").replace(/[\u0000-\u001f\u007f<>]/g, "").trim().slice(0, 60) || "An app";
  const id = "hc_" + randomHex(16);
  const secret = method === "none" ? null : randomHex(32);
  const r = await registry(env, "/client/register", { id, name, redirectUris: b.redirect_uris, secretHash: secret ? await sha256Hex(secret) : null });
  if (!r.ok) return cors(new Response(r.body, { status: r.status, headers: { "content-type": "application/json", "cache-control": "no-store" } }));
  return cors(json(201, {
    client_id: id,
    client_id_issued_at: Math.floor(Date.now() / 1e3),
    client_name: name,
    redirect_uris: b.redirect_uris,
    token_endpoint_auth_method: method,
    grant_types: ["authorization_code", "refresh_token"],
    response_types: ["code"],
    scope: SCOPE,
    ...secret ? { client_secret: secret, client_secret_expires_at: 0 } : {}
  }));
}
__name(register, "register");
async function getClient(env, id) {
  if (!/^hc_[0-9a-f]{32}$/.test(id)) return null;
  const r = await registry(env, "/client/get", { id });
  return r.ok ? await r.json() : null;
}
__name(getClient, "getClient");
async function clientAuth(env, req, form) {
  let id = form.get("client_id") ?? "";
  let secret = form.get("client_secret") ?? "";
  const basic = /^Basic\s+(\S+)$/i.exec(req.headers.get("authorization") ?? "");
  if (basic) {
    try {
      const [u, ...rest] = atob(basic[1]).split(":");
      id = decodeURIComponent(u);
      secret = decodeURIComponent(rest.join(":"));
    } catch {
      return oerr(401, "invalid_client", "malformed Basic credentials", { "www-authenticate": 'Basic realm="herald-relay"' });
    }
  }
  const c = await getClient(env, id);
  if (!c) return oerr(401, "invalid_client", "unknown client_id");
  if (c.secretHash && !safeEqual(c.secretHash, await sha256Hex(secret))) {
    return oerr(401, "invalid_client", "client authentication failed", basic ? { "www-authenticate": 'Basic realm="herald-relay"' } : {});
  }
  form.set("client_id", c.id);
  return c;
}
__name(clientAuth, "clientAuth");
var CSS = `:root{color-scheme:light dark;--bg:#f6f5f2;--fg:#1c1b19;--mut:#6b6862;--card:#fff;--line:#dedbd4;--acc:#1f5eff}
@media(prefers-color-scheme:dark){:root{--bg:#161614;--fg:#eeece6;--mut:#a09d95;--card:#201f1d;--line:#38362f;--acc:#7da2ff}}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--fg);font:16px/1.5 -apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif}
main{max-width:30rem;margin:0 auto;padding:2.5rem 1rem}h1{font-size:1.4rem;line-height:1.25;margin:0 0 .5rem}
.card{background:var(--card);border:1px solid var(--line);border-radius:12px;padding:1rem 1.1rem;margin:1rem 0}
.mut{color:var(--mut);font-size:.9rem}ul{margin:.4rem 0 0;padding-left:1.2rem}h2{font-size:1rem;margin:0 0 .25rem}
input[type=text]{font:600 1.5rem ui-monospace,Menlo,monospace;letter-spacing:.3em;width:100%;padding:.5rem .7rem;border-radius:8px;border:1px solid var(--line);background:var(--bg);color:var(--fg)}
button{font:inherit;border-radius:8px;border:1px solid var(--line);background:var(--card);color:var(--fg);padding:.5rem 1rem;cursor:pointer}
button.p{background:var(--acc);border-color:var(--acc);color:#fff}.row{display:flex;gap:.6rem;margin-top:.7rem}.bad{color:#c0392b}.dot{display:inline-block;width:.6rem;height:.6rem;border-radius:50%;background:var(--acc);margin-right:.4rem;animation:b 1.2s infinite}
@keyframes b{50%{opacity:.25}}`;
function page(status, title, body, script = "") {
  const nonce = randomHex(12);
  const html = `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>${esc(title)}</title><style nonce="${nonce}">${CSS}</style></head><body><main>${body}</main>${script ? `<script nonce="${nonce}">${script}<\/script>` : ""}</body></html>`;
  return new Response(html, { status, headers: {
    "content-type": "text/html; charset=utf-8",
    "cache-control": "no-store",
    "referrer-policy": "no-referrer",
    "x-frame-options": "DENY",
    "content-security-policy": `default-src 'none'; style-src 'nonce-${nonce}'; script-src 'nonce-${nonce}'; connect-src 'self'; base-uri 'none'; frame-ancestors 'none'`
  } });
}
__name(page, "page");
var errorPage = /* @__PURE__ */ __name((message, status = 400) => page(status, "Herald", `<h1>Can't connect</h1><div class="card">${esc(message)}</div><p class="mut">Nothing was approved. Close this tab and start again from the app.</p>`), "errorPage");
function consentPage(rid, client, redirectHost, online, note = "") {
  const name = esc(client.name);
  const body = `<h1>${name} wants to connect to Herald</h1>
<p class="mut">It will return to <b>${esc(redirectHost)}</b> after you decide.</p>
<div class="card"><h2>It will be able to</h2><ul><li>send notifications to your Mac</li><li>read receipts and your replies</li></ul>
<p class="mut" style="margin:.6rem 0 0">Nothing else: no commands, no files, no settings. You can revoke it any time in Herald, Settings, Cloud.</p></div>
<div class="card"><h2>Approve in Herald</h2>
<p id="wait"><span class="dot"></span>${online ? `A banner is waiting on your Mac. Click <b>Approve</b> there.` : `Herald does not look connected right now. Open Herald on your Mac; the request will appear there.`} This page continues by itself.</p></div>
<div class="card"><h2>Or enter the code</h2><p class="mut" style="margin-top:0">Herald, Settings, Cloud, Connector approvals shows a 6-digit code.</p>
${note ? `<p class="bad">${esc(note)}</p>` : ""}
<form method="post" action="/authorize/code"><input type="hidden" name="rid" value="${rid}"><input type="text" name="code" inputmode="numeric" autocomplete="one-time-code" pattern="[0-9 ]{6,7}" maxlength="7" placeholder="000000" required>
<div class="row"><button class="p" type="submit">Approve</button></div></form></div>
<form method="post" action="/authorize/deny"><input type="hidden" name="rid" value="${rid}"><button type="submit">Deny</button></form>`;
  const script = `var rid=${JSON.stringify(rid)};(function poll(){fetch('/authorize/status?rid='+rid,{cache:'no-store'}).then(function(r){return r.json()}).then(function(s){
if(s.redirect){location.replace(s.redirect)}else if(s.status==='expired'||s.status==='unknown'){document.getElementById('wait').textContent='This request expired. Start again from the app.'}else{setTimeout(poll,2000)}}).catch(function(){setTimeout(poll,4000)})})();`;
  return page(200, "Connect to Herald", body, script);
}
__name(consentPage, "consentPage");
function errorRedirect(redirect, error, description, state) {
  const u = new URL(redirect);
  u.searchParams.set("error", error);
  u.searchParams.set("error_description", description);
  if (state) u.searchParams.set("state", state);
  return new Response(null, { status: 302, headers: { location: u.toString(), "cache-control": "no-store" } });
}
__name(errorRedirect, "errorRedirect");
async function authorize(env, req, url) {
  if (!env.RELAY_SECRET) return errorPage("The relay is misconfigured.", 500);
  const q = url.searchParams;
  const client = await getClient(env, q.get("client_id") ?? "");
  if (!client) return errorPage("Unknown client. The app has to register with this relay first.");
  const redirect = q.get("redirect_uri") ?? "";
  if (!client.redirectUris.includes(redirect)) return errorPage("The redirect address does not match what this app registered.");
  const state = q.get("state");
  if (q.get("response_type") !== "code") return errorRedirect(redirect, "unsupported_response_type", "response_type must be code", state);
  const chal = q.get("code_challenge") ?? "";
  if (q.get("code_challenge_method") !== "S256" || !/^[A-Za-z0-9_-]{43}$/.test(chal)) {
    return errorRedirect(redirect, "invalid_request", "PKCE is required: code_challenge with code_challenge_method=S256", state);
  }
  const resource = q.get("resource");
  const mcp = mcpUrl(url.origin);
  if (resource !== null && resource.replace(/\/+$/, "") !== mcp) return errorRedirect(redirect, "invalid_target", `resource must be ${mcp}`, state);
  const scope = (q.get("scope") ?? "").trim();
  if (scope && scope.split(/\s+/).some((s) => s !== SCOPE)) return errorRedirect(redirect, "invalid_scope", "the only scope is notify", state);
  const devices = (await (await registry(env, "/devices", {})).json()).devices;
  if (devices.length === 0) return page(200, "Pair Herald first", `<h1>Pair Herald first</h1><div class="card">This relay is not paired with a Mac yet. In Herald, open Settings, Cloud and pair this relay, then connect ${esc(client.name)} again.</div>`);
  let device = devices[0];
  if (devices.length > 1) {
    const pick = Number(q.get("device"));
    if (!Number.isInteger(pick) || pick < 1 || pick > devices.length) {
      const next = new URL(url);
      const links = devices.map((d, i) => {
        next.searchParams.set("device", String(i + 1));
        return `<li><a href="${esc(next.pathname + next.search)}">${esc(d.name ?? "Mac " + (i + 1))}</a></li>`;
      }).join("");
      return page(200, "Choose a Mac", `<h1>Which Mac?</h1><p class="mut">${esc(client.name)} will notify the Mac you choose.</p><div class="card"><ul>${links}</ul></div>`);
    }
    device = devices[pick - 1];
  }
  const r = await mailbox(env, device.id, "begin", { clientId: client.id, clientName: client.name, redirectUri: redirect, challenge: chal, state, scope: SCOPE, resource: mcp });
  if (r.status === 429) return errorPage("Approvals are already waiting in Herald (or too many were requested). Answer them there, or wait a few minutes.", 429);
  if (!r.ok) return errorPage("Could not start the approval.", 502);
  const { id, online } = await r.json();
  let host = redirect;
  try {
    host = new URL(redirect).host || new URL(redirect).protocol;
  } catch {
  }
  return consentPage(id, client, host, online);
}
__name(authorize, "authorize");
async function ridDevice(env, rid) {
  if (!/^[0-9a-f]{72}$/.test(rid)) return null;
  const deviceId = rid.slice(0, 48);
  return await deviceIdValid(env.RELAY_SECRET, deviceId) ? deviceId : null;
}
__name(ridDevice, "ridDevice");
async function decided(r) {
  const j = await r.json().catch(() => ({}));
  if (j.redirect) return new Response(null, { status: 302, headers: { location: j.redirect, "cache-control": "no-store" } });
  return errorPage(j.status === "expired" ? "This request expired. Start again from the app." : "This request is no longer open.");
}
__name(decided, "decided");
async function codeEntry(env, req) {
  const form = await readForm(req);
  const rid = form.get("rid") ?? "";
  const deviceId = await ridDevice(env, rid);
  if (!deviceId) return errorPage("Unknown request.");
  const r = await mailbox(env, deviceId, "code", { id: rid, code: form.get("code") ?? "" });
  const j = await r.clone().json().catch(() => ({}));
  if (j.status === "wrong_code") {
    return page(200, "Wrong code", `<h1>That code is wrong</h1><div class="card bad">${j.attemptsLeft} ${j.attemptsLeft === 1 ? "try" : "tries"} left. Check Herald, Settings, Cloud, Connector approvals.</div>
<form method="post" action="/authorize/code"><input type="hidden" name="rid" value="${esc(rid)}"><input type="text" name="code" inputmode="numeric" autocomplete="one-time-code" pattern="[0-9 ]{6,7}" maxlength="7" placeholder="000000" required><div class="row"><button class="p" type="submit">Approve</button></div></form>`);
  }
  return decided(r);
}
__name(codeEntry, "codeEntry");
async function denyEntry(env, req) {
  const rid = (await readForm(req)).get("rid") ?? "";
  const deviceId = await ridDevice(env, rid);
  if (!deviceId) return errorPage("Unknown request.");
  return decided(await mailbox(env, deviceId, "deny", { id: rid }));
}
__name(denyEntry, "denyEntry");
async function statusEntry(env, url) {
  const rid = url.searchParams.get("rid") ?? "";
  const deviceId = await ridDevice(env, rid);
  if (!deviceId) return json(404, { status: "unknown" });
  const r = await mailbox(env, deviceId, "status", { id: rid });
  return new Response(r.body, { status: r.status === 404 ? 200 : r.status, headers: { "content-type": "application/json", "cache-control": "no-store" } });
}
__name(statusEntry, "statusEntry");
async function token(env, req) {
  const form = await readForm(req);
  const c = await clientAuth(env, req, form);
  if (c instanceof Response) return c;
  const grant = form.get("grant_type");
  const raw = grant === "authorization_code" ? form.get("code") : grant === "refresh_token" ? form.get("refresh_token") : null;
  const parsed = raw ? parseOAuthSecret(raw, grant === "refresh_token" ? "hrr" : "hrc") : null;
  if (grant !== "authorization_code" && grant !== "refresh_token") return oerr(400, "unsupported_grant_type", "grant_type must be authorization_code or refresh_token");
  if (!parsed || !await deviceIdValid(env.RELAY_SECRET, parsed.deviceId)) return oerr(400, "invalid_grant", "unknown or malformed grant");
  const body = Object.fromEntries(form.entries());
  delete body.client_secret;
  const r = await mailbox(env, parsed.deviceId, "token", body);
  return cors(new Response(r.body, { status: r.status, headers: { "content-type": "application/json; charset=utf-8", "cache-control": "no-store", pragma: "no-cache" } }));
}
__name(token, "token");
async function revoke(env, req) {
  const form = await readForm(req);
  const c = await clientAuth(env, req, form);
  if (c instanceof Response) return c;
  const t = form.get("token") ?? "";
  const parsed = parseOAuthSecret(t, "hrr") ?? parseOAuthSecret(t, "hra");
  if (parsed && await deviceIdValid(env.RELAY_SECRET, parsed.deviceId)) await mailbox(env, parsed.deviceId, "revoke", { token: t, client_id: c.id });
  return cors(json(200, {}));
}
__name(revoke, "revoke");
async function handleOAuth(req, env, url) {
  const p = url.pathname, m = req.method;
  const wellKnown = p.startsWith("/.well-known/");
  const ours = wellKnown || ["/register", "/authorize", "/authorize/code", "/authorize/deny", "/authorize/status", "/token", "/revoke"].includes(p);
  if (!ours) return null;
  if (m === "OPTIONS") return new Response(null, { status: 204, headers: { ...CORS, "access-control-max-age": "86400" } });
  if (wellKnown) {
    if (m !== "GET") return err(405, "method_not_allowed", "GET only");
    if (p === "/.well-known/oauth-protected-resource" || p === "/.well-known/oauth-protected-resource/mcp") return cors(json(200, protectedResource(url.origin), { "cache-control": "public, max-age=300" }));
    if (p === "/.well-known/oauth-authorization-server" || p === "/.well-known/openid-configuration") return cors(json(200, serverMetadata(url.origin), { "cache-control": "public, max-age=300" }));
    return null;
  }
  if (!env.RELAY_SECRET) return err(500, "misconfigured", "RELAY_SECRET is not set");
  if (p === "/authorize" && m === "GET") return authorize(env, req, url);
  if (p === "/authorize/status" && m === "GET") return statusEntry(env, url);
  if (m !== "POST") return err(405, "method_not_allowed", "POST only");
  switch (p) {
    case "/register":
      return register(env, req);
    case "/token":
      return token(env, req);
    case "/revoke":
      return revoke(env, req);
    case "/authorize/code":
      return codeEntry(env, req);
    case "/authorize/deny":
      return denyEntry(env, req);
  }
  return err(405, "method_not_allowed", "GET only");
}
__name(handleOAuth, "handleOAuth");

// src/registry.ts
import { DurableObject as DurableObject2 } from "cloudflare:workers";
var CODE_TTL_MS = 10 * 6e4;
var ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789";
var MAX_PENDING_PER_IP = 3;
var MAX_PENDING_TOTAL = 60;
var FAILS_PER_10_MIN = 10;
var STARTS_PER_HOUR_TOTAL = 300;
function newCode() {
  const b = crypto.getRandomValues(new Uint8Array(8));
  const c = [...b].map((x) => ALPHABET[x % ALPHABET.length]).join("");
  return c.slice(0, 4) + "-" + c.slice(4);
}
__name(newCode, "newCode");
var normalize = /* @__PURE__ */ __name((c) => c.toUpperCase().replace(/[^A-Z0-9]/g, ""), "normalize");
var Registry = class extends DurableObject2 {
  static {
    __name(this, "Registry");
  }
  constructor(ctx, env) {
    super(ctx, env);
    ctx.storage.sql.exec(`
      CREATE TABLE IF NOT EXISTS codes (hash TEXT PRIMARY KEY, expires_at INTEGER NOT NULL, name TEXT, ip TEXT);
      CREATE TABLE IF NOT EXISTS devices (id TEXT PRIMARY KEY, name TEXT, created_at INTEGER NOT NULL);
      CREATE TABLE IF NOT EXISTS events (kind TEXT NOT NULL, at INTEGER NOT NULL, ip TEXT);
      CREATE TABLE IF NOT EXISTS clients (id TEXT PRIMARY KEY, name TEXT NOT NULL, redirect_uris TEXT NOT NULL, secret_hash TEXT, created_at INTEGER NOT NULL);
    `);
    for (const t of ["codes", "events"]) {
      try {
        ctx.storage.sql.exec(`ALTER TABLE ${t} ADD COLUMN ip TEXT`);
      } catch {
      }
    }
  }
  q(sql, ...b) {
    return this.ctx.storage.sql.exec(sql, ...b).toArray();
  }
  async fetch(req) {
    const path = new URL(req.url).pathname;
    if (req.method !== "POST") return err(405, "method_not_allowed", "POST only");
    const now = Date.now();
    this.q("DELETE FROM codes WHERE expires_at < ?", now);
    this.q("DELETE FROM events WHERE at < ?", now - 36e5);
    if (path === "/internal/remove") {
      const { deviceId } = await req.json();
      this.q("DELETE FROM devices WHERE id = ?", deviceId);
      return json(200, { ok: true });
    }
    let body = {};
    try {
      body = await req.json();
    } catch {
    }
    if (path === "/client/register") {
      const perHour = Number(this.env.REGISTER_PER_HOUR ?? "30") || 30;
      if (this.q("SELECT COUNT(*) AS n FROM events WHERE kind = 'register'")[0].n >= perHour) {
        return err(429, "rate_limited", "too many client registrations; try again later", { retryAfterSeconds: 3600 });
      }
      const c = body;
      this.q("INSERT INTO events (kind, at) VALUES ('register', ?)", now);
      this.q("INSERT INTO clients (id, name, redirect_uris, secret_hash, created_at) VALUES (?, ?, ?, ?, ?)", c.id, c.name, JSON.stringify(c.redirectUris), c.secretHash ?? null, now);
      this.q("DELETE FROM clients WHERE id NOT IN (SELECT id FROM clients ORDER BY created_at DESC, rowid DESC LIMIT 200)");
      return json(201, { ok: true });
    }
    if (path === "/client/get") {
      const row = this.q("SELECT id, name, redirect_uris, secret_hash FROM clients WHERE id = ?", String(body.id ?? ""))[0];
      if (!row) return err(404, "not_found", "unknown client");
      return json(200, { id: row.id, name: row.name, redirectUris: JSON.parse(row.redirect_uris), secretHash: row.secret_hash });
    }
    if (path === "/devices") {
      return json(200, { devices: this.q("SELECT id, name FROM devices ORDER BY created_at, rowid") });
    }
    const ip = (await sha256Hex("ip:" + (req.headers.get("x-client-ip") || "unknown"))).slice(0, 16);
    if (path === "/pair/start") {
      const secret = this.env.PAIRING_SECRET;
      if (secret && !safeEqual(await sha256Hex(secret), await sha256Hex(String(req.headers.get("x-pairing-secret") ?? "")))) {
        return err(401, "unauthorized", "this relay requires its pairing secret (X-Pairing-Secret)");
      }
      const max = Number(this.env.MAX_DEVICES ?? "5") || 5;
      if (this.q("SELECT COUNT(*) AS n FROM devices")[0].n >= max) {
        return err(403, "device_limit", `this relay already has ${max} paired Macs`);
      }
      if (this.q("SELECT COUNT(*) AS n FROM events WHERE kind = 'start' AND ip = ?", ip)[0].n >= (Number(this.env.PAIR_STARTS_PER_HOUR ?? "6") || 6)) {
        return err(429, "rate_limited", "too many pairing attempts from this address; try again in an hour", { retryAfterSeconds: 3600 });
      }
      if (this.q("SELECT COUNT(*) AS n FROM events WHERE kind = 'start'")[0].n >= (Number(this.env.PAIR_STARTS_GLOBAL_PER_HOUR ?? STARTS_PER_HOUR_TOTAL) || STARTS_PER_HOUR_TOTAL)) {
        return err(429, "rate_limited", "this relay is receiving too many pairing attempts; try again in an hour", { retryAfterSeconds: 3600 });
      }
      if (this.q("SELECT COUNT(*) AS n FROM codes WHERE ip = ?", ip)[0].n >= MAX_PENDING_PER_IP || this.q("SELECT COUNT(*) AS n FROM codes")[0].n >= MAX_PENDING_TOTAL) {
        return err(429, "rate_limited", "pairing codes are already waiting; use one or wait 10 minutes", { retryAfterSeconds: 600 });
      }
      const code = newCode();
      const name = typeof body.deviceName === "string" ? body.deviceName.slice(0, 60) : null;
      this.q("INSERT INTO codes (hash, expires_at, name, ip) VALUES (?, ?, ?, ?)", await sha256Hex(normalize(code)), now + CODE_TTL_MS, name, ip);
      this.q("INSERT INTO events (kind, at, ip) VALUES ('start', ?, ?)", now, ip);
      return json(201, { code, expiresInSeconds: CODE_TTL_MS / 1e3 });
    }
    if (path === "/pair") {
      if (this.q("SELECT COUNT(*) AS n FROM events WHERE kind = 'fail' AND ip = ? AND at > ?", ip, now - 10 * 6e4)[0].n >= FAILS_PER_10_MIN) {
        return err(429, "rate_limited", "too many wrong codes from this address; try again later", { retryAfterSeconds: 600 });
      }
      const code = typeof body.code === "string" ? normalize(body.code) : "";
      const hash = await sha256Hex(code);
      const row = code.length === 8 ? this.q("SELECT name FROM codes WHERE hash = ?", hash)[0] : void 0;
      if (!row) {
        this.q("INSERT INTO events (kind, at, ip) VALUES ('fail', ?, ?)", now, ip);
        return err(403, "bad_code", "that pairing code is wrong, used or expired");
      }
      this.q("DELETE FROM codes WHERE hash = ?", hash);
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
};

// src/index.ts
async function mailboxFor(env, req) {
  const token2 = bearer(req);
  const p = token2 ? parseToken(token2) : null;
  if (!token2 || !p) return err(401, "unauthorized", "missing or malformed bearer token", {});
  if (!env.RELAY_SECRET) return err(500, "misconfigured", "RELAY_SECRET is not set");
  if (!await deviceIdValid(env.RELAY_SECRET, p.deviceId)) return err(401, "unauthorized", "invalid credential");
  return { stub: env.MAILBOX.get(env.MAILBOX.idFromName(p.deviceId)), token: token2 };
}
__name(mailboxFor, "mailboxFor");
var AGENT_PATHS = [/^\/v1\/notify$/, /^\/v1\/status$/, /^\/v1\/receipts\/[^/]+$/, /^\/v1\/replies\/[^/]+$/];
var index_default = {
  async fetch(req, env) {
    const url = new URL(req.url);
    const path = url.pathname;
    if (path === "/" || path === "/health" || path === "/healthz") return json(200, { service: "herald-relay", ok: true, ...env.BUNDLE_HASH ? { bundle: env.BUNDLE_HASH } : {} });
    const oauth = await handleOAuth(req, env, url);
    if (oauth) return oauth;
    if (req.method === "POST" && (path === "/v1/pair/start" || path === "/v1/pair")) {
      if (!env.RELAY_SECRET) return err(500, "misconfigured", "RELAY_SECRET is not set");
      const reg = env.REGISTRY.get(env.REGISTRY.idFromName("registry"));
      return reg.fetch(new Request("https://registry" + (path === "/v1/pair" ? "/pair" : "/pair/start"), {
        method: "POST",
        body: await req.text(),
        headers: { "x-pairing-secret": req.headers.get("x-pairing-secret") ?? "", "x-client-ip": req.headers.get("cf-connecting-ip") ?? "" }
      }));
    }
    if (req.method === "GET" && path.startsWith("/v1/audio/")) {
      const key = decodeURIComponent(path.slice("/v1/audio/".length));
      const exp = Number(url.searchParams.get("exp"));
      const sig = url.searchParams.get("sig") ?? "";
      if (!/^[0-9a-f]{48}\/r_[0-9a-f]{24}\.m4a$/.test(key) || !Number.isFinite(exp)) return err(404, "not_found", "no such audio");
      if (exp < Date.now() / 1e3) return err(410, "expired", "this audio link has expired; read the reply again for a fresh one");
      if (!safeEqual(sig, await hmacHex(env.RELAY_SECRET, `audio:${key}:${exp}`))) return err(403, "forbidden", "bad signature");
      const obj = await env.AUDIO.get(key);
      if (!obj) return err(404, "not_found", "no such audio");
      return new Response(obj.body, { headers: { "content-type": "audio/mp4", "cache-control": "private, no-store", "content-length": String(obj.size) } });
    }
    if (path === "/mcp") {
      const unauthorized = /* @__PURE__ */ __name((r) => {
        if (r.status !== 401) return r;
        const h = new Headers(r.headers);
        h.set("www-authenticate", challenge(url.origin, !!bearer(req)));
        return new Response(r.body, { status: 401, headers: h });
      }, "unauthorized");
      const m = await mailboxFor(env, req);
      if (m instanceof Response) return unauthorized(m);
      const auth = "Bearer " + m.token;
      return unauthorized(await handleMcp(req, (p, init) => m.stub.fetch(new Request(url.origin + p, { ...init, headers: { authorization: auth, "content-type": "application/json" } }))));
    }
    const isDevice = path === "/v1/device" || path.startsWith("/v1/device/");
    if (isDevice || AGENT_PATHS.some((r) => r.test(path))) {
      const m = await mailboxFor(env, req);
      if (m instanceof Response) return m;
      return m.stub.fetch(req);
    }
    return err(404, "not_found", "no such endpoint");
  }
};
export {
  Mailbox,
  Registry,
  index_default as default
};
//# sourceMappingURL=index.js.map
