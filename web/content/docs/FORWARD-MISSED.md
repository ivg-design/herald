# Forward a notification you missed

A banner you did not see is a notification you missed. A follow-up fixes that: when a banner has been on screen for a
time you choose and nobody has answered it, Herald runs one action. This guide makes that action an Apple Shortcut that
sends the notification to your phone, your email or a Slack channel. When you finish, a banner you ignore for ten
minutes arrives somewhere you will see it, and the banner shows that it was forwarded.

## Before you start

- Herald is running and an app sends notifications that stay on screen, with `persistent: true` or a long timeout. A
  banner that closes itself first never follows up. See [Follow-ups](reference/actions.md#when-it-runs).
- The Shortcuts app is on this Mac, and you are signed in to the account the Shortcut will send from: Messages, Mail or
  Slack.
- You can answer a question on a banner: Herald asks once before the Shortcut first runs (step 3).

## Steps

### 1. Make the Shortcut

1. Open the Shortcuts app and make a new Shortcut. Name it `Forward to phone`.
2. Make the Shortcut accept a file as its input.

   Herald hands the notification over as a file: a text file when you give the follow-up a text, and a JSON file when you
   do not.

3. Add the action that sends the message, to your phone, your email address or a Slack channel.
4. Set the message body to the Shortcut's input.

   By default the input is the whole notification as JSON, with the keys `title`, `body`, `app` and the others. In the
   Designer you can choose a short text instead, such as `{title}`, and then the input is that text.

5. To use one Shortcut for a button and for a follow-up, branch on `herald.followUp`.

   - With the JSON input, read the `herald` object, then its `followUp` value. It is `true` for a follow-up and `false`
     for a pressed button. When it is `true`, start the message with `Missed:`.
   - With your own text, put `{herald.followUp}` in the text. It reads `true` for a follow-up and is empty for a pressed
     button.

6. Run the Shortcut once by hand with sample text.

   The message arrives, so you know the Shortcut works before Herald runs it.

### 2. Add it as a follow-up in the Designer

1. Open the Designer from the menu bar, choose the app and the template that draws its banner. [Design a
   banner](AUTHORING.md) shows how.
2. Open the **Actions** tab. Scroll to the **Follow-up** block, under **Buttons**.
3. Switch on **If not dismissed**.

   The block shows **After** with a number and a unit, set to 10 minutes, and **Run** with a menu.

4. Under **After**, check that it reads `10` and minutes, or change it. It accepts 5 seconds to 7 days.
5. Open the **Run** menu and choose **New Shortcut action...**.

   The **Follow-up action** form opens for an action that belongs to the follow-up alone.

6. In the form, pick `Forward to phone` from the list of Shortcuts. Set **Input** to **Text** and type `{title}` to
   send only the title, or leave **Input** on **Notification (JSON)** to send the whole notification.

   In a text input, `{herald.followUp}` and `{herald.unattendedSeconds}` are filled in, so
   `{title} ({herald.unattendedSeconds} s unanswered)` sends how long the banner waited.

7. Press **Save**, then save the template.

   The **Run** menu now names the Shortcut, followed by **(this follow-up)**.

If the Shortcut is already a button on the banner, choose that button in the **Run** menu instead of making a new
action. A follow-up that points at a button uses the button's settings.

### 3. Approve it

Herald never runs a Shortcut you have not allowed. Allowing it takes one answer.

1. Send a notification that uses the template and leave it alone for the time you set.

   When the time ends, nothing runs. The buttons give way to a question: **Run a Shortcut from the "TEMPLATE"
   template?** It names the Shortcut and its input.

2. Press **Always allow this template**, or **Run once**.

   With **Always allow**, later follow-ups of this template run while you are away. With **Run once**, Herald asks
   again the next time. Changing the Shortcut's name or input asks again either way.

For a follow-up the app declares, the question is **Run this Shortcut for APP?** and **Always allow APP** turns on
**Allow this app to run commands, scripts and Shortcuts** under **Settings > Apps**. If the app never registered to run
commands, nothing asks: the banner shows **Follow-up failed**.

**Settings > Actions** lists a template's Shortcut with its status, and
[`list_approvals`](reference/mcp/apps-and-settings.md#list_approvals) shows the state of every follow-up.

### 4. See what happens

When the time ends and the action is approved, the Shortcut runs. The banner stays on screen, and a line under its
buttons reads **Follow-up ran: Forward to phone · 14:05**. If the Shortcut fails, the line reads **Follow-up failed:**
and the reason.

History keeps the record. Its row shows the same line with the date and how long the banner went unanswered, and the
item carries a `followUp` object with its `outcome`, `ranAt` and `unattendedSeconds`. See
[History API](reference/api/history.md#the-history-record).

These end a follow-up before it runs:

- Dismissing the banner, pressing any button, replying or opening it cancels it.
- Quitting Herald cancels it, because the timer lives in memory.
- Snoozing drops the timer, and the banner that comes back starts a new one.

A follow-up runs at most once for a notification.

## Set it up from an agent

A local agent can add the follow-up without the Designer. It lists the Shortcuts first, so the name is right:

```json
{}
```

That is the call to [`list_shortcuts`](reference/mcp/templates.md#list_shortcuts). It answers with the names:

```json
{"count": 2, "shortcuts": ["Forward to phone", "Log to Notes"]}
```

Then it calls [`set_follow_up`](reference/mcp/templates.md#set_follow_up):

```json
{
  "app": "example.bidbot",
  "template": "Bid won",
  "after": "10m",
  "shortcut": "Forward to phone",
  "input": "{title}"
}
```

The result, trimmed, says what is left to do:

```json
{
  "saved": true,
  "app": "example.bidbot",
  "template": "Bid won",
  "createdTemplate": false,
  "origin": "template",
  "approval": "needs-approval",
  "needsApproval": true,
  "note": "Approval stays with the person at the Mac: the banner asks the first time the action would run."
}
```

`set_follow_up` never approves code. The agent tells you, and you approve at the Mac, in step 3.

From a terminal, the same call is:

```sh
herald template follow-up --app example.bidbot --name "Bid won" \
  --after 10m --shortcut "Forward to phone" --input "{title}"
```

See [`herald template follow-up`](reference/cli.md#herald-template-follow-up).

## When an app or a connector declares one

An app can declare a default follow-up in its [manifest](reference/manifests.md#follow-up). It is a suggestion, and you
decide.

- The Designer's **Follow-up** block shows **From the issuer: LABEL after DURATION** with a switch. Turn it off to stop
  it for this template, or leave it on and add nothing.
- **Settings > Apps** shows **Declares a follow-up: LABEL after DURATION** for that app.
- An issuer's follow-up that runs code needs the app's **Allow this app to run commands, scripts and Shortcuts**
  switch.

A cloud agent's notifications arrive as the app `cloud.NAME`, and the relay refuses a request that carries a
follow-up. The connector cannot add one itself, but you can add one to its notifications:

1. Choose the connector's app and its template in the Designer.
2. Follow step 2 above.

This is how a ChatGPT connector or an OpenAI dot's notifications reach your phone when you are away from the Mac. See
[Cloud relay](CLOUD.md).

## Check that it works

Send a test notification that uses the template, with `"persistent": true`, and leave it for the time you set. Use a
short time, such as 10 seconds, while you test. The message should arrive on your phone, and the banner should show
**Follow-up ran**.

## If it does not work

| Symptom | Cause | Fix |
|---|---|---|
| Nothing happens, and the banner shows a question. | The Shortcut or its template is not approved yet. | Answer the question. See step 3. |
| Nothing happens and there is no question. | The banner was dismissed, answered or opened first, or Herald quit. | Leave the banner alone for the full time, with Herald running. |
| Nothing happens on a banner that closes. | The banner's timeout is not longer than the follow-up time. | Send with `persistent: true`, or raise the timeout. |
| The banner shows **Follow-up failed**. | The Shortcut failed, such as a Slack sign-in that expired. | Run the Shortcut in the Shortcuts app and fix it. |
| **Follow-up failed** says the app is not allowed to run commands. | The app never registered with `allowCommands`. | Register the app with `allowCommands: true`, then send again. |
| The **Run** menu does not list a link button. | Only a Shortcut, script, command or callback can follow up. | Make the Shortcut forward the link. |
| `set_follow_up` says `approval` is `app-permission-needed`. | The follow-up is the issuer's and the app may not run code yet. | Turn on the app's switch in **Settings > Apps**. |

## Related

- [Follow-ups](reference/actions.md#follow-ups): the timer, the kinds, the approval and the record.
- [Two-way notifications](ACTIONS.md): buttons that run a Shortcut when you press them.
- [Design a banner](AUTHORING.md): the Designer and its **Actions** tab.
- [`set_follow_up`](reference/mcp/templates.md#set_follow_up) and
  [`PUT /v1/templates/follow-up`](reference/api/templates.md#put-v1templatesfollow-up): add a follow-up from an agent.
- [Connect an agent with a key](cloud/connect-agent.md): the cloud connector's side.
