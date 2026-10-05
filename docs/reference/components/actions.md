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
| `include` | array of action ids | all remaining | Ordered list of the actions this cell shows: issuer actions and template-added ones (`["archive","delete","spam"]`). Empty or absent: every action of `source` that no other cell has claimed. Ids no action has show nothing (validation warns when a manifest is given). |
| `align` | string | `leading` | Where the buttons sit across the cell's width: `leading`, `center`, `trailing`, or `spaceBetween` (first at the leading edge, last at the trailing edge, the rest spread evenly). Applies to each line when the row wraps. |
| `wrap` | boolean | follows `layout` | `true` flows onto further lines when the buttons do not fit; `false` keeps one line (what does not fit goes behind "+N"). Absent: `layout: wrap` flows, `row` does not. `stack` is always one per line. |
| `spacing` | number 0-64 | 6 | Points between buttons, and between lines when wrapping. |

## Bindings and tokens

Button labels may contain `{tokens}`; they are filled from the notification's fields (a label that fills to
nothing shows the action id). Labels over 40 characters are cut, with the full text in the tooltip.

## One action, one cell

An action is drawn in at most one cell of a template, so one list can be split across cells. Cells are visited
top to bottom, left to right:

1. A `button` bound to an action id (`actionRef`, or `actionId`) claims that action.
2. An `actions` cell with `include` claims those ids, in that order.
3. An `actions` cell with no `include` shows every action of its `source` that nobody claimed.

When two cells ask for the same action the first one in reading order draws it and the other shows nothing for
it (a `button` collapses like an absent action). Validation reports a warning naming both cells.

Example, the WebWatcher email layout split by hand: the app icon in column 1 rows 1-3, a `button` for Mark as
Read in column 1 row 4, and Archive, Delete and Spam right-aligned in one merged cell spanning columns 2-4 of
row 4:

```json
{"name":"email-split","app":"webwatcher.email","layoutVersion":2,"collapseEmpty":true,
 "grid":{"rows":4,"cols":4,"rowSizes":["auto","auto","auto","auto"],"colSizes":["104","fill","fill","fill"],"gap":8,"padding":14,"width":400},
 "cells":[
  {"id":"icon","row":0,"col":0,"rowSpan":3,"component":{"type":"issuerIcon","size":56,"shape":"rounded"}},
  {"id":"title","row":0,"col":1,"colSpan":3,"component":{"type":"text","binding":"{title}","style":"title","maxLines":1}},
  {"id":"sender","row":1,"col":1,"colSpan":3,"component":{"type":"text","binding":"{sender}","style":"subtitle","maxLines":1}},
  {"id":"subject","row":2,"col":1,"colSpan":3,"component":{"type":"text","binding":"{subject}","style":"caption","maxLines":1}},
  {"id":"read","row":3,"col":0,"component":{"type":"button","actionId":"markRead"}},
  {"id":"more","row":3,"col":1,"colSpan":3,"component":{"type":"actions","include":["archive","delete","spam"],"align":"trailing","wrap":false}}]}
```

The test `ActionArrangementTests` validates this template and asserts the frames; `ActionArrangementLiveTests`
renders it through `/v1/preview` and reads the button frames back from the PNG.

## What the row contains

Each button draws its own action's `symbol`; `placement: "only"` makes it an icon-only button ([actions.md](../actions.md#the-look-of-one-action-1-8)).

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

Applies vertically. Horizontally `align` places the buttons across the cell; the snooze clock is always on the
trailing edge. A non-`leading` `align` makes the row fill its cell's width.

## Empty behaviour

Empty when `source` yields no actions. A notification with a `reminder` keeps the row alive (the reminder
button lives there) unless `source` is `template`. While an inline confirmation is pending the row is
replaced by the question (see [README.md](README.md#empty-behaviour)).

## Light and dark

Button tints follow the action's `style`: `normal` (also written `default`) uses the accent, `prominent` is a filled
accent capsule, `destructive` is system red with an outline and asks for confirmation (see
[button.md](button.md#style)), `cancel` secondary grey.

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
| Several `actions` rows in one template | An action is drawn once: the first row (reading order) takes what is left, the others are empty. | Give each row its own `include`. |
| The same id in two cells | The first cell draws it, the other shows nothing; validation warns. | Name it in one cell. |
