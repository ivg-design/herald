# Herald Connection: the plugin for OpenAI dots

A dot is an always-on cloud agent from OpenAI. A dot's host only issues event callbacks (the wake-up webhook for MCP Events) for an MCP server it knows as a **registered app
behind an installed plugin**. A connection the dot makes from its own code, with a device-flow token, sends notifications fine but can
never be woken by a reply. This folder is the plugin wrapper that makes Herald a host-recognised event source, built the same way as
the owner's other dot plugins.

Nothing here contains a secret. `.app.json` holds the registered app id once it exists.

## What has to happen once (needs the owner's ChatGPT account)

1. **Register the app.** In ChatGPT (developer mode), create a custom MCP app / connector:
   - Name: `Herald Connection`
   - MCP server URL: the owner's relay `/mcp` URL (Herald > Settings > Cloud shows it; `relay_status` returns `mcpURL`)
   - Authentication: OAuth, client id and secret left empty (the relay supports discovery, dynamic client registration and PKCE)
2. **Connect it.** Pressing Connect opens the relay's consent page. A banner appears on the owner's Mac: **Approve**. (If the banner
   was missed, the 6-digit code is in Herald > Settings > Cloud > Connector approvals.) This is the one recorded handshake; it is durable.
3. **Map the plugin to the app.** Put the resulting app id (`asdk_app_...`) into `herald-connection/.app.json` in place of
   `REPLACE_WITH_REGISTERED_APP_ID`, bump the version in both `plugin.json` files if a package was already installed, and install the
   plugin for the dot. The owner activates it.
4. **Subscribe through the host.** Ask the dot to subscribe to `notification.reply` on the Herald Connection app, using the host's
   MCP Events support and the callback URL the host issues. The relay verifies the callback with a signed challenge. No approval,
   code or allow-list step exists on the Herald side: the connector's approval covers it, and the subscription does not expire.
5. **Verify.** Send a notification with `expectReply: true`, reply on the Mac, and confirm (a) Herald > Settings > Cloud > Reply
   subscriptions shows the subscription with nothing waiting, and (b) the reply actually woke a run of the dot. Only (b) proves wake.

## Relay facts the host integration relies on

- `/mcp` is dual-era: legacy `initialize` (2025-06-18, 2025-03-26, 2024-11-05) with tools only; modern `2026-07-28` with
  `server/discover` (capabilities `tools`, `events`), `events/list`, `events/subscribe`, `events/unsubscribe`.
- Event: `notification.reply`, no arguments, payload `{notificationId, id, kind: "text"|"voice"}`.
- Subscribe: `delivery {mode: "webhook", url (https, default port, public host), secret (whsec_ + base64 of 24-64 bytes)}`; a signed
  `{type: "verification", challenge}` must be echoed with 2xx. Failures are `-32015` with `data.reason`.
- Delivery: Standard Webhooks headers (`webhook-id`, `webhook-timestamp`, `webhook-signature: v1,...`) and `X-MCP-Subscription-Id`;
  retries with backoff; 410 ends the subscription.
- Durable: tokens never expire or rotate; `refreshBefore` is reported ten years ahead; `ttlMs` is accepted and ignored.
- Full reference: `docs/CLOUD.md`, "Being told about a reply (event subscription)".

## If the host's subscribe call fails

Record the exact JSON-RPC error and the request the host sent (method, headers `MCP-Protocol-Version` / `Mcp-Method`, and the shape of
`params`, with the secret removed) and bring it back to the Herald repo: the relay is ours to adjust.
