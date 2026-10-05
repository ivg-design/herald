# Apps API

These endpoints manage the apps that send notifications: register one, list them, remove one, and read or change
the settings Herald keeps per app. Use them when your integration wants its own name, icon and defaults, or when
you build a tool that manages Herald. The examples use the `$HERALD` and `$TOKEN` variables from
[Connect](README.md#connect).

## What an app is

An **app** is a sender of notifications. It is identified by an id that you choose, such as `example.bidbot`.
Everything Herald stores is grouped by that id: the app's History, its templates, its manifest, its assets and
its settings.

Registering an app is optional. Herald registers an unknown id, with a generic icon, the first time that id
sends a notification. Register when you want to control how the app appears and behaves:

- a display name and an icon, shown on banners, in History and in **Settings > Apps**;
- default sound, corner, timeout and persistence for its banners;
- a callback URL for buttons that call your server;
- a request to run shell commands from buttons, which the user must approve.

![The Apps tab of Herald's Settings with one app selected](../../../web/public/shots/docs/settings-apps.png "Settings > Apps lists every registered app. The page for the selected app shows the same settings these endpoints read and write.")

### Where an app's name and icon come from

Every part of Herald reads an app's name and icon from the same place, so two windows never disagree.

The **name** is the registered `appName`, or the app id when no name was registered. A cloud connector is named
with the name its client chose when it signed in.

The **icon** is the first of these that exists:

1. The icon the user chose in **Settings > Apps > Change icon...**.
2. The `icon` the app registered.
3. The icon of the application named by the registered `bundleId`.
4. An automatic icon: the real icon of ChatGPT, Claude or Codex when the app's name mentions that product and
   it is installed on this Mac, otherwise a symbol tile (a cloud for a connector, a key for an agent key, a
   terminal for a local agent).
5. A bell tile.

### Approvals can be withdrawn, never granted

Two things an app can ask for are dangerous enough to need the user's consent: running shell commands from
buttons, and calling back to a server that is not on this Mac. The user grants both in Herald's own windows.
The API can read these approvals and withdraw them. No endpoint grants one, because the program holding the
token is exactly what the approval protects against.

## Endpoints

| Endpoint | Purpose |
|---|---|
| [`POST /v1/register`](#post-v1register) | Register an app or update its registration. |
| [`GET /v1/apps`](#get-v1apps) | List the registered apps. |
| [`DELETE /v1/apps/{id}`](#delete-v1appsid) | Remove an app and everything stored for it. |
| [`GET /v1/apps/settings`](#get-v1appssettings) | Read per-app settings and approvals. |
| [`PUT /v1/apps/settings`](#put-v1appssettings) | Change per-app settings, or withdraw an approval. |
| [`GET /v1/actions/approvals`](#get-v1actionsapprovals) | List the commands approved for templates. |
| [`DELETE /v1/actions/approvals`](#delete-v1actionsapprovals) | Withdraw a template's command approval. |

### `POST /v1/register`

Registers an app, or replaces the registration of an app that already exists. Call it once when your
integration starts; calling it again with the same values changes nothing.

**Request**

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `app` | body | string | yes | The app id, at most 128 bytes. |
| `appName` | body | string | no | The name shown to the user. Default: the app id. |
| `icon` | body | string | no | A file path, or a `data:image/png;base64,` URI of at most 256 KB. |
| `bundleId` | body | string | no | The bundle identifier of your Mac app, used for its icon and by **Open** actions. |
| `callbackURL` | body | string | no | Where callback buttons post. See [Callback request](replies.md#callback-request). |
| `allowCommands` | body | boolean | no | `true` asks for permission to run command buttons. The user must confirm it. |
| `defaults` | body | object | no | Default behaviour for this app's banners. See the next table. |

The `defaults` object:

| Field | Type | Required | Description |
|---|---|---|---|
| `sound` | string | no | `none`, a system sound name such as `Glass`, or a sound file path. |
| `persistent` | boolean | no | `true` keeps banners until they are dismissed. |
| `timeout` | number | no | Seconds until a banner closes itself. `0` means never. |
| `corner` | string | no | `topRight`, `topLeft`, `bottomRight` or `bottomLeft`. |

**Example request**

```sh
curl -s -X POST "$HERALD/v1/register" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{
    "app": "example.bidbot",
    "appName": "BidBot",
    "bundleId": "com.example.bidbot",
    "callbackURL": "http://127.0.0.1:5123/herald",
    "defaults": {"sound": "Glass", "persistent": true, "corner": "topRight"}
  }'
```

**Example response**

```json
{"ok": true}
```

**Errors**

| Status | When |
|---|---|
| `400` | `app` is missing or empty. |
| `413` | `app` is over 128 bytes, or `icon` is over 256 KB. |
| `429` | The app id is new and 200 apps are already registered. |

**Notes**

- A registered name and icon win over the name and icon in the app's [manifest](../manifests.md).
- `allowCommands` is only a request. Command buttons do not run until the user confirms in
  **Settings > Apps**, or chooses **Always allow** when a banner asks.
- A `callbackURL` on another machine needs the user's approval before Herald posts to it. A loopback address
  such as `127.0.0.1` does not.
- A registered `bundleId` does not make a click on a banner open your app. A template with
  `onClick: "openApp"` does. See [How banners behave](../banners.md).

### `GET /v1/apps`

Lists every registered app with the values it registered. Use it to find app ids, or to check what an app
registered.

**Request**

No parameters.

**Example request**

```sh
curl -s "$HERALD/v1/apps" -H "Authorization: Bearer $TOKEN"
```

**Example response**

```json
{
  "apps": [
    {
      "app": "example.bidbot",
      "appName": "BidBot",
      "bundleId": "com.example.bidbot",
      "callbackURL": "http://127.0.0.1:5123/herald",
      "defaults": {"sound": "Glass", "persistent": true, "corner": "topRight"}
    },
    {
      "app": "agent.claude-code",
      "appName": "Claude Code",
      "defaults": {"sound": "Glass"},
      "icon": "/Users/you/Library/Application Support/Herald/agent-icons/claude-code.png"
    }
  ]
}
```

**Response fields**

| Field | Type | Description |
|---|---|---|
| `apps` | array | One object per app, with the fields of [`POST /v1/register`](#post-v1register). |

**Notes**

- Fields an app never set are absent from its object.
- This list holds what each app registered. What the user changed afterwards is in
  [`GET /v1/apps/settings`](#get-v1appssettings).

### `DELETE /v1/apps/{id}`

Removes an app for good: its registration, all of its History, its templates, its manifest, its stored assets
and the icon files Herald made for it. Banners of the app that are on screen are closed.

> [!WARNING]
> This cannot be undone. The app's History and templates are deleted from disk.

**Request**

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `id` | path | string | yes | The app id, percent-encoded if it contains special characters. |

**Example request**

```sh
curl -s -X DELETE "$HERALD/v1/apps/example.bidbot" -H "Authorization: Bearer $TOKEN"
```

**Example response**

```json
{"ok": true, "deleted": "example.bidbot"}
```

**Errors**

| Status | When |
|---|---|
| `400` | The id is empty or contains a `/`. |
| `404` | No app with this id exists. |
| `409` | The id is `herald`, Herald's own app, which cannot be removed. |

**Notes**

- An app that sends again after it was removed is registered again as a new app.
- For a cloud connector, removing the app does not revoke the connector. Revoke it with
  [`DELETE /v1/relay/keys/{id}`](relay.md#delete-v1relaykeysid), or use **Remove and Revoke** in
  **Settings > Apps**, so that it does not come back with its next notification.

### `GET /v1/apps/settings`

Returns the settings Herald keeps for each app, the app's voice preferences, and the state of its approvals.
It also returns the schema of the keys that [`PUT /v1/apps/settings`](#put-v1appssettings) accepts.

**Request**

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `app` | query | string | no | Return only this app. Default: every app. |

**Example request**

```sh
curl -s "$HERALD/v1/apps/settings?app=example.bidbot" -H "Authorization: Bearer $TOKEN"
```

**Example response**

```json
{
  "apps": [
    {
      "app": "example.bidbot",
      "appName": "BidBot",
      "bundleId": "com.example.bidbot",
      "callbackURL": "http://127.0.0.1:5123/herald",
      "settings": {
        "sound": "Glass",
        "persistent": true,
        "timeout": 0,
        "corner": null,
        "effectiveCorner": "topRight",
        "display": "main",
        "muteBanners": false,
        "stacking": null,
        "opens": null
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
    {
      "key": "sound",
      "group": "Defaults",
      "type": "string",
      "maxLength": 1024,
      "description": "The app's default sound: none, a system sound name such as Glass, or a sound file path."
    }
  ]
}
```

**Response fields**

| Field | Type | Description |
|---|---|---|
| `apps` | array | One object per app. |
| `apps[].settings` | object | The current value of each key in the [settings table](#per-app-setting-keys). |
| `apps[].settings.effectiveCorner` | string | The corner in use: the user's `corner`, else the registered one, else `topRight`. Read-only. |
| `apps[].voice` | object | The app's voice preferences: `speak`, `voice`, `speed`, `urgentBreaksQuiet`. |
| `apps[].approvals` | object | The approval state. See the table below. |
| `schema` | array | One entry per accepted key: `key`, `group`, `type`, `description` and its limits. |
| `options` | object | The available sounds, displays, corners and voices. Present when `app` is omitted. |

The `approvals` object:

| Field | Type | Description |
|---|---|---|
| `commandsRequested` | boolean | The app registered with `allowCommands: true`. |
| `commandsConfirmed` | boolean | The user confirmed that request. |
| `commandsAllowed` | boolean | Command buttons run for this app: requested and confirmed. |
| `callbackHostRegistered` | string or null | The host of the registered `callbackURL` when it is not on this Mac. |
| `callbackHostApproved` | string or null | The remote host the user approved for callbacks. |

**Errors**

| Status | When |
|---|---|
| `404` | `app` names an app that is not registered. |

### `PUT /v1/apps/settings`

Changes one or more settings of one app. Send the app id and only the keys you want to change.

**Request**

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `app` | body | string | yes | The app to change. |
| any setting key | body | varies | no | A key from the table below with its new value. |

#### Per-app setting keys

| Key | Type | Description |
|---|---|---|
| `sound` | string | The default sound: `none`, a system sound name, or a sound file path. |
| `persistent` | boolean | `true` keeps banners until dismissed. `false` lets them leave after the timeout. |
| `timeout` | number | Seconds until a banner closes itself, from 0 to 86400. `0` means never. |
| `corner` | string or null | The user's corner for this app. `null` follows the corner the app registered. |
| `display` | string | `main`, or a display id from `options.displays`. |
| `muteBanners` | boolean | `true` shows no banners. Notifications go to History, unread. |
| `stacking` | string or null | This app's [stacking level](../stacking.md). `null` follows the global setting. |
| `opens` | string | What the app's **Open** button brings forward: a bundle id or an application path. |
| `speak` | boolean | `false` stops this app's notifications from being spoken. |
| `voice` | string or null | The app's voice. `null` uses the default voice. |
| `urgentBreaksQuiet` | boolean | `true` lets this app's `urgent` notifications speak during quiet hours. |
| `revokeCommands` | boolean | Send `true` to withdraw the approval to run command buttons. |
| `revokeCallbackHost` | boolean | Send `true` to withdraw the approval of the remote callback host. |

**Example request**

```sh
curl -s -X PUT "$HERALD/v1/apps/settings" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"app": "example.bidbot", "corner": "bottomRight", "timeout": 20, "persistent": false}'
```

**Example response**

```json
{
  "ok": true,
  "applied": ["corner", "timeout", "persistent"],
  "app": {
    "app": "example.bidbot",
    "appName": "BidBot",
    "settings": {
      "sound": "Glass",
      "persistent": false,
      "timeout": 20,
      "corner": "bottomRight",
      "effectiveCorner": "bottomRight",
      "display": "main",
      "muteBanners": false,
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

**Response fields**

| Field | Type | Description |
|---|---|---|
| `ok` | boolean | Always `true` on success. |
| `applied` | array | The keys that were changed. |
| `app` | object | The app after the change, in the shape of [`GET /v1/apps/settings`](#get-v1appssettings). |

**Errors**

| Status | When |
|---|---|
| `400` | `app` is missing, a key is unknown, or a value has the wrong type or is out of range. |
| `403` | `revokeCommands` or `revokeCallbackHost` was sent with a value other than `true`. |
| `404` | `app` names an app that is not registered. |

**Notes**

- **All or nothing.** If any key is invalid, nothing is changed.
- The two `revoke` keys only withdraw. Nothing sent to this endpoint grants an approval.
- `opens` is stored in the app's manifest as `appBundleId` or `appPath`.

### `GET /v1/actions/approvals`

Lists the shell commands, scripts and Shortcuts that the user approved for templates. A template that runs a
command must be approved once by the user, and the approval is tied to the exact commands that were shown.

**Request**

No parameters.

**Example request**

```sh
curl -s "$HERALD/v1/actions/approvals" -H "Authorization: Bearer $TOKEN"
```

**Example response**

```json
{
  "items": [
    {
      "app": "example.bidbot",
      "template": "bid-won",
      "commands": ["open -a Numbers ~/Bids/acme.numbers"],
      "approvedAt": "2026-10-02T13:15:00.000Z"
    }
  ],
  "note": "Approvals are granted by the user when a banner asks; here they can only be listed and revoked."
}
```

**Response fields**

| Field | Type | Description |
|---|---|---|
| `items` | array | One object per approved template. |
| `items[].app` | string | The app that owns the template. |
| `items[].template` | string | The template name. |
| `items[].commands` | array | The exact commands the user saw and approved. |
| `items[].approvedAt` | string | When the user approved, as an ISO 8601 date. |

### `DELETE /v1/actions/approvals`

Withdraws the approval of one template's commands. The next time a button of that template would run a
command, Herald asks the user again.

**Request**

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `app` | query | string | yes | The app that owns the template. |
| `template` | query | string | yes | The template name. |

**Example request**

```sh
curl -s -X DELETE "$HERALD/v1/actions/approvals?app=example.bidbot&template=bid-won" \
  -H "Authorization: Bearer $TOKEN"
```

**Example response**

```json
{"ok": true}
```

**Errors**

| Status | When |
|---|---|
| `400` | `app` or `template` is missing. |
| `404` | There is no approval for this app and template. |

## Related

- [The Herald app](../../APP.md): the Apps tab, changing an icon and removing an app by hand.
- [Manifests](../manifests.md): describe the fields and actions an app sends.
- [Actions reference](../actions.md): command buttons, callbacks and the approvals they need.
- [MCP tools for apps and settings](../mcp/apps-and-settings.md): the same operations for an agent.
