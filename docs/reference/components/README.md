# Components: what every component shares

A template cell holds exactly one component. On the wire a component is one flat JSON object whose
`type` picks the kind. There are twelve kinds:

| `type` | Page | One line |
|---|---|---|
| `text` | [text.md](text.md) | Bound text in one of five styles, optional inline Markdown. |
| `image` | [image.md](image.md) | A picture from a field (path, `data:` URI, https URL). |
| `issuerIcon` | [issuerIcon.md](issuerIcon.md) | The sending app's icon, round or rounded. |
| `timestamp` | [timestamp.md](timestamp.md) | A date field, or the delivery time; absolute or relative. |
| `button` | [button.md](button.md) | One action as a capsule button. |
| `actions` | [actions.md](actions.md) | The whole action row, with overflow. |
| `iconButton` | [iconButton.md](iconButton.md) | A round icon-only button (close, snooze). |
| `badge` | [badge.md](badge.md) | A small pill with a value (a count). |
| `stackBadge` | [stackBadge.md](stackBadge.md) | The stack counter pill, `{stack.count}`. |
| `progress` | [progress.md](progress.md) | A thin progress bar. |
| `rive` | [rive.md](rive.md) and [../rive.md](../rive.md) | A Rive animation driven by fields and the pointer. |
| `spacer` | [spacer.md](spacer.md) | Empty space that fills its cell. |

`GET /v1/components` (and the MCP tool `component_schema`) returns the machine-readable form of this
reference. Every JSON example in these pages was checked against that schema and the real validator
(`validate_template`),, including the SF Symbol examples (available from 1.3). Fences marked `jsonc` are fragments, not complete objects.

## The cell around a component

The component sits in a cell (see [../grid-and-layout.md](../grid-and-layout.md)):

```json
{"id":"title","row":0,"col":1,"rowSpan":1,"colSpan":2,"align":"topLeading","padding":0,
 "component":{"type":"text","binding":"{title}","style":"title"}}
```

| Cell property | Type | Default | Notes |
|---|---|---|---|
| `id` | string | `r<row>c<col>` | Unique in the template. Validation errors name cells by id. Required by the validator when empty. |
| `row`, `col` | integer >= 0 | required | 0-based first track. |
| `rowSpan`, `colSpan` | integer >= 1 | 1 | Tracks covered. The cell must fit the grid and must not overlap another cell. |
| `align` | one of nine | `topLeading` | Where the component sits inside the cell when the cell is bigger than the component. |
| `padding` | number 0 to 64 | 0 | Inset on every side, in points. |
| `component` | object | required | One component. |

A cell clips its component to the cell's frame. A component never grows its track beyond what its content
needs (see sizing in each page).

## 9-point alignment

`align` is one of `topLeading`, `top`, `topTrailing`, `leading`, `center`, `trailing`, `bottomLeading`,
`bottom`, `bottomTrailing`. The Designer shows it as a 3 x 3 pad in the inspector.

```
topLeading     top      topTrailing
leading        center   trailing
bottomLeading  bottom   bottomTrailing
```

The horizontal part (`leading`, centre, `trailing`) also sets the text alignment of a `text` component that
has no `alignment` of its own. Components that fill their cell's width (`image`, `progress`, `actions`) show
the effect only in the vertical direction.

## Empty behaviour

Every component except `spacer` accepts `emptyBehavior`:

| Value | Meaning |
|---|---|
| `collapse` | The component disappears when it has nothing to show, and a row or column left with nothing collapses to zero size (no gap either). |
| `keep` | The component stays, blank, and its cell keeps its size, so banners from one issuer keep one shape. |
| omitted | Follow the template's `collapseEmpty` (default `true`, which means `collapse`). |

What "empty" means differs per component: it is listed in each page under "Empty when". The planner that
turns that into collapsed rows and columns is described in [../grid-and-layout.md](../grid-and-layout.md#collapse-planner).

A pending inline confirmation (a "Run this command?" question) replaces the action row: every `actions` and
`button` cell is treated as collapsed while it is shown, whatever its `emptyBehavior` says. `iconButton`
cells stay, so the banner can always be dismissed.

## Bindings and tokens

Text-like properties (`binding`, and an inline action's `label`, `url`, `input`) hold `{token}`
placeholders. A token is letters, digits, `_`, `.` or `-`. See [../bindings.md](../bindings.md) for where
values come from. In short: a component is empty when it has tokens and every one of them is absent or
blank; absent tokens inside a mixed binding become empty text and the result is trimmed.

## Colours

Colour properties (`color`, `textColor`, and `accentColor` on the template) take:

- `#RGB`, `#RGBA`, `#RRGGBB` or `#RRGGBBAA`;
- or the keywords `accent` (the template `accentColor`, else the system accent), `primary`, `secondary`.

`accentColor` on the template itself takes hex only. Hex colours on text, icons and progress bars are nudged
until they are legible on the current appearance, so one hex works in light and dark; keywords follow the
system appearance. Badge pills are drawn exactly as given (see [badge.md](badge.md)).

## Light and dark

Banners follow the system appearance. Nothing in a template is appearance specific: use keywords
(`primary`, `secondary`, `accent`) or hex colours (which are legibility-adjusted). To check both, render twice:
`POST /v1/preview` with `"appearance":"light"` and `"dark"`, the MCP `render_preview`, or the Designer's
sun/moon switch.

## Actions wiring

Three components can run an action: `button` and `iconButton` (inline `action` or an `actionRef`), `rive`
(on click), and `actions` shows the whole resolved list. The resolved list is the issuer's actions plus the
template's, after `actionRules`. See [../actions.md](../actions.md).

## Static previews

Offscreen renders (`POST /v1/preview`, MCP `render_preview`, history previews) cannot draw AppKit-backed
views. Menus (the snooze clock, the "+N" overflow) are drawn as static labels and `rive` is drawn as a labelled
dashed placeholder box of the right size. Use `POST /v1/rive/check` to test a Rive component without a window
(see [../rive.md](../rive.md#testing-without-a-window)). SF Symbol effects are not drawn in static previews
either (see [../symbols.md](../symbols.md)).

## Limits

| Limit | Value |
|---|---|
| Cells per template | 100 |
| Grid tracks per axis | 1 to 12 |
| Banner width | 160 to 800 points |
| Template file size | 2 MB (larger files are ignored on read) |
| Gap, padding, cell padding | 0 to 64 points |
