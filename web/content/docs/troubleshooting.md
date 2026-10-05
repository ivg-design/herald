# Troubleshooting

This page lists what goes wrong most often with Herald and how to fix it. Find the group that matches what you see, then
the row. It is for anyone whose banner does not appear, whose request is refused, or whose button does nothing.

## Before you start

Start by checking that Herald is running and answering. This request needs no token.

```sh
D="$HOME/Library/Application Support/Herald"
HERALD="http://127.0.0.1:$(cat "$D/port")"
curl -s "$HERALD/v1/health"
```

```json
{"ok": true, "pid": 4821, "version": "1.8.1"}
```

If you get that reply, Herald is running and the rest of this page applies. If not, start with the first group.

## Herald does not answer

| Symptom | Cause | Fix |
|---|---|---|
| The CLI prints `Herald is not running. Launch Herald.app first.` and exits with status `2`. A client raises `HeraldUnavailable`. | Herald is not running. | Open Herald from Applications and look for the bell in the menu bar. |
| `cat: .../port: No such file or directory`. | Herald removes the `port` file when it quits. | Open Herald and read the file again. |
| `curl: (7) Failed to connect`, or connection refused on `48617`. | Another program owns the port, you changed it in Settings, or you hard-coded the number. | Read the `port` file instead of using a fixed number. If Herald cannot bind the port, the line under **Settings > General > Port** says so. Choose another port and press **Apply**. |
| `401` with `{"error":"unauthorized"}`. | The token is missing, wrong or old. | Read `~/Library/Application Support/Herald/token` again. **Settings > General > Reveal Token File in Finder** shows the file. |
| `403`. | The request came from a web page, so it carries an `Origin` header, or its `Host` header is not `127.0.0.1`, `localhost` or `[::1]`. | Send the request from a script or a program, not from a browser. Use the address `http://127.0.0.1:PORT`. |
| `413` with a field name. | A field is over its size limit. | Shorten the field. [Limits](reference/api/README.md#limits) lists the sizes. |
| `429`. | Herald already knows 200 apps or manifests. | Remove an app you do not use under **Settings > Apps**. |

## A notification is accepted but no banner appears

The request answered `{"ok": true}`, so Herald has the notification. It is in History. Open **History...** from the bell
menu to see it, then check these.

| Symptom | Cause | Fix |
|---|---|---|
| The notification is in History, marked **Active**, but not on screen. | The screen is full. Banners that do not fit are replaced by a **+N more** pill. | Look for the pill below the last banner. Press **+N more**, or **Dismiss All** in the bell menu. |
| The row has no banner and is counted as not dismissed. | The app's banners are muted. | Open **Settings > Apps**, select the app and turn off **Mute banners**. |
| The row reads **Snoozed until** a time. | The banner is snoozed. | Wait, or choose **Re-show as Banner** in History. |
| Nothing appears for an hour or at night. | A quiet hours window silences banners. | Check the **Quiet hours** section of **Settings > Voice**, or press **Resume Now** in the bell menu. |
| The banner appears on another display or corner. | The app has its own **Display** and **Screen corner**. | Change them under **Settings > Apps > Banners**. A display that is not connected falls back to the main display. |
| A banner vanishes in a few seconds. | The app's **Stay until dismissed** is off, or the notification has a `timeout`. | Turn on **Stay until dismissed** under **Settings > Apps**, or remove the `timeout`. See [How banners behave](reference/banners.md#how-long-a-banner-stays). |
| A second notification replaced the first. | Both used the same `id`. | Use a different `id` for each notification you want to keep on screen. |

## A banner behaves unexpectedly

| Symptom | Cause | Fix |
|---|---|---|
| Clicking the banner does not dismiss it. | A click on the body lifts the text limits or opens a link, and only the close button dismisses a banner with nothing to open. | Press the close button, the cross at the top right. [How banners behave](reference/banners.md#clicking-the-body) has the full table. |
| The banner has no close button. | Its template does not draw one. | Add an `iconButton` with a `dismiss` action in the [Designer](AUTHORING.md). |
| Clicking the banner does not open the app. | A registered `bundleId` alone does not open anything on a click. | Send a `url`, or set the template's `onClick` to `openApp`. |
| A link shows **Action failed**. | Only `http`, `https` and `mailto` links open. | Send an `https` link. |
| A button does nothing. | A command, script or Shortcut button needs the app to have asked for `allowCommands` and you to have allowed it. | Turn on **Allow this app to run commands, scripts and Shortcuts** under **Settings > Apps**. |
| A follow-up never ran. | You dismissed, answered or opened the banner first, Herald quit, the banner closed itself sooner, or the follow-up waits for approval. | Look for an approval question on the banner and a **Follow-up failed** line in History. See [Follow-ups](reference/actions.md#follow-ups). |
| A button asks a question in the banner. | Herald asks before it runs code on your Mac or sends data to another computer. | Answer **Run once**, **Always allow** or **Cancel**. See [Actions](reference/actions.md#approvals). |
| A callback button does nothing for an address that is not on this Mac. | Callbacks to another host need your approval. | Turn on **Allow callbacks to HOST** under **Settings > Apps**, or answer **Send once** in the banner. |
| **Add to Reminders** fails. | Herald has no access to Reminders. | Allow Herald in **System Settings > Privacy & Security > Reminders**. |
| The template is not applied. | A template belongs to one app and the notification named another, or the name is wrong. | Check `GET $HERALD/v1/templates?app=example.bidbot` and send the same `app`. See [Templates API](reference/api/templates.md). |

## Sound and speech

| Symptom | Cause | Fix |
|---|---|---|
| No sound. | **Mute Sounds** is on, the app's **Sound** is `none`, or the notification sent `sound: "none"`. | Check the bell menu, the app's **Sound** under **Settings > Apps**, and the notification. A quiet hours window that silences sounds also mutes them. |
| No speech. | The engine is **Off**, the app's switch under **Speak per app** is off, or quiet hours hold speech back. | Check **Settings > Voice**. Speech held back is recorded in History. |
| **Kokoro is not installed**. | The voice models are missing. | Press **Download Kokoro (about 340 MB)** in **Settings > Voice**. See [Voice](VOICE.md). |
| Speech works but is the wrong voice. | The app has its own voice, or the notification names one. | Check the voice menu in **Speak per app**. |

## The command line, clients and MCP

| Symptom | Cause | Fix |
|---|---|---|
| `herald: command not found`. | The tool is not installed, or its folder is not on your `PATH`. | Install it from **Settings > MCP > Install `herald` command line tool**. [Install Herald](install.md#install-the-command-line-tool) has the details. |
| The agent says Herald's tools are missing. | The server is not installed in that client. | Press **Install** or **Reinstall** for the client in **Settings > MCP**, then **Test connection**. See [Herald MCP server](MCP.md). |
| A client row says **Client not found**. | Herald could not find that program on this Mac. | Install the client, then reopen **Settings > MCP**. |

## Cloud agents

Problems with the cloud relay, such as a connector that cannot connect or a banner that does not arrive from a cloud
agent, are covered in [Cloud agents](CLOUD.md) and [Operating the relay](cloud/operating.md).

## Still stuck

Action logs are in `~/Library/Logs/Herald/`. **Settings > Actions > Show Log** opens the log of scripts, commands and
Shortcuts. The [project board](https://github.com/users/ivg-design/projects/14) tracks open work.

## Related

- [Install Herald](install.md)
- [Send your first notification](getting-started.md)
- [The Herald app](APP.md)
- [How banners behave](reference/banners.md)
- [HTTP API](reference/api/README.md): the shared errors and the limits.
