# Grid templates (layoutVersion 2)

> **Changed in 1.4.** The `actions` component takes `include`, `align`, `wrap` and `spacing`, and an action is
> drawn in one cell only (first cell in reading order wins). `button` accepts `actionId` as another spelling of
> `actionRef` and a `style` of `normal`, `prominent`, `destructive` or `cancel`; a destructive button is red
> and asks inline before it runs. A template can set `onClick: "openApp"` so a click on the banner brings the
> issuing app to the front. The `image` component has a Source choice (issuer image, fixed image, another image
> field), and the Designer files every token under where its value comes from. See "One action, one cell",
> "Button style", "Image source" and "Where a token comes from" below.

A v2 template lays a notification out on a grid of cells. Each cell holds one component. Issuer data
reaches components through `{token}` bindings. The same `GridBannerView` draws live banners, the
Designer canvas, history previews and `POST /v1/preview`, so a preview is what you get on screen.

Templates live at `~/Library/Application Support/Herald/templates/<app>/<name>.json`. Create them with
`PUT /v1/templates`, the Designer, or the MCP `put_template` tool. v1 templates (`layout` = `imageLeft`,
`imageRight`, `hero`, `compact`) keep rendering: they are mapped onto four built-in grid templates.

## Template shape

```json
{
  "name": "email-accumulated", "app": "webwatcher.email", "layoutVersion": 2,
  "collapseEmpty": true,
  "grid": {"rows": 3, "cols": 4, "rowSizes": ["auto","auto","auto"],
           "colSizes": ["72","fill","fill","56"], "gap": 8, "padding": 14, "width": 400},
  "cells": [ ... ],
  "actionRules": [ ... ],
  "extra": {"source": "herald"},
  "accentColor": "#2E7D32", "sound": "default", "persistent": true, "timeout": 0, "snooze": true
}
```

| Field | Meaning |
|---|---|
| `layoutVersion` | `2` for grid templates. Absent or `1` means a legacy `layout`. |
| `grid` | `rows`, `cols`, `rowSizes`, `colSizes`, `gap`, `padding`, `width` (banner width in points). |
| `cells` | The cells, see below. |
| `collapseEmpty` | Template default for empty components, rows and columns. Default `true`. |
| `actionRules` | Rules over the issuer's actions, see [ACTIONS.md](ACTIONS.md). |
| `extra` | Key/values you author. They are merged into the payload every action receives. |
| `onClick` | What a click on the banner body does: `url` (default) opens the notification's link, `openApp` brings the issuing app to the front (see [ACTIONS.md](ACTIONS.md#open-app)). |
| `title`, `body`, `url`, ... | v1 defaults still apply: the payload overrides them. |

## Grid

`rowSizes` and `colSizes` have one entry per row and column. An entry is `"auto"` (as large as its
content), `"fill"` (shares the remaining space) or a number of points (`"72"` or `72`). `gap` is the space
between tracks, `padding` the inset of the whole grid, `width` the banner width.

## Cells

```json
{"id":"title","row":0,"col":1,"rowSpan":1,"colSpan":2,"align":"topLeading","padding":0,
 "component":{"type":"text","binding":"{title}","style":"title","maxLines":2}}
```

`row` and `col` are 0-based; `rowSpan` and `colSpan` merge cells (default 1). `align` is one of
`topLeading`, `top`, `topTrailing`, `leading`, `center`, `trailing`, `bottomLeading`, `bottom`,
`bottomTrailing` and places the component inside its cell area. Cells may not overlap and must stay inside
the grid; `validate_template` reports violations by cell id.

## Bindings

A binding is a string with `{token}` placeholders: `"{title} - {count}"`, `"{image}"`. A token is read
from the notification's top-level keys first, then from `metadata`; manifest `sample` values fill it in
the Designer. Unknown tokens render as nothing. A component whose every bound token is absent is
**empty**.

### Where a token comes from

The Designer's pickers file every token under one of three provenances, and the sample beside it is what a
preview fills it with:

| Group in the picker | Provenance | Meaning |
|---|---|---|
| From the issuer app (manifest field) | the issuer | A field the issuer's manifest declares (`sender`, `thumbnail`). The issuer promises to send it, with a type and a sample. |
| From the notification (payload field) | the notification | A standard key (`title`, `body`, `image`, `deliveredAt`, `stack.count`...) or any other key a real notification carried or you typed as a custom token. Nobody promises it: it is absent when the notification does not send it. |
| Set here (fixed value) | the template | An `extra.<key>` value you wrote in the template. The same for every notification. |

See [reference/bindings.md](reference/bindings.md#three-provenances).

## Collapse semantics

Empty fields can either collapse or keep their place. It is your choice, at two levels:

1. **Template default**: `"collapseEmpty": true | false`.
2. **Per component**: `"emptyBehavior": "collapse" | "keep"` overrides the default for that component.

An empty component that collapses is removed. A row or column whose cells are all collapsed (or have no
cell) shrinks to zero, together with its gap, when `collapseEmpty` is on; with `collapseEmpty: false` it
keeps its size, so the banner keeps a stable shape. `keep` on one component keeps its cell's track alive
even when the template collapses. Components that never read data (`spacer`, `issuerIcon`, `actions`
with at least one action) are never empty.

```json
{"id":"subtitle","row":1,"col":1,"colSpan":2,
 "component":{"type":"text","binding":"{subject}","style":"subtitle","emptyBehavior":"collapse"}}
```

## Components

Every component accepts `emptyBehavior`. All other properties are optional unless marked.

| `type` | Properties |
|---|---|
| `text` | `binding` (required), `style` (`title`, `subtitle`, `body`, `caption`, `mono`), `maxLines`, `color` (hex), `fontSize`, `weight` (`regular`, `medium`, `semibold`, `bold`), `alignment` (`leading`, `center`, `trailing`), `markdown` (default true for `body`) |
| `image` | `binding` (an issuer `{image}`, a fixed file path or another image field, see "Image source"), `fit` (`fit`, `fill`, `cover`), `cornerRadius`, `aspectRatio`, `height` |
| `issuerIcon` | `size` (default 22), `shape` (`circle`, `rounded`), `cornerRadius` |
| `timestamp` | `binding` (default: delivery time), `relative` (true: "2 min ago"), `style`, `color`, `fontSize` |
| `button` | `action` (inline action) or `actionRef` / `actionId` (id of an issuer or rule action; the two names are the same), `style` (`normal`, `prominent`, `destructive`, `cancel`) |
| `actions` | `source` (`issuer`, `template`, `merged`), `layout` (`row`, `wrap`, `stack`), `maxVisible`, `include` (ordered action ids), `align` (`leading`, `center`, `trailing`, `spaceBetween`), `wrap` (true/false), `spacing` (0-64, default 6) |
| `iconButton` | `symbol` (SF Symbol name), `action` or `actionRef`, `size`, `color`, `tooltip` |
| `badge` | `binding`, `color`, `textColor` |
| `progress` | `binding` (0 to 1 or 0 to 100), `color`, `height` |
| `rive` | `asset` (manifest asset id) or `path`, `stateMachine`, `artboard`, `inputBindings`, `action`/`actionRef` (on click), `loop`, `aspectRatio`, `height` |
| `spacer` | none |

`GET /v1/components` returns the same list as a machine-readable schema, with defaults.

### One action, one cell

An action is drawn in at most one cell, so a single list can be split across the banner. Cells are visited top
to bottom, left to right:

1. A `button` bound to an action id (`actionRef` or `actionId`) claims that action.
2. An `actions` cell with `include` claims those ids, in that order.
3. An `actions` cell without `include` shows every action of its `source` that nobody claimed.

When two cells ask for the same action, the first in reading order draws it and the other shows nothing for it
(a `button` collapses like an absent action). `validate_template` warns and names both cells. `include` ids that
no action has show nothing (a warning when a manifest is given). `align` places the buttons across the cell
(`spaceBetween`: first at the leading edge, last at the trailing edge, the rest spread evenly); the snooze clock
stays on the trailing edge. `wrap: true` flows onto more lines, `wrap: false` keeps one line with "+N" for the
rest; absent, `layout: wrap` flows and `row` does not (`stack` is always one per line).

```json
{"name":"email-split","app":"webwatcher.email","layoutVersion":2,"collapseEmpty":true,
 "grid":{"rows":4,"cols":4,"rowSizes":["auto","auto","auto","auto"],"colSizes":["104","fill","fill","fill"],"gap":8,"padding":14,"width":400},
 "cells":[
  {"id":"icon","row":0,"col":0,"rowSpan":3,"component":{"type":"issuerIcon","size":56,"shape":"rounded"}},
  {"id":"title","row":0,"col":1,"colSpan":3,"component":{"type":"text","binding":"{title}","style":"title","maxLines":1}},
  {"id":"sender","row":1,"col":1,"colSpan":3,"component":{"type":"text","binding":"{sender}","style":"subtitle","maxLines":1}},
  {"id":"subject","row":2,"col":1,"colSpan":3,"component":{"type":"text","binding":"{subject}","style":"caption","maxLines":1}},
  {"id":"read","row":3,"col":0,"component":{"type":"button","actionId":"markRead"}},
  {"id":"more","row":3,"col":1,"colSpan":3,"component":{"type":"actions","include":["archive","delete","spam"],"align":"trailing","wrap":false}}]}
```

### Button style

| `style` | Look | Behaviour |
|---|---|---|
| `normal` (also `default`) | accent-tinted capsule | runs when pressed |
| `prominent` | solid accent capsule, white label | runs when pressed |
| `destructive` | red label on a red-tinted, outlined capsule | asks first: an inline row "Run "Delete"?" with Cancel replaces the buttons, nothing runs until you answer |
| `cancel` | quiet grey capsule | runs when pressed |

The old `"destructive": true` on a button still decodes (as `"style": "destructive"`). The confirmation applies
to any action whose effective style is `destructive`, wherever it was set (the button, an issuer's manifest, an
`actionRules` entry), and it comes before any approval the action's kind needs. It is drawn inside the banner
and never takes focus. `style` on a button overrides the action's own.

### Image source

In the Designer the image component's Source control writes the `binding`:

| Choice | Binding | Meaning |
|---|---|---|
| From issuer `{image}` | `"{image}"` | The picture the sending app attached. |
| Fixed image | a file path | A picture you pick, the same for every notification. Herald copies it to `~/Library/Application Support/Herald/template-images/<app>/` (named by a short content hash, so the same file twice is one copy). |
| Field | `"{key}"` | Another `image` field the manifest declares (`{thumbnail}`). |

A fixed path is never empty while the file exists. **Bundles do not yet carry fixed images**: exporting a
template to a bundle leaves the path pointing at this Mac, so re-pick the image after importing elsewhere.

### Rive

`inputBindings` maps a state-machine input name to a token or a pointer state:
`{"count":"{count}","hover":"hover","pressed":"pressed"}`. Numeric, boolean and trigger inputs are driven
from tokens; `hover` and `pressed` follow the mouse over the banner. A failed load renders a placeholder
with the error and never crashes the banner.

## Symbols

`button`, `iconButton`, `actions`, `issuerIcon` and `badge` (and every action, see ACTIONS.md) can carry an SF Symbol. `symbol` is a plain name, or an object with the full styling. An unknown name is a validation warning, never an error: the component keeps its current look (an `iconButton` draws a question mark so the typo is visible).

| key | values |
|---|---|
| `name` | an SF Symbol name; may contain a `{token}` (that is how `replace` has something to swap) |
| `weight` | `ultraLight` `thin` `light` `regular` `medium` `semibold` `bold` `heavy` `black` |
| `scale` | `small` `medium` `large` |
| `placement` | `leading` (default) `trailing` `only` (drops the label); buttons only |
| `renderingMode` | `monochrome` `hierarchical` `palette` `multicolor` |
| `colors` | 1-3 of `#RGB`, `#RRGGBB`, `#RRGGBBAA`, `accent`, `primary`, `secondary` or a `{token}` whose value is one of those |
| `variableValue` | 0-1, or a `{token}` bound to a numeric field (for symbols such as `wifi` or `speaker.wave.3`) |
| `effect` | `{kind, trigger?, speed?, cumulative?, reversing?}` (macOS 14+) |

Effects (the `effect` key): `kind` is `bounce`, `pulse`, `variableColor` (with `cumulative` / `reversing`), `scale`, `appear`, `disappear` or `replace`; `trigger` is `onAppear` (default), `onChange` (when a bound token changes), `onHover` or `repeating`; `speed` is 0.25-4. Effects run only in live banners and the Designer's live preview, never in `render_preview` / `/v1/preview` (those show weight, scale, mode, colours and the variable value), never on macOS 13, and never when Reduce Motion is on. Validation warns, without failing, on out-of-range `variableValue` or `speed` (both are clamped), more than 3 `colors`, `palette` without colours, `cumulative` / `reversing` on anything but `variableColor`, `appear` / `disappear` with `repeating`, and `replace` with a trigger other than `onChange`.

Plain name:

```json
{"type":"iconButton","symbol":"xmark","action":{"id":"dismiss","label":"Dismiss","kind":"dismiss"}}
```

Monochrome (one colour, here a token):

```json
{"type":"button","actionRef":"markRead","symbol":{"name":"checkmark.circle","weight":"semibold","colors":["{tint}"]}}
```

Hierarchical (shades of one colour):

```json
{"type":"badge","binding":"{count}","symbol":{"name":"envelope.fill","renderingMode":"hierarchical","colors":["#FF3B30"]}}
```

Palette (2-3 colours) with a bound variable value:

```json
{"type":"iconButton","size":30,"symbol":{"name":"wifi","renderingMode":"palette","colors":["#34C759","secondary"],"variableValue":"{signal}"},"action":{"id":"d","label":"Dismiss","kind":"dismiss"}}
```

Multicolor (the symbol's own colours; `colors` is ignored):

```json
{"type":"issuerIcon","size":28,"symbol":{"name":"cloud.sun.rain.fill","renderingMode":"multicolor","scale":"large"}}
```

With an effect:

```json
{"type":"iconButton","symbol":{"name":"bell.badge","effect":{"kind":"bounce","trigger":"onChange","speed":1.5}},"action":{"id":"d","label":"Dismiss","kind":"dismiss"}}
```

In the Designer, select the component and use the Symbol panel: a searchable picker over the symbols on this Mac (right-click a symbol to favourite it), weight, scale, placement, mode with colour wells, variable value and effect. `component_schema` documents the keys (`definitions.symbol`).

## Examples

### Email, accumulated

```json
{"name":"email-accumulated","app":"webwatcher.email","layoutVersion":2,"collapseEmpty":true,
 "grid":{"rows":3,"cols":4,"rowSizes":["auto","auto","auto"],"colSizes":["72","fill","fill","56"],
         "gap":8,"padding":14,"width":400},
 "cells":[
  {"id":"img","row":0,"col":0,"rowSpan":2,"component":{"type":"image","binding":"{image}","fit":"cover","cornerRadius":10}},
  {"id":"title","row":0,"col":1,"colSpan":2,"align":"topLeading","component":{"type":"text","binding":"{title}","style":"title","maxLines":2}},
  {"id":"badge","row":0,"col":3,"align":"topTrailing","component":{"type":"badge","binding":"{count}","color":"#E53935"}},
  {"id":"subject","row":1,"col":1,"colSpan":2,"component":{"type":"text","binding":"{subject}","style":"subtitle","maxLines":1}},
  {"id":"when","row":1,"col":3,"align":"trailing","component":{"type":"timestamp","binding":"{receivedAt}","relative":true,"style":"caption"}},
  {"id":"acts","row":2,"col":0,"colSpan":4,"component":{"type":"actions","source":"merged","layout":"row","maxVisible":4}}],
 "actionRules":[{"match":"archive","relabel":"Archive it","position":0}]}
```

### Compact one-liner that keeps its shape

```json
{"name":"line","app":"bidbot","layoutVersion":2,"collapseEmpty":false,
 "grid":{"rows":1,"cols":3,"rowSizes":["auto"],"colSizes":["22","fill","auto"],"gap":8,"padding":10,"width":360},
 "cells":[
  {"id":"i","row":0,"col":0,"component":{"type":"issuerIcon","size":22,"shape":"rounded"}},
  {"id":"t","row":0,"col":1,"component":{"type":"text","binding":"{title}","style":"body","maxLines":1}},
  {"id":"p","row":0,"col":2,"component":{"type":"progress","binding":"{progress}","height":4,"emptyBehavior":"collapse"}}]}
```

### Animated bell (Rive)

```json
{"id":"bell","row":0,"col":0,"component":{"type":"rive","asset":"bell","stateMachine":"Main",
 "inputBindings":{"count":"{count}","hover":"hover"},"height":40,
 "action":{"id":"open","label":"Open","kind":"url","url":"{url}"}}}
```

## Previewing

`POST /v1/preview` renders a template offscreen and returns PNG bytes:

```sh
curl -s -H "$AUTH" -d '{"template":"email-accumulated","app":"webwatcher.email","data":"sample",
  "appearance":"dark","scale":2}' $BASE/v1/preview -o preview.png
```

`template` is a template name or a full v2 template object; `data` is a JSON object or `"sample"` (uses the
manifest samples). See [API.md](API.md).
