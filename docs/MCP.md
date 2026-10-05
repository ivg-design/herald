# Connect an agent to Herald (MCP)

By the end of this page an AI agent, such as Claude Code, Codex or Claude Desktop, is connected to Herald through its MCP server, `herald-mcp`. You install the server from **Settings > MCP** with one click per client. This page is for the person who uses the agent. The tools themselves are documented in the [MCP server reference](reference/mcp/README.md).

Once connected, the agent can do three things:

- Show you banners under its own name and icon.
- Ask you a question and read your answer.
- Help you design how an app's banners look.

## Before you start

- Herald is installed and running. The bell is in the menu bar. See [Install Herald](install.md).
- The client you want to connect is installed on this Mac: Claude Code, Codex or Claude Desktop. Any other MCP client can use the generic config.
- You know that installing a client edits that client's own configuration file. Herald keeps a backup next to it.

## Steps

1. Click the Herald bell in the menu bar, choose **Settings**, and open the **MCP** tab.

   ![The MCP tab of Herald's Settings: the Server section with its path and Test connection, one row per client with its status, and the Command line tool section](../web/public/shots/docs/settings-mcp.png "Settings > MCP. Each client row shows Installed or Not installed and a Reinstall or Install button.")

   The **Server** section shows the path of the bundled server. Herald.app carries it in `Herald.app/Contents/Helpers/`, signed with the app.

2. Press **Test connection**. Herald starts the server, asks it for its tools and shows the result in green, for example **OK: 70 tools**. A red message means the server could not start; see [If it does not work](#if-it-does-not-work).

3. In the **Clients** section, find the row for your client. Its status reads **Installed**, **Not installed** or **Client not found**. Press **Install**. If the status is **Installed** the button reads **Reinstall**.

   What each install does:

   | Row | What Herald changes |
   |---|---|
   | Claude Code | Runs `claude mcp add --scope user herald -- <path> --agent claude-code`. Reinstall removes the old entry first. |
   | Codex | Adds or replaces the `[mcp_servers.herald]` table in `~/.codex/config.toml` and keeps a backup, `config.toml.bak`. |
   | Claude Desktop | Merges a `herald` entry into `mcpServers` in `~/Library/Application Support/Claude/claude_desktop_config.json`, keeps your other servers and keeps a backup. |

   A message under the row says what happened and which file or command was touched. A green message means it worked.

4. For any other MCP client, use the **Generic** row.

   1. Type the client's name in **Client name**, for example `My Bot`.
   2. Optionally press **Choose icon...** to pick an image.
   3. Press **Add and copy config**. Herald registers the client and puts the JSON entry and the command line on the clipboard.
   4. Paste the JSON into the client's MCP configuration. It looks like this, with the server path that the **Server** section shows:

   ```json
   {
     "mcpServers": {
       "herald": {
         "command": "/Applications/Herald.app/Contents/Helpers/herald-mcp",
         "args": ["--agent", "my-bot"]
       }
     }
   }
   ```

5. Restart the client. MCP clients read their configuration when they start.

6. Optional: press **Install `herald` command line tool** in the **Command line tool** section. Herald copies the `herald` tool to `/usr/local/bin`. It asks for an administrator password only when that folder is not writable.

Each installed client becomes an app of its own in Herald, with its own icon, sound and banner design. Its row shows these parts:

| Part | What it does |
|---|---|
| The app id | For example `agent.claude-code`. |
| **Design notifications...** | Opens the Designer on this agent's banner. |
| **Opens:** | The application that the banner's **Open** button brings to the front. **Choose app...** changes it and **Default** resets it. |
| **No icon found** and **Choose...** | Shown when Herald found no icon for the product. **Choose...** picks one. |

## Check that it works

In the client, ask the agent to call `herald_status`. It answers with `"running": true` and the port Herald uses. Then ask it to send you a notification:

```json
{"title": "Hello from the agent", "body": "Herald is connected.", "status": "done"}
```

A banner appears on screen with the agent's name and icon. In Claude Code the tools appear as `mcp__herald__<tool>`, and `claude mcp list` lists `herald`.

## What the agent can do

Once connected, the agent has 70 tools. They fall into five groups. The [tool index](reference/mcp/README.md#tool-index) lists every one.

| The agent can | Main tools | Where it is described |
|---|---|---|
| Tell you something, with or without a banner. | [`send_notification`](reference/mcp/notifications.md#send_notification), [`speak`](reference/mcp/notifications.md#speak) | [Notification tools](reference/mcp/notifications.md) |
| Ask you a question and read the answer. | [`wait_for_reply`](reference/mcp/notifications.md#wait_for_reply), [`get_replies`](reference/mcp/notifications.md#get_replies) | [Notification tools](reference/mcp/notifications.md#ask-the-user-a-question) |
| Design a banner and look at it. | [`put_template`](reference/mcp/templates.md#put_template), [`render_preview`](reference/mcp/templates.md#render_preview), [`send_test`](reference/mcp/notifications.md#send_test) | [Template tools](reference/mcp/templates.md) |
| Forward a missed banner: give a template a follow-up. | [`set_follow_up`](reference/mcp/templates.md#set_follow_up) | [Template tools](reference/mcp/templates.md#set_follow_up) |
| Add buttons: an Apple Shortcut, a script, a shell command or a URL. | [`add_action_rule`](reference/mcp/templates.md#add_action_rule), [`list_shortcuts`](reference/mcp/templates.md#list_shortcuts) | [Template tools](reference/mcp/templates.md#buttons) |
| Change settings, read History, set up the cloud relay. | [`set_settings`](reference/mcp/apps-and-settings.md#set_settings), [`history_search`](reference/mcp/apps-and-settings.md#history_search), [`relay_status`](reference/mcp/relay.md#relay_status) | [Apps and settings](reference/mcp/apps-and-settings.md), [Cloud relay tools](reference/mcp/relay.md) |

The agent never presses a banner button and never runs an action itself. A command, script or Shortcut it adds asks you for confirmation inside Herald the first time it would run, and again if it changes. The permission for an app to run commands, scripts and Shortcuts or call a remote host cannot be given through the server at all. Only you can give it, in **Settings > Apps**. See [Actions](ACTIONS.md).

## A worked session

You ask Claude Code: "Make the BidBot banner show the item and a count badge. Keep the View button, hide Withdraw, and add a Follow up button that runs my Create follow-up shortcut." The tool calls below are what the agent sends. The agent works through the same checks you would do in the Designer; see [Design a banner](AUTHORING.md) for that view.

**1. Look at what the app sends.** The agent reads the manifest. Its field keys are the `{tokens}` a template can show.

```json
{"app": "example.bidbot"}
```

The reply lists the manifest's fields and actions. The full shape is in [`get_manifest`](reference/mcp/templates.md#get_manifest).

| Part | Contents |
|---|---|
| Fields | `title` (required), `item` and `bids`. |
| Actions | `view` and `withdraw`. |

**2. Draft a template.** The agent reads [`component_schema`](reference/mcp/templates.md#component_schema) once to learn the grid, then saves a first draft. The draft has two slips: the count badge sits in the same cell as the title, and `colSpan` is spelled `colspan`. Herald refuses it and names the cells.

```json
{
  "ok": false,
  "error": "Template not saved: 1 error(s). Fix them and call again.",
  "saved": false,
  "errors": [{"severity": "error", "path": "cells[2]", "cellId": "bids", "message": "cell 'bids' overlaps cell 'title' at row 0, col 1"}],
  "warnings": [{"severity": "warning", "path": "cells[3].colspan", "cellId": "item", "message": "unknown key 'colspan' is ignored (did you mean 'colSpan'?)"}]
}
```

Nothing was saved. The tool returns every error with its cell id so the agent fixes exactly those cells.

**3. Fix both and save it as the app's default.** The `bids` badge moves to column 2 and `colSpan` is spelled correctly.

```json
{
  "template": {
    "name": "bid-won",
    "app": "example.bidbot",
    "layoutVersion": 2,
    "grid": {"rows": 3, "cols": 3, "rowSizes": ["auto", "auto", "auto"], "colSizes": [40, "fill", "auto"], "gap": 6, "padding": 12, "width": 380},
    "cells": [
      {"id": "icon", "row": 0, "col": 0, "rowSpan": 2, "component": {"type": "issuerIcon", "size": 32}},
      {"id": "title", "row": 0, "col": 1, "component": {"type": "text", "binding": "{title}", "style": "title", "maxLines": 2}},
      {"id": "bids", "row": 0, "col": 2, "component": {"type": "badge", "binding": "{bids}"}},
      {"id": "item", "row": 1, "col": 1, "colSpan": 2, "component": {"type": "text", "binding": "{item}", "maxLines": 3}},
      {"id": "actions", "row": 2, "col": 0, "colSpan": 3, "component": {"type": "actions", "source": "merged", "layout": "wrap"}}
    ]
  },
  "setAsDefault": true
}
```

```json
{
  "saved": true,
  "app": "example.bidbot",
  "name": "bid-won",
  "layoutVersion": 2,
  "cells": 5,
  "isDefault": true,
  "warnings": [],
  "notes": [],
  "next": "render_preview to look at it; send_test to see the real banner."
}
```

**4. Look at it in dark mode with a long item and a big count.** [`render_preview`](reference/mcp/templates.md#render_preview) returns a picture. Overriding `data` shows how the text wraps and how the badge copes with two digits.

```json
{"app": "example.bidbot", "name": "bid-won", "appearance": "dark", "data": {"bids": 14, "item": "Oak desk with three drawers, restored in 1962"}}
```

The agent sees the picture, notices that the item wraps to three lines and the badge is tight, and adjusts `maxLines` and the badge column with another `put_template` call.

**5. Change the buttons.** The agent asks for the installed Shortcuts, then adds two rules. Both calls go to [`add_action_rule`](reference/mcp/templates.md#add_action_rule).

```json
{"app": "example.bidbot", "template": "bid-won", "rule": {"match": "withdraw", "hide": true}}
```

```json
{
  "app": "example.bidbot",
  "template": "bid-won",
  "rule": {"add": {"id": "followup", "label": "Follow up", "kind": "shortcut", "shortcut": "Create follow-up", "input": "{title}\n{item}"}}
}
```

The second reply lists the resulting buttons: View (from BidBot) and Follow up (yours). BidBot's View button still opens its URL. Follow up runs your Shortcut with the title and item as text input. Every action also receives the whole payload, so a Shortcut or script can use more fields than the ones the template shows.

**6. Show it for real.**

```json
{"app": "example.bidbot", "template": "bid-won"}
```

[`send_test`](reference/mcp/notifications.md#send_test) puts a real banner on your screen with the sample values. Pressing a callback button on it calls the issuing app, so the agent tells you before you click.

## Agents as issuers

An agent that sends notifications is an issuer, the same as BidBot: it has an app id, a name, an icon, a sound, a manifest and a default template. That is why its banners arrive under its own name and why you can design them in the Designer like any other app's.

Installing a client does two things:

1. It writes the server entry with `--agent <slug>`, for example `--agent claude-code`.
2. It registers the agent as an app, `agent.claude-code`, with a manifest and a default template named `agent`.

With the identity set, the agent can call [`send_notification`](reference/mcp/notifications.md#send_notification) without naming an app, and Herald sends as `agent.claude-code`.

| Client | App id |
|---|---|
| Claude Code | `agent.claude-code` |
| Codex | `agent.codex` |
| Claude Desktop | `agent.claude-desktop` |
| Generic | `agent.<slug of the name you typed>` |

The agent banner has these parts:

- A close button.
- An **Open** button that brings the agent's own application to the front.
- A **Reply** button that opens a text field inside the banner.
- An **Open link** button, when the notification carries a link.
- A badge that shows the notification's status: `done`, `failed`, `waiting` or `question`.

The reference describes the fields, the buttons and the identity rules in [Agent identity](reference/mcp/README.md#agent-identity).

Installing again is safe. Herald keeps your template, the app's sound, name and icon, and a default template you chose.

### Ask a question

The agent has no web server for Herald to call, so answers come back through a queue. It sends a persistent notification with `status: "question"` and an `id`, then waits for the reply:

```json
{"title": "Which branch?", "body": "main or release/2?", "status": "question", "persistent": true, "id": "q-branch"}
```

```json
{"notificationId": "q-branch", "timeoutSeconds": 120}
```

The banner shows **Reply**. You press it, type `release/2` into the field and send. [`wait_for_reply`](reference/mcp/notifications.md#wait_for_reply) returns `{"replied": true, ...}` with your text. If you do not answer in time it returns `{"replied": false, "timedOut": true}` and the agent can wait again.

## Install without the app

If you build Herald from source, `make install-cli` installs `herald` and `herald-mcp` to `/usr/local/bin`, or to `~/bin` when `/usr/local/bin` is not writable. Then register the server by hand, as below.

For Claude Code:

```sh
claude mcp add --scope user herald -- /usr/local/bin/herald-mcp --agent claude-code
```

For Codex, in `~/.codex/config.toml`:

```toml
[mcp_servers.herald]
command = "/usr/local/bin/herald-mcp"
args = ["--agent", "codex"]
```

The server options, such as a different port for a second Herald, are in the [server reference](reference/mcp/README.md#how-the-server-connects-to-herald).

## If it does not work

| Symptom | Cause | Fix |
|---|---|---|
| **Test connection** shows **Failed**, or **Server not found at ...**. | The bundled server is missing, for example because Herald is not run from its app bundle. | Reinstall Herald.app, or run `make install-cli` and register `/usr/local/bin/herald-mcp`. |
| The row says **Client not found**. | Herald did not find the client's command or configuration on this Mac. | Install the client, then reopen **Settings > MCP**. For another client use the **Generic** row. |
| The install message says `The claude command was not found.` | Claude Code's `claude` command is not in a place Herald looks. | Install Claude Code. Herald looks in the usual folders, such as `~/.local/bin`, `/opt/homebrew/bin` and `/usr/local/bin`. |
| The message says `herald is already registered in Claude Code. Use Reinstall to replace it.` | An entry named `herald` exists. | Press **Reinstall**. |
| The tools do not appear in the client. | The client has not restarted, or it could not start the server. | Restart the client, then run `herald-mcp --version`. Follow the by-hand check in the [server reference](reference/mcp/README.md#how-the-server-connects-to-herald) and read the client's MCP log. |
| A tool says `Herald is not running or not reachable`. | Herald.app is not running, or the `port` file is not where the server looked. | Start Herald. Ask the agent to call `herald_status`: it shows the folder and port the server used. |
| A tool says `Herald rejected the token`. | Another Herald owns the port, or the token file changed. | Fix `HERALD_SUPPORT_DIR` or `HERALD_PORT` for the server, then restart the client. |
| `send_notification` says a button carries a shell `command`. | The agent sent a command button without `allowCommandButtons`. | This is the safety rule working. Ask the agent for a URL or callback button, or tell it to pass `allowCommandButtons: true` if you want the command. |
| No banner appears, but the tool says `sent`. | The agent's app is muted, or quiet hours silence banners. | Open **Settings > Apps**, select the agent's app and turn off **Mute banners**. See [Quiet hours](reference/quiet-hours.md). |
| `render_preview` fails with a 400. | Herald rejected the template or the data. | Read the message. It names the cell. |

More general problems are in [Troubleshooting](troubleshooting.md).

## Related

- [MCP server reference](reference/mcp/README.md) for conventions, agent identity, resources and the index of all tools.
- [Notification tools](reference/mcp/notifications.md), [template tools](reference/mcp/templates.md), [apps and settings tools](reference/mcp/apps-and-settings.md) and [cloud relay tools](reference/mcp/relay.md).
- [Agent quick start](AGENT-QUICKSTART.md) for the shortest path.
- [Design a banner](AUTHORING.md) for the same work in the Designer.
- [Actions](ACTIONS.md) for the button kinds and the confirmation rules.
- [Cloud](CLOUD.md) for agents that run away from this Mac.
