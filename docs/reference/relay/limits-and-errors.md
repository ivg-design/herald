# Relay limits and errors

This page lists every limit the relay enforces and every error it returns. Use it to size an integration, to
understand a `429` or `503`, and to look up an error code. The routes themselves are documented on the pages
linked from [Relay API](README.md); this page does not repeat their tables.

## How limits work

The limits protect each Mac from the others, and the relay from running past Cloudflare's free plan. Every paired
Mac has its own mailbox, so a per-device counter is never shared: one noisy Mac or key cannot use up another
Mac's allowance.

- Counters that reset daily reset at midnight UTC.
- A relay's owner can change most limits with a Worker variable, in `wrangler.toml` under `[vars]` or with
  `--var NAME:value`. A variable counts only when it is a positive number. Otherwise the default applies.
- `QUEUE_TTL_HOURS` is in hours. Every other variable is a plain count or a number of bytes.
- The defaults for the per-device limits are in `relay/src/limits.ts`. Other limits are constants named in the
  Source column.

## Limits

### Per Mac

| Limit | Default | Worker variable | When it is reached | Source |
|---|---|---|---|---|
| Notifications per day | 500 | `DEVICE_NOTIFICATIONS_PER_DAY` | `429 daily_cap` on `POST /v1/notify`. | `limits.ts` |
| Undelivered notifications waiting | 100 | `DEVICE_QUEUE_MAX` | `429 queue_full` on `POST /v1/notify`. | `limits.ts` |
| Wait for an undelivered notification | 24 hours | `QUEUE_TTL_HOURS` | The notification gets a `suppressed` receipt with reason `expired`. | `limits.ts` |
| Agent requests per day | 5000 | `DEVICE_REQUESTS_PER_DAY` | `503 budget_exhausted` on agent routes. | `limits.ts` |
| Voice replies per day | 40 | `DEVICE_AUDIO_UPLOADS_PER_DAY` | `429 daily_cap` on the audio upload. | `limits.ts` |
| Voice reply bytes per day | 20 MB | `DEVICE_AUDIO_BYTES_PER_DAY` | `429 daily_cap` on the audio upload. | `limits.ts` |
| Long-poll seconds per day | 3000 | `DEVICE_POLL_SECONDS_PER_DAY` | A `wait` is treated as `0`, so the relay answers at once. | `limits.ts` |
| Notify request size | 32 KB | `MAX_BODY_BYTES` | `413 too_large`. A `data:` icon may add up to 256 KB. | `limits.ts` |
| Active agent keys | 20 | none | `429 too_many_keys` when a key is made or a connector approved. | `mailbox.ts` |

Notes on the table:

- The request budget counts agent requests, device requests (except the stream and `usage`) and MCP calls. Only
  agent routes are refused once it is used up. The Mac can still connect, collect its queue and send receipts. A
  notification already queued is not lost.
- A `503 budget_exhausted` and a `429 daily_cap` carry `retryAfterSeconds` and a `Retry-After` header counted to
  the next midnight UTC.
- The daily request budget is kept below Cloudflare's free-plan allowance of 100,000 requests a day, so Cloudflare
  never has to cut the Mac off mid-day. `GET /v1/device/usage` reports every counter and its limit. See
  [Pairing and devices](pairing-and-devices.md).

### Per key

| Limit | Default | Worker variable | When it is reached | Source |
|---|---|---|---|---|
| Notifications per 10 minutes | 60 | `RATE_LIMIT_PER_KEY` | `429 rate_limited` with `Retry-After`. | `limits.ts` |
| Receipt, reply and events calls per 10 minutes | 600 | none | `429 rate_limited`, retry in 60 seconds. | `mailbox.ts` |
| Long-poll wait | 60 seconds | none | A larger `wait` is cut to 60. | `mailbox.ts` |
| Event subscriptions per connector | 5 | none | `-32602` on `events/subscribe`. | `events.ts` |

The 600 per 10 minutes applies to receipt reads, reply reads,
`events/subscribe` and `events/unsubscribe`. The status check and notify are outside it. The count is
held in memory, so a relay restart forgives the current window. The request budget still holds.

### Pairing, approvals and registration

| Limit | Default | Worker variable | When it is reached | Source |
|---|---|---|---|---|
| Macs that may pair | 5 | `MAX_DEVICES` | `403 device_limit` on `POST /v1/pair/start`. | `registry.ts` |
| Pairing starts per address per hour | 6 | `PAIR_STARTS_PER_HOUR` | `429 rate_limited`. | `registry.ts` |
| Pairing starts per hour, all addresses | 300 | `PAIR_STARTS_GLOBAL_PER_HOUR` | `429 rate_limited`. | `registry.ts` |
| Pairing codes waiting | 3 per address, 60 in all | none | `429 rate_limited` on `POST /v1/pair/start`. | `registry.ts` |
| Wrong pairing codes per address per 10 minutes | 10 | none | `429 rate_limited` on `POST /v1/pair`. | `registry.ts` |
| Client registrations per hour | 30 | `REGISTER_PER_HOUR` | `429 rate_limited` on `POST /register`. | `registry.ts` |
| Connector approvals waiting per Mac | 3 | none | `429 rate_limited`, or `slow_down` on the device flow. | `mailbox.ts` |
| Connector approvals begun per hour | 12 | none | `429 rate_limited`, or `slow_down` on the device flow. | `mailbox.ts` |
| Wrong approval codes per request | 5 | none | The request is denied. | `mailbox.ts` |

The client address is hashed before it is compared and is never stored in the clear. Pairing again under the same
device name does not count against the limit of paired Macs.

### Field and size limits

The notification fields have their own maximum sizes, listed with each field under
[`POST /v1/notify`](agent.md#post-v1notify). These are the values the relay enforces in `relay/src/validate.ts`.

| Field | Limit |
|---|---|
| `title`, `subtitle` | 200 characters. |
| `body` | 8000 characters. |
| `project`, `session`, `task`, `tool`, `group` | 100 characters each. |
| `status` | 32 characters. |
| `duration` | 40 characters. |
| `notificationId` | 128 characters. |
| `link`, `imageURL`, `icon` as a URL | 2048 characters. |
| `icon` as a `data:` image | 256 KB. |
| `tags` | 10 tags of at most 32 characters. |
| `speak` text | 2000 characters. |
| `timeoutSeconds` | 1 to 3600. |
| `speed`, `speak.speed` | 0.5 to 2. |

Other sizes:

| Value | Limit |
|---|---|
| A voice reply upload | 1 MB, `audio/mp4`, `audio/x-m4a` or `audio/aac`. |
| A key name | 1 to 32 characters: `a-z`, `0-9` and `-`. |
| A device name at pairing | The first 60 characters. |
| A registered client name | The first 60 characters. |
| Redirect URIs per registered client | 1 to 10. |
| Callback URL for an event subscription | 2048 characters. |

### Fixed lifetimes and intervals

| Value | Fixed at |
|---|---|
| Pairing code lifetime | 10 minutes, single use. |
| Browser approval request lifetime | 10 minutes. |
| Device approval request lifetime | 10 minutes. |
| Time to exchange an approved code | 5 minutes. |
| Device flow poll interval | 5 seconds, raised by 5 for each `slow_down`. |
| Signed audio link | 3600 seconds. |
| Stored voice reply | 7 days, by a rule on the audio bucket. |
| Notification ids, receipts and replies | Kept 24 hours. |
| Event delivery timeout | 10 seconds. |
| Event delivery attempts | 8, within 24 hours. |
| Event history for replay | 30 days, at most 100 events per replay. |
| Mac counted as online | Seen within 11 minutes. |
| Idle Mac removed by the relay | 30 days without a connection. |
| Idle Mac another Mac may remove | 7 days without a connection. |
| Access tokens kept per connector | 50 of the newest. |

Access tokens and refresh tokens never expire. They stop working only when the connector is revoked. A refresh
returns a new access token and the same refresh token, and `expires_in` is reported as ten years.

### Access settings

Two secrets and one list control access rather than limits.

| Setting | Purpose |
|---|---|
| Secret `RELAY_SECRET` | Required. It signs device ids so strangers cannot create mailboxes. Without it the relay answers `500 misconfigured`. |
| Secret `PAIRING_SECRET` | Optional. When set, `POST /v1/pair/start` needs it in `X-Pairing-Secret`. |
| Variable `EVENT_CALLBACK_HOSTS` | Optional, comma-separated. Limits the hosts an event subscription may call. Empty means any public host. |

## Errors

### Error body

Every error from a relay route has a JSON body with an `error` code and a `message`. One more field is added where
it helps.

```json
{
  "error": "rate_limited",
  "message": "at most 60 notifications per 10 minutes per key",
  "retryAfterSeconds": 412
}
```

| Field | Type | Description |
|---|---|---|
| `error` | string | A stable code from the table below. Match on this, not on `message`. |
| `message` | string | A sentence for a person. The wording can change. |
| `fields` | array | The rejected field names, on `invalid_request` and `forbidden_fields`. |
| `retryAfterSeconds` | integer | How long to wait, on a rate limit or an exhausted budget. |
| `status` | string | The decision already made, on `already_decided`. |

A `Retry-After` header carries the same number of seconds for these errors: `rate_limited` and `daily_cap` on
`POST /v1/notify`, `rate_limited` on the read limit, `daily_cap` on a voice reply upload, and `budget_exhausted`.
The pairing, registration and approval-begin limits send `retryAfterSeconds` in the body and no header.

Two families use another format:

- The OAuth routes answer in the OAuth error format, `error` and `error_description`. See
  [OAuth errors](#oauth-errors).
- MCP errors are JSON-RPC errors. See [JSON-RPC errors](#json-rpc-errors).

### Error codes

| Code | Status | Meaning |
|---|---|---|
| `invalid_request` | `400` | The body is not valid JSON, or a value is invalid. `fields` names the field. |
| `forbidden_fields` | `400` | The body holds a field the relay does not accept. `fields` lists it. |
| `scope_not_allowed` | `400` | A key was asked for with a scope other than `notify`. |
| `unauthorized` | `401` | The credential is missing, malformed, revoked or unknown, or a pairing secret is required. |
| `wrong_credential` | `403` | An agent key or access token was used on a device route, or the device token on an agent route. |
| `scope` | `403` | The key has no `notify` scope. |
| `forbidden` | `403` | A signed audio link has a bad signature. |
| `device_limit` | `403` | The relay already has its maximum number of paired Macs. |
| `bad_code` | `403` | A pairing code is wrong, used or expired. |
| `not_removable` | `403` | One Mac tried to remove another Mac that is active, has another name and has valid credentials. |
| `not_found` | `404` | The route, notification, key, device or entry does not exist. Notification ids are kept 24 hours. |
| `not_paired` | `404` | A connector approval was started on a relay with no paired Herald. |
| `method_not_allowed` | `405` | An OAuth route was called with the wrong method. |
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
| `budget_exhausted` | `503` | The Mac's daily request budget on the relay is used up. Nothing queued is lost. |

> [!NOTE]
> When a limit is reached, nothing is lost silently. The queue lives in the Mac's mailbox, and notifications are
> delivered when the Mac reconnects. A notification older than the queue time gets a `suppressed` receipt with
> reason `expired`.

### OAuth errors

The OAuth routes answer with `{"error": "...", "error_description": "..."}`. Token errors are status `400`, except
where the table says otherwise. The routes that return them are documented in [OAuth](oauth.md) and
[Device flow](device-flow.md).

| Code | Status | When |
|---|---|---|
| `invalid_client_metadata` | `400` | A registration field is not valid JSON or has an unsupported value. |
| `invalid_redirect_uri` | `400` | `redirect_uris` is not 1 to 10 `https` or loopback `http` URLs without a fragment. |
| `invalid_client` | `401` | The client id is unknown or its authentication failed. A Basic attempt adds `WWW-Authenticate`. |
| `unsupported_grant_type` | `400` | `grant_type` is not one of the three grants the relay supports. |
| `invalid_grant` | `400` | A code, refresh token or device code is unknown, used, malformed, mismatched or revoked. |
| `invalid_scope` | `400` | A scope other than `notify` was asked for. |
| `invalid_target` | `400` | `resource` does not match the original request. |
| `invalid_request` | `400` | The Mac is not paired, or `device` is out of range. |
| `authorization_pending` | `400` | The user has not decided yet. Poll again after the interval. |
| `slow_down` | `400` | A device poll came too soon. The interval grows by 5 seconds. |
| `slow_down` | `429` | Approvals are already waiting, or too many were started. `Retry-After` is 60. |
| `expired_token` | `400` | The device code or its approval has expired. Start again. |
| `access_denied` | `400` | The user denied the request. |
| `temporarily_unavailable` | `502` | The relay could not start the approval. |

### JSON-RPC errors

MCP calls report errors as JSON-RPC `error` objects in the body. The HTTP status is `200` unless the table says
otherwise. The methods that use them are on [`POST /mcp`](mcp.md#post-mcp) and in
[Relay events](events.md).

| Code | Status | When |
|---|---|---|
| `-32700` | `400` | The body is not valid JSON. |
| `-32600` | `400` or `202` | A batch was sent, which is not supported (`400`), or the body is a response, not a request (`202`). |
| `-32601` | `404` or `200` | The method does not exist. A client on an older protocol sees `200`. |
| `-32602` | `400` or `200` | A parameter is invalid, or the protocol `_meta` is incomplete (`400`). |
| `-32603` | `200`, `429` or `503` | The relay could not handle a subscription right now. |
| `-32000` | `405` | `GET` or `DELETE` on `/mcp`: the server answers `POST` only. |
| `-32015` | `200` | An event callback failed verification. `error.data.reason` says why. |
| `-32020` | `400` | The `Mcp-Method` or `Mcp-Name` header does not match the body. |
| `-32022` | `400` | The protocol version is not supported. `error.data` lists `supported` and `requested`. |

A missing or invalid connector credential on `/mcp` is HTTP `401` with a `WWW-Authenticate` header that points to
the discovery document, so an OAuth client knows where to start. It is not a JSON-RPC error.

## Related

- [Relay API](README.md): credentials, token shapes and the error shape in context.
- [Agent endpoints](agent.md): the routes the limits on this page guard.
- [Relay events](events.md): subscribing, delivery and retries.
- [How the relay works](../../cloud/how-it-works.md): the limits in prose.
- [Operate the relay](../../cloud/operating.md): changing the limits on a relay you run.
