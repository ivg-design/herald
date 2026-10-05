# Relay API

The relay is the small service in your Cloudflare account that sits between a cloud agent and your Mac. It
holds a mailbox for the Mac: an agent puts notifications in, Herald takes them out over one outgoing
connection, and receipts and replies travel back the same way. This page documents the API the relay itself
serves from its own address. Read it if you are writing a cloud agent or an integration that talks to the relay,
or if you operate or re-implement a relay.

Herald's own **local** API, with the `/v1/relay/*` routes that deploy and pair a relay from the Mac, is a
different thing and is documented in [Cloud relay API (local)](api/relay.md).

All examples use two variables. `$RELAY` is the relay's origin and `$KEY` is the credential an agent holds.

```sh
RELAY="https://herald-relay.example.workers.dev"
KEY="hrk_..."
```

`$KEY` is an agent key (`hrk_...`) or a connector access token (`hra_...`). Both are sent the same way, as
`Authorization: Bearer $KEY`.

## How the relay API is organised

A relay has three kinds of caller, and each one holds a different credential.

| Caller | Credential | What it may call |
|---|---|---|
| A cloud agent | An agent key (`hrk_...`) or a connector access token (`hra_...`). | [Agent endpoints](#agent-endpoints) and the [MCP endpoint](#mcp-endpoint). |
| Herald on a Mac | The device token (`hrd_...`), made when the Mac pairs. | The [`/v1/device/*` routes](#pairing-and-device-endpoints). |
| Anyone | None. | Discovery, OAuth, the health check, signed audio links and [pairing](#pairing-and-device-endpoints). |

The credentials cannot be swapped. An agent key or access token on a `/v1/device/*` route gets `403
wrong_credential`, and the device token on an agent route gets the same answer. An agent key can only send
notifications and read what it sent; it cannot change a setting, a quiet hour or anything else on the Mac.

The tokens are made of a prefix, the id of the Mac they belong to, and a secret. The relay checks the id's
signature before it touches any storage, so a guessed token never creates a mailbox.

| Token | Shape | Used as |
|---|---|---|
| Device token | `hrd_<deviceId>_<secret>` | The bearer credential of Herald on a paired Mac. |
| Agent key | `hrk_<deviceId>_<keyId>_<secret>` | The bearer credential of an agent you gave a key to. |
| Access token | `hra_<deviceId>_<secret>` | The bearer credential of an approved connector. |
| Refresh token, code, device code | `hrr_...`, `hrc_...`, `hrv_...` | Only sent to `/token` and `/revoke`. Never a bearer credential. |

The API is split into areas.

| Area | Routes | Credential |
|---|---|---|
| [Agent endpoints](#agent-endpoints) | `/v1/notify`, `/v1/receipts/*`, `/v1/replies/*`, `/v1/status`, `/health`, `/v1/audio/*` | Agent key or access token. `/health` and `/v1/audio/*` need none. |
| [MCP endpoint](#mcp-endpoint) | `/mcp` | Agent key or access token. |
| [OAuth endpoints](#oauth-endpoints) | `/.well-known/*`, `/register`, `/authorize`, `/device_authorization`, `/activate`, `/token`, `/revoke` | None. |
| [Pairing endpoints](#pairing-and-device-endpoints) | `/v1/pair/start`, `/v1/pair` | None, or the pairing secret. |
| [Device endpoints](#pairing-and-device-endpoints) | `/v1/device/*` | Device token. |

Every reply is JSON unless a block says otherwise. An error reply has this shape, and the optional fields
appear only where a block names them. The [error codes](#error-codes) table lists every code.

```json
{
  "error": "rate_limited",
  "message": "at most 60 notifications per 10 minutes per key",
  "retryAfterSeconds": 412
}
```

> [!NOTE]
> Send a custom `User-Agent` header with every request an agent makes. On a relay without a custom domain,
> Cloudflare's Browser Integrity Check rejects the default Python `urllib` agent before the request reaches the
> relay. Any other value works, so the examples send `Herald-Agent/1.0`. See
> [Cloud relay](../CLOUD.md) for the custom-domain alternative.

## Agent endpoints

These are the plain HTTPS routes an agent uses. Each one is also reachable as an [MCP tool](#mcp-endpoint), which
calls the same code.

| Endpoint | Purpose |
|---|---|
| [`POST /v1/notify`](#post-v1notify) | Queue a notification for the Mac. |
| [`GET /v1/receipts/{notificationId}`](#get-v1receiptsnotificationid) | Read what happened to a notification. |
| [`GET /v1/replies/{notificationId}`](#get-v1repliesnotificationid) | Read, or wait for, the user's reply. |
| [`GET /v1/status`](#get-v1status) | Ask whether the Mac is reachable. |
| [`GET /health`](#get-health) | Check that the relay is running. |
| [`GET /v1/audio/{deviceId}/{replyId}.m4a`](#get-v1audiodeviceidreplyidm4a) | Download a voice reply. |

An agent can only see notifications that its own key sent. Two keys, or a key and a connector, never see each
other's receipts.

### `POST /v1/notify`

Queues a notification for the user's Mac and returns its receipt. The relay stores it until Herald takes it,
which is at once when the Mac is online. Use it to tell the user something, and set `expectReply` when you want
an answer.

The body carries text and presentation only. The relay checks it against a whitelist: a field that is not in the
tables below is refused with `forbidden_fields`, so no command, button, callback, script, template or image path
can ride along. Herald checks the notification against a second whitelist when it receives it.

**Request**

All fields go in the JSON body. Only `title` is required. Text fields:

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `title` | body | string | yes | The headline, at most 200 characters. |
| `body` | body | string | no | The message text, at most 8000 characters. |
| `subtitle` | body | string | no | A second line under the title, at most 200 characters. |
| `status` | body | string | no | A short word shown as a badge, such as `done` or `error`. Letters, digits, `-` and `_`, at most 32 characters, stored in lower case. It is a label only. |
| `project` | body | string | no | The project name, at most 100 characters. |
| `session` | body | string | no | A session label, at most 100 characters. |
| `task` | body | string | no | A task label, at most 100 characters. |
| `tool` | body | string | no | The tool that produced the notification, at most 100 characters. |
| `duration` | body | string or number | no | How long the work took, for example `"2m 14s"`. A number is stored as its text. At most 40 characters. |
| `link` | body | string | no | An absolute `https` URL, at most 2048 characters. The banner offers it as an **Open link** button. |
| `notificationId` | body | string | no | Your own id: 1 to 128 characters from `A-Z a-z 0-9 . _ : -`. The relay generates one when you omit it. |
| `tags` | body | array of strings | no | Up to 10 labels of at most 32 characters, with no commas. Duplicates are removed. |

Presentation fields. None of them can run or open anything.

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `priority` | body | string | no | `low`, `normal`, `high` or `urgent`. `urgent` breaks quiet hours only where the user allowed it. |
| `group` | body | string | no | Notifications with the same group stack together. At most 100 characters. |
| `persistent` | body | boolean | no | `true` keeps the banner until the user dismisses it. When it is omitted Herald keeps the banner unless you set `timeoutSeconds`. |
| `timeoutSeconds` | body | number | no | From 1 to 3600. The banner dismisses itself after this many seconds. Herald ignores it when `persistent` is `true`. |
| `sound` | body | string | no | A system sound name such as `Glass`, `default` or `none`. Up to 40 characters from `A-Z a-z 0-9 space . _ -`. A file path is never accepted. |
| `presentation` | body | string | no | `banner`, `voice` or `both`. `voice` and `both` imply `speak: true`. |
| `icon` | body | string | no | The sender's icon: an `https` URL of at most 2048 characters, or a `data:image/png`, `jpeg`, `gif` or `webp` base64 image of at most 256 KB. |
| `imageURL` | body | string | no | An `https` URL of a preview image, at most 2048 characters. |

Speech fields. Herald speaks on the Mac, so these only choose what is said and how.

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `speak` | body | boolean, string or object | no | `true` speaks the title, then the body. A string of at most 2000 characters speaks that text. An object has `text`, `voice`, `speed` and `lang`. |
| `speak.voice` | body | string | no | A voice name such as `af_heart`: 1 to 40 letters, digits or `_`. |
| `speak.speed` | body | number | no | From 0.5 to 2. |
| `speak.lang` | body | string | no | A language code such as `en-us`. |
| `voice` | body | string | no | The same as `speak.voice`, beside `speak`. Setting it turns speaking on. |
| `speed` | body | number | no | The same as `speak.speed`, beside `speak`. Setting it turns speaking on. |

Reply fields:

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `expectReply` | body | boolean | no | `true` adds the **Reply** (text) and **Record** (voice) buttons. Nothing else about the banner changes. Default `false`. |
| `allowVoiceReply` | body | boolean | no | `false` hides the **Record** button on this notification. Default `true`. |

**Example request**

The `User-Agent` header avoids Cloudflare's browser check, as the note above explains.

```sh
curl -s -X POST "$RELAY/v1/notify" \
  -H "Authorization: Bearer $KEY" \
  -H "Content-Type: application/json" \
  -H "User-Agent: Herald-Agent/1.0" \
  -d '{
    "notificationId": "build-214",
    "title": "Build finished",
    "body": "All 214 tests passed.",
    "status": "done",
    "project": "web",
    "link": "https://example.com/builds/214",
    "speak": true,
    "expectReply": true
  }'
```

**Example response**

The reply is `202` for a new notification. It is the notification's [receipt](#the-receipt-object) plus a
`duplicate` flag.

```json
{
  "duplicate": false,
  "notificationId": "build-214",
  "received": true,
  "receivedAt": "2026-10-02T13:00:04.000Z",
  "queued": true,
  "displayed": false,
  "spoken": false,
  "replied": false,
  "expectReply": true,
  "suppressed": false
}
```

**Response fields**

| Field | Type | Description |
|---|---|---|
| `duplicate` | boolean | `true` when the same `notificationId` was already sent by this key in the last 24 hours. |
| `notificationId` | string | Your id, or the one the relay generated (`n_` and 24 hex characters). |
| other fields | various | The receipt fields described under [The receipt object](#the-receipt-object). |

**Errors**

| Status | When |
|---|---|
| `400` | The body is not a JSON object, `title` is missing, or a value is invalid. The reply has `error: "invalid_request"` and a `fields` list. |
| `400` | The body holds a field that is not accepted. The reply has `error: "forbidden_fields"`. |
| `401` | The key is missing, malformed, revoked or unknown. |
| `403` | The credential is the device token, or has no `notify` scope. |
| `413` | The body is larger than the request limit. |
| `429` | The key sent too many in 10 minutes (`rate_limited`), the Mac's daily cap is reached (`daily_cap`), or the Mac's queue is full (`queue_full`). |
| `503` | The Mac's daily request budget on the relay is used up (`budget_exhausted`). |

**Notes**

- A notification with a `notificationId` that this key already sent in the last 24 hours is not queued again.
  The relay answers `200` with the first notification's receipt and `duplicate: true`. This makes a retry safe.
- A request over 32 KB is refused with `413`. A `data:` icon is the one exception: it may add up to 256 KB to
  the body. Everything except the icon still has to fit in 32 KB.
- Speech turns on when any of these is set: `voice`, `speed`, or `presentation` with the value `voice` or `both`.
- `speak: false` removes only the speech that `presentation` implies. It does not cancel a `voice` or `speed` you also set.
- Quiet hours and mute are enforced on the Mac, not by the relay. Check the receipt to see whether a
  notification was held back.
- A request that sends `expectReply` does not change how the banner looks. Use `status` if you want a badge.
- `group` is applied by Herald on the Mac. The relay stores it and passes it on.

#### Forbidden fields

The relay accepts a fixed list of fields. A field outside that list makes the whole request fail: nothing is queued, and the error names every rejected field. Some names are called out in the error text because they would run or open something on the Mac. Use `link` for a URL and `imageURL` for a picture.

| Group | Names |
|---|---|
| Run something | `command`, `commands`, `cmd`, `script`, `scripts`, `shortcut`, `shortcuts`, `exec`, `run`. |
| Call or open something | `callback`, `callbacks`, `webhook`, `url`, `path`, `open`, `openApp`. |
| Buttons and actions | `buttons`, `actions`, `actionIds`, `action`, `reminder`, `snooze`. |
| Media | `audio`, `image`. |
| Template and identity | `template`, `templateName`, `layout`, `app`, `appId`, `metadata`, `accentColor`. |

```json
{
  "error": "forbidden_fields",
  "message": "rejected fields: buttons. Cloud notifications carry text and presentation only (buttons would run or open something on the Mac and is never accepted). Accepted fields: notificationId, title, subtitle, body, status, project, session, task, tool, duration, link, group, priority, speak, expectReply, allowVoiceReply, persistent, timeoutSeconds, sound, voice, speed, presentation, icon, imageURL, tags.",
  "fields": ["buttons"]
}
```

An unknown key inside a `speak` object is refused the same way, and is reported as `speak.<key>`.

### `GET /v1/receipts/{notificationId}`

Returns what has happened to a notification the key sent: whether the relay has it, whether the Mac showed it,
spoke it, got a reply, or held it back. Use it after sending to learn the outcome. To get the reply
itself, use [the replies endpoint](#get-v1repliesnotificationid), which can also wait for it.

**Request**

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `notificationId` | path | string | yes | The id you sent, or the one the relay returned. |

**Example request**

```sh
curl -s "$RELAY/v1/receipts/build-214" \
  -H "Authorization: Bearer $KEY" \
  -H "User-Agent: Herald-Agent/1.0"
```

**Example response**

```json
{
  "notificationId": "build-214",
  "received": true,
  "receivedAt": "2026-10-02T13:00:04.000Z",
  "queued": false,
  "displayed": true,
  "displayedAt": "2026-10-02T13:00:05.210Z",
  "spoken": true,
  "spokenAt": "2026-10-02T13:00:08.870Z",
  "replied": true,
  "repliedAt": "2026-10-02T13:02:41.402Z",
  "reply": "Ship it.",
  "text": "Ship it.",
  "expectReply": true,
  "suppressed": false
}
```

**Errors**

| Status | When |
|---|---|
| `401` | The key is missing, malformed, revoked or unknown. |
| `404` | This key sent no notification with that id in the last 24 hours. |
| `429` | The key made more than 600 receipt or reply reads in 10 minutes (`rate_limited`). |
| `503` | The Mac's daily request budget on the relay is used up (`budget_exhausted`). |

**Notes**

- Ids are kept for 24 hours. After that the receipt is gone and the same id can be sent again as a new
  notification.
- Reads are limited to 600 per 10 minutes per key, shared with `GET /v1/replies/{notificationId}`.

#### The receipt object

A receipt is a set of separate facts, each set by whoever knows it. `POST /v1/notify`, this endpoint and the
`get_receipt` MCP tool all return the same object.

| Receipt | Set by | Meaning |
|---|---|---|
| `received` | The relay, when it queues the notification. | The relay has it. It is always `true` in a reply. |
| `queued` | The relay. | `true` while the Mac has not yet taken the notification and it is not suppressed. |
| `displayed` | Herald, when the banner is up. | The notification was shown. |
| `spoken` | Herald, when speech finishes. | Speech played to the end. It stays `false` when speech was muted, cut off or never asked for. |
| `replied` | Herald, when the user answers. | The user answered with text or a voice message. |
| `suppressed` | Herald, or the relay on expiry. | The notification was held back. It was not shown, played or spoken, except for `speech` scope. |

**Response fields**

| Field | Type | Description |
|---|---|---|
| `notificationId` | string | The id of the notification. |
| `received` | boolean | Always `true`. |
| `receivedAt` | string | When the relay queued it, as an ISO 8601 time. |
| `queued` | boolean | `true` while the Mac has not taken it. |
| `displayed` | boolean | `true` once the banner was shown. |
| `displayedAt` | string | When the banner was shown. Present only when `displayed` is `true`. |
| `spoken` | boolean | `true` once speech finished. |
| `spokenAt` | string | When speech finished. Present only when `spoken` is `true`. |
| `replied` | boolean | `true` once the user answered. |
| `repliedAt` | string | When the user answered. Present only when `replied` is `true`. |
| `reply` | string | The answer: the typed text, or the transcript of a voice reply. Present with `repliedAt`. |
| `text` | string | The typed answer. Present only for a typed reply. |
| `transcript` | string | A transcript made on the user's Mac. It may be imperfect. |
| `transcriptNote` | string | A fixed sentence saying the transcript was made on the Mac and may be imperfect. |
| `audioUrl` | string | A signed link to the recorded voice reply. See [`GET /v1/audio/{deviceId}/{replyId}.m4a`](#get-v1audiodeviceidreplyidm4a). |
| `audioUrlExpiresInSeconds` | number | How long `audioUrl` stays valid: `3600`. A fresh read returns a fresh link. |
| `durationSeconds` | number | The length of the voice reply. |
| `expectReply` | boolean | Whether the notification was sent with `expectReply`. |
| `suppressed` | boolean | `true` when the notification was held back. |
| `reason` | string | Why it was held back. Present only when `suppressed` is `true`. |
| `suppressedScope` | string | `all` or `speech`. Present with `reason`. |

The `reason` values are:

| Reason | Set by | Meaning |
|---|---|---|
| `muted` | Herald | The user muted Herald. Scope `all`. |
| `quiet-hours` | Herald | Quiet hours were on. With scope `all` nothing was shown. With scope `speech` the banner was shown and only the speech was held back. |
| `expired` | The relay | The Mac stayed offline for the whole queue time (24 hours by default), so the notification was dropped. Scope `all`. |
| `delivery-failed` | Herald | Herald could not turn the notification into a banner. |
| other | Herald | The relay stores any reason of 1 to 40 characters from `a-z 0-9 -`. It uses `suppressed` when Herald sends none. |

### `GET /v1/replies/{notificationId}`

Returns the user's reply to a notification, and can wait for it. Use it when you sent `expectReply: true` and
want the answer. With `wait` the relay holds the request open until the user answers or the time runs out, so
you do not have to poll.

**Request**

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `notificationId` | path | string | yes | The id you sent, or the one the relay returned. |
| `wait` | query | number | no | Seconds to wait for a reply, from 0 to 60. Default `0`, which answers at once. |

**Example request**

```sh
curl -s "$RELAY/v1/replies/build-214?wait=30" \
  -H "Authorization: Bearer $KEY" \
  -H "User-Agent: Herald-Agent/1.0"
```

**Example response**

A voice reply. When no reply arrives within `wait`, the answer is `{"notificationId": "build-214", "replied":
false, "timedOut": true, "suppressed": false}`.

```json
{
  "notificationId": "build-214",
  "replied": true,
  "repliedAt": "2026-10-02T13:02:41.402Z",
  "reply": "Looks good, ship it.",
  "transcript": "Looks good, ship it.",
  "transcriptNote": "transcribed on the user's Mac; may be imperfect",
  "audioUrl": "https://herald-relay.example.workers.dev/v1/audio/a1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718/r_0123456789abcdef01234567.m4a?exp=1790000000&sig=9f2c",
  "audioUrlExpiresInSeconds": 3600,
  "durationSeconds": 4.2,
  "suppressed": false
}
```

**Response fields**

| Field | Type | Description |
|---|---|---|
| `notificationId` | string | The id of the notification. |
| `replied` | boolean | `true` when the user answered. |
| `timedOut` | boolean | `true` when `wait` ran out with no answer. Present only then. |
| `suppressed` | boolean | `true` when the notification was held back. |
| `reason` | string | Why it was held back. Present only when `suppressed` is `true`. |
| reply fields | various | The reply, when there is one. They are described under [The receipt object](#the-receipt-object). |

**Errors**

| Status | When |
|---|---|
| `401` | The key is missing, malformed, revoked or unknown. |
| `404` | This key sent no notification with that id in the last 24 hours. |
| `429` | The key made more than 600 receipt or reply reads in 10 minutes (`rate_limited`). |
| `503` | The Mac's daily request budget on the relay is used up (`budget_exhausted`). |

**Notes**

- The answer is `200` in every case. A missing reply is `replied: false`, not an error.
- The request ends early when the user replies, or when the notification is suppressed with scope `all`, because
  no reply can come after that.
- A request without `wait`, or with `wait=0`, never sets `timedOut`.
- While a request waits, the mailbox is awake and counts against the Mac's daily poll seconds. Once the
  allowance (3000 seconds by default) is used up, `wait` is treated as `0` and the relay answers at once.
- A typed answer is `text`. A voice answer has `transcript` and `audioUrl`. `reply` holds whichever of the two
  exists.

### `GET /v1/status`

Tells an agent whether the user's Mac is reachable and whether quiet hours are on. It exposes nothing else about
the Mac. Use it before you rely on a quick answer.

**Request**

No parameters.

**Example request**

```sh
curl -s "$RELAY/v1/status" \
  -H "Authorization: Bearer $KEY" \
  -H "User-Agent: Herald-Agent/1.0"
```

**Example response**

```json
{
  "online": true,
  "lastSeenAt": "2026-10-02T13:14:19.111Z",
  "quietHours": {
    "active": true,
    "until": "2026-10-03T07:00:00Z"
  }
}
```

**Response fields**

| Field | Type | Description |
|---|---|---|
| `online` | boolean | `true` when Herald holds its connection open and the relay heard from it in the last 11 minutes. |
| `lastSeenAt` | string | When the relay last heard from Herald. Absent when it never has. |
| `quietHours` | object | `active` is `true` while quiet hours are on. `until` is the end time Herald reported, when it reported one. |

**Errors**

| Status | When |
|---|---|
| `401` | The key is missing, malformed, revoked or unknown. |
| `503` | The Mac's daily request budget on the relay is used up (`budget_exhausted`). |

**Notes**

- Herald pings the relay every 5 minutes. `online` tolerates two missed pings.
- A status request counts toward the daily request budget but not toward the read limit.

### `GET /health`

Reports that the relay is running. It needs no credential and touches no storage, so it is safe to call from a
monitor.

**Request**

No parameters.

**Example request**

```sh
curl -s "$RELAY/health" -H "User-Agent: Herald-Agent/1.0"
```

**Example response**

```json
{
  "service": "herald-relay",
  "ok": true,
  "bundle": "3f2a9c0e"
}
```

**Response fields**

| Field | Type | Description |
|---|---|---|
| `service` | string | Always `herald-relay`. |
| `ok` | boolean | Always `true`. |
| `bundle` | string | The hash of the bundle that is running. Present only when Herald deployed the relay. |

**Notes**

- `/healthz` answers the same way. `GET /` returns a small HTML page for a person who opened the address, with
  links to the discovery documents and `/activate`; any other method on `/` returns this JSON.

### `GET /v1/audio/{deviceId}/{replyId}.m4a`

Downloads the voice message a user recorded as a reply. The `audioUrl` in a reply or receipt is exactly this
address with its signature, so an agent does not build it by hand. The link is the credential: it needs no bearer
token and works only until it expires.

**Request**

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `deviceId` | path | string | yes | The 48 hex characters of the Mac's id. |
| `replyId` | path | string | yes | The relay's id for the notification: `r_` and 24 hex characters. |
| `exp` | query | integer | yes | When the link expires, in Unix seconds. |
| `sig` | query | string | yes | The signature of the path and `exp`. |

**Example request**

```sh
curl -s -o reply.m4a "$AUDIO_URL" -H "User-Agent: Herald-Agent/1.0"
```

**Example response**

The reply is the audio file itself: `200` with `Content-Type: audio/mp4`, the byte length in `Content-Length` and
`Cache-Control: private, no-store`. There is no JSON body.

```text
HTTP/2 200
content-type: audio/mp4
cache-control: private, no-store
content-length: 53214
```

**Errors**

| Status | When |
|---|---|
| `403` | The signature does not match (`forbidden`). |
| `404` | The path is not shaped like a voice reply, or the file does not exist (`not_found`). |
| `410` | The link has expired. Read the reply again for a fresh one (`expired`). |

**Notes**

- A link is valid for 3600 seconds from the read that produced it.
- The audio is AAC in an m4a container, at most 1 MB. The relay keeps it for 7 days (the bucket's lifecycle rule),
  and deletes it earlier when the Mac unpairs.

## MCP endpoint

The relay is also a remote MCP server, so an agent platform that speaks MCP can use it without writing HTTP
calls. It offers four tools, which call the same code as the [agent endpoints](#agent-endpoints), and one event,
which tells an agent when the user replied. Setting up a connection is covered in
[Connect an agent](../cloud/connect-agent.md) and [Connect ChatGPT](../cloud/connect-chatgpt.md).

### `POST /mcp`

The one MCP endpoint. Every call is a JSON-RPC 2.0 request in a `POST` body and every reply is a single JSON
response. Use it as the server URL when you register Herald in an MCP client.

**Request**

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `Authorization` | header | string | yes | `Bearer` and an agent key or connector access token. |
| `Content-Type` | header | string | yes | `application/json`. |
| `MCP-Protocol-Version` | header | string | no | The protocol version. Required as `2026-07-28` for the event methods; see below. |
| `Mcp-Method` | header | string | no | The JSON-RPC method again. Required when the protocol version is `2026-07-28`. |
| `Mcp-Name` | header | string | no | The tool name again. Required on `tools/call` when the protocol version is `2026-07-28`. |

The body is one JSON-RPC request. An array of requests is refused.

**Example request**

```sh
curl -s -X POST "$RELAY/mcp" \
  -H "Authorization: Bearer $KEY" \
  -H "Content-Type: application/json" \
  -H "User-Agent: Herald-Agent/1.0" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/list"}'
```

**Example response**

The reply lists the four tools. The `inputSchema` of each tool is shortened here.

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "result": {
    "tools": [
      {
        "name": "send_notification",
        "title": "Send a notification to the user's Mac",
        "inputSchema": {"type": "object", "required": ["title"]}
      },
      {
        "name": "get_receipt",
        "title": "Get delivery receipts",
        "inputSchema": {"type": "object", "required": ["notificationId"]}
      },
      {
        "name": "wait_for_reply",
        "title": "Wait for the user's reply",
        "inputSchema": {"type": "object", "required": ["notificationId"]}
      },
      {
        "name": "herald_status",
        "title": "Is the user's Mac reachable",
        "inputSchema": {"type": "object"}
      }
    ]
  }
}
```

**Errors**

| Status | When |
|---|---|
| `400` | The body is not JSON (`-32700`), is an array (`-32600`), or the protocol headers are wrong (see [JSON-RPC errors](#json-rpc-errors)). |
| `401` | The credential is missing or invalid. The `WWW-Authenticate` header points to the discovery document. |
| `403` | The credential is the device token, or has no `notify` scope. |
| `404` | The method is unknown on a request that uses protocol `2026-07-28`. |
| `405` | The method is `GET` or `DELETE`. The server answers `POST` only, with no event stream and no sessions. |

**Notes**

- The transport is Streamable HTTP in its simplest form: one request, one JSON reply, no Server-Sent Events and
  no `Mcp-Session-Id`. A client that tries to open a stream with `GET` gets `405`.
- Every request needs a valid credential, even one the relay answers itself, such as `ping`. A missing or bad
  credential answers `401` with `WWW-Authenticate: Bearer resource_metadata="<origin>/.well-known/oauth-protected-resource"`,
  so an OAuth client can discover where to sign in. A rejected token adds `error="invalid_token"`.
- A request that carries no `id` is a notification. The relay answers `202` with no body.
- Each request makes one request to the Mac's mailbox for the credential check, and a tool call makes a second
  one. They count toward the daily request budget.

#### Protocol versions

Two kinds of client are served from the same URL, chosen by what the request carries.

| Kind | How it is recognised | What it gets |
|---|---|---|
| Tools only | An `initialize` handshake, with `2025-06-18`, `2025-03-26` or `2024-11-05`. | `initialize`, `ping`, `tools/list` and `tools/call`. |
| Tools and events | `MCP-Protocol-Version: 2026-07-28` and the `_meta` fields below on every request. | Everything above, plus `server/discover` and the event methods. |

A request that names any other protocol version in `MCP-Protocol-Version` is refused with `-32022`.

A request on `2026-07-28` carries no handshake, so every request states its own context. The `_meta` object in
`params` holds two members, and the headers repeat the method and the tool name so a proxy can route without
parsing the body.

| Part | Where | Must be |
|---|---|---|
| `io.modelcontextprotocol/protocolVersion` | `params._meta` | `2026-07-28`, and equal to the `MCP-Protocol-Version` header. |
| `io.modelcontextprotocol/clientCapabilities` | `params._meta` | An object. It may be empty. |
| `Mcp-Method` | header | The same as the body's `method`. |
| `Mcp-Name` | header | The same as `params.name`, on `tools/call` only. A name with non-ASCII characters is sent as `=?base64?<base64>?=`. |

A reply on `2026-07-28` also carries `resultType: "complete"` and `_meta` with the server's identity, as the
examples below show.

#### JSON-RPC errors

| Code | HTTP status | Meaning |
|---|---|---|
| `-32700` | `400` | The body is not valid JSON. |
| `-32600` | `400` or `202` | The body is a batch, or it is a response and not a request (`202`). |
| `-32601` | `200` or `404` | The method does not exist. `404` on `2026-07-28`, `200` otherwise. |
| `-32602` | `200` or `400` | A parameter is missing or invalid, a tool is unknown, or `_meta` lacks the required members. |
| `-32603` | `200`, `429` or `503` | The relay could not handle a subscription right now. |
| `-32015` | `200` | A subscription callback failed verification. |
| `-32020` | `400` | A header does not match the body: `MCP-Protocol-Version`, `Mcp-Method` or `Mcp-Name`. |
| `-32022` | `400` | The protocol version is not supported. `data` lists the `supported` versions. |
| `-32000` | `405` | The request used `GET` or `DELETE`. |

### `initialize`

Starts a tools-only session in the 2025 handshake. The relay keeps no session: the reply only tells the client
what the server can do, and the client then sends `tools/list` and `tools/call`. The relay echoes the client's
protocol version when it supports it and answers `2025-06-18` otherwise.

**Request**

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `params.protocolVersion` | body | string | no | The version the client wants: `2025-06-18`, `2025-03-26` or `2024-11-05`. |
| `params.capabilities` | body | object | no | The client's capabilities. The relay ignores them. |
| `params.clientInfo` | body | object | no | The client's name and version. The relay ignores them. |

**Example request**

```sh
curl -s -X POST "$RELAY/mcp" \
  -H "Authorization: Bearer $KEY" \
  -H "Content-Type: application/json" \
  -H "User-Agent: Herald-Agent/1.0" \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"my-agent","version":"1.0.0"}}}'
```

**Example response**

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "result": {
    "protocolVersion": "2025-06-18",
    "capabilities": {"tools": {"listChanged": false}},
    "serverInfo": {"name": "herald-relay", "title": "Herald cloud relay", "version": "1.1.0"},
    "instructions": "Send notifications to the user's Mac with send_notification; read receipts with get_receipt; wait for an answer with wait_for_reply."
  }
}
```

**Notes**

- The real `instructions` string is longer. It also describes the device flow and the event subscription.
- The relay does not issue a session id. A client may send `notifications/initialized`; the relay answers `202`.

### `tools/call`

Runs one tool. The `params` carry the tool's `name` and its `arguments`. The four tools are described next.

**Request**

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `params.name` | body | string | yes | `send_notification`, `get_receipt`, `wait_for_reply` or `herald_status`. |
| `params.arguments` | body | object | no | The tool's arguments. |

**Example request**

```sh
curl -s -X POST "$RELAY/mcp" \
  -H "Authorization: Bearer $KEY" \
  -H "Content-Type: application/json" \
  -H "User-Agent: Herald-Agent/1.0" \
  -d '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"herald_status","arguments":{}}}'
```

**Example response**

Every tool result has the same envelope. The JSON the endpoint returned is both the text of `content` and the
`structuredContent`.

```json
{
  "jsonrpc": "2.0",
  "id": 2,
  "result": {
    "content": [
      {
        "type": "text",
        "text": "{\"online\":true,\"lastSeenAt\":\"2026-10-02T13:14:19.111Z\",\"quietHours\":{\"active\":false}}"
      }
    ],
    "structuredContent": {
      "online": true,
      "lastSeenAt": "2026-10-02T13:14:19.111Z",
      "quietHours": {"active": false}
    }
  }
}
```

**Errors**

| Status | When |
|---|---|
| `200` | The tool failed. The result has `isError: true` and holds the endpoint's error body, for example `forbidden_fields` or `rate_limited`. |
| `200` | The tool name is unknown. The reply is the JSON-RPC error `-32602`, `unknown tool: <name>`. |
| `401` | The credential is invalid. A bad credential is an HTTP error, not a tool result. |

### MCP tools

Each tool forwards to the agent endpoint named in its block. The arguments and result fields are the endpoint's,
so the endpoint's tables are the full reference and these blocks list what an MCP client sees.

### `send_notification`

Queues a notification for the user's Mac. Call it to tell the user something or to ask for an answer. It takes
the same text and presentation fields as the endpoint, and refuses buttons, commands, callbacks and scripts.

**Arguments**

| Name | Type | Required | Description |
|---|---|---|---|
| `title` | string | yes | The headline. |
| `body` | string | no | The message text. |
| `expectReply` | boolean | no | Adds the **Reply** and **Record** buttons. |
| `notificationId` | string | no | Your own id. Sending the same id again within 24 hours never shows a second banner. |
| other fields | various | no | Every other field of [`POST /v1/notify`](#post-v1notify). |

**Example call**

```json
{
  "title": "Build finished",
  "body": "All 214 tests passed.",
  "speak": true,
  "expectReply": true,
  "notificationId": "build-214"
}
```

**Example result**

```json
{
  "content": [
    {
      "type": "text",
      "text": "{\"duplicate\":false,\"notificationId\":\"build-214\",\"received\":true,\"queued\":true,\"displayed\":false,\"spoken\":false,\"replied\":false,\"expectReply\":true,\"suppressed\":false}"
    }
  ],
  "structuredContent": {
    "duplicate": false,
    "notificationId": "build-214",
    "received": true,
    "receivedAt": "2026-10-02T13:00:04.000Z",
    "queued": true,
    "displayed": false,
    "spoken": false,
    "replied": false,
    "expectReply": true,
    "suppressed": false
  }
}
```

**HTTP route**

[`POST /v1/notify`](#post-v1notify). The tool schema has `additionalProperties: false`, and the relay refuses a
field outside the whitelist whatever the client sends.

**Side effects**

Queues a notification, and Herald shows a banner on the Mac. The tool is idempotent for a repeated
`notificationId`.

### `get_receipt`

Reads the receipts for a notification you sent: received, displayed, spoken, replied, suppressed. Call it to
learn whether the user saw a notification or whether quiet hours held it back.

**Arguments**

| Name | Type | Required | Description |
|---|---|---|---|
| `notificationId` | string | yes | The id you sent, or the one the relay returned. |

**Example call**

```json
{"notificationId": "build-214"}
```

**Example result**

```json
{
  "content": [
    {
      "type": "text",
      "text": "{\"notificationId\":\"build-214\",\"received\":true,\"displayed\":true,\"replied\":false,\"suppressed\":false}"
    }
  ],
  "structuredContent": {
    "notificationId": "build-214",
    "received": true,
    "receivedAt": "2026-10-02T13:00:04.000Z",
    "queued": false,
    "displayed": true,
    "displayedAt": "2026-10-02T13:00:05.210Z",
    "spoken": false,
    "replied": false,
    "expectReply": true,
    "suppressed": false
  }
}
```

**HTTP route**

[`GET /v1/receipts/{notificationId}`](#get-v1receiptsnotificationid). A missing `notificationId` is a tool error
(`isError: true`, text `notificationId is required`).

**Side effects**

None. Read-only.

### `wait_for_reply`

Waits for the user's answer to a notification sent with `expectReply`. Call it after `send_notification`. When
nothing came, it returns `replied: false` and `timedOut: true`, and you call it again to keep waiting.

**Arguments**

| Name | Type | Required | Description |
|---|---|---|---|
| `notificationId` | string | yes | The id you sent, or the one the relay returned. |
| `timeoutSeconds` | integer | no | Seconds to wait, from 0 to 55. Default `30`. |

**Example call**

```json
{"notificationId": "build-214", "timeoutSeconds": 30}
```

**Example result**

```json
{
  "content": [
    {
      "type": "text",
      "text": "{\"notificationId\":\"build-214\",\"replied\":false,\"timedOut\":true,\"suppressed\":false}"
    }
  ],
  "structuredContent": {
    "notificationId": "build-214",
    "replied": false,
    "timedOut": true,
    "suppressed": false
  }
}
```

**HTTP route**

[`GET /v1/replies/{notificationId}`](#get-v1repliesnotificationid) with `wait` set to `timeoutSeconds`. The tool
stops at 55 seconds, five below the endpoint's limit, so the MCP client's own timeout is not reached first.

**Side effects**

None. Read-only. A call that waits keeps the Mac's mailbox awake and counts against its daily poll seconds.

### `herald_status`

Says whether the user's Herald is online, when it was last seen, and whether quiet hours are on. Call it before
you depend on a fast answer.

**Arguments**

No arguments.

**Example call**

```json
{}
```

**Example result**

```json
{
  "content": [
    {
      "type": "text",
      "text": "{\"online\":true,\"quietHours\":{\"active\":false}}"
    }
  ],
  "structuredContent": {
    "online": true,
    "lastSeenAt": "2026-10-02T13:14:19.111Z",
    "quietHours": {"active": false}
  }
}
```

**HTTP route**

[`GET /v1/status`](#get-v1status).

**Side effects**

None. Read-only.

### MCP Events

An agent that sent a notification with `expectReply` can be called back the moment the user answers, instead of
polling `wait_for_reply`. This is MCP Events. The agent subscribes once with a webhook address. When the user
answers a notification that the same connector sent, the relay sends a signed `POST` to that address.

Events are available to clients on protocol `2026-07-28` only. The events methods need no setup on the Mac: the connector's approval in Herald authorises its subscriptions, and there is no second question.

A subscription does not expire. It ends in one of three ways:

- The agent unsubscribes.
- The user ends it in **Settings > Cloud > Reply subscriptions**.
- The user revokes the connector.

For an OpenAI dot, an always-on cloud agent, the subscription has to go through the platform that hosts it; see [Reply events](../cloud/reply-events.md).

Every request in this section carries the headers and `_meta` from [Protocol versions](#protocol-versions),
and every reply carries `resultType` and `_meta` as the examples show.

### `server/discover`

Describes the server to a client on protocol `2026-07-28`, which sends no handshake. Call it to learn which
protocol versions and capabilities the relay offers.

**Request**

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `params._meta` | body | object | yes | The protocol version and client capabilities. |

**Example request**

```sh
curl -s -X POST "$RELAY/mcp" \
  -H "Authorization: Bearer $KEY" \
  -H "Content-Type: application/json" \
  -H "User-Agent: Herald-Agent/1.0" \
  -H "MCP-Protocol-Version: 2026-07-28" \
  -H "Mcp-Method: server/discover" \
  -d '{"jsonrpc":"2.0","id":1,"method":"server/discover","params":{"_meta":{"io.modelcontextprotocol/protocolVersion":"2026-07-28","io.modelcontextprotocol/clientCapabilities":{}}}}'
```

**Example response**

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "result": {
    "resultType": "complete",
    "supportedVersions": ["2026-07-28", "2025-06-18", "2025-03-26", "2024-11-05"],
    "capabilities": {"tools": {}, "events": {}},
    "serverInfo": {"name": "herald-relay", "title": "Herald cloud relay", "version": "1.1.0"},
    "instructions": "Send notifications to the user's Mac with send_notification.",
    "_meta": {
      "io.modelcontextprotocol/serverInfo": {"name": "herald-relay", "title": "Herald cloud relay", "version": "1.1.0"}
    }
  }
}
```

**Errors**

| Status | When |
|---|---|
| `400` | A header is missing or does not match the body, or `_meta` lacks a required member. See [JSON-RPC errors](#json-rpc-errors). |

### `events/list`

Lists the events the relay can send. There is one: `notification.reply`.

**Request**

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `params._meta` | body | object | yes | The protocol version and client capabilities. |

**Example request**

```sh
curl -s -X POST "$RELAY/mcp" \
  -H "Authorization: Bearer $KEY" \
  -H "Content-Type: application/json" \
  -H "User-Agent: Herald-Agent/1.0" \
  -H "MCP-Protocol-Version: 2026-07-28" \
  -H "Mcp-Method: events/list" \
  -d '{"jsonrpc":"2.0","id":2,"method":"events/list","params":{"_meta":{"io.modelcontextprotocol/protocolVersion":"2026-07-28","io.modelcontextprotocol/clientCapabilities":{}}}}'
```

**Example response**

The description and schemas are shortened.

```json
{
  "jsonrpc": "2.0",
  "id": 2,
  "result": {
    "resultType": "complete",
    "events": [
      {
        "name": "notification.reply",
        "description": "The user answered a notification you sent with expectReply.",
        "delivery": ["webhook"],
        "inputSchema": {"type": "object", "additionalProperties": false, "properties": {}},
        "payloadSchema": {
          "type": "object",
          "required": ["notificationId", "id", "kind"],
          "properties": {
            "notificationId": {"type": "string"},
            "id": {"type": "string"},
            "kind": {"type": "string", "enum": ["text", "voice"]}
          }
        }
      }
    ],
    "_meta": {
      "io.modelcontextprotocol/serverInfo": {"name": "herald-relay", "title": "Herald cloud relay", "version": "1.1.0"}
    }
  }
}
```

### `events/subscribe`

Registers a webhook for `notification.reply`. The relay first checks that the address is yours by sending it a
signed challenge it must echo, and only then activates the subscription. Call it once per connector and address.

**Request**

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `params.name` | body | string | yes | The event: `notification.reply`. |
| `params.arguments` | body | object | no | Must be empty or absent. The event takes no arguments. |
| `params.delivery` | body | object | yes | `mode` is `webhook`, `url` is the callback, and `secret` is the signing secret. See below. |
| `params.cursor` | body | string | no | A cursor from an earlier subscription. The relay replays later replies of this connector, up to 100. |
| `params.ttlMs` | body | integer | no | Accepted and ignored. A positive integer, or the call fails. |

Fields of `params.delivery`:

| Name | Type | Required | Description |
|---|---|---|---|
| `mode` | string | yes | Always `webhook`. |
| `url` | string | yes | An `https` URL on the default port, at most 2048 characters, with no credentials. The host must be public, as listed under the table. |
| `secret` | string | yes | `whsec_` followed by base64 of 24 to 64 random bytes. You generate it and keep it to verify deliveries. |

The host of `url` must not be any of these:

- `localhost`, or a local, internal or private name.
- A loopback, private, link-local or reserved address.

**Example request**

```sh
curl -s -X POST "$RELAY/mcp" \
  -H "Authorization: Bearer $KEY" \
  -H "Content-Type: application/json" \
  -H "User-Agent: Herald-Agent/1.0" \
  -H "MCP-Protocol-Version: 2026-07-28" \
  -H "Mcp-Method: events/subscribe" \
  -d '{"jsonrpc":"2.0","id":3,"method":"events/subscribe","params":{"name":"notification.reply","delivery":{"mode":"webhook","url":"https://agent.example.com/hooks/herald","secret":"whsec_MfKQ9r8GKYqrTwjUPD8ILPZIo2LaLaSw"},"_meta":{"io.modelcontextprotocol/protocolVersion":"2026-07-28","io.modelcontextprotocol/clientCapabilities":{}}}}'
```

**Example response**

```json
{
  "jsonrpc": "2.0",
  "id": 3,
  "result": {
    "resultType": "complete",
    "id": "sub_3fa91c0de27b45a6d118",
    "refreshBefore": "2036-09-29T13:00:00.000Z",
    "cursor": "41",
    "truncated": false,
    "_meta": {
      "io.modelcontextprotocol/serverInfo": {"name": "herald-relay", "title": "Herald cloud relay", "version": "1.1.0"}
    }
  }
}
```

**Response fields**

| Field | Type | Description |
|---|---|---|
| `id` | string | The subscription id: `sub_` and 20 hex characters. |
| `refreshBefore` | string | A time ten years ahead. Subscriptions do not lapse, so there is nothing to refresh. |
| `cursor` | string | The sequence number of the newest reply that this subscription has been sent or has queued. |
| `truncated` | boolean | `true` when `cursor` asked for history older than the relay keeps (30 days). |

**Errors**

| Code | When |
|---|---|
| `-32602` | The request is invalid. The causes are listed under the table. |
| `-32015` | The callback failed verification. `data.reason` is `unreachable`, `bad_status` or `challenge_mismatch`. |
| `-32603` | The relay could not handle the subscription right now. The HTTP status is `429` or `503` when the cause was a limit. |

The causes of `-32602`:

- The event name is unknown, or `arguments` is not empty.
- `delivery.mode` is not `webhook`.
- The URL is not a public `https` URL on the default port without credentials.
- The host is not on the relay's `EVENT_CALLBACK_HOSTS` list. `data.reason` is `host_not_allowed`.
- The secret is malformed.
- `ttlMs` is not a positive integer.
- The connector already has 5 subscriptions.

**Notes**

- To verify the address, the relay sends a `POST` with the body `{"type":"verification","challenge":"<random>"}`,
  signed like any delivery. Your endpoint must answer `2xx` with a JSON body that echoes the same `challenge`.
- Subscribing again with the same connector, event and URL keeps the same `id`, replaces the secret and does not
  verify again.
- A cursor replays only this connector's replies. The cursor returned never moves past an event that has not
  been sent yet.
- On a relay that restricts callback hosts, the Worker variable `EVENT_CALLBACK_HOSTS` lists the allowed host
  names. Empty means any public host.

### `events/unsubscribe`

Removes a subscription. It works whatever the host rules are at that moment, and it succeeds when there is
nothing to remove.

**Request**

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `params.name` | body | string | yes | The event: `notification.reply`. |
| `params.delivery` | body | object | yes | An object whose `url` is the callback address you subscribed with. |

**Example request**

```sh
curl -s -X POST "$RELAY/mcp" \
  -H "Authorization: Bearer $KEY" \
  -H "Content-Type: application/json" \
  -H "User-Agent: Herald-Agent/1.0" \
  -H "MCP-Protocol-Version: 2026-07-28" \
  -H "Mcp-Method: events/unsubscribe" \
  -d '{"jsonrpc":"2.0","id":4,"method":"events/unsubscribe","params":{"name":"notification.reply","delivery":{"url":"https://agent.example.com/hooks/herald"},"_meta":{"io.modelcontextprotocol/protocolVersion":"2026-07-28","io.modelcontextprotocol/clientCapabilities":{}}}}'
```

**Example response**

```json
{
  "jsonrpc": "2.0",
  "id": 4,
  "result": {
    "resultType": "complete",
    "_meta": {
      "io.modelcontextprotocol/serverInfo": {"name": "herald-relay", "title": "Herald cloud relay", "version": "1.1.0"}
    }
  }
}
```

**Errors**

| Code | When |
|---|---|
| `-32602` | The event name is unknown, or `delivery.url` is not a valid URL. |

#### The `notification.reply` event

The event fires once per notification, the first time the user answers it, typed or recorded. It goes only to
subscriptions of the connector that sent that notification. The payload carries ids and never the answer, so
read the answer with `get_receipt` or `wait_for_reply`.

| Field | Type | Description |
|---|---|---|
| `eventId` | string | `evt_`, the event's sequence number, and the subscription's id. It is stable across retries. |
| `name` | string | Always `notification.reply`. |
| `timestamp` | string | When the user replied, as an ISO 8601 time. |
| `data.notificationId` | string | The id you sent, or the one the relay generated. |
| `data.id` | string | The relay's own id for the notification, `r_` and 24 hex characters. |
| `data.kind` | string | `text` or `voice`. |
| `cursor` | string | The event's sequence number. Pass it to `events/subscribe` to replay later events. |

```json
{
  "eventId": "evt_42_3fa91c0de27b45a6d118",
  "name": "notification.reply",
  "timestamp": "2026-10-02T13:02:41.402Z",
  "data": {
    "notificationId": "build-214",
    "id": "r_0123456789abcdef01234567",
    "kind": "text"
  },
  "cursor": "42"
}
```

#### Webhook delivery

Each delivery is an HTTPS `POST` with this body and these headers. The signature follows the Standard Webhooks
scheme, so any Standard Webhooks library can verify it.

| Header | Value |
|---|---|
| `Content-Type` | `application/json` |
| `User-Agent` | `Herald-Relay/1.0` |
| `webhook-id` | The `eventId`. It is the same on every retry of one event. |
| `webhook-timestamp` | The send time in Unix seconds. |
| `webhook-signature` | `v1,` and the base64 HMAC-SHA256 of `<webhook-id>.<webhook-timestamp>.<body>`. The key is the bytes of the secret after `whsec_`, decoded from base64. |
| `x-mcp-subscription-id` | The subscription's id. |

Your endpoint answers `2xx` to accept the event. The relay does not follow redirects, and a request that takes
longer than 10 seconds counts as failed.

| Your answer | What the relay does |
|---|---|
| `2xx` | The event is delivered. It is not sent again. |
| `410` | The subscription ends. |
| Another `4xx`, except `408` and `429` | That one event is dropped. The subscription stays. |
| `408`, `429`, `5xx`, a redirect, a timeout or a network error | The event is retried. |

Retries wait 1 minute, then double each time up to 1 hour, and honour a longer `Retry-After`. An event is tried
at most 8 times and for at most 24 hours, and is then dropped. Events are sent in order for each subscription:
the relay does not send a newer event until the oldest one is delivered or dropped.

> [!NOTE]
> A `2xx` means your endpoint received the event. It does not prove that your agent acted on it. To check the
> whole path, send a notification with `expectReply`, reply on the Mac, and confirm your agent woke.

#### Event limits

| Limit | Value |
|---|---|
| Subscriptions per connector | 5. |
| Replay on subscribe | Up to 100 events after the cursor. |
| History kept | 30 days of reply events. |
| Delivery timeout | 10 seconds. |
| Delivery attempts | 8, within 24 hours. |

## OAuth endpoints

The relay is its own OAuth authorization server, so a connector such as ChatGPT can be approved without anyone
copying an agent key. The approval always happens on the user's Mac: the relay shows a page or returns a code, and
Herald shows a banner that the user must approve. The web page alone never grants access.

Two ways to get a token are supported. The browser flow (authorization code with PKCE) suits a client that can
open a browser. The device flow suits an agent that cannot, such as a sandboxed cloud agent or a CI job: the agent
prints a short code and the user approves it on the Mac. The step-by-step for the device flow is in
[Device flow](../cloud/device-flow.md).

The OAuth routes send permissive CORS headers and take `application/x-www-form-urlencoded` bodies, except
`POST /register`, which takes JSON.

**Tokens do not expire.** A connector approved in Herald is a durable record that works until the user revokes it
there. Its access and refresh tokens never expire and are never rotated.

- `expires_in` is reported as `315360000` seconds (ten years) because OAuth clients expect the field.
- A refresh returns a new access token and the same refresh token. Nothing the client holds is invalidated by
  using it, so a lost response can simply be retried.
- Earlier access tokens stay valid. The relay keeps the newest 50 access tokens of a connector and drops older
  ones beyond that.
- A repeated code exchange or a repeated device poll after approval returns tokens again. It never undoes the
  approval.
- Revoking the connector in Herald ends all of its tokens and its event subscriptions at once.

### `GET /.well-known/oauth-protected-resource`

Describes the protected resource, the MCP endpoint, and names the relay as its authorization server. A client
that gets a `401` from `/mcp` reads this document next (RFC 9728).

**Request**

No parameters.

**Example request**

```sh
curl -s "$RELAY/.well-known/oauth-protected-resource" -H "User-Agent: Herald-Agent/1.0"
```

**Example response**

```json
{
  "resource": "https://herald-relay.example.workers.dev/mcp",
  "authorization_servers": ["https://herald-relay.example.workers.dev"],
  "scopes_supported": ["notify"],
  "bearer_methods_supported": ["header"],
  "resource_name": "Herald relay"
}
```

**Notes**

- `/.well-known/oauth-protected-resource/mcp` returns the same document.
- The reply is cacheable for 300 seconds. Any method other than `GET` answers `405`.

### `GET /.well-known/oauth-authorization-server`

Describes the authorization server: where its endpoints are and what it supports (RFC 8414). A client reads it to
find these endpoints:

- `/register`
- `/authorize`
- `/token`
- `/device_authorization`
- `/revoke`

**Request**

No parameters.

**Example request**

```sh
curl -s "$RELAY/.well-known/oauth-authorization-server" -H "User-Agent: Herald-Agent/1.0"
```

**Example response**

```json
{
  "issuer": "https://herald-relay.example.workers.dev",
  "authorization_endpoint": "https://herald-relay.example.workers.dev/authorize",
  "token_endpoint": "https://herald-relay.example.workers.dev/token",
  "registration_endpoint": "https://herald-relay.example.workers.dev/register",
  "device_authorization_endpoint": "https://herald-relay.example.workers.dev/device_authorization",
  "revocation_endpoint": "https://herald-relay.example.workers.dev/revoke",
  "scopes_supported": ["notify"],
  "response_types_supported": ["code"],
  "response_modes_supported": ["query"],
  "grant_types_supported": [
    "authorization_code",
    "refresh_token",
    "urn:ietf:params:oauth:grant-type:device_code"
  ],
  "code_challenge_methods_supported": ["S256"],
  "token_endpoint_auth_methods_supported": ["none", "client_secret_post", "client_secret_basic"],
  "revocation_endpoint_auth_methods_supported": ["none", "client_secret_post", "client_secret_basic"],
  "service_documentation": "https://github.com/ivg-design/herald/blob/main/docs/CLOUD.md"
}
```

**Notes**

- `/.well-known/openid-configuration` returns the same document, for clients that look there.
- The only scope is `notify`: send notifications and read receipts and replies.

### `POST /register`

Registers an OAuth client dynamically (RFC 7591). Every client registers once and keeps its `client_id`. A client
that only uses the device flow has no redirect address to register.

**Request**

The body is JSON.

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `client_name` | body | string | no | The name Herald shows in the approval banner, at most 60 characters. Control characters and `<` `>` are removed. Default `An app`. |
| `redirect_uris` | body | array of strings | no | One to 10 addresses. Required unless `grant_types` holds only the device grant (with `refresh_token` if you like). |
| `grant_types` | body | array of strings | no | Any of `authorization_code`, `refresh_token` and `urn:ietf:params:oauth:grant-type:device_code`. Default `["authorization_code"]`. |
| `token_endpoint_auth_method` | body | string | no | `none`, `client_secret_post` or `client_secret_basic`. Default `none`. |
| `response_types` | body | array of strings | no | Only `code` is accepted. |

A redirect address must meet all of these rules:

- It is `https`, or `http` on `localhost`, `127.0.0.1` or `[::1]`, or a private-use scheme such as `myapp://callback`.
- It has no fragment and no credentials.
- It is at most 500 characters.

**Example request**

```sh
curl -s -X POST "$RELAY/register" \
  -H "Content-Type: application/json" \
  -H "User-Agent: Herald-Agent/1.0" \
  -d '{"client_name":"My cloud agent","grant_types":["urn:ietf:params:oauth:grant-type:device_code"]}'
```

**Example response**

The reply is `201`.

```json
{
  "client_id": "hc_3fa91c0de27b45a6d1180123456789ab",
  "client_id_issued_at": 1790000000,
  "client_name": "My cloud agent",
  "redirect_uris": [],
  "token_endpoint_auth_method": "none",
  "grant_types": [
    "authorization_code",
    "refresh_token",
    "urn:ietf:params:oauth:grant-type:device_code"
  ],
  "response_types": ["code"],
  "scope": "notify"
}
```

**Response fields**

| Field | Type | Description |
|---|---|---|
| `client_id` | string | The client's id: `hc_` and 32 hex characters. |
| `client_id_issued_at` | integer | When it was issued, in Unix seconds. |
| `client_name` | string | The cleaned name. |
| `redirect_uris` | array | The registered addresses. |
| `token_endpoint_auth_method` | string | The method you asked for. |
| `grant_types` | array | Always all three grant types. |
| `client_secret` | string | A secret. Present only for `client_secret_post` and `client_secret_basic`. Shown once. |
| `client_secret_expires_at` | integer | `0`: the secret does not expire. Present with `client_secret`. |

**Errors**

| Status | When |
|---|---|
| `400` | The body is not JSON, or a grant type, response type or authentication method is not allowed. The error is `invalid_client_metadata`. |
| `400` | A redirect address is invalid. The error is `invalid_redirect_uri`. |
| `429` | The relay registered too many clients in the last hour (`rate_limited`, 30 by default). |

**Notes**

- Registration needs no credential.
- The relay keeps the 200 most recently registered clients. A client that falls out of that list has to register
  again.

### `GET /authorize`

Starts the browser flow. It shows the consent page, a web page that tells the person which app is asking and
waits for them to approve on the Mac. Send the user's browser here.

**Request**

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `response_type` | query | string | yes | `code`. |
| `client_id` | query | string | yes | The id from `POST /register`. |
| `redirect_uri` | query | string | yes | One of the addresses the client registered, exactly. |
| `code_challenge` | query | string | yes | The PKCE challenge: 43 characters from `A-Z a-z 0-9 - _`. |
| `code_challenge_method` | query | string | yes | `S256`. No other method is accepted. |
| `state` | query | string | no | Returned unchanged on the redirect. |
| `resource` | query | string | no | The MCP address, `<origin>/mcp`. Any other value is refused. |
| `scope` | query | string | no | `notify`. |
| `device` | query | integer | no | Which paired Mac receives the approval, counted from 1 in pairing order. Default: the Mac that is connected, else the one seen most recently. |

**Example request**

```sh
curl -s -G "$RELAY/authorize" \
  --data-urlencode "response_type=code" \
  --data-urlencode "client_id=hc_3fa91c0de27b45a6d1180123456789ab" \
  --data-urlencode "redirect_uri=https://agent.example.com/callback" \
  --data-urlencode "code_challenge=E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM" \
  --data-urlencode "code_challenge_method=S256" \
  --data-urlencode "state=xyz" \
  -H "User-Agent: Herald-Agent/1.0"
```

**Example response**

The reply is an HTML page, not JSON. It names the app, says what it will be able to do, and shows the approval
steps. The page polls the relay and sends the browser to `redirect_uri` with `code` and `state` once the user
approves on the Mac.

```text
HTTP/2 200
content-type: text/html; charset=utf-8
cache-control: no-store

<h1>My cloud agent wants to connect to Herald</h1>
```

**Errors**

| Status | When |
|---|---|
| `400` | The client is unknown, or `redirect_uri` is not one it registered. The page shows an error and the browser is never redirected. |
| `302` | A later check failed. The browser is redirected to `redirect_uri` with `error` and `error_description`. The error values are listed under the table. |
| `200` | The relay has no paired Mac yet. The page says to pair Herald first. |
| `429` | Approvals are already waiting in Herald, or too many were requested. The page asks the person to answer them or wait. |

The `error` values of the `302` redirect:

| `error` | Cause |
|---|---|
| `unsupported_response_type` | `response_type` is not `code`. |
| `invalid_request` | PKCE is missing: `code_challenge` with `code_challenge_method=S256` is required. |
| `invalid_target` | `resource` is not the relay's connector URL. |
| `invalid_scope` | The requested scope is anything other than `notify`. |

**Notes**

- Herald shows a banner on the Mac with **Approve** and **Deny**. The page also offers a 6-digit code, which
  Herald shows in **Settings > Cloud > Connector approvals**. Entering the right code approves; five wrong
  codes deny the request.
- A request lasts 10 minutes. After approval, the client has 5 minutes to exchange the code.
- The same client asking again replaces its open request and the banner is updated with a new code. At most 3
  requests wait in a Mac at once and at most 12 are begun an hour.
- Denying a request closes only that request. A key that already works is untouched.

The consent page uses these helper routes. They belong to the page and are not an API for clients.

| Route | Used by | What it does |
|---|---|---|
| `GET /authorize/status?rid=<id>` | The consent page, every 2 seconds. | Returns `{"status": "pending"}` until the user decides, then the redirect address. |
| `POST /authorize/code` | The page's code form. | Takes `rid` and `code` as a form. Approves on the right code, answers `wrong_code` with the tries left otherwise. |
| `POST /authorize/deny` | The page's **Deny** button. | Takes `rid` as a form and denies the request. |

### `POST /device_authorization`

Starts the device flow (RFC 8628) for an agent that has no usable browser. The reply holds a short `user_code`
that the agent shows to the user, and a `device_code` that the agent keeps and polls with. At the same moment,
Herald shows an approval banner on the Mac.

**Request**

The body is a form. A confidential client also sends its secret.

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `client_id` | body | string | yes | The id from `POST /register`. |
| `scope` | body | string | no | `notify`. |
| `device` | body | integer | no | Which paired Mac gets the banner, counted from 1 in pairing order. Default: the connected Mac, else the one seen most recently. |
| `client_secret` | body | string | no | The secret of a confidential client. It can instead go in a `Basic` `Authorization` header. |

**Example request**

```sh
curl -s -X POST "$RELAY/device_authorization" \
  -H "User-Agent: Herald-Agent/1.0" \
  -d client_id=hc_3fa91c0de27b45a6d1180123456789ab \
  -d scope=notify
```

**Example response**

```json
{
  "device_code": "hrv_...",
  "user_code": "BDFG-HJKM",
  "verification_uri": "https://herald-relay.example.workers.dev/activate",
  "verification_uri_complete": "https://herald-relay.example.workers.dev/activate?user_code=BDFG-HJKM",
  "expires_in": 600,
  "interval": 5,
  "device_name": "Studio Mac",
  "device_count": 1,
  "device_index": 1,
  "device_online": true
}
```

**Response fields**

| Field | Type | Description |
|---|---|---|
| `device_code` | string | The secret the agent polls `/token` with. It begins `hrv_`. |
| `user_code` | string | The code the user matches in Herald: 8 consonants as `XXXX-XXXX`. |
| `verification_uri` | string | The relay's `/activate` page, for a person with a browser. |
| `verification_uri_complete` | string | The same address with the user code filled in. |
| `expires_in` | integer | Seconds until the request expires: `600`. |
| `interval` | integer | The least seconds between polls: `5`. |
| `device_name` | string | The name of the Mac that received the banner. |
| `device_count` | integer | How many Macs are paired with the relay. |
| `device_index` | integer | The 1-based number of the chosen Mac. |
| `device_online` | boolean | `true` when that Mac is connected. |

**Errors**

| Status | When |
|---|---|
| `400` | `scope` is not `notify`, no Mac is paired yet, or `device` is out of range (`invalid_scope` or `invalid_request`). |
| `401` | The client is unknown or its secret is wrong (`invalid_client`). |
| `429` | Approvals are already waiting, or too many were requested this hour (`slow_down`). |
| `502` | The relay could not start the approval (`temporarily_unavailable`). |

**Notes**

- Tell the user which Mac will show the banner: `device_name` says so.
- The user sees a banner with the code and **Approve** and **Deny**. **Settings > Cloud > Connector approvals**
  lists the request with the code in large type and, in small type, a 6-digit approval code for the web page.
- Asking again with the same client replaces the open request. The earlier `device_code` stops working.
- The request lasts 10 minutes and the agent should poll `/token` every `interval` seconds. After approval the
  agent has 5 minutes to collect the tokens.

### `GET /activate`

Serves the page where a person with a browser enters the agent's code and approves it. It is optional: the user
can approve from the banner in Herald instead. The page asks for the `user_code` the agent printed, then for the
6-digit approval code that Herald shows, because the agent also knows the user code and could not approve itself.

**Request**

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `user_code` | query | string | no | Fills in the code field. |

**Example request**

```sh
curl -s "$RELAY/activate?user_code=BDFG-HJKM" -H "User-Agent: Herald-Agent/1.0"
```

**Example response**

The reply is an HTML page with `200`.

```text
HTTP/2 200
content-type: text/html; charset=utf-8

<h1>Approve an agent</h1>
```

**Notes**

The page posts to three helper routes. They belong to the page and are not an API for clients.

| Route | What it does |
|---|---|
| `POST /activate` | Takes `user_code` as a form and shows the confirmation step for the matching request. |
| `POST /activate/approve` | Takes `rid` and `code` (the 6-digit approval code) as a form and approves. |
| `POST /activate/deny` | Takes `rid` as a form and denies the request. |

### `POST /token`

Exchanges a grant for tokens. One endpoint serves all three grants, chosen by `grant_type`. A confidential client
sends its `client_secret` in the form or in a `Basic` header.

**Request**

The body is a form. These fields are shared by every grant.

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `grant_type` | body | string | yes | `authorization_code`, `refresh_token` or `urn:ietf:params:oauth:grant-type:device_code`. |
| `client_id` | body | string | yes | The id from `POST /register`. |
| `client_secret` | body | string | no | The secret of a confidential client. |
| `resource` | body | string | no | The MCP address. It must match the one in the original request. |

Fields of each grant:

| Grant | Name | Required | Description |
|---|---|---|---|
| `authorization_code` | `code` | yes | The `hrc_` code from the redirect. |
| `authorization_code` | `redirect_uri` | yes | The same address used in `/authorize`. |
| `authorization_code` | `code_verifier` | yes | The PKCE verifier: 43 to 128 characters from `A-Z a-z 0-9 - . _ ~`. |
| `refresh_token` | `refresh_token` | yes | The `hrr_` token from an earlier reply. |
| `refresh_token` | `scope` | no | Only `notify`. |
| device grant | `device_code` | yes | The `hrv_` code from `/device_authorization`. |

**Example request**

This is a device-flow poll.

```sh
curl -s -X POST "$RELAY/token" \
  -H "User-Agent: Herald-Agent/1.0" \
  -d grant_type=urn:ietf:params:oauth:grant-type:device_code \
  -d client_id=hc_3fa91c0de27b45a6d1180123456789ab \
  -d device_code=hrv_...
```

**Example response**

```json
{
  "access_token": "hra_...",
  "token_type": "Bearer",
  "expires_in": 315360000,
  "refresh_token": "hrr_...",
  "scope": "notify"
}
```

**Response fields**

| Field | Type | Description |
|---|---|---|
| `access_token` | string | The bearer token, `hra_...`. Send it as `Authorization: Bearer`. |
| `token_type` | string | `Bearer`. |
| `expires_in` | integer | `315360000`, ten years. The token does not expire; the field is for clients that require it. |
| `refresh_token` | string | The refresh token, `hrr_...`. A refresh returns the same one. |
| `scope` | string | `notify`. |

**Errors**

A failed request is `400` with `{"error": "...", "error_description": "..."}`, except for client authentication,
which is `401`. While a device flow waits, the agent sees these.

| Error | When |
|---|---|
| `authorization_pending` | The user has not answered yet. Keep polling every `interval` seconds. |
| `slow_down` | You polled faster than `interval`. The interval grows by 5 seconds; add that to yours. |
| `access_denied` | The user pressed **Deny**. Stop. |
| `expired_token` | The request expired, or the code is unknown. Start again at `/device_authorization`. |
| `invalid_grant` | A code, verifier, redirect address or refresh token is malformed, unknown, for another client, or its connector was revoked. |
| `invalid_target` | `resource` does not match the authorization request. |
| `invalid_scope` | A refresh asked for a scope other than `notify`. |
| `unsupported_grant_type` | `grant_type` is not one of the three. |
| `invalid_client` | The client is unknown or its secret is wrong. The status is `401`. |

**Notes**

- Approval creates one agent key for the connector, named after `client_name`, with `notify` scope. It appears in
  **Settings > Cloud > Agent keys** and can be revoked there. Approving the same client again replaces its earlier
  key.
- An access token works on every [agent endpoint](#agent-endpoints) and on `/mcp`, exactly as an agent key does.
- Poll no faster than `interval`. The device code stops being useful 10 minutes after it is issued unless the
  user approved it, in which case it works for 5 more minutes.

### `POST /revoke`

Revokes a token the client holds (RFC 7009). A client calls it to sign out. It answers `200` with an empty
object even when the token is unknown, so the reply never reveals whether a token existed.

**Request**

The body is a form.

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `token` | body | string | yes | An access token (`hra_...`) or a refresh token (`hrr_...`). |
| `client_id` | body | string | yes | The id of the client the token was issued to. |
| `client_secret` | body | string | no | The secret of a confidential client. |

**Example request**

```sh
curl -s -X POST "$RELAY/revoke" \
  -H "User-Agent: Herald-Agent/1.0" \
  -d token=hrr_... \
  -d client_id=hc_3fa91c0de27b45a6d1180123456789ab
```

**Example response**

```json
{}
```

**Errors**

| Status | When |
|---|---|
| `401` | The client is unknown or its secret is wrong (`invalid_client`). |

**Notes**

- Revoking a refresh token also revokes every access token issued with it. Revoking an access token revokes only
  that one.
- To end a connector completely, revoke it in Herald. That also ends its other tokens and its event
  subscriptions.

## Pairing and device endpoints

These routes connect a Mac to the relay and let Herald run it. Herald calls them for you from **Settings > Cloud**,
so you only need them to implement a relay or a compatible client, or to script a setup. Pairing needs no
credential; every `/v1/device/*` route needs the device token that pairing returns.

Pairing is a two-step handshake. The first call asks the relay for a one-time code. The second trades that code
for the device token. The device token is shown once and is never readable again; the relay stores only its
hash.

### `POST /v1/pair/start`

Asks the relay for a one-time pairing code. The code lasts 10 minutes and works once.

**Request**

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `X-Pairing-Secret` | header | string | no | The relay's pairing secret. Required when the relay was deployed with one. |
| `deviceName` | body | string | no | A name for the Mac, at most 60 characters. Pairing again under the same name replaces the earlier entry. |

**Example request**

```sh
curl -s -X POST "$RELAY/v1/pair/start" \
  -H "Content-Type: application/json" \
  -H "X-Pairing-Secret: ..." \
  -d '{"deviceName":"Studio Mac"}'
```

**Example response**

The reply is `201`.

```json
{
  "code": "K7QM-2XPD",
  "expiresInSeconds": 600
}
```

**Errors**

| Status | When |
|---|---|
| `401` | The relay has a pairing secret and the header is missing or wrong. |
| `403` | The relay already has its maximum number of paired Macs (`device_limit`, 5 by default). |
| `429` | Too many pairing attempts from this address or in total, or codes are already waiting (`rate_limited`). |

**Notes**

- The first pairing is trust on first use. Pair soon after deploying, or deploy with a pairing secret so a
  stranger cannot start.
- Codes are 8 characters shown as `XXXX-XXXX`. They are compared without case or the dash.

### `POST /v1/pair`

Trades a pairing code for the device token. After this call, the Mac holds the credential for everything under
`/v1/device`.

**Request**

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `code` | body | string | yes | The code from `POST /v1/pair/start`. |
| `deviceName` | body | string | no | A name for the Mac, at most 60 characters. It overrides the name given at the start. |

**Example request**

```sh
curl -s -X POST "$RELAY/v1/pair" \
  -H "Content-Type: application/json" \
  -d '{"code":"K7QM-2XPD","deviceName":"Studio Mac"}'
```

**Example response**

```json
{
  "deviceId": "a1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718",
  "deviceToken": "hrd_..."
}
```

**Errors**

| Status | When |
|---|---|
| `403` | The code is wrong, used or expired (`bad_code`). |
| `429` | This address entered 10 wrong codes in 10 minutes (`rate_limited`). |

**Notes**

- A Mac that pairs again under the same name replaces its earlier entry, with its mailbox, keys and audio. This
  is how a reinstall or a redeploy leaves no dead entry behind.

### `GET /v1/device/stream`

Opens the WebSocket that Herald keeps open to receive notifications and consent requests. It is the only way
notifications reach the Mac, and it is outgoing from the Mac, so the Mac listens on no port. The relay allows one
stream per Mac: a newer connection closes the older one.

**Request**

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `Authorization` | header | string | yes | `Bearer` and the device token. |
| `Upgrade` | header | string | yes | `websocket`. |

**Example request**

```sh
curl -s -i "$RELAY/v1/device/stream" \
  -H "Authorization: Bearer $DEVICE_TOKEN" \
  -H "Connection: Upgrade" -H "Upgrade: websocket" \
  -H "Sec-WebSocket-Version: 13" -H "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ=="
```

**Example response**

The reply is `101 Switching Protocols`. The first message on the stream is `welcome`.

```json
{"type": "welcome", "ttlSeconds": 86400}
```

**Errors**

| Status | When |
|---|---|
| `426` | The request is not a WebSocket upgrade (`upgrade_required`). |

**Notes**

- On connect the relay sends `welcome`, then every notification that is queued and not yet acknowledged, then
  every open consent request.
- Every text message must be at most 16 KB. The relay ignores a larger one, or one that is not valid JSON.
- Herald sends the text `ping` every 5 minutes and the relay answers `pong` without waking its storage. The Mac
  counts as online while it has pinged or sent a message in the last 11 minutes.
- The relay closes a stream with code `4000` when a newer one replaces it, and `4001` when the Mac is unpaired.

Messages from the relay to Herald:

| `type` | Fields | Meaning |
|---|---|---|
| `welcome` | `ttlSeconds` | The connection is open. `ttlSeconds` is how long an undelivered notification waits. |
| `notify` | `id`, `notificationId`, `createdAt`, `key`, `payload` | A notification. `id` is the relay's `r_` id, `key` holds `id`, `name` and `client` of the sender, and `payload` is the validated notification. |
| `consent` | `id`, `clientId`, `clientName`, `redirectHost`, `scope`, `code`, `status`, `createdAt`, `expiresAt`, `flow` | A connector asks to be approved. `userCode` is added for the device flow, and `redelivered: true` when Herald already saw this one. |
| `consent_resolved` | `id`, `status` | A request was approved, denied, superseded or expired, so Herald can drop its banner. |

Messages from Herald to the relay:

| `type` | Fields | Meaning |
|---|---|---|
| `hello` | `quietActive`, `muted` | Sent on connect. The relay then resends everything not yet sent. |
| `status` | `quietActive`, `quietUntil`, `muted` | Sent when quiet hours or mute change. It is what `GET /v1/status` reports to agents. |
| `ack` | `id` | Herald has stored the notification with this relay id. The relay stops resending it. |
| `receipt` | `id`, `kind`, and fields by kind | A receipt, with the same fields as [`POST /v1/device/receipt`](#post-v1devicereceipt). |

### `POST /v1/device/receipt`

Reports what happened to a notification: shown, spoken, replied or held back. Herald sends this as it happens,
and the relay passes it to the agent through the receipt and reply endpoints, and to event subscriptions. The same
receipt can be sent as a `receipt` message on the stream.

**Request**

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `id` | body | string | yes | The relay's id from the `notify` message, `r_` and 24 hex characters. |
| `kind` | body | string | yes | `displayed`, `spoken`, `replied` or `suppressed`. |
| `text` | body | string | no | The typed reply, for `replied`. At most 4000 characters. |
| `transcript` | body | string | no | The on-device transcript, for `replied`. At most 4000 characters. |
| `durationSeconds` | body | number | no | The length of the voice reply, from 0 to 600. |
| `reason` | body | string | no | Why it was held back, for `suppressed`: 1 to 40 characters from `a-z 0-9 -`. Default `suppressed`. |
| `scope` | body | string | no | `speech` or `all`, for `suppressed`. Default `all`. |

**Example request**

```sh
curl -s -X POST "$RELAY/v1/device/receipt" \
  -H "Authorization: Bearer $DEVICE_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"id":"r_0123456789abcdef01234567","kind":"displayed"}'
```

**Example response**

```json
{"ok": true}
```

**Errors**

| Status | When |
|---|---|
| `400` | The body is not JSON, `kind` is unknown, or a `replied` receipt has no text, transcript or uploaded audio (`invalid_request`). |
| `404` | No notification has that id (`not_found`). |

**Notes**

- A receipt is recorded once. The first time stays: a second `displayed` does not move the time.
- The first `replied` receipt also queues the `notification.reply` event for the sender's subscriptions.

### `POST /v1/device/reply`

Reports the user's reply. It is the same as sending a `replied` receipt, and is the route Herald uses for the
**Reply** and **Record** buttons.

**Request**

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `id` | body | string | yes | The relay's `r_` id of the notification. |
| `text` | body | string | no | The typed reply. |
| `transcript` | body | string | no | The on-device transcript of a voice reply. |
| `durationSeconds` | body | number | no | The length of the voice reply, from 0 to 600. |

At least one of `text`, `transcript` or a prior audio upload is needed.

**Example request**

```sh
curl -s -X POST "$RELAY/v1/device/reply" \
  -H "Authorization: Bearer $DEVICE_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"id":"r_0123456789abcdef01234567","text":"Ship it."}'
```

**Example response**

```json
{"ok": true}
```

**Errors**

| Status | When |
|---|---|
| `400` | There is no text, transcript or uploaded audio, or the body is not JSON. |
| `404` | No notification has that id. |

### `PUT /v1/device/reply/{replyId}/audio`

Uploads the voice message of a reply. Herald uploads the audio first, then sends the reply with its transcript,
so the reply can point to the audio. The relay stores it in its audio bucket.

**Request**

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `replyId` | path | string | yes | The relay's `r_` id of the notification. |
| `Content-Type` | header | string | yes | `audio/mp4`, `audio/x-m4a` or `audio/aac`. |
| body | body | bytes | yes | The audio, at most 1 MB (1,048,576 bytes). |

**Example request**

```sh
curl -s -X PUT "$RELAY/v1/device/reply/r_0123456789abcdef01234567/audio" \
  -H "Authorization: Bearer $DEVICE_TOKEN" \
  -H "Content-Type: audio/mp4" \
  --data-binary @reply.m4a
```

**Example response**

```json
{"ok": true, "bytes": 53214}
```

**Errors**

| Status | When |
|---|---|
| `400` | The body is empty. |
| `404` | No notification has that id. |
| `413` | The audio is larger than 1 MB. |
| `415` | The content type is not an accepted audio type. |
| `429` | The daily voice reply count or byte allowance is used up (`daily_cap`). |

### `POST /v1/device/status`

Reports the Mac's quiet-hours and mute state. It is how `GET /v1/status` knows whether quiet hours are on. The
same information can travel as a `status` message on the stream, and it also marks the Mac as seen.

**Request**

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `quietActive` | body | boolean | no | `true` while quiet hours are on. |
| `quietUntil` | body | string | no | When quiet hours end, at most 40 characters. |
| `muted` | body | boolean | no | `true` while Herald is muted. |

**Example request**

```sh
curl -s -X POST "$RELAY/v1/device/status" \
  -H "Authorization: Bearer $DEVICE_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"quietActive":true,"quietUntil":"2026-10-03T07:00:00Z","muted":false}'
```

**Example response**

```json
{"ok": true}
```

**Errors**

| Status | When |
|---|---|
| `400` | The body is not JSON. |

### `GET /v1/device/info`

Returns a short summary of this Mac's mailbox.

**Request**

No parameters.

**Example request**

```sh
curl -s "$RELAY/v1/device/info" -H "Authorization: Bearer $DEVICE_TOKEN"
```

**Example response**

```json
{
  "online": true,
  "lastSeenAt": "2026-10-02T13:14:19.111Z",
  "pending": 0,
  "quietHours": {"active": false},
  "keys": 2
}
```

**Response fields**

| Field | Type | Description |
|---|---|---|
| `online` | boolean | `true` while the stream is open and the relay heard from it in the last 11 minutes. |
| `lastSeenAt` | string | When the relay last heard from the Mac. |
| `pending` | integer | How many notifications wait for the Mac. |
| `quietHours` | object | The reported quiet-hours state. |
| `keys` | integer | How many agent keys are active. |

### `GET /v1/device/usage`

Returns today's traffic against this Mac's limits. It is not counted toward the request budget.

**Request**

No parameters.

**Example request**

```sh
curl -s "$RELAY/v1/device/usage" -H "Authorization: Bearer $DEVICE_TOKEN"
```

**Example response**

```json
{
  "day": "2026-10-02",
  "requests": 120,
  "wsMessages": 40,
  "notifications": 18,
  "pollSeconds": 90,
  "audioUploads": 1,
  "audioBytes": 53214,
  "queued": 0,
  "storageBytes": 24576,
  "limits": {
    "audioUploadsPerDay": 40,
    "audioBytesPerDay": 20971520,
    "requestsPerDay": 5000,
    "freePlanRequestsPerDay": 100000,
    "notificationsPerDay": 500,
    "pollSecondsPerDay": 3000,
    "queueMax": 100
  },
  "requestsPercent": 2,
  "budgetExhausted": false
}
```

**Response fields**

| Field | Type | Description |
|---|---|---|
| `day` | string | The UTC date the counters cover. They reset at midnight UTC. |
| `requests` | integer | Requests that reached this mailbox today. |
| `wsMessages` | integer | Messages Herald sent on the stream. |
| `notifications` | integer | Notifications queued today. |
| `pollSeconds` | integer | Seconds of long polling used today. |
| `audioUploads` | integer | Voice replies uploaded today. |
| `audioBytes` | integer | Bytes of voice replies uploaded today. |
| `queued` | integer | Notifications waiting for the Mac. |
| `storageBytes` | integer | The size of this mailbox's storage. |
| `limits` | object | The limits in force for this Mac. `freePlanRequestsPerDay` is Cloudflare's free-plan figure, not a relay limit. |
| `requestsPercent` | integer | `requests` as a percent of `requestsPerDay`. |
| `budgetExhausted` | boolean | `true` when `requests` has reached `requestsPerDay`. |

### `GET /v1/device/keys`

Lists the agent keys and connector approvals of this Mac, including revoked ones. It never returns a secret.

**Request**

No parameters.

**Example request**

```sh
curl -s "$RELAY/v1/device/keys" -H "Authorization: Bearer $DEVICE_TOKEN"
```

**Example response**

```json
{
  "keys": [
    {
      "id": "0a1b2c3d",
      "name": "build-bot",
      "client": "claude",
      "scope": "notify",
      "kind": "static",
      "createdAt": "2026-10-01T09:30:00.000Z",
      "lastUsedAt": "2026-10-02T13:00:04.000Z"
    },
    {
      "id": "4e5f6a7b",
      "name": "chatgpt",
      "client": "other",
      "scope": "notify",
      "kind": "oauth",
      "displayName": "ChatGPT",
      "createdAt": "2026-10-02T08:00:00.000Z"
    }
  ]
}
```

**Response fields**

| Field | Type | Description |
|---|---|---|
| `id` | string | The key id: 8 hex characters. |
| `name` | string | The key's name. |
| `client` | string | `claude`, `codex` or `other`. |
| `scope` | string | Always `notify`. |
| `kind` | string | `static` for a key made here, `oauth` for a connector. |
| `displayName` | string | The client's own name, for a connector. |
| `createdAt` | string | When it was made. |
| `lastUsedAt` | string | When it was last used. Updated at most every 10 minutes. |
| `revokedAt` | string | When it was revoked. Absent while it is active. |

### `POST /v1/device/keys`

Makes an agent key. The reply holds the key in full once. Only its hash is stored, so a lost key cannot be read
back and has to be replaced.

**Request**

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `name` | body | string | yes | 1 to 32 characters from `a-z 0-9 -`. The relay lowercases it. It must be unique among active keys. |
| `client` | body | string | no | `claude`, `codex` or `other`. Default `other`. |
| `scope` | body | string | no | Only `notify`. Default `notify`. |

**Example request**

```sh
curl -s -X POST "$RELAY/v1/device/keys" \
  -H "Authorization: Bearer $DEVICE_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"name":"build-bot","client":"claude"}'
```

**Example response**

The reply is `201`.

```json
{
  "id": "0a1b2c3d",
  "name": "build-bot",
  "client": "claude",
  "scope": "notify",
  "kind": "static",
  "key": "hrk_...",
  "createdAt": "2026-10-01T09:30:00.000Z"
}
```

**Errors**

| Status | When |
|---|---|
| `400` | The body is not JSON, or `name` or `client` is invalid. |
| `400` | A field other than `name`, `client` and `scope` is present (`forbidden_fields`). |
| `400` | The scope is not `notify` (`scope_not_allowed`). |
| `409` | An active key already has that name (`name_taken`). |
| `429` | The Mac already has 20 active keys (`too_many_keys`). |

### `DELETE /v1/device/keys/{keyId}`

Revokes an agent key or a connector approval. A revoked key stops working at once, and a connector's tokens and
event subscriptions end with it.

**Request**

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `keyId` | path | string | yes | The key's 8-character id. |
| `purge` | query | integer | no | `1` forgets the key entirely: its row, its tokens, what it sent and its subscriptions. Used for a throw-away test key. |

**Example request**

```sh
curl -s -X DELETE "$RELAY/v1/device/keys/0a1b2c3d" \
  -H "Authorization: Bearer $DEVICE_TOKEN"
```

**Example response**

```json
{"revoked": true, "id": "0a1b2c3d"}
```

**Errors**

| Status | When |
|---|---|
| `404` | There is no key with that id (`not_found`). |

### `GET /v1/device/consents`

Lists the connector approval requests of the last day, newest first, up to 20. Herald shows them under
**Connector approvals**.

**Request**

No parameters.

**Example request**

```sh
curl -s "$RELAY/v1/device/consents" -H "Authorization: Bearer $DEVICE_TOKEN"
```

**Example response**

```json
{
  "consents": [
    {
      "id": "a1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718aabbccddeeff001122334455",
      "clientId": "hc_3fa91c0de27b45a6d1180123456789ab",
      "clientName": "My cloud agent",
      "redirectHost": "agent.example.com",
      "scope": "notify",
      "code": "482913",
      "status": "pending",
      "createdAt": "2026-10-02T13:00:00.000Z",
      "expiresAt": "2026-10-02T13:10:00.000Z",
      "flow": "device",
      "userCode": "BDFG-HJKM"
    }
  ]
}
```

**Response fields**

| Field | Type | Description |
|---|---|---|
| `id` | string | The request id. |
| `clientId` | string | The client's id. |
| `clientName` | string | The name the client registered. |
| `redirectHost` | string | The host the browser returns to. Empty for the device flow. |
| `scope` | string | `notify`. |
| `code` | string | The 6-digit approval code for the web page. |
| `status` | string | `pending`, `approved`, `denied`, `superseded` or `expired`. |
| `flow` | string | `code` for the browser flow, `device` for the device flow. |
| `userCode` | string | The code the agent printed. Present only for the device flow. |

### `POST /v1/device/consent`

Approves or denies a connector request. Herald calls it when the user presses **Approve** or **Deny** on the
banner. It also closes the same client's open requests on every other paired Mac.

**Request**

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `id` | body | string | yes | The request id from `GET /v1/device/consents` or the `consent` message. |
| `decision` | body | string | yes | `approve` or `deny`. |

**Example request**

```sh
curl -s -X POST "$RELAY/v1/device/consent" \
  -H "Authorization: Bearer $DEVICE_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"id":"a1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718aabbccddeeff001122334455","decision":"approve"}'
```

**Example response**

```json
{"status": "approved"}
```

**Errors**

| Status | When |
|---|---|
| `400` | `id` or `decision` is missing or invalid. |
| `404` | No request has that id. |
| `409` | The request was already decided (`already_decided`). |
| `410` | The request expired (`expired`). |
| `429` | The Mac already has 20 active keys (`too_many_keys`). |

**Notes**

- For the browser flow the reply also holds `redirect`, the address the user's browser is sent to.

### `GET /v1/device/events`

Lists the reply-event subscriptions on this Mac. Herald shows them under **Reply subscriptions**.

**Request**

No parameters.

**Example request**

```sh
curl -s "$RELAY/v1/device/events" -H "Authorization: Bearer $DEVICE_TOKEN"
```

**Example response**

```json
{
  "restrictedTo": [],
  "subscriptions": [
    {
      "id": "sub_3fa91c0de27b45a6d118",
      "event": "notification.reply",
      "host": "agent.example.com",
      "key": {"id": "4e5f6a7b", "name": "chatgpt", "displayName": "ChatGPT"},
      "createdAt": "2026-10-02T08:05:00.000Z",
      "pending": 0
    }
  ]
}
```

**Response fields**

| Field | Type | Description |
|---|---|---|
| `restrictedTo` | array | The host names the relay allows callbacks to. Empty means any public host. |
| `subscriptions` | array | One entry per subscription. |
| `subscriptions[].host` | string | The callback host. The path and the secret are never shown. |
| `subscriptions[].pending` | integer | How many events wait to be delivered. |

### `DELETE /v1/device/events/subscriptions/{subscriptionId}`

Ends a reply-event subscription. Use it when the user presses **End** next to a subscription.

**Request**

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `subscriptionId` | path | string | yes | The id: `sub_` and 20 hex characters. |

**Example request**

```sh
curl -s -X DELETE "$RELAY/v1/device/events/subscriptions/sub_3fa91c0de27b45a6d118" \
  -H "Authorization: Bearer $DEVICE_TOKEN"
```

**Example response**

```json
{"removed": true, "id": "sub_3fa91c0de27b45a6d118"}
```

**Notes**

- The call succeeds when no such subscription exists. An id that is not shaped `sub_` and 20 hex characters is
  `404`.

### `GET /v1/device/devices`

Lists the Macs paired with this relay and says which of them this Mac may remove. A Mac is only allowed to remove
entries that cannot be in active use.

**Request**

No parameters.

**Example request**

```sh
curl -s "$RELAY/v1/device/devices" -H "Authorization: Bearer $DEVICE_TOKEN"
```

**Example response**

```json
{
  "removed": [],
  "devices": [
    {
      "id": "a1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718",
      "name": "Studio Mac",
      "online": true,
      "lastSeenAt": "2026-10-02T13:14:19.137Z",
      "createdAt": "2026-10-01T09:00:00.000Z",
      "thisDevice": true,
      "removable": false
    }
  ]
}
```

**Response fields**

| Field | Type | Description |
|---|---|---|
| `id` | string | The Mac's id. |
| `name` | string | The name it paired under. |
| `online` | boolean | `true` while its stream is open. |
| `lastSeenAt` | string | When it was last seen. |
| `thisDevice` | boolean | `true` for the Mac making the request. |
| `removable` | boolean | `true` when this Mac may remove the entry. |
| `removableReason` | string | `same_name`, `credentials_rotated` or `idle` (no connection for 7 days). Present when `removable` is `true`. |

**Errors**

| Status | When |
|---|---|
| `404` | This Mac is not in the relay's registry. |

### `POST /v1/device/prune`

Removes this Mac's own stale siblings: other entries with the same name, entries whose credentials were rotated,
and entries not connected for 30 days. It never removes this Mac.

**Request**

No parameters.

**Example request**

```sh
curl -s -X POST "$RELAY/v1/device/prune" -H "Authorization: Bearer $DEVICE_TOKEN"
```

**Example response**

```json
{
  "removed": ["0f1e2d3c4b5a69788796a5b4c3d2e1f00f1e2d3c4b5a6978"],
  "devices": [
    {
      "id": "a1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718",
      "name": "Studio Mac",
      "online": true,
      "lastSeenAt": "2026-10-02T13:14:19.137Z",
      "createdAt": "2026-10-01T09:00:00.000Z",
      "thisDevice": true,
      "removable": false
    }
  ]
}
```

**Notes**

- `devices` is the list of Macs that remain, in the shape of [`GET /v1/device/devices`](#get-v1devicedevices).

### `DELETE /v1/device/devices/{deviceId}`

Removes one entry from the relay's list of Macs, with its mailbox. The relay refuses unless the entry is the same
name as this Mac, has rotated credentials, or has been idle for 7 days.

**Request**

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `deviceId` | path | string | yes | The 48-character id of the entry to remove. |

**Example request**

```sh
curl -s -X DELETE "$RELAY/v1/device/devices/0f1e2d3c4b5a69788796a5b4c3d2e1f00f1e2d3c4b5a6978" \
  -H "Authorization: Bearer $DEVICE_TOKEN"
```

**Example response**

```json
{"removed": ["0f1e2d3c4b5a69788796a5b4c3d2e1f00f1e2d3c4b5a6978"]}
```

**Errors**

| Status | When |
|---|---|
| `400` | The id is this Mac. Use `DELETE /v1/device` to unpair it (`invalid_request`). |
| `403` | The entry is a different, active Mac (`not_removable`). |
| `404` | No such entry. |

### `DELETE /v1/device`

Unpairs this Mac. The relay closes the stream, deletes the mailbox (the queue, the keys, the approvals and the
subscriptions) and the stored voice replies, and forgets the device token. Every agent key stops working.

**Request**

No parameters.

**Example request**

```sh
curl -s -X DELETE "$RELAY/v1/device" -H "Authorization: Bearer $DEVICE_TOKEN"
```

**Example response**

```json
{"unpaired": true}
```

> [!WARNING]
> Unpairing deletes the relay's copy of everything for this Mac and cannot be undone. Agents must be given new
> keys after the Mac pairs again.

## Limits and error codes

The limits protect each Mac from the others, and the relay from running past Cloudflare's free plan. Every
paired Mac has its own mailbox, so every counter is **per device**, never shared: one noisy Mac or key cannot use
up another Mac's allowance. A relay's owner can change most limits with a Worker variable, in `wrangler.toml`
under `[vars]` or with `--var NAME:value`. A variable is used only when it is a positive number; otherwise the
default applies.

### Limits

Per device. Counters that reset daily reset at midnight UTC.

| Limit | Default | Worker variable | When it is reached |
|---|---|---|---|
| Notifications per day | 500 | `DEVICE_NOTIFICATIONS_PER_DAY` | `429 daily_cap` on `POST /v1/notify`, with `Retry-After` until midnight. |
| Undelivered notifications waiting | 100 | `DEVICE_QUEUE_MAX` | `429 queue_full` on `POST /v1/notify`. |
| Time an undelivered notification waits | 24 hours | `QUEUE_TTL_HOURS` | The notification gets a `suppressed` receipt with reason `expired`. |
| Agent requests per day | 5000 | `DEVICE_REQUESTS_PER_DAY` | `503 budget_exhausted` on agent routes, with `Retry-After` until midnight. The Mac can still connect and collect its queue. |
| Voice replies per day | 40 | `DEVICE_AUDIO_UPLOADS_PER_DAY` | `429 daily_cap` on the audio upload. |
| Voice reply bytes per day | 20 MB | `DEVICE_AUDIO_BYTES_PER_DAY` | `429 daily_cap` on the audio upload. |
| Long-poll seconds per day | 3000 | `DEVICE_POLL_SECONDS_PER_DAY` | A `wait` is treated as `0`, so the relay answers at once. |
| Notify request size | 32 KB | `MAX_BODY_BYTES` | `413 too_large`. A `data:` icon may add up to 256 KB. |
| Active agent keys | 20 | none | `429 too_many_keys` when a key or approval is made. |

Per key.

| Limit | Default | Worker variable | When it is reached |
|---|---|---|---|
| Notifications per 10 minutes | 60 | `RATE_LIMIT_PER_KEY` | `429 rate_limited` with `retryAfterSeconds` and `Retry-After`. |
| Receipt and reply reads per 10 minutes | 600 | none | `429 rate_limited` with `retryAfterSeconds: 60`. |
| Event subscriptions per connector | 5 | none | `-32602` on `events/subscribe`. |
| Pending connector approvals per Mac | 3 | none | `429 rate_limited` (an error page, or `slow_down` on the device flow). |
| Connector approvals begun per hour | 12 | none | `429 rate_limited`. |

Per address and per relay.

| Limit | Default | Worker variable | When it is reached |
|---|---|---|---|
| Macs that may pair | 5 | `MAX_DEVICES` | `403 device_limit` on `POST /v1/pair/start`. |
| Pairing starts per address per hour | 6 | `PAIR_STARTS_PER_HOUR` | `429 rate_limited`. |
| Pairing starts per hour, all addresses | 300 | `PAIR_STARTS_GLOBAL_PER_HOUR` | `429 rate_limited`. |
| Wrong pairing codes per address per 10 minutes | 10 | none | `429 rate_limited` on `POST /v1/pair`. |
| Pairing codes waiting | 3 per address, 60 in all | none | `429 rate_limited` on `POST /v1/pair/start`. |
| Client registrations per hour | 30 | `REGISTER_PER_HOUR` | `429 rate_limited` on `POST /register`. |

The client address is hashed before it is compared and is never stored in the clear.

Other fixed values:

| Value | Fixed at |
|---|---|
| Pairing code lifetime | 10 minutes, single use. |
| Browser approval request lifetime | 10 minutes. |
| Device approval request lifetime | 10 minutes. |
| Time to exchange an approved code | 5 minutes. |
| Device flow poll interval | 5 seconds. |
| Voice reply audio | 1 MB each. |
| Signed audio link | 3600 seconds. |
| Stored voice reply | 7 days. |
| Notification ids | Kept 24 hours. |
| Idle Mac removed by the relay | 30 days without a connection. |

Two secrets and one list control access rather than limits.

| Setting | Purpose |
|---|---|
| Secret `RELAY_SECRET` | Required. It signs device ids so strangers cannot create mailboxes. |
| Secret `PAIRING_SECRET` | Optional. When set, `POST /v1/pair/start` needs it in `X-Pairing-Secret`. |
| Variable `EVENT_CALLBACK_HOSTS` | Optional, comma-separated. Limits the hosts an event subscription may call. |

### Error codes

Every error reply from a relay route has a JSON body with an `error` code and a `message`. Where it helps, it adds one more field:

- `fields` lists the rejected fields.
- `retryAfterSeconds` says how long to wait. A `Retry-After` header carries the same value.

Two families use another format:

- The OAuth routes use the OAuth error format, `error` and `error_description`. The [token errors](#post-token) are listed with that route.
- MCP errors are JSON-RPC errors, listed under [JSON-RPC errors](#json-rpc-errors).

| Code | Status | Meaning |
|---|---|---|
| `invalid_request` | `400` | The body is not valid JSON or a value is invalid. `fields` names the field. |
| `forbidden_fields` | `400` | The body holds a field the relay does not accept. `fields` lists it. |
| `scope_not_allowed` | `400` | A key was asked for with a scope other than `notify`. |
| `unauthorized` | `401` | The credential is missing, malformed, revoked or unknown. |
| `wrong_credential` | `403` | An agent key or access token was used on a device route, or the device token on an agent route. |
| `scope` | `403` | The key has no `notify` scope. |
| `forbidden` | `403` | A signed audio link has a bad signature. |
| `device_limit` | `403` | The relay already has its maximum number of paired Macs. |
| `bad_code` | `403` | A pairing code is wrong, used or expired. |
| `not_removable` | `403` | One Mac tried to remove another Mac that is active, a different name and has valid credentials. |
| `not_found` | `404` | The route, notification, key or entry does not exist. Notification ids are kept 24 hours. |
| `name_taken` | `409` | An active key already has that name. |
| `already_decided` | `409` | A connector request was already approved, denied or expired. |
| `expired` | `410` | A connector request or a signed audio link has expired. |
| `too_large` | `413` | A request or an audio upload is over its size limit. |
| `unsupported_media_type` | `415` | An audio upload is not `audio/mp4`, `audio/x-m4a` or `audio/aac`. |
| `upgrade_required` | `426` | The stream route was called without a WebSocket upgrade. |
| `rate_limited` | `429` | A per-key, per-address or approval rate limit was reached. See `retryAfterSeconds`. |
| `daily_cap` | `429` | The Mac's daily notification, voice reply count or voice reply byte allowance is used up. |
| `queue_full` | `429` | The Mac has too many undelivered notifications waiting. It has been offline too long. |
| `too_many_keys` | `429` | The Mac already has 20 active keys or approvals. |
| `internal` | `500` | The relay failed unexpectedly. |
| `misconfigured` | `500` | The relay has no `RELAY_SECRET`. |
| `budget_exhausted` | `503` | The Mac's daily request budget on the relay is used up. Nothing queued is lost. Retry after `retryAfterSeconds`. |

> [!NOTE]
> When a limit is reached, nothing is lost silently. The queue lives in the Mac's mailbox, and notifications are
> delivered when the Mac reconnects. A notification older than the queue time gets a `suppressed` receipt with
> reason `expired`.

## Related

- [Cloud relay](../CLOUD.md): what the relay is and how to set it up.
- [How the relay works](../cloud/how-it-works.md): architecture, security and limits in prose.
- [Connect an agent](../cloud/connect-agent.md): make an agent key and use it.
- [Connect ChatGPT](../cloud/connect-chatgpt.md): approve a connector with OAuth.
- [Device flow](../cloud/device-flow.md): connect an agent that has no browser.
- [Reply events](../cloud/reply-events.md): be told when the user replies.
- [Cloud relay API (local)](api/relay.md): the routes on Herald's own API that manage the relay from the Mac.
- [Relay MCP tools](mcp/relay.md): the local MCP tools that manage the relay.
