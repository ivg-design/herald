# Stacking

When several notifications share a key, Herald folds them into **one stacked banner**: the newest notification
on top, a count badge and the edges of the cards behind it. Clicking the badge toggles the stack open or closed, like clicking the title; open, it is a
scrollable list. It keeps a busy issuer (an inbox, a set of watched sites) from covering the screen.

This page is the reference. The short version is in [../API.md](../API.md#stacking-12) and the design notes in
`DESIGN.md` section 9.

## The key: stacking levels

The key follows the **stacking level**: a global default plus a per-issuer override.

| Level | One stack per | Key |
|---|---|---|
| `byApp` | product family | the manifest's `family`, else the issuer id up to its first dot (`webwatcher.email` and `webwatcher.web` share `webwatcher`), else the whole id |
| `byIssuer` | issuer (manifest) id | the app id |
| `bySender` | payload `group` | the notification's `group`; the issuer id when it sends none. **The global default.** |
| `never` | nothing | banners never fold together |

Keys of different levels never collide, so a stack keeps its identity while the level changes under it
(members are re-keyed and arrival order is kept).

Where the level is set:

- **Global default**: the bell menu's quick switch, or `PUT /v1/settings/stacking`
  (`{"level":"bySender"}`). Live banners regroup at once.
- **Per issuer**: Settings > Apps, an override that wins over the default. Example: Gmail stacks by sender while web
  watchers stack by issuer. There is no API for the per-issuer override.

## What the issuer sends

`group` is a top-level notification key: an email sender, a watched site, a bid id.

```sh
herald notify --app webwatcher.email --group "billing@acme.com" --title "New invoice"
```

```json
{"app":"webwatcher.email","id":"msg-501","group":"billing@acme.com","title":"New invoice","count":1}
```

The family comes from the manifest: set `"family":"webwatcher"` on every issuer of a product to make `byApp`
stacking fold them together ([manifests.md](manifests.md)).

## Behaviour

- A banner arriving for a key with a live stack becomes its **top card**; the stack shows its notification, a
  count and two offset card edges behind it. The stack sits where its top card would, so a new member brings it
  to the top of the screen.
- **Same `id` again replaces in place** and never raises the count. In a stack with other members the updated
  notification moves to the top so the card shows what it says; alone it keeps its place.
- The stack's sound and speech follow the newest notification.
- A member dismissed from the expanded list leaves the stack. The card's close button dismisses the whole group
  (the members go to History as dismissed). Snoozing the card snoozes the group and brings it back as a stack,
  in the order it had.
- A stack with fewer than two members is not a stack: it stays closed and shows no counter.
- History records each member individually with its `group`; the History window folds notifications of one app
  that share an explicit `group` under a disclosure.

### Expanded stack

Clicking the count badge (or the card body when the template has no click URL) opens the stack in place: one panel
that grows into a list of the group's banners, each drawn with its own template, newest first, **six rows
before it scrolls** (the height is also bounded by the screen), with **Collapse** and **Dismiss all** at the
bottom. Clicking a member's body opens its URL (a member without one stays where it is); its actions work individually. Expanding never activates Herald
or takes focus.

## Templates: the counter

Two ways to show the count:

- `{stack.count}` in any binding, present only while the stack has two or more notifications (empty, so the
  component collapses, for a lone banner);
- the [`stackBadge`](components/stackBadge.md) component, a pill that opens the stack when clicked.

A template without a `stackBadge` gets the counter at the **top right** of the stacked card automatically.

```json
{"id":"stack","row":0,"col":3,"align":"topTrailing","component":{"type":"stackBadge","color":"#FF3B30"}}
```

## API

| Call | Purpose |
|---|---|
| `GET /v1/stacks?app=` | `{"stacks":[...]}`: the live stacks. Each has `level`, `app` (the issuer or family), `group`, `count`, `expanded`, `members` (newest first, each `{app, id, title, group, deliveredAt}`) and `frame` (the panel in screen points, when it has one). `app` filters to stacks holding a notification of that app. |
| `POST /v1/stacks/expand` | `{"app","group","expanded":true}` opens or closes a stack, as its badge and Collapse do. `group` defaults to the app id. A stack with fewer than two members stays closed. |
| `GET /v1/settings/stacking` | `{"level","levels":["byApp","byIssuer","bySender","never"]}` |
| `PUT /v1/settings/stacking` | `{"level":"bySender"}`; replies like the GET. 400 for an unknown level. |
| `POST /v1/dismissAll` | With `{"app","group"}`: dismiss every banner of that app sent with that group (one stack). `app` is required with `group`. |
| `POST /v1/preview` | `"stackCount": 1 to 99` draws the banner as the top card of a stack; `"stackExpanded": true` draws the open list. |
| MCP `list_stacks`, `dismiss {app, group}` | The same from an agent. |
| CLI `herald stacks [--app ID]`, `herald dismiss-all --app ID --group G` | The same from a shell. |

## Common mistakes

| Mistake | What happens | Fix |
|---|---|---|
| Not sending `group` and expecting one stack per sender | Under `bySender` it falls back to the issuer id: one stack per issuer. | Send `group`. |
| Different `family` spellings across issuers | `byApp` makes separate stacks. | Use one `family` string. |
| Counting on the badge in a lone-banner preview | Empty below 2. | Preview with `stackCount`. |
| Sending every update under a new `id` | Each is a new member and the count climbs. | Reuse the `id` for updates of the same thing. |
