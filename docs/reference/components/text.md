# text

Bound text: a title, a subtitle, a body, a caption, a monospaced value. The workhorse component.

## Properties

| Property | Type | Default | Allowed values / notes |
|---|---|---|---|
| `type` | string | required | `"text"` |
| `binding` | string | required | Text with `{token}` placeholders: `"{title}"`, `"{count} new from {sender}"`. A binding with no token at all is a literal. Blank is an error. |
| `style` | string | `body` | `title`, `subtitle`, `body`, `caption`, `mono`. |
| `maxLines` | integer >= 1 | per style | Line limit. Omitted: the style's default (below). |
| `color` | string | per style | `#RGB`, `#RRGGBB`, `#RRGGBBAA`, `accent`, `primary`, `secondary`. |
| `fontSize` | number 6 to 72 | per style | Points. |
| `weight` | string | per style | `regular`, `medium`, `semibold`, `bold`. |
| `alignment` | string | follows the cell | `leading`, `center`, `trailing`. Horizontal alignment of the lines. |
| `markdown` | boolean | true for `body`, else false | Render inline Markdown (`[text](url)` links, `**bold**`, `*italic*`). |
| `emptyBehavior` | string | template default | `collapse` or `keep`. |

### Style presets

| Style | Font | Default colour | Default max lines |
|---|---|---|---|
| `title` | 13 pt semibold | primary | 2 |
| `subtitle` | 12 pt regular | secondary | 2 |
| `body` | 12 pt regular | primary | the banner's `maxBodyLines` (8 unless the template or notification sets it) |
| `caption` | 10 pt regular | secondary | 1 |
| `mono` | 11 pt monospaced | primary | 4 |

## Bindings and tokens

`binding` reads any token ([../bindings.md](../bindings.md)): standard fields (`title`, `subtitle`, `body`,
`url`, `app`, `appName`, `id`, `group`, `deliveredAt`), the issuer's manifest fields, `{extra.key}` and
dotted metadata names (`{customer.name}`). Numbers print without a trailing `.0`, booleans as `true` and
`false`, lists joined with `, `.

Mixed bindings degrade gracefully: `"{sender}: {subject}"` with no `sender` shows just the subject (the
result is trimmed), and only when both are absent is the component empty.

## Sizing

- Width: in a fixed-width column the text wraps inside it. In an `auto` column the column is as wide as the
  widest cell that sits in it alone, measured on one line, then trimmed to the space that is left (widest
  columns are trimmed first). In a `fill` column the text wraps at the column width.
- Height: as many lines as the text needs, up to the line limit. The row is as tall as its tallest cell.
- Text with its own `alignment` fills its cell's width and aligns inside it; text without hugs its content and
  the cell's `align` places it.

## 9-point alignment

The cell's `align` places a short text block inside a taller or wider cell. Its horizontal part is also the
line alignment when `alignment` is not set. Example: `"align":"topTrailing"` puts the text at the top-right
and right-aligns its lines.

## Empty behaviour

Empty when: every `{token}` in `binding` is absent or blank (a binding with no tokens is empty only if it is
blank). A kept empty text holds one invisible line, so its row keeps the height of one line.

## Light and dark

Keyword colours follow the system. Hex colours are nudged to read on the current appearance. With no `color`,
`title`, `body` and `mono` are primary and `subtitle` and `caption` are secondary.

## Actions wiring

Text has no action of its own. A Markdown link inside `body` text opens its URL (http, https and mailto only;
anything else is blocked and recorded in history as a blocked link). A click on a link never also triggers the
banner's own click.

## Examples

A two-line title:

```json
{"type":"text","binding":"{title}","style":"title","maxLines":2}
```

A sender and subject that degrades when the sender is missing:

```json
{"type":"text","binding":"{sender}: {subject}","style":"body","maxLines":3,"emptyBehavior":"collapse"}
```

A right-aligned caption in a fixed accent colour, in a complete template:

```json
{"name":"text-demo","app":"demo","layoutVersion":2,"collapseEmpty":true,
 "grid":{"rows":2,"cols":2,"rowSizes":["auto","auto"],"colSizes":["fill","auto"],"gap":6,"padding":12,"width":380},
 "cells":[
  {"id":"title","row":0,"col":0,"component":{"type":"text","binding":"{title}","style":"title"}},
  {"id":"tag","row":0,"col":1,"align":"topTrailing",
   "component":{"type":"text","binding":"build {extra.build}","style":"caption","color":"accent","weight":"semibold"}},
  {"id":"body","row":1,"col":0,"colSpan":2,
   "component":{"type":"text","binding":"{body}","style":"body","markdown":true,"maxLines":4}}],
 "extra":{"build":"214"}}
```

## Common mistakes

| Mistake | What happens | Fix |
|---|---|---|
| `"binding":"title"` (no braces) | Shows the literal word "title". | `"{title}"`. |
| Putting `colspan` or `maxlines` in lower case | Ignored (validator warns about unknown keys). | Use the exact camel-case names. |
| `fontSize` of 5 or 80 | Validation error: 6 to 72. | Stay in range. |
| Expecting Markdown in a `title` | Shown as typed. | Set `"markdown": true`. |
| A long title in an `auto` column | The column grows until the space runs out, squeezing neighbours. | Use a `fill` column and a `maxLines`. |
| Text token that is a number with decimals | Prints the number as sent (`3.5`). | Format it in the issuer. |
