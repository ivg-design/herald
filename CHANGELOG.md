# Changelog

## Unreleased

### Fixed

- **Relay device hygiene and selection**: unpair purges the Mac's mailbox; pairing again under the same device name replaces the old entry;
  stale entries (rotated credentials, 30 days without a connection) are pruned lazily and by a daily alarm; `POST /v1/device/prune`,
  `GET /v1/device/devices`, `DELETE /v1/device/devices/{id}` (same-name or stale entries only); Herald prunes after every pairing and lists
  "Devices on this relay" under Settings > Cloud > Advanced. Without `device=`, `/device_authorization` and `/authorize` target the connected
  Mac (else the most recently seen), never just the first entry, and say which (`device_name`, `device_count`).
- **A relay upgrade keeps the pairing** (#79): the signing secret is never rotated by an upgrade; a deploy that did change it pairs this
  Mac again automatically; the stale "relay is not answering" message clears once online.
- **Connector approvals are one banner**: one open request per client and Mac, reconnects only refresh the list (`redelivered`), expired
  requests are removed from the mailbox and Herald, decisions remove the request on every Mac.
- **Herald's own identity**: one `herald` app named "Herald" with the app icon; `herald.connectors` is folded into it (group "connectors").
  `relay_test` leaves no trace. `DELETE /v1/apps/{id}` and `delete_app`; startup removes History of unregistered apps and the known test
  leftovers; the docs example is `example.bidbot`. History > "All Apps" is selectable and the default.

## 1.6.2 (Build 12) - 2026-10-02

### Added

- **OAuth device flow on the relay** (RFC 8628) for agents without a browser: `POST /device_authorization` returns a
  short user code; Herald shows "Approve <client> to send you notifications? Code BDFG-HJKM" with Approve / Deny
  (also under Settings → Cloud → Connector approvals); the agent polls `/token` and gets the same revocable key as the
  browser flow. `/activate` is the page for humans with a browser; `GET /` is a small info page. Documented in
  docs/CLOUD.md, docs/MCP.md, the agent quickstart and `relay_instructions` (client `device`).
- **Presentation fields through the relay**: `persistent`, `timeoutSeconds`, `sound`, `speak`, `voice`, `speed`,
  `presentation`, `priority`, `group`, `icon`, `subtitle`, `imageURL`, `tags` are accepted and rebuilt from a whitelist;
  executable keys still return a 400 listing every stripped key. A relay notification is persistent until dismissed
  by default; `expectReply` now only adds the Reply and Record buttons instead of turning the notification into a
  "question".

### Fixed

- Secrets (relay device token, Cloudflare token, pairing secret) moved to a `SecretVault` backed by the
  data-protection keychain with a 0600 file fallback under the support folder, so a new build never triggers the
  login-keychain password dialog; the legacy item is migrated once and a denied or cancelled read counts as "not
  found" without asking again.

1143 tests · 136 relay tests.

## 1.6.1 (Build 11) - 2026-10-02

### Added

- **Custom domain for the relay (optional).** Settings → Cloud → Advanced → Custom domain: load the account's zones,
  pick one, accept the suggested `herald.<zone>`, and Herald attaches a Workers Custom Domain, adds a configuration
  rule that switches Cloudflare's Browser Integrity Check off for that hostname only, adds a narrow WAF skip, warns
  about Bot Fight Mode (free-plan zones must turn it off by hand), waits for the address and re-points itself,
  keeping the pairing. Needs a token with the zone permissions (Zone Read, DNS Edit, Workers Routes Edit, Zone Settings
  Edit, Config Settings Edit, Zone WAF Edit); a token without them stops with a clear message. `relay_zones` and
  `relay_settings.customDomain` over MCP/API. OAuth connectors are bound to the URL they were approved on and must be
  re-added after a hostname change.
- `relay_test` probes the hostname with Python's default `Python-urllib/3.12` user agent and reports whether the
  Browser Integrity Check is active.

### Changed

- Cloud-agent instructions (Settings, `relay_instructions`, docs/CLOUD.md, the agent quickstart) now say: send a
  custom User-Agent. Cloudflare rejects Python's default `Python-urllib/3.x` with Error 1010 on every workers.dev
  hostname before the request reaches the relay; any other value works, so a custom domain is not required.

1123 tests · 92 relay tests.

## 1.6.0 (Build 10) - 2026-10-02

### Added

- **Enable relay, one switch.** Settings → Cloud → Enable relay creates the user's OWN relay on their free Cloudflare
  account: Herald opens the pre-filled API-token page, takes the token once (Keychain), and deploys the bundled Worker
  itself through Cloudflare's API — account, workers.dev address, voice-reply bucket with 7-day expiry, upload,
  secrets, health check — then pairs this Mac. Step log with Retry; deploying again upgrades in place; "Update available"
  when Herald ships a newer relay. Off = unpair and revoke everything. No wrangler, no Node, no shared relay: the
  maintainer's deployment is no longer a default.
- **Advanced**: every relay parameter visible and editable (relay URL for any relay, account, worker name, subdomain,
  bucket, retention, queue TTL, daily cap, max queue, body limit, per-key rate, max devices, device name, ping interval,
  pairing secret) with Apply, Redeploy, Test connection, Pair with a code, Unpair, Forget token, Delete relay.
- **OAuth 2.1 on the relay** (MCP authorization spec): discovery documents, dynamic client registration, PKCE,
  consent page with "Approve in Herald" (a banner with Approve / Deny, never taking focus) or a 6-digit code under
  Settings → Cloud → Connector approvals, access + rotating refresh tokens bound to a revocable agent key, revoke.
  ChatGPT and OpenAI cloud agents connect by adding `…/mcp` as a connector with Authentication: OAuth. Static `hrk_`
  keys still work for Claude Code / Codex.
- **MCP setup parity**: `relay_token_url`, `relay_set_cloudflare_token` (write-only), `relay_deploy`, `relay_pair`,
  `relay_unpair`, `relay_settings`, `relay_delete` (confirm), `relay_instructions`, `relay_test`, plus `list_connectors`
  and `create_agent_key` — an agent can walk a user through the whole setup (docs/AGENT-QUICKSTART.md).
- Worker hardened for many devices: per-device daily caps (500 notifications, 100 queued, 40 voice replies / 20 MB,
  5,000 requests), pairing limits per client address, `MAX_DEVICES`, re-audited Durable Object routing, `/health`
  reports the bundle hash. Free-plan budget for N devices in docs/CLOUD.md.

### Changed

- The relay bundle ships inside Herald (`Resources/relay/worker.js`, built by `make relay-bundle`; a test fails when
  it is stale).

1107 tests · 87 relay tests · 33 conformance checks.

## 1.5.0 (Build 9) - 2026-10-02

### Added

- **Cloud relay.** A Cloudflare Worker (`relay/`, deployed at https://herald-relay.ivg-design.workers.dev) and Herald's outbound
  `RelayClient` let a cloud agent notify this Mac through a notify-only key and a remote MCP connector (`send_notification`,
  `get_receipt`, `wait_for_reply`, `herald_status`). Mute and quiet hours are enforced on the Mac; receipts are separate for
  received, displayed, spoken, replied and suppressed. Settings > Cloud pairs the Mac, mints and revokes keys and shows usage.
  Cloud banners have Reply and a Record button (on-device transcript, m4a to the agent). See docs/CLOUD.md.
- The app entitlement `com.apple.security.device.audio-input` is set so Record works under the hardened runtime.

1069 tests.

## 1.4.1 (Build 8) - 2026-10-02

### Added

- **Rich text.** A `text` component can hold real line breaks; inline markup (`**bold**`, `*italic*`, `` `mono` ``,
  `__underline__`, `~~strike~~`, `{{size=14 color=#FF3B30 font=serif weight=medium}}…{{/}}`, `{{align=center}}` per
  line) or the structured `lines: [{align, runs: [...]}]` form; per-run styling overrides the component's style and a
  line's align overrides the component's. The Designer's Text field is a multi-line editor with a formatting bar
  (Bold, Italic, Mono, Underline, Strike, Size, Color, per-line Align), the `{}` token menu at the caret and a live
  preview; markup ⇄ lines is lossless. `component_schema`, `validate_template` and `render_preview` know it.
- **Agent notifications that make sense.** The agent default template has Open (brings the host app forward — Claude.app
  for Claude Desktop, the terminal or editor the install ran from for Claude Code / Codex, changeable under
  Settings → MCP → Opens), Reply (an inline text field in the banner; the answer lands on the history record and in a
  queue read by the new `get_replies` / `wait_for_reply` tools — "Ask the user a question" in docs/MCP.md) and Open
  link only when a link is present. Done and the Dismiss button are gone; × is the only close. `reply` is also an
  issuer action kind for any app.
- Settings → General shows the version and build bottom-right (click to copy).

### Fixed

- App icon: the source PNG carried a fully opaque 1 px seam on its left and right edges, visible as bright lines in
  the Dock; trimmed, and the artwork now sits on Apple's 824/1024 icon grid.
- Grid columns always sum to the inner width: resizing trades width between neighbours, the last column absorbs any
  remainder when nothing fills, 24 pt minimum per column (drags, inspector, context menu, `put_template`), templates
  that load short are auto-fixed with a warning, rulers show every column's resolved width.
- An actions row set to trailing (or in a trailing-aligned cell) now sits at the right edge.
- The style dropdown in action rows, the action editor and the issuer-action menu is labelled "Button style".
- Tooltips say what a control is or does ("Badge — a small capsule showing a short status or count"), never how to
  click it; the palette reads from the catalog.

1025 tests.

## 1.4.0 (Build 7) - 2026-10-02

### Added

- **Designer layout.** Left sidebar, centred column with the live preview above the editor grid on one axis, right
  inspector; both sidebars full height; the preview/editor divider is a full-width drag (half by default, a quarter to
  three quarters); sidebar widths drag and persist; both surfaces zoom 50–300 % (⌘+ / ⌘− / ⌘0, pinch, popover) per pane.
- **SF Symbols browser.** Apple's catalog (7,779 symbols in 25 categories) with All / Recents / Favourites, synonym
  search ("bin" finds trash), a resizable grid with a size slider, a 96 pt preview in the current weight, mode and
  colours; opens as a sheet or as a floating, non-activating panel.
- **Arbitrary button arrangements.** `actions` takes `include`, `align`, `wrap`, `spacing`; `button.actionId` binds one
  issuer action; an action renders in exactly one cell (first in reading order; duplicates warn and collapse). The
  Actions tab explains it with the Mark-as-Read-under-the-icon example.
- **Button style** `normal` / `prominent` / `destructive` / `cancel` (old `destructive: true` still decodes); destructive
  is a red label plus an inline confirmation before running, for template buttons and issuer actions alike.
- **Open app** action kind (`openApp`, `bundleId` / `path`, falling back to the manifest's `appBundleId` / `appPath`, the
  registered bundle id, then `appName`); usable as a rule, an issuer action, the banner's `onClick`, in the Designer
  (Choose app…) and over MCP.
- **Image source** From issuer / Fixed image… (copied into the support folder) / Field…; every token picker groups
  tokens by provenance — issuer manifest field, notification payload field, set here — with sample values.
- **Tooltips** on every control through one helper; Settings → General → Tooltips: Name only / Name and description.
- **⌘,** opens the single shared Settings window from any Herald window (the blank SwiftUI settings scene is gone).
- **⌘-Tab.** While the Designer, Quick send, History, Settings or the template editor is open, Herald appears in the
  switcher with its icon; back to menu-bar-only when the last window closes. Banners never change the policy.
- **MCP / API parity.** 28 new tools (49 in all) and 18 new routes so everything the editor and Settings can do is
  reachable: settings get/set, per-app settings, assets, template duplicate/rename/set-default, bundle import/export,
  history search/re-show/delete/export, symbol list, designer snapshot, Rive check, snooze, stacks, manifests. Granting
  approvals is deliberately not exposed. `docs/reference/parity.md` is the audit.
- **Agents as issuers.** Installing an MCP client registers `agent.claude-code`, `agent.codex`, `agent.claude-desktop` or
  `agent.<slug>` with a manifest, default template, sound and the real product icon (Claude from Claude.app; Codex asks
  you to choose one); `herald-mcp --agent` defaults the app for send/speak/dismiss/history; Settings → MCP shows
  "Design notifications…" per client; reinstall keeps your template.

### Fixed

- Column and row handles, the inspector field and the context menu are clamped so no track can exceed the grid width.
- Position and Span are separate labelled groups; Span is disabled when a cell cannot grow.
- `docs/TEMPLATES.md` and `docs/ACTIONS.md` brought level with the 1.3/1.4 schema.

979 tests.

## 1.3.1 (Build 6) - 2026-10-02

### Changed

- Herald has its own app icon (from `public/assets/Raster/Herald-icon.png`) and its own menu-bar glyph
  (`public/assets/Vector/Herald Statusbar Icon.svg`, a template vector drawn at 18 pt); muted draws the same
  glyph at 40 % instead of switching to a bell-with-slash symbol.

## 1.3.0 (Build 5) - 2026-10-01

### Added

- **SF Symbols everywhere.** Buttons, icon buttons, action rows, the issuer icon and badges take a `symbol`:
  a plain name or an object with `weight`, `scale`, `placement`, `renderingMode` (monochrome, hierarchical,
  palette, multicolor) with up to three `colors` (hex or `{token}`), a `variableValue` (number or `{token}`),
  and an `effect` (bounce, pulse, variableColor, scale, appear, disappear, replace; trigger onAppear /
  onChange / onHover / repeating; speed, cumulative, reversing). Effects play in live banners on macOS 14+,
  never in offscreen previews, and are off under Reduce Motion. The Designer has a Symbol panel with a
  searchable picker (favourites and recents), and `component_schema`, `validate_template`, `put_template`
  and `add_action_rule` know the keys; unknown names and inconsistent values are warnings, not errors.
- **Designer: live preview as a first-class pane.** The rendered banner takes at least half of the design
  area (above the editor below 1700 pt of width, beside it above), with light/dark, sample vs last data,
  and Send test; the divider is draggable and remembered. `GET|POST /v1/designer/snapshot` renders the
  window layout offscreen for tests.
- **Designer: components render for real.** A placed, bound component such as `{count}` draws with the
  manifest's sample value instead of an empty box; helper captions ("empty · collapses") are overlays that
  never change a cell's size.
- `POST /v1/rive/check` loads a Rive component in a window-less host and reports load errors, inputs,
  bound values, hover/press writes and click actions.
- `docs/reference/`: a complete reference — every component and every property, grid and layout, bindings,
  manifests, a full Rive guide (preparing a .riv, inputs, hover and click, sizing, assets, bundles,
  troubleshooting), SF Symbols, actions, stacking, voice, quiet hours, the HTTP API, the CLI, all MCP tools,
  and a glossary.

### Fixed

- Empty Designer placeholders were a fixed 34 pt and overlapped the next row when a row was shorter; they
  now follow the row height.
- Markdown links to blocked schemes (`file:`, custom schemes) were not recorded as link clicks, so the tap
  also opened and dismissed the banner (`LinkClickGuard`).
- Several snoozes coming due together after sleep or a clock change chime once instead of once each
  (`Snooze.rearmPlan`).
- The Kokoro installer is covered end to end (download, SHA-256, resume from `.part`, 404, cancel,
  use-existing); the quiet-hours summary tracker is extracted and tested.
- The Shortcuts success path is tested against a stand-in `shortcuts` tool.
- `docs/ACTIONS.md`: a `command` action's text is not interpolated; the merged payload arrives on stdin
  as JSON and in `HERALD_*` environment variables.

867 tests.

## 1.2.0 (Build 4) - 2026-10-01

### Added

- Inline banner confirmations (no dialogs, no focus change): a per-app or per-template gate swaps the
  button row for a yes/no strip inside the banner; callbacks report done / failed / still running and a
  banner is dismissed only when the action succeeded.
- Stacking: same-sender notifications fold into one banner with a counter, grouped by app, issuer or
  sender; click to expand in place; `GET /v1/stacks`, `POST /v1/dismissAll {app, group}`.
- Per-app display, corner and mute; lazy promotion; SQLite history with migration from the file store;
  template bundles (`.heraldtemplate`) with `herald template export/import`; Compose unified into the
  Designer; a Rive inspector; the bidbot example; snapshot tests; Settings → MCP one-click install for
  Claude Code, Codex, Claude Desktop and any client, with `herald` and `herald-mcp` bundled under
  `Contents/Helpers`.
- Notarized and stapled builds.

### Security and robustness

- Template scripts and Shortcuts are confirmed before they run, like template commands, and the approval is
  bound to what was shown (the script file's SHA-256, the Shortcut's name and input). A template's default
  `buttons` count as the template's own code, not the issuer's. The prompt names the issuer button an action
  replaced (same id). `add_action_rule` is annotated destructive. The `send_notification` and `send_test` tools
  refuse command buttons unless `allowCommandButtons` is set.
- A grid with more than 12 rows or columns is refused while it is decoded (a 31-byte body could allocate
  hundreds of megabytes), `PUT /v1/templates` validates what it stores, and the grid solver clamps track counts.
- Payload `actions` (the documented name for `buttons`) and `actionIds` now work: they resolve through one
  function (`ActionResolver.issuerSource`) for the banner, a press, the preview and the Designer. Manifest
  actions are shown only when the payload names them; a sample preview assumes it names them all.
- `get_manifest` takes `full: true`; `put_manifest` restores abbreviated markers from the stored manifest and
  refuses ones that match nothing.

- Banner, button and History links open only `http`, `https` and `mailto` URLs. Cached images are
  recognised by their bytes and stored with the matching extension (never one chosen by the sender);
  non-images are not stored, so a payload can no longer plant a file that a later click would launch.
- The listener checks the Bearer token, `Host` and `Origin` on the request head, before any body is
  buffered; body limit 32 MB -> 1 MB; 10 s deadline per request; at most 32 open connections.
- Field-size limits on notify and register (413), at most 200 apps, orphaned cached images are deleted,
  the app list and unread count no longer re-read every history file, Dismiss All and multi-delete
  refresh once, the banner body is parsed once.
- Callbacks to a non-loopback host need the user's approval (alert, plus a toggle in Settings > Apps);
  redirects are never followed.
- A notify that is still preparing its image can no longer overwrite a newer update or bring back a
  banner that was dismissed meanwhile.
- Banners that do not fit the screen collapse into a "+N more" pill; only the 6 newest are restored at
  launch; layout follows display changes.
- Action buttons no longer wrap inside their capsule; the row wraps between buttons.
- Placeholder values in a template `url` keep existing `%XX` escapes and `#` fragments.
- Composer "Copy as > Node" wraps the call in an async function (CommonJS has no top-level `await`).
- `HeraldCallbackServer(statusHandler:)`: the callback answer can reflect the outcome of the action.

## 1.1.1 - 2026-10-01

- **One-click MCP install**: Settings > MCP installs the bundled `herald-mcp` into Claude Code, Codex and
  Claude Desktop (with status detection, Reinstall, config backups), copies a generic config, installs the
  `herald` command line tool to `/usr/local/bin`, and has a Test connection button.
- `herald-mcp` and `herald` are now built into `Herald.app/Contents/Helpers/`, signed with the app.

## 1.1.0 (Build 2) - 2026-10-01

- **Manifests**: `PUT/GET /v1/manifest`, `GET /v1/manifests`. Issuers declare fields (with samples),
  actions and assets; WebWatcher registers `webwatcher.web` and `webwatcher.email`.
- **Grid templates** (`layoutVersion: 2`): rows, columns, spans, nine-point alignment, and the components
  text, image, issuerIcon, timestamp, button, actions, iconButton, badge, progress, rive and spacer.
  The v1 layouts become built-in grid templates, so existing templates keep rendering.
- **Collapse or keep**: empty fields collapse or keep their space, chosen per template (`collapseEmpty`)
  and per component (`emptyBehavior`).
- **Designer** window with palette, grid canvas, inspector, light/dark and sample/last-notification preview.
- **Two-way actions**: issuer and template actions merged through `actionRules`; new action kinds
  `script`, `shortcut`, `dismiss`, `snooze`; template `extra` data added to every action's payload.
- **Apple Shortcuts**: `GET /v1/shortcuts` and a picker to run a shortcut from a banner button.
- **Rive** component (Rive Apple runtime) with token-driven inputs, hover and pressed.
- **Preview API** `POST /v1/preview` (PNG) and `GET /v1/components` (component schema).
- **`herald-mcp`**: MCP server (stdio) to author templates, render previews, add action rules and send tests.
- Docs: TEMPLATES.md, ACTIONS.md, MCP.md; clients document manifest registration.

## 1.0.0 (build 1) - 2026-10-01

First version of Herald.

- Menu-bar app (no Dock icon) with unread count, History, Mute, Dismiss All, Settings, Quit.
- Loopback HTTP/JSON API on 127.0.0.1:48617 (port override in Settings), Bearer token in
  `~/Library/Application Support/Herald/token` (mode 0600), port file next to it.
  Endpoints: health, register, notify, dismiss, dismissAll, snooze, history (GET/DELETE), apps,
  templates (GET/PUT/DELETE).
- Banners: non-activating always-on-top panels on all Spaces, stacked from the chosen corner
  with 8 pt gaps, slide/fade, hover pauses timeouts, same `id` replaces in place, persistent by
  default, undismissed banners restored on relaunch.
- Rich content: image preview, title/subtitle/Markdown body, app icon badge, timestamp,
  buttons (open URL, callback webhook, command), snooze (5m/15m/1h/Tomorrow 9:00, survives
  relaunch), Add to Reminders (EventKit).
- Per-app history (JSON, 1000 items, cached images), History window with search and context menu.
- Per-app settings: sound, persistence, timeout, screen corner, command permission.
- Sounds via NSSound (system names, file paths, none, global mute).
- `HeraldClient` Swift library: models, client, and `HeraldCallbackServer`.
- Templates: reusable banner designs per app with layouts (imageLeft, imageRight, hero, compact),
  accent colour, visibility toggles, `{placeholders}` filled from `metadata`; notifications reference
  them with `template`.
- Composer window with live light/dark preview, Send now, Save as template, and Copy as curl / Swift /
  Python / Node / CLI; Template editor with a sample-data drawer; `herald compose`.
- Documentation: docs/API.md, docs/AUTHORING.md, clients/README.md; WebWatcher delivery integration.
