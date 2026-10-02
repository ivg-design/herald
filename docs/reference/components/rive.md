# rive

A Rive animation inside a banner cell. This page is the property reference; preparing the file, uploading it
and troubleshooting are in [../rive.md](../rive.md).

## Properties

| Property | Type | Default | Allowed values / notes |
|---|---|---|---|
| `type` | string | required | `"rive"` |
| `asset` | string | none | Id of an asset the issuer's manifest declares (or of a stored copy, `<id>.riv`). Wins over `path` when both are set. |
| `path` | string | none | A `.riv` file: absolute, `~/...`, a `file:` URL, or a name relative to the app's assets folder (no `..`). Remote URLs are refused. |
| `stateMachine` | string | the manifest asset's, else the file's default, else its first | State machine name. |
| `artboard` | string | the file's default artboard | Artboard name. |
| `inputBindings` | object | `{}` | Map of state machine input name to a `{token}` / literal, or to the keywords `hover` / `pressed`. |
| `action` | action object or string | none | Clicking the animation runs this action (inline). |
| `actionRef` | string | none | Clicking the animation runs this resolved action by id. |
| `loop` | boolean | the animation's own | Only for a file with no state machine (a linear animation): `true` loops, `false` plays once. |
| `aspectRatio` | number > 0 | the artboard's own | Width / height of the box. |
| `height` | number > 0 | derived | Fixed height in points. |
| `emptyBehavior` | string | template default | `collapse` or `keep`. |

A component needs an `asset` or a `path`; otherwise validation fails. With a manifest, an `asset` that the
manifest does not declare, or an input name the manifest asset's `inputs` list does not contain, is a warning.

## Bindings and tokens

`inputBindings` values are bound per input, see [../rive.md](../rive.md#inputs-and-how-fields-drive-them):

| Value | Meaning |
|---|---|
| `"{count}"` | A single token: the field's own value, so a number stays a number. |
| `"3"` or `"{count} new"` | Literal or mixed text: bound as the substituted text. |
| `"hover"` / `"pressed"` (any case) | Driven by the mouse over the animation, never by data. |

## Sizing

- `height` fixes the height; the width follows from `aspectRatio` (or the artboard's ratio) when not given.
- With no `height`, the box takes the width of its cell and the height from the aspect ratio (explicit, else
  the artboard's, else 4:1).
- The animation is scaled with `contain` (whole artboard visible), centred.
- The box is clamped to 1 to 2000 points on each side. A failed load is 44 points high.

## 9-point alignment

The box fills the cell width; alignment only positions it when the cell is larger than the box (fixed-height
rows). Match the artboard's proportions to the box and there is nothing to align.

## Empty behaviour

Empty only when neither `asset` nor `path` is set (which validation rejects anyway). Tokens in
`inputBindings` do **not** make it empty: an animation with absent fields still plays, and an absent token
leaves its input alone.

## Light and dark

Rive draws exactly what is in the file. Banners are translucent over the desktop and the animation is drawn
on a transparent background, so design with transparent artboards and colours that work on both. Herald does
not switch Rive themes or inputs on appearance; add a boolean input and bind it to a field if you need it.

## Actions wiring

- With `action` or `actionRef`, a click on the animation (mouse down and up inside it) runs that action, the
  pointer becomes a pointing hand and VoiceOver sees a button. Without either, clicks fall through to the
  banner body (it still tracks hover).
- A `pressed` binding also makes the animation take clicks, so the press can drive the state machine.
- Gates are the same as for [button.md](button.md#actions-wiring).

## Static previews

`POST /v1/preview`, MCP `render_preview` and history previews draw a dashed placeholder with the asset name
at the right size, not the animation. Check the animation with `POST /v1/rive/check`.

## Examples

A bell that rings when `count` changes, reacts to hover and opens the message on click:

```json
{"type":"rive","asset":"bell","stateMachine":"Main",
 "inputBindings":{"count":"{count}","hover":"hover"},"height":40,
 "action":{"id":"open","label":"Open","kind":"url","url":"{url}"}}
```

A loop-once linear animation from a file in the issuer's assets folder, kept in place:

```json
{"type":"rive","path":"spinner.riv","loop":true,"aspectRatio":1,"height":24,"emptyBehavior":"keep"}
```

In a complete template next to a title:

```json
{"name":"rive-demo","app":"webwatcher.email","layoutVersion":2,"collapseEmpty":true,
 "grid":{"rows":2,"cols":3,"rowSizes":["auto","auto"],"colSizes":["48","fill","auto"],"gap":8,"padding":14,"width":400},
 "cells":[
  {"id":"bell","row":0,"col":0,"rowSpan":2,"align":"topLeading",
   "component":{"type":"rive","asset":"bell","stateMachine":"Main","height":40,
                "inputBindings":{"count":"{count}","hover":"hover"},"actionRef":"markRead"}},
  {"id":"title","row":0,"col":1,"component":{"type":"text","binding":"{title}","style":"title","maxLines":2}},
  {"id":"badge","row":0,"col":2,"align":"topTrailing","component":{"type":"badge","binding":"{count}","color":"#FF3B30"}},
  {"id":"sub","row":1,"col":1,"colSpan":2,"component":{"type":"text","binding":"{subject}","style":"subtitle"}}]}
```

## Common mistakes

| Mistake | What happens | Fix |
|---|---|---|
| State machine or input names with the wrong case | `no state machine "main" (available: Main)` placeholder; unknown inputs are silently ignored. | Names are case-sensitive; copy them from `POST /v1/rive/check`. |
| Binding a text value to a number input | A non-numeric string is ignored. | Bind a numeric field, or a list (its length). |
| Expecting a Rive hover listener to fire | Pointer-move events are not forwarded to Rive. | Use a boolean input and `"hover":"hover"`. |
| Checking the animation with `render_preview` | Shows a placeholder. | Use `/v1/rive/check`, or look in the live banner. |
