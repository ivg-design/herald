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
