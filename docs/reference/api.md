# HTTP API reference

Every endpoint, with request, response and errors. Derived from the router (`Router.swift`), the snooze routes
and the listener. The narrative overview is [../API.md](../API.md).

## Connecting

Herald listens on `http://127.0.0.1:48617` (the port is also written to
`~/Library/Application Support/Herald/port` and can be changed in Settings). Loopback only.

```sh
D="$HOME/Library/Application Support/Herald"
BASE="http://127.0.0.1:$(cat "$D/port")"
AUTH="Authorization: Bearer $(cat "$D/token")"
```

| Rule | Detail |
|---|---|
| Auth | `Authorization: Bearer <token>` on every endpoint except `GET /v1/health`. The token is generated on first launch into `<support>/token` (mode 0600). A missing or wrong token is `401` **before the body is read**. |
| Bodies | JSON, `Content-Type: application/json`. Responses are JSON (`{"error":"..."}` on failure), except `image/png` for previews and snapshots. |
| `Content-Length` | Required for bodies; chunked bodies are `400 chunked bodies are not supported; send Content-Length`. |
| Size | Request body at most 1 MB (`413 payload too large`); headers at most 64 KB. The request must arrive within 10 s. |
| Browsers | A request with an `Origin` header is `403 browser requests are not allowed`; a `Host` other than `127.0.0.1`, `localhost` or `[::1]` is `403 unexpected Host header`. |
| Other support dir/port | `HERALD_SUPPORT_DIR`, `HERALD_PORT` run a second instance beside the installed one. |

## Errors

| Status | Meaning |
|---|---|
| `400` | Bad request: `{"error":"missing field: title"}`, `invalid field: ...`, `invalid template: cell img: cells[0]: ...`, `invalid manifest: ...`. Validation errors name the JSON path and cell id. |
| `401` | `{"error":"unauthorized"}` |
| `403` | Browser or non-loopback `Host`. |
| `404` | `not found` (unknown path), `manifest not found`, `template not found`, or the notification is unknown (snooze). |
| `405` | `method not allowed` on a known path. |
| `413` | Payload too large: a field over its limit (see Limits), or the body. |
| `429` | 200 apps, or 200 manifests, already registered. |
| `500` | Could not save, or an unexpected error. |
| `501` | The running backend does not support that feature (old Herald). |

## Endpoint index

| Method | Path | Purpose |
|---|---|---|
| GET | [`/v1/health`](#get-v1health) | Is Herald running. No auth. |
| POST | [`/v1/register`](#post-v1register) | Register or update an app. |
| POST | [`/v1/notify`](#post-v1notify) | Show a notification. |
| POST | [`/v1/speak`](#post-v1speak) | Say text aloud, no banner. |
| POST | [`/v1/dismiss`](#dismiss) | Dismiss one banner. |
| POST | [`/v1/dismissAll`](#dismiss) | Dismiss an app's banners, or one stack. |
| POST | [`/v1/snooze`](#snooze) | Snooze a banner. |
| POST | [`/v1/unsnooze`](#snooze) | Bring a snoozed banner back. |
| POST | `/v1/compose` | Open the Composer window. `{"ok":true}` |
| GET, DELETE | [`/v1/history`](#history) | Read or clear history. |
| GET | [`/v1/apps`](#get-v1apps) | Registered apps. |
| GET, PUT, DELETE | [`/v1/templates`](#templates) | List, save, delete templates. |
| GET, PUT, DELETE | [`/v1/manifest`, `/v1/manifests`](#manifests) | Issuer manifests. |
| GET | [`/v1/components`](#get-v1components) | Template schema for agents. |
| GET | [`/v1/shortcuts`](#get-v1shortcuts) | Installed Apple Shortcuts. |
| POST, GET | [`/v1/preview`](#post-v1preview) | Render a template to PNG. |
| GET, POST | [`/v1/designer/snapshot`](#designer-snapshot) | Render the Designer offscreen to PNG (test hook). |
| POST | [`/v1/rive/check`](#post-v1rivecheck) | Load a `rive` component without a window (test hook). |
| GET | [`/v1/stacks`](#stacks) | Live stacks. |
| POST | [`/v1/stacks/expand`](#stacks) | Open or close a stack. |
| GET, PUT | [`/v1/settings/stacking`](#stacks) | The global stacking level. |
| GET, PUT | [`/v1/settings/quiet-hours`](#quiet-hours) | Quiet hours. |

## GET /v1/health

No auth. `{"ok":true,"version":"1.2.0","pid":123}`. Use it to detect that Herald is running. Other methods: 405.

## POST /v1/register

```json
{"app":"bidbot","appName":"BidBot","icon":"/path/icon.png","bundleId":"com.example.bidbot",
 "callbackURL":"http://127.0.0.1:5123/herald","allowCommands":false,
 "defaults":{"sound":"Glass","persistent":true,"timeout":0,"corner":"topRight"}}
```

| Field | Meaning |
|---|---|
| `app` | Required. Up to 128 bytes. |
| `appName` | Display name. |
| `icon` | A file path or `data:image/png;base64,...`, at most 256 KB. |
| `bundleId` | Focused when a banner is clicked and the notification has no `url`. |
| `callbackURL` | Where `callback` buttons POST ([actions.md](actions.md#callbacks)). Non-loopback hosts need the user's approval. |
| `allowCommands` | A request only: the user must confirm it in Settings > Apps (or "Always allow") before `command` buttons run. |
| `defaults` | `sound`, `persistent`, `timeout`, `corner` (`topRight`, `topLeft`, `bottomRight`, `bottomLeft`). |

Reply `{"ok":true}`. Registering is optional: unknown ids are registered on their first notification with a
generic icon. A registered name and icon always win over the manifest's.

## POST /v1/notify

Show a notification.

```json
{"app":"bidbot","id":"bid-42","template":"bid-won",
 "title":"Bid accepted","subtitle":"Acme RFP","body":"Accepted. [Open](https://example.com/p/42)",
 "image":"/path/preview.png","url":"https://example.com/p/42","group":"acme",
 "sound":"default","persistent":true,"timeout":0,"priority":"high",
 "buttons":[{"label":"Open","url":"https://example.com/p/42"}],
 "actionIds":["markRead"],"snooze":true,
 "reminder":{"title":"Follow up on Acme","due":"2026-10-02T09:00:00-04:00"},
 "metadata":{"amount":"$4,200"},
 "speak":true,"presentation":"both"}
```

Reply `{"ok":true,"id":"bid-42"}` (the id is generated when omitted). Only `app` is required, plus `title`
unless `template` supplies one.

| Field | Type | Meaning |
|---|---|---|
| `app` | string | Required. The issuer id. |
| `id` | string (256 B) | The same id replaces the visible banner in place and never raises a stack's count. |
| `title` | string (1 KB) | Required unless `template` provides it. |
| `subtitle` | string (1 KB) | |
| `body` | string (16 KB) | `[text](url)` Markdown links work. |
| `image` | string (256 KB) | File path, `data:` URI or https URL (downloaded once, cached). Validated by bytes: PNG, JPEG, GIF, WebP, HEIC/AVIF, TIFF, BMP, at most 10 MB; anything else is ignored. |
| `url` | string | Opened when the banner is clicked. Only http, https, mailto are opened (also for button URLs). |
| `sound` | string | `default` (the app's), a system sound name (`Glass`), a file path, or `none`. |
| `persistent`, `timeout` | bool, number | Stay until dismissed; `timeout` > 0 auto-dismisses after N seconds, hover pauses it. |
| `priority` | string | `low`, `normal`, `high`, `urgent` (urgent breaks quiet hours only for apps that opted in). |
| `buttons` | array (8, 64 KB) | `{label, style?, url|command|callback}`. `actions` is accepted as an alias (`buttons` wins when both are sent). An explicit `[]` means no buttons. |
| `actionIds` | array of string | Ids of actions the manifest declares, instead of repeating the buttons. |
| `snooze` | bool | Adds the clock menu (5 min, 15 min, 1 h, Tomorrow 9:00). |
| `reminder` | object | Adds Add to Reminders: `{title?, due?}` (ISO 8601). |
| `group` | string | Stacking key for `bySender` ([stacking.md](stacking.md)). |
| `template` | string | A template of this app, resolved first. The manifest's `defaultTemplate` applies when omitted. |
| `layout`, `accentColor`, `showSubtitle`, `showBody`, `showTimestamp`, `maxBodyLines` | v1 | The legacy look, used when no grid template applies. |
| `metadata` | any JSON (64 KB) | Stored in History; the source of template tokens. |
| `speak`, `audio`, `presentation` | | [voice.md](voice.md). |
| any other top-level key | | Moved into `metadata`: a manifest field such as `subject` or `count` can be sent at the top level (the top-level key wins over the same name in `metadata`). |

Limits: a title or subtitle over 1 KB, a body over 16 KB, `metadata` over 64 KB, more than 8 buttons (64 KB in all),
an `image` or `icon` over 256 KB, or any other single field over 2 KB gets `413`.

## POST /v1/speak

[voice.md](voice.md#post-v1speak). `{"app","text","voice?","speed?","lang?","id?"}` returns `{"ok":true,"id":"..."}`.

## Dismiss

- `POST /v1/dismiss` `{"app","id"}`: both required (400 otherwise). `{"ok":true}`.
- `POST /v1/dismissAll` `{"app"}`: every banner of the app (all apps if the body is empty or `app` omitted);
  `{"app","group"}`: only that stack (`app` is then required). `{"ok":true}`.

A dismissed banner stays in History.

## Snooze

- `POST /v1/snooze` `{"app","id","minutes"}`: hides the banner and shows it again (same id) after `minutes`
  (`0 < minutes <= 43200`, fractions allowed). Reply `{"ok":true,"until":"2026-10-02T13:15:00.000Z"}`. `404` if the
  notification is unknown, `400` if it was already dismissed or `minutes` is out of range. Snoozes persist across
  relaunches; History marks the item as snoozed.
- `POST /v1/unsnooze` `{"app","id"}`: cancels the snooze and shows the banner again immediately, without a
  sound. Sending a notification with the same id also cancels a pending snooze.

## History

- `GET /v1/history?app=&limit=50` returns `{"items":[...]}`, newest first. Each item is the full record:
  `id`, `app`, `notification` (the resolved payload), `deliveredAt`, `dismissedAt` (null while showing),
  `actionUsed` (the button label, `open` for a banner click, `timeout`), `snoozedUntil`, `imagePath`, `fields`
  (the resolved tokens at delivery), `speech`. `limit` must be a non-negative integer. History is capped at 1000
  items per app.
- `DELETE /v1/history?app=` clears one app's history (all apps if `app` is omitted). `{"ok":true}`.

## GET /v1/apps

`{"apps":[ {app, appName, icon, bundleId, callbackURL, allowCommands, defaults}, ... ]}`: the registrations.

## Templates

- `GET /v1/templates?app=` returns `{"items":[...]}`: the saved templates of the app (all apps if omitted).
  Scratch templates (names starting with `_`) are not listed. The four `builtin.*` templates are not listed here;
  MCP `get_template` returns them.
- `PUT /v1/templates` takes one template object (only `name` and `app` are required) and writes
  `<support>/templates/<app>/<name>.json`. It is **validated first**; errors reject with `400 invalid template:
  cell <id>: <path>: <message>; ...`. `{"ok":true}`. See [grid-and-layout.md](grid-and-layout.md).
- `DELETE /v1/templates?app=&name=` (both required): `{"ok":true}`, `404 template not found`.

## Manifests

- `PUT /v1/manifest`: create or replace; validated (`400 invalid manifest: ...`); copies Rive assets. `{"ok":true}`.
- `GET /v1/manifest?app=`: one manifest, `404 manifest not found`.
- `GET /v1/manifests`: `{"items":[...]}`.
- `DELETE /v1/manifest?app=`: delete it and the copies of its assets.

Details: [manifests.md](manifests.md).

## GET /v1/components

The component schema as JSON (same document as MCP `component_schema`): every component type with each
property, allowed values and defaults, bindings, collapsing, action kinds and rules, examples. Static data.

## GET /v1/shortcuts

`{"items":["Create follow-up",...]}`: the output of `shortcuts list`. A slow or missing `shortcuts` tool is a
gateway-style error.

## POST /v1/preview

Renders a template offscreen with the real banner renderer and returns `image/png`.

```json
{"template":"email-accumulated","app":"webwatcher.email","data":"sample",
 "appearance":"dark","scale":2,"stackCount":1,"stackExpanded":false,"confirmation":null}
```

| Field | Type | Default | Meaning |
|---|---|---|---|
| `template` | string or object | the app's default template, else `builtin.imageLeft` | A saved template's name (or `builtin.*`), or a full template object (validated; errors name the cell). |
| `app` | string | the inline template's `app` | Required unless the template object carries one. |
| `data` | object or `"sample"` | `"sample"` | The notification to draw: its top-level keys and `metadata` are the fields, by the same rules as `/v1/notify`. `"sample"` uses the manifest's samples. Omit a key to see the collapse. |
| `appearance` | `light` or `dark` | `light` | |
| `scale` | number 1 to 3 | 2 | Pixel scale. |
| `confirmation` | kind or object | none | Draws an inline question: a kind (`callbackHost`, `command`, `script`, `shortcut`, `templateCommand`, `remindersError`, `remindersDenied`) or `{"kind","name","host","url","command","template","others","replaces","message"}`. |
| `stackCount` | integer 1 to 99 | 1 | Draws the banner as the top card of a stack. |
| `stackExpanded` | boolean | false | With `stackCount` above 1, draws the open list. |

`GET /v1/preview?app=&template=&appearance=&scale=&stackCount=&stackExpanded=` is the quick form with sample
data. Offscreen renders cannot draw `rive` (a labelled placeholder) or menus (static labels), and show no symbol
effects. `400` with the validation errors for a bad template or data; `500` with the message if rendering fails (for example an unknown template name, **TBD - verify** the exact status).

## Designer snapshot

`GET` or `POST /v1/designer/snapshot?app=&template=&select=&width=&height=` (a POST may carry the same keys as a
JSON object) draws the Designer window's content offscreen, with no window, as `image/png`. `app` is the issuer,
`template` the name of a saved template to open, `select` a cell id to select; `width` 600 to 4000 (default 1100)
and `height` 400 to 3000 (default 820), else `400`. A test hook: it verifies layout (the live preview pane is at
least half of the design area) without opening or focusing anything.

## POST /v1/rive/check

Loads a `rive` component in a window-less host view and reports what it found. Nothing is shown or stored. Full
request, reply and example in [rive.md](rive.md#testing-without-a-window).

## Stacks

- `GET /v1/stacks?app=` returns `{"stacks":[{level, app, group, count, expanded, members:[{app,id,title,group,deliveredAt}], frame}]}`.
- `POST /v1/stacks/expand` `{"app","group?","expanded?":true}` opens or closes a stack in place (`group` defaults to `app`).
- `GET /v1/settings/stacking` returns `{"level","levels":["byApp","byIssuer","bySender","never"]}`;
  `PUT /v1/settings/stacking` `{"level":"bySender"}` sets it (400 for an unknown level).

See [stacking.md](stacking.md).

## Quiet hours

`GET /v1/settings/quiet-hours` and `PUT /v1/settings/quiet-hours`: [quiet-hours.md](quiet-hours.md#api).

## Callbacks (Herald calls you)

A `callback` button POSTs `{"notificationId","app","action":"<label>","payload":...}` to your callback URL. Answer
2xx once the action has happened and Herald dismisses the banner; otherwise it shows "Action failed". 5 s budget,
one retry for transport errors, 408, 429 and 5xx. Redirects are never followed; non-loopback hosts need approval.
See [actions.md](actions.md#callbacks).

## Limits summary

| Limit | Value |
|---|---|
| Request body | 1 MB; headers 64 KB; arrives within 10 s |
| `app` / `id` | 128 / 256 bytes |
| `title`, `subtitle` | 1 KB each |
| `body` | 16 KB |
| `metadata` | 64 KB |
| Buttons | 8, 64 KB encoded |
| `image`, `icon` spec | 256 KB; cached image 10 MB |
| Other text fields | 2 KB |
| Template file | 2 MB; 100 cells; grid 12 x 12 |
| Apps, manifests | 200 each |
| History | 1000 per app |
| Rive file | 10 MB; 32 per app |

## Client helpers

[../../clients/README.md](../../clients/README.md): Python (`herald.py`) and Node (`herald.js`), stdlib only; the
Swift package `HeraldClient`; the CLI ([cli.md](cli.md)); the MCP server ([mcp-tools.md](mcp-tools.md)).
