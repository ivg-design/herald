# MCP server

`herald-mcp` is Herald's MCP server. It lets an AI agent, such as Claude Code, Codex, Claude Desktop or any other MCP client, do on your Mac what you do with Herald's own windows: show a banner, speak a message, ask you a question and read your answer, and design how an app's banners look and what their buttons do. This page is the reference for the server as a whole: how it connects, what every tool shares, how an agent is identified, which resources it offers, and an index of all 69 tools. It is for people who build or configure an agent integration. To install the server in a client, see [Connect an agent](../../MCP.md).

## Concepts

**What the server is.** `herald-mcp` is a small program that ships inside Herald.app, in `Herald.app/Contents/Helpers/`.

- An MCP client starts it as a child process and talks to it over standard input and output.
- It holds no data of its own. Every tool turns into one call to the [HTTP API](../api/README.md) of the running Herald, and the reply comes back to the agent as the tool's result.
- Herald.app must therefore be running, except for [`component_schema`](templates.md#component_schema) and [`validate_template`](templates.md#validate_template), which work without it.

**What it never does.** The server never presses a banner button and never runs an action. In practice:

- A command, script or Apple Shortcut that a template adds asks you for confirmation inside Herald the first time it would run, and again whenever it changes.
- The permissions that let an app run commands or call a remote host cannot be granted through the server. The agent is the program that approval guards against, so only you can give it, in **Settings > Apps**.
- An agent can read those approvals and withdraw them. See [Actions](../actions.md).

**Transport.** The server speaks JSON-RPC 2.0, one message per line, on standard input and output. It implements MCP protocol version `2025-06-18` and also accepts `2025-03-26` and `2024-11-05`. It writes logs to standard error only, so standard output carries protocol messages and nothing else. It offers tools and resources. It offers no prompts.

**Who it is for.** It is for an agent that should tell you something while it works, and for an agent that you want to help design banners. Agents that run in the cloud, away from this Mac, reach Herald through the cloud relay instead; see [Cloud](../../CLOUD.md).

## How the server connects to Herald

Herald writes its port and its bearer token into its support folder, `~/Library/Application Support/Herald/`. The server reads the `port` and `token` files there, exactly as the `herald` command line tool does. Normally there is nothing to configure. These options exist for a second Herald, such as a debug build on another port, and for tests.

| Option | Environment variable | Meaning |
|---|---|---|
| `--support-dir DIR` | `HERALD_SUPPORT_DIR` | The folder that holds the `token` and `port` files. |
| `--port N` | `HERALD_PORT` | The port to use instead of the one in the `port` file. |
| `--token T` | `HERALD_TOKEN` | The token to use instead of the `token` file. Prefer the environment variable: a flag shows in the process list. |
| `--preview-dir DIR` | `HERALD_PREVIEW_DIR` | Where [`render_preview`](templates.md#render_preview) saves its PNG files. Default `$TMPDIR/herald-previews`; the newest 40 are kept. |
| `--agent NAME` | `HERALD_AGENT` | The identity the server sends as. See [Agent identity](#agent-identity). |
| `--debug` | `HERALD_MCP_DEBUG=1` | Logs each request to standard error. |

`herald-mcp --version` prints the version and `herald-mcp --help` prints the usage.

To try the server by hand, send it two lines. The first starts the session and the second calls a tool.

```sh
printf '%s\n' \
  '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"cli","version":"0"}}}' \
  '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"herald_status","arguments":{}}}' | herald-mcp
```

## Conventions

These rules hold for every tool.

**Results are JSON text.** A successful call returns one text block that holds a JSON document. Keys are sorted and short documents stay on one line. Two tools return a picture as well: [`render_preview`](templates.md#render_preview) and [`designer_snapshot`](templates.md#designer_snapshot) return an image block (`image/png`) followed by a text block with the file path, the byte count and the pixel size.

**Failures are results, not protocol errors.** A tool that cannot do what was asked returns a result with `isError: true`. The text is a JSON document with `ok: false`, an `error` sentence that says what to do next, and extra fields where they help, such as `errors` with a path and a cell id. The agent can read it and try again.

```json
{
  "ok": false,
  "error": "Missing required argument 'app'."
}
```

Only an unknown tool name is a JSON-RPC error, code `-32602`. A missing required argument is a tool error before any request reaches Herald.

**Errors about Herald itself** use fixed wording:

| Message starts with | Cause | Fix |
|---|---|---|
| `Herald is not running or not reachable` | Herald.app is not running, or the `token` and `port` files are not where the server looked. | Start Herald.app. [`herald_status`](notifications.md#herald_status) shows the folder and port the server used. |
| `Herald rejected the token` | Another Herald owns the port, or the token file changed. | Correct `HERALD_SUPPORT_DIR` or `HERALD_PORT`, then restart the server. The client restarts it. |
| `Herald answered 404 for this request` | The running Herald is too old for this tool. | Update Herald and restart it. |
| `The running Herald does not support this (501 ...)` | The Herald build lacks this feature. | Update Herald. |
| `Herald returned <status>: <message>` | Herald refused the request. The message is Herald's own. | Read the message. It names the field or the cell. |

**Arguments are forgiving.** A number or boolean given as a string (`"5"`, `"true"`) is accepted. An object given as a JSON string is accepted. Unknown arguments are ignored by most tools. [`send_notification`](notifications.md#send_notification) passes them through as notification fields.

**Each tool carries hints.** Every tool in `tools/list` has a `title` and the MCP annotations `readOnlyHint`, `destructiveHint`, `idempotentHint` and `openWorldHint`, so a client can ask you before it runs a destructive call.

**Validation issues** are objects in the `errors` and `warnings` lists of a failed or checked template. Each has these keys:

| Key | Type | Meaning |
|---|---|---|
| `severity` | string | `error` or `warning`. |
| `path` | string | A JSON path to the problem, such as `cells[2].component.binding`. |
| `cellId` | string | The id of the cell, present only when the problem is inside a template cell. |
| `message` | string | What is wrong, in a sentence. |

## Agent identity

An agent that sends notifications is an **issuer** like any other app: it has an app id, a name, an icon, a sound, a manifest and a default template. You design its banners in the Designer and set its sound and corner in **Settings > Apps**.

Installing a client from **Settings > MCP** (or with [`install_mcp`](apps-and-settings.md#install_mcp) or `herald mcp install`) does two things:

1. It writes the server entry into the client's configuration with `--agent <slug>`.
2. It registers the agent as an issuer, with the app id `agent.<slug>`.

| Client | App id | Symbol on the status badge |
|---|---|---|
| Claude Code | `agent.claude-code` | `terminal` |
| Codex | `agent.codex` | `sparkles` |
| Claude Desktop | `agent.claude-desktop` | `message.circle` |
| Generic client | `agent.<slug of the name you type>` | `bolt.circle` |

`--agent` accepts the slug (`claude-code`) or the full id (`agent.claude-code`). A slug holds lower-case letters, digits and hyphens, at most 48 characters. A name that leaves nothing usable after slugging makes the server exit with a usage message.

With an agent identity set, `app` becomes optional on the tools that take it.

- The server fills in the agent's own app when a call leaves `app` out.
- `tools/list` shows `app` as optional and names the default in the description.
- An explicit `app` always wins.

These tools take the agent's own app when `app` is left out:

- [`send_notification`](notifications.md#send_notification)
- [`send_test`](notifications.md#send_test)
- [`speak`](notifications.md#speak)
- [`dismiss`](notifications.md#dismiss)
- [`list_stacks`](notifications.md#list_stacks)
- [`get_replies`](notifications.md#get_replies)
- [`wait_for_reply`](notifications.md#wait_for_reply)
- [`list_history`](apps-and-settings.md#list_history)

Every other tool is unchanged.

**What the install registers.** The registered manifest declares the fields an agent has to say. A field that is not sent collapses on the banner. Each field has a sample for previews.

| Field | Type | Required | Meaning |
|---|---|---|---|
| `title` | text | yes | The headline of the banner. |
| `body` | text | no | The message text. |
| `status` | text | no | `done`, `failed`, `waiting` or `question`. It fills the status badge. |
| `project` | text | no | The project the agent works on. |
| `session` | text | no | A short session id. |
| `task` | text | no | The name of the task. |
| `tool` | text | no | The last tool the agent used. |
| `duration` | text | no | How long the work took. |
| `link` | url | no | A page that **Open link** opens. |
| `needsInput` | bool | no | Whether the agent waits for an answer. |

The manifest declares three actions: `open`, `reply` and `open-link`. The default template is named `agent`. It shows these parts:

- The product icon.
- The title and body.
- A status badge that carries the agent's symbol.
- The close button.
- The project and the time.
- The button row.

The full format is in [Manifests](../manifests.md).

Every control on an agent banner does one thing, and none repeats another:

| Control | What it does |
|---|---|
| Close (x) | Dismisses the banner. There is no separate Dismiss or Done button. |
| **Open** | Brings the agent's host application to the front. It never opens a URL. |
| **Reply** | Swaps the buttons for a text field inside the banner. The text is stored on the notification and in the app's reply queue. |
| **Open link** | Opens the notification's `link`. It appears only when the notification has one. |

An agent that names no buttons gets Open, Reply and, with a `link`, Open link. The manifest's `appBundleId` or `appPath` sets what **Open** brings forward:

- Claude Desktop opens `Claude.app`.
- Claude Code, Codex and generic clients open the terminal or editor the install ran from, and Terminal when none is found.

You can change the target in **Settings > MCP** (**Opens:**, then **Choose app**), with the `opens` argument of [`install_mcp`](apps-and-settings.md#install_mcp), or with [`update_app_settings`](apps-and-settings.md#update_app_settings).

**Installing again is safe.** Herald brings the manifest up to date, but it keeps your template once it exists, the app's sound, name and icon, and a default template you chose.

**Cloud agents.** An agent key created for the cloud relay also becomes an issuer, with the app id `cloud.<key name>`. Its banner offers Reply, Record and Open link, because there is nothing on this Mac to open. See [Connect an agent](../../cloud/connect-agent.md).

## Resources

Resources are documents an agent can read without calling a tool. The URI parts after the scheme are percent-encoded, so a template named `Bid won` is `Bid%20won`.

| URI | Content |
|---|---|
| `herald://manifests/<app>` | The app's manifest as JSON, with long strings shortened as [`get_manifest`](templates.md#get_manifest) does. |
| `herald://templates/<app>/<name>` | A template as JSON. The built-in names `builtin.imageLeft`, `builtin.imageRight`, `builtin.hero` and `builtin.compact` work. |
| `herald://docs/components` | A short Markdown guide to the template format. [`component_schema`](templates.md#component_schema) has every property. |

`resources/list` always shows the guide, and shows the manifests and templates when Herald answers. `resources/templates/list` returns the two URI templates. The server does not support resource subscriptions.

## Tool index

There are 69 tools in five areas. Each tool is described once, in the page named in its row.

### Notifications

Show banners, speak, close banners and ask the user a question. All on [one page](notifications.md).

| Tool | What it does |
|---|---|
| [`herald_status`](notifications.md#herald_status) | Reports whether Herald is running and what it holds. |
| [`send_notification`](notifications.md#send_notification) | Shows a real banner. |
| [`send_test`](notifications.md#send_test) | Shows a saved template with the manifest's sample values. |
| [`speak`](notifications.md#speak) | Says a sentence aloud, with no banner. |
| [`dismiss`](notifications.md#dismiss) | Closes one banner, a stack or every banner of an app. |
| [`snooze`](notifications.md#snooze) | Hides a banner and brings it back later, or cancels a snooze. |
| [`list_stacks`](notifications.md#list_stacks) | Lists the stacks of banners on screen. |
| [`expand_stack`](notifications.md#expand_stack) | Opens or closes a stack. |
| [`get_replies`](notifications.md#get_replies) | Reads the replies waiting in an app's queue. |
| [`wait_for_reply`](notifications.md#wait_for_reply) | Waits for the user's answer to one notification. |

### Manifests and templates

Read the fields an app sends, design templates, check them, add buttons, and manage assets. All on [one page](templates.md).

| Tool | What it does |
|---|---|
| [`list_manifests`](templates.md#list_manifests) | Lists the registered manifests in short. |
| [`get_manifest`](templates.md#get_manifest) | Returns one app's fields, actions and assets. |
| [`put_manifest`](templates.md#put_manifest) | Creates or replaces a manifest. |
| [`delete_manifest`](templates.md#delete_manifest) | Deletes a manifest. Templates stay. |
| [`component_schema`](templates.md#component_schema) | Returns the template format: grid, components, bindings, actions. |
| [`list_templates`](templates.md#list_templates) | Lists saved templates and the built-in names. |
| [`get_template`](templates.md#get_template) | Returns one template, or a generated built-in. |
| [`put_template`](templates.md#put_template) | Validates and saves a template. |
| [`delete_template`](templates.md#delete_template) | Deletes a saved template. |
| [`duplicate_template`](templates.md#duplicate_template) | Copies a template, optionally for another app. |
| [`rename_template`](templates.md#rename_template) | Renames a template. |
| [`set_default_template`](templates.md#set_default_template) | Sets or clears the app's default template. |
| [`validate_template`](templates.md#validate_template) | Checks a template without saving it. |
| [`render_preview`](templates.md#render_preview) | Draws a template offscreen and returns a PNG. |
| [`designer_snapshot`](templates.md#designer_snapshot) | Draws the Designer window offscreen and returns a PNG. |
| [`list_shortcuts`](templates.md#list_shortcuts) | Lists the installed Apple Shortcuts. |
| [`add_action_rule`](templates.md#add_action_rule) | Adds a rule that changes or adds buttons. |
| [`export_template_bundle`](templates.md#export_template_bundle) | Packs a template and its Rive files into a bundle. |
| [`import_template_bundle`](templates.md#import_template_bundle) | Imports a template bundle. |
| [`list_assets`](templates.md#list_assets) | Lists an app's Rive files and images. |
| [`upload_asset`](templates.md#upload_asset) | Adds a Rive file or an image. |
| [`delete_asset`](templates.md#delete_asset) | Deletes a Rive file or an image. |
| [`list_symbols`](templates.md#list_symbols) | Searches the SF Symbol names. |
| [`rive_check`](templates.md#rive_check) | Loads a Rive component without a window and reports what it found. |

### Apps, settings and History

Register and configure apps, read and change settings, manage voice and the MCP install, and work with History. All on [one page](apps-and-settings.md).

| Tool | What it does |
|---|---|
| [`register_app`](apps-and-settings.md#register_app) | Registers an app or updates its name, icon and defaults. |
| [`list_apps`](apps-and-settings.md#list_apps) | Lists per-app settings, voice and approvals. |
| [`delete_app`](apps-and-settings.md#delete_app) | Removes an app with its History, templates and manifest. |
| [`update_app_settings`](apps-and-settings.md#update_app_settings) | Changes one app's sound, corner, display, stacking and voice. |
| [`get_settings`](apps-and-settings.md#get_settings) | Reads Herald's general and voice settings. |
| [`set_settings`](apps-and-settings.md#set_settings) | Changes general and voice settings. |
| [`get_quiet_hours`](apps-and-settings.md#get_quiet_hours) | Reads the quiet hours schedule and what is silenced now. |
| [`set_quiet_hours`](apps-and-settings.md#set_quiet_hours) | Changes the schedule or starts a silence. |
| [`list_approvals`](apps-and-settings.md#list_approvals) | Lists the commands, scripts and Shortcuts the user approved. |
| [`revoke_approval`](apps-and-settings.md#revoke_approval) | Withdraws one approval. |
| [`voice_status`](apps-and-settings.md#voice_status) | Reports the speech engine and the Kokoro voice install. |
| [`install_voice`](apps-and-settings.md#install_voice) | Starts, cancels or shortcuts the Kokoro voice install. |
| [`install_mcp`](apps-and-settings.md#install_mcp) | Reports or installs the MCP server in a client. |
| [`list_history`](apps-and-settings.md#list_history) | Lists recent delivered notifications. |
| [`history_search`](apps-and-settings.md#history_search) | Searches History. |
| [`reshow_notification`](apps-and-settings.md#reshow_notification) | Shows a past notification again as a banner. |
| [`delete_history`](apps-and-settings.md#delete_history) | Deletes one notification, or clears History. |
| [`export_history`](apps-and-settings.md#export_history) | Exports History as JSON. |

### Cloud relay

Set up and manage the cloud relay from this Mac. All on [one page](relay.md).

| Tool | What it does |
|---|---|
| [`relay_status`](relay.md#relay_status) | Reports the relay's setup state, keys and recent items. |
| [`relay_usage`](relay.md#relay_usage) | Reports today's relay traffic against the Cloudflare free plan. |
| [`relay_pair`](relay.md#relay_pair) | Pairs this Mac with the configured relay. |
| [`relay_unpair`](relay.md#relay_unpair) | Turns the relay off and revokes every key and connector. |
| [`create_agent_key`](relay.md#create_agent_key) | Creates a notify-only agent key. |
| [`revoke_agent_key`](relay.md#revoke_agent_key) | Revokes an agent key or a connector. |
| [`list_connectors`](relay.md#list_connectors) | Lists OAuth connectors and requests waiting for approval. |
| [`relay_events`](relay.md#relay_events) | Lists the live reply subscriptions. |
| [`relay_remove_event_subscription`](relay.md#relay_remove_event_subscription) | Ends one reply subscription. |
| [`relay_token_url`](relay.md#relay_token_url) | Returns the pre-filled Cloudflare token page. |
| [`relay_set_cloudflare_token`](relay.md#relay_set_cloudflare_token) | Stores the Cloudflare API token. |
| [`relay_deploy`](relay.md#relay_deploy) | Deploys or upgrades the relay in your Cloudflare account. |
| [`relay_settings`](relay.md#relay_settings) | Reads or changes the relay's Advanced settings. |
| [`relay_zones`](relay.md#relay_zones) | Lists the Cloudflare zones the token can see. |
| [`relay_delete`](relay.md#relay_delete) | Deletes the relay from Cloudflare. |
| [`relay_test`](relay.md#relay_test) | Tests the relay end to end. |
| [`relay_instructions`](relay.md#relay_instructions) | Returns the text for connecting a given agent. |

## Related

- [Connect an agent](../../MCP.md) to install the server in Claude Code, Codex or Claude Desktop and see a worked session.
- [Agent quick start](../../AGENT-QUICKSTART.md) for the shortest path to a first notification.
- [HTTP API](../api/README.md) for the calls behind each tool.
- [Parity with the app](../parity.md) for the list of what the app does and which tool does the same.
- [Cloud](../../CLOUD.md) for agents that run away from this Mac.
