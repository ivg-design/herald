# Parity: Designer, Quick send, History and Settings vs HTTP, CLI and MCP

The goal ([#56](https://github.com/ivg-design/herald/issues/56)): everything a person can do in Herald's windows
and Settings, an agent can do through the MCP server. Every MCP tool is a thin wrapper over one HTTP route
([api.md](api.md)); the CLI covers the routes that are natural at a prompt. "Before" is the state at 1.3.1
(2026-10-02) when the audit was made, "After" the state once #56 closed.

Legend: **ok** reachable, **gap** not reachable, **via X** reachable through the named route or tool because the
whole document is one JSON value, **UI** a view state with nothing persisted (selection, undo, zoom, drag), so there is
nothing to expose, **by design** deliberately not exposed (see the end).

## Designer: templates

| Capability | HTTP route | CLI | MCP tool | Before | After |
|---|---|---|---|---|---|
| List saved templates | `GET /v1/templates` | `template list` | `list_templates` | MCP ok, CLI gap | ok |
| Read one (also `builtin.*`) | `GET /v1/templates` | `template get` | `get_template` | MCP ok, CLI gap | ok |
| Create / overwrite (validated) | `PUT /v1/templates` | `template put FILE` | `put_template` | MCP ok, CLI gap | ok |
| Delete | `DELETE /v1/templates` | `template delete` | `delete_template` | MCP ok, CLI gap | ok |
| Duplicate | `POST /v1/templates/duplicate` | `template duplicate` | `duplicate_template` | gap (get + put under a new name) | ok |
| Rename | `POST /v1/templates/rename` | `template rename` | `rename_template` | gap | ok |
| Set / clear the app's default | `PUT /v1/templates/default` | `template default` | `set_default_template` | via `put_template setAsDefault` or `put_manifest`; clear gap | ok |
| Export a `.heraldtemplate` bundle | `GET /v1/templates/export` | `template export` | `export_template_bundle` | CLI ok (client side), MCP gap | ok |
| Import a bundle (keep both / replace / fail, retarget app) | `POST /v1/templates/import` | `template import` | `import_template_bundle` | CLI ok, MCP gap | ok |
| Validate a draft without saving | (client side) | none | `validate_template` | ok | ok |
| Component schema | `GET /v1/components` | none | `component_schema` | ok | ok |

## Designer: grid, cells, components, rules (all one template document)

| Capability | HTTP route | MCP tool | Before | After |
|---|---|---|---|---|
| Rows, columns, track sizes (auto / fill / points / fr), padding, gap | `PUT /v1/templates` | `put_template` | via `put_template` | ok |
| Insert / remove row or column | `PUT /v1/templates` | `put_template` | via `put_template` | ok |
| Place, move, resize, duplicate, remove a cell | `PUT /v1/templates` | `put_template` | via `put_template` | ok |
| Merge / split cells (row span, column span) | `PUT /v1/templates` | `put_template` | via `put_template` | ok |
| Add a component of every type and set every property, symbols included (`symbol`, `symbolEffect`, rendering, colors) | `PUT /v1/templates` | `put_template` (+ `list_symbols` to choose names) | property edits via `put_template`; symbol names gap | ok |
| Bind a field to a cell (`{token}`), empty behaviour, collapse | `PUT /v1/templates` | `put_template` | via `put_template` | ok |
| Action rules (add / hide / order / override), button actions, `actions.*`, `button.*` | `PUT /v1/templates` | `put_template`, `add_action_rule` | ok | ok |
| Template-level look: accent, sound, extra | `PUT /v1/templates` | `put_template` | ok | ok |
| Select a cell, undo, redo, zoom, split position, drag and drop, hover | none | none | UI | UI |

The Designer's editing verbs are helpers that rewrite the template; the saved result is a template document, and
`put_template` accepts any document the Designer can produce. Validation is the same code on both sides.

## Designer: manifests and assets

| Capability | HTTP route | CLI | MCP tool | Before | After |
|---|---|---|---|---|---|
| List / get / save a manifest | `GET /v1/manifests`, `GET`, `PUT /v1/manifest` | none | `list_manifests`, `get_manifest`, `put_manifest` | ok | ok |
| Delete a manifest | `DELETE /v1/manifest` | `manifest delete` | `delete_manifest` | HTTP ok, MCP gap | ok |
| List an app's animation and image files | `GET /v1/assets` | `assets list` | `list_assets` | gap | ok |
| Upload a Rive file or an image (base64 or a local path) | `POST /v1/assets` | `assets add` | `upload_asset` | gap | ok |
| Remove an uploaded file | `DELETE /v1/assets` | `assets rm` | `delete_asset` | gap | ok |
| Inspect a Rive file (artboards, state machines, inputs) | `POST /v1/rive/check` | none | `rive_check` | HTTP ok, MCP gap | ok |
| Installed Shortcuts | `GET /v1/shortcuts` | none | `list_shortcuts` | ok | ok |
| Scripts folder listing | (in `herald_status`) | none | `herald_status` | ok | ok |
| SF Symbol names and categories | `GET /v1/symbols` | `symbols` | `list_symbols` | gap | ok |

## Designer: preview and send

| Capability | HTTP route | CLI | MCP tool | Before | After |
|---|---|---|---|---|---|
| Preview light / dark, scale, sample data | `POST /v1/preview` | none | `render_preview` | ok | ok |
| Preview with the last delivered notification (`"last"`) | `POST /v1/preview` with `data:"last"` | none | `render_preview` `data:"last"` | gap | ok |
| Preview stack and confirmation states | `POST /v1/preview` | none | `render_preview` | ok | ok |
| Whole-Designer snapshot (layout check) | `POST /v1/designer/snapshot` | none | `designer_snapshot` | HTTP ok, MCP gap | ok |
| Send test (real banner from a template) | `POST /v1/notify` | `notify --template` | `send_test` | ok | ok |
| Open the Designer window | none | none | none | UI (a window; never opened by the API) | UI |

## Quick send (Composer)

| Capability | HTTP route | CLI | MCP tool | Before | After |
|---|---|---|---|---|---|
| Send a notification with every field | `POST /v1/notify` | `notify` | `send_notification` | ok | ok |
| Say text aloud | `POST /v1/speak` | `speak` | `speak` | ok | ok |
| Register an app | `POST /v1/register` | `register` | `register_app` | MCP gap | ok |
| Copy as curl / Swift / Python / Node / CLI | none | none | none | UI (the generated text is derived from the payload) | UI |
| Open the Composer window | `POST /v1/compose` | `compose` | none | UI by design | UI |

## History and banners

| Capability | HTTP route | CLI | MCP tool | Before | After |
|---|---|---|---|---|---|
| List an app's history | `GET /v1/history` | `history` | `list_history` | ok | ok |
| Search (all words, any app, diacritics folded) | `GET /v1/history/search` | `history search` | `history_search` | gap | ok |
| Re-show as a banner | `POST /v1/history/reshow` | `history reshow` | `reshow_notification` | gap | ok |
| Delete one item | `DELETE /v1/history/item` | `history delete` | `delete_history` | gap | ok |
| Clear an app or everything | `DELETE /v1/history` | `history --clear` | `delete_history` (`all`) | HTTP ok, MCP gap | ok |
| Export JSON | `GET /v1/history/export` | `history export` | `export_history` | gap | ok |
| Dismiss a banner / an app / a stack | `POST /v1/dismiss`, `/v1/dismissAll` | `dismiss`, `dismiss-all` | `dismiss` | ok | ok |
| Snooze / unsnooze | `POST /v1/snooze`, `/v1/unsnooze` | `snooze`, `unsnooze` | `snooze` | MCP gap | ok |
| List stacks, open or close one | `GET /v1/stacks`, `POST /v1/stacks/expand` | `stacks` | `list_stacks`, `expand_stack` | list ok, expand gap | ok |
| Mark a notification as opened (banner click) | none | none | none | by design (it acts as a click) | by design |

## Settings

| Capability | HTTP route | CLI | MCP tool | Before | After |
|---|---|---|---|---|---|
| General: port, launch at login, mute all sounds, global stacking | `GET`, `PUT /v1/settings` | `settings get`, `settings set` | `get_settings`, `set_settings` | stacking only | ok |
| History cap (keep per app) | `PUT /v1/settings` | `settings set` | `set_settings` | gap | ok |
| Voice: engine, default voice, speed, language, system voice | `PUT /v1/settings` | `settings set` | `set_settings` | gap | ok |
| Quiet hours (windows, ad-hoc silence, resume) | `GET`, `PUT /v1/settings/quiet-hours` | `quiet` | `get_quiet_hours`, `set_quiet_hours` | ok | ok |
| Kokoro install state; install, cancel, use `~/.claude/tts` | `GET /v1/voice`, `POST /v1/voice/install` | `voice` | `voice_status`, `install_voice` | gap | ok |
| Choices for the above (sounds, displays, voices, engines, corners) | `GET /v1/settings` (`options`) | `settings get` | `get_settings` | gap | ok |
| Per app: sound, stay until dismissed, timeout, corner, display, mute banners, stacking override | `GET`, `PUT /v1/apps/settings` | `apps settings` | `list_apps`, `update_app_settings` | gap | ok |
| Per app: speak on/off, voice, urgent breaks quiet hours | `PUT /v1/apps/settings` | `apps settings` | `update_app_settings` | gap | ok |
| Per app: name, icon, bundle id, callback URL, allow-commands request | `POST /v1/register` | `register` | `register_app` | MCP gap | ok |
| Per app: callback host and command approvals, read | `GET /v1/apps/settings` | `apps settings` | `list_apps` | gap | ok |
| Per app: revoke command or callback approval | `PUT /v1/apps/settings` | `apps settings` | `update_app_settings` | gap | ok |
| Per app: grant command or callback approval | none | none | none | by design | by design |
| Template commands, scripts and Shortcuts: list and revoke approvals | `GET`, `DELETE /v1/actions/approvals` | `approvals` | `list_approvals`, `revoke_approval` | gap | ok |
| Template commands: grant approval | none | none | none | by design | by design |
| Install `herald-mcp` into Claude Code, Codex, Claude Desktop; the `herald` CLI | `GET`, `POST /v1/mcp` | `mcp` | `install_mcp` | gap | ok |
| Reveal token file / scripts folder / log in Finder, test sound | none | none | none | UI (opens Finder or plays on the speakers) | UI |
| Tooltips level, activation policy | `PUT /v1/settings` | `settings set` | `set_settings` | not landed at the time of the audit | see the note below |

Settings keys are validated against one table (`SettingsSchema`); an unknown key, a wrong type or an out-of-range
value is `400` and nothing is changed. `GET /v1/settings` returns the same table as `schema`, so an agent can
discover the keys.

## Left out on purpose

- **Granting approvals** (an app's permission to run `command` buttons, approval of a non-loopback callback host,
  a template's command, script or Shortcut). These are the user's confirmation gate: the token holder is the
  program being gated, so it must not approve itself. Reading and revoking are exposed.
- **Pressing a banner button** and **opening a banner as a click** (documented in [mcp-tools.md](mcp-tools.md)).
- **Windows**: opening Designer, Composer, History or Settings. The API never activates or focuses a window; the
  offscreen preview and snapshot routes cover what a person would look at.
