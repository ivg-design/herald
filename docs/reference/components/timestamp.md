# timestamp

A time: a date field of the notification, or when the banner was delivered.

## Properties

| Property | Type | Default | Allowed values / notes |
|---|---|---|---|
| `type` | string | required | `"timestamp"` |
| `binding` | string | none | A date field such as `"{receivedAt}"`. Omitted or blank: the banner's delivery time. |
| `relative` | boolean | false | `true`: "3 min. ago", refreshed every 30 seconds. `false`: a clock time. |
| `style` | string | `caption` | `title`, `subtitle`, `body`, `caption`, `mono` (same presets as [text.md](text.md)). |
| `color` | string | per style | Hex or `accent`, `primary`, `secondary`. |
| `fontSize` | number 6 to 72 | per style | Points. |
| `emptyBehavior` | string | template default | `collapse` or `keep`. |

## Bindings and tokens

The bound value is parsed as a date: ISO 8601 (`2026-10-01T14:14:00Z`, with or without fractional seconds
and offset), or seconds since 1970 (a number above 1e11 is read as milliseconds). A value that is not a date is
shown as typed. The standard token `{deliveredAt}` is the delivery time as ISO 8601, so
`"binding":"{deliveredAt}"` equals no binding at all.

## Formats

| Mode | Same day as now | Another day |
|---|---|---|
| absolute (`relative: false`) | the time, in the user's locale (`2:14 PM`) | month, day and time (`Oct 1, 2:14 PM`) |
| relative (`relative: true`) | abbreviated named style, e.g. "3 min. ago", "in 2 hr." | the same |

## Sizing

One line, never wraps, and keeps its natural width (so an `auto` column fits it exactly). Height is one line
of the chosen style.

## 9-point alignment

Typically `topTrailing` or `trailing` in a narrow right-hand column. When the notification has speech, the
timestamp cell also carries the replay control (a banner with speech and no timestamp gets a thin row under
the grid for it).

## Empty behaviour

Empty when a `binding` is set and its token is absent. With no binding it is never empty.

## Light and dark

Secondary grey by default for `caption` and `subtitle`; keywords follow the system, hex is legibility-adjusted.

## Actions wiring

None.

## Examples

Delivery time, small and grey:

```json
{"type":"timestamp"}
```

When the email arrived, relative:

```json
{"type":"timestamp","binding":"{receivedAt}","relative":true,"style":"caption"}
```

In a right-hand meta column of a template:

```json
{"name":"ts-demo","app":"demo","layoutVersion":2,"collapseEmpty":true,
 "grid":{"rows":1,"cols":2,"rowSizes":["auto"],"colSizes":["fill","auto"],"gap":8,"padding":12,"width":380},
 "cells":[
  {"id":"title","row":0,"col":0,"component":{"type":"text","binding":"{title}","style":"title"}},
  {"id":"when","row":0,"col":1,"align":"topTrailing",
   "component":{"type":"timestamp","binding":"{receivedAt}","relative":true}}]}
```

## Common mistakes

| Mistake | What happens | Fix |
|---|---|---|
| Binding a field that holds `"yesterday"` | Shown as typed text. | Send ISO 8601 or epoch seconds. |
| Declaring the field as `text` instead of `date` in the manifest | Works, but the palette and sample are less helpful. | Use `"type":"date"`. |
| Expecting `relative` to show seconds | It uses the system's abbreviated relative style. | Use absolute for exact time. |
