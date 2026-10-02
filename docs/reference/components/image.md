# image

A picture bound to a field: a preview thumbnail, a hero image, a logo.

## Properties

| Property | Type | Default | Allowed values / notes |
|---|---|---|---|
| `type` | string | required | `"image"` |
| `binding` | string | `"{image}"` | Resolves to a file path (`~` is expanded), a `file:` URL, a `data:` URI or an https URL. |
| `fit` | string | `cover` | `fit` (whole picture, letterboxed), `fill` (stretched to the cell, distorting it), `cover` (fills the cell, crops the overflow). |
| `cornerRadius` | number >= 0 | 0 | Points; continuous corners. |
| `aspectRatio` | number > 0 | the picture's own, else 1 | Width / height: `1` square, `1.7778` for 16:9. |
| `height` | number > 0 | none | Fixed height in points. Wins over `aspectRatio`. |
| `emptyBehavior` | string | template default | `collapse` or `keep`. |

## Bindings and tokens

The standard token `{image}` is the notification's own `image`. It is present whenever the banner has a
picture, including previews that were handed one. A manifest field of type `image` (for example
`thumbnail`) works the same way: bind `"{thumbnail}"`.

Where pictures come from:

| Source | How it is loaded |
|---|---|
| The notification's `image` | Downloaded once if it is a URL, validated by its bytes (PNG, JPEG, GIF, WebP, HEIC, AVIF, TIFF, BMP, at most 10 MB), and cached under `history/images`. The spec itself is at most 256 KB. Anything else is ignored. |
| Another binding that resolves to a local path or `data:` URI | Read from disk, cached in memory (64 pictures). |
| Another binding that resolves to an http(s) URL | Drawn with `AsyncImage` while the banner is live; not downloaded ahead of time. Static previews draw nothing for it. |

## Sizing

The image fills the width of its cell. Height comes from `height` if set, else from the aspect ratio
(explicit, else the picture's own, else 1). In an `auto` column the ideal side is 48 points. In a row with
`auto` height the picture decides the row's height, so a 72 pt column with `aspectRatio: 1` gives a 72 pt
square. A picture spanning two rows lends its extra height to the last non-fixed row it covers.

## 9-point alignment

The image box fills its cell, so alignment only matters when the cell is taller than the picture needs (a
fixed-height row): then it positions the box vertically.

## Empty behaviour

Empty when the binding's token is absent, **or** when the field names something nothing can show (a missing
file, a failed download). That second rule means a template with `collapse` never leaves a blank square
for a broken image path. A kept empty image is a transparent box of the same size, so the layout holds.

## Light and dark

Pictures are drawn as they are. Corner clipping uses the same radius in both appearances.

## Actions wiring

None. A click on the picture is a click on the banner (it opens the notification's `url`).

## Examples

A square thumbnail with rounded corners:

```json
{"type":"image","binding":"{image}","fit":"cover","cornerRadius":10,"aspectRatio":1}
```

A 16:9 hero across the whole banner, in a complete template:

```json
{"name":"hero-demo","app":"demo","layoutVersion":2,"collapseEmpty":true,
 "grid":{"rows":2,"cols":1,"rowSizes":["auto","auto"],"colSizes":["fill"],"gap":8,"padding":0,"width":380},
 "cells":[
  {"id":"hero","row":0,"col":0,"component":{"type":"image","binding":"{image}","fit":"cover","aspectRatio":1.7778}},
  {"id":"text","row":1,"col":0,"padding":14,"component":{"type":"text","binding":"{title}","style":"title"}}]}
```

A fixed-height logo from a manifest field, kept in place when absent:

```json
{"type":"image","binding":"{logo}","fit":"fit","height":28,"emptyBehavior":"keep"}
```

## Common mistakes

| Mistake | What happens | Fix |
|---|---|---|
| Setting both `height` and `aspectRatio` | `height` wins; the ratio only sets the width hint. | Pick one. |
| Using `fill` to fill the cell | Stretches and distorts. | Use `cover`. |
| Binding a remote URL in a non-`image` field and checking with `render_preview` | Static previews draw nothing for it. | Check live, or send it as the notification's `image`. |
| An image over 10 MB or an unsupported format | Ignored, the component collapses. | Resize; use PNG or JPEG. |
| Putting a 72 pt fixed row for a square image in an `auto` column | The picture is cropped or letterboxed to the fixed size. | Use an `auto` row and let `aspectRatio` set the height. |
