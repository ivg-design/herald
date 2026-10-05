# Templates API

These endpoints store and inspect templates: save one, list them, copy, rename, pick the default, move them
between Macs as bundles, and render a preview image. They also serve the lookups a template author needs: the
component schema, SF Symbol names and the installed Shortcuts. The examples use the `$HERALD` and `$TOKEN`
variables from [Connect](README.md#connect).

## What a template is

A **template** is a saved layout for one app's banners. It is a grid of cells, and each cell holds a component
such as text, an image or a row of buttons. A component is bound to a field of the notification, for example
`{title}`, so one template draws every notification the app sends.

A template belongs to one app and has a name. A notification picks its template in this order:

1. The `template` named in the notification.
2. The `defaultTemplate` of the app's manifest.
3. One of the four built-in layouts: `builtin.imageLeft`, `builtin.imageRight`, `builtin.hero`,
   `builtin.compact`.

You can design a template by hand in the [Designer](../../AUTHORING.md) or send its JSON to this API. The
fields of the template object are documented in [Grid and layout](../grid-and-layout.md); this page covers
only the endpoints.

![The Designer window with a template open on the grid](../../../web/public/shots/docs/designer-overview.png "The Designer edits the same template object these endpoints store. A template saved here appears in the Designer at once.")

## Endpoints

| Endpoint | Purpose |
|---|---|
| [`GET /v1/templates`](#get-v1templates) | List saved templates. |
| [`PUT /v1/templates`](#put-v1templates) | Save a template. |
| [`DELETE /v1/templates`](#delete-v1templates) | Delete a template. |
| [`POST /v1/templates/duplicate`](#post-v1templatesduplicate) | Copy a template. |
| [`POST /v1/templates/rename`](#post-v1templatesrename) | Rename a template. |
| [`PUT /v1/templates/default`](#put-v1templatesdefault) | Set or clear an app's default template. |
| [`PUT /v1/templates/follow-up`](#put-v1templatesfollow-up) | Set or switch off a template's follow-up. |
| [`GET /v1/templates/export`](#get-v1templatesexport) | Pack a template and its assets into a bundle. |
| [`POST /v1/templates/import`](#post-v1templatesimport) | Install a bundle. |
| [`POST /v1/preview`](#post-v1preview) | Render a template to a PNG. |
| [`GET /v1/preview`](#get-v1preview) | Render a saved template with sample data. |
| [`GET /v1/components`](#get-v1components) | The schema of every component. |
| [`GET /v1/symbols`](#get-v1symbols) | Search SF Symbol names. |
| [`GET /v1/shortcuts`](#get-v1shortcuts) | List the installed Apple Shortcuts. |

## Store templates

### `GET /v1/templates`

Lists the templates saved for one app, or for every app. Each item is the full template object.

**Request**

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `app` | query | string | no | Return only this app's templates. Default: every app. |

**Example request**

```sh
curl -s "$HERALD/v1/templates?app=example.bidbot" -H "Authorization: Bearer $TOKEN"
```

**Example response**

```json
{
  "items": [
    {
      "name": "bid-won",
      "app": "example.bidbot",
      "layoutVersion": 2,
      "collapseEmpty": true,
      "grid": {
        "rows": 2,
        "cols": 2,
        "rowSizes": ["auto", "auto"],
        "colSizes": ["48", "fill"],
        "gap": 8,
        "padding": 14,
        "width": 400
      },
      "cells": [
        {"id": "icon", "row": 0, "col": 0, "rowSpan": 2, "component": {"type": "issuerIcon"}},
        {"id": "title", "row": 0, "col": 1, "component": {"type": "text", "binding": "{title}", "style": "title"}},
        {"id": "body", "row": 1, "col": 1, "component": {"type": "text", "binding": "{body}", "style": "body"}}
      ]
    }
  ]
}
```

**Notes**

- The four `builtin.*` layouts are not listed. They always exist.
- Templates whose names start with `_` are scratch templates, such as the one the Designer writes for
  **Send test**. They work by name and are never listed.

### `PUT /v1/templates`

Saves a template. If the app already has a template with the same name, it is replaced. The template is
validated before it is stored, so a bad layout is refused here and not when a notification arrives.

**Request**

The body is one template object. These two fields are required; the rest are in
[Grid and layout](../grid-and-layout.md).

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `name` | body | string | yes | The template's name. |
| `app` | body | string | yes | The app the template belongs to. |
| `grid` | body | object | no | The rows, columns and sizes of the grid. |
| `cells` | body | array | no | The cells and the component in each. |

**Example request**

```sh
curl -s -X PUT "$HERALD/v1/templates" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{
    "name": "bid-won",
    "app": "example.bidbot",
    "layoutVersion": 2,
    "collapseEmpty": true,
    "grid": {"rows": 2, "cols": 2, "rowSizes": ["auto", "auto"], "colSizes": ["48", "fill"],
             "gap": 8, "padding": 14, "width": 400},
    "cells": [
      {"id": "icon", "row": 0, "col": 0, "rowSpan": 2, "component": {"type": "issuerIcon"}},
      {"id": "title", "row": 0, "col": 1,
       "component": {"type": "text", "binding": "{title}", "style": "title"}},
      {"id": "body", "row": 1, "col": 1,
       "component": {"type": "text", "binding": "{body}", "style": "body", "maxLines": 3}}
    ]
  }'
```

**Example response**

```json
{"ok": true}
```

**Errors**

| Status | When |
|---|---|
| `400` | `name` or `app` is missing. |
| `400` | The template is invalid. The message lists every problem with its location. |
| `500` | The file could not be written. |

**Notes**

- A validation message names the cell and the path of each problem, separated by semicolons, for example
  `invalid template: grid.rowSizes: rowSizes has 1 entries but rows is 2; grid.gap: gap must be 0 to 64`.
  A problem inside a cell starts with `cell <id>:`.
- Templates are files: `templates/<app>/<name>.json` in Herald's support folder.

### `DELETE /v1/templates`

Deletes one saved template.

**Request**

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `app` | query | string | yes | The app the template belongs to. |
| `name` | query | string | yes | The template's name. |

**Example request**

```sh
curl -s -X DELETE "$HERALD/v1/templates?app=example.bidbot&name=bid-won" \
  -H "Authorization: Bearer $TOKEN"
```

**Example response**

```json
{"ok": true}
```

**Errors**

| Status | When |
|---|---|
| `400` | `app` or `name` is missing. |
| `404` | The app has no template with this name. |

## Copy, rename and choose the default

### `POST /v1/templates/duplicate`

Copies a saved template or a built-in layout. Use it to start a new design from an existing one, or to give
another app the same layout.

**Request**

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `app` | body | string | yes | The app that owns the template to copy. |
| `name` | body | string | yes | The template to copy: a saved name or a `builtin.*` name. |
| `newName` | body | string | no | The name of the copy. Default: the old name followed by `copy`. |
| `toApp` | body | string | no | The app that receives the copy. Default: the same app. |

**Example request**

```sh
curl -s -X POST "$HERALD/v1/templates/duplicate" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"app": "example.bidbot", "name": "builtin.hero", "newName": "bid-hero"}'
```

**Example response**

```json
{
  "ok": true,
  "app": "example.bidbot",
  "name": "bid-hero",
  "copiedFrom": {"app": "example.bidbot", "name": "builtin.hero"}
}
```

**Errors**

| Status | When |
|---|---|
| `400` | `newName` is not a valid name. See the notes. |
| `404` | The template to copy does not exist. |
| `409` | A template named `newName` already exists for the receiving app. |

**Notes**

- Without `newName` the copy is named after the original: `bid-won copy`, then `bid-won copy 2` when that is taken.
- A template name cannot be empty, contain `/` or `:`, start with `.` or `_`, start with `builtin.`, or be
  longer than 128 bytes.

### `POST /v1/templates/rename`

Renames a saved template. If it was the app's default template, the manifest follows the new name.

**Request**

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `app` | body | string | yes | The app that owns the template. |
| `name` | body | string | yes | The current name. |
| `newName` | body | string | yes | The new name. |

**Example request**

```sh
curl -s -X POST "$HERALD/v1/templates/rename" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"app": "example.bidbot", "name": "bid-hero", "newName": "bid-accepted"}'
```

**Example response**

```json
{
  "ok": true,
  "app": "example.bidbot",
  "name": "bid-accepted",
  "renamedFrom": "bid-hero",
  "isDefault": false,
  "note": "Command, script and Shortcut approvals belong to the old name; the user is asked again the first time they run."
}
```

**Errors**

| Status | When |
|---|---|
| `400` | `name` is a `builtin.*` layout, or `newName` is not a valid name. |
| `404` | The template does not exist. |
| `409` | A template named `newName` already exists for the app. |

**Notes**

- Approvals to run commands, scripts and Shortcuts are tied to the template's name. After a rename the user
  is asked again the first time one runs.
- Built-in layouts cannot be renamed. Duplicate one instead.

### `PUT /v1/templates/default`

Sets the template an app uses when a notification names none, or clears it. The default is stored in the
app's manifest as `defaultTemplate`, so the app must have a manifest.

**Request**

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `app` | body | string | yes | The app to change. |
| `name` | body | string | no | A saved template or a `builtin.*` layout. Omit it to clear the default. |

**Example request**

```sh
curl -s -X PUT "$HERALD/v1/templates/default" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"app": "example.bidbot", "name": "bid-accepted"}'
```

**Example response**

```json
{"ok": true, "app": "example.bidbot", "defaultTemplate": "bid-accepted"}
```

**Errors**

| Status | When |
|---|---|
| `400` | The app has no manifest. Save one with [`PUT /v1/manifest`](manifests.md#put-v1manifest) first. |
| `404` | `name` is not a saved template or built-in layout. |

### `PUT /v1/templates/follow-up`

Sets the follow-up of a template, or switches it off. A follow-up runs one action when a banner is left unattended
(see [Follow-ups](../actions.md#follow-ups)). The route edits the template for you, so you do not read and rewrite it. It
never approves code. When the action runs code, the result says the person still has to approve it at the Mac.

**Request**

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `app` | body | string | yes | The app that owns the template. |
| `template` | body | string | no | The template to edit. Default: the app's default template. When the app has none, Herald creates one from the current layout. |
| `after` | body | number or string | no | Seconds from 5 to 604800, or `"90s"`, `"10m"`, `"2h"`. Required unless `enabled` is `false`. |
| `shortcut` | body | string | no | Run this Apple Shortcut. |
| `script` | body | string | no | Run this file from Herald's scripts folder. |
| `command` | body | string | no | Run this shell command. |
| `actionRef` | body | string | no | Run the action of this id, or label, that the notification offers. |
| `input` | body | string | no | Text for the Shortcut or script, with `{tokens}` filled. |
| `label` | body | string | no | The name shown in **Follow-up ran: LABEL**. Default: the Shortcut or script name. |
| `enabled` | body | boolean | no | `false` switches the follow-up off. Default `true`. |

Give exactly one of `shortcut`, `script`, `command` and `actionRef`, unless `enabled` is `false`.

**Example request**

```sh
curl -s -X PUT "$HERALD/v1/templates/follow-up" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"app": "example.bidbot", "template": "Bid won", "after": "10m",
       "shortcut": "Forward to phone", "input": "{title}"}'
```

**Example response**

```json
{
  "saved": true,
  "app": "example.bidbot",
  "template": "Bid won",
  "createdTemplate": false,
  "followUp": {"after": 600, "action": {"id": "follow-up", "label": "Forward to phone",
                                       "kind": "shortcut", "shortcut": "Forward to phone"}},
  "action": {"id": "follow-up", "label": "Forward to phone", "kind": "shortcut"},
  "origin": "template",
  "approval": "needs-approval",
  "needsApproval": true,
  "note": "Saved. The follow-up will not run until the person approves this template's Shortcut at the Mac."
}
```

**Response fields**

| Field | Type | Description |
|---|---|---|
| `saved` | boolean | `true` when the template was written. |
| `app`, `template` | string | The app and the template that now carries the follow-up. |
| `createdTemplate` | boolean | `true` when Herald made the template because the app had none. |
| `followUp` | object | The stored follow-up, with `after` in seconds. |
| `action` | object | The action it runs: `id`, `label` and `kind`. |
| `origin` | string | `template`. The template's approval applies. |
| `approval` | string | `approved`, `needs-approval`, `app-permission-needed`, `app-not-allowed` or `none`. See below. |
| `needsApproval` | boolean | `true` when nothing runs until the person approves. |
| `note` | string | A sentence that says what happens next. |

The `approval` values:

| Value | Meaning |
|---|---|
| `approved` | The person already approved this template's code. The follow-up runs. |
| `needs-approval` | The person has to approve the template's code, in the banner's question, the first time. |
| `app-permission-needed` | The action is an issuer action. The app asked to run commands, scripts and Shortcuts and the person has not allowed it yet: the banner asks the first time it would run. |
| `app-not-allowed` | The action is an issuer action and the app never registered with `allowCommands`, so it cannot run. |
| `none` | The action runs no code, such as a callback to this Mac. |

**Errors**

| Status | When |
|---|---|
| `400` | `after` is out of range, no action or more than one is named, the kind cannot follow up, or `actionRef` names an action the notification does not offer. |
| `404` | The app, or the template named, does not exist. |

**Notes**

- Priority is template, then notification, then manifest. A template follow-up wins over the issuer's.
- `"enabled": false` also switches off a follow-up that the issuer declares.
- Approval is bound to the template's name and its code. Changing the Shortcut asks again.

## Move templates between Macs

A **bundle** is one `.heraldtemplate` file that holds a template and the Rive animations it uses. Export a
bundle to share a design, and import it on another Mac or into another app. How bundles treat assets is
explained in [Rive: packaging with a template](../rive.md#packaging-with-a-template-heraldtemplate).

### `GET /v1/templates/export`

Packs a template and its Rive files into a bundle. Herald either writes the bundle to a path you give, or
returns it in the reply as base64.

**Request**

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `app` | query | string | yes | The app that owns the template. |
| `name` | query | string | yes | A saved template or a `builtin.*` layout. |
| `path` | query | string | no | Where to write the file. Must end in `.heraldtemplate`. |

**Example request**

```sh
curl -s -G "$HERALD/v1/templates/export" -H "Authorization: Bearer $TOKEN" \
  --data-urlencode "app=example.bidbot" --data-urlencode "name=bid-accepted" \
  --data-urlencode "path=$HOME/Desktop/bid-accepted.heraldtemplate"
```

**Example response**

```json
{
  "ok": true,
  "app": "example.bidbot",
  "name": "bid-accepted",
  "file": "bid-accepted.heraldtemplate",
  "bytes": 18432,
  "assets": ["confetti.riv"],
  "warnings": [],
  "path": "/Users/you/Desktop/bid-accepted.heraldtemplate"
}
```

**Response fields**

| Field | Type | Description |
|---|---|---|
| `file` | string | The suggested file name of the bundle. |
| `bytes` | integer | The size of the bundle. |
| `assets` | array | The Rive files packed into it. |
| `warnings` | array | Problems that did not stop the export, such as a referenced file that is missing. |
| `path` | string | Where the file was written. Present when you sent `path`. |
| `base64` | string | The bundle itself. Present when you did not send `path`. |

**Errors**

| Status | When |
|---|---|
| `400` | `path` does not end in `.heraldtemplate`, or its folder does not exist. |
| `404` | The template does not exist. |

### `POST /v1/templates/import`

Installs a bundle: saves its template and stores its Rive files. You choose what happens when a template with
the same name already exists.

**Request**

Give exactly one of `base64` and `path`.

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `path` | body | string | no | A `.heraldtemplate` file on this Mac. |
| `base64` | body | string | no | The bundle as base64, for small bundles. |
| `app` | body | string | no | Install the template for this app. Default: the app named in the bundle. |
| `onConflict` | body | string | no | `keepBoth`, `replace` or `fail`. Default `keepBoth`. |

**Example request**

```sh
curl -s -X POST "$HERALD/v1/templates/import" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"path": "~/Desktop/bid-accepted.heraldtemplate", "app": "example.bidbot", "onConflict": "keepBoth"}'
```

**Example response**

```json
{
  "ok": true,
  "app": "example.bidbot",
  "name": "bid-accepted 2",
  "renamedFrom": "bid-accepted",
  "replaced": false,
  "installedAssets": ["confetti.riv"],
  "reusedAssets": [],
  "missingAssets": [],
  "warnings": []
}
```

**Response fields**

| Field | Type | Description |
|---|---|---|
| `name` | string | The name the template was saved under. |
| `renamedFrom` | string | The name in the bundle, when `keepBoth` had to pick a new one. |
| `replaced` | boolean | `true` when an existing template was overwritten. |
| `installedAssets` | array | Rive files copied into the app's assets. |
| `reusedAssets` | array | Rive files the app already had, left as they were. |
| `missingAssets` | array | Files the template refers to that were not in the bundle. |
| `warnings` | array | Problems that did not stop the import. |

**Errors**

| Status | When |
|---|---|
| `400` | Both or neither of `base64` and `path` were sent, or the bundle cannot be read. |
| `400` | `onConflict` is not one of the three values. |
| `409` | `onConflict` is `fail` and a template with that name exists. |
| `413` | The bundle is too large. |

**Notes**

- `keepBoth` saves the import under a new numbered name. `replace` overwrites. `fail` refuses.
- A request body is limited to 1 MB, so use `path` for any bundle with animations in it.

## Preview a template

### `POST /v1/preview`

Renders a template to a PNG image with the same code that draws real banners, without showing anything on
screen. Use it to check a design, including how it looks with long text, missing fields, in dark mode or as a
stack.

**Request**

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `app` | body | string | yes | The app. Optional when `template` is an object that names its app. |
| `template` | body | string or object | no | A template name, or a whole template object. |
| `data` | body | string or object | no | The notification to draw: `"sample"`, `"last"` or an object. Default `"sample"`. |
| `appearance` | body | string | no | `light` or `dark`. Default `light`. |
| `scale` | body | number | no | Pixel scale from 1 to 3. Default `2`. |
| `stackCount` | body | integer | no | From 1 to 99. Above 1, draws the banner as the top card of a stack. Default `1`. |
| `stackExpanded` | body | boolean | no | With `stackCount` above 1, draws the stack open as a list. |
| `confirmation` | body | string or object | no | Draws an inline question on the banner. See the notes. |
| `replying` | body | boolean | no | `true` draws the reply field in place of the buttons. |
| `replySample` | body | string | no | The text shown in the reply field when `replying` is `true`. |

**Example request**

```sh
curl -s -X POST "$HERALD/v1/preview" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{
    "app": "example.bidbot",
    "template": "bid-accepted",
    "data": {"title": "Bid accepted", "body": "Acme accepted your bid of $4,200."},
    "appearance": "dark"
  }' -o preview.png
```

**Example response**

The reply is the image itself, with `Content-Type: image/png`. The command above saves it as `preview.png`.

```text
preview.png: PNG image data, 800 x 196, 8-bit/color RGBA
```

**Errors**

| Status | When |
|---|---|
| `400` | `app` is missing, or a value is invalid. The message names the field. |
| `400` | An inline `template` is invalid. The message names the cell. |
| `400` | `data` is `"last"` and the app has no notification in History. |
| `500` | The render failed, for example because the named template does not exist. |

**Notes**

- Without `template`, Herald uses the app's default template, or `builtin.imageLeft`.
- `data: "sample"` uses the sample values of the app's manifest. `data: "last"` uses the app's most recent
  notification. An object is read like the body of [`POST /v1/notify`](notifications.md#post-v1notify): leave
  a field out to see how the template collapses without it.
- A preview cannot play a `rive` component and draws a labelled placeholder in its place. Menus are drawn as
  static labels, and symbol effects do not animate.

#### Confirmation kinds

Herald sometimes asks a question inside a banner before it acts, for example before it runs a command for the
first time. `confirmation` draws such a question so that you can check how it looks. Send a kind as a string,
or an object with a `kind` and optional text.

| Kind | The question it draws |
|---|---|
| `callbackHost` | Whether to let the app call a server on another machine. |
| `command` | Whether to run a shell command for the app. |
| `script` | Whether to run a script for the app. |
| `shortcut` | Whether to run an Apple Shortcut for the app. |
| `templateCommand` | Whether to run a command that a template added. |
| `destructiveAction` | Whether to go ahead with a destructive button. |
| `connectorConsent` | Whether to let a cloud connector send notifications. |
| `remindersError` | A notice that adding to Reminders failed. |
| `remindersDenied` | The same notice, with a button to open System Settings. |

The object form accepts these optional strings to fill in the question's text. Each has a sample default.

| Field | Used by | Description |
|---|---|---|
| `name` | All kinds | The app's name in the question. Default: the app id. |
| `host`, `url` | `callbackHost`, `connectorConsent` | The host, and the full address, being asked about. |
| `command` | `command`, `script`, `shortcut`, `templateCommand` | The text of what would run. |
| `template`, `others`, `replaces` | `templateCommand` | The template's name, its other commands, and the app button it replaces. |
| `label` | `destructiveAction` | The label of the destructive button. |
| `code` | `connectorConsent` | The code a connector without a browser printed. |
| `message` | `remindersError`, `remindersDenied` | The error text. |

```json
{
  "app": "example.bidbot",
  "template": "bid-accepted",
  "confirmation": {"kind": "command", "command": "open -a Numbers ~/Bids/acme.numbers"}
}
```

### `GET /v1/preview`

The quick form of the preview: renders a saved template with the manifest's sample data. It is convenient in a
browser-free check such as `curl -o`, because everything is in the URL.

**Request**

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `app` | query | string | yes | The app. |
| `template` | query | string | no | A saved template or `builtin.*` name. Default: the app's default template. |
| `appearance` | query | string | no | `light` or `dark`. Default `light`. |
| `scale` | query | number | no | Pixel scale from 1 to 3. Default `2`. |
| `stackCount` | query | integer | no | From 1 to 99. Default `1`. |
| `stackExpanded` | query | boolean | no | `true` draws the stack open. |

**Example request**

```sh
curl -s "$HERALD/v1/preview?app=example.bidbot&template=bid-accepted&appearance=dark" \
  -H "Authorization: Bearer $TOKEN" -o preview.png
```

**Example response**

The reply is a PNG image, as for [`POST /v1/preview`](#post-v1preview).

```text
preview.png: PNG image data, 800 x 196, 8-bit/color RGBA
```

**Errors**

| Status | When |
|---|---|
| `400` | `app` is missing, or `appearance`, `scale` or `stackCount` is invalid. |
| `500` | The render failed. |

## Look things up

### `GET /v1/components`

Returns the component schema: every component type with its properties, allowed values and defaults, the
binding rules, the action kinds, and worked examples. It is static data made for programs and agents that
write templates. The human-readable version is the [components reference](../components/README.md).

**Request**

No parameters.

**Example request**

```sh
curl -s "$HERALD/v1/components" -H "Authorization: Bearer $TOKEN"
```

**Example response**

The document is long. This is its outline, with the content of each part left out and the description shortened.

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "title": "Herald banner template, layoutVersion 2",
  "schemaVersion": 2,
  "description": "A Herald banner is drawn from a GRID.",
  "type": "object",
  "required": ["name", "app", "layoutVersion", "grid", "cells"],
  "properties": {},
  "definitions": {},
  "components": {},
  "bindings": {},
  "actions": {},
  "examples": [],
  "workflow": []
}
```

**Response fields**

| Field | Type | Description |
|---|---|---|
| `properties` | object | The fields of the template object. |
| `definitions` | object | The shared types: grid, cell, size, alignment. |
| `components` | object | One entry per component type with its properties and defaults. |
| `bindings` | object | The tokens a component can bind and how they are formatted. |
| `actions` | object | The action kinds and the rules a template can apply to them. |
| `examples` | array | Complete templates that validate. |
| `workflow` | array | The order of calls an agent should follow to design a template. |

### `GET /v1/symbols`

Searches the SF Symbol names available on this Mac. Use a returned name as a component's `symbol` value. See
the [SF Symbols reference](../symbols.md).

**Request**

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `q` | query | string | no | Search words. Every word must match the name, Apple's search terms or a synonym. |
| `category` | query | string | no | A category key from the `categories` list in the reply. |
| `limit` | query | integer | no | The most names to return, up to 1000. Default `100`. |
| `offset` | query | integer | no | How many matches to skip, for paging. Default `0`. |

**Example request**

```sh
curl -s "$HERALD/v1/symbols?q=bell&limit=3" -H "Authorization: Bearer $TOKEN"
```

**Example response**

```json
{
  "total": 28,
  "offset": 0,
  "limit": 3,
  "symbols": [
    {"name": "bell", "categories": ["multicolor", "objectsandtools"]},
    {"name": "bell.fill", "categories": ["multicolor", "objectsandtools"]},
    {"name": "bell.circle", "categories": ["multicolor", "objectsandtools", "variable"]}
  ],
  "categories": [
    {"key": "all", "title": "All", "icon": "square.grid.2x2", "count": 7779},
    {"key": "communication", "title": "Communication", "icon": "message", "count": 222}
  ]
}
```

**Response fields**

| Field | Type | Description |
|---|---|---|
| `total` | integer | How many symbols match. |
| `symbols` | array | The matches on this page: `name` and the `categories` it belongs to. |
| `categories` | array | Every category: `key`, `title`, `icon` and `count`. |

**Errors**

| Status | When |
|---|---|
| `400` | `category` is not a known key. The message lists the known keys. |
| `501` | This Mac has no SF Symbols list. |

### `GET /v1/shortcuts`

Lists the names of the Apple Shortcuts installed on this Mac. Use a name in a template action of kind
`shortcut`.

**Request**

No parameters.

**Example request**

```sh
curl -s "$HERALD/v1/shortcuts" -H "Authorization: Bearer $TOKEN"
```

**Example response**

```json
{"items": ["Create follow-up", "Log Entry"]}
```

**Errors**

| Status | When |
|---|---|
| `502` | The system `shortcuts` tool failed or is missing. |
| `504` | The system `shortcuts` tool did not answer in time. |

## Related

- [Follow-ups](../actions.md#follow-ups): the timer, the approval and what the banner shows.
- [Forward a notification you missed](../../FORWARD-MISSED.md): a follow-up that forwards a banner.
- [Templates guide](../../TEMPLATES.md): what to put in a template and why.
- [Design a banner in the Designer](../../AUTHORING.md): the same work by hand.
- [Grid and layout](../grid-and-layout.md): every field of the template object.
- [Components](../components/README.md): what each cell can hold.
- [MCP tools for templates](../mcp/templates.md): the same operations for an agent.
