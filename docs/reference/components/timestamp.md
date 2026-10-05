# Timestamp component

The `timestamp` component draws a point in time, either a date that a field carries or the moment the banner was
delivered. The Designer calls it **Time**. Use it to tell the reader when something happened: "2:14 PM" for a banner
about an event now, or "3 min. ago" for an email that arrived a while before the banner appeared.

**Minimal example**

```json
{"type":"timestamp"}
```

With no binding the component shows the time the banner was delivered, small and grey.

**Realistic example**

A relative arrival time in a narrow right-hand column, next to the title.

```json
{"name":"timestamp-demo","app":"example.bidbot","layoutVersion":2,"collapseEmpty":true,
 "grid":{"rows":1,"cols":2,"rowSizes":["auto"],"colSizes":["fill","auto"],"gap":8,"padding":12,"width":380},
 "cells":[
  {"id":"title","row":0,"col":0,"component":{"type":"text","binding":"{title}","style":"title"}},
  {"id":"when","row":0,"col":1,"align":"topTrailing",
   "component":{"type":"timestamp","binding":"{receivedAt}","relative":true}}]}
```

In the picture below, look at the time in the top right corner of the banner, left of the close button. It is a timestamp component showing the delivery time.

![A banner with a timestamp in its top right corner](../../../web/public/shots/docs/banner-plain.png "The time at the right of the banner is a timestamp component showing the delivery time.")

**Properties**

| Property | Type | Default | Description |
|---|---|---|---|
| `type` | string | required | Always `"timestamp"`. |
| `binding` | string | none | A date field such as `"{receivedAt}"`. When it is omitted or blank the component shows the banner's delivery time. |
| `relative` | boolean | `false` | `true` shows "3 min. ago" and refreshes every 30 seconds. `false` shows a clock time. |
| `style` | string | `caption` | A typography preset: `title`, `subtitle`, `body`, `caption` or `mono`. The presets are the ones of [`text`](text.md#styles). |
| `color` | string | per style | A hex colour, or `accent`, `primary` or `secondary`. |
| `fontSize` | number | per style | The size in points, from 6 to 72. |
| `emptyBehavior` | string | template default | `collapse` or `keep`. See [Empty timestamps](#empty-timestamps). |

## What the binding can hold

The bound value is read as a date in one of two forms:

- An ISO 8601 date and time such as `2026-10-01T14:14:00Z`, with or without fractional seconds and a time zone offset.
- A number of seconds since 1 January 1970. A number above `1e11` is read as milliseconds.

A value that is not a date is shown as typed. The standard token `{deliveredAt}` is the delivery time as ISO 8601, so
`"binding":"{deliveredAt}"` gives the same result as no binding. In the Designer, the **Date** field is left empty to show
when the banner arrived.

## Formats

| Mode | On the same day as now | On another day |
|---|---|---|
| Absolute (`relative` is `false`) | The time in the user's locale, for example `2:14 PM`. | The month, day and time, for example `Oct 1, 2:14 PM`. |
| Relative (`relative` is `true`) | The system's abbreviated relative form, for example "3 min. ago" or "in 2 hr.". | The same form. |

The Designer's **Format** control switches between **Clock time** and **3 min ago**. A relative timestamp keeps itself
current while the banner is on screen. An absolute one does not change.

## Sizing and alignment

A timestamp is one line. It never wraps and keeps its natural width, so an `auto` column fits it exactly. Its height is
one line of the chosen style. It usually sits in a narrow right-hand column with `align` set to `topTrailing` or
`trailing`.

When the notification has speech, the cell of the timestamp also holds the replay control. A banner with speech and no
timestamp gets a thin row under the grid for the control.

## Empty timestamps

A timestamp is empty only when a `binding` is set and its token is absent. Without a binding it is never empty, because
it always has the delivery time to show.

## Common mistakes

| Mistake | What happens | Fix |
|---|---|---|
| Binding a field that holds `"yesterday"`. | It is shown as typed text. | Send ISO 8601 or epoch seconds. |
| Declaring the field as `text` instead of `date` in the manifest. | It works, but the Designer's palette and sample values are less helpful. | Declare it with `"type":"date"`. |
| Expecting `relative` to show seconds. | It uses the system's abbreviated relative style. | Use an absolute timestamp for the exact time. |

## Related

- [Text component](text.md): the typography presets a timestamp shares.
- [Bindings and tokens](../bindings.md): `{deliveredAt}` and the other standard tokens.
- [Manifests](../manifests.md): declaring a field of type `date`.
- [Voice reference](../voice.md): the speech replay control that sits beside the timestamp.
