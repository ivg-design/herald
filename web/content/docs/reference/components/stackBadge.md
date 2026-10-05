# stackBadge

The stack counter: a pill that shows `{stack.count}`, the number of notifications folded into this banner's
stack. See [../stacking.md](../stacking.md).

## Properties

| Property | Type | Default | Allowed values / notes |
|---|---|---|---|
| `type` | string | required | `"stackBadge"` |
| `color` | string | `accent` | Pill colour: hex or `accent`. |
| `textColor` | string | legible on the pill | Hex or `primary`. |
| `emptyBehavior` | string | template default | `collapse` or `keep`. |

It has no `binding`: it always binds `{stack.count}`.

## Bindings and tokens

`{stack.count}` is supplied by the banner while it is drawn, and only while two or more notifications are
stacked. It is absent for a lone banner. You can also read it in any text: `"+{stack.count} more"`.

## Sizing, alignment, light and dark

Identical to [badge.md](badge.md).

## Empty behaviour

Empty while the banner is alone (the count is below 2). With `collapse` the pill, and any row or column it
alone kept alive, disappears; with `keep` it holds a blank pill-sized cell.

## Actions wiring

On a stack's top card, clicking the pill toggles the stack: it expands in place when closed and collapses when open (a scrollable list, newest first, with
Collapse and Dismiss all). It never activates Herald or takes focus from the app you are in. On a lone banner
it does nothing.

If a template has no `stackBadge`, the stacked card draws the counter at its top-right corner by itself.

## Examples

```json
{"type":"stackBadge","color":"#FF3B30"}
```

In a corner of a banner that otherwise looks the same alone and stacked:

```json
{"name":"stack-demo","app":"demo","layoutVersion":2,"collapseEmpty":true,
 "grid":{"rows":1,"cols":2,"rowSizes":["auto"],"colSizes":["fill","auto"],"gap":8,"padding":12,"width":380},
 "cells":[
  {"id":"title","row":0,"col":0,"component":{"type":"text","binding":"{title}","style":"title"}},
  {"id":"stack","row":0,"col":1,"align":"topTrailing","component":{"type":"stackBadge","color":"#007AFF"}}]}
```

## Common mistakes

| Mistake | What happens | Fix |
|---|---|---|
| Previewing a lone banner and seeing nothing | Correct: the badge is empty below 2. | `POST /v1/preview` with `"stackCount":3`. |
| Binding `{stack.count}` in a plain `badge` | Works, but without the click-to-expand behaviour. | Use `stackBadge`. |
