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
| Cloudflare API token | macOS Keychain (`com.ivg.herald.cloudflare`), this device only. Sent only to `api.cloudflare.com`. Never shown again, never returned by the local API or MCP. *Forget the token* (Advanced) deletes it. |
| Pairing secret (made at the first deploy) | Keychain; also a secret on the Worker. The relay demands it (`X-Pairing-Secret`) when a Mac pairs, so a stranger who finds the URL cannot pair. Shown under Advanced. |
| Relay signing secret (`RELAY_SECRET`, made at the first deploy) | Keychain and a Worker secret; signs device ids. Kept so a deploy from scratch is possible. |
| Device token (`hrd_...`) | Keychain (see below). |
| Account id, worker name, subdomain, bucket, limits, deployed bundle hash | `relay-cloudflare.json` in Herald's support folder (no secrets). |

### Upgrade, redeploy, delete

- **Upgrade**: Deploy again (the *Update the relay* button, or `relay_deploy`). The Worker is uploaded with the same bindings, the Durable
  Object classes are not migrated again and the existing secrets are kept.
- **Change a setting** (Advanced): a value that lives in the Worker (limits, retention, worker name, bucket) redeploys it; the rest is Herald's.
- **Delete relay from Cloudflare** (Advanced, with a confirmation): deletes the Worker with every mailbox, key and queued notification,
  and the bucket when it is empty (Cloudflare refuses to delete a bucket that still holds voice replies; Herald says so).

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
   Codex icon for those keys), designable in the Designer like any issuer (Settings > Cloud > Design...).

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

- **Can**: send notifications (text only), read receipts for what it sent, wait for your reply, ask whether the Mac is online. Exactly
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
| `GET /.well-known/oauth-authorization-server` | RFC 8414 metadata (also served as `openid-configuration`): endpoints, `S256` only, grants `authorization_code` and `refresh_token`. |
| `POST /mcp` without credentials | `401` with `WWW-Authenticate: Bearer resource_metadata="<origin>/.well-known/oauth-protected-resource"`. |
| `POST /register` | RFC 7591. `redirect_uris` (https, loopback http or a private-use scheme; no fragments), `client_name`. Public by default (`token_endpoint_auth_method: none`); `client_secret_post` / `client_secret_basic` return a secret. 30 registrations an hour. |
| `GET /authorize` | `response_type=code`, `client_id`, exact `redirect_uri`, `state`, `code_challenge` + `code_challenge_method=S256` (required), optional `resource` (must be the `/mcp` URL) and `scope` (`notify`). Serves the consent page. Unknown client or redirect: an error page, never a redirect. |
| `GET /authorize/status?rid=` | Polled by the consent page; returns the redirect once decided. |
| `POST /authorize/code`, `POST /authorize/deny` | The page's 6-digit-code form and Deny button. |
| `POST /token` | `authorization_code` (+ `code_verifier`, `redirect_uri`, `resource`) and `refresh_token`. Returns `access_token`, `refresh_token`, `expires_in: 3600`, `scope: notify`. |
| `POST /revoke` | RFC 7009. |
| `GET /v1/device/consents`, `POST /v1/device/consent` | Device token only: Herald lists pending requests and answers `{id, decision: "approve"|"deny"}`. The stream also carries `consent` and `consent_resolved` messages. |

With several Macs paired to one relay the consent page first asks which Mac the connector should notify.

## What the agent can do

Remote MCP at `/mcp` (Streamable HTTP, protocol 2025-06-18, one JSON response per POST, no sessions). Exactly four tools:

| Tool | Does |
|---|---|
| `send_notification` | `title` (required), `body`, `subtitle`, `status`, `project`, `session`, `task`, `tool`, `duration`, `link` (https), `group`, `priority` (`normal`/`urgent`), `speak` (`true` or `{text, voice, speed, lang}`), `notificationId`, `expectReply`, `allowVoiceReply`. |
| `get_receipt` | `{received, displayed, spoken, replied, reply?, suppressed, reason?}` with timestamps. |
| `wait_for_reply` | Long-poll up to 55 s for the user's answer: `{replied, text?, transcript?, audioUrl?, durationSeconds?, repliedAt}` or `{replied:false, timedOut:true}`. |
| `herald_status` | `{online, lastSeenAt, quietHours:{active, until?}}`. Nothing else about the Mac. |

Plain HTTPS with the same Bearer key: `POST /v1/notify`, `GET /v1/receipts/{notificationId}`, `GET /v1/replies/{notificationId}?wait=sec`
(long-poll, at most 60 s), `GET /v1/status`.

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

Every cloud banner has **Reply** (text) and **Record** (voice); `allowVoiceReply: false` hides Record, `expectReply: true` keeps the banner
up until answered and marks it as a question.

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
- **Device token** (`hrd_...`): minted at pairing, stored in the macOS Keychain (this device only), sent as a Bearer on the WebSocket and the
  device calls. The relay stores a SHA-256 hash.
- **Agent keys** (`hrk_<deviceId>_<keyId>_<secret>`): minted only with the device token; scope `notify` is the only scope that exists
  (anything else is a 400); stored as SHA-256 hashes in the mailbox; compared in constant time; revocable instantly; a key routes to its own
  device only (the device id is inside the key, signed with a relay secret, and the mailbox re-checks the hash). A key sees only
  notifications sent with that key.
- **OAuth connectors** (below) get the same notify-only access through short-lived tokens bound to their own `oauth` key; revoking the key
  revokes them. A connector is approved on the Mac, never by the web page alone.
- **No admin surface for agent keys.** `/v1/device/*` (keys, receipts, usage, unpair, the stream) rejects agent keys with 403 and the
  device token is rejected on agent endpoints. There is no endpoint to change permissions, settings, quiet hours or anything on the Mac.
- **Text only, twice.** The relay accepts a whitelist of fields; Herald rebuilds the notification from a whitelist again (`RelayPolicy`), so
  even a hostile relay cannot make Herald run a command, open a callback, play a file or fetch an image. Links must be https and open only
  when you press Open link.
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
| Settings shows "Offline" and keeps retrying | No network; Herald retries 1 s, 2 s, 4 s ... up to 5 minutes and at once on wake or when the network returns. |
| "the relay rejected this Mac's token" | The pairing was removed (Unpair) or the relay was reset. Pair again. |
| The agent gets 401 | The key was revoked or belongs to another relay; check Settings > Cloud. For a ChatGPT connector: it was revoked, or its refresh token was used twice; connect it again. |
| ChatGPT's page says "Pair Herald first" | The relay has no paired Mac. Pair in Settings > Cloud, then connect again. |
| The consent page waits and no banner shows | Herald is not running or not Online; or quiet hours / mute hid the banner. Use the 6-digit code from Settings > Cloud > Connector approvals. |
| "approvals are already waiting" | Three requests are open; answer or deny them in Settings > Cloud (they expire after 10 minutes). |
| `receipt.suppressed` with `muted` / `quiet-hours` | Working as designed; the user's settings win. |
| `Relay offline - limit reached` | A free-plan limit (see above); it clears at midnight UTC. |
