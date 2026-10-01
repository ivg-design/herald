# Grid templates (layoutVersion 2)

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
| `image` | `binding`, `fit` (`fit`, `fill`, `cover`), `cornerRadius`, `aspectRatio`, `height` |
| `issuerIcon` | `size` (default 22), `shape` (`circle`, `rounded`), `cornerRadius` |
| `timestamp` | `binding` (default: delivery time), `relative` (true: "2 min ago"), `style`, `color`, `fontSize` |
| `button` | `action` (inline action) or `actionRef` (id of an issuer or rule action), `style` |
| `actions` | `source` (`issuer`, `template`, `merged`), `layout` (`row`, `wrap`, `stack`), `maxVisible` |
| `iconButton` | `symbol` (SF Symbol name), `action` or `actionRef`, `size`, `color`, `tooltip` |
| `badge` | `binding`, `color`, `textColor` |
| `progress` | `binding` (0 to 1 or 0 to 100), `color`, `height` |
| `rive` | `asset` (manifest asset id) or `path`, `stateMachine`, `artboard`, `inputBindings`, `action`/`actionRef` (on click), `loop`, `aspectRatio`, `height` |
| `spacer` | none |

`GET /v1/components` returns the same list as a machine-readable schema, with defaults.

### Rive

`inputBindings` maps a state-machine input name to a token or a pointer state:
`{"count":"{count}","hover":"hover","pressed":"pressed"}`. Numeric, boolean and trigger inputs are driven
from tokens; `hover` and `pressed` follow the mouse over the banner. A failed load renders a placeholder
with the error and never crashes the banner.

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
