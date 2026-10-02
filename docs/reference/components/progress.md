# progress

A thin progress bar.

## Properties

| Property | Type | Default | Allowed values / notes |
|---|---|---|---|
| `type` | string | required | `"progress"` |
| `binding` | string | required | A numeric field: `"{percent}"`. |
| `color` | string | `accent` | Bar colour: hex or `accent`, `primary`, `secondary`. |
| `height` | number > 0 | 4 | Bar thickness in points (at least 1). |
| `emptyBehavior` | string | template default | `collapse` or `keep`. |

## Bindings and tokens

The bound text is read as a number: `0.4`, `40`, `"40%"` all mean 40 percent. A value above 1 (or ending in
`%`) is a percentage; the result is clamped to 0 to 1. Text that is not a number draws an empty track and is
reported as no value.

| Value | Fraction |
|---|---|
| `0.25` | 25 % |
| `1` | 100 % (1 is a fraction) |
| `1.5` | 1.5 % (above 1 means percent) |
| `40` | 40 % |
| `"40%"` | 40 % |
| `250` | 100 % (clamped) |

## Sizing

Fills its cell's width, at least 40 pt (ideal 120 pt in an `auto` column), exactly `height` points tall. A
rounded track with a 12 % primary tint behind the filled part.

## 9-point alignment

Applies vertically when the row is taller than the bar.

## Empty behaviour

Empty when every token is absent or blank. A kept empty bar is invisible and holds its height. If the value
is present but not a number the bar is invisible (the accessibility value is empty).

## Light and dark

The track is a faint primary tint; the fill uses `color` (default accent, legibility-adjusted for hex).

## Actions wiring

None.

## Examples

```json
{"type":"progress","binding":"{percent}"}
```

A thicker green bar that collapses when no value is sent, under a title:

```json
{"name":"progress-demo","app":"demo","layoutVersion":2,"collapseEmpty":true,
 "grid":{"rows":2,"cols":1,"rowSizes":["auto","auto"],"colSizes":["fill"],"gap":6,"padding":12,"width":380},
 "cells":[
  {"id":"title","row":0,"col":0,"component":{"type":"text","binding":"{title} {percent}%","style":"title"}},
  {"id":"bar","row":1,"col":0,"component":{"type":"progress","binding":"{percent}","color":"#34C759","height":6,"emptyBehavior":"collapse"}}]}
```

## Common mistakes

| Mistake | What happens | Fix |
|---|---|---|
| Sending `1` meaning 1 % | Shows 100 %. | Send `0.01` or `"1%"`. |
| Binding a field that holds `"3 of 7"` | Not a number, empty track. | Send a fraction or a percentage. |
| A progress bar in an `auto` column | The column is only about 120 pt wide. | Put it in a `fill` column or span columns. |
