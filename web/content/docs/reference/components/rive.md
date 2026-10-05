# Rive component

The `rive` component plays a Rive animation inside a cell: a bell that rings when the count goes up, a spinner, a small
character that reacts to the pointer. The Designer calls it **Rive**. The animation's state machine inputs can follow
fields of the notification and the position of the pointer, and a click on it can run an action.

This page is the property reference. Preparing the file in the Rive editor, getting it into Herald, and troubleshooting
are in [Rive in Herald](../rive.md).

**Minimal example**

```json
{"type":"rive","asset":"bell"}
```

This plays the file that the app's manifest declares as the asset `bell`, using the asset's state machine or the file's
default.

**Realistic example**

A bell next to a title and a count. The bell rings when `count` changes, reacts when the pointer is over it, and marks the
message read when it is clicked.

```json
{"name":"rive-demo","app":"example.bidbot","layoutVersion":2,"collapseEmpty":true,
 "grid":{"rows":2,"cols":3,"rowSizes":["auto","auto"],"colSizes":[48,"fill","auto"],"gap":8,"padding":14,"width":400},
 "cells":[
  {"id":"bell","row":0,"col":0,"rowSpan":2,"align":"topLeading",
   "component":{"type":"rive","asset":"bell","stateMachine":"Main","height":40,
                "inputBindings":{"count":"{count}","hover":"hover"},"actionRef":"markRead"}},
  {"id":"title","row":0,"col":1,"component":{"type":"text","binding":"{title}","style":"title","maxLines":2}},
  {"id":"badge","row":0,"col":2,"align":"topTrailing","component":{"type":"badge","binding":"{count}","color":"#FF3B30"}},
  {"id":"sub","row":1,"col":1,"colSpan":2,"component":{"type":"text","binding":"{subject}","style":"subtitle"}}]}
```

**Properties**

| Property | Type | Default | Description |
|---|---|---|---|
| `type` | string | required | Always `"rive"`. |
| `asset` | string | none | The id of an asset that the app's manifest declares, or of a stored copy. It wins over `path` when both are set. |
| `path` | string | none | A `.riv` file instead of an asset. The accepted forms are listed under the table. |
| `stateMachine` | string | the asset's, else the file's default, else its first | The name of the state machine to play. |
| `artboard` | string | the file's default | The name of the artboard to draw. |
| `inputBindings` | object | none | Maps the name of a state machine input to a `{token}`, a literal, or the keyword `hover` or `pressed`. See [Inputs](#inputs). |
| `action` | object | none | An inline action that a click on the animation runs. |
| `actionRef` | string | none | The id of a resolved action that a click on the animation runs. |
| `loop` | boolean | the animation's own | For a file with no state machine only: `true` loops the animation and `false` plays it once. |
| `aspectRatio` | number | the artboard's own | Width divided by height of the box, above 0. |
| `height` | number | derived | A fixed height in points, above 0. |
| `emptyBehavior` | string | template default | `collapse` or `keep`. See [Empty animations](#empty-animations). |

`path` accepts these forms:

- An absolute path.
- `~/...`.
- A `file:` URL.
- A name relative to the app's assets folder. A relative path cannot contain `..`.

Remote URLs are refused.

The component needs an `asset` or a `path`. Without one the validator reports an error. When a manifest is given, two cases are a warning:

- An `asset` that the manifest does not declare.
- An input name that the asset's `inputs` list does not contain.

## What plays

Herald loads the file, checks that it is a `.riv` file of at most 10 MB, and plays it with the whole artboard visible and
centred in its box. The state machine is the first of these that exists: `stateMachine`, the manifest asset's state
machine, the file's default, then the file's first. A file with no state machine plays its first animation, and `loop`
chooses between looping and playing once.

If the file cannot be found, is too large, is not a Rive file, or names an artboard or state machine that does not exist,
the cell shows a dashed placeholder that gives the reason, for example `no state machine "main" (available: Main)`. The
banner is not affected otherwise.

## Inputs

Each entry of `inputBindings` connects one input of the state machine to a value. Herald tells number, boolean and trigger
inputs apart by asking the state machine.

| Value | Meaning |
|---|---|
| `"{count}"` | One token. The field's own value is used, so a number stays a number. |
| `"3"` or `"{count} new"` | A literal or mixed text. The substituted text is the value. |
| `"hover"` or `"pressed"`, in any case | The pointer drives the input and data never does. |

How a value is applied depends on the input:

| Input kind | A field value is applied as | `hover` and `pressed` |
|---|---|---|
| Number | The number. A list gives its length, a boolean gives 1 or 0, and text is read as a number when it can be. | 1 while active, else 0. |
| Boolean | Its truthiness. `false`, `no`, `off`, `0`, an empty text and an empty list are false. | True while active. |
| Trigger | It fires when the value changes to something true. A bell can ring when `{count}` goes up. | It fires when the pointer becomes active. |

A token that is absent leaves its input alone. An input name the state machine does not have is ignored without an error.
Names are case-sensitive.

The two keywords are:

- `hover` is true while the pointer is over the animation.
- `pressed` is true while the mouse button is held down on it.

Herald does not pass pointer movement to the file, so a Rive "pointer enter", "exit" or "move" listener does not fire. Use a boolean input bound to `hover` instead. Mouse down, drag and up are passed on, but only when the animation takes clicks, which it does when it has an `action` or `actionRef` or a `pressed` binding.

## Clicking

With an `action` or `actionRef`, a click on the animation runs that action. A click is a press and release inside the
animation. The pointer becomes a pointing hand over it and VoiceOver treats it as a button. Without either, clicks fall
through to the banner, which still tracks hover. The action runs with the same gates as for a
[button](button.md#which-action-runs).

## Sizing and alignment

- `height` fixes the height. The width then follows from `aspectRatio`, or from the artboard's proportions.
- Without `height`, the box takes the width of its cell and a height from the aspect ratio: yours, else the artboard's,
  else 4 to 1.
- Each side is limited to 1 through 2000 points. A placeholder for a failed load is 44 points high.
- The box fills the cell width. Alignment only positions it when the cell is larger than the box, for example in a
  fixed-height row.

## Light and dark

Herald draws exactly what is in the file, on a transparent background over the translucent banner. Design with a
transparent artboard and colours that work on both appearances. Herald does not switch Rive themes on its own. To react to
the appearance, add a boolean input and bind it to a field.

## Empty animations

The component is empty only when neither `asset` nor `path` is set, which the validator rejects anyway. Tokens in
`inputBindings` do not make it empty: an animation with absent fields still plays.

## Static previews

The preview endpoint, the MCP tool `render_preview` and History thumbnails draw a dashed placeholder with the asset name
at the right size, not the animation. To check the animation without a window, use the Rive check described in
[Testing without a window](../rive.md#testing-without-a-window), or look at a live banner.

## Accepted older forms

| Older form | Current form |
|---|---|
| `"action": "markRead"` (a string) | `"actionRef": "markRead"` |

## Common mistakes

| Mistake | What happens | Fix |
|---|---|---|
| A state machine name with the wrong case. | The placeholder reads `no state machine "main" (available: Main)`. | Copy the names from `POST /v1/rive/check`. |
| An input name with the wrong case. | The input is ignored without an error. | Copy the names from `POST /v1/rive/check`. |
| Binding a text value to a number input. | Text that is not a number is ignored. | Bind a numeric field, or a list, which gives its length. |
| Expecting a Rive hover listener to fire. | Pointer movement is not passed to the file. | Use a boolean input and `"hover":"hover"`. |
| Checking the animation with `render_preview`. | It shows a placeholder. | Use `POST /v1/rive/check`, or look at a live banner. |

## Related

- [Rive in Herald](../rive.md): preparing the file, getting it into Herald and troubleshooting.
- [Manifests](../manifests.md): declaring a Rive asset and its inputs.
- [Diagnostics API](../api/diagnostics.md#post-v1rivecheck): `POST /v1/rive/check`.
- [Actions](../actions.md): what a click on the animation can run.
