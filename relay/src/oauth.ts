// OAuth 2.1 for the relay, as the MCP authorization spec (2025-06-18) asks: the relay is its own authorization server.
//   RFC 9728 protected-resource metadata, RFC 8414 server metadata, RFC 7591 dynamic registration, PKCE S256 (required),
//   RFC 8707 resource indicators, RFC 7009 revocation. Approval happens on the user's Mac (see mailbox.ts), never here.
// This file is the Worker side: discovery, registration, the consent page, and routing /token and /revoke to the right
// mailbox. Tokens, codes and the approval state live in that mailbox.

import { DEVICE_GRANT } from "./mailbox";
import { deviceIdValid, parseOAuthSecret } from "./ids";
import { err, json, randomHex, safeEqual, sha256Hex } from "./util";

export const SCOPE = "notify";
export { DEVICE_GRANT };
const CORS = { "access-control-allow-origin": "*", "access-control-allow-headers": "authorization, content-type, mcp-protocol-version", "access-control-allow-methods": "GET, POST, OPTIONS" };

export const mcpUrl = (origin: string) => origin + "/mcp";
export const resourceMetadataUrl = (origin: string) => origin + "/.well-known/oauth-protected-resource";

/** The WWW-Authenticate challenge a 401 on /mcp carries (RFC 9728 section 5.1). */
export function challenge(origin: string, invalidToken: boolean): string {
  return `Bearer ${invalidToken ? 'error="invalid_token", ' : ""}resource_metadata="${resourceMetadataUrl(origin)}"`;
}

const cors = (r: Response): Response => { for (const [k, v] of Object.entries(CORS)) r.headers.set(k, v); return r; };
const oerr = (status: number, error: string, description: string, headers: Record<string, string> = {}) =>
  cors(json(status, { error, error_description: description }, headers));

function esc(s: string): string {
  return s.replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]!);
}

async function readForm(req: Request): Promise<URLSearchParams> {
  const out = new URLSearchParams();
  try { for (const [k, v] of (await req.formData()).entries()) if (typeof v === "string") out.append(k, v); } catch { /* not a form body */ }
  return out;
}

function registry(env: Env, path: string, body: unknown): Promise<Response> {
  return env.REGISTRY.get(env.REGISTRY.idFromName("registry")).fetch(new Request("https://registry" + path, { method: "POST", body: JSON.stringify(body) }));
}
function mailbox(env: Env, deviceId: string, path: string, body: unknown): Promise<Response> {
  return env.MAILBOX.get(env.MAILBOX.idFromName(deviceId)).fetch(new Request("https://mailbox/internal/oauth/" + path, { method: "POST", body: JSON.stringify(body) }));
}

// ---------- discovery

export function protectedResource(origin: string) {
  return {
    resource: mcpUrl(origin),
    authorization_servers: [origin],
    scopes_supported: [SCOPE],
    bearer_methods_supported: ["header"],
    resource_name: "Herald relay",
  };
}

export function serverMetadata(origin: string) {
  return {
    issuer: origin,
    authorization_endpoint: origin + "/authorize",
    token_endpoint: origin + "/token",
    registration_endpoint: origin + "/register",
    device_authorization_endpoint: origin + "/device_authorization",
    revocation_endpoint: origin + "/revoke",
    scopes_supported: [SCOPE],
    response_types_supported: ["code"],
    response_modes_supported: ["query"],
    grant_types_supported: ["authorization_code", "refresh_token", DEVICE_GRANT],
    code_challenge_methods_supported: ["S256"],
    token_endpoint_auth_methods_supported: ["none", "client_secret_post", "client_secret_basic"],
    revocation_endpoint_auth_methods_supported: ["none", "client_secret_post", "client_secret_basic"],
    service_documentation: "https://github.com/ivg-design/herald/blob/main/docs/CLOUD.md",
  };
}

// ---------- dynamic client registration (RFC 7591)

const BAD_SCHEMES = new Set(["javascript:", "data:", "vbscript:", "file:", "blob:", "about:", "ftp:"]);

/** https, http on a loopback host (native apps), or a private-use scheme. No fragments, no credentials. */
export function redirectUriValid(raw: unknown): raw is string {
  if (typeof raw !== "string" || raw.length > 500) return false;
  let u: URL;
  try { u = new URL(raw); } catch { return false; }
  if (u.hash || u.username || u.password || BAD_SCHEMES.has(u.protocol)) return false;
  if (u.protocol === "https:") return true;
  if (u.protocol === "http:") return ["localhost", "127.0.0.1", "[::1]"].includes(u.hostname);
  return /^[a-z][a-z0-9+.-]*:$/.test(u.protocol) && u.protocol !== "http:";
}

async function register(env: Env, req: Request): Promise<Response> {
  let b: Record<string, unknown>;
  try { b = (await req.json()) as Record<string, unknown>; } catch { return oerr(400, "invalid_client_metadata", "body must be JSON"); }
  // A client that only uses the device flow (an agent with no browser) has no redirect address to register.
  const deviceOnly = Array.isArray(b.grant_types) && b.grant_types.length > 0 && b.grant_types.every((g) => g === DEVICE_GRANT || g === "refresh_token") && b.grant_types.includes(DEVICE_GRANT);
  if (deviceOnly && b.redirect_uris === undefined) b.redirect_uris = [];
  if (!Array.isArray(b.redirect_uris) || (b.redirect_uris.length < 1 && !deviceOnly) || b.redirect_uris.length > 10 || !b.redirect_uris.every(redirectUriValid)) {
    return oerr(400, "invalid_redirect_uri", "redirect_uris must be 1-10 https (or loopback http) URLs without a fragment");
  }
  const method = b.token_endpoint_auth_method ?? "none";
  if (method !== "none" && method !== "client_secret_post" && method !== "client_secret_basic") {
    return oerr(400, "invalid_client_metadata", "token_endpoint_auth_method must be none, client_secret_post or client_secret_basic");
  }
  const grants = b.grant_types ?? ["authorization_code"];
  if (!Array.isArray(grants) || !grants.every((g) => g === "authorization_code" || g === "refresh_token" || g === DEVICE_GRANT)) {
    return oerr(400, "invalid_client_metadata", "grant_types may only be authorization_code, refresh_token and urn:ietf:params:oauth:grant-type:device_code");
  }
  if (b.response_types !== undefined && !(Array.isArray(b.response_types) && b.response_types.every((t) => t === "code"))) {
    return oerr(400, "invalid_client_metadata", "response_types may only be code");
  }
  const name = (typeof b.client_name === "string" ? b.client_name : "").replace(/[\u0000-\u001f\u007f<>]/g, "").trim().slice(0, 60) || "An app";
  const id = "hc_" + randomHex(16);
  const secret = method === "none" ? null : randomHex(32);
  const r = await registry(env, "/client/register", { id, name, redirectUris: b.redirect_uris, secretHash: secret ? await sha256Hex(secret) : null });
  if (!r.ok) return cors(new Response(r.body, { status: r.status, headers: { "content-type": "application/json", "cache-control": "no-store" } }));
  return cors(json(201, {
    client_id: id, client_id_issued_at: Math.floor(Date.now() / 1000), client_name: name, redirect_uris: b.redirect_uris,
    token_endpoint_auth_method: method, grant_types: ["authorization_code", "refresh_token", DEVICE_GRANT], response_types: ["code"], scope: SCOPE,
    ...(secret ? { client_secret: secret, client_secret_expires_at: 0 } : {}),
  }));
}

type Client = { id: string; name: string; redirectUris: string[]; secretHash: string | null };
async function getClient(env: Env, id: string): Promise<Client | null> {
  if (!/^hc_[0-9a-f]{32}$/.test(id)) return null;
  const r = await registry(env, "/client/get", { id });
  return r.ok ? ((await r.json()) as Client) : null;
}

/** client_id plus, for confidential clients, the secret (Basic or form). Returns the client or an error response. */
async function clientAuth(env: Env, req: Request, form: URLSearchParams): Promise<Client | Response> {
  let id = form.get("client_id") ?? "";
  let secret = form.get("client_secret") ?? "";
  const basic = /^Basic\s+(\S+)$/i.exec(req.headers.get("authorization") ?? "");
  if (basic) {
    try {
      const [u, ...rest] = atob(basic[1]).split(":");
      id = decodeURIComponent(u); secret = decodeURIComponent(rest.join(":"));
    } catch { return oerr(401, "invalid_client", "malformed Basic credentials", { "www-authenticate": 'Basic realm="herald-relay"' }); }
  }
  const c = await getClient(env, id);
  if (!c) return oerr(401, "invalid_client", "unknown client_id");
  if (c.secretHash && !safeEqual(c.secretHash, await sha256Hex(secret))) {
    return oerr(401, "invalid_client", "client authentication failed", basic ? { "www-authenticate": 'Basic realm="herald-relay"' } : {});
  }
  form.set("client_id", c.id);
  return c;
}

// ---------- the consent page

const CSS = `:root{color-scheme:light dark;--bg:#f6f5f2;--fg:#1c1b19;--mut:#6b6862;--card:#fff;--line:#dedbd4;--acc:#1f5eff}
@media(prefers-color-scheme:dark){:root{--bg:#161614;--fg:#eeece6;--mut:#a09d95;--card:#201f1d;--line:#38362f;--acc:#7da2ff}}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--fg);font:16px/1.5 -apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif}
main{max-width:30rem;margin:0 auto;padding:2.5rem 1rem}h1{font-size:1.4rem;line-height:1.25;margin:0 0 .5rem}
.card{background:var(--card);border:1px solid var(--line);border-radius:12px;padding:1rem 1.1rem;margin:1rem 0}
.mut{color:var(--mut);font-size:.9rem}ul{margin:.4rem 0 0;padding-left:1.2rem}h2{font-size:1rem;margin:0 0 .25rem}
input[type=text]{font:600 1.5rem ui-monospace,Menlo,monospace;letter-spacing:.3em;width:100%;padding:.5rem .7rem;border-radius:8px;border:1px solid var(--line);background:var(--bg);color:var(--fg)}
button{font:inherit;border-radius:8px;border:1px solid var(--line);background:var(--card);color:var(--fg);padding:.5rem 1rem;cursor:pointer}
button.p{background:var(--acc);border-color:var(--acc);color:#fff}.row{display:flex;gap:.6rem;margin-top:.7rem}.bad{color:#c0392b}.dot{display:inline-block;width:.6rem;height:.6rem;border-radius:50%;background:var(--acc);margin-right:.4rem;animation:b 1.2s infinite}
@keyframes b{50%{opacity:.25}}`;

function page(status: number, title: string, body: string, script = ""): Response {
  const nonce = randomHex(12);
  const html = `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>${esc(title)}</title><style nonce="${nonce}">${CSS}</style></head><body><main>${body}</main>${script ? `<script nonce="${nonce}">${script}</script>` : ""}</body></html>`;
  return new Response(html, { status, headers: {
    "content-type": "text/html; charset=utf-8", "cache-control": "no-store", "referrer-policy": "no-referrer", "x-frame-options": "DENY",
    "content-security-policy": `default-src 'none'; style-src 'nonce-${nonce}'; script-src 'nonce-${nonce}'; connect-src 'self'; base-uri 'none'; frame-ancestors 'none'`,
  } });
}

const errorPage = (message: string, status = 400) => page(status, "Herald", `<h1>Can't connect</h1><div class="card">${esc(message)}</div><p class="mut">Nothing was approved. Close this tab and start again from the app.</p>`);

function consentPage(rid: string, client: Client, redirectHost: string, online: boolean, note = ""): Response {
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

function errorRedirect(redirect: string, error: string, description: string, state: string | null): Response {
  const u = new URL(redirect);
  u.searchParams.set("error", error);
  u.searchParams.set("error_description", description);
  if (state) u.searchParams.set("state", state);
  return new Response(null, { status: 302, headers: { location: u.toString(), "cache-control": "no-store" } });
}

async function authorize(env: Env, req: Request, url: URL): Promise<Response> {
  if (!env.RELAY_SECRET) return errorPage("The relay is misconfigured.", 500);
  const q = url.searchParams;
  // Until the client and its redirect_uri are verified, errors are shown here and never redirected (RFC 6749 section 4.1.2.1).
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

  const devices = ((await (await registry(env, "/devices", {})).json()) as { devices: { id: string; name: string | null }[] }).devices;
  if (devices.length === 0) return page(200, "Pair Herald first", `<h1>Pair Herald first</h1><div class="card">This relay is not paired with a Mac yet. In Herald, open Settings, Cloud and pair this relay, then connect ${esc(client.name)} again.</div>`);
  let device = devices[0];
  if (devices.length > 1) {
    const pick = Number(q.get("device"));
    if (!Number.isInteger(pick) || pick < 1 || pick > devices.length) {
      const next = new URL(url);
      const links = devices.map((d, i) => { next.searchParams.set("device", String(i + 1)); return `<li><a href="${esc(next.pathname + next.search)}">${esc(d.name ?? "Mac " + (i + 1))}</a></li>`; }).join("");
      return page(200, "Choose a Mac", `<h1>Which Mac?</h1><p class="mut">${esc(client.name)} will notify the Mac you choose.</p><div class="card"><ul>${links}</ul></div>`);
    }
    device = devices[pick - 1];
  }
  const r = await mailbox(env, device.id, "begin", { clientId: client.id, clientName: client.name, redirectUri: redirect, challenge: chal, state, scope: SCOPE, resource: mcp });
  if (r.status === 429) return errorPage("Approvals are already waiting in Herald (or too many were requested). Answer them there, or wait a few minutes.", 429);
  if (!r.ok) return errorPage("Could not start the approval.", 502);
  const { id, online } = (await r.json()) as { id: string; online: boolean };
  let host = redirect;
  try { host = new URL(redirect).host || new URL(redirect).protocol; } catch { /* keep the raw string */ }
  return consentPage(id, client, host, online);
}

async function ridDevice(env: Env, rid: string): Promise<string | null> {
  if (!/^[0-9a-f]{72}$/.test(rid)) return null;
  const deviceId = rid.slice(0, 48);
  return (await deviceIdValid(env.RELAY_SECRET, deviceId)) ? deviceId : null;
}

async function decided(r: Response): Promise<Response> {
  const j = (await r.json().catch(() => ({}))) as { status?: string; redirect?: string; attemptsLeft?: number };
  if (j.redirect) return new Response(null, { status: 302, headers: { location: j.redirect, "cache-control": "no-store" } });
  return errorPage(j.status === "expired" ? "This request expired. Start again from the app." : "This request is no longer open.");
}

async function codeEntry(env: Env, req: Request): Promise<Response> {
  const form = await readForm(req);
  const rid = form.get("rid") ?? "";
  const deviceId = await ridDevice(env, rid);
  if (!deviceId) return errorPage("Unknown request.");
  const r = await mailbox(env, deviceId, "code", { id: rid, code: form.get("code") ?? "" });
  const j = (await r.clone().json().catch(() => ({}))) as { status?: string; attemptsLeft?: number; redirect?: string };
  if (j.status === "wrong_code") {
    // Re-render the page with the note. The client is looked up again from the pending request via status.
    return page(200, "Wrong code", `<h1>That code is wrong</h1><div class="card bad">${j.attemptsLeft} ${j.attemptsLeft === 1 ? "try" : "tries"} left. Check Herald, Settings, Cloud, Connector approvals.</div>
<form method="post" action="/authorize/code"><input type="hidden" name="rid" value="${esc(rid)}"><input type="text" name="code" inputmode="numeric" autocomplete="one-time-code" pattern="[0-9 ]{6,7}" maxlength="7" placeholder="000000" required><div class="row"><button class="p" type="submit">Approve</button></div></form>`);
  }
  return decided(r);
}

async function denyEntry(env: Env, req: Request): Promise<Response> {
  const rid = (await readForm(req)).get("rid") ?? "";
  const deviceId = await ridDevice(env, rid);
  if (!deviceId) return errorPage("Unknown request.");
  return decided(await mailbox(env, deviceId, "deny", { id: rid }));
}

async function statusEntry(env: Env, url: URL): Promise<Response> {
  const rid = url.searchParams.get("rid") ?? "";
  const deviceId = await ridDevice(env, rid);
  if (!deviceId) return json(404, { status: "unknown" });
  const r = await mailbox(env, deviceId, "status", { id: rid });
  return new Response(r.body, { status: r.status === 404 ? 200 : r.status, headers: { "content-type": "application/json", "cache-control": "no-store" } });
}

// ---------- token and revoke

async function token(env: Env, req: Request): Promise<Response> {
  const form = await readForm(req);
  const c = await clientAuth(env, req, form);
  if (c instanceof Response) return c;
  const grant = form.get("grant_type");
  const raw = grant === "authorization_code" ? form.get("code") : grant === "refresh_token" ? form.get("refresh_token") : grant === DEVICE_GRANT ? form.get("device_code") : null;
  const parsed = raw ? parseOAuthSecret(raw, grant === "refresh_token" ? "hrr" : grant === DEVICE_GRANT ? "hrv" : "hrc") : null;
  if (grant !== "authorization_code" && grant !== "refresh_token" && grant !== DEVICE_GRANT) return oerr(400, "unsupported_grant_type", `grant_type must be authorization_code, refresh_token or ${DEVICE_GRANT}`);
  if (grant === DEVICE_GRANT && !parsed) return oerr(400, "invalid_grant", "device_code is missing or malformed");
  if (!parsed || !(await deviceIdValid(env.RELAY_SECRET, parsed.deviceId))) return oerr(400, "invalid_grant", "unknown or malformed grant");
  const body = Object.fromEntries(form.entries());
  delete body.client_secret;
  const r = await mailbox(env, parsed.deviceId, "token", body);
  return cors(new Response(r.body, { status: r.status, headers: { "content-type": "application/json; charset=utf-8", "cache-control": "no-store", pragma: "no-cache" } }));
}

async function revoke(env: Env, req: Request): Promise<Response> {
  const form = await readForm(req);
  const c = await clientAuth(env, req, form);
  if (c instanceof Response) return c;
  const t = form.get("token") ?? "";
  const parsed = parseOAuthSecret(t, "hrr") ?? parseOAuthSecret(t, "hra");
  if (parsed && (await deviceIdValid(env.RELAY_SECRET, parsed.deviceId))) await mailbox(env, parsed.deviceId, "revoke", { token: t, client_id: c.id });
  return cors(json(200, {}));
}


// ---------- device authorization grant (RFC 8628): for an agent that has no usable browser

async function deviceAuthorization(env: Env, req: Request, url: URL): Promise<Response> {
  const form = await readForm(req);
  const c = await clientAuth(env, req, form);
  if (c instanceof Response) return c;
  const scope = (form.get("scope") ?? "").trim();
  if (scope && scope.split(/\s+/).some((x) => x !== SCOPE)) return oerr(400, "invalid_scope", "the only scope is notify");
  const devices = ((await (await registry(env, "/devices", {})).json()) as { devices: { id: string }[] }).devices;
  if (devices.length === 0) return oerr(400, "invalid_request", "this relay is not paired with a Mac yet; pair Herald in Settings, Cloud first");
  // Several Macs: the optional `device` (1-based) picks one; the first is the default.
  const pick = form.get("device") === null ? 1 : Number(form.get("device"));
  if (!Number.isInteger(pick) || pick < 1 || pick > devices.length) return oerr(400, "invalid_request", `device must be 1 to ${devices.length}`);
  const r = await mailbox(env, devices[pick - 1].id, "device_begin", { clientId: c.id, clientName: c.name, scope: SCOPE, resource: mcpUrl(url.origin) });
  if (r.status === 429) return oerr(429, "slow_down", "approvals are already waiting in Herald (or too many were requested); answer them there or wait a few minutes", { "retry-after": "60" });
  if (!r.ok) return oerr(502, "temporarily_unavailable", "could not start the approval");
  const d = (await r.json()) as { deviceCode: string; userCode: string; expiresIn: number; interval: number; online: boolean };
  const verification = url.origin + "/activate";
  return cors(json(200, {
    device_code: d.deviceCode, user_code: d.userCode, verification_uri: verification,
    verification_uri_complete: verification + "?user_code=" + encodeURIComponent(d.userCode), expires_in: d.expiresIn, interval: d.interval,
  }));
}

const CODE_FIELD = `<input type="text" name="user_code" autocomplete="off" autocapitalize="characters" spellcheck="false" maxlength="9" placeholder="BDFG-HJKM" required`;
const APPROVAL_FIELD = `<input type="text" name="code" inputmode="numeric" autocomplete="one-time-code" pattern="[0-9 ]{6,7}" maxlength="7" placeholder="000000" required>`;

function activatePage(prefill = "", note = ""): Response {
  return page(200, "Activate", `<h1>Approve an agent</h1>
<p class="mut">An agent that cannot open a browser asked to send you notifications through Herald. It printed a code like BDFG-HJKM. Herald on your Mac shows the same code.</p>
${note ? `<p class="bad">${esc(note)}</p>` : ""}
<form class="card" method="post" action="/activate"><h2>The agent's code</h2>${CODE_FIELD} value="${esc(prefill)}"><div class="row"><button class="p" type="submit">Continue</button></div></form>
<p class="mut">Easier: approve it in Herald on your Mac (a banner, or Settings, Cloud, Connector approvals).</p>`);
}

async function activateLookup(env: Env, userCode: string): Promise<{ rid: string; clientName: string; userCode: string } | null> {
  const devices = ((await (await registry(env, "/devices", {})).json()) as { devices: { id: string }[] }).devices;
  for (const d of devices) {
    const r = await mailbox(env, d.id, "device_lookup", { user_code: userCode });
    if (r.ok) { const j = (await r.json()) as { id: string; clientName: string; userCode: string }; return { rid: j.id, clientName: j.clientName, userCode: j.userCode }; }
  }
  return null;
}

function activateConfirm(a: { rid: string; clientName: string; userCode: string }, note = ""): Response {
  return page(200, "Approve", `<h1>Approve ${esc(a.clientName)}?</h1>
<p class="mut">Code <b>${esc(a.userCode)}</b>. It will be able to send notifications to your Mac and read receipts and replies. Nothing else.</p>
<div class="card"><h2>Prove it is you</h2><p class="mut" style="margin-top:0">Herald, Settings, Cloud, Connector approvals shows a 6-digit approval code for this request. Type it here.</p>
${note ? `<p class="bad">${esc(note)}</p>` : ""}
<form method="post" action="/activate/approve"><input type="hidden" name="rid" value="${esc(a.rid)}">${APPROVAL_FIELD}<div class="row"><button class="p" type="submit">Approve</button></div></form></div>
<form method="post" action="/activate/deny"><input type="hidden" name="rid" value="${esc(a.rid)}"><button type="submit">Deny</button></form>`);
}

async function activateEntry(env: Env, req: Request): Promise<Response> {
  const code = (await readForm(req)).get("user_code") ?? "";
  const a = await activateLookup(env, code);
  return a ? activateConfirm(a) : activatePage(code, "That code is wrong or expired. Check what the agent printed.");
}

const donePage = (title: string, msg: string) => page(200, title, `<h1>${esc(title)}</h1><div class="card">${esc(msg)}</div>`);

async function activateApprove(env: Env, req: Request): Promise<Response> {
  const form = await readForm(req);
  const rid = form.get("rid") ?? "";
  const deviceId = await ridDevice(env, rid);
  if (!deviceId) return errorPage("Unknown request.");
  const r = await mailbox(env, deviceId, "code", { id: rid, code: form.get("code") ?? "" });
  const j = (await r.json().catch(() => ({}))) as { status?: string; attemptsLeft?: number };
  if (j.status === "wrong_code") {
    return page(200, "Wrong code", `<h1>That code is wrong</h1><div class="card bad">${j.attemptsLeft} ${j.attemptsLeft === 1 ? "try" : "tries"} left. Check Herald, Settings, Cloud, Connector approvals.</div>
<form method="post" action="/activate/approve"><input type="hidden" name="rid" value="${esc(rid)}">${APPROVAL_FIELD}<div class="row"><button class="p" type="submit">Approve</button></div></form>`);
  }
  if (j.status === "approved") return donePage("Approved", "The agent can now send you notifications. You can close this tab. Revoke it any time in Herald, Settings, Cloud.");
  if (j.status === "denied") return donePage("Denied", "Nothing was approved.");
  return errorPage(j.status === "expired" ? "This request expired. The agent has to start again." : "This request is no longer open.");
}

async function activateDeny(env: Env, req: Request): Promise<Response> {
  const rid = (await readForm(req)).get("rid") ?? "";
  const deviceId = await ridDevice(env, rid);
  if (!deviceId) return errorPage("Unknown request.");
  await mailbox(env, deviceId, "deny", { id: rid });
  return donePage("Denied", "Nothing was approved.");
}

/** The root of the relay: a small page for a person who opened the address, and a pointer for an agent. */
export function rootPage(origin: string): Response {
  const l = (p: string, t = p) => `<li><a href="${esc(p)}">${esc(t)}</a></li>`;
  return page(200, "Herald relay", `<h1>Herald relay</h1>
<p class="mut">This is a private relay that lets an AI agent send notifications to one person's Mac (the Herald app). Nothing here is public: an agent needs a key or an approval from the Mac's owner.</p>
<div class="card"><h2>For an agent</h2><ul>${l("/.well-known/oauth-authorization-server", "OAuth server metadata")}${l("/.well-known/oauth-protected-resource", "Protected resource metadata")}<li>MCP endpoint: <code>${esc(mcpUrl(origin))}</code></li></ul>
<p class="mut" style="margin:.6rem 0 0">No browser? Use the device flow: <code>POST /register</code>, <code>POST /device_authorization</code>, tell the user the code, poll <code>POST /token</code>.</p></div>
<div class="card"><h2>For the owner</h2><ul>${l("/activate", "Approve an agent with a code")}${l("/health", "Health check")}</ul></div>
<p class="mut"><a href="https://github.com/ivg-design/herald/blob/main/docs/CLOUD.md">Documentation</a></p>`);
}

// ---------- routing

/** Returns a response for the OAuth routes, or null when the path is not one of them. */
export async function handleOAuth(req: Request, env: Env, url: URL): Promise<Response | null> {
  const p = url.pathname, m = req.method;
  const wellKnown = p.startsWith("/.well-known/");
  const ours = wellKnown || ["/register", "/authorize", "/authorize/code", "/authorize/deny", "/authorize/status", "/token", "/revoke", "/device_authorization", "/activate", "/activate/approve", "/activate/deny"].includes(p);
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
  if (p === "/activate" && m === "GET") return activatePage(url.searchParams.get("user_code") ?? "");
  if (m !== "POST") return err(405, "method_not_allowed", "POST only");
  switch (p) {
    case "/register": return register(env, req);
    case "/token": return token(env, req);
    case "/revoke": return revoke(env, req);
    case "/authorize/code": return codeEntry(env, req);
    case "/authorize/deny": return denyEntry(env, req);
    case "/device_authorization": return deviceAuthorization(env, req, url);
    case "/activate": return activateEntry(env, req);
    case "/activate/approve": return activateApprove(env, req);
    case "/activate/deny": return activateDeny(env, req);
  }
  return err(405, "method_not_allowed", "GET only");
}
