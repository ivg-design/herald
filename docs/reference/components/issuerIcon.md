# Issuer icon component

The `issuerIcon` component draws the icon of the app that sent the notification, so a banner shows which app is talking.
The Designer calls it **App icon**. The icon comes from the app's registration or manifest, not from a field, so it is
the same on every banner from that app. If the app has no icon, Herald draws a generic app icon. For a different
picture on every banner use [`image`](image.md).

**Minimal example**

```json
{"type":"issuerIcon"}
```

This draws the icon 22 points wide with rounded corners.

**Realistic example**

A 32 point round icon that spans the first two rows, with a title and a subject beside it.

```json
{"name":"icon-demo","app":"example.bidbot","layoutVersion":2,"collapseEmpty":true,
 "grid":{"rows":2,"cols":2,"rowSizes":["auto","auto"],"colSizes":[40,"fill"],"gap":6,"padding":12,"width":380},
 "cells":[
  {"id":"icon","row":0,"col":0,"rowSpan":2,"align":"topLeading",
   "component":{"type":"issuerIcon","size":32,"shape":"circle"}},
  {"id":"title","row":0,"col":1,"component":{"type":"text","binding":"{title}","style":"title"}},
  {"id":"body","row":1,"col":1,"component":{"type":"text","binding":"{body}","style":"subtitle"}}]}
```

**Properties**

| Property | Type | Default | Description |
|---|---|---|---|
| `type` | string | required | Always `"issuerIcon"`. |
| `size` | number | `22` | The side of the icon in points, from 8 to 128. |
| `shape` | string | `rounded` | `rounded` draws a rounded square and `circle` draws a circle. |
| `cornerRadius` | number | 22 percent of `size` | The corner radius in points for `rounded`. It must be 0 or more and is ignored for `circle`. |
| `symbol` | name or object | none | An SF Symbol drawn instead of the app's icon. The app's icon is drawn when the name is not a symbol on this Mac. See [SF Symbols](../symbols.md). |
| `emptyBehavior` | string | none | Accepted, but it has no effect because the component is never empty. |

## Where the icon comes from

The icon is part of the app record. It is the `icon` that the app gave when it registered with [`POST /v1/register`](../api/apps.md#post-v1register) or that its [manifest](../manifests.md) declares. Two facts about it:

- It is a file path or a `data:image/png;base64,...` URI of at most 256 KB.
- Its tooltip is the app's display name, the `appName` of the manifest. Hovering over the icon on a banner shows it.

An icon is drawn as supplied, so it looks the same in light and dark appearance. A symbol follows its rendering mode and
colours. Without colours a symbol is drawn in the primary text colour at about 62 percent of `size`.

## Sizing and alignment

The icon is exactly `size` by `size` points.

- In an `auto` column or row it sets the size of the track.
- In a fixed 40 point column a 32 point icon sits inside the column where the cell's `align` puts it.
- Alignment matters whenever the cell is larger than the icon, for example `topLeading` for an icon that spans two rows.

## Empty icons

An icon is never empty, because there is always something to draw. `emptyBehavior` has no effect.

## Common mistakes

| Mistake | What happens | Fix |
|---|---|---|
| Expecting the icon to change from one notification to the next. | It never does, because it comes from the app record. | Use an `image` bound to a field for per-notification art. |
| A `size` of 4 or 200. | The validator reports an error. | Stay between 8 and 128. |
| Setting `cornerRadius` with `circle`. | It is ignored. | Use `rounded`. |

## Related

- [Image component](image.md): a picture that changes with every notification.
- [Manifests](../manifests.md): the `icon` and `appName` of an app.
- [SF Symbols](../symbols.md): drawing a symbol in place of the icon.
- [Designing a banner](../../AUTHORING.md): adding the **App icon** component in the Designer.
