# Rive in Herald

A banner can play a Rive animation: a bell that rings when new mail arrives, a spinner while a job runs, an
icon that reacts to the mouse. This page is for anyone who makes the animation or writes the template that plays
it. It covers how to prepare a `.riv` file, how to get it into Herald, how notification fields and the mouse drive
it, and how to find out why it does not play. The properties of the component itself are in
[the `rive` component reference](components/rive.md).

Examples use the fictional app `example.bidbot` unless a section says otherwise, and the `$HERALD` and `$TOKEN`
variables from [Connect](api/README.md#connect).

## What Herald does with a Rive file

A `rive` component draws one artboard of a `.riv` file inside one cell of a banner and keeps it playing while the
banner is up. Read this section first to learn what you can and cannot ask of an animation.

Herald does these things for every `rive` component:

1. It loads the file and picks an artboard and a state machine.
2. It plays the state machine with `contain` fit, centred, and starts it at once.
3. It writes the state machine's **inputs** (Number, Boolean and Trigger) from the notification's fields and from
   the mouse (`hover` and `pressed`).
4. It optionally runs an action when the animation is clicked.

Rive's own features go further than this. Herald does not use these, so design the animation without them:

| Rive feature | What to do instead |
|---|---|
| Data binding (view models and their properties). | Drive the animation with state machine inputs. |
| Text runs set from a field. | Put the text in a [`text` component](components/text.md) beside the animation. |
| Rive events. | Run an action when the animation is clicked. |
| Audio. | Use Herald's own [voice and sounds](voice.md). |
| A `.riv` file at a remote URL. | Download the file and reference the local copy. |
| Several artboards at once. | One component plays one artboard. Use several components. |

> [!NOTE]
> A file that uses data binding still loads and plays its default state. Herald just never writes to the view
> model, so nothing in the animation follows a notification.

The next sections follow the order of the work: prepare the file, store it, reference it, drive it, size it.

## Preparing the file in the Rive editor

Herald reads three things from your file: the artboard, the state machine and its inputs. This section lists what to
set in the Rive editor so that each one behaves well in a banner.

### Artboard

| Setting | Recommendation | Why |
|---|---|---|
| Name | A short, stable name such as `Bell`. | A component can name the artboard it wants. The name is case-sensitive. |
| Size and ratio | Make the artboard the same ratio as the box you will give it. | Herald draws the whole artboard with `contain`, so a box with another ratio leaves empty bands. |
| Background | Leave it transparent. | Banners are drawn on a translucent system material. A full-bleed shape draws a card inside the card. |
| Colours | Pick colours that work on light and dark. | The file is drawn as it is in both appearances. Add a Boolean input if you want two looks. |

Square artboards of 64 x 64 or 128 x 128 suit icon-sized animations, where the box is typically 24 to 48 points
high. A strip such as 400 x 120 suits a banner-wide animation. With no artboard name in the component, Herald plays
the file's default (first) artboard.

### State machine

Create a state machine and give it a name such as `Main`. Herald chooses the one to play in this order:

1. The component's `stateMachine`.
2. The `stateMachine` of the manifest asset the component names.
3. The artboard's default state machine.
4. The first state machine in the artboard.

A file with no state machine but with a linear animation plays the first animation, and the component's `loop`
chooses between looping and playing once. A file with neither shows the placeholder
`the file has no state machine or animation`. Naming a state machine that does not exist is an error, and the
message lists the names that do exist.

### Inputs

Herald supports the three input types a state machine has:

| Rive input | Herald treats it as | Herald writes |
|---|---|---|
| Number | `number` | A number. |
| Boolean | `bool` | True or false. |
| Trigger | `trigger` | A firing, when the bound value turns truthy. |

Inputs are found by name, and the match is case-sensitive.

- A binding whose name is not an input of the state machine is skipped without an error, so a typo is silent.
- Run a [check](#testing-without-a-window) and read the `inputs` it reports to see which names Herald found.
- Name inputs after what the field means, not how it looks: `count`, `isUnread`, `ring`, `progress`.

### Hover, press and click

Three different things can react to the pointer. Each is wired in the template, not in the file:

| You want | In the Rive file | In the template |
|---|---|---|
| The animation reacts when the pointer enters it. | An input used in transitions, such as a Boolean `hover`. | `"inputBindings": {"hover": "hover"}` |
| The animation reacts to a press. | An input such as a Boolean `pressed`. | `"inputBindings": {"pressed": "pressed"}`. The animation then takes clicks. |
| Something opens or runs when the animation is clicked. | Nothing. | `action` or `actionRef` on the component. |

How the pointer reaches the animation:

- A Boolean input bound to `hover` is true while the pointer is inside. A Number input gets 1 or 0. A Trigger
  fires when the pointer enters.
- `pressed` works the same way with the mouse button. Leaving the animation while pressed releases it.
- Hover tracking works in the banner, which never takes focus.
- Mouse down, drag and up are passed to Rive, so a state machine's own pointer listeners for press, drag and
  release work.
- Pointer move is not passed to Rive. A Rive "pointer enter", "exit" or "move" listener does not fire. Use a
  `hover` input instead.
- Without an `action`, an `actionRef` or a `pressed` binding, the animation lets clicks through to the banner, so
  clicking it still does what clicking the banner does. Banner clicks are described in
  [How banners behave](banners.md).

A `rive` cell is never treated as empty, because it always has an `asset` or a `path`, so it is always drawn. To show
the animation only for some notifications, use a second template, or make the state machine's idle state invisible
and bind an input to a field.

### Images and fonts inside the file

Assets embedded in the `.riv` always work. Assets the file marks as hosted elsewhere are fetched from the network
when the animation loads, which delays the banner and fails offline. For a banner that must appear instantly and
work offline, embed every asset in Rive by choosing **Embed** in the asset's export settings. The Designer reads the
file only for names and inputs and does not fetch hosted assets.

### File size and count

| Limit | Value |
|---|---|
| File name | Must end in `.riv`, in any case. A symlink is followed, and both names must end in `.riv`. |
| File size | 1 byte to 10 MB. |
| Files per app | 32 `.riv` files in the app's folder. |
| Assets per manifest | 32. |
| Files in a template bundle | 32 files of up to 10 MB each, and 64 MB in total. |

A banner loads its animation every time it appears, so keep files small. Under 100 KB is typical for icon-sized
work. The 10 MB limit is a ceiling, not a target.

## Where the files live

Herald keeps an app's animations in one folder per app, so every template of that app can use them. This section
tells you where that folder is and what Herald puts in it, which matters when you copy a file in by hand or clean up.

```text
~/Library/Application Support/Herald/assets/<app>/<asset id>.riv
```

`<app>` and `<asset id>` are each reduced to one safe path component:

- A character outside `A-Z a-z 0-9 . _ -` becomes `_` and a short hash is appended, so `a/b` and `a_b` stay different.
- A leading dot cannot reach a parent folder.
- For ordinary ids such as `webwatcher.email` and `bell` the folder and the file are exactly those names.

Two kinds of file live in an app's folder:

| Kind | Made by | Referenced with |
|---|---|---|
| A copy of a file the app's manifest declares, named `<asset id>.riv`. | Herald, when the manifest is saved. | `asset` |
| A file you or an upload put there. | You, the Designer's **Add...** button, or an upload. | `path` with the file name |

Copies keep a banner playing after the issuing app moves or deletes its own files. Nothing else is cached on disk.
Deleting a manifest removes the copies of the assets it declared and leaves the other files.

The folder holds at most 32 `.riv` files, whichever way they arrived.

## Getting a file into Herald

There are four ways to store an animation. Pick the one that matches who owns the file: an app ships its animation in
its manifest, a person uses the Designer, and an agent or script uploads. All of them end with the file in the
[app's folder](#where-the-files-live).

| Way | Best for | Referenced with |
|---|---|---|
| [Upload](#upload-from-a-script-or-an-agent) | Agents, scripts and the CLI. | `path` with the file name |
| [Manifest asset](#declare-it-in-the-manifest) | An app that ships its own animation. | `asset` with the asset id |
| [Designer](#add-it-in-the-designer) | Someone designing a template by hand. | `asset` or `path`, chosen for you |
| [Copy by hand](#copy-it-by-hand) | Quick experiments. | `path` with the file name |

### Upload from a script or an agent

Uploading copies a `.riv` file into the app's folder and returns the component to use. Send the path of a file on
this Mac, or the file's bytes encoded as base64 (the request body is limited to 1 MB, so use a path for anything
larger). Herald checks the name, the size and the 32-file limit, and it replaces a file of the same name.

```sh
herald assets add --app example.bidbot --file ~/Animations/bell.riv
```

```json
{"ok": true, "kind": "rive", "app": "example.bidbot", "id": "bell", "file": "bell.riv",
 "path": "/Users/you/Library/Application Support/Herald/assets/example.bidbot/bell.riv",
 "bytes": 18432, "replaced": false, "component": {"type": "rive", "path": "bell.riv"}}
```

The `component` value in the reply is ready to paste into a template cell. Storing and managing files has one
command, route and tool for each job:

| Job | CLI | HTTP | MCP tool |
|---|---|---|---|
| Store a file. | `herald assets add` | [`POST /v1/assets`](api/assets.md#post-v1assets) | [`upload_asset`](mcp/templates.md#upload_asset) |
| List the stored files, the templates that use each and whether the manifest declares it. | `herald assets list --app example.bidbot` | [`GET /v1/assets`](api/assets.md#get-v1assets) | [`list_assets`](mcp/templates.md#list_assets) |
| Remove a file. The reply names the templates that still reference it. | `herald assets rm --app example.bidbot --file bell.riv` | [`DELETE /v1/assets`](api/assets.md#delete-v1assets) | [`delete_asset`](mcp/templates.md#delete_asset) |

### Declare it in the manifest

An app that ships its own animation lists it in its [manifest](manifests.md) as an asset. Herald copies each asset
into the app's folder as `<asset id>.riv` when the manifest is saved, and templates refer to it by id. One bad asset
is reported and never blocks the manifest: the banner shows the reason where the animation would be.

```json
{"app": "example.bidbot", "appName": "BidBot", "version": 1,
 "fields": [{"key": "title", "type": "text", "sample": "Bid accepted"},
            {"key": "count", "type": "number", "sample": 2},
            {"key": "url", "type": "url"}],
 "assets": [{"id": "bell", "type": "rive", "path": "~/Animations/bell.riv",
             "stateMachine": "Main", "inputs": ["count", "hover"]}]}
```

```sh
curl -s -X PUT "$HERALD/v1/manifest" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  --data @manifest.json
```

This is [`PUT /v1/manifest`](api/manifests.md#put-v1manifest), also available as the MCP tool
[`put_manifest`](mcp/templates.md#put_manifest). An asset has these rules:

| Part | Rule |
|---|---|
| `id` | Letters, digits, `_`, `.` and `-`, unique in the manifest. A component's `asset` names it. |
| `type` | Must be `rive`. Any other value is refused with `asset type "x" is not supported (only rive)`. |
| `path` | An absolute path, a `~/` path, a `file://` URL, or a name relative to the app's folder. At most 2048 bytes. A remote URL is refused. |
| `stateMachine` | Optional. The state machine a component plays when it names none. |
| `inputs` | Optional. The input names the file has. The validator warns when a component binds a name that is not listed. |

Saving the manifest again refreshes the copy only when the file's content changed. If the source file later
disappears, the earlier valid copy keeps playing.

### Add it in the Designer

In the [Designer](../AUTHORING.md), the **Assets** palette lists the app's `.riv` files, each with a live preview.

- **Add...** opens a file panel and copies the chosen file into the app's folder, taking the id from the file name and making it unique.
- **Remove...** deletes a file after asking you to confirm.
- Drag a file onto the canvas, or click it, to place a `rive` component in the selected slot.

A file the manifest declares is placed by `asset`, with its state machine. A file you added is placed by `path`, with its file name.

Select a `rive` cell to open its inspector, which has these controls:

| Control | What it sets |
|---|---|
| **Asset** | A manifest asset, or **A file...** to name a file. |
| **File** | The `path`, with a menu of the stored files. Shown for **A file...**. |
| Summary line | What the Rive runtime read: artboards, state machines and inputs with their kinds. |
| Artboard and state machine pickers | `artboard` and `stateMachine`. The first choice is the file's default. |
| **Inputs** | `inputBindings`, with the file's inputs suggested and `hover` and `pressed` offered. |
| **Loop** | `loop`: **Loop**, **Once** or **Animation's own**. |
| **Ratio** | `aspectRatio`. The placeholder shows the artboard's own ratio. |
| **Height** | `height`. |
| Action | The click action: none, one from the list, or one of its own. |

**Import...** and **Export...** at the top of the Designer move a template with its animations as a
[bundle](#packaging-with-a-template-heraldtemplate).

### Copy it by hand

Copy the file into `~/Library/Application Support/Herald/assets/<app>/` and reference it with a relative `path`:

```json
{"type": "rive", "path": "spinner.riv", "height": 24}
```

## Referencing a file from a template

A `rive` component names its file with either `asset` or `path`. They resolve differently, so choose by how long the
file must live and where the template will travel. This section tells you what each one finds.

| Reference | Resolves to | Use it for |
|---|---|---|
| `"asset": "bell"` | The manifest asset `bell` is installed again if its source changed, and the stored copy plays. | Anything shared. It survives the app moving its file, picks up a changed source and travels in a bundle. |
| `"path": "spinner.riv"` | `<app>/spinner.riv` in the app's folder, checked and not copied. | A file stored by hand, by an upload or by the Designer. |
| `"path": "/abs/file.riv"`, `"~/file.riv"` or a `file:` URL | That file, checked and not copied. | Local experiments. The template breaks on another Mac. |

If both `asset` and `path` are set, `asset` is used and `path` is ignored. Asset ids match exactly.

For an `asset`, Herald looks in this order:

1. The manifest asset of that id. It is installed, and if that fails but an earlier copy is still valid, the copy is
   used.
2. The stored copy `<id>.riv` in the app's folder, when no manifest declares the id.
3. Otherwise the component shows `asset "x" is not declared by the manifest and is not installed`.

A template that uses `asset` for an id its manifest does not declare still plays when the stored copy exists, but
validation warns `the manifest declares no asset 'x'`. For a file you uploaded, use `path` with its file name.

The full list of properties is in [the `rive` component reference](components/rive.md).

## Inputs and how fields drive them

`inputBindings` connects a state machine input to a piece of the notification, so the animation follows the data.
Each entry maps an input name to a binding. This section explains what a binding can be and what value each kind of
input receives.

```json
{"type": "rive", "asset": "bell", "height": 40,
 "inputBindings": {"count": "{count}", "isUnread": "{unread}", "ring": "{count}",
                   "hover": "hover", "pressed": "pressed"}}
```

The key is the name of the input in the Rive file. The value is the binding:

| Binding | Value written |
|---|---|
| `hover` or `pressed`, in any case. | Driven by the pointer, never by data. |
| A single token such as `"{count}"`. | The field's own value, so a number stays a number and a list stays a list. |
| Anything else, such as `"3"` or `"{n} new"`. | The substituted text. |
| Tokens that are all absent or blank. | Nothing. The input keeps whatever the animation set. |

How each kind of input reads the value it is given:

| Input | From a number | From a Boolean | From text | From a list |
|---|---|---|---|---|
| Number | The number. | 1 or 0. | The number if the text parses, else ignored. | Its length. |
| Boolean | True when not zero. | The value. | False only for empty, `false`, `no`, `off` or `0` in any case. | True when not empty. |
| Trigger | Fires when not zero. | Fires when true. | Fires unless the text is empty, `false`, `no`, `off` or `0`. | Fires when not empty. |

Two behaviours are worth knowing before you design a trigger:

- **Only changed values are written.** Herald remembers what it last wrote to each input, so a redraw from hover or a
  timer never fires a trigger again. A trigger bound to `{count}` fires when the count changes to a truthy value, so
  a banner updated under the same `id` (count 2, then 3) rings again.
- **The first value counts.** Inputs are written as soon as the animation loads. A trigger bound to a field that is
  truthy on the first notification fires once when the banner appears.

The tokens come from the notification's fields. [Bindings](bindings.md) explains token syntax.

## Sizing and fit

The animation always fills its box with `contain` fit and is centred, so the box decides what you see. This section
shows which settings choose the box.

| Setting | Effect |
|---|---|
| `height` in points | A fixed box height. The width is the height times the ratio. |
| `aspectRatio` | Width divided by height of the box. It defaults to the artboard's own ratio, or 4 to 1 when the artboard size is unknown. |
| Neither | The box takes the width of its cell, with the height from the ratio. If the cell proposes nothing at all, the artboard's own size is used. |

The box is limited to 1 to 2000 points on each side. A placeholder for a failed load is 44 points high. To avoid empty
bands, give the box the artboard's ratio: leave out `aspectRatio` and the artboard's own ratio is used. Where the
box sits inside its cell is set by the cell's alignment, described with the
[nine-point alignment](components/rive.md) of the component and in
[Grid and layout](grid-and-layout.md).

## Packaging with a template (`.heraldtemplate`)

A bundle is one file that carries a template together with the Rive files it plays, so a template moves between Macs
without breaking. Use it to share a design, back it up or move it to another app.

A bundle is a zip archive with this layout:

```text
bundle.json          the format name, the template's name and app, and the list of asset files
template.json        the template, as the template store writes it
assets/<file>.riv    every Rive file a rive component of the template plays
```

Export and import are available in the Designer (**Export...** and **Import...**), on the command line, over HTTP and
as MCP tools:

```sh
herald template export --app example.bidbot --name bid-bell --out bid-bell.heraldtemplate
herald template import bid-bell.heraldtemplate --app example.bidbot --keep-both
```

The command line and the endpoints are documented in [the CLI reference](cli.md#herald-template-export) and in
[Templates API](api/templates.md#get-v1templatesexport). The MCP tools are
[`export_template_bundle`](mcp/templates.md#export_template_bundle) and
[`import_template_bundle`](mcp/templates.md#import_template_bundle).

What export does with the animations:

- An `asset` id packs the stored copy, or if there is none the file the manifest names, as `<id>.riv`.
- A loose `path` file is packed under a free file name, and the template's `path` is rewritten to that name.
- A file that cannot be found is a warning, not an error, so a template whose animation moved can still be shared.
- Scripts and Shortcuts are not packed. The export warns about each one, because they must exist on the other Mac.

What import does:

- It checks the template, then writes the Rive files into the target app's folder.
- A file already there with the same bytes is reused. A different file under the same name is written as `name-2.riv`
  and the template's references are rewritten, so another template's animation never changes.
- `--app` retargets the template to another app. When the template's name is taken, `--keep-both` (the default)
  saves it under a new name, `--replace` overwrites and `--fail` stops.
- A template that references an `asset` still plays on a Mac whose manifest does not declare it, because the stored
  copy `<id>.riv` answers.

The archive must follow these rules, which a Finder archive already does:

| Rule | Value |
|---|---|
| Compression | Stored or deflate. No zip64, no encryption. |
| Entries | At most 80, each at most 10 MB, 64 MB in total. |
| `template.json` | At most 2 MB. |
| Names | A name that climbs out of the archive is rejected. A wrapper folder and `__MACOSX` entries are accepted. |

## When the file is missing or broken

The component never throws and never crashes the banner. When it cannot play the file, it draws a dashed rounded
box with a warning icon and the reason, and shows the same reason as a tooltip. The rest of the banner is
unaffected. Use this table to read the message.

| Text in the placeholder | Cause | Fix |
|---|---|---|
| `the Rive component has no asset or path` | Neither `asset` nor `path` is set. | Set one of them. |
| `asset "bell" is not declared by the manifest and is not installed` | The manifest has no asset `bell` and `<app>/bell.riv` does not exist. | Save the manifest with the asset, or upload the file. |
| `file not found: <path>` | The path does not exist. | Fix the path, or copy the file into the app's folder. |
| `"x.riv" is not a .riv file` | The extension is wrong. | Use a file that ends in `.riv`. |
| `"x.riv" is not a regular file` | The path is a folder or another kind of item. | Point at the file. |
| `"x.riv" is empty` | The file has no bytes. | Export it again from Rive. |
| `"x.riv" is 12 MB; Rive assets are limited to 10 MB` | The file is too big. | Make the animation smaller. |
| `remote assets are not supported: https://...` | The path is a URL. | Download the file and reference it. |
| `a relative asset path cannot leave the app's assets folder` | The path contains `..`. | Use a name inside the folder. |
| `asset type "x" is not supported (only rive)` | The manifest asset's `type` is not `rive`. | Set `"type": "rive"`. |
| `an app can have at most 32 animation assets` | The folder holds 32 files. | Remove files you do not use. |
| `could not copy the asset: ...` | The copy into the folder failed. | Check the source file and the disk. |
| `no artboard "X" (available: ...)` | The artboard name is wrong. | Use one of the listed names. |
| `no state machine "X" (available: ...)` | The state machine name is wrong. | Use one of the listed names. |
| `the file has no state machine or animation` | The artboard is empty. | Add a state machine or an animation. |
| A message from the Rive runtime. | The file is not a valid or supported `.riv`. | Export it again with a runtime-compatible editor. |

Herald prints names in these messages with curly quotes. A static preview from `POST /v1/preview` or the MCP tool
`render_preview` also draws a dashed box with the asset name for a working Rive component. That box is a stand-in, not
an error, because previews cannot draw Rive.

## Testing without a window

A check loads the component in the same view a banner uses, with no window, and reports what it found. Use it to
confirm that the file loads, that your input names are right and that a click runs the action you expect. Nothing is
shown, stored or executed.

The check is [`POST /v1/rive/check`](api/diagnostics.md#post-v1rivecheck), also available as the MCP tool [`rive_check`](mcp/templates.md#rive_check). You send the app and the component. Optionally you send sample field values, and pointer steps to run in order: `hoverIn`, `pressDown`, `pressUp` and `hoverOut`.

```sh
curl -s -X POST "$HERALD/v1/rive/check" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"app": "example.bidbot",
       "component": {"type": "rive", "asset": "bell", "stateMachine": "Main",
                     "inputBindings": {"count": "{count}", "hover": "hover"},
                     "actionRef": "markRead"},
       "fields": {"count": 3},
       "simulate": ["hoverIn", "pressDown", "pressUp", "hoverOut"]}'
```

```json
{"loaded": true,
 "inputs": {"count": "number", "hover": "bool"},
 "applied": {"count": "3.0"},
 "artboards": [{"name": "Bell", "width": 64, "height": 64, "defaultMachine": "Main",
                "machines": [{"name": "Main", "inputs": [{"name": "count", "kind": "number"},
                                                         {"name": "hover", "kind": "bool"}]}],
                "animations": []}],
 "takesClicks": true,
 "pointerWrites": {"hover": "false"},
 "clickedActions": ["markRead"]}
```

How to read the reply:

- `loaded` is `true` when the animation plays. Otherwise `error` holds the placeholder text from the table above.
- `inputs` lists the inputs Herald found, by name and kind. Compare it with your `inputBindings` keys.
- `applied` shows the values your fields wrote. An input missing here received nothing.
- `takesClicks` is `true` when the animation captures clicks instead of passing them to the banner.
- `clickedActions` names the actions a simulated press and release would run. The action is reported, not run.

The [Designer snapshot](api/diagnostics.md#get-v1designersnapshot) draws the Designer offscreen, and Rive cells are
stand-ins there too. To see the real animation, send a test banner with `send_test` or `herald notify`.

## Worked example: a bell that rings on new mail

This example builds a bell that rings each time the unread count goes up and reacts to the mouse. It uses the
fictional app `example.bidbot` and runs end to end: make the file, store it, check it, design the template and send
two notifications.

**1. In Rive.** Build the file:

- Make an artboard named `Bell`, 64 x 64, with a transparent background.
- Add a state machine `Main` with a Number input `count`, a Boolean input `hover` and a Trigger `ring`.
- Add a "ring" state that plays when `ring` fires or when `hover` is true.
- Export `bell.riv` with its assets embedded.

**2. Store it.** Declare the file in the manifest with the asset example from
[Declare it in the manifest](#declare-it-in-the-manifest), setting `inputs` to `["count", "ring", "hover"]`, and save
the manifest. Herald copies the file to `assets/example.bidbot/bell.riv`.

**3. Check it.** Run the request from [Testing without a window](#testing-without-a-window) with
`"inputBindings": {"count": "{count}", "ring": "{count}", "hover": "hover"}`. Expect `loaded` to be `true` and your
three inputs in `inputs`. Fix names until `applied` shows what you expect.

**4. Write the template.** The bell sits in a 48-point column. A text cell, a badge and an action row complete the
banner:

```json
{"name": "bid-bell", "app": "example.bidbot", "layoutVersion": 2, "collapseEmpty": true,
 "grid": {"rows": 3, "cols": 3, "rowSizes": ["auto", "auto", "auto"],
          "colSizes": ["48", "fill", "auto"], "gap": 8, "padding": 14, "width": 400},
 "cells": [
  {"id": "bell", "row": 0, "col": 0, "rowSpan": 2, "align": "topLeading",
   "component": {"type": "rive", "asset": "bell", "stateMachine": "Main", "height": 40,
                 "inputBindings": {"count": "{count}", "ring": "{count}", "hover": "hover"},
                 "action": {"id": "open", "label": "Open", "kind": "url", "url": "{url}"}}},
  {"id": "title", "row": 0, "col": 1,
   "component": {"type": "text", "binding": "{title}", "style": "title", "maxLines": 2}},
  {"id": "count", "row": 0, "col": 2, "align": "topTrailing",
   "component": {"type": "badge", "binding": "{count}", "color": "#FF3B30"}},
  {"id": "subject", "row": 1, "col": 1, "colSpan": 2,
   "component": {"type": "text", "binding": "{subject}", "style": "subtitle", "maxLines": 2}},
  {"id": "acts", "row": 2, "col": 0, "colSpan": 3,
   "component": {"type": "actions", "source": "merged", "layout": "wrap"}}]}
```

**5. Preview and send.** `render_preview` shows a stand-in where the bell is. `send_test` or `herald notify` shows
the real banner. Send the same `id` twice with a higher `count` the second time, and the bell rings again:

```sh
herald notify --app example.bidbot --id inbox --template bid-bell --title "2 new bids" \
  --metadata '{"count": 2, "subject": "Acme RFP", "url": "https://example.com/bids"}'
herald notify --app example.bidbot --id inbox --template bid-bell --title "3 new bids" \
  --metadata '{"count": 3, "subject": "Acme RFP, revised", "url": "https://example.com/bids"}'
```

The first banner rings once on appearance, because `ring` is bound to a count that is already truthy. The second
replaces the first in place, and `ring` fires again because the value changed from 2 to 3.

## Troubleshooting

Start with a [check](#testing-without-a-window): its `loaded`, `inputs` and `applied` answer most of these.

| Symptom | Likely cause | What to do |
|---|---|---|
| A dashed box with a message. | The file did not load. | Read the message in [the table above](#when-the-file-is-missing-or-broken) and run a check. |
| The animation plays but never reacts to fields. | The input name has the wrong case, or is not an input of that state machine. | Compare the check's `inputs` with your keys. A wrong name is skipped silently. |
| It reacts to the first notification only. | The same value was written again, and unchanged values are not written. | A trigger fires when the value changes. Send a different value, or bind a counter. |
| A trigger fires when the banner appears. | The bound field is truthy at load. | This is expected. Bind a field that is absent on the first notification, or use a Boolean. |
| An input keeps its old value when a field disappears. | An absent token leaves the input alone. | Send an explicit `0` or `false`, or bind a field that is always sent. |
| Hover does nothing. | No input is bound to `hover`, or the input name differs from the key. | Write `"<input name>": "hover"`. The key is the input name and the value is the keyword. |
| Hover works but a Rive pointer-enter listener does not. | Pointer move is not passed to Rive. | Use the `hover` input. |
| Clicking the animation opens the notification instead of running the action. | There is no `action` or `actionRef`, or the action id is hidden. | Add one and check that `takesClicks` is `true`. |
| The animation looks letterboxed. | The box has another ratio than the artboard. | Leave out `aspectRatio`, set it to the artboard's ratio, or resize the artboard. |
| It is too small or cut off. | A fixed row is smaller than the box, or `height` is larger than the row. | Use an `auto` row or a smaller `height`. |
| It works in the Designer but not after export and import. | The template uses an absolute `path`. | Use `asset` ids or a relative `path`. Export rewrites loose paths. |
| `render_preview` shows a stand-in. | Offscreen renders cannot draw Rive. | Use `send_test` or a check. |
| The banner is slow to appear. | The file is large, or hosted assets are being fetched. | Make the file smaller and embed its assets. |
| The manifest saved but the animation is missing. | The asset path is unreadable or over 10 MB. | Fix the file and save the manifest again. Herald's log names the asset and the reason. |
| A replaced file is not picked up. | The bytes did not change, or the template uses a `path` to a copy. | Save the manifest again. An `asset` reference installs again when the source changed. |

## Related

- [The `rive` component](components/rive.md): every property, with examples.
- [Assets API](api/assets.md): upload, list and delete animations and images.
- [Diagnostics API](api/diagnostics.md#post-v1rivecheck): `POST /v1/rive/check`.
- [Templates API](api/templates.md): bundle export and import.
- [Manifests](manifests.md): declaring assets.
- [Bindings](bindings.md): tokens and how fields reach components.
- [Design a banner in the Designer](../AUTHORING.md): the Assets palette and the Rive inspector.
- [Symbols](symbols.md): SF Symbols, the other way to add motion.
