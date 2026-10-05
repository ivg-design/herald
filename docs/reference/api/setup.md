# Voice and MCP setup API

These endpoints do what two Settings tabs do: install the Kokoro voice, and install Herald's MCP server into an
AI client such as Claude Code. Use them when an installer script or an agent sets Herald up for the user. The
examples use the `$HERALD` and `$TOKEN` variables from [Connect](README.md#connect).

## What gets installed

**Kokoro** is the natural-sounding speech engine. It is an optional download of about 340 MB that runs entirely
on this Mac. Without it, Herald speaks with the macOS system voice. Installing takes a while, so the install
endpoint only starts the work and you follow progress by reading the state.

**The MCP server**, `herald-mcp`, is a small program inside the Herald app that lets an AI agent send
notifications and design templates. Installing it means adding an entry to the client's own configuration
file. Herald keeps a backup of the file it edits. Installing also registers the agent as an app in Herald, so
its notifications arrive with the agent's name and icon.

![The MCP tab of Herald's Settings, listing the clients with an Install button for each](../../../web/public/shots/docs/settings-mcp.png "Settings > MCP. Each Install button does what POST /v1/mcp/install does for that client.")

## Endpoints

| Endpoint | Purpose |
|---|---|
| [`GET /v1/voice`](#get-v1voice) | Read the speech engine, the Kokoro install state and the voices. |
| [`POST /v1/voice/install`](#post-v1voiceinstall) | Start, cancel or link a Kokoro install. |
| [`GET /v1/mcp`](#get-v1mcp) | See which clients have the MCP server installed. |
| [`POST /v1/mcp/install`](#post-v1mcpinstall) | Install the MCP server into a client, or install the CLI. |

## Voice

### `GET /v1/voice`

Returns the current speech engine, whether Kokoro is installed, the progress of a running install, and the
voices you can use. Poll it after starting an install.

**Request**

No parameters.

**Example request**

```sh
curl -s "$HERALD/v1/voice" -H "Authorization: Bearer $TOKEN"
```

**Example response**

```json
{
  "engine": "kokoro",
  "kokoro": {
    "installed": true,
    "missing": [],
    "folder": "/Users/you/Library/Application Support/Herald/tts",
    "busy": false,
    "phase": {"state": "idle"},
    "existingInstallationAvailable": false,
    "log": []
  },
  "voices": [
    {"id": "af_heart", "name": "af_heart"},
    {"id": "af_bella", "name": "af_bella"},
    {"id": "bm_george", "name": "bm_george"}
  ],
  "lastError": null
}
```

**Response fields**

| Field | Type | Description |
|---|---|---|
| `engine` | string | The engine in use: `kokoro`, `system` or `off`. |
| `kokoro.installed` | boolean | `true` when every Kokoro file is in place. |
| `kokoro.missing` | array | The files that are not there yet. |
| `kokoro.folder` | string | Where Kokoro is, or will be, installed. |
| `kokoro.busy` | boolean | `true` while an install is running. |
| `kokoro.phase` | object | The install step. See the next table. |
| `kokoro.existingInstallationAvailable` | boolean | `true` when a complete Kokoro already exists in `~/.claude/tts` and can be linked. |
| `kokoro.log` | array | The last eight lines of the install log. |
| `voices` | array | The voices of the current engine, each with an `id` and a `name`. |
| `lastError` | string or null | The most recent speech error. |

The `phase` object always has a `state`:

| State | Extra fields | Meaning |
|---|---|---|
| `idle` | None. | No install is running. |
| `downloading` | `file`, `fraction` | A file is downloading. `fraction` runs from 0 to 1. |
| `settingUp` | `step` | The download is done and the Python environment is being prepared. |
| `done` | None. | The install finished. |
| `failed` | `error` | The install stopped. `error` says why. |

### `POST /v1/voice/install`

Starts the Kokoro download, cancels one that is running, or links an installation that already exists on this
Mac. The reply comes back at once. Follow the progress with [`GET /v1/voice`](#get-v1voice).

**Request**

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `action` | body | string | yes | `install`, `cancel` or `useExisting`. |

**Example request**

```sh
curl -s -X POST "$HERALD/v1/voice/install" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"action": "install"}'
```

**Example response**

```json
{"ok": true, "action": "install", "next": "Poll GET /v1/voice for progress."}
```

**Errors**

| Status | When |
|---|---|
| `400` | `action` is missing or not one of the three values. |
| `404` | `action` is `useExisting` and there is no complete installation in `~/.claude/tts`. |
| `409` | `action` is `install` and Kokoro is already installed. |

**Notes**

- `install` downloads about 340 MB. This is the only time Herald's speech uses the network.
- `useExisting` links a complete Kokoro in `~/.claude/tts` so that nothing is downloaded twice.
- Installing Kokoro does not switch the engine. Set `voiceEngine` to `kokoro` with
  [`PUT /v1/settings`](settings.md#put-v1settings).

## MCP server

### `GET /v1/mcp`

Returns where the MCP server is, whether each known client has it installed, and the configuration to paste
into a client Herald does not know.

**Request**

No parameters.

**Example request**

```sh
curl -s "$HERALD/v1/mcp" -H "Authorization: Bearer $TOKEN"
```

**Example response**

```json
{
  "server": "/Applications/Herald.app/Contents/Helpers/herald-mcp",
  "clients": [
    {"client": "claudeCode", "name": "Claude Code", "status": "Installed"},
    {"client": "codex", "name": "Codex", "status": "Installed"},
    {"client": "claudeDesktop", "name": "Claude Desktop", "status": "Not installed"},
    {"client": "generic", "name": "Generic", "status": "Not installed"}
  ],
  "genericCommandLine": "claude mcp add --scope user herald -- /Applications/Herald.app/Contents/Helpers/herald-mcp",
  "genericConfig": "{\"mcpServers\": {\"herald\": {\"command\": \"/Applications/Herald.app/Contents/Helpers/herald-mcp\", \"args\": []}}}",
  "cli": {"destination": "/usr/local/bin/herald", "installed": true}
}
```

**Response fields**

| Field | Type | Description |
|---|---|---|
| `server` | string | The path of the `herald-mcp` program. |
| `clients[].client` | string | The client's key, used with [`POST /v1/mcp/install`](#post-v1mcpinstall). |
| `clients[].name` | string | The client's display name. |
| `clients[].status` | string | `Installed`, `Not installed` or `Client not found`. |
| `genericCommandLine` | string | A command that adds the server to a client by hand. |
| `genericConfig` | string | A JSON configuration block, as text, for a client that reads `mcpServers`. |
| `cli.destination` | string | Where the `herald` command-line tool is installed. |
| `cli.installed` | boolean | `true` when the tool is there. |

### `POST /v1/mcp/install`

Installs the MCP server into one client, or installs the `herald` command-line tool. It does what the
**Install** button for that client does in **Settings > MCP**.

**Request**

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `client` | body | string | yes | `claudeCode`, `codex`, `claudeDesktop`, `generic` or `cli`. |
| `reinstall` | body | boolean | no | `true` replaces an existing entry. Default `false`. |
| `name` | body | string | no | The agent's name. Required for `generic`. |
| `icon` | body | string | no | A file to use as the agent's icon. Default: the client product's icon. |
| `opens` | body | string | no | What the agent's **Open** button brings forward: a bundle id or an application path. |
| `detectedHost` | body | string | no | The terminal or editor the request came from, used when `opens` is not given. |

**Example request**

```sh
curl -s -X POST "$HERALD/v1/mcp/install" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"client": "claudeCode", "opens": "com.apple.Terminal"}'
```

**Example response**

```json
{
  "ok": true,
  "message": "Installed in Claude Code.",
  "touched": "/Users/you/.claude.json",
  "alreadyExists": false,
  "agent": {"app": "agent.claude-code", "name": "Claude Code", "server": "--agent claude-code"},
  "issuer": {
    "app": "agent.claude-code",
    "manifestWritten": true,
    "templateCreated": true,
    "template": "agent",
    "templateUpgraded": false,
    "opens": {"bundleId": "com.apple.Terminal"},
    "icon": "/Users/you/Library/Application Support/Herald/agent-icons/claude-code.png",
    "iconMissing": false
  }
}
```

**Response fields**

| Field | Type | Description |
|---|---|---|
| `message` | string | What happened, in a sentence. |
| `touched` | string | The configuration file that was edited. |
| `alreadyExists` | boolean | `true` when the client already had an entry. |
| `agent.app` | string | The app id the agent sends under, such as `agent.claude-code`. |
| `agent.server` | string | The argument written into the client's server entry. |
| `issuer` | object | What was registered for the agent: its manifest, its `agent` template, its icon and what **Open** opens. |
| `config` | string | For `generic`: the configuration block to paste into the client. |
| `registrationError` | string | Present when the client was configured but registering the agent failed. |

**Errors**

| Status | When |
|---|---|
| `400` | `client` is missing or unknown, or `name` is missing for `generic`. |
| `400` | `icon` names a file that does not exist, or `opens` is not a bundle id or an application path. |
| `400` | The install failed. The message says why. |
| `409` | The client already has an entry and `reinstall` is not `true`. |

**Notes**

- The agent's app id is `agent.claude-code`, `agent.codex` or `agent.claude-desktop`. For `generic` it is
  `agent.` followed by a slug of `name`.
- Installing again keeps what the user changed since: the agent's template, its icon and its settings.
- `cli` installs the `herald` tool to `/usr/local/bin/herald`. Its reply has only `ok`, `message` and
  `touched`.
- A backup of the edited configuration file is kept beside it with the extension `.bak`.

## Related

- [Make Herald speak](../../VOICE.md): choose an engine and send a spoken notification.
- [Connect an agent with MCP](../../MCP.md): the guided version of the MCP install.
- [MCP reference](../mcp/README.md): how agents become apps, and every tool.
- [herald CLI](../cli.md): the command-line tool this API can install.
