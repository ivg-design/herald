# Icon button component

The `iconButton` component draws a small round button that holds only an SF Symbol: a close button in the corner of a
banner, a snooze clock, a mark-done tick. The Designer calls it **Icon btn**. Use it for the small controls that sit
beside the text rather than in the row of action buttons. It runs one action, written inline or named by an id.

An icon button always draws the symbol from its own `symbol` property, in a round, faintly tinted circle. To show an
action as a labelled capsule that can switch between text, icon and text, or icon only, use
[`button`](button.md) or the [`actions`](actions.md) row instead.

**Minimal example**

```json
{"type":"iconButton","symbol":"xmark","action":{"id":"dismiss","label":"Dismiss","kind":"dismiss"}}
```

This is the usual close button.

**Realistic example**

A close button in the top right corner of a banner, next to the title.

```json
{"name":"icon-button-demo","app":"example.bidbot","layoutVersion":2,"collapseEmpty":false,
 "grid":{"rows":2,"cols":2,"rowSizes":["auto","auto"],"colSizes":["fill","auto"],"gap":4,"padding":12,"width":380},
 "cells":[
  {"id":"title","row":0,"col":0,"component":{"type":"text","binding":"{title}","style":"title"}},
  {"id":"close","row":0,"col":1,"align":"topTrailing",
   "component":{"type":"iconButton","symbol":"xmark","tooltip":"Close",
                "action":{"id":"dismiss","label":"Dismiss","kind":"dismiss"}}},
  {"id":"sub","row":1,"col":0,"colSpan":2,"component":{"type":"text","binding":"{subtitle}","style":"subtitle"}}]}
```

In the picture below, look at the round button in the top right corner of the banner. It is an icon button that runs a dismiss action.

![A banner with a round close button in its top right corner](../../../web/public/shots/docs/banner-plain.png "The round button in the corner of the banner is an icon button that runs a dismiss action.")

**Properties**

| Property | Type | Default | Description |
|---|---|---|---|
| `type` | string | required | Always `"iconButton"`. |
| `symbol` | name or object | required | The SF Symbol to draw, for example `"xmark"`, `"alarm"` or `"checkmark"`. It can also be an object with a `name` and styling. See [SF Symbols](../symbols.md). |
| `action` | object | none | An inline action, written out in full. See [Actions](../actions.md#action-object). |
| `actionRef` | string | none | The id of an action in the resolved list. |
| `size` | number | `18` | The diameter of the circle in points. A value below 8 is drawn as 8. |
| `color` | string | `secondary` | The colour of the symbol: a hex colour, or `accent`, `primary` or `secondary`. A colour in the symbol's own `colors` takes precedence. |
| `tooltip` | string | the action's label | The text shown when the pointer rests on the button. |
| `emptyBehavior` | string | template default | `collapse` or `keep`. See [Empty icon buttons](#empty-icon-buttons). |

The button needs a non-blank `symbol`, and an `action` or an `actionRef`. Without them the validator reports an error.

## The symbol

`symbol` is either the name of an SF Symbol or an object that adds styling:

```json
{"type":"iconButton","size":22,"actionRef":"markRead",
 "symbol":{"name":"checkmark.circle.fill","weight":"semibold","renderingMode":"palette",
           "colors":["#FFFFFF","#34C759"],"effect":{"kind":"bounce","trigger":"onHover"}}}
```

The object's keys are described in [SF Symbols](../symbols.md). Three points are specific to an icon button:

- `placement` has no effect, because an icon button has no label to place the symbol beside.
- A symbol name that is not an SF Symbol on this Mac draws a question mark in a circle, so a typo still shows something.
- In the Designer, the **Symbol** section of the inspector holds the name, a browser for symbols, and the styling.

![The Designer's symbol browser listing SF Symbols](../../../web/public/shots/docs/designer-symbol-browser.png "The symbol browser opens beside the Symbol field and lists SF Symbols by name and category.")

## The label of the action

The action's `label` is not drawn. It is the button's tooltip and the name that VoiceOver reads. Setting `tooltip` replaces
it for both. Give the action a short label such as "Close" or "Snooze". In the Designer's action form the label is optional
when **Shows** is **Icon only**, and Herald fills in a plain name for what the action does. An action written in JSON
needs a label or an id, which stands in for it.

The per-action **Shows** setting of the Designer's **Actions** tab, with **Text**, **Icon and text** and **Icon only**,
controls capsule buttons. It does not change an icon button, which always draws its own `symbol`.

## What pressing it does

- A `dismiss` action closes the banner. This is the usual close button.
- A `snooze` action without `snoozeMinutes` opens Herald's snooze menu with **5 minutes**, **15 minutes**, **1 hour** and
  **Tomorrow 9:00**. With `snoozeMinutes` it snoozes for exactly that long.
- Any other kind runs as it does for a [button](button.md#which-action-runs), with the same gates and confirmations.

A snooze menu is drawn as a plain symbol in a static preview.

An icon button is never taken away by a pending inline question, so the banner can always be dismissed.

## Sizing and alignment

The button is a circle of `size` points with a faint translucent fill.

- The symbol is drawn bold at 9 points, or 10 points when `size` is above 18.
- The circle does not wrap or stretch.
- It is usually placed with `align` set to `topTrailing` for a close button in the corner.
- The fill is a faint tint of the primary colour and the symbol uses `color`, so both follow the light or dark appearance.

## Empty icon buttons

An icon button is empty when its `actionRef` names an action that is not in the resolved list. An inline action is never
empty. A kept empty icon button is invisible and holds its size.

## Accepted older forms

| Older form | Current form |
|---|---|
| `"action": "dismiss"` (a string) | `"actionRef": "dismiss"` |

## Common mistakes

| Mistake | What happens | Fix |
|---|---|---|
| A misspelt symbol name. | A question mark in a circle is drawn. | Look the name up in the SF Symbols app. |
| Leaving out the action. | The validator reports an error. | Add `action` or `actionRef`. |
| A `snooze` action with `snoozeMinutes`, expecting the menu. | It snoozes at once for that time. | Omit `snoozeMinutes` to get the menu. |
| Using an icon button when you want a labelled button that can also show an icon. | The label is never drawn. | Use a `button`, and set the action's symbol. |

## Related

- [Actions](../actions.md): action kinds, the snooze action and confirmation gates.
- [Button component](button.md): a labelled capsule button with an optional icon.
- [Actions component](actions.md): the row of buttons, and the per-action **Shows** setting.
- [SF Symbols](../symbols.md): names, weights, colours and effects.
