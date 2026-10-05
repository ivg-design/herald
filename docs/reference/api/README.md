# HTTP API

Herald runs a small HTTP server on your Mac. Any program that can make an HTTP request can use it to show a
notification, read History, design a template or change a setting. This page explains how to connect, what every
request has in common, and where each endpoint is documented. It is for anyone writing an integration by hand; if
you use the [CLI](../cli.md), the [client libraries](../../../clients/README.md) or the
[MCP server](../mcp/README.md), they make these calls for you.

## How the API is organised

The server listens on the loopback address only, so nothing outside your Mac can reach it. Every endpoint lives
under `/v1` and takes and returns JSON. A bearer token, created when Herald first starts, proves that the caller
is a program running as you.

The endpoints are grouped by what they work on. Each group has its own page.

| Area | What you do there |
|---|---|
| [Notifications](notifications.md) | Show a banner, speak, dismiss, snooze. |
| [Apps](apps.md) | Register an app, list and remove apps, change per-app settings. |
| [Templates](templates.md) | Save, list, copy, export and preview banner templates. |
| [Manifests](manifests.md) | Describe the fields and actions an app sends. |
| [Assets](assets.md) | Store an app's Rive animations and images. |
| [History](history.md) | Read, search, re-show, delete and export past notifications. |
| [Replies](replies.md) | Read what the user typed into a banner's reply field. |
| [Stacks](stacks.md) | See and open stacks of banners, and set how banners stack. |
| [Settings](settings.md) | Read and change general, voice and quiet-hours settings. |
| [Voice and MCP setup](setup.md) | Install the Kokoro voice and the MCP server. |
| [Cloud relay](relay.md) | Deploy, pair and manage the cloud relay from this Mac. |
| [Diagnostics](diagnostics.md) | Check that Herald is running, and test renders without a window. |

## Connect

Herald writes its port and token to files in its support folder. Read them once and reuse the two variables in
every request. All the examples in this reference assume this block has run.

```sh
D="$HOME/Library/Application Support/Herald"
HERALD="http://127.0.0.1:$(cat "$D/port")"
TOKEN="$(cat "$D/token")"
```

The default port is `48617`. You can change it in **Settings > General > Local API**; the `port` file always
holds the current number.

Check the connection with the one endpoint that needs no token:

```sh
curl -s "$HERALD/v1/health"
```

```json
{"ok": true, "pid": 4821, "version": "1.8.1"}
```

## Authentication

Send the token in an `Authorization` header on every request except
[`GET /v1/health`](diagnostics.md#get-v1health).

```sh
curl -s "$HERALD/v1/apps" -H "Authorization: Bearer $TOKEN"
```

The token is a file readable only by your user account (mode `0600`). A request with a missing or wrong token
gets `401` before Herald reads the body.

> [!WARNING]
> The token lets a program run anything the API allows, as you. Do not paste it into a web page, a chat or a
> shared log.

## Request rules

| Rule | Detail |
|---|---|
| Body format | JSON with `Content-Type: application/json`. |
| Body length | `Content-Length` is required. Chunked bodies are refused with `400`. |
| Body size | At most 1 MB. Headers at most 64 KB. |
| Time limit | The whole request must arrive within 10 seconds. |
| Connections | At most 32 connections are served at once. |
| Browsers | A request with an `Origin` header is refused with `403`. |
| Host header | Must be `127.0.0.1`, `localhost` or `[::1]`, else `403`. |

Query parameters are used by `GET` and `DELETE` endpoints. Request bodies are used by `POST` and `PUT`.

## Responses

A successful response is `200` with a JSON object, with two exceptions:
[`POST /v1/relay/keys`](relay.md#post-v1relaykeys) answers `201`, and the preview and snapshot endpoints
return a PNG image (`Content-Type: image/png`).

A failed response is a JSON object with one field, `error`, that says what was wrong.

```json
{"error": "missing field: title"}
```

Dates are ISO 8601 strings in UTC, for example `2026-10-02T13:15:00.000Z`.

## Errors shared by every endpoint

Each endpoint page lists only the errors specific to that endpoint. These apply everywhere.

| Status | When |
|---|---|
| `400` | The body is not valid JSON, a required field is missing, or a value is invalid. |
| `401` | The token is missing or wrong. |
| `403` | The request came from a browser or used an unexpected `Host` header. |
| `404` | The path does not exist. |
| `405` | The path exists but not with this method. |
| `413` | The body, or one field in it, is over its size limit. |
| `500` | Herald could not save, or met an unexpected error. |
| `501` | This Herald does not support the route. |

A `400` message names the problem and where it is: `missing field: title`, `invalid field: timeout`, or for a
template `invalid template: grid.rows: rows must be 1 to 12`.

## Limits

| What | Limit |
|---|---|
| Request body | 1 MB. |
| App id | 128 bytes. |
| Notification id | 256 bytes. |
| Title, subtitle | 1 KB each. |
| Body text | 16 KB. |
| `metadata` | 64 KB. |
| Buttons | 8 per notification, 64 KB together. |
| `image` or `icon` value | 256 KB as sent. A downloaded image may be 10 MB. |
| Any other text field | 2 KB. |
| Template | 2 MB, 100 cells, a grid of 12 by 12. |
| Apps, manifests | 200 each. |
| History | 1000 notifications per app by default. |
| Rive files | 10 MB each, 32 per app. |
| Images | 10 MB each, 100 per app. |

A request over a size limit gets `413` with the name of the field. Registering a 201st app or manifest gets `429`.

## Run a second instance

Two environment variables start a second Herald beside the installed one, with its own port, token and data.
Use this to develop against Herald without touching your real notifications.

| Variable | Effect |
|---|---|
| `HERALD_PORT` | The port the second instance listens on. |
| `HERALD_SUPPORT_DIR` | The folder that holds its token, port file, History and templates. |

## Related

- [Send your first notification](../../getting-started.md): the shortest path from nothing to a banner.
- [herald CLI](../cli.md): the same operations from a terminal.
- [MCP tools](../mcp/README.md): the same operations for an AI agent.
- [Python, Node and Swift clients](../../../clients/README.md): thin wrappers over this API.
- [Cloud relay API](../relay-api.md): the separate API the relay serves to cloud agents.
