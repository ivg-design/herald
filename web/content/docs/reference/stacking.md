# Stacking

When a busy app sends many notifications, Herald folds related ones into one **stacked banner** instead of
covering the screen with a column of cards. The newest notification is on top, a count shows how many are in the
stack, and the edges of the cards behind it peek out below. This page explains what makes notifications stack
together, how a stack looks and behaves, and how a template shows the count. It is for senders choosing a `group`,
template authors, and users choosing a stacking level.

## Concepts

A **stack** is a set of live banners that share a **stacking key**. A banner that arrives for a key that already
has a stack joins it and becomes its top card. A stack needs at least two members: a lone banner is just a
banner and shows no count.

The key comes from the **stacking level**. There is a global default, and an app can override it. Four levels
exist, and each groups by something different.

## Stacking levels

| Level | One stack per | Key |
|---|---|---|
| `byApp` | Product family. | The manifest's `family`, else the app id up to its first dot, else the whole id. |
| `byIssuer` | App (issuer) id. | The app id. |
| `bySender` | Notification `group`. | The notification's `group`, or the app id when it sends none. |
| `never` | Nothing. | Banners never fold together. |

`bySender` is the global default. In the menu the levels are named **By App**, **By Issuer**, **By Sender** and
**Never**.

Examples, with three apps: `webwatcher.web`, `webwatcher.email` and `example.bidbot`.

- **`byApp`**: `webwatcher.web` and `webwatcher.email` share the family `webwatcher`, so all their banners are
  one stack. BidBot has its own stack. Set `"family": "webwatcher"` in each app's [manifest](manifests.md) to
  group apps whose ids do not share a prefix.
- **`byIssuer`**: `webwatcher.web` has one stack and `webwatcher.email` has another. Every BidBot banner is in
  one stack.
- **`bySender`**: each `group` is its own stack. Email notifications from `billing@acme.com` stack together
  and are separate from those of `news@acme.com`. A notification with no `group` stacks under its app id.
- **`never`**: every notification is a separate banner.

Keys of different levels never collide. When the level changes while banners are on screen, Herald regroups them
at once and keeps their arrival order.

### Where the level is set

- **Global default**: the menu's **Stack Notifications** submenu, or
  [`PUT /v1/settings/stacking`](api/stacks.md#put-v1settingsstacking). Banners on screen regroup immediately.
- **Per app**: **Settings > Apps**, the **Stack notifications** menu. Its first choice, **Default (By Sender)** or whichever level is the global default, follows the
  global default and any other choice overrides it for that app. The override wins over the default. An agent
  sets the same thing with the app setting `stacking` through
  [`PUT /v1/apps/settings`](api/apps.md#put-v1appssettings), where `null` clears it.

A typical mix is Gmail stacking by sender while web watchers stack by app.

## The `group` field

`group` is a top-level field of a notification. It names what the notification is about: an email sender, a
watched site, a bid id. Under `bySender`, notifications of one app with the same `group` stack together. See
[`POST /v1/notify`](api/notifications.md#post-v1notify) for the field itself.

**Minimal example**

```json
{"app": "webwatcher.email", "title": "New invoice", "group": "billing@acme.com"}
```

**Realistic example**

```json
{
  "app": "webwatcher.email",
  "id": "msg-501",
  "group": "billing@acme.com",
  "title": "New invoice",
  "subtitle": "Acme Billing",
  "body": "Invoice 2041 is due on the 14th."
}
```

From a shell, `herald notify --group "billing@acme.com"` sets the same field. See
[`herald notify`](cli.md#herald-notify).

## A closed stack

A closed stack is the top card, with a count badge on its top edge at the right and two card edges peeking out
below it.

![A stacked Herald banner showing the newest notification on top, a count badge reading 3 and the edges of two cards behind it](../../web/public/shots/docs/banner-stack-closed.png "A closed stack: the newest notification on top, a count badge, and the edges of the cards behind it.")

Rules for a closed stack:

- A new member becomes the top card, and the stack sits on screen where its top card would, so a new member
  brings it to the top of the screen.
- Sending the same `id` again replaces that notification in place and never raises the count. In a stack with
  other members, the updated notification moves to the top so the card shows what it now says.
- The stack's sound and speech follow the newest notification.
- The close button, the snooze menu and a click on the body act on the whole group, not on one notification.
- A stack with fewer than two members is not a stack: it stays closed and shows no count.

## An open stack

Pressing the count badge, or the card's body when the template has no click URL, opens the stack in place. The
panel grows into a list of the group's banners, each drawn with its own template, newest first.

![An open stack: the group's banners listed one under another, with Collapse and Dismiss all at the bottom](../../web/public/shots/docs/banner-stack-open.png "An open stack: each notification as its own row, with Collapse and Dismiss all below.")

- The list shows six rows before it scrolls. Its height is also limited by the screen, so the buttons never fall
  off the edge.
- **Collapse** closes the list.
- **Dismiss all** closes every banner of the stack.
- Each row works on its own: its buttons run for that notification, and a click on its body opens its link. A
  row without a link stays where it is.
- Closing one row removes only that notification from the stack.
- Opening or closing a stack never activates Herald and never takes focus from the app you are using.

An agent opens or closes a stack with [`POST /v1/stacks/expand`](api/stacks.md#post-v1stacksexpand). A stack
with fewer than two members stays closed.

## Dismissing and snoozing a stack

- Closing the card of a closed stack dismisses the whole group. The members go to History as dismissed.
- Snoozing the card snoozes the group. When it returns, it comes back as a stack in the order it had.
- [`POST /v1/dismissAll`](api/notifications.md#post-v1dismissall) with `app` and `group` dismisses one stack.
- History records each member individually with its `group`, and the History window folds notifications of one app
  that share an explicit `group` under a disclosure.

## Showing the count in a template

A template shows the stack size in two ways.

- `{stack.count}` is a token that works in any binding. It has a value only while the stack has two or more
  notifications, and is empty otherwise, so a component that shows it collapses on a lone banner. For example,
  `"+{stack.count} more"`. See [Bindings](bindings.md).
- The [`stackBadge`](components/stackBadge.md) component is a pill that shows the count and opens the stack
  when pressed.

A template with no `stackBadge` gets the default badge on the top edge of the stacked card. A template that has
one draws the count where you placed it.

```json
{"id": "stack", "row": 0, "col": 3, "align": "topTrailing",
 "component": {"type": "stackBadge", "color": "#FF3B30"}}
```

## Endpoints, tools and commands

| For | Use |
|---|---|
| Listing live stacks. | [`GET /v1/stacks`](api/stacks.md#get-v1stacks), [`list_stacks`](mcp/notifications.md#list_stacks), `herald stacks`. |
| Opening or closing one. | [`POST /v1/stacks/expand`](api/stacks.md#post-v1stacksexpand), [`expand_stack`](mcp/notifications.md#expand_stack). |
| Reading the global level. | [`GET /v1/settings/stacking`](api/stacks.md#get-v1settingsstacking). |
| Setting the global level. | [`PUT /v1/settings/stacking`](api/stacks.md#put-v1settingsstacking). |
| Dismissing a stack. | [`POST /v1/dismissAll`](api/notifications.md#post-v1dismissall), [`herald dismiss-all`](cli.md#herald-dismiss-all). |

## Common mistakes

| Mistake | What happens | Fix |
|---|---|---|
| Sending no `group` and expecting one stack per sender. | Under `bySender` it falls back to the app id: one stack per app. | Send a `group`. |
| Spelling `family` differently across a product's apps. | `byApp` makes separate stacks. | Use one `family` string everywhere. |
| Sending every update under a new `id`. | Each one is a new member and the count climbs. | Reuse the `id` for updates of the same thing. |
| Expecting the badge in a preview of a lone banner. | The count is empty below 2. | Preview with a `stackCount` of 2 or more. |
| Expecting a stack of one. | A single banner is shown as a plain banner. | Nothing to fix. |

## Related

- [How banners behave](banners.md): click, expand, close and timeout.
- [`stackBadge`](components/stackBadge.md): the counter component.
- [Stacks API](api/stacks.md): list, open and close stacks, and the global level.
- [Manifests](manifests.md): the `family` field that `byApp` stacking reads.
