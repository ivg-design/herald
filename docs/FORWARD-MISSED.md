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
- You can press a button on the banner, because Herald asks you once before the Shortcut first runs.

## Steps

### 1. Make the Shortcut

1. Open the Shortcuts app and choose **New Shortcut**. Name it `Forward to phone`.
2. Open the Shortcut's details with the info button and check that it accepts **Text** and **Files** as input. Herald
   hands the notification over as **Shortcut Input**, as a text file when you choose a text and as a JSON file when you
   do not.

3. Add the action that sends the message:
   - **Send Message** to your own number or a contact, to reach your phone.
   - **Send Email** to your own address.
   - A **Slack** action such as **Send Message to Channel**, to post to a channel.

4. Set the message body to **Shortcut Input**.

   Herald gives the Shortcut one of two things. By default it is the whole notification as JSON, with the keys `title`,
   `body`, `app` and the others. The Designer lets you choose a short text instead, such as `{title}`, and then
   **Shortcut Input** is that text.

5. To use one Shortcut for a button and for a follow-up, branch on `herald.followUp`. When the Shortcut receives the
   JSON, add **Get Dictionary from Input**, then **Get Dictionary Value** for the key `herald`, then again for the key
   `followUp`. Add an **If** action that tests whether the value is `true`. In the **If** branch, start the message with
   `Missed:`. In the **Otherwise** branch, send it as it is.

   When the Shortcut receives your own text, put `{herald.followUp}` in that text and test the text instead.

6. Press the play button in the Shortcuts app once with sample text.

   The message arrives, so you know the Shortcut works before Herald runs it.

### 2. Add it as a follow-up in the Designer

1. Open the Designer from the menu bar, choose the app and the template that draws its banner. [Design a
   banner](AUTHORING.md) shows how.
2. Open the **Actions** tab. Scroll to the **Follow-up** block, under **Buttons**.
3. Switch on **If not dismissed**.

   The block shows **After** with a number and a unit, and **Run** with a menu.

4. Under **After**, type `10` and choose minutes.
5. Open the **Run** menu and choose **New Shortcut action...**.

   The **Add action** form opens for an action that belongs to the follow-up alone.

6. In the form, pick `Forward to phone` from the list of Shortcuts, and in **Input** type `{title}` to send only the
   title, or leave it empty to send the whole notification.

   The tokens `{herald.followUp}` and `{herald.unattendedSeconds}` are available in **Input**, so
   `{title} ({herald.unattendedSeconds} s unanswered)` sends how long the banner waited.

7. Press **Save**, then save the template.

   The **Run** menu now names the Shortcut, followed by **(this follow-up)**.

If the Shortcut is already a button on the banner, choose that button in the **Run** menu instead of making a new
action. A follow-up that points at a button uses the button's settings.

### 3. Approve it

Herald never runs a Shortcut you have not allowed. Allowing it takes one answer.

1. Send a notification that uses the template and leave it alone for the time you set.

   When the time ends, nothing runs. The buttons give way to a question: **Run a command from the "TEMPLATE"
   template?** It names the Shortcut and its input.

2. Press **Always allow this template**, or **Run once**.

   With **Always allow**, later follow-ups of this template run while you are away. With **Run once**, Herald asks
   again the next time. Changing the Shortcut's name or input asks again either way.

For an app's own follow-up, the question is **Run this command for APP?** and **Always allow APP** turns on **Allow
this app to run commands, scripts and Shortcuts** under **Settings > Apps**. You can see the state of every follow-up
in **Settings > Actions**, or with [`list_approvals`](reference/mcp/apps-and-settings.md#list_approvals).

### 4. See what happens

When the time ends and the action is approved, the Shortcut runs. The banner stays on screen, and a line under its
buttons reads **Follow-up ran: Forward to phone · 14:05**. If the Shortcut fails, the line reads **Follow-up failed:**
and the reason.

History keeps the record. The row shows the same line, and the item carries a `followUp` object with its `outcome`,
`ranAt` and `unattendedSeconds`. See [History API](reference/api/history.md#the-history-record).

Dismissing the banner, pressing any button, replying or opening it before the time ends cancels the follow-up.
Snoozing restarts it when the banner comes back. A follow-up runs at most once, and Herald keeps the timer in memory, so
quitting Herald cancels it.

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

The result says what is left to do:

```json
{
  "saved": true,
  "app": "example.bidbot",
  "template": "Bid won",
  "createdTemplate": false,
  "origin": "template",
  "approval": "needs-approval",
  "needsApproval": true,
  "note": "Saved. The follow-up will not run until the person approves this template's Shortcut at the Mac."
}
```

`set_follow_up` never approves code. The agent tells you, and you approve at the Mac, in step 3. From a terminal, the
same call is `herald template follow-up --app example.bidbot --name "Bid won" --after 10m --shortcut "Forward to
phone" --input "{title}"`. See [`herald template follow-up`](reference/cli.md#herald-template-follow-up).

## When an app or a connector declares one

An app can declare a default follow-up in its [manifest](reference/manifests.md#follow-up). It is a suggestion, and you
decide. The Designer's **Follow-up** block then shows **From the issuer: LABEL after DURATION** with a switch. Turn it
off to stop it for this template, or leave it on and add nothing. **Settings > Apps** shows **Declares a follow-up:
LABEL after DURATION** for that app. An issuer's follow-up that runs code needs the app's **Allow this app to run
commands, scripts and Shortcuts** switch.

A cloud agent's notifications arrive as the app `cloud.NAME`, and the relay never lets the agent send a follow-up. You
can add a follow-up to a connector's notifications in the Designer; the connector cannot add one itself. Choose the
connector's app and its template, then follow step 2. This is how a ChatGPT connector or an OpenAI dot's notifications
reach your phone when you are away from the Mac. See [Cloud relay](CLOUD.md).

## Check that it works

Send a test notification that uses the template, with `"persistent": true`, and leave it for the time you set. Use a short
time, such as 10 seconds, while you test. The message should arrive on your phone, and the banner should show
**Follow-up ran**.

## If it does not work

| Symptom | Cause | Fix |
|---|---|---|
| Nothing happens, and the banner shows a question. | The Shortcut or its template is not approved yet. | Answer the question. See step 3. |
| Nothing happens and there is no question. | The banner was dismissed, answered or opened first, or Herald quit. | Leave the banner alone for the full time, with Herald running. |
| Nothing happens on a banner that closes. | The banner's timeout is not longer than the follow-up time. | Send with `persistent: true`, or raise the timeout. |
| The banner shows **Follow-up failed**. | The Shortcut failed, such as a Slack sign-in that expired. | Run the Shortcut in the Shortcuts app and fix it. |
| The **Run** menu does not list a link button. | Only a Shortcut, script, command or callback can follow up. | Make the Shortcut forward the link. |
| `set_follow_up` says `approval` is `app-permission-needed`. | The follow-up is the issuer's and the app may not run code yet. | Turn on the app's switch in **Settings > Apps**. |

## Related

- [Follow-ups](reference/actions.md#follow-ups): the timer, the kinds, the approval and the record.
- [Two-way notifications](ACTIONS.md): buttons that run a Shortcut when you press them.
- [Design a banner](AUTHORING.md): the Designer and its **Actions** tab.
- [`set_follow_up`](reference/mcp/templates.md#set_follow_up) and
  [`PUT /v1/templates/follow-up`](reference/api/templates.md#put-v1templatesfollow-up): add a follow-up from an agent.
- [Connect an agent with a key](cloud/connect-agent.md): the cloud connector's side.
