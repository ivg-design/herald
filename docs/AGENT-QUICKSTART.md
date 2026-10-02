# Herald — quick start for an agent on this Mac

Herald is a local notification service. You can make it show the user a banner through any of these interfaces. Everything is local to the Mac; nothing leaves the machine.

## 1. CLI (simplest)

`herald` is installed at `/usr/local/bin/herald` (if missing: `cd ~/github/herald && make install-cli`).

```bash
herald notify --app bidbot --title "Bid accepted" --body "Your bid of \$4,200 was accepted" \
  --url "https://example.com/bids/42" --image /path/preview.png \
  --button "Open=https://example.com/bids/42" --sound Glass --snooze
```

JSON on stdin also works:

```bash
echo '{"app":"bidbot","title":"Bid accepted","body":"Your bid was accepted","url":"https://…",
       "buttons":[{"label":"Open","url":"https://…"}],"sound":"Glass","persistent":true}' | herald notify --json -
```

Exit codes: 0 ok, 1 usage/HTTP error (reply printed), 2 Herald is not running (launch /Applications/Herald.app).

## 2. HTTP API

`POST http://127.0.0.1:48617/v1/notify` with header `Authorization: Bearer <token>`; the token is the contents of `~/Library/Application Support/Herald/token` (the port is in `.../port`). Same JSON body as above. `GET /v1/health` needs no token. `POST /v1/register` sets your app name, icon and a `callbackURL` that Herald POSTs to when the user presses a callback button.

## 3. Clients

`~/github/herald/clients/python/herald.py` and `clients/node/herald.js` (no dependencies):

```python
from herald import Herald
Herald().notify(app="bidbot", title="Bid accepted", body="…", url="https://…")
```

## 4. Cloud agents (not on this Mac)

An agent running in the cloud reaches the user's Mac through the relay (docs/CLOUD.md), never directly. Claude, Codex and any client that can send a header use a notify-only key (`Authorization: Bearer hrk_...`, Settings > Cloud > Agent keys). ChatGPT and other connectors that only support OAuth point at the relay's `/mcp` URL (`relay_status` > `mcpURL`) with authentication OAuth; the user approves once on the Mac (banner or the 6-digit code in Settings > Cloud > Connector approvals). Both can send text notifications (with presentation fields: `persistent`, `timeoutSeconds`, `sound`, `speak`, `presentation`, ... default: the banner stays until dismissed; `expectReply` only adds Reply and Record), read receipts and wait for replies, and nothing else. `list_connectors` shows who is connected.

### Set up the cloud relay (scripted walkthrough)

The relay lives in the user's own Cloudflare account; you can set the whole thing up with the local MCP tools. The user does two things only:
create a token, and approve a connector on the Mac.

1. `relay_status`: read `setup.state`. `online` means it is done (go to step 7). `token-needed` or `ready` means continue.
2. `relay_token_url`: tell the user to open `url` (the sign-up link is `signUpURL` if they have no Cloudflare account), press Continue to
   summary, then Create Token, and paste the token to you. The page already has the permissions (three for the deploy, six Zone ones for the custom domain in step 6).
3. `relay_set_cloudflare_token {token}`. Do not echo the token anywhere.
4. Optional: `relay_settings` to read the Advanced values, `relay_settings {settings: {...}}` to change them before deploying.
5. `relay_deploy`: takes up to about a minute; the reply is the step log. On failure the error is Cloudflare's message (for example a
   missing permission): fix it and call `relay_deploy` again, which is safe to repeat and upgrades in place.
6. Custom domain (OPTIONAL). A cloud agent that calls the relay over HTTP must **send a custom User-Agent (for example `Herald-Agent/1.0`)**:
   Cloudflare rejects Python's default `Python-urllib/3.x` with Error 1010 before the request reaches the relay; any other value works
   (`urllib.request.Request(url, headers={"User-Agent": "Herald-Agent/1.0", ...})`). The custom domain turns that check off for a hostname, so
   default User-Agents work too (`relay_test` reports `browserCheckActive`): `relay_zones`, ask the user which zone, then `relay_settings {settings: {customDomain: {zone, hostname}}}`
   (suggest `herald.<zone>`; it redeploys, attaches the hostname, switches Browser Integrity Check off for it and re-points Herald, the Mac
   stays paired). Read `warnings` in the reply (Bot Fight Mode on the zone must be turned off by the user). "Token is missing Zone
   permissions" means: have the user create a new token from `relay_token_url` and repeat from step 3. Connectors added earlier must be
   re-added with the new `mcpURL`.
6b. `relay_test`: `roundTrip: true` means a notification went through the relay and reached this Mac.
7. Connect the agent: `relay_instructions {client: "chatgpt"}` (OAuth: the user adds the URL as a connector in ChatGPT and approves on the Mac;
   `list_connectors` shows pending requests and who is connected) or `relay_instructions {client: "claude"|"codex"}` plus
   `create_agent_key {name, client}` (the key is shown once; hand over the connector block). **No browser** in the agent (its consent page is
   blocked, `net::ERR_BLOCKED_BY_CLIENT`)? `relay_instructions {client: "device"}`: register, `POST /device_authorization`, tell the user the
   `user_code`, poll `POST /token`; the user presses Approve on the banner (the pending request and its code are in `list_connectors`).
8. Turn off with `relay_unpair` (revokes everything); remove with `relay_delete {confirm: true}` after asking the user.

## Conventions

- Always use the same `app` id (e.g. `bidbot`) so your messages get their own history, icon, sound and templates.
- Buttons: `{"label":"Open","url":"…"}`, `{"label":"Done","callback":{"payload":{…}}}` (Herald POSTs to your callbackURL), `{"label":"Archive","command":"…"}` (runs only after the user approves commands for your app once), or Apple Shortcuts via the user's templates.
- `id` lets a later notification replace an earlier banner (use it for accumulating counts).
- `persistent: true` keeps the banner until the user dismisses it; `timeout: 8` auto-dismisses.
- Coming with Herald 1.1: register a **manifest** describing your fields and actions, and the user designs the banner layout; an MCP server (`herald-mcp`) lets you design it too.
