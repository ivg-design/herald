# Authoring notifications in Herald

You can write notifications by hand (JSON), or design them visually in the Composer and Template editor.
All three paths use the same banner renderer, so what the preview shows is what you get on screen.

## Templates

A template is a reusable banner design for one app, stored as
`~/Library/Application Support/Herald/templates/<app>/<name>.json`.

| Field | Meaning |
|---|---|
| `name`, `app` | Identity. The id is `app/name`. |
| `layout` | `imageLeft` (default), `imageRight`, `hero` (image across the top at 16:9, then text), `compact` (one line, icon and title, no image). |
| `accentColor` | Hex colour such as `#2E7D32`. |
| `showSubtitle`, `showBody`, `showTimestamp` | Show or hide each part. |
| `maxBodyLines` | Line limit for the body. |
| `title`, `subtitle`, `body`, `image`, `url` | Default content; may contain `{placeholders}`. |
| `buttons` | Default button set. |
| `sound`, `persistent`, `timeout`, `snooze`, `priority`, `reminder` | Default behaviour. |

Partial files are fine: missing fields take their defaults.

```json
{"name":"bid-won","app":"example.bidbot","layout":"hero","accentColor":"#2E7D32",
 "title":"Bid accepted: {amount}","subtitle":"{client}",
 "body":"{client} accepted your bid. [Open](https://example.com/p/{id})",
 "buttons":[{"label":"Open","url":"https://example.com/p/{id}"}],
 "sound":"Glass","snooze":true,"maxBodyLines":3}
```

Use it by name:

```sh
herald notify --app example.bidbot --json - <<< '{"template":"bid-won","metadata":{"amount":"$4,200","client":"Acme"},"id":"42"}'
```

### Resolution rules

1. Herald loads the template named by `template` for the notification's `app`.
2. Anything present in the notification overrides the template's value (title, buttons, layout, sound, ...).
3. `{placeholder}` tokens in the template's `title`, `subtitle`, `body` and `url` are filled from the
   notification's `metadata` string values first, then from its own fields: `title`, `subtitle`, `body`,
   `app`, `id`.
4. Unknown placeholders become empty text.

The banner is drawn from the resolved result. A missing template is not an error; the notification is
shown as sent.

Manage templates with the Composer, the Template editor, or the API (`GET`, `PUT`, `DELETE /v1/templates`).

## Herald 1.1: manifests, the Designer, actions, MCP

Herald 1.1 adds a four-step path from "an app can send data" to "a banner that looks and acts the way
you want".

1. **Manifest.** The issuing app declares the fields it sends (with sample values), the actions it
   supports and any assets: `PUT /v1/manifest` (see [API.md](API.md#manifests)). Fields you did not
   declare still arrive in `metadata` and show up in the palette as "custom".
2. **Grid template.** Menu bar > Design Template opens the Designer. The palette on the left lists
   components, the issuer's fields (drag a field onto a cell to bind it) and actions. The centre canvas is
   the 3 x 4 grid at real banner size: select cells to Merge or Split, drag components between cells,
   resize spans, pick one of nine alignments. The inspector on the right edits bindings, style, size and
   **empty behaviour**. The preview bar switches between Sample data and the last real notification, light
   and dark; **Send test** delivers it for real; **Set as issuer default** makes it the template used
   when a notification names none. Reference: [TEMPLATES.md](TEMPLATES.md).
3. **Empty fields: collapse or keep.** For each template (and each component) you choose whether an
   empty field disappears and frees its space, or stays and keeps the banner shape. See
   [Collapse semantics](TEMPLATES.md#collapse-semantics).
4. **Two-way actions.** Keep the issuer's buttons, hide or relabel them, and add your own: a shell command,
   a script, an Apple Shortcut, a URL. Details in [ACTIONS.md](ACTIONS.md). Each action row on the Actions tab has **Shows** (Text, Icon
   and text, Icon only) and its own icon ([the look of each button](ACTIONS.md#the-look-of-each-button)).

### Authoring with an agent (MCP)

`herald-mcp` is an MCP server (stdio) that lets Claude Code, Codex or any MCP client design templates
for you. A typical session: the agent calls `list_manifests` and `get_manifest` to learn the fields,
`component_schema` for what it may place, drafts a template with `put_template` (errors name the
offending cell id), checks it with `render_preview` (it receives the PNG), adds a rule with
`add_action_rule` or an action found with `list_shortcuts`, and finishes with `send_test`. Setup and the
tool list are in [MCP.md](MCP.md).

## Composer

Open it from the menu bar (Compose...) or run `herald compose`, which only opens the window.

- Left: the form. App picker, template picker, title, subtitle, body (Markdown links), image
  (file or URL), click URL, buttons editor (label, action type url / callback / command, style), sound
  picker with a play button, persistent and timeout, snooze on or off, reminder title and due date,
  priority, and metadata key/value rows.
- Right: a live preview of the real banner view, in light and dark appearance side by side.
- Toolbar:
  - **Send now** delivers the notification.
  - **Save as template...** stores the form as a template for the chosen app.
  - **Copy as...** puts ready-to-run code for the exact payload on the clipboard: curl, Swift
    (`HeraldClient`), Python, Node, or the `herald` CLI.

## Template editor

Open a template from Settings > Apps > Templates... > Edit. It is the Composer pointed at a template, plus a
sample-data drawer where you type values for the placeholders and watch the preview update. Save,
Duplicate and Delete are in the toolbar.

## Copy-as examples: a "Bid accepted" notification

curl:

```sh
D="$HOME/Library/Application Support/Herald"
curl -s -X POST "http://127.0.0.1:$(cat "$D/port")/v1/notify" \
  -H "Authorization: Bearer $(cat "$D/token")" -H 'Content-Type: application/json' \
  -d '{"app":"example.bidbot","id":"bid-42","title":"Bid accepted","subtitle":"Acme RFP",
       "body":"Your bid of $4,200 was accepted. [Open proposal](https://example.com/p/42)",
       "url":"https://example.com/p/42","sound":"Glass","snooze":true,
       "buttons":[{"label":"Open","url":"https://example.com/p/42"}]}'
```

Swift:

```swift
import HeraldClient

let id = try await HeraldClient.shared.notify(HeraldNotification(
    app: "example.bidbot", id: "bid-42", title: "Bid accepted", subtitle: "Acme RFP",
    body: "Your bid of $4,200 was accepted. [Open proposal](https://example.com/p/42)",
    url: "https://example.com/p/42", sound: "Glass",
    buttons: [HeraldButton(label: "Open", url: "https://example.com/p/42")], snooze: true))
```

Python:

```python
from herald import Herald
Herald().notify(app="example.bidbot", id="bid-42", title="Bid accepted", subtitle="Acme RFP",
                body="Your bid of $4,200 was accepted. [Open proposal](https://example.com/p/42)",
                url="https://example.com/p/42", sound="Glass", snooze=True,
                buttons=[{"label": "Open", "url": "https://example.com/p/42"}])
```

Node:

```js
const { Herald } = require('./herald');
await new Herald().notify('example.bidbot', 'Bid accepted', {
  id: 'bid-42', subtitle: 'Acme RFP',
  body: 'Your bid of $4,200 was accepted. [Open proposal](https://example.com/p/42)',
  url: 'https://example.com/p/42', sound: 'Glass', snooze: true,
  buttons: [{ label: 'Open', url: 'https://example.com/p/42' }],
});
```

CLI:

```sh
herald notify --app example.bidbot --id bid-42 --title "Bid accepted" --subtitle "Acme RFP" \
  --body "Your bid of \$4,200 was accepted. [Open proposal](https://example.com/p/42)" \
  --url https://example.com/p/42 --sound Glass --snooze --button "Open=https://example.com/p/42"
```
