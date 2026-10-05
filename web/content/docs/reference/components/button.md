# Button component

The `button` component draws one action as a capsule button. The Designer calls it **Button**. Use it when you want one
specific action in a specific place, such as a **Mark as Read** button in the corner of a banner, while the rest of the
actions sit in an [`actions`](actions.md) row elsewhere. The button either points at an action by id (`actionRef`) or
carries an action of its own (`action`). The button can show its label, an icon with its label, or an icon alone.

**Minimal example**

```json
{"type":"button","actionRef":"markRead"}
```

This shows the issuer's `markRead` action as a button. If the notification does not offer that action, the button is
empty.

**Realistic example**

Two buttons under a title. The first shows an action the app sends. The second is the template's own button that runs an
Apple Shortcut with the title and link as its input and shows an icon next to its label.

```json
{"name":"button-demo","app":"example.bidbot","layoutVersion":2,"collapseEmpty":true,
 "grid":{"rows":2,"cols":2,"rowSizes":["auto","auto"],"colSizes":["fill","fill"],"gap":6,"padding":12,"width":380},
 "cells":[
  {"id":"title","row":0,"col":0,"colSpan":2,"component":{"type":"text","binding":"{title}","style":"title"}},
  {"id":"read","row":1,"col":0,"component":{"type":"button","actionRef":"markRead","emptyBehavior":"collapse"}},
  {"id":"follow","row":1,"col":1,"component":{"type":"button",
    "action":{"id":"followup","label":"Follow up","kind":"shortcut","shortcut":"Create follow-up",
              "input":"{title}\n{url}","symbol":"flag"}}}]}
```

![A banner with action buttons under its text](../../../web/public/shots/docs/banner-actions.png "Each capsule under the text is an action. A button component draws one of them in a cell of its own.")

**Properties**

| Property | Type | Default | Description |
|---|---|---|---|
| `type` | string | required | Always `"button"`. |
| `action` | object | none | An inline action, written out in full. See [Actions](../actions.md#action-object). |
| `actionRef` | string | none | The id of an action in the resolved list: an issuer action such as `"markRead"`, or one that `actionRules` add. |
| `style` | string | the action's style, else `normal` | The button's look: `normal`, `prominent`, `destructive` or `cancel`. It overrides the action's own style. See [Style](#style). |
| `symbol` | name or object | none | An SF Symbol drawn with the label. The action's own `symbol` wins over it. See [Icon, text or both](#icon-text-or-both). |
| `emptyBehavior` | string | template default | `collapse` or `keep`. See [Empty buttons](#empty-buttons). |

A button needs an inline `action` or an `actionRef`. Without one the validator reports an error. An inline action has three required parts:

- A `label`.
- An `id`, which defaults to a slug of the label.
- A `kind`, which can be inferred from the fields present. For example, a `url` field means `kind` is `url`.

## Style

The style sets how prominent the button is and whether it asks before it runs.

| Style | Look | When pressed |
|---|---|---|
| `normal` | A capsule tinted with the accent colour. | The action runs. |
| `prominent` | A solid accent capsule with a white label. Use it for the one action the banner exists for. | The action runs. |
| `destructive` | A red label on a red-tinted, outlined capsule. | Herald asks first. |
| `cancel` | A quiet grey capsule. | The action runs. |

In the Designer the control is **Button style** and its choices are **Normal**, **Prominent**, **Destructive** and
**Quiet**. `default` is read as `normal`.

A destructive button does not run at once. It replaces the buttons with an inline question, `Run "Delete"?`, with the button's label and a **Cancel** button. Nothing runs until the user answers.

- The question is drawn inside the banner and never takes focus.
- It is asked every time, and before any approval that the action's own kind needs, such as a command, script or Shortcut.
- The same rule applies to any action whose effective style is `destructive`, whether the button, the issuer's manifest or an `actionRules` entry set it.

## Icon, text or both

A button can show its text label, an icon with the label, or an icon alone. This is decided per action, by the action's
`symbol`:

| The button shows | The action's `symbol` |
|---|---|
| Text only | None. |
| Icon and text | A symbol with the default `placement` (`leading`), or `trailing` to put the icon after the label. |
| Icon only | A symbol with `"placement": "only"`. The label is not drawn. |

For example, an icon-only link button:

```json
{"type":"button","action":{"id":"open","label":"Open","kind":"url","url":"{url}",
  "symbol":{"name":"arrow.up.right","placement":"only"}}}
```

The button's own `symbol` is used when the action has none, and a `symbol` on the action always wins. For an action that comes from the issuer, give it a symbol with an `actionRules` entry instead of editing the action:

```json
{"match": "markRead", "symbol": "checkmark"}
```

[Rules](../actions.md#action-rules) describes the entry.

An icon-only button still has a capsule around its icon. Its label is not drawn but it is the button's tooltip and its name for VoiceOver, so give it a short one.

- In the Designer's action form the label is optional for **Icon only**. Herald fills in a plain name for what the action does, such as "Open link" or "Dismiss".
- An action written in JSON needs a label or an id, which stands in for it.
- A symbol name that is not an SF Symbol on this Mac is ignored and the button shows its label alone.

In the Designer each action has its own look. Open the **Actions** tab of the inspector. Every row of the **Buttons**
list has a **Shows** menu with **Text**, **Icon and text** and **Icon only**, and an **Icon** button that opens the
symbol picker. The same **Shows** control sits in the form that adds or edits an action.

![The Actions tab of the Designer inspector with a Shows menu on each action](../../../web/public/shots/docs/designer-inspector-actions.png "Each action in the Buttons list has its own Shows menu and icon.")

![The form for adding an action, with the Shows control and the symbol section](../../../web/public/shots/docs/designer-action-form.png "The action form's Shows control chooses text, icon and text, or icon only. The symbol is picked below it.")

## Labels and sizing

The label may contain `{tokens}`, for example `"Open {sender}'s message"`.

- Tokens are filled from the notification's fields. If that leaves nothing, the action's id is shown.
- A label longer than 40 characters is cut with an ellipsis, and the tooltip shows the full text.
- An inline action's `url` and `input` are filled from fields too.

A button is 24 points high. Its width is the label plus 10 points of padding on each side, and the label never wraps. In
an `auto` column the column is as wide as the button. The cell's `align` positions the capsule inside its cell, for
example `trailing` to push a single button to the right edge. The capsule fill brightens on hover and while it is
pressed.

## Which action runs

- **Inline `action`.** The action belongs to the template, so a `command`, `script` or `shortcut` asks for one
  confirmation per template the first time it runs. See [Confirmation gates](../actions.md#approvals).
- **`actionRef`.** The action keeps its origin. An issuer `command` needs the app's command permission, and an issuer
  `callback` posts to the app's callback URL.
- **Snooze.** A `snooze` action without `snoozeMinutes` is Herald's snooze menu. Show it with an
  [`iconButton`](iconButton.md) or in the `actions` row. A `button` can run a snooze that has fixed minutes.

A button bound by id claims that action: no other cell draws it. See
[One action, one cell](actions.md#one-action-one-cell).

## Empty buttons

A button is empty when its `actionRef` names an action that is not in the resolved list, because a rule hid it, the app
did not send it, or an earlier cell already claimed it. An inline action is never empty. A kept empty button is an
invisible placeholder of the same size.

## Accepted older forms

| Older form | Current form |
|---|---|
| `"actionId": "markRead"` | `"actionRef": "markRead"` |
| `"action": "markRead"` (a string) | `"actionRef": "markRead"` |
| `"destructive": true` | `"style": "destructive"` |

## Common mistakes

| Mistake | What happens | Fix |
|---|---|---|
| An `actionRef` for an action the notification did not send. | The button is empty and collapses. A real notification shows only the actions it sends. Only a sample preview assumes every action the manifest declares. | Send the action with `actionIds` or `buttons`, or use an inline action. |
| Hiding an action with a rule and still referencing it. | The button is empty. | Remove the rule or the reference. |
| Putting `placement: "only"` on an action with a label that the user has to read. | The label is hidden, leaving only a tooltip. | Use **Icon and text** for anything that is not a familiar symbol. |
| A `command` with a stray shell quote. | The validator passes it and the command fails when it runs. The failure is logged in `~/Library/Logs/Herald/actions.log`. | Test the command in a terminal first, and prefer a `script`. |

## Related

- [Actions](../actions.md): action kinds, rules, confirmation gates and the resolved list.
- [Actions component](actions.md): the whole row of buttons and the one-action-one-cell rule.
- [Icon button component](iconButton.md): a round button with a symbol.
- [SF Symbols](../symbols.md): symbol names, weights and effects.
- [Designing a banner](../../AUTHORING.md): arranging buttons in the Designer.
