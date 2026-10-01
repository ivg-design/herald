# Herald clients

All clients read the port and Bearer token from `~/Library/Application Support/Herald/` and fail with a
clear "Herald is not running" error when the app is down. The wire format is in
[../docs/API.md](../docs/API.md).

| Client | Where | Dependencies |
|---|---|---|
| CLI `herald` | `Sources/herald-cli`, installed by `make install-cli` to /usr/local/bin | none |
| Swift `HeraldClient` | package library product | none |
| Python | `clients/python/herald.py` | standard library |
| Node | `clients/node/herald.js` | none (Node 18+) |

## Python

```python
from herald import Herald, HeraldUnavailable
h = Herald()
if h.is_available():
    h.register("bidbot", appName="BidBot", defaults={"sound": "Glass"})
    h.notify(app="bidbot", title="Bid accepted", template="bid-won", metadata={"amount": "$4,200"})
    h.dismiss("bidbot", "bid-42")
    print(h.history("bidbot", limit=10))
```

## Node

```js
const { Herald } = require('./herald');
const h = new Herald();
if (await h.isAvailable()) {
  await h.notify('bidbot', 'Bid accepted', { template: 'bid-won', metadata: { amount: '$4,200' } });
  console.log(await h.history('bidbot', 10));
}
```

## Swift

Add the package and depend on `HeraldClient`. `HeraldClient.shared.isAvailable` is a cheap check;
`HeraldCallbackServer` receives button callbacks on an OS-assigned loopback port.

## CLI

```sh
herald health
herald notify --app bidbot --title "Bid accepted" --button "Open=https://example.com"
herald notify --app bidbot --json payload.json      # or --json - for stdin
herald history --app bidbot --limit 20
herald dismiss --app bidbot --id bid-42
herald compose                                       # opens the Composer window
```

Exit codes: 0 ok, 1 error, 2 Herald is not running.

Template and snooze endpoints are plain HTTP calls (`/v1/templates`, `/v1/snooze`); see the API reference.

## Registering a manifest (1.1)

A manifest declares the fields your app sends, the actions it supports and optional assets, so the
Designer can offer them with sample values. Register it once at startup (it replaces the previous one for
the same `app`); then send fields at the top level of each notification. Format: [../docs/API.md](../docs/API.md#manifests).
The helpers below are plain HTTP, so they work with any client version.

### Python

```python
import json, urllib.request
from herald import Herald

h = Herald()
manifest = {
    "app": "bidbot", "appName": "BidBot", "version": 1,
    "fields": [{"key": "title", "type": "text", "required": True, "sample": "Bid accepted"},
               {"key": "amount", "type": "text", "sample": "$4,200"},
               {"key": "url", "type": "url"}],
    "actions": [{"id": "archive", "label": "Archive", "kind": "callback", "style": "destructive"}],
}
req = urllib.request.Request(h.base_url + "/v1/manifest", method="PUT",
                             data=json.dumps(manifest).encode(),
                             headers={"Authorization": "Bearer " + h.token,
                                      "Content-Type": "application/json"})
urllib.request.urlopen(req).read()
h.notify(app="bidbot", title="Bid accepted", amount="$4,200", url="https://example.com/p/42")
```

### Node

```js
const { Herald } = require('./herald');
const h = new Herald();
await h._request('PUT', '/v1/manifest', { body: {
  app: 'bidbot', appName: 'BidBot', version: 1,
  fields: [{ key: 'title', type: 'text', required: true, sample: 'Bid accepted' },
           { key: 'amount', type: 'text', sample: '$4,200' }],
  actions: [{ id: 'archive', label: 'Archive', kind: 'callback' }],
}});
await h.notify('bidbot', 'Bid accepted', { amount: '$4,200' });
```

### CLI / curl

```sh
D="$HOME/Library/Application Support/Herald"
curl -s -X PUT "http://127.0.0.1:$(cat "$D/port")/v1/manifest" \
  -H "Authorization: Bearer $(cat "$D/token")" -H 'Content-Type: application/json' \
  -d @manifest.json
herald notify --app bidbot --json payload.json
```

Read manifests back with `GET /v1/manifests`; list installed Apple Shortcuts with `GET /v1/shortcuts`.
`herald-mcp` (see [../docs/MCP.md](../docs/MCP.md)) exposes the same operations to agents.
