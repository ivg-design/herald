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

An agent running in the cloud reaches the user's Mac through the relay (docs/CLOUD.md), never directly. Claude, Codex and any client that can send a header use a notify-only key (`Authorization: Bearer hrk_...`, Settings > Cloud > Agent keys). ChatGPT and other connectors that only support OAuth point at `https://herald-relay.ivg-design.workers.dev/mcp` with authentication OAuth; the user approves once on the Mac (banner or the 6-digit code in Settings > Cloud > Connector approvals). Both can send text notifications, read receipts and wait for replies, and nothing else. `list_connectors` shows who is connected.

## Conventions

- Always use the same `app` id (e.g. `bidbot`) so your messages get their own history, icon, sound and templates.
- Buttons: `{"label":"Open","url":"…"}`, `{"label":"Done","callback":{"payload":{…}}}` (Herald POSTs to your callbackURL), `{"label":"Archive","command":"…"}` (runs only after the user approves commands for your app once), or Apple Shortcuts via the user's templates.
- `id` lets a later notification replace an earlier banner (use it for accumulating counts).
- `persistent: true` keeps the banner until the user dismisses it; `timeout: 8` auto-dismisses.
- Coming with Herald 1.1: register a **manifest** describing your fields and actions, and the user designs the banner layout; an MCP server (`herald-mcp`) lets you design it too.
