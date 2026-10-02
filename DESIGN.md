# Herald — a Growl-style notification service for macOS (design v1, 2026-10-01)

Working name "Herald" (rename later). A separate menu-bar app that other apps send notifications to. It draws its own banners (always on top, persistent until dismissed, per-app sound), keeps a per-app history, and offers rich banner content: image preview, buttons, snooze, Add to Reminders, links. Clients: a local HTTP+JSON API, a `herald` CLI, a Swift package, and single-file Python/Node helpers, so a Swift app (WebWatcher) and a Codex-built bot can both use it.

Repo: ~/github/herald. Tooling: xcodegen 2.44 (`project.yml` → Herald.xcodeproj), Swift 5.9+, macOS 13+. Signing/notarization per ~/github/NOTARIZATION.md (Developer ID, team 7S422NVLUK, Manual signing, hardened runtime, CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO, OTHER_CODE_SIGN_FLAGS=--timestamp). Not sandboxed (needs to listen on loopback and run optional callback commands).

## 1. Architecture

```
┌────────────┐  HTTP 127.0.0.1:48617 (+Bearer token)  ┌──────────────────────────┐
│ WebWatcher │ ─────────────────────────────────────▶ │ Herald.app (menu bar)    │
│ bidbot     │                                        │  HTTPServer → Router     │
│ herald CLI │ ◀────── callback webhook (optional) ── │  BannerCenter (NSPanels) │
└────────────┘                                        │  HistoryStore (JSON)     │
                                                      │  AppRegistry + Settings  │
                                                      │  Sounds · Reminders      │
                                                      └──────────────────────────┘
```
- **Loopback HTTP server** (Network.framework `NWListener` on 127.0.0.1, fixed port 48617, overridable in Settings; the port is also written to `~/Library/Application Support/Herald/port`). Every request needs `Authorization: Bearer <token>`; the token is generated on first launch into `~/Library/Application Support/Herald/token` (mode 0600). Clients read both files. Minimal HTTP/1.1 parsing (Content-Length bodies, JSON only). Health endpoint is the only unauthenticated one. Hardening: the token and the `Host`/`Origin` headers are checked on the request head before the body is read; request bodies are capped at 1 MB, a request must complete within 10 s, at most 32 connections are open; field sizes are capped (title/subtitle 1 KB, body 16 KB, metadata 64 KB, 8 buttons, image/icon specs 256 KB, 200 apps).
- **Banners** are borderless `NSPanel`s (`.nonactivatingPanel`, `level = .statusBar`, `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]`, `hidesOnDeactivate = false`), SwiftUI content via `NSHostingView`, stacked from the chosen screen corner (default top-right) with 8 pt gaps, slide/fade in, re-layout when one closes. Persistent by default (no timeout); optional per-app or per-notification `timeout` seconds. Hover pauses any timeout. `id` replaces an existing banner in place (accumulation). Undismissed banners are restored on relaunch (history entries carry `dismissedAt == nil`).
- **History**: `~/Library/Application Support/Herald/history/<app>.json`, newest first, capped at 1000 per app; every delivered notification is recorded with its full payload, delivery time, dismissal time, and which button (if any) was used. History window: sidebar of apps, list with search, click opens the notification's url, context menu Dismiss/Delete, "Clear app history".
- **Apps**: registered implicitly on first `notify` (or explicitly via `/v1/register`): id, display name, icon (path or base64), default sound, default persistence/timeout, corner, callback URL. Per-app settings editable in Settings (Apps tab). Unknown app ids are accepted and get a generic icon.
- **Sounds**: per notification `sound`: `"default"` (app's default), a system sound name (files in /System/Library/Sounds, e.g. "Glass"), a file path, or `"none"`. Played with `NSSound`. Global mute switch in the menu.
- **Actions**: clicking the banner body opens `url` if present (else focuses the sending app by bundle id if given, else nothing). Buttons: each has `label`, optional `style` (`default|destructive|cancel`), and exactly one of `url` (open), `command` (run via `/bin/zsh -lc`, only if the app was registered with `allowCommands: true` which the user confirms once in Settings), or `callback` (`{url, payload}` → POST JSON to the app's callback URL with `{notificationId, app, action: label, payload}`; the app answers 2xx). Snooze: a ⏰ menu with 5 min / 15 min / 1 h / Tomorrow 9:00 — hides the banner and re-shows it (same id) at that time, surviving relaunch (persisted `snoozedUntil`). Add to Reminders: creates an EventKit reminder titled from the notification (or `reminder.title`) with the banner url in notes and optional `reminder.due` (ISO 8601); asks for Reminders permission the first time. Links: `body` supports `[text](url)` Markdown links via `AttributedString`. Only `http`, `https` and `mailto` URLs are opened from a banner, a button, a body link or History; callback URLs must be loopback unless the user approved the host, and redirects are not followed.
- **Launch at login**: `SMAppService.mainApp`, toggle in Settings; default on after first launch confirmation.
- **Menu bar**: icon with unread count; menu: History…, Mute, Dismiss All, Settings…, Quit.

## 2. API (all JSON; `Content-Type: application/json`)

- `GET /v1/health` → `{"ok":true,"version":"1.0.0","pid":123}` (no auth)
- `POST /v1/register` → `{"app":"bidbot","appName":"BidBot","icon":"<path|data:image/png;base64,…>","bundleId":"com.x.bidbot","callbackURL":"http://127.0.0.1:5123/herald","allowCommands":false,"defaults":{"sound":"Glass","persistent":true,"timeout":0,"corner":"topRight"}}` → `{"ok":true}`
- `POST /v1/notify` →
```json
{"app":"bidbot","id":"bid-42","title":"Bid accepted","subtitle":"Acme RFP","body":"Your bid of $4,200 was accepted. [Open proposal](https://…)",
 "image":"/path/to/preview.png","url":"https://…","sound":"default","persistent":true,"timeout":0,"priority":"high",
 "buttons":[{"label":"Open","url":"https://…"},{"label":"Mark done","callback":{"payload":{"bid":42}}},{"label":"Archive","style":"destructive","command":"bidbot archive 42"}],
 "snooze":true,"reminder":{"title":"Follow up on Acme","due":"2026-10-02T09:00:00-04:00"},"metadata":{"any":"json"}}
```
→ `{"ok":true,"id":"bid-42"}`. Only `app` and `title` are required. `image` accepts a file path, `data:` URI or https URL (downloaded once, cached under history/images).
- `POST /v1/dismiss` `{"app":"bidbot","id":"bid-42"}` ; `POST /v1/dismissAll` `{"app":"bidbot"}`
- `GET /v1/history?app=bidbot&limit=50` → `{"items":[…full records…]}` ; `DELETE /v1/history?app=bidbot`
- `GET /v1/apps` → registered apps and their settings.
- Errors: `401 {"error":"unauthorized"}`, `400 {"error":"…"}`.

## 3. Clients
- **CLI** `herald` (Swift executable target in the same package, `make install` copies to /usr/local/bin): `herald notify --app bidbot --title "Bid accepted" --body "…" --image preview.png --url https://… --button "Open=https://…" --button "Archive=cmd:bidbot archive 42" --sound Glass --timeout 0 --snooze --reminder "Follow up|2026-10-02T09:00"`, `herald register …`, `herald history --app bidbot`, `herald dismiss …`, `herald health`. Reads token/port from Application Support; exits non-zero with a clear message when Herald isn't running.
- **Swift package** `HeraldClient` (library target): `HeraldClient.shared.isAvailable`, `notify(_ n: HeraldNotification) async throws -> String`, `register(...)`, `dismiss(...)`, Codable models mirroring §2; a tiny `HeraldCallbackServer` helper that listens on an OS-assigned loopback port and delivers button callbacks to a closure (used by WebWatcher).
- **Python** `clients/python/herald.py` (stdlib only; `Herald().notify(app=..., title=..., …)`) and **Node** `clients/node/herald.js` (no deps). Both read token/port files and raise/throw when the service is down.

## 4. Repo layout
```
herald/
  project.yml            # xcodegen: Herald.app target (+ HeraldClient + herald CLI via Package.swift)
  Package.swift          # products: HeraldClient (library), herald (executable); the app target is Xcode-only
  Sources/Herald/        # app: App.swift, Server/, Banners/, History/, Settings/, Sounds/, Reminders/
  Sources/HeraldClient/  # shared Codable models + client
  Sources/herald-cli/
  clients/python/herald.py  clients/node/herald.js
  Tests/HeraldTests/     # router/auth, payload decoding, history store, snooze scheduling, CLI arg parsing
  scripts/notarize.sh    # copy of ~/github/web-watcher/scripts/notarize.sh
  README.md  DESIGN.md  CHANGELOG.md
```

## 5. Non-goals (v1)
Remote/network delivery, encryption beyond loopback+token, iOS, Focus awareness (the user does not need it), lock-screen banners.

## 6. Authoring UI (added 2026-10-01 — built in SwiftUI inside Herald)

- **Templates** (`Sources/HeraldClient/HeraldTemplate.swift`, Codable, stored at `~/Library/Application Support/Herald/templates/<app>/<name>.json`): `name`, `app`, `layout` (`imageLeft` default | `imageRight` | `hero` (image across the top, 16:9) | `compact` (one line, no image)), `accentColor` (hex, optional), `showSubtitle`/`showBody`/`showTimestamp`, `buttons` (default button set), `sound`, `persistent`, `timeout`, `snooze`, `reminder` default, `maxBodyLines`. Notifications may reference one with `"template":"bid-won"`; payload fields override template defaults; `{placeholders}` in template title/body are filled from `metadata` (e.g. `{amount}`), unknown placeholders are left blank.
- **Composer window** (menu "Compose…" and `herald compose` which just opens it): left column = form (app picker, template picker, title, subtitle, body with Markdown links, image file/URL, click url, buttons editor (label + action type url/callback/command + style), sound picker with ▶ preview, persistent/timeout, snooze on/off, reminder title/due, priority, metadata key/value rows); right column = live preview using the SAME banner view as real banners, rendered for light and dark appearance side by side; toolbar: **Send now**, **Save as template…**, **Copy as…** (curl / Swift HeraldClient / Python / Node / CLI command) which generates the exact code to reproduce the payload.
- **Template editor**: the same window opened on a template (menu Settings → Apps → Templates… → Edit), with a sample-data drawer to fill placeholders for the preview; Save/Duplicate/Delete.
- **Renderer**: one `BannerView(model:template:)` used by live banners, the composer preview, and history previews; layouts implemented as SwiftUI variants, not separate views.

## 7. Herald 1.1 — manifests, grid templates, components, two-way actions, Shortcuts, MCP (2026-10-01)

One sentence: Herald is a standalone macOS notification service that lets any app declare the data it can send and lets you design, in a visual grid-based editor, exactly how that data is rendered as persistent, interactive, animated banners with history, sound and actions.

### 7.1 Manifest (per issuer; `PUT /v1/manifest`, stored at Application Support/Herald/manifests/<app>.json)
```json
{"app":"webwatcher.email","appName":"WebWatcher · Email","icon":"<path|data:>","version":1,
 "fields":[{"key":"title","type":"text","required":true,"sample":"2 new from Acme Billing"},
           {"key":"subject","type":"text","sample":"Invoice #4021"},{"key":"sender","type":"text","sample":"Acme Billing"},
           {"key":"count","type":"number","sample":2},{"key":"image","type":"image","sample":"<bundled sample path>"},
           {"key":"receivedAt","type":"date","sample":"2026-10-01T14:14:00Z"},{"key":"url","type":"url"}],
 "actions":[{"id":"markRead","label":"Mark as Read","kind":"callback"},{"id":"archive","label":"Archive","kind":"callback","style":"destructive"}],
 "assets":[{"id":"bell","type":"rive","path":"<path to .riv>","stateMachine":"Main","inputs":["count","hover"]}],
 "defaultTemplate":"email-accumulated"}
```
Types: text, number, date, url, image, bool, list. Samples drive the designer preview. Fields not in the manifest may still be sent in `metadata` and appear in the palette as "custom". A notification references the manifest by `app`; `fields` values are read from the payload's top-level keys first, then `metadata`.

### 7.2 Grid template (`HeraldTemplate` v2; `layoutVersion: 2`)
- `grid`: `{rows:3, cols:4, rowSizes:["auto","auto","auto"], colSizes:["72","fill","fill","56"], gap:8, padding:14, width:400}`; sizes are `auto`, `fill`, or a point value.
- `cells`: each `{id, row, col, rowSpan, colSpan, align:"topLeading|top|topTrailing|leading|center|trailing|bottomLeading|bottom|bottomTrailing", padding, component}`.
- `collapse`: template default `"collapseEmpty": true|false`; each component may override with `emptyBehavior: "collapse"|"keep"`. Collapsing removes the component; a row or column whose cells are all collapsed (or empty) collapses to zero when `collapseEmpty` is on for them, else keeps its size.
- Components (`component.type`): `text` {binding:"{title} — {count}", style: title|subtitle|body|caption|mono, maxLines, color, font size}, `image` {binding:"{image}", fit: fit|fill|cover, cornerRadius}, `issuerIcon` {size, cornerRadius, shape: circle|rounded}, `timestamp` {binding:"{receivedAt}", relative:Bool}, `button` {action ref or inline action, style}, `actions` {source:"issuer"|"template"|"merged", layout: row|wrap|stack, maxVisible}, `iconButton` {symbol, action}, `badge` {binding:"{count}", color}, `progress` {binding}, `rive` {asset id or path, stateMachine, inputBindings:{inputName:"{token}" | "hover" | "pressed"}, action on click, loop}, `spacer`.
- Rich text (#64): a `text` binding may hold line breaks and markup (`**b**`, `*i*`, `` `m` ``, `__u__`, `~~s~~`, `{{size= color= font= weight=}}…{{/}}`, `{{align=}}`), or structured `lines:[{align?,runs:[{text?,token?,weight?,italic?,font?,size?,color?,underline?,strike?}]}]` (wins over `binding`); one AttributedString per line, lines stacked with `lineSpacing`; a line whose tokens are all absent collapses. Model and markup in `HeraldClient/RichText.swift`.
- Bindings use `{token}` syntax; a component whose every bound token is absent is "empty".
- The legacy v1 layouts (imageLeft/imageRight/hero/compact) become four built-in v2 grid templates so every existing template keeps rendering.

### 7.3 Two-way actions
- Resolved action list = issuer actions (from the payload's `buttons`/`actions`, or its `actionIds` looked up in the manifest; manifest actions are never shown unless the payload names them, while a sample preview assumes an issuer that names them all, all through `ActionResolver.issuerSource`) + template actions, applied through template rules: `actionRules: [{match:"markRead", hide:true}|{match:"archive", relabel:"Archive it", style:"destructive", position:0}|{add:{id:"shortcut-followup", label:"Follow up", kind:"shortcut", shortcut:"Create follow-up", input:"{title}\n{url}"}}]`.
- Action kinds: `url`, `callback` (to issuer), `command` (shell via /bin/zsh -lc, confirmed per app as today; template-authored commands, scripts and shortcuts are the user's own and are allowed after one confirmation per template, bound to the command text, the script file's SHA-256 or the shortcut's name and input), `script` (a file under Application Support/Herald/scripts run with the notification JSON on stdin), `shortcut` (`/usr/bin/shortcuts run "<name>" --input-path <tmp json or text>`; the template chooses whether the input is text from a binding or the full JSON), `dismiss`, `snooze`. Every action receives the merged payload (issuer fields + metadata + template-added `extra` key/values the user authored).
- Shortcuts palette: the designer lists installed shortcuts via `shortcuts list` and offers "Run shortcut…" with a picker; the MCP exposes the same.

### 7.4 Designer (replaces the v1 Compose "Look" section; v1 Compose stays for quick sends)
Window "Design Template": left palette (components; issuer fields as draggable tokens with their sample values; actions incl. issuer actions and "Add action…" for script/command/shortcut/url), center canvas = the 3×4 grid at real banner size with merge/split (select cells → Merge; Split), drag to move components between cells, resize spans, 9-point alignment control, right inspector (bindings, style, empty behaviour, size); preview bar: Sample / Last real notification / light / dark; "Send test"; Save; template list per issuer; Set as issuer default. Rendering uses the one `GridBannerView` that live banners use.

### 7.5 Preview API (for the designer, MCP and tests)
`POST /v1/preview` `{template:<HeraldTemplate v2 or name>, app, data:{…}|"sample", appearance:"light"|"dark", scale:2}` → PNG bytes (rendered offscreen with ImageRenderer from the same GridBannerView). `GET /v1/manifests`, `GET /v1/manifest?app=`, `PUT /v1/manifest`, `GET /v1/shortcuts` (names from `shortcuts list`), `GET /v1/components` (schema of component types and their properties, for agents).

### 7.6 MCP server (`herald-mcp`, Swift executable target, stdio JSON-RPC 2.0, MCP protocol version 2025-06-18)
Tools: `herald_status`, `list_manifests`, `get_manifest`, `put_manifest`, `list_templates`, `get_template`, `put_template` (validates against the grid schema and returns errors with cell ids), `delete_template`, `validate_template`, `component_schema`, `render_preview` (returns the PNG as an MCP image content block plus the file path), `send_notification`, `send_test` (template + sample data), `list_shortcuts`, `add_action_rule`, `list_history`, `dismiss`. Resources: `herald://manifests/<app>`, `herald://templates/<app>/<name>`, `herald://docs/components`. The binary reads the token/port files like the CLI. `docs/MCP.md` shows the Claude Code (`claude mcp add herald -- /usr/local/bin/herald-mcp`) and Codex config. `make install` installs both `herald` and `herald-mcp`.

### 7.7 Rive
Dependency: the Rive Apple runtime Swift package (github.com/rive-app/rive-ios, product `RiveRuntime`, supports macOS 13+) added to project.yml and Package.swift (the app target only; HeraldClient stays dependency-free). The `rive` component hosts a `RiveViewModel` in an NSViewRepresentable, binds numeric/bool/trigger inputs from tokens, drives `hover`/`pressed` inputs from the banner's mouse tracking, and maps click to an action. Assets come from the manifest (copied into Application Support/Herald/assets/<app>/) or from the template's own assets folder. A failed load renders a placeholder with the error, never crashes the banner.

### 7.8 WebWatcher
Registers two manifests (`webwatcher.web`, `webwatcher.email`) with samples and actions, sends fields at the top level, ships default templates for both, and keeps the v1 payload path working.

## 7.9 Voice: spoken notifications and voice messages (added 2026-10-01)

Agents can make Herald speak a notification or attach a recorded voice message; the text always goes to history so the log stays searchable.

- **Payload**: `speak` on `/v1/notify` — `true` (speak title, then body) or `{"text":"…","voice":"af_heart","speed":1.1,"lang":"en-us"}`; `audio` — path, `data:` URI or https URL of a WAV/MP3/M4A voice message to play on delivery (cached under history/audio/, ≤ 20 MB); `presentation` — `"banner"` (default), `"voice"` (no banner; history entry only), `"both"`. `POST /v1/speak {app, text, voice, speed}` is a shortcut for presentation voice. The CLI gains `--speak`, `--speak-text`, `--voice`, `--speed`, `--audio`, `--presentation`; the MCP gains a `speak` tool and `speak`/`audio` fields on `send_notification`.
- **Engine** (Settings → Voice): `Kokoro (local, natural)` — an optional download; `System voice` — AVSpeechSynthesizer fallback; `Off`. Kokoro runs through a Python venv exactly like the user's existing `~/.claude/tts/speak` script: `uv venv --python 3.12 <support>/tts/venv && uv pip install kokoro-onnx soundfile` (fall back to `python3 -m venv` + pip when uv is absent), models `kokoro-v1.0.onnx` (≈310 MB) and `voices-v1.0.bin` (≈27 MB) downloaded from the kokoro-onnx GitHub release into `~/Library/Application Support/Herald/tts/` with progress, SHA-256 printed, resumable; the Settings pane also offers "Use existing installation at ~/.claude/tts" (symlink/copy) which is pre-filled when that folder exists. Synthesis = a persistent Python worker process (`tts_worker.py` bundled in Resources) that keeps the model loaded and answers JSON lines `{text, voice, speed, out}` → WAV; first-call latency a few seconds, later calls < 1 s. Playback via AVAudioPlayer with a queue (never overlapping speech), interruptible by Dismiss, respects global mute and per-app "Speak" toggle; a ▶ button on the banner and in History replays the cached WAV.
- **Voices**: af_heart (default), af_bella, af_nicole, am_michael, bf_emma, bm_george and the rest reported by the model; per-app default voice and speed in Settings; the designer can bind `speak.text` to a template field (e.g. `{sender} says {subject}`).
- **History**: entries store `speech: {text, voice, audioPath, durationSeconds}`; the History window shows a speaker icon, the spoken text, and replay.
- **Security**: audio files validated by signature; text length capped (2,000 chars); no shell interpolation (the worker receives JSON over stdin).

### 7.9.1 Quiet hours for voice (added 2026-10-01)
Settings → Voice → **Quiet hours**: a list of windows `{days: [Mon…Sun], start: "22:30", end: "07:30"}` (overnight windows allowed), each with checkboxes for what it silences: **Speech** (on by default), **Sounds**, **Banners** (banners silenced go straight to History and the +N pill, still counted as unread). Stored in AppSettings (`quietHours: [QuietWindow]`), evaluated in the user's local calendar at delivery time; a window that is active shows "Quiet until 07:30" in the menu bar menu with "Resume now". Suppressed speech is logged in history as `speech.suppressed: "quiet-hours"`; an optional per-window "Speak queued messages when quiet hours end" plays a single summary ("3 messages while you were away: …") at the window's end. Per-notification override: `priority: "urgent"` may bypass quiet hours only if the per-app setting "Urgent can break quiet hours" is on (off by default). API: `GET/PUT /v1/settings/quiet-hours` so the MCP/CLI can read and set them; `herald quiet --until 07:30` and `herald quiet off` for ad-hoc silence.

## 8. Focus invariant (2026-10-01, user requirement: "must make absolutely sure that a notification does not take away focus from any app")
- Banner panels are `.nonactivatingPanel`, `canBecomeKey == false`, `canBecomeMain == false`, `becomesKeyOnlyIfNeeded`, shown with `orderFrontRegardless` — never `makeKey…`, never `NSApp.activate` on the delivery path.
- Confirmations (callback host, command, template command, Reminders errors) must NOT use `NSAlert.runModal` + `NSApp.activate` (that steals focus). They become an inline confirmation row inside the banner itself ("Run `…`? Run once · Always allow · Cancel"), rendered by GridBannerView/BannerView, answered by button presses that still never activate Herald. Only user-opened windows (Compose, Designer, History, Settings) may activate the app.
- Regression check in the integrator protocol: with another app frontmost, post a banner, press a callback button and a template-command button via AX, and verify the frontmost app never changes.

## 9. Stacking: same-sender notifications collapse into one banner with a counter (2026-10-01)
- **Grouping levels** (setting `stacking`, global default `bySender` with a per-issuer override, and a quick switch in the bell menu):
  - `byApp` — one stack per product family: the manifest's `family` (e.g. `"webwatcher"`), falling back to the issuer id's prefix before the first dot, so `webwatcher.web` and `webwatcher.email` share a stack ("all WebWatcher notifications").
  - `byIssuer` — one stack per manifest/issuer id ("all Gmail notifications", "all web-watcher notifications").
  - `bySender` — one stack per payload `group` key (an email sender, a watched site such as Rive, a bid id); issuers set `group`; when absent it falls back to the issuer id.
  - `never`.
  Per-issuer overrides let, for example, Gmail stack by sender while web watchers stack by issuer.
- **Behaviour**: when a banner arrives for a group that already has a live banner, the new one becomes the top card of that group's stack: one panel showing the newest notification plus a count badge ("3") and a stacked-cards visual (two offset edges behind the card). Replacing by `id` still updates in place and does not increase the count. The stack's sound/speech follow the newest notification.
- **Expand**: clicking the count badge (or the card body when the template has no click url) expands the stack in place: the panel grows into a scrollable list of the group's banners (each rendered with its own template, newest first, ≤ 6 visible then scroll), with "Collapse" and "Dismiss all" at the bottom. Clicking a member's body opens its url; its actions work individually. Esc or a click on the collapse control returns to the stacked card. Expansion never activates Herald (focus invariant §8).
- **Dismiss / snooze**: the card's ✕ dismisses the whole group (members go to History as dismissed); a member dismissed from the expanded list leaves the stack; snooze applies to the group and restores it as a stack.
- **History** records each member individually with `group`; the History window groups by `group` with a disclosure.
- **Templates**: `{stack.count}` token and a `stackBadge` component (defaults to the top-right of the card) so a template can place the counter; `{stack.count}` is empty when the count is 1.
- **API**: `POST /v1/dismissAll {app, group}`; `GET /v1/stacks?app=` lists live stacks; MCP exposes `list_stacks`.
- **Built (1.2)**: the rules are pure (`Core/StackPlanner.swift`: `StackKeying`, `StackBook`, `HistoryGrouping`, tested in `StackPlannerTests`); `Banners/StackCenter.swift` holds the live `StackBook` and `BannerCenter.applyStacks()` draws it, one panel per stack (the top card's; a card under another has no panel on screen while the stack is closed). The stack sits where its top card would, so a new member, or a member sent again under its id, brings the stack to the top of the screen; the count never changes on a replace. A stack counts down as one: hovering the card or opening the list holds every member's timeout, and each member still expires on its own. The close button, snooze menu and body click of a closed stack's top card act on the group (a body click with no url opens the stack); on a lone banner or a row of the open list they act on that notification. Group snooze wakes the members oldest first a few milliseconds apart, so the stack is rebuilt with the same top and chimes once. `Esc` collapses an open stack only while a Herald window has the key: a banner panel never takes the key (section 8) and a global key monitor needs Accessibility or Input Monitoring, so the badge and the Collapse button are the controls on the banner itself. Test hooks that need no UI: `GET /v1/stacks` (each stack's panel `frame`), `POST /v1/stacks/expand {app, group, expanded}`, and `stackCount` / `stackExpanded` on `POST /v1/preview`.

## 10. Testing policy (2026-10-01, user requirement)
Automated and delegated verification must never take focus from the user: no window activation, no Accessibility presses on live UI, no screenshots that need a window in front, no UI scripting. Verify through the HTTP/MCP API (`/v1/preview` returns rendered PNGs; `/v1/history`, `/v1/stacks`, `/v1/apps`), unit and snapshot tests (offscreen ImageRenderer), and headless Debug instances that only answer API calls. Where a UI path has no API, add a test hook or an endpoint rather than driving the UI.
Rive without a window: `POST /v1/rive/check {app, component, fields?, simulate?}` loads a `rive` component in the same `RiveHostView` a banner uses, with no window, and reports `loaded`/`error` (the placeholder's text), the state machine's `inputs` by kind, the `applied` values the fields write, the file's `artboards`, whether the view `takesClicks`, and what the simulated pointer steps (`hoverIn`, `hoverOut`, `pressDown`, `pressUp`) wrote to inputs (`pointerWrites`) and which click actions ran (`clickedActions`). Offscreen `/v1/preview` draws a placeholder for Rive by design.
Designer layout without a window: `GET|POST /v1/designer/snapshot?app=&width=&height=` draws the Designer's content offscreen (no window) as PNG. The live preview is a pane of its own, never below half the design area (`Core/DesignerSplit.swift`): on top of the editor below 1700 pt width, beside it above; the divider is draggable and remembered.

## 11. Cloud relay (2026-10-02, user request: a cloud agent must be able to notify this Mac)
Full description: [docs/CLOUD.md](docs/CLOUD.md). Source: `relay/` (Cloudflare Worker + Durable Object) and `Sources/Herald/Relay/`.
- **Shape**: a Worker `herald-relay` with one Durable Object ("mailbox") per paired Mac. Herald keeps one **outbound** WebSocket (URLSessionWebSocketTask,
  hibernation API on the relay side) and there is no inbound port. Agents reach the mailbox over HTTPS or remote MCP (`/mcp`, Streamable HTTP,
  protocol 2025-06-18, four tools: `send_notification`, `get_receipt`, `wait_for_reply`, `herald_status`).
- **Auth**: pairing with a one-time code returns a device token (Keychain); agent keys are minted only with it, scope `notify` only, stored hashed, revocable,
  bound to their own device. Agent keys never reach `/v1/device/*`; there is no endpoint that changes permissions or settings.
- **Text only**: the relay accepts a whitelist of fields (no command, callback, script, shortcut, buttons, url, image, audio, template); Herald rebuilds the
  notification from a whitelist again and runs it through the normal notify path as app `cloud.<key name>` (manifest with Reply, Record and Open link; the real
  Claude/Codex icon for those keys). Mute and quiet hours are enforced on the Mac (`RelayPolicy`); a held-back item sends a `suppressed` receipt with the reason.
- **Receipts** are separate: `received` (relay, on enqueue), `displayed` (banner up), `spoken` (speech queue job finished, `SpeechQueue.Job.finished`), `replied`,
  `suppressed`. Dedupe by the relay's delivery id, persisted 24 h on both sides.
- **Replies**: Reply (text, the existing reply queue and `ReplyRecorder`) and Record (a `reply` action with `voice: true`): an inline record strip like the
  reply and confirmation strips (focus invariant, section 8, holds; recording only starts on the button), AAC m4a 32 kbps mono, 60 s, on-device transcript,
  upload to R2 (7-day lifecycle), signed one-hour `audioUrl` for the agent; History keeps the m4a and transcript (`replyAudioPath`, `replyTranscript`).
- **Free plan**: designed to its limits (hibernation, auto-response pings every 5 minutes, no polling, 24 h TTL, per-key and daily caps, in-memory counters);
  the budget table is in docs/CLOUD.md. Hitting a limit shows "Relay offline - limit reached" and loses nothing.
- **Testing**: relay: vitest + miniflare (`relay/test`); Herald: `RelayTests.swift` with a fake socket, fake HTTP and fake recorder; live checks through a headless
  Debug instance against `wrangler dev` (section 10: no UI is driven).
