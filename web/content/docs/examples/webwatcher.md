# WebWatcher with Herald

WebWatcher is a real app that sends its alerts to Herald, so this page shows what a complete integration looks like in
production. It covers what WebWatcher is, what it registers and sends, the manifest and template that go with it, how its
banner buttons call back, and how to try it on your own Mac. [BidBot](bidbot/README.md) is the runnable teaching example;
WebWatcher is the same pattern in a shipping Swift app.

## What WebWatcher is

WebWatcher is a macOS menu bar app that watches web pages and Gmail for changes. It reads the pages from Safari tabs you
already have open, and it watches Gmail senders through the Gmail API. When something changes, it raises a notification.
By default WebWatcher raises it through Herald, and it falls back to a macOS notification when Herald is not running. Herald
shows banners that stay until you deal with them, groups them into stacks, and lets you change how each one looks.

The code is at [github.com/ivg-design/web-watcher](https://github.com/ivg-design/web-watcher).

## What it sends to Herald

WebWatcher sends as two apps, one for pages and one for mail. Each has its own manifest and default template, so each can be
restyled separately.

| App id | Shown as | Used for | Default template |
|---|---|---|---|
| `webwatcher.web` | WebWatcher · Web | Page watchers, and the notice that a watcher stopped working. | `web-default` |
| `webwatcher.email` | WebWatcher · Email | Gmail sender and domain watchers. | `email-default` |

Both manifests set the family `webwatcher`, so the stacking level that groups by product puts all WebWatcher banners in one
stack. See [Stacking](../reference/stacking.md).

### How it registers

Before the first notification, and again after Herald restarts, WebWatcher does three things, in this order:

1. It registers the app with [`POST /v1/register`](../reference/api/apps.md#post-v1register): the display name, the
   WebWatcher icon, its bundle id, and a callback address on a loopback port. It sets `allowCommands` to `false`, because
   its buttons never run commands.
2. It saves the default template with [`PUT /v1/templates`](../reference/api/templates.md#put-v1templates), but only when
   Herald has no template of that name for the app. A template you changed in Herald is never overwritten.
3. It saves the manifest with [`PUT /v1/manifest`](../reference/api/manifests.md#put-v1manifest).

If registering fails, WebWatcher shows the notification through macOS instead. If the template or manifest fails, the
notification is still sent: they change only how the banner looks.

### What a notification carries

Every notification is [`POST /v1/notify`](../reference/api/notifications.md#post-v1notify) with these properties:

| Property | Value |
|---|---|
| `app` | `webwatcher.web` or `webwatcher.email`. |
| `id` | A stable id, so an update replaces the banner in place. The patterns are listed below the table. |
| `title`, `subtitle`, `body` | The text WebWatcher built for the event. |
| `url` | The page, or the Gmail thread. |
| `image` | The watcher's custom icon, when it has one. |
| `sound` | `default`, or `none` when the watcher's sound is off. |
| `persistent` | Always `true`: the banner stays until you act on it. |
| `group` | The stack key. A page watcher uses the site, and mail uses the sender. |
| `buttons` | The buttons described in [Buttons and callbacks](#buttons-and-callbacks). |
| `metadata` | What WebWatcher knows about the event, such as the watcher id and the account. |

The `id` follows one pattern for each kind of notification.

| Notification | `id` |
|---|---|
| A page watcher's change. | `watcher-<watcher id>` |
| A page watcher's health notice. | `health-<watcher id>` |
| A Gmail message. | `gmail-<message id>` |
| An email watcher's running count. | `emailwatcher-<watcher id>` |

The `group` of a page watcher is the site, such as `example.com`. For mail it is the sender's address in lower case.

The manifest's fields also travel at the top level of the payload, which is how a template binds them. A field that is empty
is left out, never sent blank. This is a page watcher notification, shortened:

```json
{
  "app": "webwatcher.web",
  "id": "watcher-3F2504E0-4F89-41D3-9A0C-0305E82C3301",
  "title": "Inbox",
  "subtitle": "Orders",
  "body": "You have 3 new messages",
  "url": "https://example.com/inbox",
  "sound": "default",
  "persistent": true,
  "group": "example.com",
  "buttons": [{"label": "Open", "style": "default", "url": "https://example.com/inbox"}],
  "value": "3",
  "previous": "1",
  "watcherName": "Inbox",
  "site": "example.com",
  "count": 3
}
```

And an email watcher's running notification. It uses the same id on every update, so one banner shows the current count:

```json
{
  "app": "webwatcher.email",
  "id": "emailwatcher-8A1C5E7B-2D44-4B0B-9F63-6E2C1D7A9B10",
  "title": "2 new from Acme Billing",
  "subtitle": "Invoice #4021",
  "body": "Your invoice for September is attached. Payment is due in 14 days.",
  "url": "https://mail.google.com/mail/u/0/#inbox",
  "sound": "default",
  "persistent": true,
  "group": "billing@acme.example",
  "sender": "Acme Billing",
  "address": "billing@acme.example",
  "subject": "Invoice #4021",
  "count": 2,
  "buttons": [
    {"label": "Mark as Read", "style": "default", "callback": {"payload": {"action": "GMAIL_MARK_READ"}}},
    {"label": "Archive", "style": "destructive", "callback": {"payload": {"action": "GMAIL_ARCHIVE"}}}
  ]
}
```

The two example payloads show the shape. The real payloads also carry identifiers in the button payloads and in `metadata`:
the watcher, the Gmail account, and the message ids. The second example shows two of the four buttons, and not those
identifiers.

## The manifest

Each app's manifest declares the fields it sends, with sample values, and the actions it offers. The samples let the Designer
and previews draw a realistic banner before anything has been sent. This is the manifest of `webwatcher.email`:

```json
{
  "app": "webwatcher.email",
  "appName": "WebWatcher · Email",
  "version": 1,
  "family": "webwatcher",
  "defaultTemplate": "email-default",
  "fields": [
    {"key": "title", "type": "text", "required": true, "sample": "2 new from Acme Billing"},
    {"key": "subject", "type": "text", "sample": "Invoice #4021"},
    {"key": "sender", "type": "text", "sample": "Acme Billing"},
    {"key": "address", "type": "text", "sample": "billing@acme.example"},
    {"key": "count", "type": "number", "sample": 2},
    {"key": "receivedAt", "type": "date", "sample": "2026-10-01T14:14:00Z"},
    {"key": "image", "type": "image"},
    {"key": "url", "type": "url", "sample": "https://mail.google.com/mail/u/0/#inbox"},
    {"key": "snippet", "type": "text", "sample": "Your invoice for September is attached. Payment is due in 14 days."}
  ],
  "actions": [
    {"id": "markRead", "label": "Mark as Read", "kind": "callback", "style": "default"},
    {"id": "archive", "label": "Archive", "kind": "callback", "style": "destructive"},
    {"id": "delete", "label": "Delete", "kind": "callback", "style": "destructive"},
    {"id": "spam", "label": "Spam", "kind": "callback", "style": "destructive"}
  ]
}
```

The manifest of `webwatcher.web` declares one action, `open`, and these fields. The fields are described in the
[manifest reference](../reference/manifests.md).

| Field | What it holds |
|---|---|
| `title`, `subtitle`, `body` | The text of the event. |
| `value`, `previous` | The new and the old value the watcher read. |
| `url` | The page that changed. |
| `image` | The watcher's icon. Its sample is the WebWatcher icon. |
| `watcherName`, `site` | The name of the watcher and the site it watches. |
| `count` | A count, sent only when it means something. |

`count` is a numeric badge or element count for a page, or more than one unread message for mail. A count badge in the
template collapses when there is nothing to count.

The buttons themselves are built for each notification, because each carries what its click acts on. The manifest's actions
declare the ids, and Herald matches a notification's buttons to them by label.

## The default template

Both templates share one skeleton, a grid of 4 rows and 4 columns that looks like Herald's built-in image-left layout, so a
banner reads the same in either app:

```text
          col 0 (72 pt)   col 1 (fill)       col 2 (auto)   col 3 (auto)
  row 0   image           title              app icon       close button
  row 1   image           subtitle (cols 1-2)                 count badge
  row 2   image           body (cols 1-2)                     time
  row 3                   actions (cols 1-3), wrapping
```

The image spans the first three rows. The actions start in the second column, because a cell that spanned the image column
would keep it alive, and a banner without a picture, such as every per-message email, would keep a blank strip. Empty
components collapse: no image column without an image, no badge without a count, no action row without buttons.

| Cell | `webwatcher.web` | `webwatcher.email` |
|---|---|---|
| Title | `{title}`, up to 2 lines. | `{title}`, up to 2 lines. |
| Subtitle | `{subtitle}`, up to 2 lines. | `{subject}`, up to 2 lines. |
| Body | `{body}`, up to 4 lines, with Markdown. | `{body}`, up to 5 lines. |
| Time | The time the notification was delivered. | `{receivedAt}`. |
| Count badge | `{count}`. | `{count}`. |

Read the stored template back to see every property, then change it in the Designer:

```sh
herald template list --app webwatcher.email
```

The [`herald template list`](../reference/cli.md#herald-template-list) command prints the saved templates of the app. Because
WebWatcher saves a template only when none of that name exists, what you save in the Designer stays.

## Buttons and callbacks

A page watcher banner has one button. A Gmail banner has four. The buttons carry a payload that WebWatcher attached, and
Herald posts it back to WebWatcher when the button is pressed. See [Callbacks](../reference/actions.md#callbacks) and the
[callback request](../reference/api/replies.md#callback-request).

| Button | App | What it does |
|---|---|---|
| Open | `webwatcher.web` | Opens the watcher's action address, or the watched page. A watcher with an API lookup command is answered through a callback instead: WebWatcher runs the command and opens the address it prints. |
| Mark as Read | `webwatcher.email` | Removes the unread label from the message or messages. |
| Archive | `webwatcher.email` | Removes the message from the Inbox. |
| Delete | `webwatcher.email` | Moves the message to Trash. |
| Spam | `webwatcher.email` | Marks the message as spam and removes it from the Inbox. |

The callback request reaches a small server that WebWatcher runs on a loopback port, the address it registered. WebWatcher
treats it with care:

- **Only its own buttons count.** WebWatcher remembers the payload it attached to each notification, and acts only on an event
  whose payload is exactly one of them. Anything else is answered `403`, so nothing else on the Mac can make WebWatcher
  archive or delete mail. After WebWatcher restarts, it reads the payloads back from the banners Herald still holds.
- **The answer follows the outcome.** Herald closes the banner when the callback is answered with a `2xx`, so WebWatcher
  answers only after the action has run. The statuses it uses are in the table.

| Answer | When |
|---|---|
| `200` | The action worked. Herald closes the banner. |
| `409` | The action failed. The banner stays and shows the failure, and Herald does not retry. |
| `504` | The action was still running after 4 seconds. Herald retries once, and the Gmail calls are safe to repeat. |
| `404` | The watcher to open has been deleted. |
| `403` | The payload is not one WebWatcher sent. |

## Try it

### Before you start

- Herald is installed and running. See [Install Herald](../install.md).
- WebWatcher is installed. See [its repository](https://github.com/ivg-design/web-watcher).

### Steps

1. In WebWatcher, click the icon in the menu bar and choose **Settings...**. Scroll to the **Notifications** group.
2. Set **Deliver notifications via** to **Herald when available**. This is the default.

   Under the picker, a line reads `Herald: running (port 47321)` with a green dot. The port number is your Herald's. When
   Herald is not running, the line reads `Herald not running — using macOS notifications`.

3. Add a watcher in WebWatcher, or connect a Gmail account and add a Gmail sender watcher, and wait for a change.

   A banner from **WebWatcher · Web** or **WebWatcher · Email** appears and stays on screen. Banners from the same site, or the
   same sender, fold into one stack.

4. Press a button. On a Gmail banner, press **Archive**.

   The banner closes after WebWatcher has archived the message.

### Check that it works

Ask Herald what it knows about WebWatcher:

```sh
herald apps
herald stacks --app webwatcher.email
herald history --app webwatcher.web --limit 5
```

`herald apps` lists `webwatcher.web` and `webwatcher.email` once WebWatcher has registered them. `herald stacks` shows the stacks on screen,
and `herald history` the latest notifications. To see the layout without waiting for a change, draw the template with sample
values:

```sh
curl -s -X POST "$HERALD/v1/preview" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"app":"webwatcher.email","template":"email-default","data":"sample","appearance":"dark"}' -o email.png
```

`$HERALD` and `$TOKEN` come from [Connect](../reference/api/README.md#connect). The preview runs against the manifest's sample
values, so it works before the first real email. [Testing](../TESTING.md) shows how to do all of this against a second instance of
Herald.

### Change how it looks

Open **Design Template** from the Herald menu, choose **WebWatcher · Email** and its `email-default` template, and edit the
grid. WebWatcher keeps sending the same fields, and the new design applies from the next notification. See
[Designing a banner](../AUTHORING.md).

### If it does not work

| Symptom | Cause | Fix |
|---|---|---|
| WebWatcher says `Herald not running — using macOS notifications`. | Herald is not open, or it is not installed. | Open Herald. WebWatcher uses it from the next notification. |
| Banners still appear in Notification Center. | **Deliver notifications via** is set to **macOS notifications**. | Set it to **Herald when available**. |
| A Gmail banner stays after you press a button. | The action failed, and the banner shows the failure. | Read the failure on the banner. If it names the account, use **Reconnect** in WebWatcher's **Settings > Gmail**. |
| A banner looks different from `email-default`. | You edited the template in Herald. | That is expected: WebWatcher never overwrites a template that is already saved. Delete the template, then quit and reopen WebWatcher, which saves it again. |

## Related

- [BidBot walkthrough](bidbot/README.md): the same pattern in a small script you can run.
- [Manifests](../reference/manifests.md): every field of a manifest.
- [Stacking](../reference/stacking.md): how `group` and `family` fold banners together.
- [Actions](../ACTIONS.md): buttons, callbacks and what Herald asks you to confirm.
- [Designing a banner](../AUTHORING.md): change `web-default` or `email-default` in the Designer.
