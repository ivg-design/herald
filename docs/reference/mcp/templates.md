# MCP tools: manifests, templates and assets

These tools let an agent design how an app's banners look and what their buttons do. A **manifest** says what an app sends (its fields and actions). A **template** says how a banner draws those fields on a grid of cells. **Assets** are the Rive animations and images a template can use. The tools read and write exactly what the Designer reads and writes, and they check a template with the same validation the Designer uses. This page is for an agent author, or for anyone who wants to know what an agent can change.

For the shared conventions (result format, errors, images) see the [MCP server overview](README.md#conventions). The format of a template itself is in [Grid and layout](../grid-and-layout.md), the components are in [Components](../components/README.md), and the action rules are in [Actions](../actions.md).

## How these tools fit together

The usual design session calls the tools in this order:

1. [`get_manifest`](#get_manifest) to see the fields the app sends. Each field key is a `{token}` a template can bind.
2. [`component_schema`](#component_schema) once, to learn the grid and the components.
3. [`put_template`](#put_template) to save a draft. Errors name the JSON path and the cell id, and nothing is saved until there are none.
4. [`render_preview`](#render_preview) to look at the result, in light and dark, with long or missing values passed in `data`.
5. [`list_shortcuts`](#list_shortcuts) and [`add_action_rule`](#add_action_rule) for buttons of your own.
6. [`send_test`](notifications.md#send_test) to see the real banner on screen.

A worked example of this session is in [Connect an agent](../../MCP.md#a-worked-session).

## Tools

- Manifests
  - [`list_manifests`](#list_manifests)
  - [`get_manifest`](#get_manifest)
  - [`put_manifest`](#put_manifest)
  - [`delete_manifest`](#delete_manifest)
- The template format
  - [`component_schema`](#component_schema)
- Templates
  - [`list_templates`](#list_templates)
  - [`get_template`](#get_template)
  - [`put_template`](#put_template)
  - [`delete_template`](#delete_template)
  - [`duplicate_template`](#duplicate_template)
  - [`rename_template`](#rename_template)
  - [`set_default_template`](#set_default_template)
- Checking a design
  - [`validate_template`](#validate_template)
  - [`render_preview`](#render_preview)
  - [`designer_snapshot`](#designer_snapshot)
- Buttons
  - [`list_shortcuts`](#list_shortcuts)
  - [`add_action_rule`](#add_action_rule)
- Sharing
  - [`export_template_bundle`](#export_template_bundle)
  - [`import_template_bundle`](#import_template_bundle)
- Assets and symbols
  - [`list_assets`](#list_assets)
  - [`upload_asset`](#upload_asset)
  - [`delete_asset`](#delete_asset)
  - [`list_symbols`](#list_symbols)
  - [`rive_check`](#rive_check)

## Manifests

A manifest is registered by the app that sends notifications, or written by an agent for an app that does not. Its fields and actions are documented in [Manifests](../manifests.md). Agents installed from **Settings > MCP** get a manifest automatically; see [Agent identity](README.md#agent-identity).

### `list_manifests`

Lists the manifests the issuing apps registered. A manifest declares the fields an app sends and the actions (buttons) it offers. The result has one summary per app. Use [`get_manifest`](#get_manifest) for sample values.

**Arguments**

No arguments.

**Example call**

```json
{}
```

**Example result**

```json
{
  "count": 1,
  "manifests": [
    {
      "app": "example.bidbot",
      "appName": "BidBot",
      "version": 1,
      "fields": ["title:text!", "item:text", "bids:number"],
      "actions": ["view", "withdraw"],
      "assets": [],
      "defaultTemplate": "bid-won"
    }
  ],
  "note": "A trailing ! marks a required field. get_manifest shows sample values."
}
```

Each field is written `key:type`, with a trailing `!` when the field is required.

**HTTP route**

[`GET /v1/manifests`](../api/manifests.md#get-v1manifests).

**Side effects**

None. Read-only.

### `get_manifest`

Returns one app's whole manifest: the fields (type, required flag and sample value), the issuer's actions with their ids, the assets and the default template.

- The field keys are the `{tokens}` a template binds.
- The samples are what `render_preview` and `send_test` show.
- The manifest is also readable as the resource `herald://manifests/<app>`, always shortened.

Strings over 1,200 characters, such as an embedded icon or a long sample, are shortened to a marker like `<data:image/png;base64,... 5022 characters omitted>`. Pass `full: true` to get the real values.

**Arguments**

| Name | Type | Required | Description |
|---|---|---|---|
| `app` | string | yes | The app id, such as `example.bidbot`. [`list_manifests`](#list_manifests) shows the registered ids. |
| `full` | boolean | no | Returns long strings in full instead of shortening them. Default `false`. |

**Example call**

```json
{"app": "example.bidbot"}
```

**Example result**

```json
{
  "app": "example.bidbot",
  "appName": "BidBot",
  "version": 1,
  "fields": [
    {"key": "title", "type": "text", "required": true, "sample": "Bid accepted"},
    {"key": "item", "type": "text", "sample": "Oak desk, 1920"},
    {"key": "bids", "type": "number", "sample": 3}
  ],
  "actions": [
    {"id": "view", "label": "View", "kind": "url", "url": "https://example.com/bids"},
    {"id": "withdraw", "label": "Withdraw", "kind": "callback", "style": "destructive"}
  ],
  "assets": [],
  "defaultTemplate": "bid-won"
}
```

When the app has no manifest the tool fails and lists the apps that do.

**HTTP route**

[`GET /v1/manifest`](../api/manifests.md#get-v1manifest).

**Side effects**

None. Read-only.

### `put_manifest`

Creates a manifest or replaces the whole one. Read it with `get_manifest`, edit it and send it back. Apps normally register their own manifest. Use this to describe an app that does not, to add sample values for the Designer, or to set `defaultTemplate`.

Rules for what you send:

- A shortened marker that `get_manifest` wrote is swapped back for the stored value. A marker that matches nothing stored is refused: read the manifest again with `full: true`.
- An issuer action is one of the kinds `url`, `callback`, `command`, `openApp`, `reply` or `dismiss`. Each kind is described in [Actions](../actions.md#action-kinds). Shortcut, script and snooze actions are authored in templates with [`add_action_rule`](#add_action_rule).
- An invalid manifest is rejected with the path of the field.
- Rive files named in `assets` are copied into Herald's assets folder.

**Arguments**

| Name | Type | Required | Description |
|---|---|---|---|
| `manifest` | object | yes | The whole manifest. `app` is required. The other fields are in [Manifests](../manifests.md). |

**Example call**

```json
{
  "manifest": {
    "app": "example.bidbot",
    "appName": "BidBot",
    "fields": [
      {"key": "title", "type": "text", "required": true, "sample": "Bid accepted"},
      {"key": "bids", "type": "number", "sample": 3}
    ],
    "actions": [{"id": "view", "label": "View", "kind": "url", "url": "https://example.com/bids"}],
    "defaultTemplate": "bid-won"
  }
}
```

**Example result**

```json
{
  "saved": true,
  "app": "example.bidbot",
  "fields": 2,
  "actions": 1,
  "assets": 0,
  "defaultTemplate": "bid-won",
  "restoredAbbreviatedValues": 0
}
```

**HTTP route**

[`PUT /v1/manifest`](../api/manifests.md#put-v1manifest).

**Side effects**

Overwrites the app's manifest. Existing templates are kept.

### `delete_manifest`

Deletes an app's manifest and the copies of its Rive assets. Templates stay. The app's notifications then use the generic look until a manifest is registered again.

**Arguments**

| Name | Type | Required | Description |
|---|---|---|---|
| `app` | string | yes | The app id. |

**Example call**

```json
{"app": "example.bidbot"}
```

**Example result**

```json
{"ok": true}
```

**HTTP route**

[`DELETE /v1/manifest`](../api/manifests.md#delete-v1manifest).

**Side effects**

Deletes stored data. The tool carries the destructive hint, so a client can ask before it runs.

## The template format

### `component_schema`

Returns the format of a template, for authoring: the grid, every component type with each property, allowed values and default, how `{token}` bindings and empty collapsing work, the action kinds and rules, symbol styling, and complete examples. Read it before writing a template. The same format is documented for people in [Grid and layout](../grid-and-layout.md) and [Components](../components/README.md). It is also available as the short resource `herald://docs/components`.

The tool asks the running Herald for its own document and falls back to the one built into `herald-mcp`, so it works when Herald is down.

**Arguments**

| Name | Type | Required | Description |
|---|---|---|---|
| `component` | string | no | Returns only this component's schema plus the shared definitions it uses. A component name from the [component reference](../components/README.md). |
| `section` | string | no | Returns only this part of the document. One of `definitions`, `components`, `bindings`, `actions`, `examples`, `workflow`. |

**Example call**

```json
{"component": "badge"}
```

**Example result**

The result is a JSON document. A call with no arguments returns the whole document as text. An unknown name fails and lists the valid names. A narrowed call returns an object with these keys:

| Key | Meaning |
|---|---|
| `component` | The component name that was asked for. |
| `schema` | The JSON schema of that component. |
| `definitions` | The shared definitions the schema uses. |
| `source` | `herald` when the running app answered, or `herald-mcp (built in; ...)` when the server answered from its own copy. |

**HTTP route**

[`GET /v1/components`](../api/templates.md#get-v1components).

**Side effects**

None. Read-only.

## Templates

Four built-in templates exist for every app and are generated on request: `builtin.imageLeft`, `builtin.imageRight`, `builtin.hero` and `builtin.compact`. They are read-only starting points: copy one with [`duplicate_template`](#duplicate_template) or read it with [`get_template`](#get_template) and save it under another name.

### `list_templates`

Lists the saved templates of one app or of all apps, and the names of the built-ins. Each summary has the app, the name, the layout version, the cell count, the `{tokens}` the template reads, the number of action rules, and whether it is the app's default.

**Arguments**

| Name | Type | Required | Description |
|---|---|---|---|
| `app` | string | no | Only this app's templates. Default: all apps. |

**Example call**

```json
{"app": "example.bidbot"}
```

**Example result**

```json
{
  "count": 1,
  "templates": [
    {
      "app": "example.bidbot",
      "name": "bid-won",
      "layoutVersion": 2,
      "cells": 5,
      "tokens": ["bids", "item", "title"],
      "actionRules": 1,
      "collapseEmpty": true,
      "isDefault": true
    }
  ],
  "builtins": ["builtin.imageLeft", "builtin.imageRight", "builtin.hero", "builtin.compact"]
}
```

**HTTP route**

[`GET /v1/templates`](../api/templates.md#get-v1templates).

**Side effects**

None. Read-only.

### `get_template`

Returns the full JSON of one template, or of a built-in generated for the app. Edit it and save it back with [`put_template`](#put_template). It is also readable as the resource `herald://templates/<app>/<name>`; path parts are percent-encoded, so `Bid won` is `Bid%20won`.

**Arguments**

| Name | Type | Required | Description |
|---|---|---|---|
| `app` | string | yes | The app id. |
| `name` | string | yes | A template name, or `builtin.imageLeft`, `builtin.imageRight`, `builtin.hero` or `builtin.compact`. |

**Example call**

```json
{"app": "example.bidbot", "name": "builtin.compact"}
```

**Example result**

The result is the template as a JSON document, in the format described in [Grid and layout](../grid-and-layout.md). A name that does not exist fails and lists the saved and built-in names.

**HTTP route**

[`GET /v1/templates`](../api/templates.md#get-v1templates), filtered by name. Built-in templates are generated by the server.

**Side effects**

None. Read-only.

### `put_template`

Creates or overwrites a template. Herald validates it against the grid schema first. Errors carry the JSON path and the id of the cell at fault, and nothing is saved until there are none. Errors include overlapping cells, a cell outside the grid, an unknown component type, a property of the wrong type and a bad colour. Warnings are returned with the success and do not block: a `{token}` the manifest does not declare, or an unknown key that is probably a typo such as `colspan` for `colSpan`.

Names that start with `builtin.` are reserved. With `setAsDefault: true` the template also becomes the manifest's `defaultTemplate`; the app needs a manifest for that.

**Arguments**

| Name | Type | Required | Description |
|---|---|---|---|
| `template` | object | yes | The whole template object. Its fields are in [Grid and layout](../grid-and-layout.md). |
| `app` | string | no | The app id. Needed only when the template object has no `app`. It must match the template's own `app` when both are given. |
| `setAsDefault` | boolean | no | Also sets the manifest's `defaultTemplate` to this template. Default `false`. |

**Example call**

```json
{
  "template": {
    "name": "bid-won",
    "app": "example.bidbot",
    "layoutVersion": 2,
    "grid": {"rows": 3, "cols": 3, "rowSizes": ["auto", "auto", "auto"], "colSizes": [40, "fill", "auto"], "gap": 6, "padding": 12, "width": 380},
    "cells": [
      {"id": "icon", "row": 0, "col": 0, "rowSpan": 2, "component": {"type": "issuerIcon", "size": 32}},
      {"id": "title", "row": 0, "col": 1, "component": {"type": "text", "binding": "{title}", "style": "title", "maxLines": 2}},
      {"id": "bids", "row": 0, "col": 2, "component": {"type": "badge", "binding": "{bids}"}},
      {"id": "item", "row": 1, "col": 1, "colSpan": 2, "component": {"type": "text", "binding": "{item}", "maxLines": 3}},
      {"id": "actions", "row": 2, "col": 0, "colSpan": 3, "component": {"type": "actions", "source": "merged", "layout": "wrap"}}
    ]
  },
  "setAsDefault": true
}
```

**Example result**

```json
{
  "saved": true,
  "app": "example.bidbot",
  "name": "bid-won",
  "layoutVersion": 2,
  "cells": 5,
  "isDefault": true,
  "warnings": [],
  "notes": [],
  "next": "render_preview to look at it; send_test to see the real banner."
}
```

When validation fails the result has `isError` set and looks like this. Fix the cells it names and call again.

```json
{
  "ok": false,
  "error": "Template not saved: 1 error(s). Fix them and call again.",
  "saved": false,
  "errors": [{"severity": "error", "path": "cells[2]", "cellId": "bids", "message": "cell 'bids' overlaps cell 'title' at row 0, col 1"}],
  "warnings": []
}
```

The `notes` array explains what the tool could not do, such as ignoring `setAsDefault` for an app with no manifest.

**HTTP route**

- [`PUT /v1/templates`](../api/templates.md#put-v1templates) saves the template.
- [`PUT /v1/manifest`](../api/manifests.md#put-v1manifest) sets the default, only when `setAsDefault` is `true`.

**Side effects**

Saves a template, overwriting one of the same name. The user is asked again before a changed command, script or Shortcut runs.

### `delete_template`

Deletes a saved template. Built-in templates cannot be deleted. Notifications that name a deleted template use the default look. If the deleted template was the manifest's `defaultTemplate`, the result says so in `notes`.

**Arguments**

| Name | Type | Required | Description |
|---|---|---|---|
| `app` | string | yes | The app id. |
| `name` | string | yes | The template name. |

**Example call**

```json
{"app": "example.bidbot", "name": "bid-won"}
```

**Example result**

```json
{
  "deleted": true,
  "app": "example.bidbot",
  "name": "bid-won",
  "notes": ["'bid-won' is still the manifest's defaultTemplate; put_manifest to change it."]
}
```

**HTTP route**

[`DELETE /v1/templates`](../api/templates.md#delete-v1templates).

**Side effects**

Deletes stored data. The tool carries the destructive hint.

### `duplicate_template`

Copies a saved template, or a `builtin.*` layout, under a new name, optionally for another app. It is the Designer's Duplicate. Without `newName` the copy is called `<name> copy`, numbered when that name is taken.

**Arguments**

| Name | Type | Required | Description |
|---|---|---|---|
| `app` | string | yes | The app the template belongs to. |
| `name` | string | yes | The template to copy: a saved name or `builtin.*`. |
| `newName` | string | no | The name of the copy. It must not start with `.`, `_` or `builtin.`, and must not contain `/` or `:`. |
| `toApp` | string | no | Creates the copy for this app instead. |

**Example call**

```json
{"app": "example.bidbot", "name": "builtin.hero", "newName": "bid-lost"}
```

**Example result**

```json
{"ok": true, "app": "example.bidbot", "name": "bid-lost", "copiedFrom": {"app": "example.bidbot", "name": "builtin.hero"}}
```

**HTTP route**

[`POST /v1/templates/duplicate`](../api/templates.md#post-v1templatesduplicate).

**Side effects**

Saves a new template. Changes no existing one.

### `rename_template`

Renames a saved template. The app's default template follows the new name. Command, script and Shortcut approvals belong to the old name, so the user is asked again the first time those buttons run. Built-in templates cannot be renamed; duplicate them instead.

**Arguments**

| Name | Type | Required | Description |
|---|---|---|---|
| `app` | string | yes | The app id. |
| `name` | string | yes | The current name. |
| `newName` | string | yes | The new name. |

**Example call**

```json
{"app": "example.bidbot", "name": "bid-won", "newName": "bid-accepted"}
```

**Example result**

```json
{
  "ok": true,
  "app": "example.bidbot",
  "name": "bid-accepted",
  "renamedFrom": "bid-won",
  "isDefault": true,
  "note": "Command, script and Shortcut approvals belong to the old name; the user is asked again the first time they run."
}
```

**HTTP route**

[`POST /v1/templates/rename`](../api/templates.md#post-v1templatesrename).

**Side effects**

Renames stored data and resets the user's approvals for the template. The tool carries the destructive hint.

### `set_default_template`

Makes a template the app's default: the one used by notifications that name no template. This sets the manifest's `defaultTemplate`, so the app needs a manifest. Omit `name` to clear the default.

**Arguments**

| Name | Type | Required | Description |
|---|---|---|---|
| `app` | string | yes | The app id. |
| `name` | string | no | The template name, saved or `builtin.*`. Omit it to clear the default. |

**Example call**

```json
{"app": "example.bidbot", "name": "bid-won"}
```

**Example result**

```json
{"ok": true, "app": "example.bidbot", "defaultTemplate": "bid-won"}
```

**HTTP route**

[`PUT /v1/templates/default`](../api/templates.md#put-v1templatesdefault).

**Side effects**

Changes the manifest's `defaultTemplate`.

## Check a design

Three tools let an agent see a design without leaving a banner behind. `validate_template` checks the structure. `render_preview` draws the banner. `designer_snapshot` draws the editor.

### `validate_template`

Checks a template without saving it. Give a draft as `template`, or a saved one as `app` and `name`.

- The result lists errors and warnings, each with a path and the cell id.
- When a manifest is available it also reports, for the manifest's sample data, which cells are empty, which rows and columns collapse, and the resulting button list.
- It works without Herald running. The manifest check is then skipped and the result says so in `note`.

**Arguments**

| Name | Type | Required | Description |
|---|---|---|---|
| `template` | object | no | A draft template object. Omit it when you use `app` and `name`. |
| `app` | string | no | The app id. Tokens are checked against its manifest. Required with `name`. |
| `name` | string | no | A saved template, or `builtin.*`, to validate instead of a draft. |

One of `template` or `name` is needed.

**Example call**

```json
{"app": "example.bidbot", "name": "bid-won"}
```

**Example result**

```json
{
  "valid": true,
  "errors": [],
  "warnings": [],
  "manifestChecked": true,
  "tokens": ["bids", "item", "title"],
  "withSampleData": {
    "emptyCells": [],
    "collapsedCells": [],
    "collapsedRows": [],
    "collapsedCols": [],
    "actions": [
      {"id": "view", "label": "View", "kind": "url", "origin": "issuer"},
      {"id": "withdraw", "label": "Withdraw", "kind": "callback", "style": "destructive", "origin": "issuer"}
    ]
  }
}
```

Each issue has the keys listed under [Validation issues](README.md#conventions). `cellId` is present when the problem is inside a cell.

**HTTP route**

None for the check itself: the tool validates locally. When it needs data it reads:

- the manifest, with [`GET /v1/manifest`](../api/manifests.md#get-v1manifest);
- a saved template, with [`GET /v1/templates`](../api/templates.md#get-v1templates).

**Side effects**

None. Read-only.

### `render_preview`

Draws a template offscreen with Herald's real banner renderer and returns the picture. The result has two parts: an image block (a PNG) and a text block with the saved file path and the pixel size. Preview a saved template with `name` (or `builtin.*`), an unsaved draft with `template` (validated first; errors name the cell), or neither, which draws the app's default template.

What the picture is drawn from:

- The data is the manifest's sample values by default, or the app's latest real notification with `source: "last"`.
- `data` overrides single fields. Pass a very long value to see how text wraps, and leave a key out to see how its cell collapses.
- Sample data stands in for an issuer that names every action its manifest declares, so the buttons shown are all of those. A real notification shows only the actions it sends.
- Rive components are drawn as placeholders and symbol effects are not drawn.
- Render light and dark to check both.

**Arguments**

| Name | Type | Required | Description |
|---|---|---|---|
| `name` | string | no | A saved template's name, or `builtin.*`. Needs `app`. |
| `template` | object | no | An unsaved draft template, instead of `name`. |
| `app` | string | no | The app id. Defaults to the draft's own `app`. Required with `name` or with neither argument. |
| `source` | string | no | `sample` (default) uses the manifest's samples. `last` uses the app's most recent notification in History. |
| `data` | object | no | Field values that override the source's, such as `{"bids": 12, "item": "A very long item name"}`. |
| `appearance` | string | no | `light` (default) or `dark`. |
| `scale` | number | no | The pixel scale, from 1 to 3. Default 2. |

**Example call**

```json
{"app": "example.bidbot", "name": "bid-won", "appearance": "dark", "data": {"bids": 14, "item": "Oak desk with three drawers, restored in 1962"}}
```

**Example result**

The first content block is the image, a PNG of the banner. The second is text:

```json
{
  "path": "/var/folders/xy/T/herald-previews/preview-example.bidbot-bid-won-dark-20261004-150210-E3BC.png",
  "bytes": 41873,
  "app": "example.bidbot",
  "template": "bid-won",
  "appearance": "dark",
  "scale": 2,
  "data": "sample+overrides",
  "width": 760,
  "height": 300
}
```

The reply carries these extra facts:

- `data` says where the values came from: `sample`, `last`, or either followed by `+overrides`.
- A `warnings` array is added when a draft has warnings.
- The server keeps the newest 40 preview files in its preview folder.

**HTTP route**

[`POST /v1/preview`](../api/templates.md#post-v1preview).

**Side effects**

Writes a PNG to the preview folder and removes the oldest ones beyond 40. Shows nothing on screen.

### `designer_snapshot`

Draws the Designer window's content offscreen and returns it as a PNG: the grid canvas with its handles, the inspector and the live preview. No window opens and nothing takes focus. Use it to check how the editor looks for a template; use [`render_preview`](#render_preview) to see the banner itself.

**Arguments**

| Name | Type | Required | Description |
|---|---|---|---|
| `app` | string | no | The app to open in the Designer. |
| `template` | string | no | A saved template name to open. |
| `select` | string | no | A cell id to select, so the inspector shows it. |
| `width` | integer | no | The image width, from 600 to 4000. Default 1100. |
| `height` | integer | no | The image height, from 400 to 3000. Default 820. |

**Example call**

```json
{"app": "example.bidbot", "template": "bid-won", "select": "title", "width": 1200, "height": 800}
```

**Example result**

The result is an image block (a PNG) and a text block such as `{"bytes": 188402, "width": 1200, "height": 800}`.

**HTTP route**

[`GET /v1/designer/snapshot`](../api/diagnostics.md#get-v1designersnapshot).

**Side effects**

None. Read-only. Opens no window.

## Buttons

A template can change the buttons the issuing app sent and add buttons of its own. The rules live in the template's `actionRules`; see [Actions](../actions.md). An agent cannot press a button and cannot grant the permission to run a command. The user confirms a command, script or Shortcut in Herald the first time its button is pressed.

### `list_shortcuts`

Lists the names of the Apple Shortcuts installed on this Mac. Use one in an action of kind `shortcut` (see [`add_action_rule`](#add_action_rule)): Herald runs it with the notification as input when the user presses the button.

**Arguments**

No arguments.

**Example call**

```json
{}
```

**Example result**

```json
{
  "count": 2,
  "shortcuts": ["Create follow-up", "Log to Notes"],
  "use": "add_action_rule with {\"add\": {\"id\": \"...\", \"label\": \"...\", \"kind\": \"shortcut\", \"shortcut\": \"<one of these names>\", \"input\": \"{title}\\n{url}\"}}"
}
```

**HTTP route**

[`GET /v1/shortcuts`](../api/templates.md#get-v1shortcuts).

**Side effects**

None. Read-only.

### `add_action_rule`

Adds one rule to a saved template's `actionRules`. A rule either changes an issuer action or adds an action of your own.

- To change an issuer action, set `match` to its id, its label or `*`, together with the change to make. The fields are in [Action rules](../actions.md#action-rules).
- To add an action, set `add` to an action object. The kinds and their fields are in [Action object](../actions.md#action-object) and [Fields by kind](../actions.md#fields-by-kind). For a Shortcut, take the name from [`list_shortcuts`](#list_shortcuts).

Rules that apply to every rule:

- A `script` action runs a file in `~/Library/Application Support/Herald/scripts/`, which [`herald_status`](notifications.md#herald_status) lists. The script receives the notification JSON on stdin. This server only talks to Herald's API, so an agent that wants a script writes the file itself and then adds the rule.
- A command, script or Shortcut you add is confirmed by the user the first time its button is pressed, and again whenever it changes.
- An add with the id of one of the issuer's own actions overwrites that button, and the confirmation says so. An action id that an earlier add rule already uses overwrites that rule.
- Any action can carry an SF Symbol, as a name (`checkmark.circle`) or a full styling object. An unknown name is a warning.
- The tool validates the template before saving it. It warns about a script that is missing or cannot run, a Shortcut that is not installed, and a `match` that matches nothing.

**Arguments**

| Name | Type | Required | Description |
|---|---|---|---|
| `app` | string | yes | The app id. |
| `template` | string | yes | The saved template's name. Built-in templates are read-only: copy one with [`duplicate_template`](#duplicate_template) first. |
| `rule` | object | yes | One rule. Its fields are in [Action rules](../actions.md#action-rules). |

**Example call**

```json
{
  "app": "example.bidbot",
  "template": "bid-won",
  "rule": {
    "add": {
      "id": "followup",
      "label": "Follow up",
      "kind": "shortcut",
      "shortcut": "Create follow-up",
      "input": "{title}\n{item}"
    }
  }
}
```

**Example result**

```json
{
  "saved": true,
  "app": "example.bidbot",
  "template": "bid-won",
  "ruleIndex": 0,
  "replacedExistingRule": false,
  "actionRules": 1,
  "resultingActions": [
    {"id": "view", "label": "View", "kind": "url", "origin": "issuer"},
    {"id": "withdraw", "label": "Withdraw", "kind": "callback", "style": "destructive", "origin": "issuer"},
    {"id": "followup", "label": "Follow up", "kind": "shortcut", "origin": "template"}
  ],
  "warnings": []
}
```

**HTTP route**

- [`PUT /v1/templates`](../api/templates.md#put-v1templates) saves the template with the rule added.
- [`GET /v1/templates`](../api/templates.md#get-v1templates) is read first, for the template.
- [`GET /v1/manifest`](../api/manifests.md#get-v1manifest) is read first, to check the rule.
- [`GET /v1/shortcuts`](../api/templates.md#get-v1shortcuts) is read first, to check a Shortcut name.

**Side effects**

Saves the template with the rule added. The user must confirm a new command, script or Shortcut in Herald before it first runs.

## Share a template

A template bundle is one `.heraldtemplate` file that holds a template and the Rive files it plays. It is what the Designer's Export and Import use.

### `export_template_bundle`

Packs a saved template, or a built-in generated for the app, and the Rive files it plays into one bundle. With `path` Herald writes the file on this Mac. Without it the bundle comes back as base64.

**Arguments**

| Name | Type | Required | Description |
|---|---|---|---|
| `app` | string | yes | The app id. |
| `name` | string | yes | The template name. |
| `path` | string | no | Where to write the file. It must end in `.heraldtemplate` and its folder must exist. |

**Example call**

```json
{"app": "example.bidbot", "name": "bid-won", "path": "~/Desktop/bid-won.heraldtemplate"}
```

**Example result**

```json
{
  "ok": true,
  "app": "example.bidbot",
  "name": "bid-won",
  "file": "bid-won.heraldtemplate",
  "bytes": 2481,
  "assets": [],
  "warnings": [],
  "path": "/Users/you/Desktop/bid-won.heraldtemplate"
}
```

Without `path`, the result has a `base64` field instead of `path`.

**HTTP route**

[`GET /v1/templates/export`](../api/templates.md#get-v1templatesexport).

**Side effects**

Writes a file when `path` is given. Changes no stored template.

### `import_template_bundle`

Imports a `.heraldtemplate` bundle. Give the bundle in one of two ways, not both:

- `path`, a file on this Mac, up to 64 MB.
- `base64`, up to about 700 KB.

`app` retargets the template to another app. The bundle's Rive files go into that app's assets folder. Script actions inside a bundle still need their script files and the user's approval.

**Arguments**

| Name | Type | Required | Description |
|---|---|---|---|
| `path` | string | no | A `.heraldtemplate` file on this Mac. |
| `base64` | string | no | The bundle, base64 encoded. |
| `app` | string | no | Imports the template for this app instead of the app in the bundle. |
| `onConflict` | string | no | What to do when the name exists: `keepBoth` (default; saves it as `name 2`), `replace` or `fail`. |

One of `path` or `base64` is needed.

**Example call**

```json
{"path": "~/Desktop/bid-won.heraldtemplate", "app": "example.bidbot", "onConflict": "keepBoth"}
```

**Example result**

```json
{
  "ok": true,
  "app": "example.bidbot",
  "name": "bid-won 2",
  "replaced": false,
  "installedAssets": [],
  "reusedAssets": [],
  "missingAssets": [],
  "warnings": [],
  "renamedFrom": "bid-won"
}
```

`renamedFrom` appears only when `keepBoth` renamed the template.

**HTTP route**

[`POST /v1/templates/import`](../api/templates.md#post-v1templatesimport).

**Side effects**

Saves a template and copies its Rive files. With `onConflict: "replace"` it overwrites a template of the same name. The tool carries the destructive hint.

## Assets and symbols

Assets are the Rive animations (`.riv`, at most 10 MB each, 32 per app) and images (at most 10 MB each, 100 per app) stored for an app. A template refers to a Rive file with `{"type": "rive", "path": "confetti.riv"}`. See the [Rive component](../components/rive.md).

### `list_assets`

Lists the Rive animations and images stored for an app, with their size, whether the manifest declares them, which templates play them, and the component snippet to use.

**Arguments**

| Name | Type | Required | Description |
|---|---|---|---|
| `app` | string | yes | The app id. |

**Example call**

```json
{"app": "example.bidbot"}
```

**Example result**

```json
{
  "app": "example.bidbot",
  "assets": [
    {
      "kind": "rive",
      "id": "confetti",
      "file": "confetti.riv",
      "path": "/Users/you/Library/Application Support/Herald/assets/example.bidbot/confetti.riv",
      "bytes": 48213,
      "declared": true,
      "usedBy": ["bid-won"],
      "component": {"type": "rive", "path": "confetti.riv"}
    },
    {"kind": "image", "file": "logo.png", "path": "/Users/you/Library/Application Support/Herald/assets/example.bidbot/images/logo.png", "bytes": 5120}
  ],
  "folder": "/Users/you/Library/Application Support/Herald/assets/example.bidbot",
  "limits": {"bytes": 10485760, "riveFiles": 32}
}
```

**HTTP route**

[`GET /v1/assets`](../api/assets.md#get-v1assets).

**Side effects**

None. Read-only.

### `upload_asset`

Adds a Rive animation or an image to an app's assets, like the Designer's Add. Give `path` (a file on this Mac) or `base64` (up to about 700 KB, with `name`). The reply has the stored path and the component to use. An existing file of the same name is overwritten. Images are checked by their bytes, so a wrong extension is caught. Accepted images are PNG, JPEG, GIF, WebP, HEIC, TIFF and BMP.

**Arguments**

| Name | Type | Required | Description |
|---|---|---|---|
| `app` | string | yes | The app id. |
| `path` | string | no | A file on this Mac. |
| `base64` | string | no | The file, base64 encoded. Needs `name`. |
| `name` | string | no | The file name, such as `confetti.riv` or `logo.png`. Required with `base64`. |
| `kind` | string | no | `rive` or `image`. Inferred from the name when omitted. |

Give exactly one of `path` or `base64`.

**Example call**

```json
{"app": "example.bidbot", "path": "~/Downloads/confetti.riv"}
```

**Example result**

```json
{
  "ok": true,
  "kind": "rive",
  "app": "example.bidbot",
  "id": "confetti",
  "file": "confetti.riv",
  "path": "/Users/you/Library/Application Support/Herald/assets/example.bidbot/confetti.riv",
  "bytes": 48213,
  "replaced": false,
  "component": {"type": "rive", "path": "confetti.riv"}
}
```

An image reply has `format` and `usage` fields instead of `id` and `component`; `usage` says to use the path as an image field's value or as a fixed image source.

**HTTP route**

[`POST /v1/assets`](../api/assets.md#post-v1assets).

**Side effects**

Writes a file into the app's assets folder, overwriting one of the same name.

### `delete_asset`

Deletes a Rive file or an image from an app's assets by file name. Templates that play a deleted animation show a placeholder, and the reply lists them.

**Arguments**

| Name | Type | Required | Description |
|---|---|---|---|
| `app` | string | yes | The app id. |
| `file` | string | yes | The file name, such as `confetti.riv`. [`list_assets`](#list_assets) shows the names. |

**Example call**

```json
{"app": "example.bidbot", "file": "confetti.riv"}
```

**Example result**

```json
{"ok": true, "deleted": "confetti.riv", "stillReferencedBy": ["bid-won"]}
```

**HTTP route**

[`DELETE /v1/assets`](../api/assets.md#delete-v1assets).

**Side effects**

Deletes a file. The tool carries the destructive hint.

### `list_symbols`

Searches the SF Symbol names available on this Mac, with their categories, for a component's `symbol` property. See [SF Symbols](../symbols.md). The arguments are in the table below. In short:

- `q` matches every word in the name or its search terms.
- `category` narrows the list, and the reply lists the categories with counts.
- `limit` and `offset` page through long lists.

**Arguments**

| Name | Type | Required | Description |
|---|---|---|---|
| `q` | string | no | Search words, such as `bell` or `arrow up`. |
| `category` | string | no | A category key from the reply, such as `communication` or `weather`. |
| `limit` | integer | no | Names per page, up to 1,000. Default 100. |
| `offset` | integer | no | How many names to skip. Default 0. |

**Example call**

```json
{"q": "bell", "limit": 2}
```

**Example result**

```json
{
  "total": 14,
  "offset": 0,
  "limit": 2,
  "symbols": [
    {"name": "bell", "categories": ["communication"]},
    {"name": "bell.fill", "categories": ["communication"]}
  ],
  "categories": [{"key": "communication", "title": "Communication", "icon": "bubble.left.and.bubble.right", "count": 10}]
}
```

**HTTP route**

[`GET /v1/symbols`](../api/templates.md#get-v1symbols).

**Side effects**

None. Read-only.

### `rive_check`

Loads a `rive` component without a window and reports what it found: the artboards, the state machines and their inputs, and the view-model properties. Nothing is shown or stored. See [Rive](../rive.md#testing-without-a-window).

With `simulate` it first runs pointer steps in order and reports what they wrote to the inputs. The steps are:

| Step | Pointer action |
|---|---|
| `hoverIn` | The pointer moves onto the animation. |
| `hoverOut` | The pointer leaves it. |
| `pressDown` | The button goes down. |
| `pressUp` | The button comes up. |

**Arguments**

| Name | Type | Required | Description |
|---|---|---|---|
| `app` | string | yes | The app id. Assets resolve in its folder. |
| `component` | object | yes | The `rive` component: `asset` or `path`, and optionally `artboard`, `stateMachine`. |
| `fields` | object | no | Field values for the component's bindings. |
| `simulate` | array of string | no | Pointer steps to run in order. |

**Example call**

```json
{"app": "example.bidbot", "component": {"type": "rive", "path": "confetti.riv"}, "simulate": ["hoverIn", "pressDown"]}
```

**Example result**

The reply is trimmed here to its main fields.

```json
{
  "loaded": true,
  "inputs": {"celebrate": "trigger"},
  "applied": {},
  "artboards": [
    {
      "name": "Main",
      "width": 320,
      "height": 120,
      "defaultMachine": "Machine",
      "machines": [{"name": "Machine", "inputs": [{"name": "celebrate", "kind": "trigger"}]}],
      "animations": []
    }
  ],
  "takesClicks": false,
  "pointerWrites": {}
}
```

When the animation does not load, `loaded` is `false` and `error` holds the reason the banner's placeholder shows.

**HTTP route**

[`POST /v1/rive/check`](../api/diagnostics.md#post-v1rivecheck).

**Side effects**

None. Opens no window and stores nothing.

## Related

- [MCP server overview](README.md) for the conventions and the index of every tool.
- [Design a banner with an agent](../../MCP.md#a-worked-session) for a full session using these tools.
- [Grid and layout](../grid-and-layout.md), [Components](../components/README.md) and [Actions](../actions.md) for the formats behind the arguments.
- [Manifests](../manifests.md) for the fields and actions an app declares.
- [Templates API](../api/templates.md) and [Manifests API](../api/manifests.md) for the HTTP calls.
