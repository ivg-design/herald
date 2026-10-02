import { hmacHex, randomHex, safeEqual } from "./util";

// Device id: 32 hex random + 16 hex of HMAC(RELAY_SECRET, random). The Worker checks the MAC before it touches a
// Durable Object, so a stranger cannot make the relay create mailboxes by guessing ids.
//   device token: hrd_<deviceId>_<64 hex secret>
//   agent key:    hrk_<deviceId>_<8 hex keyId>_<64 hex secret>

export async function newDeviceId(relaySecret: string): Promise<string> {
  const r = randomHex(16);
  return r + (await hmacHex(relaySecret, "device:" + r)).slice(0, 16);
}

export async function deviceIdValid(relaySecret: string, id: string): Promise<boolean> {
  if (!/^[0-9a-f]{48}$/.test(id)) return false;
  const mac = (await hmacHex(relaySecret, "device:" + id.slice(0, 32))).slice(0, 16);
  return safeEqual(mac, id.slice(32));
}

export type Principal =
  | { kind: "device"; deviceId: string; secret: string }
  | { kind: "agent"; deviceId: string; keyId: string; secret: string }
  | { kind: "oauth"; deviceId: string; secret: string };

/** Splits a bearer token; null when it is not shaped like one of ours. Does not verify anything. */
export function parseToken(token: string): Principal | null {
  const p = token.split("_");
  if (p[0] === "hrd" && p.length === 3 && /^[0-9a-f]{48}$/.test(p[1]) && /^[0-9a-f]{64}$/.test(p[2])) {
    return { kind: "device", deviceId: p[1], secret: p[2] };
  }
  if (p[0] === "hrk" && p.length === 4 && /^[0-9a-f]{48}$/.test(p[1]) && /^[0-9a-f]{8}$/.test(p[2]) && /^[0-9a-f]{64}$/.test(p[3])) {
    return { kind: "agent", deviceId: p[1], keyId: p[2], secret: p[3] };
  }
  // OAuth access token: hra_<deviceId>_<64 hex>. Refresh (hrr_) and authorization codes (hrc_) share the shape but are
  // only ever read by the /token and /revoke endpoints, through parseOAuthSecret.
  if (p[0] === "hra" && p.length === 3 && /^[0-9a-f]{48}$/.test(p[1]) && /^[0-9a-f]{64}$/.test(p[2])) {
    return { kind: "oauth", deviceId: p[1], secret: p[2] };
  }
  return null;
}

/** hrr_ (refresh), hrc_ (authorization code) or hrv_ (device code): `<prefix>_<deviceId>_<hex>`. */
export function parseOAuthSecret(token: string, prefix: "hrr" | "hrc" | "hra" | "hrv"): { deviceId: string } | null {
  const p = token.split("_");
  if (p[0] === prefix && p.length === 3 && /^[0-9a-f]{48}$/.test(p[1]) && /^[0-9a-f]{32,64}$/.test(p[2])) return { deviceId: p[1] };
  return null;
}

export const oauthToken = (prefix: "hrr" | "hrc" | "hra" | "hrv", deviceId: string, secret: string) => `${prefix}_${deviceId}_${secret}`;
export const deviceToken = (deviceId: string, secret: string) => `hrd_${deviceId}_${secret}`;
export const agentKey = (deviceId: string, keyId: string, secret: string) => `hrk_${deviceId}_${keyId}_${secret}`;
