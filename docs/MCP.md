# Herald MCP server (`herald-mcp`)

`herald-mcp` lets an AI agent (Claude Code, Codex, any MCP client) help you design how Herald's banners
look and what their buttons do. The agent can read an app's manifest (the fields and actions the app
sends), draft a grid template, **see** the result as an image, add buttons of its own (an Apple
Shortcut, a script, a shell command, a URL) and show a real test banner. It works through Herald's
loopback API, so Herald.app must be running.

- Transport: stdio, newline-delimited JSON-RPC 2.0, MCP protocol version 2025-06-18 (2025-03-26 and
  2024-11-05 are also accepted). Logs go to stderr; stdout carries protocol messages only.
- It never presses a banner button and never runs an action. Template-authored commands, scripts and
  shortcuts still ask you for confirmation inside Herald the first time they would run, and again if
  they change (see [ACTIONS.md](ACTIONS.md#security)).

## Install

### One click: Settings > MCP

Herald.app bundles the server and the CLI in `Herald.app/Contents/Helpers/` (`herald-mcp`, `herald`), signed
with the app. Open Settings > MCP: "One-click install for Claude Code, Codex and Claude Desktop. Any other MCP
client can use the generic config." Each client row shows Installed, Not installed or Client not found, with
an Install or Reinstall button, and reports the exact file or command it touched:

- **Claude Code** runs `claude mcp add --scope user herald -- <path>` (Reinstall runs `claude mcp remove herald` first).
- **Codex** adds or replaces `[mcp_servers.herald]` in `~/.codex/config.toml` (backup: `config.toml.bak`).
- **Claude Desktop** merges `mcpServers.herald` into `~/Library/Application Support/Claude/claude_desktop_config.json`, keeping other servers (backup: `.bak`).
- **Copy generic config** puts the JSON entry and the stdio command line on the pasteboard.

"Install `herald` command line tool" copies the bundled `herald` to `/usr/local/bin` (asks for an administrator
password only if that folder is not writable). **Test connection** runs the bundled server with `initialize` and
`tools/list` and shows the tool count. Restart the client after installing.

### From source

`make install-cli` builds and installs `herald` and `herald-mcp` to `/usr/local/bin` (or `~/bin` when
`/usr/local/bin` is not writable). `make install` does that and installs Herald.app.

### Claude Code

```sh
claude mcp add herald -- /usr/local/bin/herald-mcp
```

To make it available in every project use `claude mcp add --scope user herald -- /usr/local/bin/herald-mcp`
(`--scope project` writes `.mcp.json` for the repository). Check it with `claude mcp list`, or `/mcp` inside a session. The tools appear as
`mcp__herald__<tool>`.

### Codex

```sh
codex mcp add herald -- /usr/local/bin/herald-mcp
```

or in `~/.codex/config.toml`:

```toml
[mcp_servers.herald]
command = "/usr/local/bin/herald-mcp"
args = []
# env = { HERALD_PORT = "48617" }
```

### Any other client

Most clients take a JSON server entry:

```json
{ "mcpServers": { "herald": { "command": "/usr/local/bin/herald-mcp", "args": [] } } }
```

### Configuration

Normally there is nothing to configure: `herald-mcp` reads the token and port from
`~/Library/Application Support/Herald/` like the `herald` CLI does.

| Flag | Environment | Meaning |
|---|---|---|
| `--support-dir DIR` | `HERALD_SUPPORT_DIR` | Folder holding the `token` and `port` files. |
| `--port N` | `HERALD_PORT` | Port to use instead of the `port` file (a second Herald, e.g. a debug build). |
| `--token T` | `HERALD_TOKEN` | Token to use instead of the `token` file. Prefer the environment variable: a flag shows in `ps`. |
| `--preview-dir DIR` | `HERALD_PREVIEW_DIR` | Where `render_preview` saves PNGs (default `$TMPDIR/herald-previews`, newest 40 kept). |
| `--debug` | `HERALD_MCP_DEBUG=1` | Log each request to stderr. |

Try it by hand:

```sh
printf '%s\n' \
  '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"cli","version":"0"}}}' \
  '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"herald_status","arguments":{}}}' | herald-mcp
```

## Tools

Results are JSON text. A tool that cannot do what was asked returns a result with `isError: true` and an
explanation (never a protocol error), so the agent can read it and try again. Only an unknown tool name
is a JSON-RPC error (`-32602`).

| Tool | Arguments | What it does |
|---|---|---|
| `herald_status` | none | Is Herald running, its version and pid, the port and support folder in use, counts of apps, manifests, templates and Shortcuts, and the scripts folder with the files in it. Never fails: when Herald is down it says so and how to start it. |
| `list_manifests` | none | The registered manifests in short: each app's fields as `key:type` (`!` = required), action ids, assets, `defaultTemplate`. |
| `get_manifest` | `app`, `full?` | One manifest: fields with samples, issuer actions with ids, assets. The field keys are the `{tokens}` a template binds. Strings over 1200 characters (an embedded icon, a long sample) are shown as a marker such as `<data:image/png;base64,... 5022 characters omitted>`; `full: true` returns them whole. |
| `put_manifest` | `manifest` | Create or **replace** a manifest. Validated; errors carry the field path. Issuer actions are `url`, `callback`, `command` or `dismiss`. A marker that `get_manifest` wrote is swapped back for the stored value, and one that matches nothing stored is refused. |
| `list_templates` | `app?` | Saved templates in short (cells, tokens, rule count, whether it is the app's default) plus the four built-in names. |
| `get_template` | `app`, `name` | The full template JSON. `builtin.imageLeft`, `builtin.imageRight`, `builtin.hero` and `builtin.compact` are generated for the app, as starting points. |
| `put_template` | `template`, `app?`, `setAsDefault?` | Validate, then save. Errors name the JSON path and the **cell id** and nothing is saved until there are none. Warnings (an undeclared `{token}`, a mistyped key such as `colspan`) come back with the success. `setAsDefault` sets the manifest's `defaultTemplate`. Names starting with `builtin.` are reserved. |
| `delete_template` | `app`, `name` | Delete a saved template. |
| `validate_template` | `template` or `app` + `name` | Validate without saving. Also reports, for the manifest's sample data, which cells are empty, which rows and columns collapse, and the resulting action list. Works without Herald running (the manifest check is skipped). |
| `component_schema` | `component?`, `section?` | The template format: grid, every component type with properties, defaults and examples, bindings, empty-collapsing, action kinds and rules. `component: "text"` or `section: "actions"` returns just that part. Uses the running Herald's document, falling back to the one built into `herald-mcp`. |
| `render_preview` | `name` or `template`; `app?`, `source?`, `data?`, `appearance?`, `scale?` | Render with Herald's real banner renderer. Returns an **image content block** (PNG) and a text block with the saved file path and pixel size. `name` is a saved or built-in template; `template` is an unsaved draft (validated first). `source` is `sample` (the manifest's samples, default) or `last` (the app's latest notification in history); `data` replaces individual fields (omit a key to see the collapse). `appearance` is `light` or `dark`; `scale` 1 to 3. |
| `send_notification` | `app`, `title?`, any notification field, `fields?` | Deliver a real notification (a banner appears). Same payload as `POST /v1/notify`; manifest fields go in `fields` or at the top level. `actionIds` names manifest actions. Buttons with a shell `command` are refused unless `allowCommandButtons: true`, because an agent can send as any app id. `speak`, `audio` and `presentation` (`banner`, `voice`, `both`) add a spoken or recorded voice message. |
| `send_test` | `app`, `template?`, `data?`, `id?`, `includeIssuerActions?`, `allowCommandButtons?` | Show a saved template for real: the manifest's sample values plus the manifest's actions as the issuer's buttons (command actions only with `allowCommandButtons`). The id is `mcp-test-<template>`, so repeating it replaces the banner. |
| `list_shortcuts` | none | Names of the installed Apple Shortcuts (`shortcuts list`). |
| `add_action_rule` | `app`, `template`, `rule` | Append a rule to a saved template's `actionRules`: change an issuer action (`match` by id, label or `*`: `hide`, `relabel`, `style`, `position`) or add your own (`add`: `url`, `command`, `script`, `shortcut`, `dismiss`, `snooze`). Adding an id that an earlier rule already adds replaces that rule. Warns about a Shortcut that is not installed, a script file that is missing or not runnable, and a `match` that hits nothing. Returns the resulting button list. |
| `list_history` | `app?`, `limit?`, `full?` | Recent delivered notifications with their resolved field values. |
| `dismiss` | `app`, `id`, `group` or `all: true` | Close one banner, every banner of the app sent with a `group` (a stack), or every banner of the app. |
| `list_stacks` | `app?` | The stacks of banners on screen (notifications folded into one banner with a counter): level, app, group, count, whether it is open and its notifications newest first. |
| `speak` | `app`, `text`, `voice?`, `speed?`, `lang?`, `id?` | Say `text` aloud on the Mac with Herald's local voice, without a banner. The history keeps the text. Meant for "the long task finished" in a sentence or two. |

**Parity with the editor and Settings.** Anything a person does in the Designer, Quick send, History or Settings is also a tool
(see [reference/parity.md](reference/parity.md)): `get_settings` and `set_settings` (general, voice, tooltips, History cap),
`list_apps` and `update_app_settings` (per-app sound, corner, display, mute, stacking, voice, and the approvals the user gave),
`register_app`, `voice_status` and `install_voice`, `install_mcp`, `duplicate_template`, `rename_template`,
`set_default_template`, `export_template_bundle` and `import_template_bundle`, `list_assets`, `upload_asset` (Rive or an
image, by path or base64) and `delete_asset`, `list_symbols` (SF Symbol names and categories), `rive_check`,
`history_search`, `reshow_notification`, `delete_history`, `export_history`, `snooze`, `expand_stack`, `delete_manifest`,
`list_approvals` and `revoke_approval`, and `designer_snapshot` (the Designer drawn offscreen). Each is a thin wrapper
over one HTTP route; arguments and routes are in [reference/mcp-tools.md](reference/mcp-tools.md#parity-tools).
Grid, cell, component and action-rule edits are `put_template` (the template is one document), checked by the same
validation the Designer uses. **Not exposed on purpose:** granting an app permission to run commands or call a remote
host, and approving a template's commands: the agent is the program that approval guards against, so only the user
can give it, in Settings. An agent can read those approvals and withdraw them.

**Scripts.** A `script` action runs a file in `~/Library/Application Support/Herald/scripts/` (a plain file
name; `.sh`, `.zsh`, `.bash`, `.py`, `.rb`, `.pl`, `.scpt` run through their interpreter, anything else
must be executable) with the notification JSON on stdin. This server only talks to Herald's API, so an
agent that wants a script writes the file itself (Claude Code and Codex can) and then adds the rule;
`herald_status` lists what is in the folder and `add_action_rule` warns when the file is missing.

Arguments given as strings (`"5"`, `"true"`) and an object given as a JSON string are accepted.

### Resources

| URI | Content |
|---|---|
| `herald://manifests/<app>` | The app's manifest (JSON). |
| `herald://templates/<app>/<name>` | A template (JSON); `builtin.*` names work. Path parts are percent-encoded (`Bid%20won`). |
| `herald://docs/components` | A short Markdown guide to the template format. `component_schema` has every property. |

`resources/list` shows the guide always, and the manifests and templates when Herald answers;
`resources/templates/list` returns the two URI templates.

## Typical session

1. `herald_status`, then `get_manifest` for the app to design for.
2. `component_schema` (or `herald://docs/components`) once, to learn the grid and components.
3. Draft with `put_template`; fix what the errors say; `render_preview` in light and dark, with `data`
   that makes the subject very long or leaves a field out, to see how it wraps and collapses.
4. `list_shortcuts` and `add_action_rule` for buttons of your own; hide or relabel the issuer's.
5. `put_template` with `setAsDefault: true` (or later `put_manifest`) so the app uses it.
6. `send_test` to see the real banner on screen.

## Example: an agent designs the WebWatcher email banner

You ask: *"Make the email banner show the sender and subject with a count badge. Keep Mark as Read,
hide Archive, and add a Follow up button that runs my 'Create follow-up' shortcut."*

**1. Look at what the app sends.**

```text
agent> get_manifest {"app": "webwatcher.email"}
herald< fields: title:text (required), subject:text, sender:text, count:number (sample 2),
        receivedAt:date, url:url
        actions: markRead (callback), archive (callback, destructive)
```

**2. Draft a template.** The agent has read `component_schema` and writes a 3 x 4 grid. Two slips: the
badge sits on the title's columns, and `colspan` is mistyped.

```text
agent> put_template {"template": {"name": "email-accumulated", "app": "webwatcher.email", "layoutVersion": 2,
         "grid": {"rows": 3, "cols": 4, "rowSizes": ["auto","auto","auto"], "colSizes": [40,"fill","fill","auto"],
                  "gap": 6, "padding": 12, "width": 380},
         "cells": [
           {"id": "icon",    "row": 0, "col": 0, "rowSpan": 2, "component": {"type": "issuerIcon", "size": 32}},
           {"id": "title",   "row": 0, "col": 1, "colSpan": 2, "component": {"type": "text", "binding": "{title}", "style": "title", "maxLines": 2}},
           {"id": "count",   "row": 0, "col": 2, "align": "topTrailing", "component": {"type": "badge", "binding": "{count}"}},
           {"id": "subject", "row": 1, "col": 1, "colspan": 2, "component": {"type": "text", "binding": "{sender}: {subject}", "maxLines": 3}},
           {"id": "actions", "row": 2, "col": 0, "colSpan": 4, "component": {"type": "actions", "source": "merged", "layout": "wrap"}}]}}
herald< isError: true
        { "error": "Template not saved: 1 error(s). Fix them and call again.",
          "errors":   [{"cellId": "count", "path": "cells[2]", "severity": "error",
                        "message": "cell 'count' overlaps cell 'title' at row 0, col 2"}],
          "warnings": [{"cellId": "subject", "path": "cells[3].colspan", "severity": "warning",
                        "message": "unknown key 'colspan' is ignored (did you mean 'colSpan'?)"}],
          "saved": false }
```

**3. Fix both and save it as the app's default.**

```text
agent> put_template {"template": {... "count" now at "col": 3, "subject" has "colSpan": 2 ...}, "setAsDefault": true}
herald< { "saved": true, "app": "webwatcher.email", "name": "email-accumulated", "cells": 5,
          "isDefault": true, "warnings": [], "next": "render_preview to look at it; send_test to see the real banner." }
```

**4. Look at it, dark mode, with a long subject and a bigger count.**

```text
agent> render_preview {"app": "webwatcher.email", "name": "email-accumulated", "appearance": "dark",
                       "data": {"count": 14, "subject": "Re: Invoice #4021 is overdue, please confirm payment today"}}
herald< [image/png, 760 x 300]
        { "path": "/var/folders/.../T/herald-previews/preview-webwatcher.email-email-accumulated-dark-20261001-164852-E3BC.png",
          "width": 760, "height": 300, "appearance": "dark", "scale": 2, "data": "sample+overrides" }
```

The agent sees the image, notices the subject wraps to three lines and the badge is tight, and adjusts
`maxLines` and the badge column with another `put_template`.

**5. Two-way buttons.** Hide Archive, then add the Shortcut.

```text
agent> list_shortcuts {}
herald< { "count": 3, "shortcuts": ["Create follow-up", "Log to Notes", "Archive thread"] }

agent> add_action_rule {"app": "webwatcher.email", "template": "email-accumulated", "rule": {"match": "archive", "hide": true}}
herald< { "saved": true, "ruleIndex": 0,
          "resultingActions": [{"id": "markRead", "label": "Mark as Read", "kind": "callback", "origin": "issuer"}] }

agent> add_action_rule {"app": "webwatcher.email", "template": "email-accumulated",
         "rule": {"add": {"id": "followup", "label": "Follow up", "kind": "shortcut",
                          "shortcut": "Create follow-up", "input": "{title}\n{url}"}}}
herald< { "saved": true, "ruleIndex": 1, "warnings": [],
          "resultingActions": [{"id": "markRead", "label": "Mark as Read", "kind": "callback", "origin": "issuer"},
                               {"id": "followup", "label": "Follow up", "kind": "shortcut", "origin": "template"}] }
```

The issuer's Mark as Read still calls back WebWatcher; Follow up is yours and runs the Shortcut with the
title and URL as text input. Every action also receives the merged payload (the issuer's fields, its
metadata and the template's `extra`), so the Shortcut or script can use more than what you bound.

**6. Show it for real.**

```text
agent> send_test {"app": "webwatcher.email"}
herald< { "sent": true, "id": "mcp-test-email-accumulated", "template": "email-accumulated",
          "issuerActions": ["markRead", "archive"] }
```

A banner appears on your screen with the sample values. Pressing Mark as Read there calls WebWatcher's
callback with the test notification's id, so the agent tells you before you click.

## Agents as issuers

Installing a client from Settings > MCP (or `install_mcp`, `herald mcp install`) does two things. It writes the server entry
with `--agent <slug>`, and it registers the agent as an issuer, so the agent's notifications arrive under their own name,
icon and sound and you design their look like any other app (Settings > Apps lists it, the Designer opens on it).

| Client | App id | Symbol | Icon taken from |
|---|---|---|---|
| Claude Code | `agent.claude-code` | `terminal` | `Claude.app` (as Finder draws it), else the `claude` package's files |
| Codex | `agent.codex` | `sparkles` | `Codex.app`, else an icon file in the `@openai/codex` package |
| Claude Desktop | `agent.claude-desktop` | `message.circle` | `Claude.app` |
| Generic | `agent.<slug of the name you type>` | `bolt.circle` | the file you pick in the install row |

The icon is copied into Herald's own folder (`<support>/agent-icons/`) at install time and the app's `icon` points there, so
moving or updating the product does not break it. When no icon can be found on this Mac, the client's row shows **No icon
found** with a Choose button; nothing generated is put in its place.

What gets registered: the app (display name, icon, default sound), a **manifest** (`title`, `body`, `status`, `project`,
`session`, `task`, `tool`, `duration`, `link`, `needsInput`, with samples; actions `open`, `reply`, `dismiss`), and a default
template named `agent` built from `builtin.compact`: the agent's icon, title, time and close button, the body (two lines), a
**status badge** carrying the agent's symbol, the project, and the action row. Send `status` as `done`, `failed`, `waiting` or
`question`. Fields that are not sent collapse.

With `--agent` (or `HERALD_AGENT`) in its configuration, `herald-mcp` uses that app when a call leaves `app` out
(`send_notification`, `send_test`, `speak`, `dismiss`, `list_history`, `list_stacks`; an explicit `app` still wins), so an agent
can just call:

```text
agent> send_notification {"title": "Build finished", "body": "214 tests passed", "status": "done", "project": "herald"}
herald< {"app": "agent.claude-code", "id": "...", "sent": true}
```

Installing again is safe. The manifest is brought up to date, but your template (it is never overwritten once it exists),
the app's sound, name and icon, and a default template you chose all stay as you set them. The manifest format is in
[reference/manifests.md](reference/manifests.md#agents-as-issuers).

## Troubleshooting

| Symptom | Cause |
|---|---|
| `Herald is not running or not reachable` | Start Herald.app. The server looked for `token` and `port` in the support folder and for an answer on that port (`herald_status` shows both). |
| `Herald rejected the token` | Another Herald owns the port, or the token file changed. Fix `HERALD_SUPPORT_DIR` / `HERALD_PORT`, then restart the MCP server (the client restarts it). |
| `the running Herald predates Herald 1.1` | Update Herald. Manifests, grid templates and previews arrived in 1.1. |
| `render_preview` fails with a 400 | Herald rejected the template or data; the message names the cell. |
| The tools do not appear in the client | Run `herald-mcp --version`, then the by-hand check above; check the client's MCP log for stderr output. |

Related: [TEMPLATES.md](TEMPLATES.md) for the template format, [ACTIONS.md](ACTIONS.md) for the action
kinds and security, [API.md](API.md) for the HTTP endpoints behind the tools.
