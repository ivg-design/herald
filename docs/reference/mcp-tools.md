# MCP server: tools, resources, arguments

`herald-mcp` is a stdio MCP server (newline-delimited JSON-RPC 2.0; protocol version 2025-06-18, with 2025-03-26
and 2024-11-05 also accepted) that lets an agent design Herald templates, look at the result, add buttons and
show a real test banner. It works through Herald's loopback API, so Herald.app must be running for everything
except `component_schema` and `validate_template`. This page lists every tool and its arguments, from the tool
definitions. Installation, configuration and a worked session are in [../MCP.md](../MCP.md).

It never presses a banner button and never runs an action. Template-authored commands, scripts and Shortcuts
still ask the user for confirmation in Herald ([actions.md](actions.md#confirmation-gates)).

## Conventions

- Results are JSON text. A tool that cannot do what was asked returns a result with `isError: true` and an
  explanation, never a protocol error, so the agent can read it and try again. Only an unknown tool name is a
  JSON-RPC error (`-32602`).
- Arguments given as strings (`"5"`, `"true"`) and an object given as a JSON string are accepted.
- Validation issues are objects `{severity, path, cellId?, message}`.
- Each tool carries MCP annotations (`readOnlyHint`, `destructiveHint`, `idempotentHint`) so a client can ask
  before a destructive call.

| Server option | Environment | Meaning |
|---|---|---|
| `--support-dir DIR` | `HERALD_SUPPORT_DIR` | Folder with the `token` and `port` files. |
| `--port N` | `HERALD_PORT` | Port to use. |
| `--token T` | `HERALD_TOKEN` | Token (prefer the environment variable). |
| `--preview-dir DIR` | `HERALD_PREVIEW_DIR` | Where `render_preview` saves PNGs (default `$TMPDIR/herald-previews`, newest 40 kept). |
| `--debug` | `HERALD_MCP_DEBUG=1` | Log each request to stderr. |

## Tool index

| Tool | Kind | Needs Herald |
|---|---|---|
| [`herald_status`](#herald_status) | read | no (reports it is down) |
| [`list_manifests`](#list_manifests), [`get_manifest`](#get_manifest) | read | yes |
| [`put_manifest`](#put_manifest) | write | yes |
| [`list_templates`](#list_templates), [`get_template`](#get_template) | read | yes |
| [`put_template`](#put_template), [`delete_template`](#delete_template), [`add_action_rule`](#add_action_rule) | write | yes |
| [`validate_template`](#validate_template), [`component_schema`](#component_schema) | read | no |
| [`render_preview`](#render_preview) | read | yes |
| [`send_notification`](#send_notification), [`send_test`](#send_test), [`speak`](#speak) | deliver | yes |
| [`list_shortcuts`](#list_shortcuts), [`list_history`](#list_history), [`list_stacks`](#list_stacks) | read | yes |
| [`dismiss`](#dismiss) | write | yes |
| [`get_quiet_hours`](#get_quiet_hours), [`set_quiet_hours`](#set_quiet_hours) | read / write | yes |
| [`get_settings`, `set_settings`](#settings-and-apps) | read / write | yes |
| [`list_apps`, `update_app_settings`, `register_app`](#settings-and-apps) | read / write | yes |
| [`voice_status`, `install_voice`, `install_mcp`](#settings-and-apps) | read / write | yes |
| [`list_approvals`, `revoke_approval`](#settings-and-apps) | read / write | yes |
| [`duplicate_template`, `rename_template`, `set_default_template`](#templates-assets-and-symbols) | write | yes |
| [`export_template_bundle`, `import_template_bundle`, `delete_manifest`](#templates-assets-and-symbols) | write | yes |
| [`list_assets`, `upload_asset`, `delete_asset`, `list_symbols`, `rive_check`](#templates-assets-and-symbols) | read / write | yes |
| [`history_search`, `reshow_notification`, `delete_history`, `export_history`](#history-and-banners) | read / write | yes |
| [`snooze`, `expand_stack`, `designer_snapshot`](#history-and-banners) | write / read | yes |

## herald_status

No arguments. Call it first. Returns whether Herald is running, its version and pid, the port and support
directory in use, counts of apps, manifests, templates and installed Shortcuts, and the scripts folder with the
script files in it. Never fails: when Herald is down it says so and how to start it.

## list_manifests

No arguments. A summary per app: fields as `key:type` (`!` marks required), action ids, assets, `defaultTemplate`.

## get_manifest

| Argument | Type | Required | Meaning |
|---|---|---|---|
| `app` | string | yes | The app id, e.g. `webwatcher.email`. |
| `full` | boolean | no | Return long strings in full. Strings over 1200 characters (an embedded icon, a long sample) are otherwise abbreviated to a marker such as `<data:image/png;base64,... 5022 characters omitted>`. |

Also readable as the resource `herald://manifests/<app>` (always abbreviated).

## put_manifest

| Argument | Type | Required | Meaning |
|---|---|---|---|
| `manifest` | object | yes | The whole manifest ([manifests.md](manifests.md)): `{app, appName?, icon?, version?, fields, actions, assets?, defaultTemplate?, family?}`. |

Creates or **replaces** (get it first, edit, send it back). An abbreviation marker that `get_manifest` wrote is
swapped back for the stored value; a marker that matches nothing stored is refused (use `get_manifest` with
`full: true`). Issuer actions are `url`, `callback`, `command` or `dismiss`. Invalid manifests are rejected with
the field path. Rive assets are copied into Herald's assets folder.

## list_templates

| Argument | Type | Required | Meaning |
|---|---|---|---|
| `app` | string | no | Only this app. Omit for all. |

A summary each: app, name, `layoutVersion`, cell count, the `{tokens}` it reads, rule count, whether it is the
app's default. The four built-in templates always exist.

## get_template

| Argument | Type | Required | Meaning |
|---|---|---|---|
| `app` | string | yes | |
| `name` | string | yes | A template name, or `builtin.imageLeft`, `builtin.imageRight`, `builtin.hero`, `builtin.compact` (generated for the app, as starting points). |

Also readable as `herald://templates/<app>/<name>`.

## put_template

| Argument | Type | Required | Meaning |
|---|---|---|---|
| `template` | object | yes | `{name, app, layoutVersion: 2, grid, cells, collapseEmpty?, actionRules?, extra?, accentColor?, sound?, ...}` ([grid-and-layout.md](grid-and-layout.md)). |
| `app` | string | no | Only needed when the template object has no `app`. |
| `setAsDefault` | boolean | no | Also set the manifest's `defaultTemplate` to this template (the app needs a manifest). |

Validates against the grid schema first. Errors carry the JSON path and the id of the offending cell, and nothing
is saved until there are none (overlapping cells, a cell outside the grid, an unknown component type or a
property of the wrong type, a bad colour...). Warnings (an undeclared `{token}`, an unknown key that is probably a
typo such as `colspan`) are returned but do not block. Names starting with `builtin.` are reserved. On success:
`{saved, app, name, cells, isDefault, warnings, next}`; on failure `{error, errors, warnings, saved:false}`.

## delete_template

| Argument | Type | Required |
|---|---|---|
| `app` | string | yes |
| `name` | string | yes |

Built-ins cannot be deleted. Notifications that name a deleted template fall back to the default look.

## validate_template

| Argument | Type | Required | Meaning |
|---|---|---|---|
| `template` | object | one of | A draft template. |
| `app` + `name` | strings | one of | A saved (or `builtin.*`) template; `app` also checks tokens against its manifest. |

Returns `valid`, `errors` and `warnings` and, with the app's manifest sample data, which cells would be empty,
which rows and columns would collapse, and the resulting action list. Works without Herald running (the
manifest check is then skipped).

## component_schema

| Argument | Type | Required | Meaning |
|---|---|---|---|
| `component` | string | no | One of `text`, `image`, `issuerIcon`, `timestamp`, `button`, `actions`, `iconButton`, `badge`, `stackBadge`, `progress`, `rive`, `spacer`: only that component's schema plus the shared definitions. |
| `section` | string | no | One of `definitions`, `components`, `bindings`, `actions`, `examples`, `workflow`. |

The format of a template for authoring: grid, every component type with each property, allowed values and
default, bindings and empty-collapsing, action kinds and rules, symbol styling, complete examples. Read it before
writing a template. Also the resource `herald://docs/components` (a short guide).

## render_preview

| Argument | Type | Required | Meaning |
|---|---|---|---|
| `name` | string | one of | A saved template's name, or `builtin.*`. Needs `app`. |
| `template` | object | one of | An unsaved draft (validated first; errors name the cell). |
| `app` | string | with `name` | Defaults to the draft's app. |
| `source` | `sample` or `last` | no | `sample` (default): the manifest's samples. `last`: the app's most recent notification in history. |
| `data` | object | no | Field values that replace the source's, e.g. `{"count":12,"subject":"A very long subject line"}`. Omit a key to see the collapse. |
| `appearance` | `light` or `dark` | no | Default `light`. |
| `scale` | number 1 to 3 | no | Default 2. |

With neither `name` nor `template`, the app's default template is rendered. Returns an **image content block**
(PNG) plus a text block with the saved file path, pixel size and `data` provenance. Sample data stands in for an
issuer that names every action its manifest declares; a real notification shows only the actions it sends.
Rive components are drawn as placeholders and symbol effects are not drawn. Render light and dark to check
both.

## send_notification

Delivers a real notification: a banner appears and it is recorded in history. Same payload as
`POST /v1/notify` ([api.md](api.md#post-v1notify)).

| Argument | Type | Required | Meaning |
|---|---|---|---|
| `app` | string | yes | The sending app id. |
| `title` | string | no | May be omitted when `template` supplies it. |
| `subtitle`, `body` | string | no | `body` takes `[text](https://...)` links. |
| `id` | string | no | The same id again replaces the banner. |
| `template` | string | no | A saved template of this app. |
| `fields` | object | no | Manifest field values, sent as top-level keys. |
| `buttons` | array | no | `[{label, style?, url?\|command?\|callback?}]`; `actions` is an alias. |
| `actionIds` | array of string | no | Ids of actions the manifest declares. |
| `allowCommandButtons` | boolean | no | Allow buttons that carry a shell `command` (**refused by default**: you can send as any app id, so a command button would run under that app's command permission). |
| `metadata` | object | no | Free-form; readable as `{key}` too. |
| `speak` | `true` or object | no | `{text?, voice?, speed?, lang?}`. |
| `audio` | string | no | A WAV/MP3/M4A path, https URL or `data:` URI (at most 20 MB). |
| `presentation` | `banner`, `voice`, `both` | no | Default `banner`. |
| any other key | | | Passed through as a notification field (`additionalProperties` is allowed). |

Prefer `send_test` while iterating on a template.

## send_test

| Argument | Type | Required | Meaning |
|---|---|---|---|
| `app` | string | yes | |
| `template` | string | no | A **saved** template (defaults to the manifest's `defaultTemplate`). |
| `data` | object | no | Replaces manifest samples. |
| `id` | string | no | Default `mcp-test-<template>` so repeating replaces the banner. |
| `includeIssuerActions` | boolean | no | Send the manifest's actions as the issuer's buttons (default true), so rules have something to act on. |
| `allowCommandButtons` | boolean | no | Also send manifest actions that run a shell command (left out by default). |

Pressing an issuer callback button calls the issuing app, so tell the user before they click.

## list_shortcuts

No arguments. The names of the installed Apple Shortcuts, for `add_action_rule` actions of kind `shortcut`.

## add_action_rule

| Argument | Type | Required | Meaning |
|---|---|---|---|
| `app` | string | yes | |
| `template` | string | yes | A saved template (built-ins are read-only: copy one with `put_template` first). |
| `rule` | object | yes | `{match?, hide?, relabel?, style?: normal\|prominent\|destructive\|cancel, symbol?: <name or object>, position?, add?: {id, label, kind, url?\|command?\|script?\|shortcut?, input?, snoozeMinutes?, style?, symbol?}}`. |

Appends one rule to `actionRules` ([actions.md](actions.md#rules-actionrules)). A rule changes an issuer action
(`match` by id, label or `*`) or adds one of your own. `script` actions run a file in the scripts folder, which
`herald_status` lists: write the file there first (the tool warns when it is missing). A command, script or
shortcut you add is confirmed by the user in Herald the first time its button is pressed, and again whenever it
changes. Adding an action id that an earlier add-rule already has replaces that rule. Validated before saving;
returns `{saved, ruleIndex, warnings, resultingActions}`.

## list_history

| Argument | Type | Meaning |
|---|---|---|
| `app` | string | Only this app. |
| `limit` | integer 1 to 100 | Default 10. |
| `full` | boolean | Complete records instead of the summary. |

## dismiss

| Argument | Type | Required | Meaning |
|---|---|---|---|
| `app` | string | yes | |
| `id` | string | one of | The notification id. |
| `group` | string | one of | Every banner of the app sent with this group (a stack). |
| `all` | boolean | one of | Every banner of the app. |

Only closes the banner; the history keeps the notification.

## list_stacks

| Argument | Type | Meaning |
|---|---|---|
| `app` | string | Only stacks that hold a notification of this app. |

## speak

| Argument | Type | Required | Meaning |
|---|---|---|---|
| `app` | string | yes | |
| `text` | string | yes | At most 2000 characters; a sentence or two. |
| `voice` | string | no | e.g. `af_heart` (default), `af_bella`, `am_michael`, `bf_emma`. |
| `speed` | number 0.5 to 2.0 | no | Default 1.0. |
| `lang` | string | no | e.g. `en-us`, `en-gb`. |
| `id` | string | no | Notification id for the history entry. |

Local voice, no banner; the history keeps the text. Held back by quiet hours.

## get_quiet_hours

No arguments. The scheduled windows, any ad hoc silence, and `status` (what is silenced now and until when).

## set_quiet_hours

| Argument | Type | Meaning |
|---|---|---|
| `windows` | array | The **complete** schedule: `[{days?, start, end, speech?, sounds?, banners?, speakSummary?}]` ([quiet-hours.md](quiet-hours.md)). |
| `until` | string `HH:MM` | Silence until this clock time (next occurrence). |
| `minutes` | number 1 to 10080 | Silence for this long. |
| `banners` | boolean | With `until`/`minutes`: silence banners too (default false). |
| `resume` | boolean | End the current silence now. |

Tell the user before silencing them.

## Parity tools

Everything the Designer, History and Settings can do is also a tool ([parity.md](parity.md) lists each one
against its route). Every tool below is a thin wrapper over one HTTP route ([api.md](api.md)): the arguments become the
query or body, the reply is Herald's JSON, and a Herald error comes back as a readable tool error. A missing required
argument is a tool error before any request is made. Destructive tools carry `destructiveHint`.

### Settings and apps

| Tool | Arguments | Route | Notes |
|---|---|---|---|
| `get_settings` | none | `GET /v1/settings` | Values, `schema`, `options` (sounds, displays, voices, corners, levels). |
| `set_settings` | `settings` (object) | `PUT /v1/settings` | Keys: `port`, `launchAtLogin`, `muteAllSounds`, `stacking`, `historyCapPerApp`, `tooltipLevel`, `voiceEngine`, `voiceDefault`, `voiceSpeed`, `voiceLang`, `voiceSystem`. All or nothing. |
| `list_apps` | `app?` | `GET /v1/apps/settings` | Per-app settings, voice, approvals (read only) and the schema. |
| `update_app_settings` | `app`, `settings` | `PUT /v1/apps/settings` | `sound`, `persistent`, `timeout`, `corner`, `display`, `muteBanners`, `stacking`, `speak`, `voice`, `urgentBreaksQuiet`; `revokeCommands: true`, `revokeCallbackHost: true`. Granting an approval is refused (403). |
| `register_app` | `app`, `appName?`, `icon?`, `bundleId?`, `callbackURL?`, `allowCommands?`, `defaults?` | `POST /v1/register` | `allowCommands` is only a request; the user confirms it in Settings. |
| `voice_status` | none | `GET /v1/voice` | Engine, Kokoro installed or missing, progress, voices. |
| `install_voice` | `action`: `install`, `cancel`, `useExisting` | `POST /v1/voice/install` | `install` downloads about 340 MB: ask first. |
| `install_mcp` | `client?`, `reinstall?` | `GET /v1/mcp`, `POST /v1/mcp/install` | Without `client`: status. Edits another application's configuration. |
| `list_approvals` | none | `GET /v1/actions/approvals` | Template commands, scripts and Shortcuts the user approved. |
| `revoke_approval` | `app`, `template` | `DELETE /v1/actions/approvals` | Destructive. There is no tool that grants one. |

### Templates, assets and symbols

| Tool | Arguments | Route | Notes |
|---|---|---|---|
| `duplicate_template` | `app`, `name`, `newName?`, `toApp?` | `POST /v1/templates/duplicate` | `name` may be `builtin.*`. |
| `rename_template` | `app`, `name`, `newName` | `POST /v1/templates/rename` | Destructive: the default template follows, approvals reset. |
| `set_default_template` | `app`, `name?` | `PUT /v1/templates/default` | Omit `name` to clear. Needs a manifest. |
| `export_template_bundle` | `app`, `name`, `path?` | `GET /v1/templates/export` | `path` ends in `.heraldtemplate`; without it, base64. |
| `import_template_bundle` | `path` or `base64`, `app?`, `onConflict?` | `POST /v1/templates/import` | `keepBoth` (default), `replace`, `fail`. Destructive (replace). |
| `delete_manifest` | `app` | `DELETE /v1/manifest` | Destructive; templates stay. |
| `list_assets` | `app` | `GET /v1/assets` | Rive files and images, with `usedBy` and the component snippet. |
| `upload_asset` | `app`, `path` or `base64` (+ `name`), `kind?` | `POST /v1/assets` | Rive at most 10 MB; images checked by their bytes. Same name replaces. |
| `delete_asset` | `app`, `file` | `DELETE /v1/assets` | Destructive; the reply lists templates left with a placeholder. |
| `list_symbols` | `q?`, `category?`, `limit?`, `offset?` | `GET /v1/symbols` | Names and categories for a component's `symbol`. |
| `rive_check` | `app`, `component`, `fields?`, `simulate?` | `POST /v1/rive/check` | Load a `rive` component without a window ([rive.md](rive.md#testing-without-a-window)). |

### History and banners

| Tool | Arguments | Route | Notes |
|---|---|---|---|
| `history_search` | `q`, `app?`, `limit?` | `GET /v1/history/search` | Every word must match; newest first. |
| `reshow_notification` | `app`, `id` | `POST /v1/history/reshow` | A new banner with sound. |
| `delete_history` | `app`, `id`; or `all: true` (+ `app?`) | `DELETE /v1/history/item`, `DELETE /v1/history` | Destructive; cannot be undone. |
| `export_history` | `app?`, `path?` | `GET /v1/history/export` | `path` (`.json`): Herald writes the file. |
| `snooze` | `app`, `id`, `minutes` or `cancel: true` | `POST /v1/snooze`, `/v1/unsnooze` | |
| `expand_stack` | `app`, `group?`, `expanded?` | `POST /v1/stacks/expand` | |
| `designer_snapshot` | `app?`, `template?`, `select?`, `width?`, `height?` | `POST /v1/designer/snapshot` | Returns an image of the Designer drawn offscreen. No window opens. |

## Resources

| URI | Content |
|---|---|
| `herald://manifests/<app>` | The app's manifest (JSON, abbreviated). |
| `herald://templates/<app>/<name>` | A template (JSON); `builtin.*` names work. Path parts are percent-encoded (`Bid%20won`). |
| `herald://docs/components` | A short Markdown guide to the template format; `component_schema` has every property. |

`resources/list` shows the guide always, and the manifests and templates when Herald answers;
`resources/templates/list` returns the two URI templates. There are no prompts.

## A typical session

1. `herald_status`, then `get_manifest` for the app.
2. `component_schema` once.
3. Draft with `put_template`; fix what the errors say; `render_preview` in light and dark with `data` that makes
   a subject very long or leaves a field out.
4. `list_shortcuts` and `add_action_rule` for buttons of your own.
5. `put_template` with `setAsDefault: true`.
6. `send_test` to see the real banner.
