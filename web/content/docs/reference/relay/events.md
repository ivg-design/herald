# Relay events

An agent that sends a notification with `expectReply` can be called back the moment the user answers, instead of
polling `wait_for_reply`. This page documents that mechanism, MCP Events on the relay: the four JSON-RPC methods an
agent calls on `/mcp`, and the signed webhook requests the relay then sends to the agent's server. It is for
people who build or run a cloud agent. The task-level view is in [Reply events](../../cloud/reply-events.md).

## Before you start

- You have a connector: an agent key or an OAuth access token the user approved in Herald. See
  [Relay API](README.md) for the credentials.
- Your client speaks MCP protocol `2026-07-28`. The events methods exist only in that protocol. A client on an
  older protocol gets `-32601` for them. See [`POST /mcp`](mcp.md#post-mcp) for how the two protocols differ.
- You run a server at a public `https` address that can receive a `POST`.

The examples use `$RELAY` for the relay's origin and `$KEY` for the connector's token, as defined in
[Relay API](README.md).

## Concepts

**One event.** The relay sends one event, `notification.reply`. It fires once per notification, the first time the
user answers it, typed or recorded. It goes only to the subscriptions of the connector that sent that
notification. Its payload holds ids and never the answer, so the answer travels only over the agent's own
authenticated connection: read it with `get_receipt` or `wait_for_reply`.

**A subscription is a webhook.** You subscribe once with a callback URL and a signing secret you generate. The
relay proves the address is yours with a signed challenge before it activates the subscription.

**Nothing to approve on the Mac.** The connector's approval in Herald authorises its subscriptions. There is no
second question for the user.

**Subscriptions do not lapse.** A subscription lasts until the agent unsubscribes, the user ends it in
**Settings > Cloud > Reply subscriptions**, or the user revokes the connector. `refreshBefore` is reported ten
years ahead and `ttlMs` is accepted and ignored, so there is nothing to renew.

**Callback hosts.** A callback URL may go to any public `https` host, unless the relay's owner sets the
`EVENT_CALLBACK_HOSTS` Worker variable to a comma-separated list of allowed host names.

**Request shape.** Each request in this page carries the headers and `_meta`
that [`POST /mcp`](mcp.md#post-mcp) describes for the 2026-07-28 protocol, and every successful reply carries
`resultType` and a `_meta` object, as the examples show.

## MCP methods

All four methods are `POST $RELAY/mcp` with a JSON-RPC body. Each needs a valid connector credential. A missing or
invalid credential gives HTTP `401`, and a credential without the `notify` scope gives HTTP `403`, as on every
agent route. Successful calls and most method errors answer HTTP `200`.

> [!NOTE]
> Send a custom `User-Agent` header with every request an agent makes, as [Relay API](README.md) explains. The
> examples send `Herald-Agent/1.0`.

### `server/discover`

Describes the server to a client on protocol `2026-07-28`, which sends no handshake. Call it to learn which
protocol versions and capabilities the relay offers. `capabilities.events` is present, which tells the client
that the events methods exist.

**Request**

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `MCP-Protocol-Version` | header | string | yes | `2026-07-28`. |
| `Mcp-Method` | header | string | yes | `server/discover`. |
| `params._meta` | body | object | yes | The protocol version and the client capabilities. |

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

The `instructions` text is shortened.

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
      "io.modelcontextprotocol/serverInfo": {
        "name": "herald-relay", "title": "Herald cloud relay", "version": "1.1.0"
      }
    }
  }
}
```

**Errors**

| Status | Code | When |
|---|---|---|
| `400` | `-32020` | A header does not match the body. |
| `400` | `-32022` | The protocol version is not supported. `error.data` lists `supported` and `requested`. |
| `400` | `-32602` | `_meta` lacks the protocol version or the client capabilities. |

### `events/list`

Lists the events the relay can send. There is one: `notification.reply`. Call it to read the payload schema.

**Request**

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `MCP-Protocol-Version` | header | string | yes | `2026-07-28`. |
| `Mcp-Method` | header | string | yes | `events/list`. |
| `params._meta` | body | object | yes | The protocol version and the client capabilities. |

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

```json
{
  "jsonrpc": "2.0",
  "id": 2,
  "result": {
    "resultType": "complete",
    "events": [
      {
        "name": "notification.reply",
        "description": "The user answered (typed or recorded) a notification you sent with expectReply. Call get_receipt or wait_for_reply with data.notificationId to read the answer. The payload holds ids only, never the text. A subscription lasts until you unsubscribe or the user revokes this connector in Herald.",
        "delivery": ["webhook"],
        "inputSchema": {"type": "object", "additionalProperties": false, "properties": {}},
        "payloadSchema": {
          "type": "object",
          "additionalProperties": false,
          "required": ["notificationId", "id", "kind"],
          "properties": {
            "notificationId": {
              "type": "string",
              "description": "The id you sent (or the relay's id when you sent none)."
            },
            "id": {"type": "string", "description": "The relay's own id for the notification."},
            "kind": {"type": "string", "enum": ["text", "voice"]}
          }
        }
      }
    ],
    "_meta": {
      "io.modelcontextprotocol/serverInfo": {
        "name": "herald-relay", "title": "Herald cloud relay", "version": "1.1.0"
      }
    }
  }
}
```

**Errors**

| Status | Code | When |
|---|---|---|
| `400` | `-32020`, `-32022`, `-32602` | The headers or `_meta` are wrong, as for `server/discover`. |

### `events/subscribe`

Registers a webhook for `notification.reply`. The relay first checks that the address is yours by sending it a
signed challenge it must echo, and only then activates the subscription. Call it once per connector and address.

**Request**

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `MCP-Protocol-Version` | header | string | yes | `2026-07-28`. |
| `Mcp-Method` | header | string | yes | `events/subscribe`. |
| `params.name` | body | string | yes | The event: `notification.reply`. |
| `params.delivery` | body | object | yes | The webhook: `mode`, `url` and `secret`, described below. |
| `params.arguments` | body | object | no | Empty or absent. The event takes no arguments. |
| `params.cursor` | body | string | no | Digits only. Replays this connector's later replies, up to 100. |
| `params.ttlMs` | body | integer | no | A positive integer, accepted and ignored. Any other value is an error. |
| `params._meta` | body | object | yes | The protocol version and the client capabilities. |

Fields of `params.delivery`:

| Name | Type | Required | Description |
|---|---|---|---|
| `mode` | string | yes | `webhook`. |
| `url` | string | yes | An `https` URL on the default port with no credentials, at most 2048 characters. |
| `secret` | string | yes | `whsec_` and the base64 of 24 to 64 random bytes. You keep it to verify deliveries. |

The host of `url` must be public. These are refused:

- A single-label name, `localhost`, and names ending in `.local`, `.internal` or `.home.arpa`.
- Loopback, private, link-local, shared-address, multicast and reserved IPv4 and IPv6 addresses.

**Example request**

```sh
curl -s -X POST "$RELAY/mcp" \
  -H "Authorization: Bearer $KEY" \
  -H "Content-Type: application/json" \
  -H "User-Agent: Herald-Agent/1.0" \
  -H "MCP-Protocol-Version: 2026-07-28" \
  -H "Mcp-Method: events/subscribe" \
  -d '{"jsonrpc":"2.0","id":3,"method":"events/subscribe","params":{"name":"notification.reply","arguments":{},"delivery":{"mode":"webhook","url":"https://agent.example.com/hooks/herald","secret":"whsec_MfKQ9r8GKYqrTwjUPD8ILPZIo2LaLaSw"},"cursor":null,"_meta":{"io.modelcontextprotocol/protocolVersion":"2026-07-28","io.modelcontextprotocol/clientCapabilities":{}}}}'
```

**Example response**

```json
{
  "jsonrpc": "2.0",
  "id": 3,
  "result": {
    "resultType": "complete",
    "id": "sub_3fa91c0de27b45a6d118",
    "refreshBefore": "2036-10-01T13:00:00.000Z",
    "cursor": "41",
    "truncated": false,
    "_meta": {
      "io.modelcontextprotocol/serverInfo": {
        "name": "herald-relay", "title": "Herald cloud relay", "version": "1.1.0"
      }
    }
  }
}
```

**Response fields**

| Field | Type | Description |
|---|---|---|
| `id` | string | The subscription id: `sub_` and 20 hex characters. |
| `refreshBefore` | string | A time ten years ahead. Subscriptions do not lapse, so there is nothing to refresh. |
| `cursor` | string | The sequence number of the newest event this subscription has been sent or has queued. |
| `truncated` | boolean | `true` when the cursor you sent is older than the history the relay keeps. |

**Errors**

| Status | Code | When |
|---|---|---|
| `200` | `-32602` | The request is invalid. The causes are listed below. |
| `200` | `-32015` | The callback failed verification. `error.data.reason` says why. |
| `200` | `-32603` | The relay could not handle the subscription right now. |
| `429` or `503` | `-32603` | A limit stopped the call: the key's read rate or the Mac's daily request budget. |
| `401` or `403` | none | The credential is missing, revoked or lacks the `notify` scope. |

The causes of `-32602`, each with its message:

| Cause | Message |
|---|---|
| Unknown event name. | `unknown event: <name>` |
| `arguments` is not empty. | `notification.reply takes no arguments` |
| `mode` is not `webhook`. | `delivery.mode must be webhook` |
| `url` does not parse. | `delivery.url must be an https URL` |
| `url` is not `https`, has credentials or is over 2048 characters. | `delivery.url must be an https URL without credentials` |
| `url` has a port. | `delivery.url must use the default https port` |
| `url` is not a public address. | `delivery.url must be a public address` |
| `url` is not on `EVENT_CALLBACK_HOSTS`. | `delivery.url host is not on this relay's EVENT_CALLBACK_HOSTS list` |
| The secret is malformed. | `delivery.secret must be whsec_ followed by base64 of 24-64 bytes` |
| `ttlMs` is not a positive integer. | `ttlMs must be a positive integer number of milliseconds` |
| The connector has 5 subscriptions. | `at most 5 subscriptions per connector` |

The `EVENT_CALLBACK_HOSTS` error also carries `error.data` with `reason` set to `host_not_allowed` and the
rejected `host`. The reasons of `-32015` are in [Verification challenge](#verification-challenge).

**Notes**

- Subscribing again with the same connector and URL keeps the same `id` and does not verify again. The secret you
  send in the second call becomes the secret in force, without a new challenge.
- The same connector may subscribe several URLs, up to 5 in all.
- Each call counts toward the key's read limit and the Mac's daily request budget. See
  [Limits and errors](limits-and-errors.md).

### `events/unsubscribe`

Removes a subscription and drops any events still waiting for it. It succeeds when there is nothing to remove, and
it works whatever the callback host rules are at that moment.

**Request**

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `MCP-Protocol-Version` | header | string | yes | `2026-07-28`. |
| `Mcp-Method` | header | string | yes | `events/unsubscribe`. |
| `params.name` | body | string | yes | The event: `notification.reply`. |
| `params.delivery` | body | object | yes | An object whose `url` is the callback you subscribed with. |
| `params._meta` | body | object | yes | The protocol version and the client capabilities. |

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
      "io.modelcontextprotocol/serverInfo": {
        "name": "herald-relay", "title": "Herald cloud relay", "version": "1.1.0"
      }
    }
  }
}
```

**Errors**

| Status | Code | When |
|---|---|---|
| `200` | `-32602` | `delivery.url` does not parse, or the event name is unknown. |
| `401` or `403` | none | The credential is missing, revoked or lacks the `notify` scope. |

**Notes**

- Only the connector's own subscription for that URL is removed. Other connectors are not affected.
- Herald, with the device token, can also list and end subscriptions. See
  [listing subscriptions](device-side.md#get-v1deviceevents) and
  [ending one](device-side.md#delete-v1deviceeventssubscriptionssubscriptionid).

## What the relay sends

The relay sends two kinds of `POST` to the callback URL: a verification challenge when a subscription is created,
and then one event for each reply. Both are signed the same way.

### Signature headers

Each request is an `https` `POST` with a JSON body. The signature follows the Standard Webhooks scheme, so any
Standard Webhooks library can verify it.

| Header | Value |
|---|---|
| `Content-Type` | `application/json`. |
| `User-Agent` | `Herald-Relay/1.0`. |
| `webhook-id` | The `eventId`, or `ver_` and 16 hex characters for a challenge. The same on every retry of one event. |
| `webhook-timestamp` | The send time in Unix seconds. Each attempt, including a retry, carries a fresh time. |
| `webhook-signature` | `v1,` and the base64 HMAC-SHA256 of `<webhook-id>.<webhook-timestamp>.<body>`. |

The HMAC key is the bytes you get by base64-decoding the part of your secret after `whsec_`. The signed text uses
the body exactly as received. A request also carries `x-mcp-subscription-id`, the subscription's id.

This function checks a request. It compares in constant time and takes the raw body bytes.

```python
import base64
import hashlib
import hmac


def verify(secret: str, headers: dict, body: bytes) -> bool:
    key = base64.b64decode(secret.removeprefix("whsec_"))
    prefix = f'{headers["webhook-id"]}.{headers["webhook-timestamp"]}.'
    digest = hmac.new(key, prefix.encode() + body, hashlib.sha256).digest()
    expected = "v1," + base64.b64encode(digest).decode()
    return hmac.compare_digest(expected, headers["webhook-signature"])
```

The relay does not follow redirects, and a request that takes longer than 10 seconds counts as failed.

### Verification challenge

When `events/subscribe` creates a subscription, the relay posts a challenge before it activates it. Your endpoint
must answer with a `2xx` status and a JSON body that echoes the same `challenge`.

```json
{"type": "verification", "challenge": "9c1f0a7d5b3e48a2c6d4f1e0b7a39285"}
```

The answer your endpoint gives:

```json
{"challenge": "9c1f0a7d5b3e48a2c6d4f1e0b7a39285"}
```

If the check fails, `events/subscribe` returns `-32015` with `error.data.reason` set to one of these, and no
subscription is created.

| Reason | When |
|---|---|
| `unreachable` | The request failed or timed out after 10 seconds. |
| `bad_status` | Your endpoint answered with a status outside `2xx`, a redirect included. |
| `challenge_mismatch` | The body is not JSON, or its `challenge` differs from the one sent. |

### The `notification.reply` event

The event body carries ids and never the answer.

**Example event**

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

**Event fields**

| Field | Type | Description |
|---|---|---|
| `eventId` | string | `evt_`, the event's sequence number, `_` and the subscription's id without `sub_`. |
| `name` | string | `notification.reply`. |
| `timestamp` | string | When the user replied, as an ISO 8601 time. |
| `data.notificationId` | string | The id you sent, or the id the relay generated when you sent none. |
| `data.id` | string | The relay's own id for the notification: `r_` and 24 hex characters. |
| `data.kind` | string | `text` or `voice`. |
| `cursor` | string | The event's sequence number. Pass it to `events/subscribe` to replay later events. |

**Notes**

- The event fires once per notification. A second answer to the same notification sends nothing.
- A reply sent from the Mac over its socket also fires the event.
- Read the answer with `get_receipt` or `wait_for_reply` and the `notificationId`.

### Retries and ordering

Your endpoint answers `2xx` to accept the event. What the relay does with each answer:

| Your answer | What the relay does |
|---|---|
| `2xx` | The event is delivered and is not sent again. |
| `410` | The subscription ends and its waiting events are dropped. |
| Another `4xx`, except `408` and `429` | That one event is dropped. The subscription stays. |
| `408`, `429`, `5xx`, a redirect, a timeout or a network error | The event is retried. |

A retry waits 1 minute after the first attempt, then doubles the wait each time up to 1 hour. When the response
carries a longer `Retry-After`, as seconds or an HTTP date, the relay waits that long instead. An event is tried at
most 8 times and for at most 24 hours, then dropped.

Events are sent in order for each subscription. The relay sends only the oldest waiting event, so a newer event
waits until the oldest is delivered or dropped. A cursor you read from a delivery therefore never passes an event
you have not been sent.

> [!NOTE]
> A `2xx` means your endpoint received the event. It does not prove that your agent acted on it. To check the
> whole path, send a notification with `expectReply`, reply on the Mac, and confirm your agent woke.

### Cursor and replay

Every reply gets a sequence number, kept per Mac, and the cursor is that number as a string. When you pass
`cursor` to `events/subscribe`, the relay queues this connector's replies after it, oldest first, up to 100, and
delivers them like any other event. It keeps 30 days of reply events.

- The cursor in the response never passes an event that has not been sent to this subscription yet.
- When 100 events were queued, the cursor is the last one of them. Subscribe again with it to continue.
- `truncated` is `true` when the cursor you sent is older than the oldest event the relay still keeps.
- A `cursor` that is not a string of 1 to 15 digits is ignored and nothing is replayed.

### Subscription lifetime

| Fact | Detail |
|---|---|
| How long it lasts | Until you unsubscribe, the user ends it in Settings, or the user revokes the connector. |
| Renewal | None. `refreshBefore` is ten years ahead and `ttlMs` is ignored. |
| Per connector | At most 5 subscriptions. |
| Waiting events | An event that cannot be delivered is dropped after 24 hours. |
| User view | **Settings > Cloud > Reply subscriptions** shows the host, never the path or the secret. |

## Related

- [Reply events](../../cloud/reply-events.md): the task page for subscribing and for connecting an OpenAI dot, an
  always-on cloud agent.
- [`POST /mcp`](mcp.md#post-mcp): protocol versions, headers and the other MCP methods.
- [Device endpoints](device-side.md): how Herald lists and ends subscriptions.
- [Limits and errors](limits-and-errors.md): limits that apply to subscribing, and every error code.
- [Relay API](README.md): credentials and the shared error shape.
