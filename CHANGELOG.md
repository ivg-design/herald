# Changelog

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
