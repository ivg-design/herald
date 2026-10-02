# Cloud relay: notifications from an agent running in the cloud

A cloud agent (Claude, Codex, anything that speaks remote MCP or HTTPS) cannot reach your Mac, and you do not want it to.
The relay is a small Cloudflare Worker that holds a mailbox for your Mac. The agent puts notifications in; Herald, which
keeps one **outbound** WebSocket open to the relay, takes them out and shows them through its normal path. There is no inbound
port on the Mac and the agent never talks to Herald directly.

```
cloud agent --HTTPS or remote MCP (agent key)--> relay (Worker + Durable Object "mailbox") <--WebSocket, outbound-- Herald
                                                         receipts and replies flow back the same way
```

Deployed relay: **https://herald-relay.ivg-design.workers.dev** (account: ivg-design, workers.dev subdomain, no custom domain).
Source: `relay/`. Herald's side: `Sources/Herald/Relay/`. Settings > Cloud.

## Connect a cloud agent

1. **Pair this Mac** (once): Herald > Settings > Cloud > **Pair...** The relay hands out a one-time code (shown in Settings,
   valid 10 minutes), Herald redeems it and stores the device token in the Keychain. Status turns to Online.
2. **Create an agent key**: Settings > Cloud > Agent keys > name (for example `build-bot`), Agent (Claude, Codex or Other) > **Create key**.
   The key and a ready-to-paste connector block are shown **once** (the relay keeps only a hash). **Copy connector config**.
3. **Give the block to the agent**: URL `https://herald-relay.ivg-design.workers.dev/mcp` and `Authorization: Bearer hrk_...`.
   - Claude Code: `claude mcp add --transport http herald https://herald-relay.ivg-design.workers.dev/mcp --header "Authorization: Bearer hrk_..."`
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
2. Name it `Herald`. **MCP server URL**: `https://herald-relay.ivg-design.workers.dev/mcp`. **Authentication: OAuth**. Leave any client id
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

## Free plan budget

The relay is built to live on Cloudflare's free plan (limits checked on developers.cloudflare.com on 2026-10-02).

| Resource | Free plan limit | What Herald's relay does |
|---|---|---|
| Workers requests | 100,000 / day, 10 ms CPU each | Auth is a hash and an HMAC (about 1 ms); no work is done in the Worker beyond routing. |
| Durable Object requests | 100,000 / day (WebSocket messages in count 20:1) | Herald sends only `hello`, `ack`, receipts and a status change: about 3 messages per notification = 0.15 requests. |
| DO duration | 13,000 GB-s / day | The WebSocket Hibernation API: Herald's idle socket does not keep the object awake. Keepalive is `setWebSocketAutoResponse("ping" -> "pong")`, answered without waking it, every 5 minutes. Long-polls keep it awake while they wait (7.5 GB-s per full minute), so waiting is capped at 6,000 s a day. |
| DO SQLite rows written | 100,000 / day | About 10 per notification; counters are kept in memory and written once a minute; read rate limits are in memory. |
| DO SQLite rows read | 5,000,000 / day | Queue scans are over at most 200 rows. |
| DO storage | 5 GB | Notifications are deleted after 25 hours; an empty mailbox is about 12 KB. |
| R2 storage | 10 GB-month | Voice replies only, at most 1 MB each, at most 200 a day, deleted after 7 days by a bucket lifecycle rule (`relay/r2-lifecycle.json`, `npm run r2:setup`). |
| R2 Class A / Class B | 1,000,000 / 10,000,000 a month | One put per voice reply, one get per download. |
| KV, Queues, Cron | not used | No cron triggers; no polling from Herald (only the socket). |

**One notification costs**: 1 Worker request + 1 Durable Object request to send, about the same for each receipt read or poll the agent makes
(say 3), 0.15 request for Herald's side, about 10 rows written, about 1 KB stored for 25 hours. A few dozen notifications a day is
about 100-200 requests (0.2% of the day), 1,000 rows written (1%), a few MB of storage.

**Worst case under the limits**: 20 keys at 60 per 10 minutes would be 172,800 a day, so a per-Mac daily cap of 2,000 notifications comes
first (about 20,000 rows written, 20% of the allowance), reads are limited to 600 per 10 minutes per key, and the relay answers `503`
(`budget_exhausted`, `Retry-After` until midnight UTC) once it has served 90,000 requests in a UTC day, ahead of Cloudflare's own 100,000.
Junk traffic to the public URL (not authenticated) is counted by Cloudflare against the 100,000 Workers requests; it is rejected in the
Worker for about 1 ms each.

**When a limit is hit**: agents get `429` (rate, daily cap, queue full) or `503` with `Retry-After`; Herald shows
**"Relay offline - limit reached"** in Settings > Cloud and retries with backoff (at least the `Retry-After`). Nothing is lost silently: the
queue is stored in the Mac's mailbox, items are delivered when the Mac reconnects, and an item older than 24 hours gets a `suppressed`
receipt with reason `expired`. If Cloudflare itself cuts the account off (error 1027 or 429 on the WebSocket) the same applies.

**See it**: Settings > Cloud > **Usage today** (requests, notifications, queued, storage), `relay_usage` in the local MCP,
`GET /v1/relay/usage`, or `GET /v1/device/usage` on the relay with the device token.

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
| Settings shows "Offline" and keeps retrying | No network; Herald retries 1 s, 2 s, 4 s ... up to 5 minutes and at once on wake or when the network returns. |
| "the relay rejected this Mac's token" | The pairing was removed (Unpair) or the relay was reset. Pair again. |
| The agent gets 401 | The key was revoked or belongs to another relay; check Settings > Cloud. For a ChatGPT connector: it was revoked, or its refresh token was used twice; connect it again. |
| ChatGPT's page says "Pair Herald first" | The relay has no paired Mac. Pair in Settings > Cloud, then connect again. |
| The consent page waits and no banner shows | Herald is not running or not Online; or quiet hours / mute hid the banner. Use the 6-digit code from Settings > Cloud > Connector approvals. |
| "approvals are already waiting" | Three requests are open; answer or deny them in Settings > Cloud (they expire after 10 minutes). |
| `receipt.suppressed` with `muted` / `quiet-hours` | Working as designed; the user's settings win. |
| `Relay offline - limit reached` | A free-plan limit (see above); it clears at midnight UTC. |
