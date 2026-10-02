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
| GET, PUT | [`/v1/settings`](#settings) | Every general and voice setting, validated. |
| GET | [`/v1/replies`, `/v1/replies/wait`](#replies) | Answers typed into banners' Reply; long-poll for one. |
| GET, PUT | [`/v1/apps/settings`](#per-app-settings) | Per-app sound, corner, display, mute, stacking, voice; approvals (revoke only). |
| GET, POST, DELETE | [`/v1/assets`](#assets) | An app's Rive files and images. |
| POST | [`/v1/templates/duplicate`, `/rename`](#template-duplicate-rename-default) | Duplicate or rename a template. |
| PUT | [`/v1/templates/default`](#template-duplicate-rename-default) | Set or clear the app's default template. |
| GET, POST | [`/v1/templates/export`, `/import`](#template-bundles) | `.heraldtemplate` bundles. |
| GET | [`/v1/history/search`, `/export`](#history-search-re-show-delete-export) | Search or export History. |
| POST, DELETE | [`/v1/history/reshow`, `/item`](#history-search-re-show-delete-export) | Re-show or delete one notification. |
| GET | [`/v1/symbols`](#symbols) | SF Symbol names and categories. |
| GET, POST | [`/v1/voice`, `/v1/voice/install`](#voice-and-mcp-install) | Kokoro state and install. |
| GET, POST | [`/v1/mcp`, `/v1/mcp/install`](#voice-and-mcp-install) | Install `herald-mcp` in a client. |
| GET, DELETE | [`/v1/actions/approvals`](#approvals) | Template command approvals: list, revoke. |

## GET /v1/health

No auth. `{"ok":true,"version":"1.2.0","pid":123}`. Use it to detect that Herald is running. Other methods: 405.

## POST /v1/register

```json
{"app":"example.bidbot","appName":"BidBot","icon":"/path/icon.png","bundleId":"com.example.bidbot",
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
{"app":"example.bidbot","id":"bid-42","template":"bid-won",
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

## DELETE /v1/apps/{id}

Removes the app for good: its record, **all** of its History, its templates, its manifest (and the Rive copies) and the icon files Herald
made for it. `200 {"ok":true,"deleted":"<id>"}`; `404` for an unknown app; `409` for `herald`, Herald's own app. The id is percent-decoded.
MCP: `delete_app`. Startup also removes History of apps that are not registered any more, and once the known test leftovers
(`cloud.herald-test-*`, a bare `bidbot` without a manifest); the docs examples use `example.bidbot`, never registered by default.

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
| `data` | object, `"sample"` or `"last"` | `"sample"` | The notification to draw: its top-level keys and `metadata` are the fields, by the same rules as `/v1/notify`. `"sample"` uses the manifest's samples; `"last"` the app's most recent notification from History (`400` when it has none). Omit a key to see the collapse. |
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

## Settings

`GET /v1/settings` returns `{"settings":{key:value},"schema":[{key,group,type,min?,max?,values?,description}],"options":{...}}`.
`options` lists what the choices are: `sounds`, `displays` (`id`, `name`), `corners`, `stackingLevels`,
`voiceEngines`, `voices`, `historyCapChoices`. `PUT /v1/settings` takes an object of keys and new values and
answers like the GET plus `applied`. **All or nothing**: an unknown key, a wrong type or a value out of range is `400`
and nothing is changed.

| Key | Type | Meaning |
|---|---|---|
| `port` | integer 1024 to 65535 | Local API port. The server restarts on the new port just after the reply. |
| `launchAtLogin` | boolean | Login item. |
| `muteAllSounds` | boolean | Global sound mute. |
| `stacking` | `byApp`, `byIssuer`, `bySender`, `never` | Default stacking ([stacking.md](stacking.md)). |
| `historyCapPerApp` | integer 1 to 100000 | History kept per app; older items are deleted. |
| `tooltipLevel` | `nameOnly`, `nameAndDescription` | Settings > Tooltips. |
| `voiceEngine` | `kokoro`, `system`, `off` | Speech engine ([voice.md](voice.md)). |
| `voiceDefault`, `voiceLang` | string | Default voice and language. |
| `voiceSpeed` | number 0.5 to 2.0 | Default speed. |
| `voiceSystem` | string or `null` | macOS voice id for the system engine. |

Quiet hours keep their own route ([quiet-hours.md](quiet-hours.md#api)); `GET`/`PUT /v1/settings/stacking` still works.

## Per-app settings

`GET /v1/apps/settings[?app=]` returns `{"apps":[{app, appName, bundleId?, callbackURL?, settings, voice, approvals}],
"schema":[...]}`. `PUT /v1/apps/settings` takes `{"app":"id", key: value, ...}` (404 for an unknown app; the same
all-or-nothing validation).

| Key | Type | Meaning |
|---|---|---|
| `sound`, `persistent`, `timeout` | string, boolean, 0 to 86400 | The app's defaults ([actions](#post-v1register) `defaults`). |
| `corner` | corner or `null` | The user's corner; `null` follows what the app registered. |
| `display` | `"main"` or a display id | From `options.displays`. |
| `muteBanners` | boolean | No banners; notifications go to History, unread. |
| `stacking` | level or `null` | Override of the global stacking. |
| `speak`, `urgentBreaksQuiet` | boolean | Voice, per app. |
| `voice` | string or `null` | The app's voice. |
| `revokeCommands`, `revokeCallbackHost` | `true` | Withdraw the approval to run command buttons, or to call the registered non-loopback host. |

**Approvals can be read (`approvals`) and withdrawn, never granted.** Sending `false` for a revoke key, or any key that
would grant, is `403` or `400`: only the user can allow command buttons or a remote callback host, in Settings > Apps.

## Assets

- `GET /v1/assets?app=` returns the Rive files (`kind:"rive"`: `id`, `file`, `path`, `bytes`, `declared`, `usedBy`, and the
  `component` to use) and images (`kind:"image"`: `file`, `path`, `bytes`) stored for the app.
- `POST /v1/assets` `{"app","name?","kind?","base64"|"path"}`: exactly one of `base64` (the body limit is 1 MB, so up to about
  700 KB) or `path` (a file on this Mac). `name` is required with `base64`. `kind` is inferred from the name. Rive: at most
  10 MB, 32 per app, stored as `<id>.riv`. Images: PNG, JPEG, GIF, WebP, HEIC, TIFF, BMP, checked by their bytes, at most
  10 MB, 100 per app, stored in `<assets>/<app>/images/`. The same name replaces. The reply has the stored `path`.
- `DELETE /v1/assets?app=&file=` removes one; the reply lists templates that still play a deleted animation.

## Template duplicate, rename, default

- `POST /v1/templates/duplicate` `{"app","name","newName?","toApp?"}`: copies a saved template or a `builtin.*` layout;
  without `newName` the copy is `<name> copy` (numbered when taken). `409` when `newName` exists.
- `POST /v1/templates/rename` `{"app","name","newName"}`: the manifest's `defaultTemplate` follows. Command, script and
  Shortcut approvals belong to the old name (the user is asked again). Built-ins cannot be renamed.
- `PUT /v1/templates/default` `{"app","name?"}`: sets the manifest's `defaultTemplate` (a saved or `builtin.*` name), or clears
  it when `name` is omitted. `400` when the app has no manifest.

## Template bundles

- `GET /v1/templates/export?app=&name=[&path=]`: packs the template and its Rive files ([rive.md](rive.md#packaging-with-a-template-heraldtemplate)).
  With `path` (ending in `.heraldtemplate`) Herald writes the file; otherwise the reply carries `base64`.
- `POST /v1/templates/import` `{"base64"|"path","app?","onConflict?"}`: `onConflict` is `keepBoth` (default), `replace` or
  `fail` (`409`). `app` retargets the bundle to another issuer. The reply lists `installedAssets`, `missingAssets` and warnings.

## History search, re-show, delete, export

- `GET /v1/history/search?q=&app=&limit=`: every word of `q` must appear (any case, accents folded) in the title, subtitle,
  body, app id or app name; newest first; `{"query","count","items"}`.
- `POST /v1/history/reshow` `{"app","id"}`: shows the stored notification again as a banner (sound, fresh delivery time). `{"ok","id"}`.
- `DELETE /v1/history/item?app=&id=`: deletes one notification and closes its banner (`404` when unknown). `DELETE /v1/history`
  still clears an app (or all).
- `GET /v1/history/export?app=[&path=]`: `{"count","items"}` (the full records); with `path` (`.json`) Herald writes the file.

## Symbols

`GET /v1/symbols?q=&category=&limit=&offset=`: `{"total","offset","limit","symbols":[{name,categories}],"categories":[{key,title,icon,count}]}`.
`q` matches every word in the name, Apple's search terms or a synonym; `category` is a key from `categories` (`400`
otherwise); `limit` defaults to 100 (at most 1000). Use the names for a component's `symbol` ([symbols.md](symbols.md)).

## Voice and MCP install

- `GET /v1/voice`: `{"engine","kokoro":{installed,missing,folder,busy,phase,existingInstallationAvailable,log},"voices","lastError"}`.
- `POST /v1/voice/install` `{"action":"install"|"cancel"|"useExisting"}`: starts the 340 MB download, stops it, or links a complete
  `~/.claude/tts`. Poll `GET /v1/voice`.
- `GET /v1/mcp`: the server path and the status of Claude Code, Codex and Claude Desktop (`Installed`, `Not installed`,
  `Client not found`).
- `POST /v1/mcp/install` `{"client":"claudeCode"|"codex"|"claudeDesktop"|"cli"|"generic","reinstall?","name?","icon?"}`: the Settings > MCP
  button. It edits that client's own configuration (a `.bak` is kept), writes `--agent <slug>` into the server entry, and registers
  the agent as an issuer: app `agent.claude-code`, `agent.codex`, `agent.claude-desktop` or `agent.<slug of name>` (`generic` needs
  `name`), a manifest, a default template `agent` and the product's icon (`icon` picks a file instead; `400` if it is missing).
  Re-running keeps what the user changed ([../MCP.md](../MCP.md#agents-as-issuers)). `cli` installs the `herald` tool into `/usr/local/bin`.

## Replies

A `reply` action (the agent default's Reply, or any issuer's) shows a text field inside the banner; the text lands on the history record (`reply`, `repliedAt`) and in a per-app queue (at most 200 per app).

- `GET /v1/replies?app=&since=&consume=`: `{"replies":[{notificationId, app, text, repliedAt, title}], "count"}`, oldest first. `since` is ISO 8601 or epoch seconds. `consume=true` removes the returned replies from the queue.
- `GET /v1/replies/wait?id=&app=&timeout=&consume=`: long-polls up to `timeout` seconds (1 to 300, default 60). `{"replied":true,"reply":{...}}` as soon as it exists (also from History), else `{"replied":false,"timedOut":true}`. `consume` defaults to true. `400` without `id`.

`/v1/preview` also takes `"replying": true` (and `"replySample"`) to draw the reply field instead of the buttons. `PUT /v1/apps/settings` takes `opens` (bundle id or `.app` path): what Open brings to the front. `POST /v1/mcp/install` takes `opens` and `detectedHost`.

## Approvals

`GET /v1/actions/approvals`: the commands, scripts and Shortcuts the user approved for templates (`app`, `template`, `commands`,
`approvedAt`). `DELETE /v1/actions/approvals?app=&template=` withdraws one (`404` when there is none). There is no route
that grants an approval.

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

## Cloud relay

`/v1/relay/*` on the loopback API (same bearer token) pairs this Mac with the cloud relay and manages agent keys; see
[../CLOUD.md](../CLOUD.md). The relay itself is a separate, remote API (`relay/`).

| Route | Does |
|---|---|
| `GET /v1/relay/status` | `{paired, state, online, relayURL, mcpURL, deviceId, lastSeenAt, keys, log, devices}`; `devices` lists the Macs on the relay (`id`, `name`, `online`, `lastSeenAt`, `thisDevice`, `removable`, `removableReason`), so an agent can tell the user which Mac a banner will appear on; `log` is the last 20 relay items with `displayed`, `spoken`, `replied`, `suppressed`. |
| `POST /v1/relay/pair` | Pairs this Mac with the relay: asks for a one-time code, redeems it, stores the device token in the secret store (data-protection keychain, else a 0600 file). Replies `{paired, code, deviceId}`. |
| `POST /v1/relay/unpair` | Wipes the mailbox on the relay (keys, queue, audio) and forgets the token. |
| `GET /v1/relay/keys` | The agent keys: `id`, `name`, `client`, `scope` (always `notify`), `createdAt`, `lastUsedAt`, `revokedAt`. Never a secret. |
| `POST /v1/relay/keys` | `{name, client?}` (`client`: `claude`, `codex`, `other`) mints a notify-only key. The reply has `key` (shown once), `mcpURL` and `connectorConfig`, the block to paste into the agent. 409 when the name is taken. |
| `DELETE /v1/relay/keys/{id}` | Revokes the key at once. |
| `GET /v1/relay/connectors` | Connectors that signed in with OAuth: `connectors` (the `oauth` keys: `id`, `name`, `displayName`, `kind`, `createdAt`, `lastUsedAt`) and `pending` (requests waiting for approval: `id`, `clientName`, `redirectHost`, `expiresAt`, and for the device flow the `userCode` the agent printed, like `BDFG-HJKM`). The 6-digit approval code is never returned; approving happens on the Mac. Revoke with `DELETE /v1/relay/keys/{id}`. |
| `GET /v1/relay/usage` | Today's relay traffic against this device's caps: `requests`, `notifications`, `queued`, `storageBytes`, `requestsPercent`, `budgetExhausted`. |
| `GET /v1/relay/setup` | The setup state machine: `state` (`token-needed`, `ready`, `deploying`, `connecting`, `online`, `offline`, `error`), `hasToken`, `paired`, `online`, `relayURL`, `mcpURL`, `workersDevURL`, `customURL`, `customDomainRecommended`, `bundledVersion`, `deployedVersion`, `updateAvailable`, `message`, `steps`, `usage`. Also returned as `setup` by `GET /v1/relay/status`. |
| `GET /v1/relay/token-url` | The pre-filled Cloudflare token page `url`, the sign-up URL, the nine `permissions` (three for the deploy, six Zone ones for the custom domain) with the reason for each, and `steps` to tell the user. |
| `POST /v1/relay/token` | `{token}` stores the Cloudflare API token in the secret store (see CLOUD.md). Never returned by any route. |
| `POST /v1/relay/deploy` | Deploys or upgrades the Worker in the user's Cloudflare account, waits for `/health`, pairs this Mac. Replies `{deployed, upgraded, relayURL, paired, online, steps, workersDevURL, customURL, warnings}` (`relayURL` is the custom address when one is set; `warnings` carries Bot Fight Mode and reconnect notes); a failure is `4xx/5xx` with Cloudflare's message. |
| `GET /v1/relay/settings`, `PUT /v1/relay/settings` | Every Advanced field (`relayURL`, `accountId`, `workerName`, `subdomain`, `bucket`, `audioRetentionDays`, `queueTTLHours`, `notificationsPerDay`, `maxQueue`, `bodyLimitBytes`, `ratePerKey`, `maxDevices`, `deviceName`, `pingSeconds`, `customDomain` `{zone, hostname, attached}` (`null` removes it; setting it redeploys and applies it, see docs/CLOUD.md "Custom domain"), write-only `pairingSecret`). PUT validates (400 names the field) and redeploys when a Worker value or the custom domain changed (`redeployed`, `steps`). |
| `GET /v1/relay/zones` | `{zones: [{id, name, status, suggestedHostname}]}`: the Cloudflare zones the stored token can see. 403 with "Token is missing Zone permissions ..." when it lacks Zone: Read. |
| `POST /v1/relay/delete` | `{confirm: true}` deletes the Worker, every mailbox and key, and the bucket when empty, from Cloudflare. |
| `POST /v1/relay/test` | `/health`, then a notification through the relay with a temporary key and its receipt (the notification is a `herald` one titled "Relay test"; the key, the History item and the log line are deleted afterwards, so it leaves no trace): `{healthy, paired, online, roundTrip, receipt, detail}`. |
| `GET /v1/relay/instructions?client=chatgpt\|claude\|codex\|device` | `{client, text}`: the exact instructions to give that agent. |

Keys carry `kind` (`static`, or `oauth` for a connector approved through the relay's OAuth flow, with `displayName`).

Errors: 409 when not paired, 429 when the relay reports a limit, 502 when the relay cannot be reached.

The relay's own OAuth 2.1 endpoints (discovery, `/register`, `/authorize`, `/device_authorization`, `/activate`, `/token`, `/revoke`) are
documented in [../CLOUD.md](../CLOUD.md#connect-chatgpt-oauth); agents with no browser use the device flow
([../CLOUD.md](../CLOUD.md#no-browser-use-the-device-flow)). A pending request has `flow: "device"` and a `userCode` (`BDFG-HJKM`) in
`GET /v1/relay/connectors`; the notifications accept presentation fields ([../CLOUD.md](../CLOUD.md#presentation-fields)); a connector's access token works wherever an `hrk_` key does on `/mcp`, `/v1/notify`,
`/v1/status`, `/v1/receipts/*` and `/v1/replies/*`, and nowhere else.

**Cloudflare API calls Herald makes** (only on Deploy / Delete / settings changes; token in `Authorization: Bearer`, host `api.cloudflare.com/client/v4`):

| Call | Purpose |
|---|---|
| `GET /user/tokens/verify` | the token is active |
| `GET /accounts` | the account id (unless set in Advanced) |
| `GET /accounts/{id}/workers/subdomain`, `PUT` when none | the workers.dev subdomain |
| `POST /accounts/{id}/r2/buckets` (409 = exists) | the voice-reply bucket |
| `PUT /accounts/{id}/r2/buckets/{bucket}/lifecycle` | delete objects after the retention days |
| `GET /accounts/{id}/workers/scripts/{name}/settings` | does the Worker exist (first deploy or upgrade) |
| `PUT /accounts/{id}/workers/scripts/{name}` (multipart: `metadata` + `worker.js`) | upload the relay: main module, compatibility date, Durable Object bindings + migration (first deploy only), R2 binding, vars, secrets (`RELAY_SECRET` first deploy only, never rotated by an upgrade; `PAIRING_SECRET`), `keep_bindings: ["secret_text"]` on upgrades |
| `POST /accounts/{id}/workers/scripts/{name}/subdomain` | switch on the workers.dev address |
| `DELETE /accounts/{id}/workers/scripts/{name}?force=true`, `DELETE /accounts/{id}/r2/buckets/{bucket}` | Delete relay from Cloudflare |

then `GET https://<name>.<subdomain>.workers.dev/health` (unauthenticated; `{service, ok, bundle}`).

Two implementations of the relay protocol can exist; `conformance/` is the black-box suite (`RELAY_URL=... npm test -w conformance`).

A notification from the cloud arrives as an ordinary notification of the app `cloud.<key name>` with `id` = the relay's delivery id, so it
appears in `/v1/history` and `/v1/apps` like any other. A `reply` action may carry `voice: true` (the Record button): the banner shows the
inline record strip instead of a text field.
