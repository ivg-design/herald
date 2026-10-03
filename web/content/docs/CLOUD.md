# Cloud relay: notifications from an agent running in the cloud

A cloud agent (Claude, Codex, anything that speaks remote MCP or HTTPS) cannot reach your Mac, and you do not want it to.
The relay is a small Cloudflare Worker that holds a mailbox for your Mac. The agent puts notifications in; Herald, which
keeps one **outbound** WebSocket open to the relay, takes them out and shows them through its normal path. There is no inbound
port on the Mac and the agent never talks to Herald directly.

```
cloud agent --HTTPS or remote MCP (agent key)--> relay (Worker + Durable Object "mailbox") <--WebSocket, outbound-- Herald
                                                         receipts and replies flow back the same way
```

The relay is **yours**: Herald puts it in your own Cloudflare account (free plan is enough) with one switch, **Settings > Cloud > Enable relay**.
Nobody else's server is involved and there is no shared default relay. Source: `relay/`. Herald's side: `Sources/Herald/Relay/`.

## Set up your relay (Enable relay)

1. **Settings > Cloud > Enable relay.** With no relay yet, a sheet opens: *Create your relay on Cloudflare (free)*.
2. **Create a token.** *Open Cloudflare...* opens Cloudflare's token page with the three permissions already filled in and the name
   "Herald relay". (No account? *I need a free Cloudflare account* opens the sign-up page.) Press *Continue to summary*, then *Create Token*,
   and copy the token.
3. **Paste it and press Deploy.** Herald does the rest through Cloudflare's API, naming each step in the sheet: check the token, find your
   account, find (or create) your `workers.dev` address, create the voice-reply bucket and its 7-day expiry, upload the relay, switch on its
   address, wait until `GET /health` answers, then **pair this Mac automatically** (the pairing code never shows). The sheet ends with the
   switch on and a green **Online**.
4. The relay's connector URL is `https://herald-relay.<your-subdomain>.workers.dev/mcp`, shown in Settings with a Copy button, together
   with two ready-made instruction blocks: **ChatGPT / OpenAI cloud agents** (add the URL as a connector, choose OAuth, approve in Herald)
   and **Claude Code / Codex CLI** (a static key). Below them: connected agents with Revoke, and Usage today.

If a step fails, the sheet shows Cloudflare's own message and **Retry**. Running Deploy again **upgrades the Worker in place** (same name,
same data, same secrets). Settings shows *Update available* when the relay bundled with your Herald differs from the one running (Herald
reads the bundle hash from `GET /health`, set as the Worker var `BUNDLE_HASH`).

**Turning the switch off** unpairs this Mac, which revokes every agent key and connector. The Worker stays in your Cloudflare account until
you press *Delete relay from Cloudflare* (Advanced).

### The API token

| Permission (Cloudflare name, template key) | Why |
|---|---|
| Workers Scripts: Edit (`workers_scripts`) | upload the relay, switch on its workers.dev address, set its variables and secrets |
| Workers R2 Storage: Edit (`workers_r2`) | create the voice-reply bucket and its expiry rule |
| Account Settings: Read (`account_settings`) | find your account id |
| Zone: Read (`zone`) | custom domain: list your zones, find the one you pick |
| DNS: Edit (`dns`) | custom domain: Cloudflare creates the DNS record |
| Workers Routes: Edit (`workers_routes`) | custom domain: attach the relay to the hostname |
| Zone Settings: Edit (`zone_settings`) | custom domain: read the zone's settings |
| Config Settings: Edit (`config_settings`) | custom domain: the Configuration Rule that switches Browser Integrity Check off |
| Zone WAF: Edit (`waf`) | custom domain: a narrow skip rule for the relay hostname |

The last six are only used for the [custom domain](#custom-domain-optional). A token without
them still deploys the relay on workers.dev; asking for a custom domain with such a token stops with "Token is missing Zone
permissions ..." (create a new token from the pre-filled page, or skip the custom domain). Group names are Cloudflare's; the template
keys in the page link are Herald's best match, and the page lists any it does not know, so check the six zone rows are ticked.

The page Herald opens is `https://dash.cloudflare.com/profile/api-tokens?permissionGroupKeys=[...]&accountId=*&zoneId=all&name=Herald relay`
(Cloudflare's "create a token from a link" format, [docs](https://developers.cloudflare.com/fundamentals/api/how-to/account-owned-token-template/)).
You can narrow the token to your account on that page.

### What Herald stores where

| What | Where |
|---|---|
| Cloudflare API token | Secret store (below; service `com.ivg.herald.cloudflare`), this device only. Sent only to `api.cloudflare.com`. Never shown again, never returned by the local API or MCP. *Forget the token* (Advanced) deletes it. |
| Pairing secret (made at the first deploy) | Secret store; also a secret on the Worker. The relay demands it (`X-Pairing-Secret`) when a Mac pairs, so a stranger who finds the URL cannot pair. Shown under Advanced. |
| Relay signing secret (`RELAY_SECRET`, made at the first deploy) | Secret store and a Worker secret; signs device ids. Kept so a deploy from scratch is possible. |
| Device token (`hrd_...`) | Secret store (service `com.ivg.herald.relay`). |
| Account id, worker name, subdomain, bucket, limits, deployed bundle hash | `relay-cloudflare.json` in Herald's support folder (no secrets). |

**The secret store, and why there is no Keychain password prompt.** Herald's secrets used to sit in the legacy login keychain, whose access
list is tied to the app's code signature: after an update macOS asked "Herald wants to use your confidential information ... enter your
keychain password", over and over if that password is out of sync. Herald now keeps each secret in the **data-protection keychain**
(`kSecUseDataProtectionKeychain`, this device only, available after first unlock), which has no per-signature access list and never
prompts. That keychain needs the app's application identifier from a provisioning profile; a Developer ID build without one is refused
with `errSecMissingEntitlement` (-34018), and Herald then keeps the secret in a **file with mode 0600** in its support folder
(`~/Library/Application Support/Herald/secrets/<service>.<account>`), the same protection the local API `token` file has. (Herald does not
add a `keychain-access-groups` entitlement: it is restricted, and a build that claims it without a profile does not launch.)
**Migration**: the first time a secret is not found in the new place, Herald reads the old keychain item **once** (macOS may ask one last
time; Deny, a wrong password or a locked keychain simply mean "not found", and Herald pairs again or asks for the Cloudflare token
again), copies it into the new store and deletes the old item. A marker file (`secrets/<service>.<account>.migrated`) makes sure the old
item is never read twice. `herald`, `herald-mcp` and the helpers read only the support folder's `token` file and never use the keychain.

### Upgrade, redeploy, delete

- **Upgrade**: Deploy again (the *Update the relay* button, or `relay_deploy`). The Worker is uploaded with the same bindings, the Durable
  Object classes are not migrated again and the existing secrets are kept: Herald reuses the signing secret (`RELAY_SECRET`) and the pairing
  secret it holds in its secret store (reading the legacy keychain item first when that is where they still live), and when it holds none
  the Worker keeps the ones it has. An upgrade never rotates the signing secret, so this Mac's device token and every agent key keep working.
  Only a *first* deploy, or a deploy over a Worker that was deleted, makes a new signing secret; if this Mac was paired with the old one the
  relay refuses its token (401), and Herald **pairs again automatically** at the end of the deploy (the step log shows "Pair this Mac again",
  `relay_deploy` returns a warning): agent keys and connectors made before must be created again. A "relay is not answering" message from an
  earlier attempt is cleared as soon as the socket is online.
- **Change a setting** (Advanced): a value that lives in the Worker (limits, retention, worker name, bucket) redeploys it; the rest is Herald's.
- **Delete relay from Cloudflare** (Advanced, with a confirmation): deletes the Worker with every mailbox, key and queued notification,
  and the bucket when it is empty (Cloudflare refuses to delete a bucket that still holds voice replies; Herald says so).

### Several Macs

One relay can serve several Macs (`maxDevices`, default 5); each has its own mailbox, keys and limits. The relay keeps a list of them and keeps
it clean:

- A Mac that pairs again **under the same device name** replaces its old entry (the old mailbox is purged: keys, queue, consents and voice
  replies). Unpairing removes the entry and purges the mailbox too. Herald also calls `POST /v1/device/prune` after every pairing, which
  drops this Mac's same-name leftovers and any entry that is stale.
- Stale means: its credentials were rotated (its id no longer verifies against the relay's signing secret), its mailbox is gone, or it has not
  connected for 30 days. The relay checks lazily whenever it lists devices and once a day (a Durable Object alarm, no cron trigger).
- An agent that gives no `device=` reaches the Mac that is connected right now, else the most recently seen; `/authorize` does the same and its
  page names the Mac, with links to the others.
- Settings > Cloud > Advanced > **Devices on this relay** lists every Mac (name, connected or last seen, "this Mac") and offers **Remove**
  for an entry this Mac may remove: the same name as this Mac, rotated credentials, or no connection for a week. A different active Mac is
  never removable from another (`403 not_removable`). `relay_status` carries the same list as `devices`.

The device-token routes: `GET /v1/device/devices`, `POST /v1/device/prune`, `DELETE /v1/device/devices/{id}`.

### Advanced

Everything is visible and editable: relay URL (any relay, not only Cloudflare), account id, worker name, workers.dev subdomain, R2 bucket,
voice replies kept (days, default 7), undelivered kept (hours, default 24), notifications per day (500), most waiting at once (100),
largest request (32 KB), per key per 10 minutes (60), Macs that may pair (5), this Mac's name, keep-alive seconds (300), the pairing
secret; plus **Apply settings**, **Redeploy**, **Test connection** (health, then a notification through the relay and its receipt),
**Pair with a code** (for a relay Herald did not deploy), **Unpair**, **Forget token** and **Delete relay from Cloudflare**.
The same fields are `relay_settings` in the local MCP and `GET|PUT /v1/relay/settings`.

### Custom domain (optional)

Symptom: a cloud agent (an OpenAI sandbox, ChatGPT) calling `https://<worker>.<account>.workers.dev` gets **403 / Error 1010**
("the owner of this website has banned your access based on your browser's signature"). That is Cloudflare's **Browser Integrity
Check**, which rejects Python's default `User-Agent: Python-urllib/3.x` on every Cloudflare-fronted host before the request reaches the
relay (any other value works: curl, requests, aiohttp, no User-Agent, a custom string). **The simplest fix: send a custom
User-Agent such as `Herald-Agent/1.0`:**

```python
req = urllib.request.Request(url, headers={"User-Agent": "Herald-Agent/1.0", "Authorization": "Bearer <key>"})
```

The instruction blocks Herald gives for cloud agents carry this note. A custom domain is the optional alternative: a hostname in a
zone you control, with the check switched off for that hostname only, so even default library User-Agents work; it also gives the
relay a stable, branded address. workers.dev's check cannot be switched off. `relay_test` reports `browserCheckActive` (it asks
`/health` and `/mcp` with `Python-urllib/3.12` and with a custom User-Agent) and says when the check is active on the hostname.

Settings > Cloud > Advanced > Custom domain (or `relay_zones`, then `relay_settings {settings: {customDomain: {zone, hostname}}}`):

1. **Load zones** lists the zones the token sees (`GET /zones`; `relay_zones`). Pick one; Herald suggests `herald.<zone>`.
2. Herald deploys (idempotent, same Worker) and then: **attaches a Workers Custom Domain**
   (`PUT /accounts/{id}/workers/domains {hostname, service, environment: "production", zone_id, zone_name}`; Cloudflare creates the DNS
   record and the certificate); **creates a Configuration Rule** in the zone, phase `http_config_settings`, action `set_config` with
   `bic: false`, expression `(http.host eq "<hostname>")`, description "Herald relay: allow non-browser clients" (found by that
   description and updated on a re-run; other rules in the zone are never touched); **adds a WAF custom-rule skip** in phase
   `http_request_firewall_custom` for the same host (products `bic`, `securityLevel`); **checks Bot Fight Mode**; and waits until
   `https://<hostname>/health` answers (the certificate can take a minute or two; press Retry).
3. Herald points this Mac at `https://<hostname>`. The relay is the same Worker, and a device token is signed by the Worker, not
   tied to a hostname, so **this Mac stays paired** (Herald verifies the token and re-pairs silently only if the relay refuses it).
   Agent keys keep working on both addresses. Settings shows both addresses, the custom one as canonical.
4. **Existing OAuth connectors (ChatGPT) are bound to the old `/mcp` URL: add them again with the new URL.** Discovery, issuer and the
   OAuth `resource` follow the request's Host, so the relay needs no redeploy for a new hostname.

**Bot Fight Mode.** If the zone has Bot Fight Mode (free plan) on, Herald says so: no rule can bypass it on the free plan, so turn it off
in the Cloudflare dashboard (Security > Bots), or it can still challenge cloud agents. Super Bot Fight Mode with "Definitely
automated" not set to Allow is reported the same way. These are warnings, not failures. A missing Zone WAF permission is a warning
too; a missing Zone, DNS, Workers Routes or Config Settings permission stops the deploy with a clear message.

After a deploy without a custom domain, Settings > Cloud shows "Cloud agents: send a custom User-Agent; or set up a custom domain to skip Cloudflare's browser check" with **Set up...**.
"Use workers.dev again" removes the setting and points Herald back at workers.dev; the hostname, DNS record and rules stay in your
Cloudflare account (delete them there if you want them gone).

### Your own relay without Herald's deploy

Any relay that speaks this protocol works: put its address in Advanced > Relay URL and use *Pair with a code* (or `POST /v1/relay/pair`).
`cd relay && npm install && npm run deploy` still deploys the same Worker with wrangler ([Operating the relay](#operating-the-relay)).
`conformance/` is a black-box suite any implementation can run: `RELAY_URL=https://... npm test -w conformance`.

## Connect a cloud agent

1. **Enable relay** (once; see above). Herald pairs itself: it asks the relay for a one-time code (valid 10 minutes), redeems it and stores the
   device token in the Keychain. Status turns to Online.
2. **Create an agent key**: Settings > Cloud > Agent keys > name (for example `build-bot`), Agent (Claude, Codex or Other) > **Create key**.
   The key and a ready-to-paste connector block are shown **once** (the relay keeps only a hash). **Copy connector config**.
3. **Give the block to the agent**: URL `https://herald-relay.<your-subdomain>.workers.dev/mcp` and `Authorization: Bearer hrk_...`.
   - Claude Code: `claude mcp add --transport http herald https://herald-relay.<your-subdomain>.workers.dev/mcp --header "Authorization: Bearer hrk_..."`
   - Claude.ai custom connector / ChatGPT / any remote MCP client: URL and Bearer header.
   - Codex `~/.codex/config.toml`: `[mcp_servers.herald]`, `url = ".../mcp"`, `bearer_token_env_var = "HERALD_RELAY_KEY"`.
   - Plain HTTPS works too (below).
4. The agent's notifications arrive as the app **`cloud.<key name>`**: its own manifest, template, sound and icon (the real Claude or
   Codex icon for those keys), designable in the Designer like any issuer (Settings > Cloud > Design...). A connector's app is named with
   the client's own `client_name` (the app id keeps the key slug), and an app with no icon gets ChatGPT's, Claude's or Codex's icon when
   installed, else a cloud tile (static key: a key tile). Settings > Apps > Change icon... overrides it.

Scriptable: `herald-mcp` has `relay_status`, `relay_usage`, `list_connectors`, `create_agent_key(name, client?)`, `revoke_agent_key(id)`; the loopback API
has `/v1/relay/*` ([reference/api.md](reference/api.md#cloud-relay)).

## Connect ChatGPT (OAuth)

ChatGPT's connector flow signs in with OAuth and has no field for a custom API key, so the static `hrk_` key of the section above does not
work there. The relay is therefore also its own OAuth 2.1 authorization server, as the MCP authorization spec (2025-06-18) describes.
**Claude, Codex and any client that can send a header can use either way**: a static key (above), or OAuth (this section; Claude.ai
custom connectors support it too). Both land on the same `/mcp` and `/v1/notify` with the same notify-only scope and limits.

**Before you start**: Herald is paired and Online (Settings > Cloud), and Herald is running on the Mac you want to notify.

1. In ChatGPT open **Settings > Connectors** (the exact labels vary by plan and version; custom MCP connectors may need
   **Advanced > Developer mode**) and choose **Create** / **Add a custom connector**.
2. Name it `Herald`. **MCP server URL**: `https://herald-relay.<your-subdomain>.workers.dev/mcp`. **Authentication: OAuth**. Leave any client id
   and secret fields empty: ChatGPT registers itself with the relay (dynamic client registration). Create / Connect.
3. ChatGPT opens a Herald page in your browser: **"ChatGPT wants to connect to Herald"**, naming the scope (send notifications to your Mac,
   read receipts and your replies) and the address it returns to.
4. On the Mac a banner appears: **"Let ChatGPT send you notifications? Approve / Deny"**. It is the same inline strip Herald uses for other
   questions: it never takes focus from what you are typing. Press **Approve**. The browser page continues by itself and returns to ChatGPT.
   - Missed the banner, or Herald hides banners right now? Open **Settings > Cloud > Connector approvals**: the request is there with
     **Approve / Deny** and a **6-digit code**. Type the code on the browser page instead (five wrong tries deny the request).
   - **Deny** (banner, Settings or the page) sends ChatGPT back with `access_denied`; nothing is created.
5. Back in ChatGPT the connector is connected and lists four tools. Ask it to "send me a Herald notification saying hello". The banner
   arrives as the app `cloud.chatgpt`.

The approval created an agent key of kind **oauth** named after the connector (`chatgpt`). It shows in **Settings > Cloud > Agent keys**
and under **Connector approvals**, and `list_connectors` (local MCP) / `GET /v1/relay/connectors` list it.

**Revoke**: Settings > Cloud > Connector approvals (or Agent keys) > **Revoke**. The key's access and refresh tokens stop working at once
(the next ChatGPT call gets 401 and has to be authorized again); `revoke_agent_key` does the same from the local MCP. A connector can also
revoke itself (`POST /revoke`, RFC 7009).

### What a connector can and cannot do

- **Can**: send notifications (text and presentation fields), read receipts for what it sent, wait for your reply, ask whether the Mac is online. Exactly
  the four tools above, within the same limits as a static key (60 notifications per 10 minutes, 2,000 a day, 32 KB).
- **Cannot**: run commands, scripts or Shortcuts, set callbacks, add buttons, show images or play audio, read your history, see other
  keys' notifications, change settings or quiet hours, create or revoke keys, approve anything for itself. `/v1/device/*` answers an OAuth
  token with 403. Mute and quiet hours are still enforced on the Mac.
- **Approval is yours, on the Mac**: a request cannot be approved from the web page alone. It needs the banner (or Settings) on the paired
  Mac, or the 6-digit code that only Herald shows. An approval request is shown only for clients that registered with this relay, with
  the name they chose and the host they return to, so a look-alike name still shows its real address; at most 3 requests wait at once and
  12 an hour.
- Tokens: opaque, stored only as SHA-256 hashes in the mailbox. Access token 1 hour, refresh token 30 days and **rotating** (each refresh
  returns a new pair; using an old refresh token again burns the whole family). Authorization codes live 5 minutes after approval, work
  once, require PKCE (S256), and a code used twice revokes what it produced. Tokens are bound to the `/mcp` resource (RFC 8707) and to
  their client. Re-authorizing the same connector replaces its earlier key.
- Setting up your own relay changes nothing: the URLs above come from the host the connector was added with.

### Endpoints (all on the relay's origin)

| Endpoint | Purpose |
|---|---|
| `GET /.well-known/oauth-protected-resource` (also `.../mcp`) | RFC 9728: `resource` = the `/mcp` URL, `authorization_servers` = the relay, `scopes_supported` = `["notify"]`. |
| `GET /.well-known/oauth-authorization-server` | RFC 8414 metadata (also served as `openid-configuration`): endpoints (including `device_authorization_endpoint`), `S256` only, grants `authorization_code`, `refresh_token` and `urn:ietf:params:oauth:grant-type:device_code`. |
| `POST /mcp` without credentials | `401` with `WWW-Authenticate: Bearer resource_metadata="<origin>/.well-known/oauth-protected-resource"`. |
| `POST /register` | RFC 7591. `redirect_uris` (not needed when `grant_types` is only the device grant; https, loopback http or a private-use scheme; no fragments), `client_name`. Public by default (`token_endpoint_auth_method: none`); `client_secret_post` / `client_secret_basic` return a secret. 30 registrations an hour. |
| `GET /authorize` | `response_type=code`, `client_id`, exact `redirect_uri`, `state`, `code_challenge` + `code_challenge_method=S256` (required), optional `resource` (must be the `/mcp` URL) and `scope` (`notify`). Serves the consent page. Unknown client or redirect: an error page, never a redirect. |
| `GET /authorize/status?rid=` | Polled by the consent page; returns the redirect once decided. |
| `POST /authorize/code`, `POST /authorize/deny` | The page's 6-digit-code form and Deny button. |
| `POST /device_authorization` | RFC 8628: `client_id`, optional `scope` (`notify`) and `device`. Returns `device_code`, `user_code` (`BDFG-HJKM`), `verification_uri` (`/activate`), `verification_uri_complete`, `expires_in: 600`, `interval: 5`, and which Mac gets the banner: `device_name`, `device_count`, `device_index`, `device_online`. See [No browser?](#no-browser-use-the-device-flow). |
| `GET /activate`, `POST /activate`, `/activate/approve`, `/activate/deny` | The optional page for a person: user code, then the Mac's 6-digit approval code. |
| `GET /` | A small plain page: what this is, links to the `.well-known` documents and `/activate`. (`/health` is the JSON check.) |
| `POST /token` | `authorization_code` (+ `code_verifier`, `redirect_uri`, `resource`), `refresh_token`, and `urn:ietf:params:oauth:grant-type:device_code` (+ `device_code`). Returns `access_token`, `refresh_token`, `expires_in: 3600`, `scope: notify`. |
| `POST /revoke` | RFC 7009. |
| `GET /v1/device/consents`, `POST /v1/device/consent` | Device token only: Herald lists pending requests and answers `{id, decision: "approve"\|"deny"}`. The stream also carries `consent` and `consent_resolved` messages. |

With several Macs paired to one relay (see [Several Macs](#several-macs)) the consent page names the Mac the approval goes to and links the
others; `device=<n>` (1-based, in pairing order) chooses explicitly.

A connector asks once: the same client asking again (a retry, a second `POST /device_authorization`) replaces its open request instead of
adding a banner (one open request per client and Mac; the old `device_code` stops working and the banner is updated in place with the new
code). A request is a banner once; after a reconnect the relay re-sends it flagged `redelivered: true` and Herald only refreshes
Settings > Connector approvals. An unanswered request is removed from the mailbox after 10 minutes (the relay tells Herald, which drops the
banner and the list entry), and approving or denying one removes it everywhere, including the same client's open request on another Mac.
Deny only closes that request; keys that already work are untouched.

## No browser? Use the device flow

Some cloud agents (OpenAI's sandbox, CI jobs, anything headless) cannot open the browser consent page; their browser reports
`net::ERR_BLOCKED_BY_CLIENT` and no consent screen ever opens. For them the relay speaks the OAuth 2.0 Device Authorization Grant
(RFC 8628). The approval is still yours, on the Mac; the agent only prints a code.

The exact sequence for the agent (replace `$RELAY` with the relay's origin, `https://herald-relay.<your-subdomain>.workers.dev`; send a
custom `User-Agent`, see Troubleshooting):

```sh
# 1. Register once (no redirect_uris needed for a device-only client). Keep client_id.
curl -s $RELAY/register -H 'content-type: application/json' \
  -d '{"client_name":"My cloud agent","grant_types":["urn:ietf:params:oauth:grant-type:device_code"]}'
# 2. Ask for a device code.
curl -s $RELAY/device_authorization -d client_id=hc_... -d scope=notify
#    -> {"device_code":"hrv_...","user_code":"BDFG-HJKM","verification_uri":"$RELAY/activate",
#        "verification_uri_complete":"$RELAY/activate?user_code=BDFG-HJKM","expires_in":600,"interval":5}
# 3. TELL THE USER: "Approve my Herald request. The code is BDFG-HJKM." (Herald shows a banner and lists it in
#    Settings > Cloud > Connector approvals; they press Approve if the code matches.)
# 4. Poll every `interval` seconds until it stops answering authorization_pending.
curl -s $RELAY/token -d grant_type=urn:ietf:params:oauth:grant-type:device_code -d client_id=hc_... -d device_code=hrv_...
#    -> {"access_token":"hra_...","refresh_token":"hrr_...","expires_in":3600,"scope":"notify","token_type":"Bearer"}
# 5. Use it: POST $RELAY/mcp with  Authorization: Bearer hra_...   (refresh with grant_type=refresh_token before it expires)
```

What `/token` answers while you wait (RFC 8628 section 3.5, HTTP 400 with `{"error": ...}`): `authorization_pending` (keep polling),
`slow_down` (you polled faster than `interval`; the interval grows by 5 seconds, add it to yours), `access_denied` (the user pressed Deny:
stop), `expired_token` (10 minutes passed: start again at step 2). On approval you get the same tokens as the browser flow and the same
**oauth** agent key named after `client_name`, notify-only, revocable in Settings > Cloud.

On the Mac the request arrives the moment step 2 returns: the banner says **"Approve <client> to send you notifications? Code BDFG-HJKM"**
with Approve and Deny, and Settings > Cloud > Connector approvals lists it with the code in large type (match it with what the agent
printed) and, small, the 6-digit approval code for the web page. A request nobody answers expires after 10 minutes; at most 3 wait at
once and 12 an hour. With several Macs paired, `device=<n>` (1-based) on step 2 picks the Mac; without it the relay targets the Mac that is
**connected right now** (else the one seen most recently, never simply the first entry) and the reply says which: `device_name`,
`device_count`, `device_index` and `device_online`. Tell the user which Mac will show the banner. Repeating step 2 replaces the open request.

`/activate` is an optional page for a person with a browser: enter the agent's code, then the 6-digit approval code Herald shows (the
user code alone is not enough, because the agent knows it), then Approve or Deny. The root `/` is a small information page, not a 404.

## What the agent can do

Remote MCP at `/mcp` (Streamable HTTP, protocol 2025-06-18, one JSON response per POST, no sessions). Exactly four tools:

| Tool | Does |
|---|---|
| `send_notification` | `title` (required), `body`, `subtitle`, `status`, `project`, `session`, `task`, `tool`, `duration`, `link` (https), `group`, `priority` (`low`/`normal`/`high`/`urgent`), the presentation fields below, `notificationId`, `expectReply`, `allowVoiceReply`. |
| `get_receipt` | `{received, displayed, spoken, replied, reply?, suppressed, reason?}` with timestamps. |
| `wait_for_reply` | Long-poll up to 55 s for the user's answer: `{replied, text?, transcript?, audioUrl?, durationSeconds?, repliedAt}` or `{replied:false, timedOut:true}`. |
| `herald_status` | `{online, lastSeenAt, quietHours:{active, until?}}`. Nothing else about the Mac. |

Plain HTTPS with the same Bearer key: `POST /v1/notify`, `GET /v1/receipts/{notificationId}`, `GET /v1/replies/{notificationId}?wait=sec`
(long-poll, at most 60 s), `GET /v1/status`.

### Presentation fields

Besides the text, a cloud notification may set how it looks and sounds. All optional, none of them can run or open anything:

| Field | Effect |
|---|---|
| `persistent` | Default **true**: the banner stays until you dismiss it. `false` gives Herald's own timeout. |
| `timeoutSeconds` | 1 to 3600: the banner dismisses itself after that long (hover pauses). Ignored when `persistent` is true. |
| `sound` | A system sound name (`Glass`), `default` (the sender's own) or `none`. Never a path. |
| `speak` | `true` (title, then body), a string (that text) or `{text, voice, speed, lang}`. |
| `voice`, `speed` | Voice name (`af_heart`) and 0.5 to 2, beside `speak`; either alone turns speaking on. |
| `presentation` | `banner` (default), `voice` (speech only, no banner; implies `speak`) or `both` (implies `speak`). |
| `priority` | `low`, `normal`, `high`, `urgent` (urgent breaks quiet hours only if you allowed it). |
| `group` | Notifications with the same group stack into one banner. |
| `subtitle` | A second line. |
| `icon` | The sender's icon for this key: an https image URL or a `data:image/png\|jpeg\|gif\|webp;base64,...` image up to 256 KB. Your own icon (Settings) wins. |
| `imageURL` | An https preview image. |
| `tags` | Up to 10 short labels, stored with the notification for templates and search. |

`expectReply: true` **only adds the Reply and Record buttons** (the banner is already persistent by default). It does not change the title,
the status badge, the template or the presentation; use `status` yourself if you want a badge.

A spoken banner that stays until dismissed:

```json
{"title":"Build finished","body":"All 214 tests passed.","speak":true,"persistent":true}
```

Quiet hours and mute still apply on the Mac: speech held back by quiet hours leaves the banner showing (and the receipt says `suppressed`
with `reason`, scope `speech`).

### Receipts

Separate facts, set by whoever knows them:

| Receipt | Set by | Meaning |
|---|---|---|
| `received` | relay, on enqueue | The relay has it (`queued: true` while the Mac has not taken it). |
| `displayed` | Herald, when the banner is up | The notification was shown. |
| `spoken` | Herald, when speech finishes | Speech played to the end (not when it was muted, cut off or never asked for). |
| `replied` | Herald | The user answered; `reply`/`text`, or `transcript` and `audioUrl`. |
| `suppressed` + `reason` | Herald | Held back by the user's settings: `muted`, `quiet-hours` (scope `all`), or `quiet-hours` with scope `speech` (banner shown, speech held), `expired` (24 h in the queue), `delivery-failed`. A suppressed notification is not shown, played or spoken. |

Mute and quiet hours are enforced **on the Mac**, in Herald, with the user's real settings; the relay only learns "quiet hours on/off" so
`herald_status` can say so. `priority: urgent` breaks quiet hours only when the user allowed it for that app.

### Idempotency and limits

- `notificationId` (yours; generated when omitted) is deduplicated for 24 hours per key: sending it again returns the first notification's
  receipt with `duplicate: true` and never produces a second banner. Herald dedupes again by the relay's delivery id (persisted 24 h), so a
  reconnect or a restart cannot show one twice.
- Body at most 32 KB (413), 60 notifications per 10 minutes per key (429 + `Retry-After`), 2,000 notifications per day, 200 undelivered per
  Mac (429 `queue_full`), queue kept 24 hours while the Mac is offline.
- **No** `command`, `commands`, `script`, `shortcut`, `callback`, `buttons`, `actions`, `url`, `image`, `audio`, `template`, `app`, ... : the
  schema is a whitelist and anything else is rejected with `400 forbidden_fields` listing the keys.

## Replying to the agent

Every cloud banner has **Reply** (text) and **Record** (voice); `allowVoiceReply: false` hides Record, `expectReply: true` only
adds those two buttons (banners stay until dismissed anyway; the notification is not turned into a question).

- **Reply**: the inline field; the text goes to the relay, `wait_for_reply` / `GET /v1/replies/{id}` return it and the receipt flips to
  `replied`. History keeps it.
- **Record**: pressing it opens an inline strip (red dot, elapsed time, Stop / Send / Cancel; 60 s maximum). Nothing records until you
  press Record. The first use asks for the microphone. Audio is AAC m4a, mono, 32 kbps (about 240 KB a minute), **transcribed on this
  Mac** with `SFSpeechRecognizer(requiresOnDeviceRecognition = true)`; with no on-device model, no transcript is made and the agent gets
  the audio alone. Herald uploads the m4a (`PUT /v1/device/reply/{id}/audio`, at most 1 MB) to R2 (bucket `herald-relay-audio`, deleted
  after 7 days) and then the reply with the transcript. The agent receives `transcript` (the tool says it is on-device and may be imperfect),
  `durationSeconds` and `audioUrl`, a signed link valid for one hour (HMAC over key and expiry; no other credential). History keeps the
  local m4a and the transcript. The banner never takes focus except while you click into the Reply field.

## Security model

- **Outbound only.** Herald opens the WebSocket; the Mac has no listener for the relay and the loopback API stays on 127.0.0.1.
- **Device token** (`hrd_...`): minted at pairing, stored in Herald's secret store (data-protection keychain, else a 0600 file; see above), sent as a Bearer on the WebSocket and the
  device calls. The relay stores a SHA-256 hash.
- **Agent keys** (`hrk_<deviceId>_<keyId>_<secret>`): minted only with the device token; scope `notify` is the only scope that exists
  (anything else is a 400); stored as SHA-256 hashes in the mailbox; compared in constant time; revocable instantly; a key routes to its own
  device only (the device id is inside the key, signed with a relay secret, and the mailbox re-checks the hash). A key sees only
  notifications sent with that key.
- **OAuth connectors** (below) get the same notify-only access through short-lived tokens bound to their own `oauth` key; revoking the key
  revokes them. A connector is approved on the Mac, never by the web page alone.
- **No admin surface for agent keys.** `/v1/device/*` (keys, receipts, usage, unpair, the stream) rejects agent keys with 403 and the
  device token is rejected on agent endpoints. There is no endpoint to change permissions, settings, quiet hours or anything on the Mac.
- **Text and presentation only, twice.** The relay accepts a whitelist of fields; Herald rebuilds the notification from a whitelist again
  (`RelayPolicy`), so even a hostile relay cannot make Herald run a command, open a callback or play a file. `sound` is a name, never a
  path. The only things Herald fetches are the https `icon` and `imageURL` the sender names, decoded as images and size-capped. Links
  must be https and open only when you press Open link.
- **Pairing**: one-time codes (10 minutes, single use, rate limited), at most `MAX_DEVICES` Macs (5). The first pairing is
  trust-on-first-use: pair soon after deploying, or set `wrangler secret put PAIRING_SECRET` and the relay then demands it
  (`X-Pairing-Secret`) on `POST /v1/pair/start`.
- **What the relay can read**: notification text and replies pass through it and sit in the mailbox up to 24 hours (audio 7 days). Use your
  own relay (`wrangler deploy` from `relay/`) if that matters; Settings > Cloud takes any URL.
- **Revoke**: Revoke a key in Settings > Cloud; Unpair wipes the mailbox (queue, keys, audio) and forgets the token.

## Free plan budget and per-device limits

The relay is built to live on Cloudflare's free plan (limits checked on developers.cloudflare.com on 2026-10-02). Every paired Mac has its
own mailbox, so **every cap is per device, never global**: one noisy Mac or key cannot use up another Mac's allowance, and a relay shared
by several Macs divides the plan between them. The defaults (Worker vars; Advanced edits them) are sized so about **20 devices can each
hit every cap on the same day** without exceeding the free plan, and a normal Mac uses about 1% of its caps.

| Cap (per device) | Default | Worker var | When reached |
|---|---|---|---|
| Notifications per day | 500 | `DEVICE_NOTIFICATIONS_PER_DAY` | 429 `daily_cap` until midnight UTC |
| Undelivered waiting for the Mac | 100 | `DEVICE_QUEUE_MAX` | 429 `queue_full` |
| Requests that reach the mailbox per day | 5,000 | `DEVICE_REQUESTS_PER_DAY` | 503 `budget_exhausted` until midnight UTC (the Mac can still connect and drain its queue) |
| Voice replies per day / bytes per day | 40 / 20 MB | `DEVICE_AUDIO_UPLOADS_PER_DAY`, `DEVICE_AUDIO_BYTES_PER_DAY` | 429 `daily_cap` |
| Long-poll seconds per day | 3,000 | `DEVICE_POLL_SECONDS_PER_DAY` | polls stop waiting (answer at once) |
| Undelivered kept | 24 h | `QUEUE_TTL_HOURS` | `suppressed` receipt `expired` |
| Notifications per 10 min per key | 60 | `RATE_LIMIT_PER_KEY` | 429 + `Retry-After` |
| Largest notify request | 32 KB | `MAX_BODY_BYTES` | 413 |
| Receipt/reply reads per 10 min per key | 600 | (fixed) | 429 |
| Macs that may pair | 5 | `MAX_DEVICES` | 403 `device_limit` |

**Pairing limits are per client address**: 6 pairing starts an hour (`PAIR_STARTS_PER_HOUR`) and 10 wrong codes per 10 minutes per address
(stored hashed), at most 3 codes waiting per address, and flood guards of 300 starts an hour and 60 waiting codes across all addresses.
One address cannot lock the others out. With a pairing secret set (Herald sets one) a stranger cannot even start.

| Resource | Free plan limit | What the relay does |
|---|---|---|
| Workers requests | 100,000 / day, 10 ms CPU each | Auth is a hash and an HMAC (about 1 ms); routing only. Each device is capped at 5,000 mailbox requests a day; unauthenticated junk is rejected in the Worker. |
| Durable Object requests | 100,000 / day (WebSocket messages count 20:1) | Herald sends only `hello`, `ack`, receipts and a status change: about 3 messages per notification = 0.15 requests. |
| DO duration | 13,000 GB-s / day | WebSocket Hibernation: Herald's idle socket does not keep the object awake; keepalive is answered without waking it. Long-polls keep it awake (7.5 GB-s per full minute), capped per device. |
| DO SQLite rows written | 100,000 / day | About 10 per notification; counters are kept in memory and written once a minute. |
| DO storage | 5 GB | Notifications are deleted after 25 hours; an empty mailbox is about 12 KB. |
| R2 storage | 10 GB-month | Voice replies only, at most 1 MB each and 20 MB a day per device, deleted after 7 days by the bucket's lifecycle rule (Herald creates it). |
| KV, Queues, Cron | not used | No cron triggers; no polling from Herald (only the socket). |

**Worst case for N devices** (every device at every cap): rows written 500 x 10 = 5,000 per device a day, so **20 devices fill the 100,000
rows** and the 5,000-request cap fills the 100,000 requests at 20 as well. Beyond that Cloudflare itself answers 429/1027 (Herald shows
*Relay offline - limit reached* and retries) or you move to Workers Paid. **Typical**: a few dozen notifications a day is 100-200
requests and 300 rows per device, so a free account serves several hundred such devices; the per-device caps are what protect them from
each other.

**When a limit is hit**: agents get `429` (rate, daily cap, queue full) or `503` with `Retry-After`; Herald shows
**"Relay offline - limit reached"** in Settings > Cloud and retries with backoff (at least the `Retry-After`). Nothing is lost silently: the
queue is stored in the Mac's mailbox, items are delivered when the Mac reconnects, and an item older than the queue TTL gets a `suppressed`
receipt with reason `expired`.

**See it**: Settings > Cloud > **Usage today** (requests, notifications, queued, storage), `relay_usage` in the local MCP,
`GET /v1/relay/usage`, or `GET /v1/device/usage` on the relay with the device token (it includes this device's `limits`).

## Operating the relay

```sh
cd relay
npm install
npm test                       # vitest + miniflare
wrangler secret put RELAY_SECRET   # once: any 32+ random bytes, signs device ids
npm run r2:setup               # once: the audio bucket and its 7-day lifecycle rule
npm run deploy                 # wrangler deploy -> https://herald-relay.<account>.workers.dev
wrangler dev                   # local: needs relay/.dev.vars with RELAY_SECRET=...
```

Device endpoints (device token only): `GET /v1/device/stream` (WebSocket), `POST /v1/device/receipt`, `POST /v1/device/reply`,
`PUT /v1/device/reply/{id}/audio`, `POST /v1/device/status`, `GET /v1/device/info`, `GET /v1/device/usage`, `GET|POST /v1/device/keys`,
`DELETE /v1/device/keys/{id}`, `GET /v1/device/consents`, `POST /v1/device/consent`, `DELETE /v1/device`. Public: `POST /v1/pair/start`,
`POST /v1/pair`, `GET /healthz`, `GET /v1/audio/...` (signed), and the OAuth routes (`/.well-known/*`, `/register`, `/authorize`, `/token`,
`/revoke`).

## Troubleshooting

| Symptom | Cause |
|---|---|
| A cloud agent gets 403 / Error 1010 on the workers.dev address | Cloudflare's Browser Integrity Check blocks it on workers.dev. Set up a [custom domain](#custom-domain-optional). |
| A connector request never reaches this Mac, or goes to the wrong one | An old entry for this Mac was first in the relay's list (a reinstall, a redeploy that changed the secrets). Current relays pick the connected Mac and prune stale entries; see [Several Macs](#several-macs). Redeploy to get that, then check Advanced > Devices on this relay. |
| Settings shows "Offline" and keeps retrying | No network; Herald retries 1 s, 2 s, 4 s ... up to 5 minutes and at once on wake or when the network returns. |
| "the relay rejected this Mac's token" | The pairing was removed (Unpair) or the relay was reset. Pair again. |
| The agent gets 401 | The key was revoked or belongs to another relay; check Settings > Cloud. For a ChatGPT connector: it was revoked, or its refresh token was used twice; connect it again. |
| ChatGPT's page says "Pair Herald first" | The relay has no paired Mac. Pair in Settings > Cloud, then connect again. |
| The consent page waits and no banner shows | Herald is not running or not Online; or quiet hours / mute hid the banner. Use the 6-digit code from Settings > Cloud > Connector approvals. |
| "approvals are already waiting" | Three requests are open; answer or deny them in Settings > Cloud (they expire after 10 minutes). |
| `receipt.suppressed` with `muted` / `quiet-hours` | Working as designed; the user's settings win. |
| `Relay offline - limit reached` | A free-plan limit (see above); it clears at midnight UTC. |
