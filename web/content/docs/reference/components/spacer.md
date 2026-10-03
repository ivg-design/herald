# spacer

Empty space that fills its cell. Never empty, never collapses.

## Properties

| Property | Type | Default | Notes |
|---|---|---|---|
| `type` | string | required | `"spacer"` |

A spacer has no other properties and no `emptyBehavior` (any `emptyBehavior` you write is ignored; the
schema does not list it).

## Bindings and tokens

None.

## Sizing

Zero width and height of its own. Its cell's track size comes from the grid: a `fixed` or `fill` track keeps
its size, an `auto` track with only a spacer is zero. Use a spacer when you want a **fixed** track to stay
alive for alignment, because a track with a spacer in it is never collapsed (a spacer is never empty).

## 9-point alignment

Irrelevant.

## Empty behaviour

Never empty. A row or column that contains a spacer is never collapsed by the planner.

## Light and dark

Transparent.

## Actions wiring

None.

## Examples

Keep a 16 pt gutter column at the right of a text column:

```json
{"name":"spacer-demo","app":"demo","layoutVersion":2,"collapseEmpty":true,
 "grid":{"rows":1,"cols":2,"rowSizes":["auto"],"colSizes":["fill","16"],"gap":0,"padding":12,"width":380},
 "cells":[
  {"id":"title","row":0,"col":0,"component":{"type":"text","binding":"{title}","style":"title"}},
  {"id":"gutter","row":0,"col":1,"component":{"type":"spacer"}}]}
```

## Common mistakes

| Mistake | What happens | Fix |
|---|---|---|
| Using a spacer to push things apart in an `auto` row | Contributes no height. | Use a fixed row size or cell `padding`. |
| Expecting a spacer to collapse | It never does. | Leave the cell out instead. |
