# issuerIcon

The sending app's icon: the `icon` from `POST /v1/register` or the manifest, else a generic app icon.

## Properties

| Property | Type | Default | Allowed values / notes |
|---|---|---|---|
| `type` | string | required | `"issuerIcon"` |
| `size` | number 8 to 128 | 22 | Side in points. |
| `shape` | string | `rounded` | `rounded` or `circle`. |
| `cornerRadius` | number >= 0 | 22 % of `size` | Points. Ignored for `circle`. |
| `emptyBehavior` | string | template default | Accepted, but the component is never empty. |
| `symbol` | name or object | none | **Available from 1.3.** An SF Symbol drawn instead of the app icon; the app icon is the fallback when the name is unknown. See [../symbols.md](../symbols.md). |

## Bindings and tokens

None. The icon comes from the app record (`icon` is a file path or `data:image/png;base64,...`, at most
256 KB), not from a field. The icon's tooltip is the app's display name (`appName`).

## Sizing

Exactly `size` x `size` points. In an `auto` column or row it sets the track's size; in a fixed 40 pt column a
32 pt icon sits inside it according to the cell's alignment.

## 9-point alignment

Matters whenever the cell is bigger than the icon, for example `topLeading` for an icon that spans two rows.

## Empty behaviour

Never empty (it always has an icon to draw), so `emptyBehavior` has no effect.

## Light and dark

The icon is drawn as supplied. A symbol (1.3) follows its rendering mode and colours.

## Actions wiring

None.

## Examples

The default small icon:

```json
{"type":"issuerIcon","size":22,"shape":"rounded"}
```

A circular 32 pt avatar spanning the first two rows:

```json
{"id":"icon","row":0,"col":0,"rowSpan":2,"align":"topLeading",
 "component":{"type":"issuerIcon","size":32,"shape":"circle"}}
```

A symbol in place of the icon (available from 1.3):

```json
{"type":"issuerIcon","size":24,"symbol":{"name":"envelope.badge","renderingMode":"palette","colors":["accent","primary"]}}
```

## Common mistakes

| Mistake | What happens | Fix |
|---|---|---|
| Expecting a field-driven icon | The icon never changes per notification. | Use an `image` bound to a field for per-notification art. |
| `size` of 4 or 200 | Validation error (8 to 128). | Stay in range. |
| Setting `cornerRadius` with `circle` | Ignored. | Use `rounded`. |
