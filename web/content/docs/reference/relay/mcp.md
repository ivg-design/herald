# MCP endpoint

The relay is also a remote MCP server, so an agent platform that speaks MCP can use it without writing HTTP calls.
This page documents the one URL, `POST /mcp`, the methods it answers, and the four tools it offers. Read it if you
are building an MCP client, or if you want to know exactly what the relay does with each request. To set up a
connection from ChatGPT, Claude or Codex, follow [Connect an agent](../../cloud/connect-agent.md) instead.

The examples use `$RELAY` for the relay's origin and `$KEY` for the credential, as in
[Agent endpoints](agent.md).

```sh
RELAY="https://herald-relay.example.workers.dev"
KEY="hrk_..."
```

## Before you start

- You hold an agent key (`hrk_...`) or a connector access token (`hra_...`), sent as `Authorization: Bearer $KEY`.
  An approved connector works until the user revokes it. Tokens never expire and are never rotated.
- Send a custom `User-Agent` header, as the examples do. See [Relay API](README.md) for why.

## Concepts

The transport is Streamable HTTP in its simplest form. Every request is a `POST` with one JSON-RPC 2.0 message,
and every reply is one JSON response. There is no Server-Sent Events stream and no `Mcp-Session-Id`, so a request
never depends on an earlier one.

One URL serves two kinds of client. The relay tells them apart by what the request carries.

| Kind | How the relay recognises it | What it gets |
|---|---|---|
| Session-less | No `_meta` protocol member. An optional `initialize` handshake with `2025-06-18`, `2025-03-26` or `2024-11-05`. | `initialize`, `ping`, `tools/list` and `tools/call`. |
| Stateless | The header `MCP-Protocol-Version: 2026-07-28` and the `_meta` members below on every request. | `server/discover`, `ping`, `tools/list`, `tools/call` and the [event methods](events.md). |

A session-less client gets tools only. Reply events, which tell an agent the moment the user answers, are offered to
stateless clients. The relay has no handshake for them, so every request states its own context.

A stateless request carries these parts. The headers repeat the method and the tool name so a proxy can route
without parsing the body.

| Part | Where | Must be |
|---|---|---|
| `MCP-Protocol-Version` | header | `2026-07-28`. |
| `io.modelcontextprotocol/protocolVersion` | `params._meta` | `2026-07-28`, equal to the header. |
| `io.modelcontextprotocol/clientCapabilities` | `params._meta` | An object. It may be empty. |
| `Mcp-Method` | header | The same as the body's `method`. |
| `Mcp-Name` | header | The same as `params.name`, on `tools/call` only. A name with non-ASCII characters is sent as `=?base64?<base64>?=`. |

A stateless reply also carries `resultType: "complete"` and a `_meta` member naming the server, as the examples
below show.

Tools are a thin layer over the [agent endpoints](agent.md). A tool call goes to the same checked HTTP route, so
the limits, the validation and the errors are the endpoint's. A connector cannot send buttons, commands, scripts
or any code: the relay accepts text and presentation fields only.

| Method | Session-less | Stateless |
|---|---|---|
| [`initialize`](#initialize) | yes | no |
| [`ping`](#post-mcp) | yes | yes |
| [`tools/list`](#toolslist) | yes | yes |
| [`tools/call`](#toolscall) | yes | yes |
| [`server/discover`](events.md#serverdiscover) | no | yes |
| [`events/list`, `events/subscribe`, `events/unsubscribe`](events.md) | no | yes |

A method a client's kind does not have is answered with `-32601`.

## The endpoint

### `POST /mcp`

The one MCP endpoint. Use it as the server URL when you register Herald in an MCP client.

**Request**

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `Authorization` | header | string | yes | `Bearer` and an agent key or connector access token. |
| `Content-Type` | header | string | yes | `application/json`. |
| `MCP-Protocol-Version` | header | string | no | Required as `2026-07-28` for a stateless request. A session-less client may send `2025-06-18`, `2025-03-26` or `2024-11-05`. |
| `Mcp-Method` | header | string | no | The JSON-RPC method again. Required on a stateless request. |
| `Mcp-Name` | header | string | no | The tool name again. Required on a stateless `tools/call`. |

The body is one JSON-RPC request. An array of requests is refused.

**Example request**

```sh
curl -s -X POST "$RELAY/mcp" \
  -H "Authorization: Bearer $KEY" \
  -H "Content-Type: application/json" \
  -H "User-Agent: Herald-Agent/1.0" \
  -d '{"jsonrpc":"2.0","id":1,"method":"ping"}'
```

**Example response**

```json
{"jsonrpc": "2.0", "id": 1, "result": {}}
```

**Errors**

| Status | When |
|---|---|
| `400` | The body is not JSON (`-32700`) or is an array (`-32600`), or the protocol headers are wrong. See [JSON-RPC errors](#json-rpc-errors). |
| `401` | The credential is missing, malformed, revoked or unknown. |
| `403` | The credential is the device token (`wrong_credential`), or has no notify scope (`scope`). |
| `404` | The method does not exist, on a stateless request (`-32601`). |
| `405` | The method is `GET` or `DELETE`. The server answers `POST` only. |
| `429`, `503` | An event subscription hit a limit. See [Events](events.md). |

**Notes**

- A `401` carries `WWW-Authenticate: Bearer resource_metadata="$RELAY/.well-known/oauth-protected-resource"`, so
  an OAuth client learns where to sign in. A token that was sent and rejected adds `error="invalid_token"`. The
  `403` answers carry no such header.
- Every request needs a valid credential, even one the relay answers itself, such as `ping`. The check comes
  before the protocol checks, so a bad key with a wrong version header gets `401`.
- A request with no `id` is a notification, such as `notifications/initialized`. The relay answers `202` with no
  body. A message with no `method` is a response from the client: the relay ignores it and answers `202`.
- A tool call authenticates with its own request to the Mac's mailbox, so it costs one request. Any other
  method costs one `GET /v1/status` check. Both count toward the Mac's daily request budget, and only a `401` or
  `403` from that check stops the request.
- A `GET` on `/mcp` answers `405` with `Allow: POST` and the JSON-RPC error `-32000`. The relay offers no event
  stream.

### `initialize`

Starts a session-less handshake. The relay keeps no session: the reply only says what the server can do, and the client
then sends `tools/list` and `tools/call`. The relay echoes the client's protocol version when it supports it and
answers `2025-06-18` otherwise. A stateless client does not send `initialize`.

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

The `instructions` text is shortened here.

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

**Errors**

| Status | When |
|---|---|
| `401` | The credential is invalid. |
| `403` | The credential is the device token. |

**Notes**

- The real `instructions` text is longer. It also describes the OAuth device flow and the reply event.
- The reply has no `events` capability. A client that asks for `2026-07-28` in `initialize` gets `2025-06-18`
  back and stays a session-less client.

### `tools/list`

Lists the four tools with their input schemas. It answers both kinds of client.

**Request**

No parameters.

**Example request**

```sh
curl -s -X POST "$RELAY/mcp" \
  -H "Authorization: Bearer $KEY" \
  -H "Content-Type: application/json" \
  -H "User-Agent: Herald-Agent/1.0" \
  -d '{"jsonrpc":"2.0","id":2,"method":"tools/list"}'
```

**Example response**

The `inputSchema` and `annotations` of each tool are shortened here.

```json
{
  "jsonrpc": "2.0",
  "id": 2,
  "result": {
    "tools": [
      {
        "name": "send_notification",
        "title": "Send a notification to the user's Mac",
        "inputSchema": {"type": "object", "required": ["title"]},
        "annotations": {"readOnlyHint": false, "idempotentHint": true}
      },
      {
        "name": "get_receipt",
        "title": "Get delivery receipts",
        "inputSchema": {"type": "object", "required": ["notificationId"]},
        "annotations": {"readOnlyHint": true}
      },
      {
        "name": "wait_for_reply",
        "title": "Wait for the user's reply",
        "inputSchema": {"type": "object", "required": ["notificationId"]},
        "annotations": {"readOnlyHint": true}
      },
      {
        "name": "herald_status",
        "title": "Is the user's Mac reachable",
        "inputSchema": {"type": "object"},
        "annotations": {"readOnlyHint": true}
      }
    ]
  }
}
```

A stateless request, with the headers and `_meta` described above, gets the same list with two additions in
`result`: `"resultType": "complete"` and a `_meta` member with the server's name, title and version.

```sh
curl -s -X POST "$RELAY/mcp" \
  -H "Authorization: Bearer $KEY" \
  -H "Content-Type: application/json" \
  -H "User-Agent: Herald-Agent/1.0" \
  -H "MCP-Protocol-Version: 2026-07-28" -H "Mcp-Method: tools/list" \
  -d '{"jsonrpc":"2.0","id":3,"method":"tools/list","params":{"_meta":{"io.modelcontextprotocol/protocolVersion":"2026-07-28","io.modelcontextprotocol/clientCapabilities":{}}}}'
```

**Errors**

| Status | When |
|---|---|
| `400` | A stateless request has missing or mismatched `_meta` or headers. See [JSON-RPC errors](#json-rpc-errors). |
| `401` | The credential is invalid. |
| `403` | The credential is the device token. |

### `tools/call`

Runs one tool. The `params` carry the tool's `name` and its `arguments`. The four tools are described under
[Tools](#tools).

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
  -d '{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"herald_status","arguments":{}}}'
```

**Example response**

Every tool result has the same envelope. The JSON the endpoint returned is both the text of `content` and the
`structuredContent`.

```json
{
  "jsonrpc": "2.0",
  "id": 4,
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

When the endpoint refuses the call, the result adds `isError: true` and holds the endpoint's error body. This is
what `send_notification` returns for a forbidden field:

```json
{
  "jsonrpc": "2.0",
  "id": 5,
  "result": {
    "content": [
      {
        "type": "text",
        "text": "{\"error\":\"forbidden_fields\",\"message\":\"rejected fields: command.\",\"fields\":[\"command\"]}"
      }
    ],
    "structuredContent": {
      "error": "forbidden_fields",
      "message": "rejected fields: command.",
      "fields": ["command"]
    },
    "isError": true
  }
}
```

The `message` is shortened here.

**Errors**

| Status | When |
|---|---|
| `200` | The tool failed. The result has `isError: true`. This covers every endpoint error except `401` and `403`, for example `forbidden_fields`, `rate_limited`, `not_found` and `budget_exhausted`. |
| `200` | `get_receipt` or `wait_for_reply` has no `notificationId`. The result has `isError: true` and the text `notificationId is required`, with no `structuredContent`. |
| `200` | The tool name is unknown. The reply is the JSON-RPC error `-32602` with the message `unknown tool: <name>`. |
| `400` | A stateless request lacks the `Mcp-Name` header or it differs from `params.name` (`-32020`). |
| `401` | The credential is invalid. A bad credential is an HTTP error, never a tool result. |
| `403` | The credential is the device token, or has no notify scope. |

**Notes**

- A stateless result also carries `resultType: "complete"` and a `_meta` member naming the server.
- A tool call to `send_notification`, `get_receipt`, `wait_for_reply` or `herald_status` makes one request to the
  Mac's mailbox. A call that fails before it reaches the mailbox (an unknown tool, a missing id) costs one
  status check instead.

## Tools

Each tool forwards to the agent endpoint named in its block. The arguments and result fields are the endpoint's,
so the endpoint's tables are the full reference. These blocks list what an MCP client sees.

### `send_notification`

Queues a notification for the user's Mac. Call it to tell the user something or to ask for an answer. It takes
the same text and presentation fields as the endpoint and refuses buttons, commands, callbacks and scripts.

**Arguments**

| Name | Type | Required | Description |
|---|---|---|---|
| `title` | string | yes | The headline, at most 200 characters. |
| `body` | string | no | The message text, at most 8000 characters. |
| `expectReply` | boolean | no | Adds the **Reply** and **Record** buttons. |
| `notificationId` | string | no | Your own id. Sending the same id again within 24 hours never shows a second banner. |
| other fields | various | no | Every other field of [`POST /v1/notify`](agent.md#post-v1notify). |

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

The `structuredContent` is the notification's receipt. The `content` text holds the same JSON as a string and is
omitted here.

```json
{
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

[`POST /v1/notify`](agent.md#post-v1notify). The tool schema sets `additionalProperties` to `false`, and the
relay refuses a field outside its whitelist whatever the client sends.

**Side effects**

Queues a notification, and Herald shows a banner on the Mac, speaks, or both. A repeated `notificationId` is
not queued again.

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

[`GET /v1/receipts/{notificationId}`](agent.md#get-v1receiptsnotificationid). The relay keeps an id for
24 hours.

**Side effects**

None. Read-only.

### `wait_for_reply`

Waits for the user's answer to a notification sent with `expectReply`. Call it after `send_notification`. When
nothing came, it returns `replied: false` and `timedOut: true`, and you call it again to keep waiting.

**Arguments**

| Name | Type | Required | Description |
|---|---|---|---|
| `notificationId` | string | yes | The id you sent, or the one the relay returned. |
| `timeoutSeconds` | integer | no | Seconds to wait, from 0 to 55. Default `30`. A value above 55 is lowered to 55. |

**Example call**

```json
{"notificationId": "build-214", "timeoutSeconds": 30}
```

**Example result**

```json
{
  "structuredContent": {
    "notificationId": "build-214",
    "replied": false,
    "timedOut": true,
    "suppressed": false
  }
}
```

A typed answer has `text`. A voice answer has `transcript`, made on the user's Mac and possibly imperfect, and
an `audioUrl` that stays valid for 3600 seconds, with `durationSeconds`.

**HTTP route**

[`GET /v1/replies/{notificationId}`](agent.md#get-v1repliesnotificationid) with `wait` set to `timeoutSeconds`.
The tool stops at 55 seconds, five below the endpoint's limit of 60, so the client's own timeout is not reached
first.

**Side effects**

None. Read-only. A call that waits keeps the Mac's mailbox awake and counts against its daily poll seconds. To be
told instead of waiting, subscribe to the [reply event](events.md).

### `herald_status`

Says whether the user's Herald is online, when it was last seen, and whether quiet hours are on. Call it before
you depend on a fast answer. Nothing else about the Mac is exposed.

**Arguments**

No arguments.

**Example call**

```json
{}
```

**Example result**

```json
{
  "structuredContent": {
    "online": true,
    "lastSeenAt": "2026-10-02T13:14:19.111Z",
    "quietHours": {"active": false}
  }
}
```

**HTTP route**

[`GET /v1/status`](agent.md#get-v1status).

**Side effects**

None. Read-only.

## JSON-RPC errors

A JSON-RPC error has `code` and `message`, and sometimes `data`. This is the reply to an unsupported protocol
version:

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "error": {
    "code": -32022,
    "message": "Unsupported protocol version",
    "data": {
      "supported": ["2026-07-28", "2025-06-18", "2025-03-26", "2024-11-05"],
      "requested": "1900-01-01"
    }
  }
}
```

| Code | HTTP status | Meaning |
|---|---|---|
| `-32700` | `400` | The body is not valid JSON. |
| `-32600` | `400` or `202` | The body is a batch (`400`), or it is a response and not a request (`202`). |
| `-32601` | `200` or `404` | The method does not exist. `404` on a stateless request, `200` on a session-less one. |
| `-32602` | `200` or `400` | A tool is unknown (`200`), or `_meta` lacks the required members (`400`). |
| `-32603` | `200`, `429` or `503` | The relay could not handle a subscription right now. |
| `-32015` | `200` | A subscription callback failed verification. See [Events](events.md). |
| `-32020` | `400` | A header does not match the body: the protocol version, `Mcp-Method` or `Mcp-Name`. |
| `-32022` | `400` | The protocol version is not supported. `data` lists `supported` and `requested`. |
| `-32000` | `405` | The request used `GET` or `DELETE`. |

## Related

- [Agent endpoints](agent.md): the HTTP routes behind the four tools.
- [Events](events.md): `server/discover`, the reply event and webhook delivery.
- [Relay API](README.md): credentials and the shared error format.
- [Limits and errors](limits-and-errors.md): every limit and error code.
- [Connect an agent](../../cloud/connect-agent.md): set up a connection step by step.
