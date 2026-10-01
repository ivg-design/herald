# Herald

A Growl-style notification service for macOS. Apps and scripts send notifications to Herald over
a local HTTP API; Herald draws its own always-on-top banners, keeps a per-app history, and offers
image previews, buttons, snooze, Add to Reminders and links.

Requires macOS 13 or later.

## Install

1. Download the notarized `Herald.dmg` and drag Herald to /Applications, or build from source and
   run `make install` (app to /Applications, `herald` CLI to /usr/local/bin).
2. Launch it. A bell appears in the menu bar. On first launch from /Applications it asks whether to
   start at login (also in Settings > General).
   **Launch at login** is a toggle in Settings > General (uses `SMAppService`).
3. Clients read the API token and port from `~/Library/Application Support/Herald/`.

Build from source:

```sh
brew install xcodegen
xcodegen generate
xcodebuild -project Herald.xcodeproj -scheme Herald -configuration Debug build CODE_SIGNING_ALLOWED=NO
swift test
```

Release builds are signed with Developer ID and notarized with `mac-notarize --dmg` (see
`scripts/notarize.sh`).

## API

Base URL `http://127.0.0.1:48617` (the port is also in `~/Library/Application Support/Herald/port`).
Every request except `/v1/health` needs `Authorization: Bearer <token>`. Bodies are JSON.

| Method | Path | Purpose |
|---|---|---|
| GET | `/v1/health` | `{"ok":true,"version":"1.0.0","pid":123}` (no auth) |
| POST | `/v1/register` | Register or update an app (name, icon, bundle id, callback URL, defaults) |
| POST | `/v1/notify` | Show a notification; returns `{"ok":true,"id":"..."}` |
| POST | `/v1/dismiss` | `{"app","id"}` dismiss one banner |
| POST | `/v1/dismissAll` | `{"app"}` dismiss all banners (all apps if omitted) |
| POST | `/v1/snooze` | `{"app","id","minutes"}` snooze a banner |
| POST | `/v1/unsnooze` | `{"app","id"}` bring a snoozed banner back now |
| POST | `/v1/compose` | open the Composer window (`herald compose`) |
| GET | `/v1/history?app=&limit=50` | `{"items":[...]}` newest first |
| DELETE | `/v1/history?app=` | Clear history |
| GET | `/v1/apps` | `{"apps":[...]}` |
| GET | `/v1/templates?app=` | `{"items":[...]}` templates |
| PUT | `/v1/templates` | Create or replace a template (body = template) |
| DELETE | `/v1/templates?app=&name=` | Delete a template |

Full reference: [docs/API.md](docs/API.md). Client helpers: [clients/README.md](clients/README.md).

Errors: `401 {"error":"unauthorized"}`, `400 {"error":"..."}`, `404`, `405`.

### Notification

```json
{"app":"bidbot","id":"bid-42","title":"Bid accepted","subtitle":"Acme RFP",
 "body":"Your bid was accepted. [Open proposal](https://example.com)",
 "image":"/path/preview.png","url":"https://example.com","sound":"default",
 "persistent":true,"timeout":0,"priority":"high",
 "buttons":[{"label":"Open","url":"https://example.com"},
            {"label":"Mark done","callback":{"payload":{"bid":42}}},
            {"label":"Archive","style":"destructive","command":"bidbot archive 42"}],
 "snooze":true,"reminder":{"title":"Follow up","due":"2026-10-02T09:00:00-04:00"},
 "metadata":{"any":"json"}}
```

- Only `app` and `title` are required. Unknown apps are registered implicitly.
- `id` replaces a banner with the same id in place. Without an id one is generated.
- `image`: file path, `data:` URI or https URL (cached by Herald).
- `sound`: `default` (the app's default), a system sound name such as `Glass`, a file path, or `none`.
- Banners stay until dismissed. `timeout` > 0 auto-dismisses after that many seconds (hover pauses it);
  `persistent: false` without a timeout uses 8 seconds.
- Clicking the banner opens `url`, or else focuses the app with the registered `bundleId`.
- Button styles: `default`, `destructive`, `cancel`. A button has exactly one of `url`, `command`,
  `callback`. The "Add to Reminders" button appears when `reminder` is present; `snooze: true` adds the
  clock menu.
- Body supports inline Markdown links.

- `template`: name of a saved template; its defaults and `{placeholders}` are applied first, and
  fields in the payload override them. Banner look: `layout` (`imageLeft`, `imageRight`, `hero`,
  `compact`), `accentColor`, `showSubtitle`, `showBody`, `showTimestamp`, `maxBodyLines`.

### Templates and the Composer

Templates live in `~/Library/Application Support/Herald/templates/<app>/<name>.json`. Placeholders such
as `{amount}` in a template's title, subtitle, body and url are filled from the notification's
`metadata`, then from its own fields (title, subtitle, body, app, id); unknown ones become empty.
The Composer (menu > Compose..., or `herald compose`) has a form, a live light/dark preview drawn by
the same view as real banners, **Send now**, **Save as template...** and **Copy as...** (curl, Swift,
Python, Node, CLI). The Template editor (Settings > Apps > Templates... > Edit) adds a sample-data
drawer for placeholders. Details and a worked "Bid accepted" example in every language:
[docs/AUTHORING.md](docs/AUTHORING.md).

### Callbacks

A `callback` button POSTs `{"notificationId","app","action":"<label>","payload":...}` to
`callback.url`, or to the app's registered `callbackURL`. Answer with any 2xx once the action has
happened: Herald dismisses the banner on a 2xx, keeps it and shows "Action failed" on any other status
(a 4xx is final; 408, 429 and 5xx are retried once). `HeraldCallbackServer(statusHandler:)` lets a Swift
client answer with the status of its own action.

A callback goes to a loopback address (`127.0.0.1`, `::1`, `localhost`) freely. For any other host Herald
asks you the first time a callback button is pressed (Send Once / Always Allow / Cancel); the host is also
listed in Settings > Apps, where the approval can be revoked. Redirects are never followed.

### Commands

`command` buttons run through `/bin/zsh -lc` only if the app registered with `allowCommands: true`
and you confirmed it in Settings > Apps. Otherwise the button does nothing.

## Examples

curl:

```sh
D="$HOME/Library/Application Support/Herald"
curl -s -X POST "http://127.0.0.1:$(cat "$D/port")/v1/notify" \
  -H "Authorization: Bearer $(cat "$D/token")" -H 'Content-Type: application/json' \
  -d '{"app":"demo","title":"Hello","body":"From curl","snooze":true}'
```

Swift (package product `HeraldClient`):

```swift
import HeraldClient

if HeraldClient.shared.isAvailable {
    let id = try await HeraldClient.shared.notify(HeraldNotification(
        app: "demo", title: "Build finished", body: "All tests passed",
        buttons: [HeraldButton(label: "Open", url: "https://example.com")], snooze: true))
}

// Button callbacks
let server = HeraldCallbackServer { event in print(event.action, event.payload as Any) }
try server.start()
try await HeraldClient.shared.register(HeraldAppRegistration(app: "demo", callbackURL: server.callbackURL))
```

Python (stdlib only, `clients/python/herald.py`):

```python
from herald import Herald
Herald().notify(app="demo", title="Hello", body="From Python", snooze=True)
```

Node (no dependencies, `clients/node/herald.js`):

```js
const { Herald } = require('./herald');
await new Herald().notify({ app: 'demo', title: 'Hello', body: 'From Node', snooze: true });
```

CLI: `herald notify --app demo --title Hello --body "From the shell"`.

## Security model

- The server binds to 127.0.0.1 only; nothing is reachable from the network.
- Every endpoint except `/v1/health` requires a random 256-bit Bearer token, created on first launch in
  a mode 0600 file inside a mode 0700 directory. Any process running as you can read it, so Herald
  protects against other users and remote hosts, not against code already running as you.
- Token comparison is constant-time. The token is checked on the request head, so a caller without it
  is answered 401 before any of its body is read. Bodies are limited to 1 MB, a whole request must arrive
  within 10 s, at most 32 connections are served at once, and a request with an `Origin` header or a
  `Host` other than `127.0.0.1`, `localhost` or `[::1]` is refused (browsers and DNS rebinding).
- Field limits (413 beyond them): title and subtitle 1 KB, body 16 KB, metadata 64 KB, 8 buttons (64 KB),
  image and icon specs 256 KB, 200 apps. Cached images must be PNG, JPEG, GIF, WebP, HEIC/AVIF, TIFF or
  BMP by their bytes (the type the sender names is ignored) and at most 10 MB; images no history item
  uses any more are deleted.
- A banner, button or History click opens only `http`, `https` and `mailto` links; any other URL
  (`file:`, `smb:`, custom schemes) is refused and the banner shows "Action failed".
- At most the 6 newest undismissed banners are put back on screen at launch, and banners that do not fit
  the screen are replaced by a "+N more" pill that opens History or dismisses all.
- Herald is not sandboxed (it must listen on a socket and may run commands). Command buttons are off
  unless the app requests `allowCommands` and you confirm in Settings. Callbacks go only to the URL the
  app registered or the button names.
- Reminders access is requested only when you press Add to Reminders.

## WebWatcher integration

WebWatcher can deliver its alerts through Herald. In WebWatcher's settings choose the delivery
option "Herald" (instead of macOS notifications); it registers the app id `webwatcher` with a callback
server so the banner buttons (open page, snooze, dismiss) call back into WebWatcher. If Herald is not
running WebWatcher falls back to its own notifications.

## Troubleshooting

- **"Herald is not running"** (CLI exit code 2, clients raise `HeraldUnavailable`): launch Herald.app;
  check `curl http://127.0.0.1:$(cat ~/Library/Application\ Support/Herald/port)/v1/health`.
- **401 unauthorized**: the token file changed or you passed an old token; re-read
  `~/Library/Application Support/Herald/token`.
- **Connection refused on 48617**: another program owns the port, or you changed it in Settings. Clients
  read the `port` file, so use it instead of a hard-coded number.
- **Command button does nothing**: the app needs `allowCommands: true` and your confirmation in
  Settings > Apps.
- **No sound**: check the global Mute in the menu and the notification's `sound` value.
- **Banner missing from the screen**: look in History; a snoozed banner returns at its time.
- **Add to Reminders fails**: grant Herald access in System Settings > Privacy & Security > Reminders.
- **Template not applied**: the template must belong to the same `app` as the notification; check
  `GET /v1/templates?app=`.

## Layout

`Sources/Herald` is the app (`Core/` holds the AppKit-free server, router, history and registry, which
SwiftPM also builds as `HeraldCore` for tests). `Sources/HeraldClient` is the shared library.
