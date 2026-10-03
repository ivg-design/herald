# iconButton

A round icon-only button with an SF Symbol: close, snooze, mark done.

## Properties

| Property | Type | Default | Allowed values / notes |
|---|---|---|---|
| `type` | string | required | `"iconButton"` |
| `symbol` | string | required | SF Symbol name, e.g. `"xmark"`, `"alarm"`, `"checkmark"`. An unknown name draws `questionmark.circle`. From 1.3 it can also be an object `{name, weight, scale, renderingMode, colors, variableValue, placement, effect}`; see [../symbols.md](../symbols.md). |
| `action` | action object or string | none | Inline action, or a string naming a resolved action's id. |
| `actionRef` | string | none | Id of an action in the resolved list. |
| `size` | number | 18 | Diameter in points (at least 8). |
| `color` | string | secondary | Glyph colour: hex or `accent`, `primary`, `secondary`. |
| `tooltip` | string | the action's label | Hover text. |
| `emptyBehavior` | string | template default | `collapse` or `keep`. |

It needs a non-blank `symbol` and an `action` or `actionRef`.

## Bindings and tokens

None in `symbol`. The tooltip falls back to the action label, whose `{tokens}` are filled. (From 1.3 a
symbol's `colors` and `variableValue` may be tokens.)

## Sizing

A circle of `size` points (default 18) with a faint translucent fill; the glyph is bold, 9 pt (10 pt above
18 pt `size`). It does not wrap or stretch.

## 9-point alignment

Usually `topTrailing` for a close button in the corner.

## Empty behaviour

Empty when `actionRef` names an action that is not in the resolved list. An inline action is never empty.
Icon buttons are never collapsed by a pending confirmation, so the banner stays dismissable.

## Light and dark

The circle fill is a faint primary tint, the glyph uses `color` (default secondary), so both follow the
appearance.

## Actions wiring

- A `dismiss` action closes the banner (the usual close button).
- A `snooze` action **without** `snoozeMinutes` opens the snooze menu (5 min, 15 min, 1 hour, Tomorrow 9:00);
  with `snoozeMinutes` it snoozes for exactly that long.
- Other kinds run exactly as for [button.md](button.md#actions-wiring), with the same gates.

## Examples

Close button:

```json
{"type":"iconButton","symbol":"xmark","action":{"id":"dismiss","label":"Dismiss","kind":"dismiss"}}
```

Snooze menu button with a tooltip:

```json
{"type":"iconButton","symbol":"alarm","size":20,"action":{"id":"snooze","label":"Snooze","kind":"snooze"},"tooltip":"Remind me later"}
```

In a corner, in a complete template:

```json
{"name":"icon-button-demo","app":"demo","layoutVersion":2,"collapseEmpty":false,
 "grid":{"rows":2,"cols":2,"rowSizes":["auto","auto"],"colSizes":["fill","auto"],"gap":4,"padding":12,"width":380},
 "cells":[
  {"id":"title","row":0,"col":0,"component":{"type":"text","binding":"{title}","style":"title"}},
  {"id":"close","row":0,"col":1,"align":"topTrailing",
   "component":{"type":"iconButton","symbol":"xmark","action":{"id":"dismiss","label":"Dismiss","kind":"dismiss"}}},
  {"id":"sub","row":1,"col":0,"colSpan":2,"component":{"type":"text","binding":"{subtitle}","style":"subtitle"}}]}
```

A styled symbol (available from 1.3):

```json
{"type":"iconButton","symbol":{"name":"checkmark.circle.fill","weight":"semibold","renderingMode":"palette",
 "colors":["#FFFFFF","#34C759"],"effect":{"kind":"bounce","trigger":"onHover"}},
 "actionRef":"markRead","size":22}
```

## Common mistakes

| Mistake | What happens | Fix |
|---|---|---|
| A misspelt symbol name | Draws a question mark in a circle. | Look the name up in the SF Symbols app. |
| Omitting the action | Validation error. | Add `action` or `actionRef`. |
| Using `snooze` with `snoozeMinutes` and expecting the menu | Snoozes immediately for that time. | Omit `snoozeMinutes` for the menu. |
