# Two-way notifications

A notification does not have to end at the banner. It can carry buttons that open a link, call your server back, take a
typed answer or run a command, a script or a Shortcut on the Mac. This guide shows how to add each kind and what the user sees when they press
it. When you finish you will have a banner with working buttons and a program that hears what the user chose. The full
list of fields, kinds and rules is in the [actions reference](reference/actions.md).

## Before you start

- Herald is running, and you can send a notification. If not, follow [Send your first notification](getting-started.md).
- The examples use `$HERALD` and `$TOKEN`. Define them once as shown in
  [Connect](reference/api/README.md#connect).
- The examples send as the fictional app `example.bidbot`. Use your own app id.

## How buttons work

A button is part of the notification. You send it in `buttons`, and each button does one thing. Herald draws it on the
banner, waits for the user to press it, then does what the button says and closes the banner.

![A banner titled Build failed with four buttons under its text: Open log, an icon-only button, Dismiss and Post to Slack](../web/public/shots/docs/banner-actions.png "A banner with buttons. Each button is one entry of the buttons list, or one the template adds, like the last one here.")

The buttons you send are the **issuer's** buttons. You can also declare them once in the app's
[manifest](reference/manifests.md#actions), and the user can hide, rename or add to them in the Designer without
changing your code. [Where actions come from](reference/actions.md#where-actions-come-from) explains the merge.

## Add a button that opens a link

A link button is the simplest: it opens a page in the default browser. It needs no registration and no approval.

1. Send a notification with a `url` button.

   ```sh
   curl -s -X POST "$HERALD/v1/notify" \
     -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
     -d '{
       "app": "example.bidbot",
       "id": "bid-42",
       "title": "Bid accepted",
       "body": "Your bid of $4,200 was accepted.",
       "buttons": [{"label": "Open bid", "url": "https://example.com/bids/42"}]
     }'
   ```

   The banner appears with an **Open bid** button.

2. Press **Open bid**.

   The page opens in your browser and the banner closes. Only `http`, `https` and `mailto` links open.

## Add a button that calls your server

A callback button tells your program which button the user pressed. Herald sends one HTTP request to a URL you give it.
Use it for anything your program has to decide, such as accepting an offer.

1. Start a server that listens on your Mac. This one prints each press and answers `200`.

   ```python
   from http.server import BaseHTTPRequestHandler, HTTPServer
   import json

   class Hook(BaseHTTPRequestHandler):
       def do_POST(self):
           size = int(self.headers["Content-Length"])
           event = json.loads(self.rfile.read(size))
           print(event["notificationId"], event["action"], event.get("payload"))
           self.send_response(200)   # any 2xx closes the banner
           self.end_headers()

   HTTPServer(("127.0.0.1", 5123), Hook).serve_forever()
   ```

2. Tell Herald where the server is, by registering the app with a `callbackURL`.

   ```sh
   curl -s -X POST "$HERALD/v1/register" \
     -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
     -d '{"app": "example.bidbot", "appName": "BidBot", "callbackURL": "http://127.0.0.1:5123/herald"}'
   ```

   The reply is `{"ok": true}`. You can instead put a `url` inside each button's `callback`. See
   [`POST /v1/register`](reference/api/apps.md#post-v1register).

3. Send a notification with callback buttons.

   ```sh
   curl -s -X POST "$HERALD/v1/notify" \
     -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
     -d '{
       "app": "example.bidbot",
       "id": "bid-43",
       "title": "Counter-offer from Acme",
       "body": "They offer $3,900. Accept?",
       "persistent": true,
       "buttons": [
         {"label": "Accept", "callback": {"payload": {"decision": "accept"}}},
         {"label": "Decline", "style": "destructive", "callback": {"payload": {"decision": "decline"}}}
       ]
     }'
   ```

   The banner stays on screen until you press a button.

4. Press **Accept**.

   Your server prints `bid-43 Accept {'decision': 'accept'}` and the banner closes. **Decline** is styled
   `destructive`, so Herald asks **Run "Decline"?** first and only then sends the request.

The server received this body. The `action` field is the label of the button, and `payload` is the data you attached.

```json
{
  "notificationId": "bid-43",
  "app": "example.bidbot",
  "action": "Accept",
  "payload": {"decision": "accept"}
}
```

Answer with a `2xx` status once the work is done. Any other status keeps the banner on screen and shows **Action
failed**, so the user can try again. Herald waits 5 seconds and retries once after a temporary failure.
[Callbacks](reference/actions.md#callbacks) has the timing, the retry rules and the answers Herald accepts.

> [!NOTE]
> A callback to a host that is not this Mac asks the user first. The banner shows **Send BidBot's button action to
> HOST?** with **Send once** and **Always allow HOST**. Addresses on this Mac never ask.

## Add a reply field

A reply button turns the banner into a small form. The user types an answer and sends it, without opening any window.
Use it when you need a sentence, not a choice.

1. Send a persistent notification with a `reply` button. The field needs the banner to stay on screen, so use
   `persistent`.

   ```sh
   curl -s -X POST "$HERALD/v1/notify" \
     -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
     -d '{
       "app": "example.bidbot",
       "id": "bid-44",
       "title": "Counter-offer from Acme",
       "body": "What should we answer?",
       "persistent": true,
       "buttons": [{"label": "Reply", "reply": {"placeholder": "Message to Acme"}}]
     }'
   ```

2. Press **Reply** on the banner.

   The buttons give way to a text field with the placeholder **Message to Acme**, a **Send** button and a close button.

   ![A banner titled Migration finished with a text field, a Send button and a close button in place of its buttons](../web/public/shots/docs/banner-reply.png "The reply field replaces the buttons inside the banner. This banner's field says Reply to Claude (build-bot)...; yours shows Message to Acme. The close button brings the buttons back.")

3. Type an answer and press **Send**.

   The banner closes. Herald stores the answer on the notification in History and in the app's reply queue.

4. Read the answer. If your program can wait, ask Herald to hold the request until the reply exists.

   ```sh
   curl -s "$HERALD/v1/replies/wait?app=example.bidbot&id=bid-44&timeout=60" \
     -H "Authorization: Bearer $TOKEN"
   ```

   ```json
   {
     "replied": true,
     "reply": {
       "notificationId": "bid-44",
       "app": "example.bidbot",
       "text": "Counter at $4,000",
       "repliedAt": "2026-10-02T14:21:07.000Z",
       "title": "Counter-offer from Acme"
     }
   }
   ```

   If no one replies within the timeout, the answer is `{"replied": false, "timedOut": true}`. The parameters are in
   [`GET /v1/replies/wait`](reference/api/replies.md#get-v1replieswait).

   To read the queue without waiting, use [`GET /v1/replies`](reference/api/replies.md#get-v1replies).

There are other ways to receive a reply:

- An agent reads the same answer with the MCP tools [`wait_for_reply`](reference/mcp/notifications.md#wait_for_reply) and
  [`get_replies`](reference/mcp/notifications.md#get_replies).
- A program that runs a server can give the reply button a `callback`. The typed text arrives as `payload.reply` in the
  request.
- Notifications that come through the cloud relay can carry a voice reply, where the banner records and transcribes the
  answer on the Mac.

![A banner titled Migration finished with a recording strip: a red dot, 0:07 of 60 s, a Stop button and a cancel cross](../web/public/shots/docs/banner-record.png "A voice reply shows the elapsed time out of the longest recording. Stop ends the recording and Send then uploads it.")

See [Cloud](CLOUD.md) for the relay.

## Add a command button

A command button runs a shell command on the Mac as the user. Because that is powerful, Herald only runs a command
from an app the user has trusted.

1. Register the app and say it wants to run commands.

   ```sh
   curl -s -X POST "$HERALD/v1/register" \
     -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
     -d '{"app": "example.bidbot", "appName": "BidBot", "allowCommands": true}'
   ```

   Asking is not enough. The user still has to agree, in the next steps.

2. Send a notification with a `command` button.

   ```sh
   curl -s -X POST "$HERALD/v1/notify" \
     -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
     -d '{
       "app": "example.bidbot",
       "id": "bid-45",
       "title": "Report ready",
       "persistent": true,
       "buttons": [{"label": "Open report", "command": "open ~/Reports/bids.pdf"}]
     }'
   ```

3. Press **Open report**.

   The buttons give way to a question in the banner: **Run this command for BidBot?** The command is shown in a box,
   with **Run once**, **Always allow BidBot** and **Cancel**.

   ![A banner titled Preview looks good asking Run Deploy, with a warning icon, a line saying the button is marked destructive, a red Deploy button and a Cancel button](../web/public/shots/docs/banner-confirm.png "The same kind of question, here for a destructive Deploy button: the question, a line about why Herald asks, and the answers. A command question shows Run once, Always allow and Cancel in this place.")

4. Press **Run once**.

   The command runs and the banner closes. **Always allow BidBot** turns on **Allow this app to run commands, scripts and Shortcuts**
   under **Settings > Apps**, so later presses run at once. Turn the switch off to ask again.

If the app never registered with `allowCommands`, the press fails with **commands are not allowed for BidBot** and
nothing runs. The command text is never edited. The notification's data arrives on standard input as JSON and in
`HERALD_*` environment variables, so a sender's text can never become part of a command line. See
[What a process receives](reference/actions.md#what-a-process-receives).

A `script` button, which names a file in Herald's scripts folder, and a `shortcut` button, which names an installed
Apple Shortcut, work the same way and ask under the same switch. Their question names the script with its SHA-256, or
the Shortcut with its input text:

```json
{"label": "Forward", "shortcut": "Forward to phone", "input": "{title}"}
```

> [!WARNING]
> A command runs with your user permissions. Allow commands only for apps you trust, and use a template script rather
> than a command when the action handles text from strangers.

## Change the buttons without changing the sender

You can change an app's buttons yourself, in the Designer, without asking the app to change. Open the template, choose
the **Actions** tab, and you see the app's buttons followed by the ones you added. For each of the app's buttons you can:

- Hide it, rename it, or change its style.
- Move it, or give it an icon.

You can also add your own button: a link, a shell command, a script or an Apple Shortcut.

![The Actions tab of the Designer, with the issuer's buttons and the buttons you added](../web/public/shots/docs/designer-inspector-actions.png "Each row has its own Shows control, so one button can show an icon while its neighbour shows text.")

Code you add this way, such as a command, a script or a Shortcut, is confirmed once for the template the first time it
runs. Herald asks again if the code changes. **Settings > Actions** lists the confirmations, with a **Revoke** button
for each.

![The Actions tab of Settings with the scripts folder and one template row marked Not confirmed yet](../web/public/shots/docs/settings-actions.png "A template row shows its status at the right: Confirmed, Changed since confirmed or Not confirmed yet. This one is Not confirmed yet.")

[Designing a banner](AUTHORING.md) walks through the Designer. The rules and fields are in
[Action rules](reference/actions.md#action-rules).

## Run an action when nobody answers

A follow-up runs one action when a banner is left unattended: nobody dismisses it, presses a button, replies or opens
it for the time you set. Use it to forward a missed banner with a Shortcut. You can send one with a notification:

```sh
curl -s -X POST "$HERALD/v1/notify" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{
    "app": "example.bidbot",
    "id": "bid-46",
    "title": "Bid accepted",
    "persistent": true,
    "followUp": {"after": "10m", "action": {"id": "fwd", "label": "Forward", "kind": "shortcut",
                                           "shortcut": "Forward to phone", "input": "{title}"}}
  }'
```

The action asks for the same approval a button of that kind asks for. After it runs, the banner stays and shows
**Follow-up ran: Forward**. The timer, the approval and the record are in
[Follow-ups](reference/actions.md#follow-ups). The whole task, from the Shortcut to the Designer, is in
[Forward a notification you missed](FORWARD-MISSED.md).

## Check that it works

Send the link notification from the first section and press its button. If the page opens and the banner closes, the
button path works. For a callback, watch your server print the press. To see the buttons without a real send, use the
Designer's preview, which shows every action the manifest declares.

## If it does not work

| Symptom | Cause | Fix |
|---|---|---|
| The banner shows **Action failed** with `no callback URL`. | The button has no `callback.url` and the app has no `callbackURL`. | Register the app with a `callbackURL`. |
| The banner shows **Action failed** with `connection refused`. | Nothing listens at the callback address. | Start your server, or correct the address. |
| The banner shows **Action failed** with `HTTP 500`. | Your server answered with an error. | Fix the server. Herald retried once already. |
| The banner shows **commands are not allowed for BidBot**. | The app was not registered with `allowCommands`. | Register with `allowCommands: true`, then press the button again. |
| `send_notification` refuses a command, script or Shortcut button. | The MCP tool blocks code that runs on the Mac unless asked. | Pass `allowCommandButtons: true`, or send the button through the API. |
| A link button shows `this link type is not allowed`. | The link uses a scheme other than `http`, `https` or `mailto`. | Use one of those schemes. |
| The banner closes before the user can answer. | A timeout or the app's defaults closed it. | Send with `"persistent": true`. |

## Related

- [Actions reference](reference/actions.md): every kind, field, rule, approval and failure.
- [Manifests](reference/manifests.md): declare an app's buttons once and offer them by id.
- [Forward a notification you missed](FORWARD-MISSED.md): a follow-up that forwards a banner to your phone.
- [Notifications API](reference/api/notifications.md#button-object): the button object a notification sends.
- [Replies API](reference/api/replies.md): read what the user typed, and the callback request.
- [App settings API](reference/api/apps.md): registration and per-app approvals.
- [Designing a banner](AUTHORING.md): the Designer and its **Actions** tab.
