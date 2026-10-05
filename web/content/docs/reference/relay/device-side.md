# Device side

These are the routes Herald itself uses on a paired Mac: the stream that delivers notifications, the receipts and
replies it sends back, the agent keys and connector approvals it manages, and the reply subscriptions it lists.
You need this page to implement a relay or a compatible client, or to script what **Settings > Cloud** does. A
cloud agent never calls these routes. Pairing, the list of Macs, and the mailbox summary, usage and status routes
are on [Pairing and devices](pairing-and-devices.md).

Every route here needs the device token that [`POST /v1/pair`](pairing-and-devices.md#post-v1pair) returns. Examples
use `$RELAY` from the [relay API overview](README.md) and a variable for the device token.

```sh
RELAY="https://herald-relay.example.workers.dev"
DEVICE_TOKEN="hrd_..."
```

## Concepts

**One credential.** A device route accepts only the device token. An agent key or access token gets
`403 wrong_credential`. A missing, malformed or unknown token gets `401 unauthorized`. A path under `/v1/device`
that no route matches gets `404 not_found` with the message `no such device endpoint`. That includes a path
parameter in the wrong shape and a known path with the wrong method.

**Receipts.** A notification has a lifecycle on the Mac: it is shown, spoken, answered or held back. Herald reports
each step as a receipt, over the stream or with [`POST /v1/device/receipt`](#post-v1devicereceipt), and the relay
shows it to the agent that sent the notification. A notification has two ids. The agent's own `notificationId`
names it for the agent. The relay's `r_` id, 24 hex characters after the prefix, names it for Herald. Every route
on this page that takes `id` takes the relay's id.

**Connectors.** An agent that connects with OAuth or the device flow does not hold a key you made. It asks to be
approved, and Herald shows a banner. The request reaches Herald as a `consent` message on the stream and in the
[list of approval requests](#get-v1deviceconsents). Pressing **Approve** or **Deny** sends
[the decision](#post-v1deviceconsent). An approved connector appears in the [list of keys](#get-v1devicekeys)
with the kind `oauth`.

## Endpoints

| Endpoint | Purpose |
|---|---|
| [`GET /v1/device/stream`](#get-v1devicestream) | Open the WebSocket that delivers notifications. |
| [`POST /v1/device/receipt`](#post-v1devicereceipt) | Report what happened to a notification. |
| [`POST /v1/device/reply`](#post-v1devicereply) | Report the user's reply. |
| [`PUT /v1/device/reply/{replyId}/audio`](#put-v1devicereplyreplyidaudio) | Upload the voice message of a reply. |
| [`GET /v1/device/keys`](#get-v1devicekeys) | List agent keys and connector approvals. |
| [`POST /v1/device/keys`](#post-v1devicekeys) | Make an agent key. |
| [`DELETE /v1/device/keys/{keyId}`](#delete-v1devicekeyskeyid) | Revoke a key or an approval. |
| [`GET /v1/device/consents`](#get-v1deviceconsents) | List connector approval requests. |
| [`POST /v1/device/consent`](#post-v1deviceconsent) | Approve or deny a connector request. |
| [`GET /v1/device/events`](#get-v1deviceevents) | List reply subscriptions. |
| [`DELETE /v1/device/events/subscriptions/{subscriptionId}`](#delete-v1deviceeventssubscriptionssubscriptionid) | End a reply subscription. |

### `GET /v1/device/stream`

Opens the WebSocket that Herald keeps open to receive notifications and connector requests. It is the only way
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

- On connect the relay sends `welcome`, then every notification that is waiting and not yet acknowledged, then
  every open connector request.
- `ttlSeconds` is how long an undelivered notification waits. It is `86400` unless the relay's owner changed
  `QUEUE_TTL_HOURS`.
- Every text message must be at most 16 KB. The relay ignores a larger one, a binary one, or one that is not valid
  JSON, and sends no error.
- Herald sends the text `ping` every 300 seconds and the relay answers `pong` without waking its storage. The Mac
  counts as online while it has pinged or sent a message in the last 11 minutes.
- The relay closes a stream with code `4000` when a newer one takes its place, and `4001` when the Mac is unpaired.
- Opening the stream does not count toward the daily request budget. Each message Herald sends counts toward
  `wsMessages` in [`GET /v1/device/usage`](pairing-and-devices.md#get-v1deviceusage).

Messages from the relay to Herald:

| `type` | Fields | Meaning |
|---|---|---|
| `welcome` | `ttlSeconds` | The connection is open. |
| `notify` | `id`, `notificationId`, `createdAt`, `key`, `payload` | A notification. `id` is the relay's `r_` id. `key` holds `id`, `name` and `client` of the sender. `payload` is the validated notification. |
| `consent` | `id`, `clientId`, `clientName`, `redirectHost`, `scope`, `code`, `status`, `createdAt`, `expiresAt`, `flow` | A connector asks to be approved. The fields are the ones of [`GET /v1/device/consents`](#get-v1deviceconsents). `redelivered` is `true` when Herald already saw this request. |
| `consent_resolved` | `id`, `status` | A request was approved, denied, superseded or expired, so Herald can drop its banner. |

A `consent` message with `redelivered` set is sent on a reconnect for a request Herald already showed. Herald
updates its list and shows no new banner. A request that arrived while Herald was away is sent once without the
flag. When the same client asks again, the relay reuses the request and sends a fresh `consent` message with the
new code, without the flag.

Messages from Herald to the relay:

| `type` | Fields | Meaning |
|---|---|---|
| `hello` | `quietActive`, `quietUntil`, `muted` | Sent on connect. It stores the state and sends any notification that was never sent. |
| `status` | `quietActive`, `quietUntil`, `muted` | Sent when quiet hours or mute change. It is what [`GET /v1/status`](agent.md#get-v1status) reports to agents. |
| `ack` | `id` | Herald has stored the notification with this relay id. The relay stops resending it. |
| `receipt` | `id`, `kind`, and fields by kind | A receipt, with the fields of [`POST /v1/device/receipt`](#post-v1devicereceipt). An invalid receipt is ignored without an error. |

### `POST /v1/device/receipt`

Reports what happened to a notification: shown, spoken, replied or held back. Herald sends this as it happens,
and the relay passes it to the agent through the receipt and reply endpoints, and to reply subscriptions. The same
receipt can be sent as a `receipt` message on the stream.

**Request**

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `id` | body | string | yes | The relay's id from the `notify` message: `r_` and 24 hex characters. |
| `kind` | body | string | yes | `displayed`, `spoken`, `replied` or `suppressed`. |
| `text` | body | string | no | The typed reply, for `replied`. The relay trims it and keeps the first 4000 characters. |
| `transcript` | body | string | no | The on-device transcript, for `replied`. The relay trims it and keeps the first 4000 characters. |
| `durationSeconds` | body | number | no | The length of the voice reply, from 0 to 600. A value outside that range is ignored. |

`reason` and `scope` apply to `suppressed`:

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `reason` | body | string | no | Why it was held back: 1 to 40 characters from `a-z 0-9 -`. Any other value is stored as `suppressed`. Default `suppressed`. |
| `scope` | body | string | no | `speech` or `all`. Any other value is stored as `all`. Default `all`. |

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

- A `displayed`, `spoken` or `replied` receipt is recorded once. The first time stays: a second `displayed` does
  not move the time, and a second reply does not change the stored text.
- A `suppressed` receipt is not kept once. A later one overwrites the stored reason and scope.
- Every receipt marks the notification as received by the Mac, so the relay stops resending it.
- The first `replied` receipt also queues the `notification.reply` event for the sender's subscriptions. The
  event kind is `text` when the receipt has `text` and `voice` otherwise.
- The field `notificationId` is accepted in place of `id`, and it must still hold the relay's `r_` id.
- A `suppressed` receipt with the scope `all` ends a waiting
  [`GET /v1/replies/{notificationId}`](agent.md#get-v1repliesnotificationid). With the scope `speech` the wait
  continues.

### `POST /v1/device/reply`

Reports the user's reply. It is the same as sending a `replied` receipt, and it is the route Herald uses for the
**Reply** and **Record** buttons.

**Request**

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `id` | body | string | yes | The relay's `r_` id of the notification. |
| `text` | body | string | no | The typed reply. |
| `transcript` | body | string | no | The on-device transcript of a voice reply. |
| `durationSeconds` | body | number | no | The length of the voice reply, from 0 to 600. |

At least one of `text`, `transcript` or a prior audio upload is needed. Limits and trimming are those of
[`POST /v1/device/receipt`](#post-v1devicereceipt).

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
| `400` | There is no text, transcript or uploaded audio, or the body is not JSON (`invalid_request`). |
| `404` | No notification has that id (`not_found`). |

### `PUT /v1/device/reply/{replyId}/audio`

Uploads the voice message of a reply. Herald uploads the audio first, then sends the reply with its transcript, so
the reply can point to the audio. The relay stores the audio in its audio bucket, and the agent downloads it with
a signed link from the receipt or reply.

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
| `400` | The body is empty (`invalid_request`). |
| `404` | No notification has that id (`not_found`). |
| `413` | The audio is larger than 1 MB (`too_large`). |
| `415` | The content type is not an accepted audio type (`unsupported_media_type`). |
| `429` | The daily voice reply count or byte allowance is used up (`daily_cap`). |

**Notes**

- A `replyId` that is not `r_` and 24 hex characters does not match this route and gets `404 not_found` with the
  message `no such device endpoint`.
- The relay checks the declared length, the daily count, the body size, the daily bytes and the content type, in
  that order. A `429` carries `retryAfterSeconds` and a `Retry-After` header that run to midnight UTC.
- A second upload for the same notification takes the place of the first.
- The relay keeps stored audio for 7 days.

### `GET /v1/device/keys`

Lists the agent keys and connector approvals of this Mac, including revoked ones, oldest first. It never returns a
secret.

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
| `name` | string | The key's name. A connector gets a name made from its client name, such as `chatgpt`. |
| `client` | string | `claude`, `codex` or `other`. A connector is always `other`. |
| `scope` | string | Always `notify`. |
| `kind` | string | `static` for a key made with `POST /v1/device/keys`, `oauth` for a connector. |
| `displayName` | string | The client's own name, for a connector. |
| `createdAt` | string | When it was made. |
| `lastUsedAt` | string | When it was last used. Absent until first use. The relay updates it at most every 10 minutes. |
| `revokedAt` | string | When it was revoked. Absent while it is active. |

### `POST /v1/device/keys`

Makes an agent key. The reply holds the key in full once. Only its hash is stored, so a lost key cannot be read
back and has to be replaced.

**Request**

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `name` | body | string | yes | 1 to 32 characters from `a-z 0-9 -`, starting with a letter or digit. The relay trims and lowercases it. It must be unique among active keys. |
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
| `400` | The body is not JSON, or `name` or `client` is invalid (`invalid_request`). |
| `400` | A field other than `name`, `client` and `scope` is present (`forbidden_fields`). The reply lists them in `fields`. |
| `400` | The scope is not `notify` (`scope_not_allowed`). |
| `409` | An active key already has that name (`name_taken`). |
| `429` | The Mac already has 20 active keys and approvals (`too_many_keys`). |

**Notes**

- A key sends notifications and reads what it sent. It carries no other scope, and the relay refuses to make one.
- A revoked key does not hold its name, so the name can be used again.
- The 20-key limit counts connector approvals as well as keys.

### `DELETE /v1/device/keys/{keyId}`

Revokes an agent key or a connector approval. A revoked key stops working at once, and a connector's tokens and
reply subscriptions end with it. The key stays in the list with a `revokedAt` time.

**Request**

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `keyId` | path | string | yes | The key's 8-character id. |
| `purge` | query | integer | no | `1` forgets the key entirely: its row, its tokens, the notifications it sent and its subscriptions. Herald uses it for the throw-away key of its relay test. |

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

**Notes**

- With `purge=1` the reply also holds `"purged": true`, and the key is not in the list.
- Revoking a key that is already revoked succeeds and changes nothing.
- A key id that is not 8 hex characters does not match this route and gets `404 not_found` with the message
  `no such device endpoint`.

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
      "redirectHost": "",
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
| `id` | string | The request id: the device id and 24 hex characters. |
| `clientId` | string | The client's id. |
| `clientName` | string | The name the client registered. |
| `redirectHost` | string | The host the browser returns to. Empty for the device flow. |
| `scope` | string | Always `notify`. |
| `code` | string | The 6-digit approval code. |
| `status` | string | `pending`, `approved`, `denied` or `superseded`. |
| `createdAt` | string | When the request began. |
| `expiresAt` | string | When the request runs out. |
| `flow` | string | `code` for the browser flow, `device` for the device flow. |
| `userCode` | string | The code the agent printed. Present only for the device flow. |

**Notes**

- A pending request that has run out is deleted when the Mac reads the list, so `expired` is never listed. It
  reaches Herald as a `consent_resolved` message.
- `superseded` means the same client asked again, or another Mac decided the request.

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
  -H "Authorization: Bearer $DEVICE_TOKEN" -H "Content-Type: application/json" \
  -d '{"id":"a1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718aabbccddeeff001122334455","decision":"approve"}'
```

**Example response**

```json
{"status": "approved"}
```

**Response fields**

| Field | Type | Description |
|---|---|---|
| `status` | string | `approved` or `denied`. |
| `redirect` | string | The address the user's browser is sent to. Present for the browser flow only. |

**Errors**

| Status | When |
|---|---|
| `400` | `id` or `decision` is missing or invalid, or the body is not JSON (`invalid_request`). |
| `404` | No request has that id (`not_found`). |
| `409` | The request was already decided (`already_decided`). The reply holds its `status`. |
| `410` | The request expired (`expired`). |
| `429` | An approval would make more than 20 active keys (`too_many_keys`). |

**Notes**

- Approving makes one connector key for the client. If the same client was approved before, the earlier key is
  revoked first, so a client holds one key at a time.
- Denying revokes nothing that already works.
- Both decisions send a `consent_resolved` message on the stream.
- For the browser flow the `redirect` of an approval carries the one-time code, and the `redirect` of a denial
  carries `error=access_denied`. See [OAuth](oauth.md#get-authorize).

### `GET /v1/device/events`

Lists the reply subscriptions on this Mac. Herald shows them under **Reply subscriptions**.

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
| `restrictedTo` | array | The host names the relay allows callbacks to. Empty means any public https host. |
| `subscriptions` | array | One entry per subscription, oldest first. |
| `subscriptions[].id` | string | The subscription id: `sub_` and 20 hex characters. |
| `subscriptions[].event` | string | The event name, always `notification.reply`. |
| `subscriptions[].host` | string | The callback host name. The path, the port and the secret are never shown. |
| `subscriptions[].key` | object | The connector or key that subscribed: `id`, `name` and, for a connector, `displayName`. |
| `subscriptions[].createdAt` | string | When it was made. |
| `subscriptions[].pending` | integer | How many events wait to be delivered. |

**Notes**

- `restrictedTo` lists the hosts in the relay's `EVENT_CALLBACK_HOSTS` variable. The relay's owner sets that
  variable. When it is empty, callbacks may go to any public https host.
- Subscriptions do not lapse. They end when the agent unsubscribes, when the connector is revoked, or when you end
  one. See [MCP Events](events.md).

### `DELETE /v1/device/events/subscriptions/{subscriptionId}`

Ends a reply subscription and drops the events still waiting for it. Use it when the user presses **End** next to
a subscription.

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

**Errors**

| Status | When |
|---|---|
| `404` | The id is not `sub_` and 20 hex characters (`not_found`, message `no such device endpoint`). |

**Notes**

- The call succeeds when no subscription has that id.
- The connector keeps its approval and can subscribe again.

## Related

- [Pairing and devices](pairing-and-devices.md): pair a Mac, manage the Macs, read the mailbox summary and usage.
- [Agent endpoints](agent.md): what an agent sees of the receipts and replies reported here.
- [OAuth](oauth.md) and [Device flow](device-flow.md): how a connector reaches the approval request.
- [MCP Events](events.md): the subscriptions listed here.
- [Limits and errors](limits-and-errors.md): every limit and error code.
- [Cloud relay](../../CLOUD.md): the relay in **Settings > Cloud**.
- [Reply events](../../cloud/reply-events.md): be told when the user replies.
