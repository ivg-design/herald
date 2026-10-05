# Spacer component

The `spacer` component draws nothing. It fills its cell with empty space and counts as content, so the row and column it
sits in are never collapsed. The Designer calls it **Spacer**. Use it to keep a fixed-size track alive for alignment, for
example a gutter column that stays at the right of a text column even when nothing else is in it.

**Minimal example**

```json
{"type":"spacer"}
```

**Realistic example**

A text column and a 16 point gutter column that holds a spacer, so the gutter exists on every banner.

```json
{"name":"spacer-demo","app":"example.bidbot","layoutVersion":2,"collapseEmpty":true,
 "grid":{"rows":1,"cols":2,"rowSizes":["auto"],"colSizes":["fill",16],"gap":0,"padding":12,"width":380},
 "cells":[
  {"id":"title","row":0,"col":0,"component":{"type":"text","binding":"{title}","style":"title"}},
  {"id":"gutter","row":0,"col":1,"component":{"type":"spacer"}}]}
```

**Properties**

| Property | Type | Default | Description |
|---|---|---|---|
| `type` | string | required | Always `"spacer"`. |

A spacer has no other properties. It has no `emptyBehavior` either: any `emptyBehavior` you write is ignored.

## Sizing

A spacer has no width or height of its own. The size of its cell comes from the grid.

- A `fixed` or `fill` track keeps its size, and an `auto` track that holds only a spacer is zero wide or tall.
- A spacer is never empty, so a row or column that contains one is never collapsed by [the collapse planner](../grid-and-layout.md#how-sizes-are-solved). That is the reason to use one: it holds a track open.
- It is transparent and has no action. Its alignment does not matter.

## Common mistakes

| Mistake | What happens | Fix |
|---|---|---|
| Using a spacer to push things apart in an `auto` row. | It adds no height. | Use a fixed row size or the cell's `padding`. |
| Expecting a spacer to collapse. | It never does. | Leave the cell out instead. |

## Related

- [The grid, cells and layout](../grid-and-layout.md): track sizes and the collapse planner.
- [Components](README.md#empty-components-and-emptybehavior): how empty components collapse.
- [Designing a banner](../../AUTHORING.md): adding a **Spacer** in the Designer.
