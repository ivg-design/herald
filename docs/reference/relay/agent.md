# Agent endpoints

These are the plain HTTPS routes a cloud agent uses to reach a user's Mac through the relay: queue a notification,
read what happened to it, wait for the user's answer, and ask whether the Mac is reachable. Read this page if you
are writing an agent or an integration that talks to the relay without MCP. Every route except `/health` and the
signed audio links needs the agent's credential. The same four actions are also offered as [MCP tools](mcp.md).

All examples use two variables. `$RELAY` is the relay's origin and `$KEY` is the credential the agent holds.

```sh
RELAY="https://herald-relay.example.workers.dev"
KEY="hrk_..."
```

## Before you start

- You hold an agent key (`hrk_...`) or a connector access token (`hra_...`). Both are sent as
  `Authorization: Bearer $KEY`. See [Relay API](README.md) for how credentials are made and how they differ.
- Send a custom `User-Agent` header, as the examples do. On a relay without a custom domain, Cloudflare's Browser
  Integrity Check can reject a default library agent before the request reaches the relay.

## Concepts

An approved connector works until the user revokes it. Agent keys and access tokens never expire and are never
rotated, so an agent keeps one credential for as long as the user keeps it. A revoked key or token is refused
with `401` at once.

An agent sees only the notifications its own credential sent. Two keys, or a key and a connector, never see each
other's receipts or replies. A credential can send notifications and read what it sent. It cannot change a
setting, a quiet hour or anything else on the Mac.

A connector cannot send buttons, commands, scripts or any code. The relay accepts a fixed list of text and
presentation fields and refuses everything else, as [Forbidden fields](#forbidden-fields) shows.

| Endpoint | Purpose |
|---|---|
| [`POST /v1/notify`](#post-v1notify) | Queue a notification for the Mac. |
| [`GET /v1/receipts/{notificationId}`](#get-v1receiptsnotificationid) | Read what happened to a notification. |
| [`GET /v1/replies/{notificationId}`](#get-v1repliesnotificationid) | Read, or wait for, the user's reply. |
| [`GET /v1/status`](#get-v1status) | Ask whether the Mac is reachable. |
| [`GET /health`](#get-health) | Check that the relay is running. |
| [`GET /v1/audio/{deviceId}/{replyId}.m4a`](#get-v1audiodeviceidreplyidm4a) | Download a voice reply. |

## The receipt

A receipt is a set of separate facts, each set by whoever knows it. the notify call, the receipt read and the `get_receipt` and `send_notification` MCP tools all return this
object. A reply read from the replies endpoint shares its reply fields.

| Fact | Set by | Meaning |
|---|---|---|
| `received` | The relay. | The relay has the notification. It is always `true`. |
| `queued` | The relay. | The Mac has not yet acknowledged the notification and it is not suppressed. |
| `displayed` | Herald. | The banner was shown. |
| `spoken` | Herald. | Speech played to the end. It stays `false` when speech was muted, cut off or not asked for. |
| `replied` | Herald. | The user answered with text or a voice message. |
| `suppressed` | Herald, or the relay on expiry. | The notification was held back. |

**Response fields**

| Field | Type | Description |
|---|---|---|
| `notificationId` | string | The id of the notification. |
| `received` | boolean | Always `true`. |
| `receivedAt` | string | When the relay queued it, as an ISO 8601 time. |
| `queued` | boolean | `true` while the Mac has not acknowledged it. |
| `displayed` | boolean | `true` once the banner was shown. |
| `displayedAt` | string | When the banner was shown. Present only when `displayed` is `true`. |
| `spoken` | boolean | `true` once speech finished. |
| `spokenAt` | string | When speech finished. Present only when `spoken` is `true`. |
| `replied` | boolean | `true` once the user answered. |
| `repliedAt` | string | When the user answered. Present only when `replied` is `true`. |
| `reply` | string | The answer: the typed text, or the transcript of a voice reply. |
| `text` | string | The typed answer. Present only for a typed reply. |
| `transcript` | string | A transcript made on the user's Mac. It may be imperfect. |
| `transcriptNote` | string | A fixed sentence saying the transcript was made on the Mac and may be imperfect. |
| `audioUrl` | string | A signed link to the recorded voice reply. |
| `audioUrlExpiresInSeconds` | number | How long `audioUrl` stays valid: `3600`. A new read returns a new link. |
| `durationSeconds` | number | The length of the voice reply, when Herald reported it. |
| `expectReply` | boolean | Whether the notification was sent with `expectReply`. |
| `suppressed` | boolean | `true` when the notification was held back. |
| `reason` | string | Why it was held back. Present only when `suppressed` is `true`. |
| `suppressedScope` | string | `all` or `speech`. Present with `reason`. |

The reply fields (`repliedAt`, `reply`, `text`, `transcript`, `transcriptNote`, `audioUrl`,
`audioUrlExpiresInSeconds`, `durationSeconds`) are present only after the user has replied.

The `reason` values are:

| Reason | Set by | Meaning |
|---|---|---|
| `muted` | Herald | The user muted Herald. Scope `all`. |
| `quiet-hours` | Herald | Quiet hours were on. Scope `all` shows nothing. Scope `speech` shows the banner and holds only the speech. |
| `expired` | The relay | The Mac stayed offline for the whole queue time, 24 hours by default, so the relay dropped the notification. Scope `all`. |
| `delivery-failed` | Herald | Herald could not turn the notification into a banner. Scope `all`. |
| other | Herald | The relay stores any reason of 1 to 40 characters from `a-z`, `0-9` and `-`. It stores `suppressed` when Herald sends none. |

## Notifications

### `POST /v1/notify`

Queues a notification for the user's Mac and returns its receipt. The relay stores the notification until Herald
takes it, which is at once when the Mac is online. Use it to tell the user something, and set `expectReply` when
you want an answer.

The body carries text and presentation only. The relay checks it against a whitelist, and Herald checks the
notification again when it receives it.

**Request**

Only `title` is required. Every field goes in the JSON body. The text fields:

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `title` | body | string | yes | The headline, at most 200 characters. |
| `body` | body | string | no | The message text, at most 8000 characters. |
| `subtitle` | body | string | no | A second line under the title, at most 200 characters. |
| `status` | body | string | no | A short badge word such as `done` or `error`: letters, digits, `-` and `_`, at most 32 characters, stored in lower case. A label only. |
| `project` | body | string | no | The project name, at most 100 characters. |
| `session` | body | string | no | A session label, at most 100 characters. |
| `task` | body | string | no | A task label, at most 100 characters. |
| `tool` | body | string | no | The tool that produced the notification, at most 100 characters. |
| `duration` | body | string or number | no | How long the work took, for example `"2m 14s"`. A number is stored as its text. At most 40 characters. |
| `link` | body | string | no | An absolute `https` URL of at most 2048 characters. The banner offers it as an **Open link** button. |
| `notificationId` | body | string | no | Your own id: 1 to 128 characters from `A-Z`, `a-z`, `0-9`, `.`, `_`, `:` and `-`. The relay makes one when you leave it out. |
| `tags` | body | array of strings | no | Up to 10 labels of at most 32 characters with no commas. Duplicates are removed. |

The presentation fields. None of them can run or open anything.

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `priority` | body | string | no | `low`, `normal`, `high` or `urgent`. `urgent` breaks quiet hours only where the user allowed it. |
| `group` | body | string | no | Notifications with the same group stack together. At most 100 characters. |
| `persistent` | body | boolean | no | `true` keeps the banner until the user dismisses it. When omitted, the banner stays unless you set `timeoutSeconds`. |
| `timeoutSeconds` | body | number | no | From 1 to 3600. The banner dismisses itself after this many seconds. Herald ignores it when `persistent` is `true`. |
| `sound` | body | string | no | A system sound name such as `Glass`, `default` or `none`: up to 40 characters from `A-Z`, `a-z`, `0-9`, space, `.`, `_` and `-`. A file path is refused. |
| `presentation` | body | string | no | `banner`, `voice` or `both`. `voice` and `both` imply `speak: true`. |
| `icon` | body | string | no | The sender's icon: an `https` URL of at most 2048 characters, or a `data:image/png`, `jpeg`, `gif` or `webp` base64 image of at most 256 KB. |
| `imageURL` | body | string | no | An `https` URL of a preview image, at most 2048 characters. |

The speech fields. Herald speaks on the Mac, so these only choose what is said and how.

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `speak` | body | boolean, string or object | no | `true` speaks the title, then the body. A string of at most 2000 characters speaks that text. An object has `text`, `voice`, `speed` and `lang`. |
| `speak.voice` | body | string | no | A voice name such as `af_heart`: 1 to 40 letters, digits or `_`. |
| `speak.speed` | body | number | no | From 0.5 to 2. |
| `speak.lang` | body | string | no | A language code such as `en-us`. |
| `voice` | body | string | no | The same as `speak.voice`, beside `speak`. Setting it turns speaking on. |
| `speed` | body | number | no | The same as `speak.speed`, beside `speak`. Setting it turns speaking on. |

The reply fields:

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `expectReply` | body | boolean | no | `true` adds the **Reply** (text) and **Record** (voice) buttons. Nothing else about the banner changes. Default `false`. |
| `allowVoiceReply` | body | boolean | no | `false` hides the **Record** button on this notification. Default `true`. |

**Example request**

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

The reply is `202` for a new notification. It is the [receipt](#the-receipt) plus a `duplicate` flag.

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
| `duplicate` | boolean | `true` when this key already sent the same `notificationId` in the last 24 hours. |
| `notificationId` | string | Your id, or the one the relay made: `n_` and 24 hex characters. |
| other fields | various | The facts described in [The receipt](#the-receipt). |

**Errors**

Every error body has `error` and `message`. See [Limits and errors](limits-and-errors.md) for the shared errors.

| Status | When |
|---|---|
| `400` | The body is not JSON, is not an object, `title` is missing or a value is invalid. `error` is `invalid_request` and `fields` names the field. |
| `400` | The body holds a field that is not accepted. `error` is `forbidden_fields`. |
| `401` | The credential is missing, malformed, revoked or unknown (`unauthorized`). |
| `403` | The credential is the device token (`wrong_credential`), or has no notify scope (`scope`). |
| `413` | The body is larger than the limit (`too_large`). |
| `429` | This key sent too many in 10 minutes (`rate_limited`), the Mac's daily cap is reached (`daily_cap`), or the Mac's queue is full (`queue_full`). |
| `503` | The Mac's daily request budget on the relay is used up (`budget_exhausted`). |

**Notes**

- A notification with a `notificationId` that this key sent in the last 24 hours is not queued again. The relay
  answers `200` with the first notification's receipt and `duplicate: true`, so a retry is safe. A duplicate does
  not count toward the 60 per 10 minutes limit.
- The relay allows 60 notifications per 10 minutes per key. A `429` carries `retryAfterSeconds` and a
  `Retry-After` header, except `queue_full`, which carries neither.
- The body may be 32 KB. A `data:` icon is the one exception: it may add up to 256 KB, and everything else must
  still fit in 32 KB. An icon larger than 256 KB is a `400` that names `icon`.
- Speech turns on when `voice`, `speed`, or a `presentation` of `voice` or `both` is set.
  An explicit `speak: false` turns it off again, whatever else is set.
- Quiet hours and mute are enforced on the Mac, not by the relay. Read the receipt to see whether Herald held a
  notification back.
- `expectReply` does not change how the banner looks. Use `status` for a badge.
- The relay stores `group` and passes it on. Herald applies it on the Mac.
- The relay checks the credential, then the daily request budget, then the body, so a key with a spent budget
  gets `503` even for a body that is invalid.

#### Forbidden fields

A field outside the accepted list makes the whole request fail. Nothing is queued, and the error names every
rejected field. The error text calls out some names because they would run or open something on the Mac. Use
`link` for a URL and `imageURL` for a picture.

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

An unknown key inside a `speak` object is refused the same way and reported as `speak.<key>`.

## Receipts and replies

### `GET /v1/receipts/{notificationId}`

Returns what has happened to a notification this credential sent: whether the relay has it, whether the Mac
showed it, spoke it, got a reply, or held it back. Use it after sending to learn the outcome. To read the reply
itself, or to wait for it, use [`GET /v1/replies/{notificationId}`](#get-v1repliesnotificationid).

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

The fields are those of [The receipt](#the-receipt).

**Errors**

| Status | When |
|---|---|
| `401` | The credential is missing, malformed, revoked or unknown (`unauthorized`). |
| `403` | The credential is the device token (`wrong_credential`). |
| `404` | This credential sent no notification with that id in the last 24 hours (`not_found`). |
| `429` | The key made more than 600 receipt and reply reads in 10 minutes (`rate_limited`). |
| `503` | The Mac's daily request budget on the relay is used up (`budget_exhausted`). |

**Notes**

- The relay keeps an id for 24 hours. After that the receipt is gone and the same id can be sent again as a
  new notification.
- Receipt and reply reads share one limit of 600 per 10 minutes per key. A `429` carries `retryAfterSeconds: 60`
  and `Retry-After: 60`.

### `GET /v1/replies/{notificationId}`

Returns the user's reply to a notification and can wait for it. Use it when you sent `expectReply: true` and want
the answer. With `wait`, the relay holds the request open until the user answers or the time runs out, so you do
not have to poll.

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

A voice reply:

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

When no reply arrives within `wait`:

```json
{
  "notificationId": "build-214",
  "replied": false,
  "timedOut": true,
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
| reply fields | various | The reply, once there is one: see [The receipt](#the-receipt). |

**Errors**

| Status | When |
|---|---|
| `401` | The credential is missing, malformed, revoked or unknown (`unauthorized`). |
| `403` | The credential is the device token (`wrong_credential`). |
| `404` | This credential sent no notification with that id in the last 24 hours (`not_found`). |
| `429` | The key made more than 600 receipt and reply reads in 10 minutes (`rate_limited`). |
| `503` | The Mac's daily request budget on the relay is used up (`budget_exhausted`). |

**Notes**

- The answer is `200` in every case. A missing reply is `replied: false`, not an error.
- The request ends early when the user replies, or when the notification is suppressed with scope `all`,
  because no reply can follow.
- A request without `wait`, or with `wait=0`, never sets `timedOut`.
- While a request waits, the Mac's mailbox is awake and counts against the Mac's daily poll seconds, 3000 by
  default. When that allowance is spent, `wait` is treated as `0` and the relay answers at once.
- A typed answer is `text`. A voice answer has `transcript` and `audioUrl`. `reply` holds whichever exists.
- To be told when the user answers instead of polling, subscribe to the [reply event](events.md).

## Status and health

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
    "until": "2026-10-03T07:30:00Z"
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
| `401` | The credential is missing, malformed, revoked or unknown (`unauthorized`). |
| `403` | The credential is the device token (`wrong_credential`). |
| `503` | The Mac's daily request budget on the relay is used up (`budget_exhausted`). |

**Notes**

- Herald pings the relay every 5 minutes. `online` tolerates two missed pings.
- A status request counts toward the Mac's daily request budget but not toward the 600 reads limit.

### `GET /health`

Reports that the relay is running. It needs no credential and touches no storage, so a monitor can call it.

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
| `bundle` | string | The hash of the bundle that is running. Present only when the relay was deployed with a bundle hash. |

**Notes**

- `/healthz` answers the same way. `GET /` returns a small HTML page for a person who opened the address, and
  any other method on `/` returns this JSON.
- The reply is the same on every host name the relay answers on.

## Voice replies

### `GET /v1/audio/{deviceId}/{replyId}.m4a`

Downloads the voice message a user recorded as a reply. The `audioUrl` in a reply or receipt is this address with
its signature, so an agent does not build it by hand. The signed link is the credential: the route needs no
bearer token and works until the link expires.

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

The reply is the audio file itself, with no JSON body. These are its status line and headers.

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
| `410` | The link has expired, or `exp` is missing. Read the reply again for a new link (`expired`). |

**Notes**

- A link is valid for 3600 seconds from the read that made it.
- The audio is AAC in an m4a container, at most 1 MB. The relay keeps it for 7 days and deletes it earlier when
  the Mac unpairs.
- A link works only for its own clip. Changing the path invalidates the signature.

## Related

- [Relay API](README.md): credentials, token shapes and the error format.
- [MCP endpoint](mcp.md): the same four actions as MCP tools.
- [Events](events.md): be told when the user replies instead of polling.
- [Limits and errors](limits-and-errors.md): every limit and error code.
- [Cloud relay](../../CLOUD.md): what the relay is and how to set it up.
