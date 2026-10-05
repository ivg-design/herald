# Herald clients

Herald is controlled over a local HTTP API, and three small clients wrap it so your code does not build requests by
hand: a Swift package for macOS apps, a Python module and a Node module. Each one finds the running Herald, adds the bearer
token, sends the request and raises a clear error when Herald is not running. For shell scripts there is also the
[command line tool](../docs/reference/cli.md), and for agents the [MCP server](../docs/MCP.md).

All three clients read the port and token from Herald's support folder, `~/Library/Application Support/Herald/`, the same
two files the [API](../docs/reference/api/README.md#connect) describes. They talk to `127.0.0.1` only. A client
function is a thin wrapper: the request and reply fields are documented once, in the endpoint it names.

| Client | Where | Needs | Covers |
|---|---|---|---|
| [Swift `HeraldClient`](#swift) | The `HeraldClient` library product of this package. | macOS 13 or later. No dependencies. | Notifications, apps, History, stacks, quiet hours, manifests, templates, previews, and every other route. |
| [Python](#python) | `clients/python/herald.py` | Python 3 and its standard library. | Notifications, apps and History. |
| [Node](#node) | `clients/node/herald.js` | Node 18 or later. No dependencies. | Notifications, apps and History. |

The Python and Node clients cover what most integrations need: send a notification, dismiss it, read History. For a
manifest, a template or a preview from those languages, call the HTTP route yourself, as
[Registering a manifest](#registering-a-manifest) shows.

## Swift

`HeraldClient` is a Swift package library with no dependencies. It has typed models for notifications, buttons,
manifests and templates, an async client, and a small server that receives button callbacks. Use it from a macOS app
or a command line tool.

**Add it**

Add the package to your `Package.swift` and depend on the `HeraldClient` product:

```swift
dependencies: [
    .package(url: "https://github.com/ivg-design/herald.git", branch: "main"),
],
targets: [
    .target(name: "MyApp", dependencies: [
        .product(name: "HeraldClient", package: "herald"),
    ]),
]
```

In an Xcode project, use **File > Add Package Dependencies** with the same address.

**Minimal example**

```swift
import HeraldClient

let herald = HeraldClient.shared
guard herald.isAvailable else { return }          // a cheap check; false when Herald is not running
let id = try await herald.notify(HeraldNotification(app: "example.bidbot", title: "Bid accepted"))
```

`notify` returns the notification id. `HeraldClient.shared` reads the default support folder. `isAvailable` is true
when the token and port files exist and the health endpoint answers within a second.

**Realistic example**

Register the app with a callback address, send a notification with buttons, and receive the button presses:

```swift
import HeraldClient

let callbacks = HeraldCallbackServer(handler: { event in
    // event.action is the label of the button; event.payload is the JSON you attached to it.
    print("\(event.notificationId): \(event.action) \(String(describing: event.payload))")
})
try callbacks.start()

let herald = HeraldClient.shared
try await herald.register(HeraldAppRegistration(
    app: "example.bidbot", appName: "BidBot",
    callbackURL: callbacks.callbackURL,
    defaults: HeraldAppDefaults(sound: "Glass")))

let id = try await herald.notify(HeraldNotification(
    app: "example.bidbot", id: "bid-42", title: "Counter-offer from Acme",
    body: "They offer $3,900. Accept?",
    buttons: [
        HeraldButton(label: "Accept", callback: HeraldCallback(payload: .object(["decision": .string("accept")]))),
        HeraldButton(label: "Decline", style: "destructive",
                     callback: HeraldCallback(payload: .object(["decision": .string("decline")]))),
    ],
    snooze: true))

let recent = try await herald.history(app: "example.bidbot", limit: 10)
try await herald.dismiss(app: "example.bidbot", id: id)
callbacks.stop()
```

`HeraldCallbackServer` listens on a loopback port that the system picks, so `callbacks.callbackURL` is only known after `start()`. See [Actions](../docs/ACTIONS.md) for the callback request.

How Herald reads the answer to a callback:

- Any `2xx` answer means "the action happened", and Herald closes the banner.
- When your action can fail, create the server with `HeraldCallbackServer(statusHandler:)` and return `200` only after the action succeeded.
- A `4xx` is final. `408`, `429` and `5xx` make Herald retry once.
- Herald waits at most 5 seconds for the answer.

**Second instance**

`HeraldClient(supportDirectory:port:token:)` points a client at another Herald, such as the
[second instance used for testing](../docs/TESTING.md#run-a-second-instance-of-herald). The `HERALD_SUPPORT_DIR`
environment variable has the same effect on `HeraldClient.shared`.

**Errors**

Calls throw `HeraldError`.

| Case | When |
|---|---|
| `.notRunning` | There is no token or port file, or nothing answers on the port. |
| `.unauthorized` | Herald answered `401`: the token is wrong. |
| `.server(status:message:)` | Herald answered with another error. `message` is the `error` text of the reply. |
| `.invalidResponse` | The reply was not what the client expected. |

**Functions**

| Function | What it does | Endpoint |
|---|---|---|
| `isAvailable` | Tells whether Herald answers, without throwing. | [`GET /v1/health`](../docs/reference/api/diagnostics.md#get-v1health) |
| `health()` | Returns `ok`, the app version and its process id. | [`GET /v1/health`](../docs/reference/api/diagnostics.md#get-v1health) |
| `notify(_:)` | Shows a notification and returns its id. | [`POST /v1/notify`](../docs/reference/api/notifications.md#post-v1notify) |
| `notify(payload:)` | Sends a JSON payload exactly as given, so manifest fields stay at the top level. | [`POST /v1/notify`](../docs/reference/api/notifications.md#post-v1notify) |
| `speak(_:)` | Says text aloud with no banner. | [`POST /v1/speak`](../docs/reference/api/notifications.md#post-v1speak) |
| `register(_:)` | Registers or updates an app. | [`POST /v1/register`](../docs/reference/api/apps.md#post-v1register) |
| `dismiss(app:id:)` | Closes one banner. | [`POST /v1/dismiss`](../docs/reference/api/notifications.md#post-v1dismiss) |
| `dismissAll(app:)` | Closes every banner of an app. | [`POST /v1/dismissAll`](../docs/reference/api/notifications.md#post-v1dismissall) |
| `dismissAll(app:group:)` | Closes the banners of one stack. | [`POST /v1/dismissAll`](../docs/reference/api/notifications.md#post-v1dismissall) |
| `stacks(app:)` | Lists the stacks on screen. | [`GET /v1/stacks`](../docs/reference/api/stacks.md#get-v1stacks) |
| `history(app:limit:)` | Returns stored notifications, newest first. | [`GET /v1/history`](../docs/reference/api/history.md#get-v1history) |
| `quietHours()` | Returns the quiet-hours schedule and what is silenced now. | [`GET /v1/settings/quiet-hours`](../docs/reference/api/settings.md#get-v1settingsquiet-hours) |
| `setQuietHours(_:)` | Changes the schedule or starts a one-off quiet period. | [`PUT /v1/settings/quiet-hours`](../docs/reference/api/settings.md#put-v1settingsquiet-hours) |
| `apps()` | Lists registered apps. | [`GET /v1/apps`](../docs/reference/api/apps.md#get-v1apps) |
| `manifests()` | Lists every manifest. | [`GET /v1/manifests`](../docs/reference/api/manifests.md#get-v1manifests) |
| `manifest(app:)` | Returns one app's manifest, or `nil` when it has none. | [`GET /v1/manifest`](../docs/reference/api/manifests.md#get-v1manifest) |
| `putManifest(_:)` | Saves an app's manifest. | [`PUT /v1/manifest`](../docs/reference/api/manifests.md#put-v1manifest) |
| `deleteManifest(app:)` | Deletes an app's manifest. | [`DELETE /v1/manifest`](../docs/reference/api/manifests.md#delete-v1manifest) |
| `templates(app:)` | Lists saved templates. | [`GET /v1/templates`](../docs/reference/api/templates.md#get-v1templates) |
| `template(app:name:)` | Returns one template, including the built-in `builtin.*` ones. | [`GET /v1/templates`](../docs/reference/api/templates.md#get-v1templates) |
| `putTemplate(_:)` | Saves a template. | [`PUT /v1/templates`](../docs/reference/api/templates.md#put-v1templates) |
| `deleteTemplate(app:name:)` | Deletes a template. | [`DELETE /v1/templates`](../docs/reference/api/templates.md#delete-v1templates) |
| `components()` | Returns the component schema. | [`GET /v1/components`](../docs/reference/api/templates.md#get-v1components) |
| `shortcuts()` | Lists the installed Apple Shortcuts. | [`GET /v1/shortcuts`](../docs/reference/api/templates.md#get-v1shortcuts) |
| `preview(_:)` | Draws a template offscreen and returns the PNG bytes. | [`POST /v1/preview`](../docs/reference/api/templates.md#post-v1preview) |
| `designerSnapshot(app:template:select:width:height:)` | Draws the Designer window offscreen and returns the PNG bytes. | [`GET /v1/designer/snapshot`](../docs/reference/api/diagnostics.md#get-v1designersnapshot) |
| `call(_:_:query:body:timeout:)` | Sends any authenticated request and returns the JSON reply. Use it for the routes with no typed function. | Any route in the [API reference](../docs/reference/api/README.md). |

`HeraldCallbackServer` is the one part that is not a request: it is a listener for the callbacks Herald sends. See the
[callback request](../docs/reference/api/replies.md#callback-request).

## Python

`clients/python/herald.py` is one file that uses only the Python standard library. Copy it next to your script, or put
its folder on `PYTHONPATH`.

**Minimal example**

```python
from herald import Herald

Herald().notify("example.bidbot", "Bid accepted")
```

`notify(app, title, **fields)` returns the notification id. Every extra keyword becomes a field of the notification.

**Realistic example**

Register the app, send a notification with buttons, update it, and read History. The second `notify` reuses the `id`, so
Herald replaces the banner instead of stacking a new one.

```python
from herald import Herald, HeraldError, HeraldUnavailable

h = Herald()
try:
    if h.is_available():
        h.register("example.bidbot", appName="BidBot",
                   callbackURL="http://127.0.0.1:5123/herald", defaults={"sound": "Glass"})
        h.notify("example.bidbot", "Counter-offer from Acme",
                 id="bid-42", body="They offer $3,900. Accept?", sound="Glass", snooze=True,
                 buttons=[{"label": "Accept", "callback": {"payload": {"decision": "accept"}}},
                          {"label": "Open", "url": "https://example.com/bids/42"}])
        h.notify("example.bidbot", "Counter-offer from Acme", id="bid-42",
                 body="They now offer $4,100. Accept?")
        for item in h.history("example.bidbot", limit=5):
            print(item["id"], item["notification"]["title"])
        h.dismiss("example.bidbot", "bid-42")
except HeraldUnavailable:
    print("Herald is not running")
except HeraldError as e:
    print("Herald refused the request:", e.status, e.message)
```

A callback button posts to the `callbackURL` you registered. A receiver needs only the standard library. Herald sends a JSON object and treats a `2xx` answer as success. The fields of the object are in [the callback request](../docs/reference/api/replies.md#callback-request).

A receiver looks like this:

```python
import json
from http.server import BaseHTTPRequestHandler, HTTPServer

class Callback(BaseHTTPRequestHandler):
    def do_POST(self):
        event = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        print(event["notificationId"], event["action"], event.get("payload"))
        self.send_response(200)
        self.end_headers()

HTTPServer(("127.0.0.1", 5123), Callback).serve_forever()
```

**Second instance**

The module reads the default support folder. For another Herald, pass the port and token:
`Herald(port=48700, token=open("/tmp/herald-test/token").read().strip())`.

**Errors**

Two exceptions matter:

- `HeraldUnavailable` means Herald is not running. It is a subclass of `HeraldError`.
- `HeraldError` carries `status` and `message` for an error answer.

The client waits 10 seconds by default. `Herald(timeout=...)` changes it.

**Functions**

| Function | What it does | Endpoint |
|---|---|---|
| `is_available()` | Returns `True` when Herald answers. | [`GET /v1/health`](../docs/reference/api/diagnostics.md#get-v1health) |
| `health()` | Returns `ok`, the version and the process id. | [`GET /v1/health`](../docs/reference/api/diagnostics.md#get-v1health) |
| `notify(app, title, **fields)` | Shows a notification and returns its id. | [`POST /v1/notify`](../docs/reference/api/notifications.md#post-v1notify) |
| `register(app, **fields)` | Registers or updates an app. | [`POST /v1/register`](../docs/reference/api/apps.md#post-v1register) |
| `dismiss(app, id)` | Closes one banner. | [`POST /v1/dismiss`](../docs/reference/api/notifications.md#post-v1dismiss) |
| `dismiss_all(app)` | Closes every banner of an app. | [`POST /v1/dismissAll`](../docs/reference/api/notifications.md#post-v1dismissall) |
| `history(app, limit=50)` | Returns the stored notifications as a list. | [`GET /v1/history`](../docs/reference/api/history.md#get-v1history) |
| `clear_history(app)` | Deletes an app's History. | [`DELETE /v1/history`](../docs/reference/api/history.md#delete-v1history) |
| `apps()` | Lists registered apps. | [`GET /v1/apps`](../docs/reference/api/apps.md#get-v1apps) |

## Node

`clients/node/herald.js` is one file with no dependencies. It needs Node 18 or later, for the built-in `fetch`. It is a
CommonJS module that an ES module can also import.

**Minimal example**

```js
const { Herald } = require('./herald');

await new Herald().notify('example.bidbot', 'Bid accepted');
```

`notify(app, title, fields)` returns the notification id. `fields` is an object of any other notification fields.

**Realistic example**

```js
const { Herald, HeraldError, HeraldUnavailable } = require('./herald');

const h = new Herald();
try {
  if (await h.isAvailable()) {
    await h.register('example.bidbot', {
      appName: 'BidBot', callbackURL: 'http://127.0.0.1:5123/herald', defaults: { sound: 'Glass' },
    });
    await h.notify('example.bidbot', 'Counter-offer from Acme', {
      id: 'bid-42', body: 'They offer $3,900. Accept?', sound: 'Glass', snooze: true,
      buttons: [
        { label: 'Accept', callback: { payload: { decision: 'accept' } } },
        { label: 'Open', url: 'https://example.com/bids/42' },
      ],
    });
    for (const item of await h.history('example.bidbot', 5)) console.log(item.id, item.notification.title);
    await h.dismiss('example.bidbot', 'bid-42');
  }
} catch (e) {
  if (e instanceof HeraldUnavailable) console.error('Herald is not running');
  else if (e instanceof HeraldError) console.error('Herald refused the request:', e.status, e.message);
  else throw e;
}
```

**Second instance**

The module reads the default support folder. For another Herald, pass the port and token:
`new Herald({ port: 48700, token: '...' })`. The options are `port`, `token` and `timeoutMs` (default 10000).

**Errors**

Two errors matter:

- `HeraldUnavailable` means Herald is not running. It extends `HeraldError`.
- `HeraldError` carries `status` for an error answer.

`isAvailable()` returns `false` when Herald answers with an error, and throws `HeraldUnavailable` when it does not answer at all.

**Functions**

| Function | What it does | Endpoint |
|---|---|---|
| `isAvailable()` | Resolves `true` when Herald answers. | [`GET /v1/health`](../docs/reference/api/diagnostics.md#get-v1health) |
| `health()` | Resolves `ok`, the version and the process id. | [`GET /v1/health`](../docs/reference/api/diagnostics.md#get-v1health) |
| `notify(app, title, fields)` | Shows a notification and resolves its id. | [`POST /v1/notify`](../docs/reference/api/notifications.md#post-v1notify) |
| `register(app, fields)` | Registers or updates an app. | [`POST /v1/register`](../docs/reference/api/apps.md#post-v1register) |
| `dismiss(app, id)` | Closes one banner. | [`POST /v1/dismiss`](../docs/reference/api/notifications.md#post-v1dismiss) |
| `dismissAll(app)` | Closes every banner of an app. | [`POST /v1/dismissAll`](../docs/reference/api/notifications.md#post-v1dismissall) |
| `history(app, limit = 50)` | Resolves the stored notifications as an array. | [`GET /v1/history`](../docs/reference/api/history.md#get-v1history) |
| `clearHistory(app)` | Deletes an app's History. | [`DELETE /v1/history`](../docs/reference/api/history.md#delete-v1history) |
| `apps()` | Resolves the registered apps. | [`GET /v1/apps`](../docs/reference/api/apps.md#get-v1apps) |

## Registering a manifest

A manifest declares the fields your app sends, the actions it offers and any assets, so the Designer can show them with
sample values and a template can bind them. Register it once when your app starts. Saving a manifest for an app replaces
the one before it. Then send the fields at the top level of each notification. The format is in the
[manifest reference](../docs/reference/manifests.md); the route is
[`PUT /v1/manifest`](../docs/reference/api/manifests.md#put-v1manifest).

The Python and Node clients have no manifest function, so the examples call the route with the client's own address and
token. Swift has `putManifest(_:)`.

### Swift

```swift
import HeraldClient

let manifest = try HeraldJSON.decoder().decode(HeraldManifest.self, from: Data("""
{"app": "example.bidbot", "appName": "BidBot", "version": 1,
 "fields": [{"key": "title", "type": "text", "required": true, "sample": "Bid accepted"},
            {"key": "amount", "type": "text", "sample": "$4,200"},
            {"key": "url", "type": "url"}],
 "actions": [{"id": "archive", "label": "Archive", "kind": "callback", "style": "destructive"}]}
""".utf8))
try await HeraldClient.shared.putManifest(manifest)

// Manifest fields go at the top level of the payload, the way an app sends them.
_ = try await HeraldClient.shared.notify(payload: .object([
    "app": .string("example.bidbot"), "title": .string("Bid accepted"),
    "amount": .string("$4,200"), "url": .string("https://example.com/bids/42"),
]))
```

### Python

```python
import json
import urllib.request
from herald import Herald

h = Herald()
manifest = {
    "app": "example.bidbot", "appName": "BidBot", "version": 1,
    "fields": [{"key": "title", "type": "text", "required": True, "sample": "Bid accepted"},
               {"key": "amount", "type": "text", "sample": "$4,200"},
               {"key": "url", "type": "url"}],
    "actions": [{"id": "archive", "label": "Archive", "kind": "callback", "style": "destructive"}],
}
request = urllib.request.Request(
    h.base_url + "/v1/manifest", method="PUT", data=json.dumps(manifest).encode(),
    headers={"Authorization": "Bearer " + h.token, "Content-Type": "application/json"})
urllib.request.urlopen(request).read()

h.notify("example.bidbot", "Bid accepted", amount="$4,200", url="https://example.com/bids/42")
```

### Node

```js
const { Herald } = require('./herald');

const h = new Herald();
await fetch(h.baseUrl + '/v1/manifest', {
  method: 'PUT',
  headers: { Authorization: `Bearer ${h.token}`, 'Content-Type': 'application/json' },
  body: JSON.stringify({
    app: 'example.bidbot', appName: 'BidBot', version: 1,
    fields: [{ key: 'title', type: 'text', required: true, sample: 'Bid accepted' },
             { key: 'amount', type: 'text', sample: '$4,200' }],
    actions: [{ id: 'archive', label: 'Archive', kind: 'callback' }],
  }),
});
await h.notify('example.bidbot', 'Bid accepted', { amount: '$4,200' });
```

### Shell

```sh
D="$HOME/Library/Application Support/Herald"
curl -s -X PUT "http://127.0.0.1:$(cat "$D/port")/v1/manifest" \
  -H "Authorization: Bearer $(cat "$D/token")" -H "Content-Type: application/json" \
  -d @manifest.json
```

The [command line tool](../docs/reference/cli.md) has no command that saves a manifest. It can delete one, with
[`herald manifest delete`](../docs/reference/cli.md#herald-manifest-delete). To read manifests back, use
[`GET /v1/manifests`](../docs/reference/api/manifests.md#get-v1manifests).
