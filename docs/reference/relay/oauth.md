# Relay OAuth endpoints

The relay is its own OAuth authorization server. A connector such as ChatGPT registers itself, sends the person to a
consent page, and trades the result for tokens, without anyone copying an agent key. This page documents the
discovery documents, client registration, the browser flow (`GET /authorize`), the token endpoint and revocation.
The flow for an agent that cannot open a browser is on [Relay device flow](device-flow.md). The examples use `$RELAY`,
the relay's origin, as defined in [Relay API](README.md).

## Concepts

The approval always happens on the user's Mac. The relay shows a web page or hands out a code, and Herald shows a
banner that the user must approve. The web page alone never grants access.

| Flow | Starts at | Use it when |
|---|---|---|
| Browser | [`GET /authorize`](#get-authorize) | The client can open a browser and receive a redirect. |
| Device | [`POST /device_authorization`](device-flow.md#post-device_authorization) | The client is a sandboxed agent or a job with no browser. |

Both flows end at [`POST /token`](#post-token) and produce the same tokens. What an approved connector can do:

- It sends notifications and reads receipts and replies. The only scope is `notify`.
- It cannot send buttons, commands, scripts or any code.
- It works until the user revokes it in Herald, in **Settings > Cloud > Connector approvals**.

Every OAuth route sends permissive CORS headers and answers `OPTIONS` with `204`. Bodies are
`application/x-www-form-urlencoded`, except [`POST /register`](#post-register), which takes JSON. OAuth errors are
JSON in the shape `{"error": "...", "error_description": "..."}`.

### Token lifetime

An approved connector is a durable record in Herald. Its tokens do not follow a clock.

- Access and refresh tokens never expire and are never rotated.
- `expires_in` is `315360000` seconds, ten years, because OAuth clients expect the field.
- A refresh returns a new access token and the same refresh token. Nothing the client holds is invalidated by
  using it, so a lost response can be retried.
- Earlier access tokens stay valid. The relay keeps the newest 50 access tokens of a connector and drops older
  ones beyond that.
- A retried code exchange (same code and PKCE verifier) returns tokens again. It never undoes the approval.
- Revoking the connector in Herald ends all of its tokens and its event subscriptions at once.

### Token shapes

| Prefix | What it is |
|---|---|
| `hrc_` | An authorization code, returned in the redirect. |
| `hra_` | An access token. Send it as `Authorization: Bearer`. |
| `hrr_` | A refresh token. |
| `hrv_` | A device code, from the [device flow](device-flow.md). |

## Endpoints

| Endpoint | Purpose |
|---|---|
| [`GET /.well-known/oauth-protected-resource`](#get-well-knownoauth-protected-resource) | Describe the MCP endpoint and name the authorization server. |
| [`GET /.well-known/oauth-authorization-server`](#get-well-knownoauth-authorization-server) | List the server's endpoints and capabilities. |
| [`POST /register`](#post-register) | Register a client. |
| [`GET /authorize`](#get-authorize) | Start the browser flow. |
| [`POST /token`](#post-token) | Exchange a grant for tokens. |
| [`POST /revoke`](#post-revoke) | Revoke a token. |

### `GET /.well-known/oauth-protected-resource`

Describes the protected resource, the MCP endpoint, and names the relay as its authorization server. A client that
gets a `401` from [`/mcp`](mcp.md) reads this document next (RFC 9728).

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

**Errors**

| Status | When |
|---|---|
| `405` | The method is not `GET` (`method_not_allowed`). |

**Notes**

- `/.well-known/oauth-protected-resource/mcp` returns the same document.
- The reply is cacheable for 300 seconds.

### `GET /.well-known/oauth-authorization-server`

Describes the authorization server: where its endpoints are and what it supports (RFC 8414). A client reads it to
find `/register`, `/authorize`, `/token`, `/device_authorization` and `/revoke`.

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

**Errors**

| Status | When |
|---|---|
| `405` | The method is not `GET` (`method_not_allowed`). |

**Notes**

- `/.well-known/openid-configuration` returns the same document, for clients that look there.
- The reply is cacheable for 300 seconds.

### `POST /register`

Registers an OAuth client dynamically (RFC 7591). A client registers once and keeps its `client_id`. A client that
only uses the [device flow](device-flow.md) has no redirect address to register.

**Request**

The body is JSON.

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `client_name` | body | string | no | The name Herald shows in the approval banner, at most 60 characters. Control characters and `<` `>` are removed. Default `An app`. |
| `redirect_uris` | body | array of strings | no | One to 10 addresses. Required unless `grant_types` holds the device grant and nothing but `refresh_token` besides it. |
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
  -d '{"client_name":"My connector","redirect_uris":["https://agent.example.com/callback"]}'
```

**Example response**

The status is `201`.

```json
{
  "client_id": "hc_3fa91c0de27b45a6d1180123456789ab",
  "client_id_issued_at": 1790000000,
  "client_name": "My connector",
  "redirect_uris": ["https://agent.example.com/callback"],
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
| `token_endpoint_auth_method` | string | The method you asked for, or `none`. |
| `grant_types` | array | Always all three grant types, whatever you asked for. |
| `response_types` | array | Always `["code"]`. |
| `scope` | string | `notify`. |
| `client_secret` | string | 64 hex characters. Present only for `client_secret_post` and `client_secret_basic`. Shown once. |
| `client_secret_expires_at` | integer | `0`: the secret does not expire. Present with `client_secret`. |

**Errors**

| Status | When |
|---|---|
| `400` | The body is not JSON, or a grant type, response type or authentication method is not allowed (`invalid_client_metadata`). |
| `400` | `redirect_uris` is missing, empty, has more than 10 entries, or holds an invalid address (`invalid_redirect_uri`). |
| `429` | Too many clients registered in the last hour (`rate_limited`). The limit is 30. |

**Notes**

- Registration needs no credential.
- The hourly limit is for the whole relay. The relay's owner can change it with the `REGISTER_PER_HOUR` variable.
- The relay keeps the 200 most recently registered clients. A client that falls out of that list registers again.
- A secret is stored only as a hash. Lose it and the client registers again.

### `GET /authorize`

Starts the browser flow. It shows the consent page, a web page that names the app, lists what it will be able to
do, and waits for the user to approve on the Mac. Send the user's browser here.

**Request**

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `response_type` | query | string | yes | `code`. |
| `client_id` | query | string | yes | The id from [`POST /register`](#post-register). |
| `redirect_uri` | query | string | yes | One of the addresses the client registered, exactly. |
| `code_challenge` | query | string | yes | The PKCE challenge: 43 characters from `A-Z a-z 0-9 - _`. |
| `code_challenge_method` | query | string | yes | `S256`. No other method is accepted. |
| `state` | query | string | no | Returned unchanged on the redirect. |
| `resource` | query | string | no | The MCP address, `$RELAY/mcp`. A trailing slash is ignored. Any other value is refused. |
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

The reply is an HTML page, not JSON. The page polls the relay every 2 seconds. When the user approves on the Mac,
it sends the browser to `redirect_uri` with `code` and `state`.

```text
HTTP/2 200
content-type: text/html; charset=utf-8
cache-control: no-store

<h1>My connector wants to connect to Herald</h1>
```

The redirect after approval looks like this:

```text
https://agent.example.com/callback?code=hrc_...&state=xyz
```

**Errors**

| Status | When |
|---|---|
| `400` | The client is unknown, `redirect_uri` is not one it registered, or `device` is out of range. The page shows the error and the browser is never redirected. |
| `302` | A later check failed. The browser goes to `redirect_uri` with `error` and `error_description`. |
| `200` | The relay has no paired Mac. The page says to pair Herald first. |
| `429` | Approvals are already waiting in Herald, or too many were requested. The page asks the person to answer them or wait. |
| `502` | The relay could not start the approval. |

The `error` values of the `302` redirect:

| `error` | Cause |
|---|---|
| `unsupported_response_type` | `response_type` is not `code`. |
| `invalid_request` | PKCE is missing: `code_challenge` with `code_challenge_method=S256` is required. |
| `invalid_target` | `resource` is not the relay's MCP address. |
| `invalid_scope` | The requested scope is anything other than `notify`. |
| `access_denied` | The user denied the request, or entered five wrong approval codes. |

**Notes**

- Herald shows a banner on the Mac with **Approve** and **Deny**. The page also offers a 6-digit code, which Herald
  shows in **Settings > Cloud > Connector approvals**. Entering the right code approves. The fifth wrong code
  denies the request.
- A request lasts 10 minutes. After approval, the client has 5 minutes to exchange the code.
- The same client asking again takes over its open request, and the banner is updated with a new code. At most 3
  requests wait on one Mac at once, and at most 12 are begun an hour.
- Denying a request closes only that request. A connector that already works is untouched.
- Approval creates one agent key for the connector, named after `client_name`, with `notify` scope. It appears in
  **Settings > Cloud > Agent keys** and can be revoked there. Approving the same client again takes the place of
  its earlier key.

The consent page uses these helper routes. They belong to the page and are not an API for clients.

| Route | Used by | What it does |
|---|---|---|
| `GET /authorize/status?rid=<id>` | The consent page, every 2 seconds. | Returns `{"status": "pending"}` until the user decides, then the status with a `redirect` address. |
| `POST /authorize/code` | The page's code form. | Takes `rid` and `code` as a form. Approves on the right code, otherwise shows the tries left. |
| `POST /authorize/deny` | The page's **Deny** button. | Takes `rid` as a form and denies the request. |

### `POST /token`

Exchanges a grant for tokens. One endpoint serves all three grants, chosen by `grant_type`. A confidential client
sends its `client_secret` in the form or in a `Basic` `Authorization` header. The device grant is described in
[Relay device flow](device-flow.md#post-token).

**Request**

The body is a form. These fields are shared by every grant.

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `grant_type` | body | string | yes | `authorization_code`, `refresh_token` or `urn:ietf:params:oauth:grant-type:device_code`. |
| `client_id` | body | string | yes | The id from [`POST /register`](#post-register). |
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

This exchanges an authorization code.

```sh
curl -s -X POST "$RELAY/token" \
  -H "User-Agent: Herald-Agent/1.0" \
  -d grant_type=authorization_code \
  -d client_id=hc_3fa91c0de27b45a6d1180123456789ab \
  -d code=hrc_... \
  -d redirect_uri=https://agent.example.com/callback \
  -d code_verifier=dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk
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
| `expires_in` | integer | `315360000`, ten years. The token does not expire. The field is for clients that require it. |
| `refresh_token` | string | The refresh token, `hrr_...`. A refresh returns the same one. |
| `scope` | string | `notify`. |

**Errors**

A failed request is `400` with the OAuth error shape, except client authentication, which is `401`.

| Error | When |
|---|---|
| `invalid_grant` | A code, verifier, redirect address or refresh token is malformed, unknown, expired, for another client, or its connector was revoked. A wrong PKCE verifier is also `invalid_grant`. |
| `invalid_target` | `resource` does not match the authorization request. |
| `invalid_scope` | A refresh asked for a scope other than `notify`. |
| `unsupported_grant_type` | `grant_type` is not one of the three. |
| `invalid_client` | The client is unknown or its secret is wrong. The status is `401`. |

The device grant adds `authorization_pending`, `slow_down`, `access_denied` and `expired_token`. They are listed on
[Relay device flow](device-flow.md#post-token).

**Notes**

- An access token works on every [agent endpoint](agent.md) and on [`/mcp`](mcp.md), exactly as an agent key does.
- A retried exchange with the same code and verifier returns tokens again. A code that was never approved, or
  that is older than 5 minutes and was never exchanged, is `invalid_grant`.
- The reply carries `Cache-Control: no-store`.
- A client that authenticates with `Basic` and fails gets `401` with a `WWW-Authenticate: Basic` header.

### `POST /revoke`

Revokes a token the client holds (RFC 7009). A client calls it to sign out. It answers `200` with an empty object
even when the token is unknown, so the reply never reveals whether a token existed.

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
- A token that belongs to another client is ignored, and the reply is still `200`.
- To end a connector completely, revoke it in Herald. That also ends its other tokens and its event
  subscriptions.

## Related

- [Relay device flow](device-flow.md): the grant for an agent with no browser.
- [Relay API](README.md): credentials, token shapes and the error shape.
- [Relay MCP endpoint](mcp.md): where an access token is used.
- [Connect ChatGPT](../../cloud/connect-chatgpt.md): the task page for approving a connector.
- [Cloud and the relay](../../CLOUD.md): what the relay is and how it is hosted.
