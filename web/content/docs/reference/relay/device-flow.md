# Relay device flow

The device flow connects an agent that cannot open a browser, such as a sandboxed cloud agent or a CI job. It follows
RFC 8628. The agent asks the relay for a short code and shows it to the user. The user approves the request on the
Mac, and the agent collects its tokens by polling. This page documents the three routes of the flow:
the device authorization request, the activation page and the device grant of the token request. The step-by-step for a person
setting this up is in [Device flow](../../cloud/device-flow.md). The examples use `$RELAY` as defined in
[Relay API](README.md).

## Before you start

- The relay is paired with at least one Mac. See [Pairing and devices](pairing-and-devices.md).
- The client is registered with the device grant. See [`POST /register`](oauth.md#post-register). A client that only
  uses the device flow sends no `redirect_uris`.

## Concepts

The flow has four steps.

1. The agent calls [`POST /device_authorization`](#post-device_authorization) and receives a `device_code`, a
   `user_code` and an `interval`.
2. The agent shows the `user_code` and the name of the Mac to the user.
3. The user approves on the Mac: a banner with **Approve** and **Deny**, or **Settings > Cloud > Connector
   approvals**, or the relay's [`/activate`](#get-activate) page.
4. The agent polls [`POST /token`](#post-token) every `interval` seconds until it gets tokens or an error that ends
   the flow.

| Value | What it is |
|---|---|
| `device_code` | A secret that begins `hrv_`. Only the agent holds it. It is how the agent polls. |
| `user_code` | Eight consonants as `XXXX-XXXX`. The user matches it in Herald. It is not a secret. |
| Approval code | Six digits, shown only in Herald. The `/activate` page asks for it so that the agent, which knows the `user_code`, cannot approve itself. |

The tokens that come out are the same as in the browser flow. An approved connector works until revoked, its tokens
never expire and are never rotated, and `expires_in` is ten years. See [Token lifetime](oauth.md#token-lifetime).
A repeated poll after approval returns tokens again.

## Endpoints

| Endpoint | Purpose |
|---|---|
| [`POST /device_authorization`](#post-device_authorization) | Start a device request and show a banner on the Mac. |
| [`GET /activate`](#get-activate) | Serve the page where a person enters the code and approves. |
| [`POST /token`](#post-token) | Poll with the device code. |

### `POST /device_authorization`

Starts the device flow for an agent that has no usable browser. The reply holds a short `user_code` that the agent
shows to the user, and a `device_code` that the agent keeps and polls with. At the same moment, Herald shows an
approval banner on the Mac.

**Request**

The body is a form. A confidential client also sends its secret.

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `client_id` | body | string | yes | The id from [`POST /register`](oauth.md#post-register). |
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
| `device_name` | string | The name of the Mac that received the banner. `Mac 1`, `Mac 2` and so on when the Mac has no name. |
| `device_count` | integer | How many Macs are paired with the relay. |
| `device_index` | integer | The 1-based number of the chosen Mac. |
| `device_online` | boolean | `true` when that Mac is connected. |

**Errors**

| Status | When |
|---|---|
| `400` | `scope` is not `notify` (`invalid_scope`), no Mac is paired, or `device` is out of range (`invalid_request`). |
| `401` | The client is unknown or its secret is wrong (`invalid_client`). |
| `429` | Approvals are already waiting, or too many were requested this hour (`slow_down`). The reply carries `Retry-After: 60`. |
| `502` | The relay could not start the approval (`temporarily_unavailable`). |

**Notes**

- Tell the user which Mac will show the banner: `device_name` says so.
- The user sees a banner with the code and **Approve** and **Deny**. **Settings > Cloud > Connector approvals**
  lists the request with the code in large type and, in small type, a 6-digit approval code for the web page.
- Asking again with the same client takes over the open request. The earlier `device_code` stops working.
- The request lasts 10 minutes. After approval, the agent has 5 minutes to collect the tokens.
- At most 3 approvals wait on one Mac at once, and at most 12 are begun an hour.

### `GET /activate`

Serves the page where a person with a browser enters the agent's code and approves it. The page is optional: the user
can approve from the banner in Herald instead. The page asks for the `user_code` the agent printed, then for the
6-digit approval code that Herald shows.

**Request**

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `user_code` | query | string | no | Fills in the code field. |

**Example request**

```sh
curl -s "$RELAY/activate?user_code=BDFG-HJKM" -H "User-Agent: Herald-Agent/1.0"
```

**Example response**

The reply is an HTML page with status `200`.

```text
HTTP/2 200
content-type: text/html; charset=utf-8

<h1>Approve an agent</h1>
```

**Errors**

| Status | When |
|---|---|
| `500` | The relay's owner has not set its secret (`misconfigured`). |

**Notes**

- A wrong or expired `user_code` shows the entry page again with a note. It is never an error status.
- The fifth wrong approval code denies the request.

The page posts to three helper routes. They belong to the page and are not an API for clients.

| Route | What it does |
|---|---|
| `POST /activate` | Takes `user_code` as a form and shows the confirmation step for the matching request. |
| `POST /activate/approve` | Takes `rid` and `code` (the 6-digit approval code) as a form and approves. |
| `POST /activate/deny` | Takes `rid` as a form and denies the request. |

### `POST /token`

Collects the tokens of an approved device request. This is the device grant of the token endpoint. Send
`grant_type=urn:ietf:params:oauth:grant-type:device_code` and poll no faster than `interval`. The other grants,
the shared fields and the token reply are documented under [`POST /token`](oauth.md#post-token).

**Request**

The body is a form.

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `grant_type` | body | string | yes | `urn:ietf:params:oauth:grant-type:device_code`. |
| `client_id` | body | string | yes | The client that started the request. |
| `device_code` | body | string | yes | The `hrv_` code from `/device_authorization`. |
| `client_secret` | body | string | no | The secret of a confidential client. |
| `resource` | body | string | no | The MCP address. It must match the one the request was made for. |

**Example request**

```sh
curl -s -X POST "$RELAY/token" \
  -H "User-Agent: Herald-Agent/1.0" \
  -d grant_type=urn:ietf:params:oauth:grant-type:device_code \
  -d client_id=hc_3fa91c0de27b45a6d1180123456789ab \
  -d device_code=hrv_...
```

**Example response**

Once the user has approved, the reply is `200`:

```json
{
  "access_token": "hra_...",
  "token_type": "Bearer",
  "expires_in": 315360000,
  "refresh_token": "hrr_...",
  "scope": "notify"
}
```

While the user has not answered, the reply is `400`:

```json
{
  "error": "authorization_pending",
  "error_description": "waiting for the user to approve in Herald"
}
```

**Response fields**

The fields of the success reply are in [`POST /token`](oauth.md#post-token).

**Errors**

A failed poll is `400` with `{"error": "...", "error_description": "..."}`, except client authentication, which is
`401`.

| Error | When |
|---|---|
| `authorization_pending` | The user has not answered yet. Keep polling every `interval` seconds. |
| `slow_down` | You polled faster than `interval`. The interval grows by 5 seconds. Add that to yours. |
| `access_denied` | The user pressed **Deny**, or entered five wrong approval codes. Stop. |
| `expired_token` | The request expired, the approval was not collected within 5 minutes, or the code is unknown. Start again at `/device_authorization`. |
| `invalid_grant` | The `device_code` is malformed, belongs to another client, or its connector was revoked. |
| `invalid_target` | `resource` does not match the request. |
| `invalid_client` | The client is unknown or its secret is wrong. The status is `401`. |

**Notes**

- Poll no faster than `interval`. The first poll must also wait `interval` seconds after the request started, or it
  gets `slow_down`.
- A poll that gets `slow_down` or `authorization_pending` is not fatal. Only `access_denied`, `expired_token` and
  `invalid_grant` end the flow.
- A repeated poll after approval, for example after a lost response, returns tokens again. It never undoes the
  approval.
- Approval creates one agent key for the connector, named after `client_name`, with `notify` scope. It appears in
  **Settings > Cloud > Agent keys** and can be revoked there. The access token works on every
  [agent endpoint](agent.md) and on [`/mcp`](mcp.md).

## Related

- [Device flow](../../cloud/device-flow.md): the task page for connecting an agent without a browser.
- [Relay OAuth endpoints](oauth.md): registration, the browser flow, refresh and revocation.
- [Relay API](README.md): credentials and the error shape.
- [Cloud and the relay](../../CLOUD.md): what the relay is and how it is hosted.
