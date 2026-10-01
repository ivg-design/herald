# Herald API reference

Herald listens on `http://127.0.0.1:48617` (the port is also written to
`~/Library/Application Support/Herald/port` and can be changed in Settings). All bodies are JSON
(`Content-Type: application/json`). Every endpoint except `/v1/health` needs
`Authorization: Bearer <token>`; the token lives in `~/Library/Application Support/Herald/token`.

```sh
D="$HOME/Library/Application Support/Herald"
BASE="http://127.0.0.1:$(cat "$D/port")"
AUTH="Authorization: Bearer $(cat "$D/token")"
```

## Endpoints

| Method | Path | Purpose |
|---|---|---|
| GET | `/v1/health` | `{"ok":true,"version":"1.0.0","pid":123}`. No auth. Use it to detect that Herald is running. |
| POST | `/v1/register` | Register or update an app. |
| POST | `/v1/notify` | Show a notification. Resolves `template` first. |
| POST | `/v1/dismiss` | `{"app","id"}` dismiss one banner. |
| POST | `/v1/dismissAll` | `{"app"}` dismiss every banner of the app (all apps if omitted). |
| POST | `/v1/snooze` | `{"app","id","minutes"}` snooze a banner. `{"ok":true,"until":"<ISO 8601>"}` |
| POST | `/v1/unsnooze` | `{"app","id"}` bring a snoozed banner back now (silently). |
| POST | `/v1/compose` | Open the Composer window (`herald compose`). |
| GET | `/v1/history?app=&limit=50` | `{"items":[...]}` newest first, full records. |
| DELETE | `/v1/history?app=` | Clear an app's history. |
| GET | `/v1/apps` | Registered apps and their settings. |
| GET | `/v1/templates?app=` | `{"items":[...]}` templates of the app (all apps if omitted). |
| PUT | `/v1/templates` | Create or replace a template (body is the template). `{"ok":true}` |
| DELETE | `/v1/templates?app=&name=` | Delete a template. `{"ok":true}` |

Errors: `401 {"error":"unauthorized"}`, `400 {"error":"..."}`, `404`, `405`.

### POST /v1/register

```json
{"app":"bidbot","appName":"BidBot","icon":"/path/icon.png","bundleId":"com.example.bidbot",
 "callbackURL":"http://127.0.0.1:5123/herald","allowCommands":false,
 "defaults":{"sound":"Glass","persistent":true,"timeout":0,"corner":"topRight"}}
```

`icon` is a file path or a `data:image/png;base64,...` URI. Registering is optional: unknown app ids are
registered on their first notification and get a generic icon. `allowCommands: true` is only a request;
the user must confirm it in Settings > Apps before `command` buttons run.

### POST /v1/notify

```json
{"app":"bidbot","id":"bid-42","template":"bid-won",
 "title":"Bid accepted","subtitle":"Acme RFP",
 "body":"Your bid of $4,200 was accepted. [Open proposal](https://example.com/p/42)",
 "image":"/path/preview.png","url":"https://example.com/p/42",
 "sound":"default","persistent":true,"timeout":0,"priority":"high",
 "buttons":[{"label":"Open","url":"https://example.com/p/42"},
            {"label":"Mark done","callback":{"payload":{"bid":42}}},
            {"label":"Archive","style":"destructive","command":"bidbot archive 42"}],
 "snooze":true,
 "reminder":{"title":"Follow up on Acme","due":"2026-10-02T09:00:00-04:00"},
 "layout":"hero","accentColor":"#2E7D32","showSubtitle":true,"showBody":true,
 "showTimestamp":true,"maxBodyLines":3,
 "metadata":{"amount":"$4,200"}}
```

Response: `{"ok":true,"id":"bid-42"}`. Only `app` and `title` are required (a `template` can supply the title).

| Field | Meaning |
|---|---|
| `id` | Same id replaces the visible banner in place. Generated when omitted. |
| `template` | Name of a template of this app. Resolved before anything else (see AUTHORING.md). |
| `title`, `subtitle`, `body` | Text. `body` supports `[text](url)` Markdown links. |
| `image` | File path, `data:` URI or https URL (downloaded once, cached under history/images). Must be a PNG, JPEG, GIF, WebP, HEIC/AVIF, TIFF or BMP by its bytes and at most 10 MB; anything else is ignored. The spec itself is at most 256 KB. |
| `url` | Opened when the banner body is clicked; otherwise the app's `bundleId` is focused. Only `http`, `https` and `mailto` URLs are opened (this applies to button `url`s too). |
| `sound` | `default` (the app's default), a system sound name (`Glass`), a file path, or `none`. |
| `persistent`, `timeout` | Banners stay until dismissed. `timeout` > 0 auto-dismisses after N seconds; hover pauses it. |
| `priority` | `low`, `normal` or `high`. |
| `buttons` | Each has `label`, optional `style` (`default`, `destructive`, `cancel`) and exactly one of `url`, `command`, `callback`. |
| `snooze` | `true` adds the clock menu (5 min, 15 min, 1 h, Tomorrow 9:00). |
| `reminder` | Adds Add to Reminders. `title` (defaults to the notification title) and optional ISO 8601 `due`. |
| `layout` | `imageLeft` (default), `imageRight`, `hero`, `compact`. |
| `accentColor` | Hex colour, e.g. `#2E7D32`. |
| `showSubtitle`, `showBody`, `showTimestamp` | Toggle parts of the banner. |
| `maxBodyLines` | Body line limit. |
| `metadata` | Arbitrary JSON, stored in history, and the source of template `{placeholders}`. |

### Limits

A request body is at most 1 MB and must arrive within 10 s. `413` is returned for a title or subtitle over
1 KB, a body over 16 KB, `metadata` over 64 KB, more than 8 buttons (64 KB in all), an `image` or `icon`
over 256 KB, or when 200 apps are already registered (`429`). Requests with an `Origin` header or a `Host`
other than `127.0.0.1`, `localhost` or `[::1]` get `403`; a missing or wrong token gets `401` before the
body is read.

### Callbacks

A `callback` button POSTs `{"notificationId","app","action":"<label>","payload":...}` to
`callback.url` if given, else the app's registered `callbackURL`. Answer with any 2xx once the action has
happened: Herald then dismisses the banner. Any other status keeps the banner and shows "Action failed"
(408, 429 and 5xx are retried once, other 4xx are final). The answer must come within 5 s.

The URL must be on this Mac (`127.0.0.1`, `::1`, `localhost`) unless the user approved its host (an alert
the first time a button is pressed, or the toggle in Settings > Apps). Redirects are not followed.

### POST /v1/snooze and /v1/unsnooze

`{"app":"bidbot","id":"bid-42","minutes":15}` hides the banner and shows it again (same id) after
15 minutes (`0 < minutes <= 43200`, fractions allowed). The reply is `{"ok":true,"until":"2026-10-02T13:15:00.000Z"}`.
Snoozes are persisted and survive a relaunch of Herald; History marks the item as snoozed. `404` if the
notification is unknown, `400` if it was already dismissed or `minutes` is out of range.

`POST /v1/unsnooze {"app","id"}` cancels the snooze and shows the banner again immediately, without a sound.
Sending a notification with the same id also cancels a pending snooze.

### Templates

`GET /v1/templates?app=bidbot`:

```json
{"items":[{"name":"bid-won","app":"bidbot","layout":"hero","accentColor":"#2E7D32",
           "showSubtitle":true,"showBody":true,"showTimestamp":true,"maxBodyLines":3,
           "title":"Bid accepted: {amount}","body":"{client} accepted your bid.",
           "buttons":[{"label":"Open","url":"{url}"}],"snooze":true}]}
```

`PUT /v1/templates` takes one template object and writes
`~/Library/Application Support/Herald/templates/<app>/<name>.json`. Only `name` and `app` are required;
every other field is optional, so partial JSON is accepted. See [AUTHORING.md](AUTHORING.md).

### History records

Each record holds the full notification payload plus `deliveredAt`, `dismissedAt` (null while the banner
is still showing), the label of the button used, and `snoozedUntil`. History is capped at 1000 items per app.
