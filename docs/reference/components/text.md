# Text component

The `text` component draws bound text: a title, a subtitle, a body, a caption or a monospaced value. It is the most used
component, and the Designer calls it **Text**. Use it for every line of words on a banner. It can hold several lines,
and each line can have its own alignment and styled words. For a number in a pill use [`badge`](badge.md), and for a
date use [`timestamp`](timestamp.md).

**Minimal example**

```json
{"type":"text","binding":"{title}","style":"title"}
```

**Realistic example**

A two-column header: the title on the left and a build tag in the accent colour on the right, then a body that allows
Markdown links.

```json
{"name":"text-demo","app":"example.bidbot","layoutVersion":2,"collapseEmpty":true,
 "grid":{"rows":2,"cols":2,"rowSizes":["auto","auto"],"colSizes":["fill","auto"],"gap":6,"padding":12,"width":380},
 "cells":[
  {"id":"title","row":0,"col":0,"component":{"type":"text","binding":"{title}","style":"title"}},
  {"id":"tag","row":0,"col":1,"align":"topTrailing",
   "component":{"type":"text","binding":"build {extra.build}","style":"caption","color":"accent","weight":"semibold"}},
  {"id":"body","row":1,"col":0,"colSpan":2,
   "component":{"type":"text","binding":"{body}","style":"body","markdown":true,"maxLines":4}}],
 "extra":{"build":"214"}}
```

In the picture below, look at the three lines of text: the bold title, the grey subtitle line and the body. Each is a text component, and the styles `title`, `subtitle` and `body` give them their size and colour.

![A banner with a bold title, a grey subtitle line and two lines of body text](../../../web/public/shots/docs/banner-plain.png "Each line of text on the banner is a text component. The bold title uses the title style, the grey line the subtitle style and the last lines the body style.")

**Properties**

| Property | Type | Default | Description |
|---|---|---|---|
| `type` | string | required | Always `"text"`. |
| `binding` | string | required unless `lines` is set | The text, with `{token}` placeholders. A binding with no token is literal text. It may hold line breaks and [rich text markup](#rich-text-markup). |
| `lines` | array | none | The text as structured lines of styled runs. When set it takes precedence over `binding`. See [Structured lines](#structured-lines). |
| `lineSpacing` | number | `0` | Extra points between lines. It must be 0 or more. |
| `style` | string | `body` | A typography preset: `title`, `subtitle`, `body`, `caption` or `mono`. |
| `maxLines` | integer | per style | The most lines to show, at least 1. When it is omitted the style decides. |
| `color` | string | per style | A hex colour, or `accent`, `primary` or `secondary`. |
| `fontSize` | number | per style | The size in points, from 6 to 72. |
| `weight` | string | per style | The font weight: `regular`, `medium`, `semibold` or `bold`. |
| `alignment` | string | follows the cell | The horizontal alignment of the lines: `leading`, `center` or `trailing`. A line's own `align` overrides it. |
| `markdown` | boolean | `true` for `body`, else `false` | Whether `[text](url)` links in the text are drawn as links. |
| `emptyBehavior` | string | template default | `collapse` or `keep`. See [Empty text](#empty-text-and-line-limits). |

## Styles

A style sets the font, the colour and how many lines show when you set none of your own.

| Style | Font | Default colour | Default line limit |
|---|---|---|---|
| `title` | 13 pt semibold | primary | 2 |
| `subtitle` | 12 pt regular | secondary | 2 |
| `body` | 12 pt regular | primary | The banner's `maxBodyLines`, which is 8 unless the template or notification sets it. |
| `caption` | 10 pt regular | secondary | 1 |
| `mono` | 11 pt monospaced | primary | 4 |

`color`, `fontSize` and `weight` replace the style's value for the whole component. A run in `lines` can replace them
again for a few words.

## Writing the binding

The binding reads any token described in [Bindings and tokens](../bindings.md), which lists the standard fields, the fields a manifest declares, `{extra.key}` for the template's own values, and dotted names such as `{customer.name}` for nested metadata. Values print in a fixed way:

- Numbers print without a trailing `.0`.
- Booleans print as `true` or `false`.
- Lists are joined with `, `.

In a binding that mixes tokens and text, an absent token becomes empty text and the literal text stays. The result is
trimmed. `"{sender}: {subject}"` without a `sender` reads `: Invoice`. Prefer two components when the parts should
disappear independently.

## Rich text markup

A binding, and the `text` of a run, can carry light markup. It works in every style. The Designer's text editor writes it
for you.

| Write | Result |
|---|---|
| A line break (`\n` in JSON) | A new line. |
| `**bold**` | Bold weight. |
| `*italic*` | Italic. |
| `` `mono` `` | A monospaced font. |
| `__underline__` | An underline. |
| `~~strike~~` | A strikethrough. |
| `{{size=14 color=#FF3B30 font=serif weight=medium}}text{{/}}` | A span. Any of `size` (6 to 72), `color` (same values as `color`), `font` (`sans`, `mono`, `serif`, `rounded`) and `weight` can be given. `{{/}}` closes it. |
| `{{align=center}}` at the very start of a line | Aligns that line: `leading`, `center` or `trailing`. |
| A backslash before `*`, `_`, `~`, a backtick, `{` or another backslash | That character itself. |
| `{token}` | A field, as everywhere else. |

Rules for markup:

- Markers combine (`***both***`, `**{project}**`) and can wrap tokens.
- They never span a line break, and a span ends at the end of its line.
- A marker with no partner, such as `**oops`, is shown as typed.
- Values that arrive through tokens are never read as markup.
- Markup has no links. Use `markdown` for `[text](url)`.

`validate_template` warns about an unpaired marker, an unknown span key, a bad value, and `{{align=...}}` anywhere but the start of a line.

This binding writes a bold label on one line and an italic monospaced value, right-aligned, on the next:

```json
{"type":"text","binding":"**Project:**\n{{align=trailing}}*`{project}`*","style":"body"}
```

## Structured lines

`lines` is the same model written out as data. Use it when an agent builds the text programmatically. Both forms compile
to the same thing, and the Designer converts between them without loss.

```json
{"type":"text","style":"body","lineSpacing":2,"lines":[
  {"runs":[{"text":"Project:","weight":"bold"}]},
  {"align":"trailing","runs":[{"token":"{project}","italic":true,"font":"mono","color":"accent"}]}]}
```

| Key | On | Description |
|---|---|---|
| `align` | line | `leading`, `center` or `trailing`. It overrides the component's `alignment` for this line. |
| `runs` | line | The pieces of the line, drawn one after another. |
| `text` | run | Literal text. Markup is allowed. When a run has both `text` and `token`, the text comes first. |
| `token` | run | A field written as `"{project}"`. |
| `weight`, `italic`, `font`, `size`, `color`, `underline`, `strike` | run | Override the component's `style`, `fontSize`, `weight` and `color` for this run. A key you leave out is inherited. |

Three rules apply to `lines`:

- When `lines` is set, `binding` is ignored.
- A run needs `text` or `token`.
- A run `size` must be 6 to 72.

## Empty text and line limits

How empty lines are handled:

- A line that contains tokens, all of them absent, is empty. It is dropped, or with `emptyBehavior` set to `keep` it stays as a blank line.
- A line of literal text stays even when its neighbour is empty: `"Project:\n{project}"` without a `project` shows just `Project:`.
- The component is empty when every line is, so `"{count} new"` with no `count` collapses instead of showing the word "new".
- Blank lines at the top and bottom are trimmed, and a blank line in the middle is kept as spacing.

`maxLines` counts lines. Lines beyond the limit are cut off, and a line that wraps may use whatever the others leave.
Clicking a banner whose text was cut shows all of it and the banner grows. A second click folds it back. The behaviour is
described in [How banners behave](../banners.md).

![A banner whose long body ends in an ellipsis at its line limit](../../../web/public/shots/docs/banner-long-collapsed.png "A long body is cut at its line limit.")

After one click the same banner shows the whole text.

![The same banner after a click, with the whole body shown](../../../web/public/shots/docs/banner-long-expanded.png "A click on the banner lifts the line limits so the whole text is readable.")

## Sizing and alignment

- In a fixed-width column the text wraps inside it.
- In an `auto` column the column is as wide as the widest cell that sits in it alone, measured on one line, then trimmed
  to the space that is left. The widest columns are trimmed first.
- In a `fill` column the text wraps at the column width.
- The height is as many lines as the text needs, up to the line limit. A row is as tall as its tallest cell.
- A text with its own `alignment`, or with a line that has an `align`, fills its cell's width and aligns inside it. A text
  without one hugs its content and the cell's `align` places it. `"align":"topTrailing"` puts the text at the top right
  and right-aligns its lines.
- A kept empty text holds one invisible line, so its row keeps the height of a line.

## Links

Text has no action of its own. When `markdown` is on, a `[text](url)` link opens its URL. Three rules apply to links:

- Only `http`, `https` and `mailto` links open. Any other scheme is blocked, and History records the click as a blocked link.
- A click on a link never also triggers the banner's own click.

## Common mistakes

| Mistake | What happens | Fix |
|---|---|---|
| `"binding":"title"` with no braces. | The banner shows the literal word "title". | Write `"{title}"`. |
| A wrong case in a key, such as `maxlines`. | The key is ignored and the validator warns about an unknown key. | Use the exact camel-case names. |
| A `fontSize` of 5 or 80. | The validator reports an error. | Stay between 6 and 72. |
| A `[link](url)` in a `title`. | It is shown as typed. | Set `"markdown": true`. |
| A literal `*` or `_` pair in the text. | It is read as markup. | Write `\*` or `\_`. |
| `{{align=center}}` in the middle of a line. | It is ignored and the validator warns. | Put it first on the line. |
| A long title in an `auto` column. | The column grows until the space runs out and squeezes its neighbours. | Use a `fill` column and a `maxLines`. |
| Expecting a decimal to be rounded. | It prints as sent, for example `3.5`. | Format the number in the app that sends it. |

## Related

- [Designing a banner](../../AUTHORING.md): the Designer's text editor and inspector.
- [Bindings and tokens](../bindings.md): the fields a binding can read.
- [The grid, cells and layout](../grid-and-layout.md): how column and row sizes treat text.
- [How banners behave](../banners.md): clicking a banner to expand cut-off text.
- [Timestamp component](timestamp.md) and [Badge component](badge.md): the other components that show values.
