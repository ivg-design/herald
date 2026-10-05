# button

One action as a capsule button.

## Properties

| Property | Type | Default | Allowed values / notes |
|---|---|---|---|
| `type` | string | required | `"button"` |
| `action` | action object **or** string | none | An inline action (see [../actions.md](../actions.md)), or a bare string naming a resolved action's id (same as `actionRef`). |
| `actionRef` | string | none | Id of an action in the resolved list: an issuer action (`"markRead"`) or one added by `actionRules`. |
| `actionId` | string | none | Another spelling of `actionRef` (the id of the issuer action this button runs); it is read as `actionRef`. A button bound by id claims that action: no other cell draws it (see [actions.md](actions.md#one-action-one-cell)). |
| `style` | string | the action's style, else `normal` | `normal`, `prominent`, `destructive`, `cancel` (the quiet grey); `default` is read as `normal`. Overrides the action's own style. See [Style](#style). The old `"destructive": true` is read as `"style": "destructive"`. |
| `emptyBehavior` | string | template default | `collapse` or `keep`. |
| `symbol` | name or object | none | **Available from 1.3.** A symbol drawn with the label; an action's own `symbol` wins. With `placement: "only"` (**1.8**) the button is the icon alone. See [../symbols.md](../symbols.md). |

A button needs an inline `action` or an `actionRef`; otherwise validation reports an error. An inline action
needs `label` and `id` (the id defaults to a slug of the label) and a `kind`, which can be inferred from the
fields present.

## Style

| Style | Look | Behaviour |
|---|---|---|
| `normal` | accent-tinted capsule | runs when pressed |
| `prominent` | solid accent capsule, white label | runs when pressed; use it for the one action the banner is for |
| `destructive` | red label on a red-tinted, outlined capsule | **asks first**: pressing it shows an inline row "Run "Delete"?" with the button's label and Cancel; nothing runs until the user answers. The question is drawn inside the banner and never takes focus. It is asked every time, and before any approval the action's own kind needs (command, script, Shortcut). |
| `cancel` | quiet grey capsule | runs when pressed |

The same rule holds for any action whose effective style is `destructive`, whether the button, the issuer's
manifest, or an `actionRules` entry set it. In the Designer the control is labelled *Style*, with the caption
"Destructive draws the label in red and asks for confirmation before running".

## Bindings and tokens

The button's label may contain `{tokens}` (`"Open {sender}"`); they are filled from the notification's fields.
If that leaves nothing, the action's id is shown. Labels longer than 40 characters are cut with an ellipsis
and the tooltip shows the full text. An inline action's `url` and `input` are filled from fields too.

## Sizing

Height 24 points; width is the label plus 10 pt padding each side. The label never wraps. In an `auto` column
the column is as wide as the button.

## 9-point alignment

Positions the capsule inside its cell (for example `trailing` to push a single button to the right edge).

## Empty behaviour

Empty when `actionRef` names an action that is not in the resolved list (hidden by a rule, or the issuer did
not send it). An inline action is never empty. A kept empty button is an invisible placeholder of the same
size.

## Light and dark

`default` is tinted with the template's accent (nudged legible) or the system accent; `destructive` is system
red with an outline; `cancel` is secondary grey. The capsule fill brightens on hover and press.

## Actions wiring

- Inline `action`: the action is the template's own (origin `template`). A `command`, `script` or `shortcut`
  needs one confirmation per template the first time it runs. See [../actions.md](../actions.md#confirmation-gates).
- `actionRef`: the action keeps its origin. An issuer `command` needs the app's command permission; an issuer
  `callback` POSTs to the app's callback URL.
- A `snooze` action without `snoozeMinutes` is the built-in menu; use `iconButton` or the `actions` row for it.

## Examples

Show one issuer action:

```json
{"type":"button","actionRef":"markRead"}
```

An inline URL button with a token in the label:

```json
{"type":"button","action":{"id":"open","label":"Open {sender}'s message","kind":"url","url":"{url}"}}
```

A Shortcut button in a complete template, with the issuer's actions hidden from the generic row:

```json
{"name":"button-demo","app":"demo","layoutVersion":2,"collapseEmpty":true,
 "grid":{"rows":2,"cols":2,"rowSizes":["auto","auto"],"colSizes":["fill","fill"],"gap":6,"padding":12,"width":380},
 "cells":[
  {"id":"title","row":0,"col":0,"colSpan":2,"component":{"type":"text","binding":"{title}","style":"title"}},
  {"id":"read","row":1,"col":0,"component":{"type":"button","actionRef":"markRead","emptyBehavior":"collapse"}},
  {"id":"follow","row":1,"col":1,"component":{"type":"button",
    "action":{"id":"followup","label":"Follow up","kind":"shortcut","shortcut":"Create follow-up","input":"{title}\n{url}"}}}]}
```

## Common mistakes

| Mistake | What happens | Fix |
|---|---|---|
| `actionRef` for an action the notification did not send | The button is empty and collapses. A real notification must send `actions`/`buttons` or `actionIds`; only a *sample* preview assumes every manifest action. | Send the action, or use an inline action. |
| Hiding an action with a rule and still referencing it | Empty button. | Remove the rule or the reference. |
| Using `"kind":"command"` with a stray shell quote | Validation passes; the command fails at run time (see `~/Library/Logs/Herald/actions.log`). | Test in a terminal first; prefer `script`. |
