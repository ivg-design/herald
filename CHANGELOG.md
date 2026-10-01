# Changelog

## Unreleased - security and robustness fixes

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
