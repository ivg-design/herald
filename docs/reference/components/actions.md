# actions

The action row: every action of the resolved list (or the issuer's, or the template's) as capsule buttons,
with overflow, the snooze clock and Add to Reminders.

## Properties

| Property | Type | Default | Allowed values / notes |
|---|---|---|---|
| `type` | string | required | `"actions"` |
| `source` | string | `merged` | `issuer` (only the issuer's actions after your rules), `template` (only actions added by `actionRules[].add`), `merged` (both, in resolved order). |
| `layout` | string | `wrap` | `row` (one line; whatever does not fit goes behind "+N"), `wrap` (flows onto more lines), `stack` (one button per line). |
| `maxVisible` | integer >= 1 | all | Show at most this many buttons; the rest sit behind a "+N" menu. Never below 1. |
| `emptyBehavior` | string | template default | `collapse` or `keep`. |
| `symbol` | name or object | none | **Available from 1.3.** A symbol every button of the row gets unless its action has its own `symbol`. See [../symbols.md](../symbols.md). |

## Bindings and tokens

Button labels may contain `{tokens}`; they are filled from the notification's fields (a label that fills to
nothing shows the action id). Labels over 40 characters are cut, with the full text in the tooltip.

## What the row contains

1. The resolved actions of `source`, in order, as capsule buttons (24 pt high).
2. A `snooze` action with no `snoozeMinutes` (what `"snooze": true` in a notification adds, or a rule's
   `{"add":{"kind":"snooze"}}`) is not a button: it is the clock menu, pinned to the trailing edge, with
   5 minutes, 15 minutes, 1 hour and Tomorrow 9:00.
3. When the notification has a `reminder` (and `source` is not `template`): the Add to Reminders button, with
   its working / added / failed states.
4. When some actions do not fit (`row` layout) or exceed `maxVisible`: a "+N" menu with the rest. `maxVisible`
   applies in every layout.

The first variant that fits the width wins in `row` layout: all buttons, else one fewer plus "+1", and so on.

## Sizing

Fills its cell's width. Height is one button (24 pt); `wrap` and `stack` grow by one button per line. A kept
empty row holds one button's height.

## 9-point alignment

Applies vertically. Horizontally the row always starts at the leading edge and the snooze clock is on the
trailing edge.

## Empty behaviour

Empty when `source` yields no actions. A notification with a `reminder` keeps the row alive (the reminder
button lives there) unless `source` is `template`. While an inline confirmation is pending the row is
replaced by the question (see [README.md](README.md#empty-behaviour)).

## Light and dark

Button tints: `default` uses the accent, `destructive` system red with an outline, `cancel` secondary grey.

## Actions wiring

Each button runs its action with the origin it came from (issuer or template); gates and confirmations are
described in [../actions.md](../actions.md#confirmation-gates). The sample data of a preview stands in for an
issuer that names every action its manifest declares; a real notification shows only the actions it sends.

## Examples

Everything, wrapping:

```json
{"type":"actions","source":"merged","layout":"wrap"}
```

At most three buttons on one line, rest in the menu, only the user's own actions:

```json
{"type":"actions","source":"template","layout":"row","maxVisible":3}
```

A full-width row with rules that hide Archive, relabel Mark as Read and add a Shortcut:

```json
{"name":"actions-demo","app":"webwatcher.email","layoutVersion":2,"collapseEmpty":true,
 "grid":{"rows":2,"cols":1,"rowSizes":["auto","auto"],"colSizes":["fill"],"gap":8,"padding":12,"width":380},
 "cells":[
  {"id":"title","row":0,"col":0,"component":{"type":"text","binding":"{title}","style":"title"}},
  {"id":"acts","row":1,"col":0,"component":{"type":"actions","source":"merged","layout":"wrap","maxVisible":4}}],
 "actionRules":[
  {"match":"markRead","relabel":"Mark as read","position":0},
  {"match":"archive","hide":true},
  {"add":{"id":"followup","label":"Follow up","kind":"shortcut","shortcut":"Create follow-up","input":"{title}\n{url}"}}]}
```

## Common mistakes

| Mistake | What happens | Fix |
|---|---|---|
| Expecting the manifest's actions to show | A real notification shows only what it sends (`actions`/`buttons`, or `actionIds`). | Send `"actionIds":["markRead"]`. |
| `source: "template"` with no `add` rules | Empty row, collapses. | Add rules or use `merged`. |
| `maxVisible: 0` | Treated as 1 (never only a menu), and validation reports an error (`at least 1`). | Use 1 or more. |
| Several `actions` rows in one template | Each shows the whole list. | Use `button` cells with `actionRef` to split. |
