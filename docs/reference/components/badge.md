# badge

A small pill with a value: an unread count, a status word, a price.

## Properties

| Property | Type | Default | Allowed values / notes |
|---|---|---|---|
| `type` | string | required | `"badge"` |
| `binding` | string | required | Text with `{tokens}`, e.g. `"{count}"` or `"{count} new"`. |
| `color` | string | `accent` | Pill colour: hex or `accent` (also `primary`, `secondary`). |
| `textColor` | string | legible on the pill | Text colour: hex or `primary` / `secondary` / `accent`. |
| `emptyBehavior` | string | template default | `collapse` or `keep`. |
| `symbol` | name or object | none | **Available from 1.3.** A symbol drawn before the value. See [../symbols.md](../symbols.md). |

## Bindings and tokens

The value is the bound text, one line, 10.5 pt semibold with monospaced digits. Numbers print without a
trailing `.0`.

## Sizing

A capsule hugging its text: 6 pt horizontal and 1.5 pt vertical padding, at least 17 pt wide, so a single digit
is a circle-ish pill. It never wraps or stretches.

## 9-point alignment

Typically `topTrailing` next to a title.

## Empty behaviour

Empty when every token in `binding` is absent or blank. A kept empty badge is invisible but holds its size.

## Light and dark

Pill colours are **not** legibility-adjusted: what you write is what is drawn in both appearances, so choose a
colour that works on both (a saturated red or blue is fine). With no `textColor`, black or white is chosen for
contrast against the pill (a pill lighter than about 62 % luminance gets black text).

## Actions wiring

None. (The stack counter, which opens a stack when clicked, is [stackBadge.md](stackBadge.md).)

## Examples

Unread count:

```json
{"type":"badge","binding":"{count}","color":"#FF3B30"}
```

Status word on an accent pill with explicit text colour:

```json
{"type":"badge","binding":"{status}","color":"accent","textColor":"#FFFFFF"}
```

Beside a title in a complete template:

```json
{"name":"badge-demo","app":"webwatcher.email","layoutVersion":2,"collapseEmpty":true,
 "grid":{"rows":1,"cols":3,"rowSizes":["auto"],"colSizes":["40","fill","auto"],"gap":8,"padding":12,"width":380},
 "cells":[
  {"id":"icon","row":0,"col":0,"component":{"type":"issuerIcon","size":32}},
  {"id":"title","row":0,"col":1,"component":{"type":"text","binding":"{title}","style":"title","maxLines":2}},
  {"id":"count","row":0,"col":2,"align":"topTrailing","component":{"type":"badge","binding":"{count}","color":"#FF3B30"}}]}
```

## Common mistakes

| Mistake | What happens | Fix |
|---|---|---|
| A very light `color` with no `textColor` | Black text is chosen, fine; but on a white banner the pill disappears. | Use a mid-tone colour. |
| Binding `{count}` with a count of 0 | `0` is shown (a number zero is not blank). | Omit the field when there is nothing to show, or bind a text field. |
| Using `badge` for the stack count | Never shows the stack. | Use `stackBadge`. |
