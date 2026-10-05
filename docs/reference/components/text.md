# text

Bound text: a title, a subtitle, a body, a caption, a monospaced value. The workhorse component.

## Properties

| Property | Type | Default | Allowed values / notes |
|---|---|---|---|
| `type` | string | required | `"text"` |
| `binding` | string | required unless `lines` is set | Text with `{token}` placeholders: `"{title}"`, `"{count} new from {sender}"`. A binding with no token at all is a literal. Blank is an error. May hold real line breaks (`\n` in JSON) and the [rich text markup](#rich-text). |
| `lines` | array | none | Structured rich text: [lines of styled runs](#structured-form-lines). Takes precedence over `binding`. |
| `lineSpacing` | number >= 0 | 0 | Extra points between lines. |
| `style` | string | `body` | `title`, `subtitle`, `body`, `caption`, `mono`. |
| `maxLines` | integer >= 1 | per style | Line limit. Omitted: the style's default (below). |
| `color` | string | per style | `#RGB`, `#RRGGBB`, `#RRGGBBAA`, `accent`, `primary`, `secondary`. |
| `fontSize` | number 6 to 72 | per style | Points. |
| `weight` | string | per style | `regular`, `medium`, `semibold`, `bold`. |
| `alignment` | string | follows the cell | `leading`, `center`, `trailing`. Horizontal alignment of the lines. A line's own `align` overrides it. |
| `markdown` | boolean | true for `body`, else false | Render inline Markdown links (`[text](url)`) in the text. The rich text markup (`**bold**` and the rest) works in every style whatever this is set to. |
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

In a mixed binding an absent token becomes empty text and the literal text stays: `"{sender}: {subject}"`
without `sender` reads `: Invoice`. The result is trimmed of surrounding whitespace. Only when **every** token is
absent is the component empty (literal text alone does not keep it alive), so `"{count} new"` with no count
collapses instead of showing "new". Prefer two components when the parts should collapse independently.

## Rich text

A text can have several lines, and each line can have its own alignment and styled words. Two ways to write it;
both compile to the same model, and the Designer converts between them without loss.

### Markup (in `binding` and in a run's `text`)

| Write | Result |
|---|---|
| a real line break (`\n` in JSON) | a new line |
| `**bold**` | weight bold |
| `*italic*` | italic |
| `` `mono` `` | monospaced font |
| `__underline__` | underline |
| `~~strike~~` | strikethrough |
| `{{size=14 color=#FF3B30 font=serif weight=medium}}text{{/}}` | a span: any of `size` (6 to 72), `color` (as `color` above), `font` (`sans`, `mono`, `serif`, `rounded`), `weight` (`regular`, `medium`, `semibold`, `bold`), closed by `{{/}}` |
| `{{align=center}}` at the very start of a line | that line's alignment: `leading`, `center`, `trailing` |
| `\*` `\_` `\~` `` \` `` `\{` `\\` | the character itself |
| `{token}` | a field, as everywhere |

Markers combine (`***both***`, `**{project}**`) and may sit around tokens. They never span a line break and a
span ends at the end of its line. A marker with no partner (`**oops`) is shown as typed and `validate_template`
warns; so does an unknown span key, a bad value or `{{align=...}}` anywhere but the start of a line. Values that
tokens bring in are never read as markup. There are no links in the markup: use `markdown` for `[text](url)`.

```json
{"type":"text","binding":"**Project:**\n{{align=trailing}}*`{project}`*"}
```

### Structured form (`lines`)

```json
{"type":"text","style":"body","lineSpacing":2,"lines":[
  {"runs":[{"text":"Project:","weight":"bold"}]},
  {"align":"trailing","runs":[{"token":"{project}","italic":true,"font":"mono","color":"accent"}]}]}
```

| Key | Where | Meaning |
|---|---|---|
| `align` | line | `leading`, `center`, `trailing`; overrides the component's `alignment` for this line |
| `runs` | line | the pieces of the line, drawn one after another |
| `text` | run | literal text (markup allowed); filled before `token` when both are given |
| `token` | run | a field, `"{project}"` |
| `weight`, `italic`, `font`, `size`, `color`, `underline`, `strike` | run | override the component's `style`, `fontSize`, `weight` and `color` for this run; a key left out inherits |

When `lines` is set, `binding` is ignored (the Designer writes a plain-text copy of it for older readers).

### Empty lines and line limits

- A line that has tokens and whose tokens are **all** absent is empty: it collapses (it is dropped), or with
  `emptyBehavior: "keep"` stays as a blank line. A line of literal text stays even if its neighbour is empty:
  `"Project:\n{project}"` without `project` shows just `Project:`.
- The component is empty when every line is. Blank lines at the top and bottom are trimmed; one in the middle is
  kept as spacing.
- `maxLines` counts lines: lines beyond it are cut off, and a line that wraps may use what the others leave. Clicking a banner whose
  text was cut shows all of it (the banner grows); a second click folds it back. See [Clicking a banner](../api.md#clicking-a-banner).
- Each line wraps inside the column on its own. Height comes from the real layout of every line.

### In the Designer

The Text field is a multi-line editor (Return adds a line, Option-Return too, Command-Return finishes). The bar
above it acts on the selection: bold, italic, monospace, underline, strikethrough, size down/up, colour; the
segmented control aligns the line the caret is on; the `{}` menu inserts a field at the caret. The markup stays
visible in the field and a rendered preview sits below it. Unstyled text is stored as plain `binding`; as soon as
anything is styled the component stores `lines`.

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

A sender and subject (note that without `sender` it reads `: subject`; split it if that matters):

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

A two-row label and value, the value right-aligned in a monospaced italic:

```json
{"type":"text","binding":"**Project:**\n{{align=trailing}}*`{project}`*","style":"body"}
```

## Common mistakes

| Mistake | What happens | Fix |
|---|---|---|
| `"binding":"title"` (no braces) | Shows the literal word "title". | `"{title}"`. |
| Putting `colspan` or `maxlines` in lower case | Ignored (validator warns about unknown keys). | Use the exact camel-case names. |
| `fontSize` of 5 or 80 | Validation error: 6 to 72. | Stay in range. |
| Expecting a `[link](url)` in a `title` | Shown as typed. | Set `"markdown": true`. (`**bold**` and the other rich text markers work in any style.) |
| A literal `*` or `_` pair in text | Read as markup. | Write `\*`. |
| `{{align=center}}` in the middle of a line | Ignored, warned. | Put it first on the line. |
| A long title in an `auto` column | The column grows until the space runs out, squeezing neighbours. | Use a `fill` column and a `maxLines`. |
| Text token that is a number with decimals | Prints the number as sent (`3.5`). | Format it in the issuer. |
