// MCP Events (protocol 2026-07-28): how a reply on the Mac wakes a cloud agent. An agent subscribes with a webhook URL; when the user
// answers a notification that agent sent, the relay POSTs a signed event to it (Standard Webhooks). Same shape as the bidbot relay.

import { DAY_MS } from "./util";

/** The one event: the user answered a notification this connector sent. Ids only; the answer is read with get_receipt / wait_for_reply. */
export const REPLY_EVENT = "notification.reply";
export const EVENTS = [{
  name: REPLY_EVENT,
  description: "The user answered (typed or recorded) a notification you sent with expectReply. Call get_receipt or wait_for_reply with data.notificationId " +
    "to read the answer. The payload holds ids only, never the text. A subscription lasts until you unsubscribe or the user revokes this connector in Herald.",
  delivery: ["webhook"],
  inputSchema: { type: "object", additionalProperties: false, properties: {} },
  payloadSchema: { type: "object", additionalProperties: false, required: ["notificationId", "id", "kind"], properties: {
    notificationId: { type: "string", description: "The id you sent (or the relay's id when you sent none)." },
    id: { type: "string", description: "The relay's own id for the notification." },
    kind: { type: "string", enum: ["text", "voice"] } } },
}];

export const MAX_SUBS_PER_KEY = 5;
export const DELIVERY_TIMEOUT_MS = 10_000;
export const RETRY_BASE_MS = 60_000;
export const HOUR_MS = 3600_000;
export const MAX_ATTEMPTS = 8;
export const MAX_REPLAY = 100;
export const EVENT_HISTORY_MS = 30 * DAY_MS;
/** A subscription does not lapse. `refreshBefore` is still reported, this far ahead, for clients that expect the field. */
export const REFRESH_AHEAD_MS = 10 * 365 * DAY_MS;
/** SQL condition on event_outbox alias o: the row is its subscription's oldest pending event. */
export const HEAD = "o.seq = (SELECT MIN(seq) FROM event_outbox h WHERE h.sub_id = o.sub_id)";

export type RpcOut = { result: Record<string, unknown> } | { error: { code: number; message: string; data?: unknown } };
export type Sub = { id: string; key_id: string; name: string; args: string; url: string; secret: string; created_at: number };
export type Outbox = { id: string; sub_id: string; seq: number; payload: string; attempts: number; next_at: number; created_at: number };
export type EventRow = { seq: number; key_id: string; rid: string; nid: string; kind: string; at: number };

/** The HMAC key of a Standard Webhooks secret (whsec_ + base64 of 24-64 bytes), or null if malformed. */
export function signingKey(secret: string): Uint8Array | null {
  if (!/^whsec_[A-Za-z0-9+/]+={0,2}$/.test(secret)) return null;
  try {
    const k = Uint8Array.from(atob(secret.slice(6)), (c) => c.charCodeAt(0));
    return k.length >= 24 && k.length <= 64 ? k : null;
  } catch { return null; }
}

/** A callback host must be a public name or address: no single-label, local or internal names, and no loopback, private, link-local, shared or reserved IPs. */
export function publicHost(hostname: string): boolean {
  const h = hostname.toLowerCase().replace(/\.$/, "");
  if (h.startsWith("[")) {
    const [head, tail] = h.slice(1, -1).split("::") as [string, string?];
    const part = (x: string | undefined) => (x ? x.split(":").map((g) => parseInt(g, 16)) : []);
    const a = part(head), b = part(tail);
    const g = tail === undefined ? a : [...a, ...Array(8 - a.length - b.length).fill(0), ...b];
    if (g.length !== 8 || g.some((x) => !(x >= 0 && x <= 0xffff))) return false;
    return !(g[0] === 0 || (g[0] & 0xfe00) === 0xfc00 || (g[0] & 0xffc0) === 0xfe80 || (g[0] & 0xffc0) === 0xfec0 || (g[0] & 0xff00) === 0xff00
      || (g[0] === 0x64 && g[1] === 0xff9b) || (g[0] === 0x2001 && g[1] === 0xdb8) || g[0] === 0x2002);
  }
  const v4 = /^(\d+)\.(\d+)\.(\d+)\.(\d+)$/.exec(h);
  if (v4) {
    const [a, b, c] = v4.slice(1).map(Number);
    return !(a === 0 || a === 10 || a === 127 || a >= 224 || (a === 100 && b >= 64 && b <= 127) || (a === 169 && b === 254) || (a === 172 && b >= 16 && b <= 31)
      || (a === 192 && b === 168) || (a === 192 && b === 0 && (c === 0 || c === 2)) || (a === 198 && (b === 18 || b === 19)) || (a === 198 && b === 51 && c === 100)
      || (a === 203 && b === 0 && c === 113));
  }
  return h.includes(".") && !/(^|\.)(localhost|local|internal|home\.arpa)$/.test(h);
}

/** A host name as the user may type it in Herald: lower case, no scheme, path or port. Null when it is not a plain public host name. */
export function cleanHost(v: unknown): string | null {
  if (typeof v !== "string") return null;
  const h = v.trim().toLowerCase().replace(/\.$/, "");
  if (!/^[a-z0-9]([a-z0-9-]{0,62}[a-z0-9])?(\.[a-z0-9]([a-z0-9-]{0,62}[a-z0-9])?)+$/.test(h) || h.length > 253) return null;
  return publicHost(h) ? h : null;
}

/** Retry-After as delay-seconds or an HTTP-date, in ms from now; 0 if absent or unreadable. */
export function retryAfterMs(v: string | null, now: number): number {
  if (!v) return 0;
  if (/^\d+$/.test(v.trim())) return Number(v.trim()) * 1000;
  const at = Date.parse(v);
  return Number.isFinite(at) ? Math.max(at - now, 0) : 0;
}

export async function hmacB64(key: Uint8Array, text: string): Promise<string> {
  const k = await crypto.subtle.importKey("raw", key, { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  return btoa(String.fromCharCode(...new Uint8Array(await crypto.subtle.sign("HMAC", k, new TextEncoder().encode(text)))));
}
