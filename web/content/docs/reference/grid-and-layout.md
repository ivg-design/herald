# Grid, cells and layout

This page is the reference for the template object: the grid a banner is laid out on, the cells that sit on
it, how Herald works out sizes, and the limits the validator enforces. It is for anyone who writes template
JSON by hand or generates it from an agent. To build a template step by step, read the
[template guide](../TEMPLATES.md). To place a component in a cell, see the
[component pages](components/README.md).

## Concepts

**Template.** A template is a saved banner design for one app. A notification asks for it by name with
`"template"`. The template holds the layout, default content and behaviour, and the rules for the app's
buttons.

**Grid.** The layout is a table of rows and columns. A row or a column is called a **track**. The grid has a
width in points, a **gap** between tracks and a **padding** between the banner edge and the tracks.

**Cell.** A cell is a rectangle of tracks that holds one [component](components/README.md): a text, an
image, a button, a progress bar. A cell is placed by its first row and first column. Rows and columns are
numbered from 0 in JSON. The Designer shows them from 1.

**Span.** A cell can cover more than one track. `rowSpan` and `colSpan` say how many. Merging two columns is
`"colSpan": 2`. Slots that no cell covers stay empty and draw nothing.

**Row and column sizes.** Each track is `auto` (as large as its content), `fill` (an equal share of what is
left over) or a fixed number of points.

**Alignment.** When a cell is larger than its component, `align` picks one of nine positions inside the cell.

**Collapsing.** A component whose data is missing is empty. An empty component can disappear and close up its
row or column, or keep its blank space. The template sets the default with `collapseEmpty` and each component
can override it with `emptyBehavior`. The full rules are in
[Collapse semantics](../TEMPLATES.md#collapse-semantics).

**Click.** `onClick` says what a click on the banner body does: open the notification's link, or bring the
issuing app to the front. How clicks, expansion and closing work together is in
[How banners behave](banners.md).

One renderer draws live banners, the Designer, History and previews, so a preview shows what a delivery
shows. Layout does not depend on light or dark appearance. Only colours change.

## The template object

A template is one JSON object. Only `name` and `app` are required. Every other field has a default, so a
short file is valid. A grid template shows nothing until it has cells.

| Field | Type | Required | Description |
|---|---|---|---|
| `name` | string | yes | The name notifications use in `template`. Unique per app. |
| `app` | string | yes | The id of the app the template belongs to. |
| `layoutVersion` | integer | no | `2` for a grid template. Default `2` when the template has a `grid`, otherwise `1`. |
| `grid` | object | no | The grid. Required when `layoutVersion` is `2`. See [The grid object](#the-grid-object). |
| `cells` | array | no | The cells, at most 100. Default `[]`. See [The cell object](#the-cell-object). |
| `collapseEmpty` | boolean | no | Default for components without their own `emptyBehavior`. Default `true`. |
| `onClick` | string | no | `url` opens the notification's link. `openApp` brings the issuing app to the front. Default `url`. |
| `actionRules` | array | no | Rules that hide, relabel, restyle, reorder or add buttons. See [Action rules](actions.md). |
| `followUp` | object | no | One action to run when a banner is left unattended, or `{"enabled": false}` to switch off the issuer's. See [Follow-ups](actions.md#follow-ups). |
| `extra` | object | no | Your own string values. Components read them as `{extra.key}` and every action receives them. |
| `accentColor` | string | no | A hex colour (`#RGB`, `#RRGGBB` or `#RRGGBBAA`) that tints accent-coloured components and default buttons. |

Default behaviour for notifications that do not set it themselves:

| Field | Type | Required | Description |
|---|---|---|---|
| `sound` | string | no | A system sound name, a file path or `none`. The notification's own `sound` wins. |
| `persistent` | boolean | no | Keep the banner until it is dismissed. The notification's own value wins. |
| `timeout` | number | no | Seconds until the banner closes itself. `0` means until dismissed. |
| `snooze` | boolean | no | Show the snooze control. |
| `priority` | string | no | `low`, `normal`, `high` or `urgent`. See [Quiet hours](quiet-hours.md). |
| `reminder` | object | no | The **Add to Reminders** button, with an optional `title` and `due`. |
| `maxBodyLines` | integer | no | The line limit for `body` text that sets no `maxLines` of its own. Default `8`. Values are held between 1 and 30. |

Default content, used when the notification leaves the field out. The notification's own value always wins,
and `{token}` placeholders are filled only in text that comes from the template. The notification's own
fields are described in [`POST /v1/notify`](api/notifications.md#post-v1notify).

| Field | Type | Required | Description |
|---|---|---|---|
| `title` | string | no | The headline, with `{token}` placeholders. |
| `subtitle` | string | no | The second line, with placeholders. |
| `body` | string | no | The main text, with placeholders. |
| `url` | string | no | The link a click opens. Placeholder values are percent-encoded. |
| `image` | string | no | A picture. Placeholders are not filled in this field. |

**Minimal example**

```json
{
  "name": "plain",
  "app": "example.bidbot",
  "grid": {"rows": 1, "cols": 1},
  "cells": [
    {"row": 0, "col": 0, "component": {"type": "text", "binding": "{title}"}}
  ]
}
```

**Realistic example**

```json
{
  "name": "bid-update",
  "app": "example.bidbot",
  "layoutVersion": 2,
  "collapseEmpty": true,
  "accentColor": "#2E7D32",
  "grid": {
    "rows": 3, "cols": 4,
    "rowSizes": ["auto", "auto", "auto"],
    "colSizes": [72, "fill", "fill", 56],
    "gap": 8, "padding": 14, "width": 400
  },
  "cells": [
    {"id": "img", "row": 0, "col": 0, "rowSpan": 2,
     "component": {"type": "image", "binding": "{image}", "fit": "cover", "cornerRadius": 10}},
    {"id": "title", "row": 0, "col": 1, "colSpan": 2,
     "component": {"type": "text", "binding": "{title}", "style": "title", "maxLines": 2}},
    {"id": "count", "row": 0, "col": 3, "align": "topTrailing",
     "component": {"type": "badge", "binding": "{count}", "color": "#E53935"}},
    {"id": "client", "row": 1, "col": 1, "colSpan": 2,
     "component": {"type": "text", "binding": "{client}", "style": "subtitle", "maxLines": 1}},
    {"id": "when", "row": 1, "col": 3, "align": "trailing",
     "component": {"type": "timestamp", "binding": "{receivedAt}", "relative": true}},
    {"id": "buttons", "row": 2, "col": 0, "colSpan": 4,
     "component": {"type": "actions", "source": "merged", "layout": "row", "maxVisible": 4}}
  ],
  "actionRules": [{"match": "archive", "relabel": "Archive it", "position": 0}],
  "extra": {"queue": "bids"},
  "sound": "Glass",
  "timeout": 0
}
```

Rules that span several fields:

- A template is stored as one file per template under `~/Library/Application Support/Herald/templates/`,
  in a folder named after the app. The file name is derived from the template name, so address a template
  by `app` and `name`, not by path.
- Herald ignores a stored file larger than 2 MB.
- Names that start with `builtin.` are reserved for the [built-in templates](#built-in-templates).
  Duplicate and rename refuse them.
- A name that starts with `_` is a scratch template. Notifications can name it, but
  [`GET /v1/templates`](api/templates.md#get-v1templates) never lists it. The Designer's **Send test** writes
  one called `_designer-test`.
- Duplicate and rename refuse a name that is empty, contains `/` or `:`, starts with `.` or `_`, or is longer than
  128 bytes.
- The Designer refuses an empty name, `/`, `:` and a leading `.` or `_` when you save.
- A notification's own value beats the template's default for the same field. An explicit empty `buttons`
  array in a notification means no buttons, even if the template defines some.

## The grid object

The grid sets how many tracks there are, how big each one is, and the spacing around and between them.
Every property is optional. When you give a size list but not the count, the count is the length of the
list.

| Property | Type | Required | Description |
|---|---|---|---|
| `rows` | integer | no | The number of rows, 1 to 12. Default: the length of `rowSizes`, else `3`. |
| `cols` | integer | no | The number of columns, 1 to 12. Default: the length of `colSizes`, else `4`. |
| `rowSizes` | array | no | One size per row. Must have exactly `rows` entries. Default: `auto` for every row. |
| `colSizes` | array | no | One size per column. Must have exactly `cols` entries. Default: `fill` for every column. |
| `gap` | number | no | Space between tracks, in points, 0 to 64. Default `8`. |
| `padding` | number | no | Space between the banner edge and the tracks, in points, 0 to 64. Default `14`. |
| `width` | number | no | The banner width in points, 160 to 800. Default `400`. |

A size is one of three values:

| Size | In a column | In a row |
|---|---|---|
| A number such as `72` | Exactly that many points wide. | Exactly that many points tall. Taller content is clipped by its cell. |
| `"auto"` | As wide as the widest cell that sits in it alone, measured on one line. | As tall as its tallest cell. |
| `"fill"` | An equal share of the width left over. | The same as `auto`. A banner's height comes from its content, so there is no fixed height to share. |

A number may also be written as a string: `"72"`, `"72pt"` or `"72px"`. Fixed sizes are 0 to 4000 points.

The Designer's starting grid is 3 rows by 4 columns with a 72 point first column and a 56 point last column.
The built-in templates use a width of 380.

**Minimal example**

```json
{"rows": 1, "cols": 2, "colSizes": [48, "fill"]}
```

**Realistic example**

```json
{
  "rows": 3,
  "cols": 4,
  "rowSizes": ["auto", "auto", "auto"],
  "colSizes": [72, "fill", "fill", 56],
  "gap": 8,
  "padding": 14,
  "width": 400
}
```

Two adjustments keep fixed columns usable. Herald applies them when a template is stored or loaded, and the
validator reports each as a warning:

- A fixed column narrower than 24 points is raised to 24.
- When every column is fixed, the last column takes any width left over, or gives back any width that
  overflows. Other columns are never squeezed below 24 points. A grid with a `fill` or `auto` column does not
  need this, because those columns absorb the difference.

## The cell object

A cell places one component on the grid. Validation messages name cells by `id`, so give cells short, meaningful ids.
A cell without an `id` is named `r<row>c<col>`, for example `r0c1`. The table marks which properties are required.

| Property | Type | Required | Description |
|---|---|---|---|
| `id` | string | no | The cell's name, unique in the template. Default `r<row>c<col>`. |
| `row` | integer | yes | The first row the cell covers, counted from 0. |
| `col` | integer | yes | The first column the cell covers, counted from 0. |
| `rowSpan` | integer | no | How many rows the cell covers. Default `1`. |
| `colSpan` | integer | no | How many columns the cell covers. Default `1`. |
| `align` | string | no | Where the component sits inside the cell. Default `topLeading`. |
| `padding` | number | no | Space between the cell edge and its component, in points, 0 to 64. Default `0`. |
| `component` | object | yes | The component. Its `type` picks the kind. See [Components](components/README.md). |

The nine values of `align`:

| | Leading | Centre | Trailing |
|---|---|---|---|
| **Top** | `topLeading` | `top` | `topTrailing` |
| **Middle** | `leading` | `center` | `trailing` |
| **Bottom** | `bottomLeading` | `bottom` | `bottomTrailing` |

**Minimal example**

```json
{"row": 0, "col": 0, "component": {"type": "text", "binding": "{title}"}}
```

**Realistic example**

```json
{
  "id": "subject",
  "row": 1,
  "col": 1,
  "colSpan": 2,
  "align": "topLeading",
  "padding": 0,
  "component": {
    "type": "text",
    "binding": "{sender}: {subject}",
    "style": "subtitle",
    "maxLines": 1,
    "emptyBehavior": "collapse"
  }
}
```

Every component also accepts `emptyBehavior` (`collapse` or `keep`). See
[what every component shares](components/README.md).

### Empty slots, merging and growing

Slots that no cell covers are valid and draw nothing. In the Designer they are the dashed placeholders. To
merge slots there, select them and press **Merge slots**, or use the context menu's **Merge Selected Slots**.
**Split** undoes a merge. A cell can only grow into empty slots. The
[Designer how-to](../AUTHORING.md) shows each step.

## Validation and limits

[`PUT /v1/templates`](api/templates.md#put-v1templates), the MCP tool `put_template` and the Designer all run the
same checks before they store a template. An error rejects the template and names the cell. A warning is
reported and the template is still stored.

| Rule | Limit | Result |
|---|---|---|
| Name and app | Neither may be blank. | Error. |
| `layoutVersion` | `1` or `2`. | Error for any other value. |
| `grid` | Required when `layoutVersion` is `2`. | Error. |
| `rows` and `cols` | 1 to 12 each. | Error. |
| `rowSizes` and `colSizes` | Exactly `rows` and `cols` entries. | Error. |
| Fixed size | 0 to 4000 points. | Error. |
| `gap` and `padding` | 0 to 64 points each. | Error. |
| `width` | 160 to 800 points. | Error. |
| Cell count | At most 100. | Error. |
| Cell `id` | Not empty, unique. | Error. |
| Cell position | `row` and `col` at least 0, spans at least 1. | Error. |
| Cell fit | `row + rowSpan` at most `rows`, `col + colSpan` at most `cols`. | Error. |
| Cell overlap | Two cells may not cover the same slot. | Error naming both cells. |
| Cell `padding` | 0 to 64 points. | Error. |
| `accentColor` | A hex colour. Keywords such as `accent` are not accepted here. | Error. |
| Fixed column width | At least 24 points. | Warning, and the column is raised. |
| Fixed columns that do not add up to the grid | Must fill the inner width. | Warning, and the last column is adjusted. |
| `layoutVersion` `1` with a `grid` or `cells` | Both are ignored. | Warning. |
| An action asked for by two cells | Drawn once, in the first cell in reading order. | Warning naming both cells. |
| `extra` key | Letters, digits, `_`, `.` and `-`. | Warning. |

Checks on a component's own properties are on its page under [Components](components/README.md).

## How sizes are solved

Herald turns the grid, the cells, the collapse plan and the measured size of each cell's content into a
width for every column, a height for every row and a frame for every cell. Columns are solved first, because
a text's height depends on the width it gets. The same arithmetic runs in the app and in the tests.

**Columns**

1. A collapsed column has width 0 and adds no gap.
2. The inner width is the banner `width` minus twice the `padding`, minus every gap between visible columns.
3. A fixed column takes exactly its points.
4. An `auto` column wants the one-line width of the widest cell that sits in that column alone, plus the
   cell's padding. A cell that spans several columns lends its extra width to the `auto` columns it covers,
   but only when none of the columns it covers is `fill`.
5. The `auto` columns share what remains after the fixed columns and the gaps. When they want more than is
   left, the widest are trimmed to an equal share first and narrow ones keep their natural width.
6. The `fill` columns split what the `auto` columns left, equally. When there is no `fill` column, the last
   visible column takes any width that is left over.

**Rows**

1. A collapsed row has height 0 and adds no gap.
2. Each cell is laid out at its final width and reports the height its content needs. Text wraps first.
3. A fixed row takes exactly its points. `auto` and `fill` rows are as tall as their tallest single-row cell.
4. A tall cell that spans several rows lends its extra height to the **last** row it covers that is not
   fixed. Text beside a tall image stays packed at the top.
5. The banner height is twice the `padding`, plus the row heights, plus the gaps between visible rows.

A cell's frame includes the cell's own `padding`. The component is laid out inside the frame and placed by
`align`.

What this means when you design:

| Situation | Result |
|---|---|
| Long text in an `auto` column. | The column grows to the longest line until the space runs out. Put long text in a `fill` column. |
| One `fill` column between two fixed columns. | The usual image, text, meta layout. |
| A fixed row smaller than its content. | The content is clipped. |
| Columns that want more than the banner width. | The widest `auto` columns are trimmed. |

## Built-in templates

Four layouts exist without being stored. They are grid templates, 380 points wide, generated in code.

| Template name | `layout` value |
|---|---|
| `builtin.imageLeft` | `imageLeft`, the default. |
| `builtin.imageRight` | `imageRight`. |
| `builtin.hero` | `hero`. |
| `builtin.compact` | `compact`. |

- A notification that names no template is drawn with the one its `layout` field chooses.
- A notification can also name one directly, with `"template": "builtin.hero"`.
- The [MCP tool `get_template`](mcp/templates.md#get_template) returns any of them as a starting point to edit and
  save under your own name.
- [`GET /v1/templates`](api/templates.md#get-v1templates) does not list them.

The [template guide](../TEMPLATES.md#the-built-in-layouts) describes what each one looks like.

## Accepted older forms

Herald reads these older spellings and treats them as the current form.

| Older form | Current form |
|---|---|
| A template with no `grid`, using `layout`, `showSubtitle`, `showBody` and `showTimestamp`. | A grid template. Herald draws it from the matching built-in template, and the Designer opens it converted to a grid. |
| `buttons` on the template: default buttons with `label`, `style` and `url`, `command` or `callback`. | `actionRules` entries with `add`. A default button that runs a shell command asks the user to confirm once. |
| A size written as `"72"`, `"72pt"` or `"72px"`. | The number `72`. |
| `layoutVersion` left out. | `2` when the template has a `grid`, otherwise `1`. |

## Related

- [Template guide](../TEMPLATES.md): what templates are for and a step-by-step walk-through.
- [Design a banner in the Designer](../AUTHORING.md): the same grid edited visually.
- [Bindings and tokens](bindings.md): how `{token}` placeholders get their values.
- [Components](components/README.md): the properties of each component.
- [Action rules](actions.md): `actionRules`.
- [Templates API](api/templates.md): store, list, preview and share templates over HTTP.
