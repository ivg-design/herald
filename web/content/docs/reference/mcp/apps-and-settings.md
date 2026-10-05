# Apps and settings tools

These MCP tools manage the things around the banners: the apps that send them, the approvals the user has given,
Herald's own settings, quiet hours, the voice and MCP installers, and History. They are for an agent that has to
change how Herald behaves for the user, clean up after itself, or look back at what was sent. Every tool here is a
thin wrapper over one route of the [HTTP API](../api/README.md); the [tool index](README.md) lists the rest of the server.

## Concepts

**An app** is whatever sends notifications, identified by an id such as `example.bidbot`. Herald creates the app the
first time it sends something, or you can create it on purpose with `register_app`. The record holds a display name, an
icon, the bundle id to bring to the front on a click, and the defaults that apply to its banners. The user sees and
edits the same record in **Settings > Apps**.

**Per-app settings** are what the user decides about one app: its sound, whether banners stay until dismissed, its
timeout, the screen corner and display, whether its banners are muted, how they stack, and whether its notifications are
spoken. `update_app_settings` changes them. They are the user's preferences, so say what you change.

**Approvals** are the permissions only the user can give. There are two kinds:

- An app can be allowed to run **command buttons**, and to call a **callback host** that is not on this Mac. These are
  shown by `list_apps` under `approvals`.
- A template's **commands, scripts and Shortcuts** are approved one template at a time, the first time its button is
  pressed. These are shown by `list_approvals`.

No tool can grant an approval. A tool can list approvals and withdraw them:

- `update_app_settings` accepts `revokeCommands: true` and `revokeCallbackHost: true`.
- `revoke_approval` withdraws a template's approval.
- A request that tries to grant one is refused.

After a withdrawal the user is asked again the next time the button is pressed.

**Settings are all or nothing.** `set_settings` checks every key and value first. If one is wrong, nothing is changed
and the error names the key. The same holds for `update_app_settings`.

**History** is the record of every notification Herald delivered, kept after its banner is gone. The history tools read
it, show an entry again, export it and delete from it. The format of the records is in
[History](../api/history.md).

![The Settings window on the Apps tab, with one app selected and its sound, timeout, corner and approvals showing](../../../web/public/shots/docs/settings-apps.png "The Apps tab is what list_apps reads and update_app_settings writes. Approvals are shown here and can only be granted here.")

## Tools

- [Apps](#apps)
  - [`register_app`](#register_app)
  - [`list_apps`](#list_apps)
  - [`delete_app`](#delete_app)
  - [`update_app_settings`](#update_app_settings)
- [Approvals](#approvals)
  - [`list_approvals`](#list_approvals)
  - [`revoke_approval`](#revoke_approval)
- [Settings](#settings)
  - [`get_settings`](#get_settings)
  - [`set_settings`](#set_settings)
- [Quiet hours](#quiet-hours)
  - [`get_quiet_hours`](#get_quiet_hours)
  - [`set_quiet_hours`](#set_quiet_hours)
- [Voice and MCP setup](#voice-and-mcp-setup)
  - [`voice_status`](#voice_status)
  - [`install_voice`](#install_voice)
  - [`install_mcp`](#install_mcp)
- [History](#history)
  - [`list_history`](#list_history)
  - [`history_search`](#history_search)
  - [`reshow_notification`](#reshow_notification)
  - [`delete_history`](#delete_history)
  - [`export_history`](#export_history)

## Apps

These tools create, read, change and remove the records of the apps that send to Herald.

### `register_app`

Creates an app or updates it. Call it to give an app a display name, an icon, a bundle id and defaults before it sends
anything, or to describe an app that does not register itself. Fields you leave out keep their value.

**Arguments**

| Name | Type | Required | Description |
|---|---|---|---|
| `app` | string | yes | The app id, for example `example.bidbot`. |
| `appName` | string | no | The name shown on banners and in Settings. |
| `icon` | string | no | A file path or a `data:image/png;base64,...` URI, at most 256 KB. |
| `bundleId` | string | no | The bundle id of the application to bring to the front when a banner is clicked. |
| `callbackURL` | string | no | The address that callback buttons post to. |
| `allowCommands` | boolean | no | Asks for permission to run command buttons. This is only a request: the user confirms it in **Settings > Apps**. |
| `defaults` | object | no | The app's default `sound`, `persistent`, `timeout` and `corner`. |

**Example call**

```json
{
  "app": "example.bidbot",
  "appName": "BidBot",
  "bundleId": "com.example.bidbot",
  "defaults": {"sound": "Glass", "persistent": true, "timeout": 0}
}
```

**Example result**

```json
{"ok": true}
```

**HTTP route**

[`POST /v1/register`](../api/apps.md#post-v1register)

**Side effects**

Creates or changes the app record. Shows nothing and never grants the command permission.

### `list_apps`

Lists the apps that have sent to Herald, with each app's per-app settings, voice settings and approvals. Call it to
find an app id, to see what the user has set before you change it, or to check whether an app may run commands.

**Arguments**

| Name | Type | Required | Description |
|---|---|---|---|
| `app` | string | no | Only this app. An unknown id is an error. Omit it for every app. |

**Example call**

```json
{"app": "example.bidbot"}
```

**Example result**

```json
{
  "apps": [
    {
      "app": "example.bidbot",
      "appName": "BidBot",
      "bundleId": "com.example.bidbot",
      "settings": {
        "sound": "Glass",
        "persistent": true,
        "timeout": 0,
        "display": "main",
        "muteBanners": false,
        "effectiveCorner": "topRight",
        "corner": null,
        "stacking": null,
        "opens": "com.example.bidbot"
      },
      "voice": {"speak": true, "voice": null, "speed": null, "urgentBreaksQuiet": false},
      "approvals": {
        "commandsRequested": false,
        "commandsConfirmed": false,
        "commandsAllowed": false,
        "callbackHostRegistered": null,
        "callbackHostApproved": null
      }
    }
  ],
  "schema": [
    {"key": "timeout", "group": "Defaults", "type": "number", "description": "Auto-dismiss after this many seconds; 0 never.", "min": 0, "max": 86400}
  ]
}
```

**Response fields**

| Field | Type | Description |
|---|---|---|
| `apps` | array | One object per app, with `app`, `appName`, `settings`, `voice` and `approvals`. `bundleId` and `callbackURL` appear when the app has them. |
| `settings` | object | The per-app settings. `corner` and `stacking` are `null` when the app follows the default, and `effectiveCorner` is the corner in use. `opens` appears when the app has a manifest. |
| `voice` | object | The app's voice settings. |
| `approvals` | object | What the user allowed: whether the app asked to run commands, whether the user confirmed it, and the callback host it registered and the one approved. |
| `schema` | array | One entry per key `update_app_settings` accepts, with its type, range and description. The example shows one entry. |
| `options` | object | The choices for sounds, displays and corners. Present only when you ask for every app. |

**HTTP route**

[`GET /v1/apps/settings`](../api/apps.md#get-v1appssettings)

**Side effects**

None. Read-only.

### `delete_app`

Removes an app for good: its record, all of its History, its templates, its manifest and the Rive copies, and the icon
files Herald made for it. Use it for test and demo apps registered by mistake. It does not revoke a cloud connector: use
[`revoke_agent_key`](relay.md#revoke_agent_key) for that.

**Arguments**

| Name | Type | Required | Description |
|---|---|---|---|
| `app` | string | yes | The app id, as `list_apps` shows it. It must not contain `/`. |

**Example call**

```json
{"app": "example.demo"}
```

**Example result**

```json
{"ok": true, "deleted": "example.demo"}
```

**HTTP route**

[`DELETE /v1/apps/{id}`](../api/apps.md#delete-v1appsid)

**Side effects**

Destructive and not undoable. Deletes the app's data and closes any banner it still has up. An unknown app is a `404`,
and Herald's own app, `herald`, cannot be removed (`409`). Ask the user first.

### `update_app_settings`

Changes one app's settings, the same ones the user sets in **Settings > Apps**. Call it when the user asks for a change
such as "mute this app" or "show its banners bottom left". It can also withdraw an approval, never grant one.

**Arguments**

| Name | Type | Required | Description |
|---|---|---|---|
| `app` | string | yes | The app id, as `list_apps` shows it. |
| `settings` | object | yes | The keys to change and their new values. The keys, types and ranges are in [`PUT /v1/apps/settings`](../api/apps.md#put-v1appssettings). |

**Example call**

```json
{
  "app": "example.bidbot",
  "settings": {"muteBanners": true, "corner": "bottomLeft"}
}
```

**Example result**

```json
{
  "ok": true,
  "applied": ["corner", "muteBanners"],
  "app": {
    "app": "example.bidbot",
    "appName": "BidBot",
    "settings": {
      "sound": "Glass",
      "persistent": true,
      "timeout": 0,
      "display": "main",
      "muteBanners": true,
      "effectiveCorner": "bottomLeft",
      "corner": "bottomLeft",
      "stacking": null
    },
    "voice": {"speak": true, "voice": null, "speed": null, "urgentBreaksQuiet": false},
    "approvals": {
      "commandsRequested": false,
      "commandsConfirmed": false,
      "commandsAllowed": false,
      "callbackHostRegistered": null,
      "callbackHostApproved": null
    }
  }
}
```

**HTTP route**

[`PUT /v1/apps/settings`](../api/apps.md#put-v1appssettings)

**Side effects**

Changes the user's per-app preferences. All or nothing: one bad key changes nothing. Send `revokeCommands: true` or
`revokeCallbackHost: true` to withdraw an approval. Any other value for those two keys is refused with `403`, because only
the user grants an approval, in **Settings > Apps**.

## Approvals

These tools show and withdraw the approvals the user gave to a template's commands, scripts and Shortcuts. There is no
tool that grants one.

### `list_approvals`

Lists the commands, scripts and Shortcuts the user has approved. Call it to see what a template is already allowed to
run, or to find the app and template names to pass to `revoke_approval`.

**Arguments**

No arguments.

**Example call**

```json
{}
```

**Example result**

```json
{
  "items": [
    {
      "app": "example.bidbot",
      "template": "Bid won",
      "commands": ["open -a Notes"],
      "approvedAt": "2026-10-01T09:30:00.000Z"
    }
  ],
  "note": "Approvals are granted by the user when a banner asks; here they can only be listed and revoked."
}
```

**HTTP route**

[`GET /v1/actions/approvals`](../api/apps.md#get-v1actionsapprovals)

**Side effects**

None. Read-only.

### `revoke_approval`

Withdraws the approval for one template. The user is asked again the next time one of its command, script or Shortcut
buttons is pressed. Call it when the user wants to take back a permission.

**Arguments**

| Name | Type | Required | Description |
|---|---|---|---|
| `app` | string | yes | The app id. |
| `template` | string | yes | The template name, exactly as `list_approvals` shows it. |

**Example call**

```json
{"app": "example.bidbot", "template": "Bid won"}
```

**Example result**

```json
{"ok": true}
```

**HTTP route**

[`DELETE /v1/actions/approvals`](../api/apps.md#delete-v1actionsapprovals)

**Side effects**

Destructive for the user's earlier decision. Changes state only; shows nothing. A pair with no approval is a `404`.

## Settings

These tools read and change Herald's general and voice settings, the ones in **Settings > General**, **Voice** and
**Tooltips**. Quiet hours and per-app settings have their own tools.

### `get_settings`

Reads every general and voice setting with its current value, a schema that says what each key accepts, and the lists of
valid choices. Call it before `set_settings` to see the keys and the current values.

**Arguments**

No arguments.

**Example call**

```json
{}
```

**Example result**

```json
{
  "settings": {
    "port": 48617,
    "launchAtLogin": true,
    "muteAllSounds": false,
    "stacking": "byApp",
    "historyCapPerApp": 500,
    "tooltipLevel": "nameAndDescription",
    "voiceEngine": "kokoro",
    "voiceDefault": "af_heart",
    "voiceSpeed": 1,
    "voiceLang": "en-us",
    "voiceSystem": null
  },
  "schema": [
    {"key": "muteAllSounds", "group": "General", "type": "boolean", "description": "Global mute for notification sounds (the bell menu's Mute)."}
  ],
  "options": {
    "sounds": ["none", "Glass", "Ping"],
    "displays": [{"id": "main", "name": "Main display"}],
    "corners": ["topRight", "topLeft", "bottomRight", "bottomLeft"],
    "stackingLevels": ["byApp", "byIssuer", "bySender", "never"],
    "voiceEngines": ["kokoro", "system", "off"],
    "voices": [{"id": "af_heart", "name": "Heart"}],
    "historyCapChoices": [100, 500, 1000]
  }
}
```

**Response fields**

| Field | Type | Description |
|---|---|---|
| `settings` | object | The current value of every key. `voiceSystem` is `null` when the macOS default voice is used. |
| `schema` | array | One entry per key with `key`, `group`, `type`, `description`, and a range (`min`, `max`), `values`, or `maxLength` where they apply. The example shows one entry. |
| `options` | object | The valid choices for sounds, displays, corners, stacking levels, voice engines, voices and History caps. The example shows a short list of each. |

**HTTP route**

[`GET /v1/settings`](../api/settings.md#get-v1settings)

**Side effects**

None. Read-only.

### `set_settings`

Changes one or more general or voice settings in a single call. Every value is checked first; one bad key changes
nothing. These are the user's own preferences, so say what you are changing. The keys, types and ranges are in
[`PUT /v1/settings`](../api/settings.md#put-v1settings).

**Arguments**

| Name | Type | Required | Description |
|---|---|---|---|
| `settings` | object | yes | Key and value pairs from the schema that `get_settings` returns. |

**Example call**

```json
{"settings": {"muteAllSounds": true, "stacking": "bySender", "voiceSpeed": 1.2}}
```

**Example result**

The reply is the same as `get_settings` with the keys that were changed listed in `applied`. `schema` and `options` are
shortened here.

```json
{
  "settings": {
    "port": 48617,
    "launchAtLogin": true,
    "muteAllSounds": true,
    "stacking": "bySender",
    "historyCapPerApp": 500,
    "tooltipLevel": "nameAndDescription",
    "voiceEngine": "kokoro",
    "voiceDefault": "af_heart",
    "voiceSpeed": 1.2,
    "voiceLang": "en-us",
    "voiceSystem": null
  },
  "schema": [
    {"key": "voiceSpeed", "group": "Voice", "type": "number", "description": "The default speech speed, 0.5 to 2.0.", "min": 0.5, "max": 2}
  ],
  "options": {"corners": ["topRight", "topLeft", "bottomRight", "bottomLeft"]},
  "applied": ["muteAllSounds", "stacking", "voiceSpeed"]
}
```

**HTTP route**

[`PUT /v1/settings`](../api/settings.md#put-v1settings)

**Side effects**

Changes the user's settings. All or nothing. Changing `port` restarts the local server a moment after the reply and the
reply carries a `note` saying so; this MCP server follows the new number from the port file. Changing `launchAtLogin`
registers or removes the login item.

## Quiet hours

Quiet hours are the times Herald stays silent: spoken text, sounds and optionally banners. A **window** repeats on chosen
days. An **ad hoc silence** starts now and runs until a time you give. The full rules, including what an `urgent`
notification can break through, are in [Quiet hours](../quiet-hours.md).

### `get_quiet_hours`

Reads the schedule, any ad hoc silence and what is silenced right now. Call it before you speak or send a sound, or
before you change the schedule. While speech is silenced, `speak` and `send_notification` with speech are held back and
logged in History as suppressed with the reason `quiet-hours`.

**Arguments**

No arguments.

**Example call**

```json
{}
```

**Example result**

```json
{
  "windows": [
    {
      "id": "w1",
      "days": [],
      "start": "22:30",
      "end": "07:30",
      "speech": true,
      "sounds": false,
      "banners": false,
      "speakSummary": false
    }
  ],
  "status": {
    "active": true,
    "speech": true,
    "sounds": false,
    "banners": false,
    "until": "2026-10-05T07:30:00.000Z",
    "source": "window"
  }
}
```

**Response fields**

| Field | Type | Description |
|---|---|---|
| `windows` | array | The scheduled windows. An empty `days` list means every day. An `end` that is not after `start` runs into the next morning. |
| `adHoc` | object | The current ad hoc silence, with `until`, `speech`, `sounds` and `banners`. Absent when there is none. |
| `status` | object | What is silenced now. `active` says whether anything is, `until` when the last silence ends, and `source` is `window`, `adhoc` or `both`. |

**HTTP route**

[`GET /v1/settings/quiet-hours`](../api/settings.md#get-v1settingsquiet-hours)

**Side effects**

None. Read-only.

### `set_quiet_hours`

Changes quiet hours. Tell the user before you silence them. Give one of:

- `windows` to replace the schedule.
- `until` or `minutes` to start an ad hoc silence.
- `resume` to end the current silence.

**Arguments**

| Name | Type | Required | Description |
|---|---|---|---|
| `windows` | array | no | The complete schedule. The fields of one window are in [Windows](../quiet-hours.md#windows). |
| `until` | string | no | Silence speech and sounds until this clock time, `HH:MM`, at its next occurrence. |
| `minutes` | number | no | Silence speech and sounds for this many minutes, from 1 to 10080. |
| `banners` | boolean | no | With `until` or `minutes`: silence banners too. Default `false`. |
| `resume` | boolean | no | `true` ends the current silence now. |

At least one of `windows`, `until`, `minutes` or `resume` is required.

**Example call**

```json
{"windows": [{"days": ["mon", "tue", "wed", "thu", "fri"], "start": "22:30", "end": "07:30", "speech": true, "sounds": true}]}
```

**Example result**

```json
{
  "windows": [
    {
      "id": "w2",
      "days": ["mon", "tue", "wed", "thu", "fri"],
      "start": "22:30",
      "end": "07:30",
      "speech": true,
      "sounds": true,
      "banners": false,
      "speakSummary": false
    }
  ],
  "status": {"active": false, "speech": false, "sounds": false, "banners": false}
}
```

**HTTP route**

[`PUT /v1/settings/quiet-hours`](../api/settings.md#put-v1settingsquiet-hours)

**Side effects**

Changes the user's schedule or starts or ends a silence. `windows` replaces every window, so read the schedule with
`get_quiet_hours` first if you want to keep the others. A notification with priority `urgent` breaks quiet hours only for
apps whose **Urgent can break quiet hours** setting the user turned on.

## Voice and MCP setup

These tools mirror **Settings > Voice** and **Settings > MCP**. They report what is installed and start the installers.
See [Voice](../voice.md) for what the voice engines do and the [MCP guide](../../MCP.md) for connecting a client.

### `voice_status`

Reports the speech engine, whether the optional Kokoro voice is installed, the install progress and the voices
available. Call it before you ask the user to install Kokoro, and to poll after `install_voice`.

**Arguments**

No arguments.

**Example call**

```json
{}
```

**Example result**

```json
{
  "engine": "kokoro",
  "kokoro": {
    "installed": false,
    "missing": ["kokoro-v1.0.onnx", "voices-v1.0.bin", "Python environment"],
    "folder": "/Users/you/Library/Application Support/Herald/tts",
    "busy": true,
    "phase": {"state": "downloading", "file": "kokoro-v1.0.onnx", "fraction": 0.42},
    "existingInstallationAvailable": false,
    "log": ["Downloading kokoro-v1.0.onnx"]
  },
  "voices": [{"id": "af_heart", "name": "Heart"}],
  "lastError": null
}
```

**Response fields**

| Field | Type | Description |
|---|---|---|
| `engine` | string | The speech engine in use: `kokoro`, `system` or `off`. |
| `kokoro` | object | Whether Kokoro is installed, the files still `missing`, the install `folder`, whether an install is `busy`, and its `phase`. |
| `kokoro.phase` | object | `state` is `idle`, `downloading` (with `file` and `fraction`), `settingUp` (with `step`), `done` or `failed` (with `error`). |
| `kokoro.existingInstallationAvailable` | boolean | `true` when a complete `~/.claude/tts` can be reused with `install_voice`. |
| `voices` | array | The voices that can be chosen, each with an `id` and a `name`. |
| `lastError` | string | The last voice error, or `null`. |

**HTTP route**

[`GET /v1/voice`](../api/setup.md#get-v1voice)

**Side effects**

None. Read-only.

### `install_voice`

Starts, cancels or shortcuts the Kokoro voice install. Call it only after the user agrees, because `install` downloads
about 340 MB and builds a Python environment. Poll `voice_status` for progress.

**Arguments**

| Name | Type | Required | Description |
|---|---|---|---|
| `action` | string | yes | `install` downloads and sets up Kokoro, `cancel` stops a running install, `useExisting` links a complete `~/.claude/tts` without downloading. |

**Example call**

```json
{"action": "install"}
```

**Example result**

```json
{"ok": true, "action": "install", "next": "Poll GET /v1/voice for progress."}
```

**HTTP route**

[`POST /v1/voice/install`](../api/setup.md#post-v1voiceinstall)

**Side effects**

Downloads files and creates a folder on this Mac. Ask the user first. Two calls fail by design:

- `install` when Kokoro is already installed is a `409`.
- `useExisting` with no complete `~/.claude/tts` is a `404`.

### `install_mcp`

Without `client`, reports the status of each MCP client and the path of the server. With `client`, adds `herald-mcp` to
that client's configuration, registers the agent as an app, and gives it a manifest, a default template and an icon.
Call it only when the user asked for it, because it edits another application's configuration.

**Arguments**

| Name | Type | Required | Description |
|---|---|---|---|
| `client` | string | no | `claudeCode`, `codex`, `claudeDesktop`, `generic` or `cli`. Omit it to read the status. |
| `reinstall` | boolean | no | Replaces an existing registration. Only `claudeCode` uses it. |
| `name` | string | no | The client's name. Required with `generic`: its notifications arrive as `agent.<slug of the name>`. |
| `icon` | string | no | An image file on this Mac to use as the agent's icon. Without it the product's own icon is used. |
| `opens` | string | no | What the agent's **Open** button brings to the front: a bundle id such as `com.apple.Terminal` or an application path such as `/Applications/iTerm.app`. |

What the install does depends on `client`:

- `cli` installs the `herald` command-line tool instead of an MCP entry.
- For the other clients, the server is added with `--agent <client>` and a backup of the configuration file is kept. `claudeCode` runs `claude mcp add`.
- Running it again keeps the user's edits.
- The agent's app id is `agent.claude-code`, `agent.codex`, `agent.claude-desktop` or `agent.<slug>`, as in [Agent identity](README.md#agent-identity).
- Without `opens`, the button opens Claude.app for Claude Desktop, and for the others the terminal or editor the server runs in, else Terminal.

**Example call**

```json
{"client": "claudeCode"}
```

**Example result**

```json
{
  "ok": true,
  "message": "Registered with Claude Code (user scope).",
  "touched": "claude mcp add --scope user herald -- /Applications/Herald.app/Contents/MacOS/herald-mcp --agent claude-code",
  "alreadyExists": false,
  "agent": {"app": "agent.claude-code", "name": "Claude Code", "server": "--agent claude-code"},
  "issuer": {
    "app": "agent.claude-code",
    "manifestWritten": true,
    "templateCreated": true,
    "template": "agent",
    "templateUpgraded": false,
    "opens": "com.apple.Terminal",
    "icon": "/Users/you/Library/Application Support/Herald/icons/agent.claude-code.png",
    "iconMissing": false
  }
}
```

Without `client` the reply is the status:

```json
{
  "server": "/Applications/Herald.app/Contents/MacOS/herald-mcp",
  "clients": [
    {"client": "claudeCode", "name": "Claude Code", "status": "Installed"},
    {"client": "codex", "name": "Codex", "status": "Not installed"},
    {"client": "claudeDesktop", "name": "Claude Desktop", "status": "Client not found"},
    {"client": "generic", "name": "Other", "status": "Not installed"}
  ],
  "genericConfig": "{\"mcpServers\": {\"herald\": {\"command\": \"/Applications/Herald.app/Contents/MacOS/herald-mcp\"}}}",
  "genericCommandLine": "/Applications/Herald.app/Contents/MacOS/herald-mcp",
  "cli": {"destination": "/usr/local/bin/herald", "installed": false}
}
```

**HTTP route**

- Without `client`: [`GET /v1/mcp`](../api/setup.md#get-v1mcp)
- With `client`: [`POST /v1/mcp/install`](../api/setup.md#post-v1mcpinstall)

**Side effects**

Edits another application's configuration file and registers an app in Herald. An install that already exists is a `409`
unless `reinstall` is `true`.

## History

History holds every notification Herald delivered. These tools list and search it, show an entry again as a banner,
export it and delete from it.

### `list_history`

Lists the most recent notifications, newest first, with the template used, the button the user pressed and the field
values the template bound. Call it to see what an app really sends. `render_preview` with `source: "last"` reads the same
record.

**Arguments**

| Name | Type | Required | Description |
|---|---|---|---|
| `app` | string | no | Only this app. Omit it for every app. When the server runs with `--agent`, it defaults to the agent's own app. |
| `limit` | integer | no | How many entries to return, from 1 to 100. Default `10`. |
| `full` | boolean | no | `true` returns the complete records instead of the summary. Long strings are shortened. |

**Example call**

```json
{"app": "example.bidbot", "limit": 2}
```

**Example result**

```json
{
  "count": 1,
  "items": [
    {
      "id": "bid-42",
      "app": "example.bidbot",
      "title": "Bid won: Walnut desk",
      "template": "Bid won",
      "deliveredAt": "2026-10-04T10:12:03.000Z",
      "dismissedAt": "2026-10-04T10:12:40.000Z",
      "actionUsed": "open",
      "fields": {"item": "Walnut desk", "price": 240}
    }
  ]
}
```

**Response fields**

| Field | Type | Description |
|---|---|---|
| `count` | number | How many entries are in `items`. |
| `items[].id` | string | The notification id. |
| `items[].app` | string | The app that sent it. |
| `items[].title` | string | The title it was shown with. `subtitle` and `template` appear when set. |
| `items[].deliveredAt` | string | When it was delivered. `dismissedAt` appears once the banner is gone. |
| `items[].actionUsed` | string | The label of the button used, `open` for a click on the banner, or `timeout` for an automatic close. Absent while the banner is open. |
| `items[].fields` | object | The field values the template bound, resolved at delivery. Long strings are shortened. |

**HTTP route**

[`GET /v1/history`](../api/history.md#get-v1history)

**Side effects**

None. Read-only.

### `history_search`

Searches History the way its search box does: every word must appear, in any case and with accents ignored, in the title,
subtitle, body, app id or app name. Results are newest first. Call it to find a notification when you do not know its id.

**Arguments**

| Name | Type | Required | Description |
|---|---|---|---|
| `q` | string | yes | The words to find. |
| `app` | string | no | Only this app. Omit it to search every app. |
| `limit` | integer | no | At most this many results, from 0 to 1000. Default `50`. |

**Example call**

```json
{"q": "walnut desk", "limit": 5}
```

**Example result**

```json
{
  "query": "walnut desk",
  "count": 1,
  "items": [
    {
      "id": "bid-42",
      "app": "example.bidbot",
      "notification": {"app": "example.bidbot", "id": "bid-42", "title": "Bid won: Walnut desk", "template": "Bid won"},
      "deliveredAt": "2026-10-04T10:12:03.000Z",
      "dismissedAt": "2026-10-04T10:12:40.000Z",
      "actionUsed": "open"
    }
  ]
}
```

Each item is the full History record, trimmed here. Its fields are described in [History](../api/history.md).

**HTTP route**

[`GET /v1/history/search`](../api/history.md#get-v1historysearch)

**Side effects**

None. Read-only.

### `reshow_notification`

Shows a notification from History again as a new banner, with its sound and a fresh delivery time. It is the **Re-show
as Banner** action of the History window. Call it when the user asks to see something again.

**Arguments**

| Name | Type | Required | Description |
|---|---|---|---|
| `app` | string | yes | The app id. |
| `id` | string | yes | The notification id, from `list_history` or `history_search`. |

**Example call**

```json
{"app": "example.bidbot", "id": "bid-42"}
```

**Example result**

```json
{"ok": true, "id": "bid-42"}
```

`id` is the id of the new banner's notification.

**HTTP route**

[`POST /v1/history/reshow`](../api/history.md#post-v1historyreshow)

**Side effects**

Shows a banner on the user's screen, plays its sound, and speaks it if the notification asked for speech. An id that is
not in History is a `404`.

### `delete_history`

Deletes one notification from History and closes its banner, clears one app's whole History, or clears everything. The arguments choose the scope:

- `app` and `id` delete one entry.
- `app` and `all: true` clear one app.
- `all: true` alone clears every app.

**Arguments**

| Name | Type | Required | Description |
|---|---|---|---|
| `app` | string | no | The app id. Required with `id`. |
| `id` | string | no | The notification id. Omit it when you use `all`. |
| `all` | boolean | no | `true` clears every notification of `app`, or of every app when `app` is omitted. |

**Example call**

```json
{"app": "example.bidbot", "id": "bid-42"}
```

**Example result**

```json
{"ok": true}
```

**HTTP route**

- With `app` and `id`: [`DELETE /v1/history/item`](../api/history.md#delete-v1historyitem)
- With `all`: [`DELETE /v1/history`](../api/history.md#delete-v1history)

**Side effects**

Destructive and not undoable. Removes the records and closes the banner of a single entry. Without `id` and without
`all: true` the tool refuses to run. Ask the user first.

### `export_history`

Returns History as JSON, newest first, for one app or all. With `path`, Herald writes the file itself and returns only
the count, which keeps a large History out of the conversation.

**Arguments**

| Name | Type | Required | Description |
|---|---|---|---|
| `app` | string | no | Only this app. Omit it for every app. |
| `path` | string | no | A file on this Mac, ending in `.json`, in a folder that exists. Herald writes the records there. |

**Example call**

```json
{"app": "example.bidbot", "path": "~/Desktop/bidbot-history.json"}
```

**Example result**

```json
{"count": 218, "path": "/Users/you/Desktop/bidbot-history.json", "bytes": 164210}
```

Without `path` the result has `count` and an `items` array that holds every record.

**HTTP route**

[`GET /v1/history/export`](../api/history.md#get-v1historyexport)

**Side effects**

Writes the file when `path` is given. Otherwise read-only. A `path` is a `400` in two cases:

- It does not end in `.json`.
- Its folder does not exist.

## Related

- [MCP tool index and conventions](README.md): how the server reports errors and how an agent gets its own app id.
- [MCP guide](../../MCP.md): install the server, connect a client and follow a worked session.
- [Cloud relay tools](relay.md): the tools for the cloud relay and its agent keys.
- [Quiet hours](../quiet-hours.md): what the windows and the ad hoc silence do.
- [Voice](../voice.md): the speech engines and the Kokoro install.
- [Apps API](../api/apps.md), [Settings API](../api/settings.md) and [History API](../api/history.md): the routes behind these tools.
