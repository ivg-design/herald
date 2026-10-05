# Relay API

The relay is the small service in your Cloudflare account that sits between a cloud agent and your Mac. It holds
a mailbox for the Mac: an agent puts notifications in, Herald takes them out over one outgoing connection, and
receipts and replies travel back the same way. This reference documents the API the relay serves from its own
address. Read it if you are writing a cloud agent or an integration that talks to the relay, or if you operate or
re-implement a relay.

Herald's own **local** API, with the `/v1/relay/*` routes that deploy and pair a relay from the Mac, is a different
thing. It is documented in [Cloud relay API (local)](../api/relay.md).

All examples use two variables. `$RELAY` is the relay's origin and `$KEY` is the credential an agent holds.

```sh
RELAY="https://herald-relay.example.workers.dev"
KEY="hrk_..."
```

`$KEY` is an agent key (`hrk_...`) or a connector access token (`hra_...`). Both are sent the same way, as
`Authorization: Bearer $KEY`.

## The pages

The relay API is split by who calls it and what for. Each endpoint is documented once, on the page that owns it.

| Page | What it covers |
|---|---|
| [Agent endpoints](agent.md) | Send a notification, read its receipt and reply, check the Mac, download a voice reply. |
| [MCP endpoint](mcp.md) | The `/mcp` route and its four tools. |
| [MCP Events](events.md) | Subscribe to `notification.reply` and receive signed webhooks. |
| [OAuth](oauth.md) | Discovery documents, client registration, the browser approval flow, tokens and revocation. |
| [Device flow](device-flow.md) | Connect an agent that has no browser. |
| [Pairing and devices](pairing-and-devices.md) | Pair a Mac and manage the Macs on a relay. |
| [Device side](device-side.md) | The routes Herald itself uses: the stream, receipts, keys, approvals and subscriptions. |
| [Limits and errors](limits-and-errors.md) | Every limit, every error code and every status. |

## Who calls the relay

A relay has three kinds of caller, and each one holds a different credential.

| Caller | Credential | What it may call |
|---|---|---|
| A cloud agent | An agent key (`hrk_...`) or a connector access token (`hra_...`). | The [agent endpoints](agent.md) and the [MCP endpoint](mcp.md). |
| Herald on a Mac | The device token (`hrd_...`), made when the Mac pairs. | The `/v1/device/*` routes on the [device side](device-side.md) and in [pairing and devices](pairing-and-devices.md). |
| Anyone | None. | Discovery, OAuth, the health check, signed audio links and [pairing](pairing-and-devices.md). |

The credentials cannot be swapped. An agent key or access token on a `/v1/device/*` route gets `403
wrong_credential`, and the device token on an agent route gets the same answer. An agent key can only send
notifications and read what it sent. It cannot change a setting, a quiet hour or anything else on the Mac.

## Credentials

A token is made of a prefix, the id of the Mac it belongs to, and a secret. The device id carries a signature
that the relay checks before it touches any storage, so a guessed token never creates a mailbox. A malformed
token, or one whose device id does not verify, gets `401 unauthorized`.

| Token | Shape | Used as |
|---|---|---|
| Device token | `hrd_<deviceId>_<secret>` | The bearer credential of Herald on a paired Mac. |
| Agent key | `hrk_<deviceId>_<keyId>_<secret>` | The bearer credential of an agent you gave a key to. |
| Access token | `hra_<deviceId>_<secret>` | The bearer credential of an approved connector. |
| Refresh token, code, device code | `hrr_...`, `hrc_...`, `hrv_...` | Sent only to `/token` and `/revoke`. Never a bearer credential. |

The device id is 48 hex characters. A secret is 64 hex characters. A key id is 8 hex characters.

The relay stores only a hash of every secret, so a lost token cannot be read back. A key or a connector is
revoked from the Mac, in **Settings > Cloud**, or with
[`DELETE /v1/device/keys/{keyId}`](device-side.md#delete-v1devicekeyskeyid).

> [!NOTE]
> An approved connector works until it is revoked. Its access tokens never expire and are never rotated. The
> `expires_in` field of a token reply says ten years only because OAuth clients expect the field. A refresh
> returns a new access token and the same refresh token. Event subscriptions do not lapse either. See
> [OAuth](oauth.md#post-token) and [MCP Events](events.md).

## What a credential can send

An agent key or access token can send a notification that holds text, a link, a priority and a few presentation
options. It cannot send buttons, commands, scripts, callbacks or any other code. The relay refuses a notification
that carries such a field with `400 forbidden_fields` and names the field. See
[`POST /v1/notify`](agent.md#post-v1notify).

Event callbacks may go to any public https host. The relay's owner can narrow that with the `EVENT_CALLBACK_HOSTS`
variable. See [MCP Events](events.md).

## Responses and errors

Every reply is JSON unless a block says otherwise. An error reply has this shape. The `retryAfterSeconds` and
`fields` members appear only on the replies that name them.

```json
{
  "error": "rate_limited",
  "message": "at most 60 notifications per 10 minutes per key",
  "retryAfterSeconds": 412
}
```

| Member | Type | Description |
|---|---|---|
| `error` | string | A short code such as `rate_limited` or `forbidden_fields`. |
| `message` | string | A sentence for a person. |
| `retryAfterSeconds` | integer | How long to wait. Present on `429` and `503` replies about a limit. |
| `fields` | array | The rejected field names. Present on `forbidden_fields`. |

Two families use another format. The OAuth routes answer with `error` and `error_description`, as OAuth
requires. The `/mcp` route answers with JSON-RPC errors. The pages that own those routes list their errors.
[Limits and errors](limits-and-errors.md) lists every code and status.

## Send a User-Agent

> [!NOTE]
> Send a custom `User-Agent` header with every request an agent makes. On a relay without a custom domain,
> Cloudflare's Browser Integrity Check rejects the default Python `urllib` agent before the request reaches the
> relay. Any other value works, so the examples send `Herald-Agent/1.0`. See
> [Custom domain](../../cloud/custom-domain.md) for the alternative.

## Related

- [Cloud relay](../../CLOUD.md): what the relay is and how to set it up.
- [How the relay works](../../cloud/how-it-works.md): architecture and security in prose.
- [Connect an agent](../../cloud/connect-agent.md): make an agent key and use it.
- [Cloud relay API (local)](../api/relay.md): the routes on Herald's own API that manage the relay from the Mac.
