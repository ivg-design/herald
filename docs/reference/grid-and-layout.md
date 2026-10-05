# The grid, cells and layout

A Herald banner is drawn from a **grid** of rows and columns. Cells sit on the grid, each holding one
[component](components/README.md). One renderer (`GridBannerView`) draws live banners, the Designer canvas,
history previews and `POST /v1/preview`, so a preview is what you get on screen.

This page is the layout reference: the template object, the grid, cells and merging, how sizes are solved,
and how empty rows and columns collapse. Per-component sizing is on each component's page.

## The template object

```json
{"name":"email-accumulated","app":"webwatcher.email","layoutVersion":2,
 "collapseEmpty":true,
 "grid":{"rows":3,"cols":4,"rowSizes":["auto","auto","auto"],"colSizes":[72,"fill","fill",56],
         "gap":8,"padding":14,"width":400},
 "cells":[ ],
 "actionRules":[ ],
 "extra":{"queue":"inbox"},
 "accentColor":"#2E7D32"}
```

| Field | Type | Default | Meaning |
|---|---|---|---|
| `name` | string | required | Unique per app. Notifications choose it with `"template"`. No `/` or `:`, no leading `.` or `_`, at most 100 characters. `builtin.` is reserved. A name starting with `_` is a scratch template: usable by name, never listed (`GET /v1/templates` hides it; the Designer's Send test writes `_designer-test`). |
| `app` | string | required | The issuer's app id. |
| `layoutVersion` | integer | 2 when there is a `grid`, else 1 | `2` is a grid template. `1` is a legacy fixed layout; `grid` and `cells` are ignored (with a warning). Any other value is an error. |
| `grid` | object | required for v2 | See below. |
| `cells` | array | `[]` | At most 100. |
| `collapseEmpty` | boolean | `true` | Template default for components without their own `emptyBehavior`. |
| `onClick` | string | `url` | What clicking the banner does: `url` opens the notification's link, `openApp` brings the issuing application to the front (see [actions.md](actions.md#open-app)). Since 1.8 a click opens only a banner that carries a link, see [Clicking a banner](api.md#clicking-a-banner). |
| `actionRules` | array | `[]` | Rules over the issuer's actions: [actions.md](actions.md). |
| `extra` | object of strings | `{}` | Your own key/values. Bindings read them as `{extra.key}`; every action receives them as `extra`. Keys are letters, digits, `_`, `.`, `-`. |
| `accentColor` | string | system accent | Hex colour. Tints `accent`-coloured components and default buttons. Hex only here. |
| `sound` | string | app's default | Default sound: a system sound name, a file path, or `none`. The payload overrides. |
| `persistent`, `timeout` | bool, number | app's | Default persistence; auto-dismiss seconds (0 = until dismissed). The payload overrides. |
| `snooze` | boolean | none | Show the snooze control by default. |
| `priority` | string | none | `low`, `normal`, `high` (and `urgent`, see [quiet-hours.md](quiet-hours.md)). |
| `reminder` | object | none | Default "Add to Reminders": `{title?, due?}`. |
| `title`, `subtitle`, `body`, `image`, `url` | string | none | Default content with `{tokens}`, used when the payload leaves the field out. |
| `buttons` | array | `[]` | Legacy default buttons `{label, style, url\|command\|callback}`. Prefer `actionRules`. A default button that runs a shell command is the template's own code and needs a one-time confirmation (the validator warns). |
| `layout`, `showSubtitle`, `showBody`, `showTimestamp`, `maxBodyLines` | v1 | | The v1 look flags. `maxBodyLines` also sets the default line limit of `body` text (default 8). |

Templates are stored one file each at `~/Library/Application Support/Herald/templates/<app>/<name>.json`
(files over 2 MB are ignored on read). Partial files are fine; every optional field has a default.
`PUT /v1/templates` validates first and rejects errors (HTTP 400) naming the cell.

### Payload beats template

For defaults (`title`, `sound`, `buttons`, `persistent`, `timeout`...): the notification's own value wins and the
template fills what the notification left out. `{tokens}` are filled only in text that came from the template,
since a sender's own text may legitimately contain braces. An explicit empty `buttons` array in a payload is a
deliberate "no buttons".

### Built-in templates

The four v1 layouts exist as grid templates named `builtin.imageLeft`, `builtin.imageRight`, `builtin.hero` and
`builtin.compact` (380 points wide). They cannot be saved over or deleted; `get_template` returns them as
starting points. A notification with no template, or a v1 template, is drawn from one of them according to its
`layout`, `showSubtitle`, `showBody`, `showTimestamp`, `maxBodyLines` and `accentColor`.

## The grid

```json
{"rows":3,"cols":4,"rowSizes":["auto","auto","auto"],"colSizes":[72,"fill","fill",56],
 "gap":8,"padding":14,"width":400}
```

| Property | Type | Default | Range | Meaning |
|---|---|---|---|---|
| `rows` | integer | length of `rowSizes`, else 3 | 1 to 12 | Number of rows. |
| `cols` | integer | length of `colSizes`, else 4 | 1 to 12 | Number of columns. |
| `rowSizes` | array of size | `auto` for every row | exactly `rows` entries | One size per row. |
| `colSizes` | array of size | `fill` for every column | exactly `cols` entries | One size per column. |
| `gap` | number | 8 | 0 to 64 | Space between tracks, points. |
| `padding` | number | 14 | 0 to 64 | Space between the banner edge and the tracks. |
| `width` | number | 400 | 160 to 800 | Banner width in points. |

The Designer's starting grid is 3 rows x 4 columns with a 72 pt image column and a 56 pt meta column. The
built-in templates use width 380.

### Sizes

A size is `"auto"`, `"fill"` or a number of points. A number may be written `72`, `"72"`, `"72pt"` or `"72px"`.
Points are 0 to 4000.

| Size | Columns | Rows |
|---|---|---|
| `72` (points) | exactly that wide | exactly that tall; a taller content is clipped by the cell |
| `auto` | as wide as the widest cell that sits in it alone, measured on one line | as tall as its tallest cell |
| `fill` | an equal share of the width that is left | same as `auto` (a banner's height is decided by its content, there is no fixed height to share) |

## Cells and merging

A cell covers `rowSpan` x `colSpan` tracks starting at (`row`, `col`), both 0-based. Merging is simply a span:
two columns merged is `"colSpan":2`. The cell properties are in [components/README.md](components/README.md#the-cell-around-a-component).

Rules enforced by validation (each error names the cell id and a JSON path):

- the cell must fit: `row + rowSpan <= rows` and `col + colSpan <= cols`;
- spans are at least 1, `row` and `col` at least 0;
- ids are unique and non-empty;
- cells must not overlap: two cells may not claim the same track;
- at most 100 cells; cell `padding` 0 to 64.

Unoccupied slots are allowed. They are the dashed "+" placeholders in the Designer and nothing on the banner.
In the Designer: select slots and press **Merge slots** (or the context menu's **Merge Selected Slots**) to make
a spanning cell, **Split** to undo it; drag components between slots; the inspector's 3 x 3 pad sets `align`.

## How sizes are solved

Given the grid, the cells, the collapse plan and a measurement of each cell's content, the solver computes
every track and every cell frame. The same arithmetic runs in the app and in the tests (`GridSolver`).

### Columns

1. Collapsed columns get zero width and no gap.
2. The inner width is `width - 2 x padding`; subtract all gaps between live columns.
3. Fixed columns take exactly their points.
4. Each `auto` column wants the ideal (one-line) width of the widest cell that lies in that column alone, plus
   that cell's padding. A cell spanning several columns lends its excess to the `auto` columns it covers, but
   only if none of the columns it covers is `fill`.
5. `auto` columns share what remains after the fixed columns and gaps. When they want more than is left, the
   widest are trimmed to an equal share first and narrow ones keep their natural width.
6. `fill` columns split what the `auto` columns left, equally.

### Rows

1. Collapsed rows get zero height and no gap.
2. Each cell is laid out at its resolved width and reports the height its content needs (text wraps).
3. Fixed rows take exactly their points. `auto` and `fill` rows are as tall as their tallest single-row cell.
4. A tall cell that spans several rows lends its excess to the **last** non-fixed row it covers, so text beside
   a tall image stays packed at the top.
5. Banner height is `2 x padding` plus the row heights and the gaps between live rows.

The cell frame includes the cell's own `padding`; the component is laid out inside it and positioned by `align`.

### Consequences

- A text in an `auto` column makes that column as wide as its longest line (until the space runs out): put
  long text in `fill` columns.
- A `fill` column is never narrower than what is left, so one `fill` between two fixed columns is a classic
  "image | text | meta" layout.
- A fixed row smaller than its content clips the content.
- A banner can be narrower than all its columns want; the widest `auto` columns are trimmed.

## Collapse planner

For one notification Herald works out which cells are empty, which of those collapse, and which rows and
columns have nothing left. This is `HeraldTemplate.plan`, a pure function.

1. A cell is **empty** when its component has nothing to show (each component's "Empty when").
2. An empty cell **collapses** when its behaviour is `collapse`: its own `emptyBehavior`, else the template's
   `collapseEmpty` (`true` is `collapse`, `false` is `keep`). An empty cell whose behaviour is `keep` is
   drawn blank.
3. The cells that are not collapsed are **live**.
4. A **row** (or column) collapses when no live cell covers it, a spanning cell counting for every track it
   covers. A row/column that **no cell touches at all** collapses only when `collapseEmpty` is `true`.
5. A collapsed row or column has size 0 and adds no gap.

So `keep` on one component keeps its tracks alive even when the template collapses, and `collapseEmpty: false`
keeps every track, including ones that no cell touches, so the banner has a stable shape.

### Worked examples

Template `email-accumulated` (3 x 4): `img` rows 0-1 col 0; `title` row 0 cols 1-2; `count` badge row 0 col 3;
`subject` row 1 cols 1-2; `when` timestamp row 1 col 3; `acts` row 2 cols 0-3. `collapseEmpty` is true.

| Notification | Empty cells | Rows collapsed | Result |
|---|---|---|---|
| everything present | none | none | full banner |
| no `subject`, no `receivedAt` | `subject` (`when` has a binding, so empty) | none: `img` is live and spans rows 0-1 | row 1 stays as tall as the image needs |
| no `subject`, no `receivedAt`, no `image` | `subject`, `when`, `img` | row 1 | title row is followed directly by the action row |
| no `count` | `count` | none (title is live in row 0) | column 3 stays: `when` and `acts` live in it |
| no `title`, `count` | `title`, `count` | none | `img` still live in row 0 |
| all empty and `acts` has no actions | every cell | all rows and columns | a zero-height banner (padding only) |
| `collapseEmpty: false`, no `subject` | `subject` is kept | none | blank line where the subject was |

A template with a fourth row that no cell uses: with `collapseEmpty: true` the row collapses (no stray gap);
with `false` it stays at its size.

Per-component override: `"emptyBehavior":"keep"` on `subject` in the first template keeps row 1 and columns 1-2
alive for every notification, even with `collapseEmpty: true`.

### Interaction with confirmations

While an inline confirmation is shown, every `actions` and `button` cell is treated as empty and collapsed
regardless of its `emptyBehavior`; the question replaces the row. `iconButton` cells stay.

## Light and dark

Layout is appearance independent. Only colours change (see [components/README.md](components/README.md#colours)).
To look at both: `POST /v1/preview` with `"appearance":"light"` and `"dark"`.

## Previewing

```sh
curl -s -H "$AUTH" -H 'Content-Type: application/json' $BASE/v1/preview -o preview.png -d '{
  "template":"email-accumulated","app":"webwatcher.email",
  "data":{"title":"2 new from Acme","count":14,"subject":"A very long subject line that wraps"},
  "appearance":"dark","scale":2}'
```

Omit a key in `data` to see the collapse. Add `"stackCount":3` to see the banner as the top of a stack. See
[api.md](api.md#post-v1preview).
