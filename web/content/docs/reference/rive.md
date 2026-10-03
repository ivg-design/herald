# Rive in Herald

How to prepare a `.riv` file, get it into Herald, wire it to notification fields and the mouse, and find out why
it does not play. The property reference for the component is [components/rive.md](components/rive.md).

Everything here comes from the code that plays animations (`RiveComponentView`, `AssetStore`,
`HeraldTemplateBundle`, the Rive Apple runtime `RiveRuntime`). Where the code does not decide something it
says **TBD - verify**.

## What Herald does with a Rive file

A `rive` component hosts one artboard of a `.riv` file in a banner cell. Herald:

1. Loads the file with `RiveFile(data:, loadCdn: true)` and picks an artboard and a state machine.
2. Plays the state machine with `fit: contain`, centred, auto-playing.
3. Writes the state machine's **inputs** (Number, Boolean, Trigger) from the notification's fields, and from the
   mouse (`hover`, `pressed`).
4. Optionally maps a click on the animation to an action.

What it does not do (there is no code path for any of these):

| Not supported | Instead |
|---|---|
| Rive data binding (view models, view model properties, data-bound text) | Drive the animation with state machine inputs. A file that uses data binding still loads; whether its default view model instance plays correctly is **TBD - verify** with your Rive runtime version (the Swift package pins `rive-ios` 6.28.0). |
| Text runs set from a field | Put the text in a Text component of the banner next to the animation. **TBD - verify** whether `RiveRuntime` 6.28 would allow a `setTextRunValue` hook; Herald does not call it. |
| Rive events (`RiveEvent`) | Not observed. Use a click action. |
| Audio | Not wired (**TBD - verify**: audio events inside the runtime). |
| Remote `.riv` URLs | Refused: `remote assets are not supported`. Download it and reference the file. |
| Several artboards at once | One component plays one artboard. Use several components. |

## Preparing the file in the Rive editor

### Artboard

- **Name** it something short and stable (`Bell`). Herald plays the file's default (first) artboard unless the
  component sets `artboard`. The name is case-sensitive.
- **Size and ratio.** The animation is drawn with `contain`: the whole artboard is visible and letterboxed
  when the box has another ratio. Make the artboard's ratio equal to the box you will give it, and Herald needs
  no `aspectRatio` at all. Recommended: square artboards of 64 x 64 or 128 x 128 for icon-sized animations
  (the box is typically 24 to 48 points high); 400 x 120 style artboards for a banner-wide strip.
- **Background.** Banners are drawn on the system material (translucent). Keep the artboard background
  transparent, and avoid a full-bleed shape unless you want a card inside the card.
- **Light and dark.** The file is drawn as is in both. Pick colours that work on both, or add a boolean input
  your template binds to a field.
- **Fit.** The artboard is always scaled with `contain` and centred; Herald does not resize the artboard
  to the box (**TBD - verify** how Rive "Layout" / responsive artboards behave under `contain`).

### State machine

- Create a state machine and **name** it (`Main`). Mark it as the default if the artboard has several: Herald
  picks, in order, the component's `stateMachine`, the manifest asset's `stateMachine`, the artboard's default
  state machine, then the first one.
- A file with **no state machine** but a linear animation plays the first animation; `loop: true/false` picks
  looping or play once. If the file has neither, the component shows `the file has no state machine or animation`.
- A named state machine that does not exist is an error, with the available names in the message.

### Inputs

Herald supports the three input types the runtime exposes:

| Rive input | Herald detects it as | Written with |
|---|---|---|
| Number | `number` | a number (a boolean becomes 1/0, numeric text is parsed, a list becomes its length) |
| Boolean | `bool` | truthiness of the value |
| Trigger | `trigger` | fired when the bound value changes to something truthy |

Inputs are found **by name, case-sensitively**. An `inputBindings` entry whose name is not an input of the
state machine is ignored without an error, so a typo in the name is silent: use `POST /v1/rive/check` and read
`inputs` to see what Herald found.

Name inputs after what the field means, not after how it looks: `count`, `isUnread`, `ring`, `progress`.

### Hover, pressed, click and visibility

| You want | In Rive | In the template |
|---|---|---|
| React to the mouse entering the animation | Boolean (or Number, or Trigger) input, e.g. `hover`, used in transitions | `"inputBindings":{"hover":"hover"}` |
| React to a press | Boolean input `pressed` | `"inputBindings":{"pressed":"pressed"}`; the animation then takes clicks |
| Open or run something when it is clicked | nothing | `action` or `actionRef` on the component |
| Show it only when a field is present | nothing | not possible: a `rive` cell is never empty (it always has an `asset` or `path`), so it is always drawn. Use a separate template for the case, or make the state machine's idle state invisible and bind an input to the field |

Pointer behaviour in detail, from the code:

- A Boolean input bound to `hover` follows the pointer (`true` while inside). A Number input gets 1 or 0. A
  Trigger fires when the pointer enters.
- `pressed` works the same way with the mouse button; leaving while pressed releases it.
- Hover tracking works in the non-activating banner panel (it uses an `NSTrackingArea` with `activeAlways`),
  so it never takes focus.
- Mouse **down, drag and up** are forwarded to Rive, so state machine pointer **listeners** for press / drag /
  release work. Pointer **move** events are not forwarded: do not rely on a Rive "pointer enter/exit/move"
  listener, use the `hover` input instead.
- Without `action`, `actionRef` or a `pressed` binding the animation is invisible to mouse clicks so the banner
  body keeps its own click (open the notification's `url`).

### Out-of-band assets (images, fonts)

Herald loads the file with `loadCdn: true`. Assets embedded in the `.riv` always work. Assets the file marks as
referenced/CDN-hosted are fetched from the network by the Rive runtime when the animation loads. For a banner
that must work offline and instantly, embed them in Rive ("Embed" in the asset's export settings). The
Designer's inspector reads files with `loadCdn: false` (names and inputs only).

### File size and count

| Limit | Value |
|---|---|
| File name | must end in `.riv` (any case); symlinks are followed but both names must end in `.riv` |
| Size | 1 byte to **10 MB** (`Rive assets are limited to 10 MB`) |
| Copies per app | **32** installed copies (hand-dropped files do not count toward it) |
| Assets per manifest | 32 |
| Files in a template bundle | 32, 10 MB each, 64 MB in total |

Keep banner animations small: they load on every banner that shows them and a 10 MB limit is a ceiling, not
a target. Under 100 KB is typical for icon-sized work.

## Where the files live

```
~/Library/Application Support/Herald/assets/<app>/<asset id>.riv
```

`<app>` and `<asset id>` are reduced to one safe path component: characters outside `A-Z a-z 0-9 . _ -` become
`_` and a short hash is appended so `a/b` and `a_b` differ; a leading dot cannot address a parent folder. For
ordinary ids (`webwatcher.email`, `bell`) the folder and file are exactly those names.

Two kinds of file live in an app's folder:

1. **Copies of the issuer's manifest assets**, named `<asset id>.riv`, made by Herald so a banner keeps
   playing after the issuer moves or deletes its own bundle.
2. **Files you put there yourself**, which a template references with a relative `path`
   (`"path":"spinner.riv"`).

Nothing else is cached on disk. Deleting the manifest removes the copies of the assets it declared (files you
dropped there stay).

## Getting a file into Herald

There is no endpoint that accepts raw `.riv` bytes: the HTTP API, the MCP and the CLI all point Herald at a file
on this Mac, and Herald copies it. Herald is not sandboxed, so any path it can read works.

### 1. Through the manifest (API or MCP)

Declare the file as an asset of the issuer:

```json
{"app":"webwatcher.email","appName":"WebWatcher - Email","version":1,
 "fields":[{"key":"title","type":"text","sample":"2 new from Acme Billing"},
           {"key":"count","type":"number","sample":2},
           {"key":"subject","type":"text","sample":"Invoice #4021"},
           {"key":"url","type":"url"}],
 "actions":[{"id":"markRead","label":"Mark as Read","kind":"callback"}],
 "assets":[{"id":"bell","type":"rive","path":"/Users/me/Animations/bell.riv",
            "stateMachine":"Main","inputs":["count","hover"]}]}
```

```sh
D="$HOME/Library/Application Support/Herald"
BASE="http://127.0.0.1:$(cat "$D/port")"; AUTH="Authorization: Bearer $(cat "$D/token")"
curl -s -X PUT -H "$AUTH" -H 'Content-Type: application/json' --data @manifest.json $BASE/v1/manifest
```

or the MCP tool `put_manifest {"manifest": {...}}`. On `PUT /v1/manifest` Herald immediately copies every
asset to `assets/<app>/<id>.riv`; a bad asset is logged and never blocks the manifest (the banner shows the
reason where the animation would be).

Asset fields:

| Field | Required | Meaning |
|---|---|---|
| `id` | yes | Letters, digits, `_`, `.`, `-`; unique in the manifest. This is what a component's `asset` names. |
| `type` | yes | `"rive"` (anything else: `asset type "x" is not supported (only rive)`). |
| `path` | yes | An absolute path, a `~/` path, a `file://` URL, or a name relative to the app's assets folder. Remote URLs are refused. At most 2048 bytes. |
| `stateMachine` | no | The state machine a component plays when it names none. |
| `inputs` | no | The input names the file has; the validator warns when a component binds a name that is not listed. |

Re-sending the manifest refreshes the copy only when the content changed. If the source file later vanishes,
the earlier valid copy keeps playing.

### 2. In the Designer

Open the Designer for the issuer (menu bar > Design Template):

- **Assets** palette: lists the issuer's `.riv` files, each with a live preview. **Add...** opens a file panel,
  copies the file into the assets folder (`<id>.riv`, with the id taken from the file name and made unique) and
  Remove deletes one. Drag a file onto the canvas, or click it, to place a `rive` component in the selected
  slot. A file the manifest declares is placed by `asset` (with its state machine); a hand-added file by `path`
  (its file name).
- **Rive inspector** (select a `rive` cell): Asset picker (or "A file..." with a path field and a menu of the
  stored files), a summary of what the Rive runtime read (artboards, state machines, inputs and their kinds),
  Artboard and State machine pickers, an Inputs editor with the file's inputs suggested and `hover` / `pressed`
  buttons, Loop, Ratio (placeholder shows the artboard's ratio), Height and the click action.
- **Import... / Export...** of `.heraldtemplate` bundles (below).

### 3. By hand

Copy the file to `~/Library/Application Support/Herald/assets/<app>/` and reference it with a relative
`path`:

```json
{"type":"rive","path":"spinner.riv","height":24}
```

## Referencing a file from a template

| Reference | Resolves to | Use it for |
|---|---|---|
| `"asset":"bell"` | The manifest asset `bell` is (re)installed and the stored copy `assets/<app>/bell.riv` plays. Without a manifest only an already stored copy can answer. | Everything shared: it survives the issuer moving its file, it picks up a changed source file, and it travels in a bundle. |
| `"path":"spinner.riv"` | `assets/<app>/spinner.riv`, validated, not copied. | A file you put there by hand. |
| `"path":"/abs/or/~/file.riv"` or `file:` URL | That file, validated, **not copied**. | Local experiments; the template breaks on any other Mac. |

If both are set, `asset` wins and `path` is ignored. `asset` ids are matched exactly.

Resolution order for `asset`: manifest asset found (install it; if that fails but an earlier copy is valid, use
the copy) -> else stored copy `<id>.riv` -> else `asset "x" is not declared by the manifest and is not
installed`.

## Inputs and how fields drive them

`inputBindings` maps an **input name** to a **binding**:

```jsonc
// a fragment of a rive component
"inputBindings":{"count":"{count}","isUnread":"{unread}","ring":"{count}","hover":"hover","pressed":"pressed"}
```

Binding value rules (`RiveInputBinding`):

| Binding | Value written |
|---|---|
| `hover` or `pressed` (any case) | Driven by the pointer, never by data. |
| A single token, `"{count}"` | The field's own value, so a number stays a number, a list stays a list. |
| Anything else, `"3"`, `"{n} new"` | The substituted text. |
| Tokens that are all absent or blank | **Nothing is written.** The input keeps whatever the animation set. |

How each input kind reads the value:

| Input kind | Number value | Boolean value | Text value | List value |
|---|---|---|---|---|
| Number | as is | 1 / 0 | parsed if numeric, else ignored | its length |
| Boolean | non-zero is true | as is | false only for empty, `false`, `no`, `off`, `0` (any case) | true when not empty |
| Trigger | fires when non-zero | fires when true | fires unless empty, `false`, `no`, `off`, `0` | fires when not empty |

Two properties worth knowing:

- **Only changed values are written.** Herald remembers what it last wrote to each input, so a redraw (hover, a
  timer) never re-fires a trigger. A trigger bound to `{count}` fires when the count **changes to a truthy
  value**: a banner updated under the same `id` (count 2 to 3) rings again.
- **First application fires too.** Inputs are applied as soon as the animation loads, so a trigger bound to a
  field that is truthy on the first notification fires once on appearance.

## Sizing and fit

| Setting | Effect |
|---|---|
| `height` (points) | Fixed box height. Width = `height` x ratio. |
| `aspectRatio` | Box width / height; the artboard's own ratio when omitted (4:1 if the artboard size is unknown). |
| neither | Width of the cell, height from the ratio. If nothing at all is proposed, the artboard's own size is used. |

The animation fills the box with `contain` and is centred; the box is clamped to 1 to 2000 points per side. A
failed load is 44 points high. See the nine-point alignment note in [components/rive.md](components/rive.md).

## Packaging with a template (`.heraldtemplate`)

A bundle is a zip with one template and the Rive files it plays:

```
bundle.json          {"format":"heraldtemplate","version":1,"app":"...","name":"...","createdAt":"...","assets":["bell.riv"]}
template.json        the template, as the template store writes it
assets/<file>.riv    every Rive file a rive component of the template plays
```

- **Export**: Designer's Export..., or `herald template export --app webwatcher.email --name email-accumulated
  [--out file.heraldtemplate]`. Asset ids pack the stored copy (else the file the manifest names) as
  `<id>.riv`; loose `path` files are packed under a free file name and the template's `path` is rewritten to
  that name. A file that cannot be found is a **warning**, not an error. Scripts and Shortcuts are not packed;
  the export warns about them.
- **Import**: Designer's Import..., or `herald template import file.heraldtemplate [--app ID]
  [--keep-both | --replace | --fail]`. The template is validated, its Rive files go into
  `assets/<app>/` **without replacing a different file already there** (a different file under the same name is
  written as `name-2.riv` and the template's references are rewritten, so another template's animation never
  changes), and the template is saved. `--app` retargets it to another issuer.
- Zip rules: stored or deflate only, no zip64, no encryption; names that climb out of the archive are rejected;
  at most 80 entries, 10 MB per entry, 64 MB total; the template is at most 2 MB. Finder's Compress archives
  (a wrapper folder, `__MACOSX`) are accepted.
- After import with an `asset` reference, the manifest on the new Mac may not declare the asset: the stored copy
  still plays because resolution falls back to `assets/<app>/<id>.riv`.

## When the file is missing or broken

The component never throws and never crashes the banner. It draws a dashed rounded box with a warning icon and
the reason (also as the tooltip); the rest of the banner is unaffected.

| Text in the placeholder | Cause | Fix |
|---|---|---|
| `the Rive component has no asset or path` | Neither `asset` nor `path` set. | Set one. |
| `asset "bell" is not declared by the manifest and is not installed` | The manifest has no asset `bell` and `assets/<app>/bell.riv` does not exist. | `PUT /v1/manifest` with the asset, or copy the file. |
| `file not found: <path>` | The path does not exist. | Fix the path; copy it into the assets folder. |
| `"x.riv" is not a .riv file` | Wrong extension. | Use a `.riv`. |
| `"x.riv" is empty` | Zero-byte file. | Re-export. |
| `"x.riv" is 12 MB; Rive assets are limited to 10 MB` | Too big. | Optimise the file. |
| `remote assets are not supported: https://...` | A URL. | Download and reference the file. |
| `a relative asset path cannot leave the app's assets folder` | `..` in a path. | Use a name inside the folder. |
| `asset type "x" is not supported (only rive)` | Manifest asset `type` is not `rive`. | Set `"type":"rive"`. |
| `an app can have at most 32 animation assets` | Folder holds 32 copies. | Remove unused files. |
| `no artboard "X" (available: ...)` | Wrong artboard name. | Use a listed name. |
| `no state machine "X" (available: ...)` | Wrong state machine name. | Use a listed name. |
| `the file has no state machine or animation` | Empty artboard. | Add a state machine or an animation. |
| a runtime error from `RiveFile` | Not a valid or supported `.riv`. | Re-export with a runtime-compatible editor version. |

In a static preview (`POST /v1/preview`, `render_preview`) a *working* Rive component also shows a dashed
placeholder with the asset name; that is not an error.

## Testing without a window

`POST /v1/rive/check` loads the component in the same host view a banner uses, with no window, and reports
what it found. Nothing is shown or stored.

```sh
curl -s -X POST -H "$AUTH" -H 'Content-Type: application/json' $BASE/v1/rive/check -d '{
  "app":"webwatcher.email",
  "component":{"type":"rive","asset":"bell","stateMachine":"Main",
               "inputBindings":{"count":"{count}","hover":"hover"},"actionRef":"markRead"},
  "fields":{"count":3},
  "simulate":["hoverIn","pressDown","pressUp","hoverOut"]}'
```

Request: `app` (required), `component` (a rive component object, without needing `type` validity beyond the
fields), `fields` (optional resolved field values: string, number, boolean or list of strings), `simulate`
(optional steps run in order: `hoverIn`, `hoverOut`, `pressDown`, `pressUp`).

Reply:

```json
{"loaded":true,
 "inputs":{"count":"number","hover":"bool"},
 "applied":{"count":"3.0"},
 "artboards":[{"name":"Bell","width":64,"height":64,"defaultMachine":"Main",
               "machines":[{"name":"Main","inputs":[{"name":"count","kind":"number"},{"name":"hover","kind":"bool"}]}],
               "animations":[]}],
 "takesClicks":true,
 "pointerWrites":{"hover":"false"},
 "clickedActions":["markRead"]}
```

`loaded` is `true` when the animation loads and plays; otherwise `error` holds the placeholder text above.
`inputs` are the machine's inputs by kind, `applied` the values written from `fields`, `takesClicks` whether
clicks are captured, `pointerWrites` the last value each simulated pointer step wrote, `clickedActions` the
action ids that a simulated press and release ran (the action is **not** executed, only reported).

The Designer snapshot (`GET|POST /v1/designer/snapshot`) draws the Designer offscreen; Rive cells are
placeholders there as well.

## Worked example: a bell that rings on new mail

**1. In Rive.** Artboard `Bell`, 64 x 64, transparent. State machine `Main` with a Number input `count`, a
Boolean input `hover` and a Trigger `ring`; a "ring" state that plays when `ring` fires or when `hover` is true.
Export `bell.riv`. Embed any assets.

**2. Declare it.** Save the manifest from the section above (asset `bell`, `stateMachine: "Main"`,
`inputs: ["count","ring","hover"]`) with `PUT /v1/manifest`. Herald copies it to
`assets/webwatcher.email/bell.riv`.

**3. Check it.** Run the `/v1/rive/check` request above. Expect `loaded: true` and your three inputs in
`inputs`. Fix names until `applied` shows what you expect.

**4. Template.**

```json
{"name":"email-bell","app":"webwatcher.email","layoutVersion":2,"collapseEmpty":true,
 "grid":{"rows":3,"cols":3,"rowSizes":["auto","auto","auto"],"colSizes":["48","fill","auto"],"gap":8,"padding":14,"width":400},
 "cells":[
  {"id":"bell","row":0,"col":0,"rowSpan":2,"align":"topLeading",
   "component":{"type":"rive","asset":"bell","stateMachine":"Main","height":40,
                "inputBindings":{"count":"{count}","ring":"{count}","hover":"hover"},
                "action":{"id":"open","label":"Open","kind":"url","url":"{url}"}}},
  {"id":"title","row":0,"col":1,"component":{"type":"text","binding":"{title}","style":"title","maxLines":2}},
  {"id":"count","row":0,"col":2,"align":"topTrailing","component":{"type":"badge","binding":"{count}","color":"#FF3B30"}},
  {"id":"subject","row":1,"col":1,"colSpan":2,"component":{"type":"text","binding":"{subject}","style":"subtitle","maxLines":2}},
  {"id":"acts","row":2,"col":0,"colSpan":3,"component":{"type":"actions","source":"merged","layout":"wrap"}}]}
```

**5. Preview and send.** `render_preview` shows a placeholder where the bell is; `send_test` shows the real
thing. Sending the same `id` again with a higher `count` rings the bell:

```sh
herald notify --app webwatcher.email --id inbox --template email-bell --title "2 new from Acme" \
  --metadata '{"count":2,"subject":"Invoice #4021","url":"https://mail.example.com"}'
herald notify --app webwatcher.email --id inbox --template email-bell --title "3 new from Acme" \
  --metadata '{"count":3,"subject":"Re: Invoice #4021","url":"https://mail.example.com"}'
```

## Troubleshooting

| Symptom | Likely cause | What to do |
|---|---|---|
| Dashed box with a message | A load error | Read the message (table above) and run `/v1/rive/check` |
| Animation plays but never reacts to fields | Input name wrong (case) or not an input of that machine | `check` -> `inputs`; names are case-sensitive; the binding is silently ignored otherwise |
| Reacts to the first notification only | Same value written again: unchanged values are not re-written | Triggers fire when the value changes; send a different value or bind a counter |
| Trigger fires on appearance | The bound field is truthy at load | Expected; bind a field that is absent on the first notification, or use a Boolean |
| Input stays at its old value when a field disappears | An absent token leaves the input alone | Send an explicit `0`/`false`, or bind a field that is always sent |
| Hover does nothing | No input bound to `hover`, or the input name differs from the key | `"inputBindings":{"<your input name>":"hover"}`; the **key** is the input name, the **value** is the keyword |
| Hover works but a Rive pointer-enter listener does not | Pointer-move events are not forwarded | Use the `hover` input |
| Clicking the animation opens the notification instead of running the action | No `action`/`actionRef`, or the action id is hidden | Add one and check `takesClicks` in `check` |
| Animation looks letterboxed | Box ratio differs from the artboard | Set `aspectRatio` to the artboard's ratio (the Designer shows it as the placeholder) or resize the artboard |
| Too small or cut off | Fixed row smaller than the box, or `height` larger than the row | Use an `auto` row or smaller `height` |
| Works in the Designer, not after export/import | Used an absolute `path` | Use `asset` ids, or let export rewrite loose paths |
| `render_preview` shows a placeholder | Offscreen renders cannot draw Rive | Use `send_test` or `/v1/rive/check` |
| Banner is slow to appear | Large file, or CDN assets being fetched | Shrink it; embed assets |
| Manifest saved but animation missing | Asset path unreadable or over 10 MB | Server log: `manifest <app>: asset <id>: ...`; fix and re-send the manifest |
| Replaced file not picked up | Same bytes, or you used a `path` to a copy | Re-`PUT` the manifest; `asset` references re-install when the source content changed |
