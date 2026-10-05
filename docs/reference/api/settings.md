# Settings API

These endpoints read and change Herald's own settings: the general and voice settings as one validated table,
and the quiet-hours schedule. Use them to configure Herald from a script, or to build a tool that shows its
state. The examples use the `$HERALD` and `$TOKEN` variables from [Connect](README.md#connect).

## How settings are organised

Herald has three kinds of settings, and each has its own endpoints.

| Kind | What it covers | Endpoints |
|---|---|---|
| **General settings** | The port, login item, sound mute, stacking, History size, tooltips and voice. | [`/v1/settings`](#get-v1settings) on this page. |
| **Quiet hours** | When speech, sounds and banners are held back. | [`/v1/settings/quiet-hours`](#get-v1settingsquiet-hours) on this page. |
| **Per-app settings** | One app's sound, corner, display, mute and voice. | [`/v1/apps/settings`](apps.md#get-v1appssettings) in the Apps API. |

The general settings are a flat list of **keys**. Each key has a type and a range. The reply to a read includes
a **schema** that describes every key, and **options** that list the allowed choices on this Mac, such as the
installed sounds, the connected displays and the available voices. A program can build a settings screen from
those two parts without knowing the keys in advance.

![The General tab of Herald's Settings with the Local API port, Launch at login, Mute all sounds, Tooltips and Keep per app](../../../web/public/shots/docs/settings-general.png "Settings > General. Each control here maps to a key of the settings table.")

## Endpoints

| Endpoint | Purpose |
|---|---|
| [`GET /v1/settings`](#get-v1settings) | Read every general and voice setting. |
| [`PUT /v1/settings`](#put-v1settings) | Change one or more of them. |
| [`GET /v1/settings/quiet-hours`](#get-v1settingsquiet-hours) | Read the quiet-hours schedule and what is silenced now. |
| [`PUT /v1/settings/quiet-hours`](#put-v1settingsquiet-hours) | Change the schedule, start a silence, or end one. |

The global stacking level also has its own short route,
[`/v1/settings/stacking`](stacks.md#get-v1settingsstacking), documented with the Stacks API.

## General and voice settings

### Setting keys

These are the keys of the settings table. A read returns their current values and a write changes them.

| Key | Type | Description |
|---|---|---|
| `port` | integer | The local API port, from 1024 to 65535. Changing it restarts the server on the new port. |
| `launchAtLogin` | boolean | `true` opens Herald when you log in. |
| `muteAllSounds` | boolean | `true` mutes every notification sound. It is the **Mute Sounds** item of the bell menu. |
| `stacking` | string | The global [stacking level](../stacking.md): `byApp`, `byIssuer`, `bySender` or `never`. |
| `historyCapPerApp` | integer | How many notifications History keeps per app, from 1 to 100000. Older ones are removed. |
| `tooltipLevel` | string | How much a tooltip says: `nameOnly` or `nameAndDescription`. |
| `voiceEngine` | string | The speech engine: `kokoro`, `system` or `off`. |
| `voiceDefault` | string | The default voice id, such as `af_heart`. |
| `voiceSpeed` | number | The default speech speed, from 0.5 to 2.0. |
| `voiceLang` | string | The default language code, such as `en-us`. |
| `voiceSystem` | string or null | The macOS voice the `system` engine uses. `null` picks the system default. |

What the voice keys do is explained in the [voice reference](../voice.md).

### `GET /v1/settings`

Returns the current value of every key, the schema that describes the keys, and the choices available on this
Mac.

**Request**

No parameters.

**Example request**

```sh
curl -s "$HERALD/v1/settings" -H "Authorization: Bearer $TOKEN"
```

**Example response**

The `schema` and `options` lists are shortened here to one or two entries each.

```json
{
  "settings": {
    "port": 48617,
    "launchAtLogin": true,
    "muteAllSounds": false,
    "stacking": "bySender",
    "historyCapPerApp": 1000,
    "tooltipLevel": "nameAndDescription",
    "voiceEngine": "kokoro",
    "voiceDefault": "af_heart",
    "voiceSpeed": 1,
    "voiceLang": "en-us",
    "voiceSystem": null
  },
  "schema": [
    {
      "key": "port",
      "group": "General",
      "type": "integer",
      "min": 1024,
      "max": 65535,
      "restartsServer": true,
      "description": "The local API port (General > Local API). Changing it restarts the server; the new port is written to the port file."
    },
    {
      "key": "stacking",
      "group": "General",
      "type": "choice",
      "values": ["byApp", "byIssuer", "bySender", "never"],
      "description": "How banners stack by default: byApp, byIssuer, bySender or never. An app can override it."
    }
  ],
  "options": {
    "sounds": ["none", "Basso", "Blow", "Glass"],
    "displays": [{"id": "main", "name": "Main display"}, {"id": "3", "name": "Studio Display"}],
    "corners": ["topRight", "topLeft", "bottomRight", "bottomLeft"],
    "stackingLevels": ["byApp", "byIssuer", "bySender", "never"],
    "voiceEngines": ["kokoro", "system", "off"],
    "voices": [{"id": "af_heart", "name": "af_heart"}, {"id": "bm_george", "name": "bm_george"}],
    "historyCapChoices": [100, 250, 500, 1000, 2500, 5000]
  }
}
```

**Response fields**

| Field | Type | Description |
|---|---|---|
| `settings` | object | The current value of each [setting key](#setting-keys). |
| `schema` | array | One entry per key. See the next table. |
| `options` | object | The choices available on this Mac. See the table after that. |

Each `schema` entry:

| Field | Type | Description |
|---|---|---|
| `key` | string | The setting's key. |
| `group` | string | The Settings tab or section it belongs to. |
| `type` | string | `boolean`, `integer`, `number`, `string` or `choice`. |
| `description` | string | What the setting does, in one sentence. |
| `min`, `max` | number | The allowed range of a numeric key. |
| `values` | array | The allowed values of a `choice` key. |
| `maxLength` | integer | The longest allowed string. |
| `nullable` | boolean | `true` when the key accepts `null`. |
| `restartsServer` | boolean | `true` when changing the key restarts the local API. |

The `options` object:

| Field | Type | Description |
|---|---|---|
| `sounds` | array | The sound names this Mac offers, with `none` first. |
| `displays` | array | The connected displays, each with an `id` and a `name`. |
| `corners` | array | The four screen corners. |
| `stackingLevels` | array | The four stacking levels. |
| `voiceEngines` | array | The speech engines. |
| `voices` | array | The voices of the current engine, each with an `id` and a `name`. |
| `historyCapChoices` | array | The History sizes that Settings offers in its menu. |

### `PUT /v1/settings`

Changes one or more settings. Send an object with only the keys you want to change.

**Request**

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| any [setting key](#setting-keys) | body | varies | yes | The new value for that key. Send at least one key. |

**Example request**

```sh
curl -s -X PUT "$HERALD/v1/settings" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"muteAllSounds": true, "voiceSpeed": 1.15}'
```

**Example response**

The reply has the same three parts as [`GET /v1/settings`](#get-v1settings), with the new values, plus
`applied`. The `schema` and `options` parts are left out of this example.

```json
{
  "applied": ["muteAllSounds", "voiceSpeed"],
  "settings": {
    "port": 48617,
    "launchAtLogin": true,
    "muteAllSounds": true,
    "stacking": "bySender",
    "historyCapPerApp": 1000,
    "tooltipLevel": "nameAndDescription",
    "voiceEngine": "kokoro",
    "voiceDefault": "af_heart",
    "voiceSpeed": 1.15,
    "voiceLang": "en-us",
    "voiceSystem": null
  }
}
```

**Response fields**

| Field | Type | Description |
|---|---|---|
| `applied` | array | The keys that were changed. |
| `settings` | object | Every setting after the change. |
| `schema`, `options` | array, object | As in [`GET /v1/settings`](#get-v1settings). |
| `note` | string | Present when `port` changed: a reminder that the server is restarting. |

**Errors**

| Status | When |
|---|---|
| `400` | The body is empty, a key is unknown, or a value has the wrong type or is out of range. |

**Notes**

- **All or nothing.** If any key is invalid, nothing is changed. The message names the key, and for an
  unknown key it lists the known ones.
- When you change `port`, the reply still arrives on the old port. A moment later the server restarts on the
  new one and the `port` file holds the new number. Read the file again before your next request.

## Quiet hours

Quiet hours are times when Herald holds back speech, sounds or banners. There is a weekly schedule of
**windows**, and an **ad hoc** silence that you can start at any moment for a fixed time. What a window is and
what "silenced" means for each kind of output is explained in the
[quiet-hours reference](../quiet-hours.md), which also documents every field of the window object.

### `GET /v1/settings/quiet-hours`

Returns the schedule, the ad hoc silence if one is running, and what is silenced at this moment.

**Request**

No parameters.

**Example request**

```sh
curl -s "$HERALD/v1/settings/quiet-hours" -H "Authorization: Bearer $TOKEN"
```

**Example response**

```json
{
  "windows": [
    {
      "id": "night",
      "days": [],
      "start": "22:30",
      "end": "07:30",
      "speech": true,
      "sounds": true,
      "banners": false,
      "speakSummary": false
    }
  ],
  "adHoc": {
    "until": "2026-10-02T14:00:00.000Z",
    "speech": true,
    "sounds": true,
    "banners": false
  },
  "status": {
    "active": true,
    "speech": true,
    "sounds": true,
    "banners": false,
    "until": "2026-10-02T14:00:00.000Z",
    "source": "adhoc"
  }
}
```

**Response fields**

| Field | Type | Description |
|---|---|---|
| `windows` | array | The weekly schedule. Each item is a [window object](../quiet-hours.md#windows). |
| `adHoc` | object | The running ad hoc silence: when it ends and what it silences. Absent when there is none. |
| `status.active` | boolean | `true` when anything is silenced right now. |
| `status.speech` | boolean | `true` when speech is held back right now. |
| `status.sounds` | boolean | `true` when sounds are held back right now. |
| `status.banners` | boolean | `true` when banners are held back right now. |
| `status.until` | string | When the current silence ends. Present while `active` is `true`. |
| `status.source` | string | What is causing the silence: `window`, `adhoc` or `both`. Present while active. |

### `PUT /v1/settings/quiet-hours`

Changes quiet hours. The body can do three things, alone or together: replace the schedule, end the current
silence, and start an ad hoc silence.

**Request**

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `windows` | body | array | no | Replaces the whole schedule with these [window objects](../quiet-hours.md#windows). |
| `resume` | body | boolean | no | `true` ends the current silence. |
| `adHoc` | body | object | no | Starts a silence now. See the next table. |

The `adHoc` object needs `until` or `minutes`:

| Field | Type | Required | Description |
|---|---|---|---|
| `minutes` | number | no | How long the silence lasts. More than 0 and at most 10080 (7 days). |
| `until` | string | no | When it ends: `HH:MM` for the next time the clock shows it, or an ISO 8601 date. |
| `speech` | boolean | no | Hold back speech. Default `true`. |
| `sounds` | boolean | no | Hold back sounds. Default `true`. |
| `banners` | boolean | no | Hold back banners. Default `false`. |

**Example request**

Silence speech and sounds for one hour:

```sh
curl -s -X PUT "$HERALD/v1/settings/quiet-hours" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"adHoc": {"minutes": 60}}'
```

**Example response**

The reply has the same shape as [`GET /v1/settings/quiet-hours`](#get-v1settingsquiet-hours), after the change.

```json
{
  "windows": [],
  "adHoc": {"until": "2026-10-02T14:00:00.000Z", "speech": true, "sounds": true, "banners": false},
  "status": {
    "active": true,
    "speech": true,
    "sounds": true,
    "banners": false,
    "until": "2026-10-02T14:00:00.000Z",
    "source": "adhoc"
  }
}
```

**Errors**

| Status | When |
|---|---|
| `400` | A window's `start` or `end` is not `HH:MM`, they are equal, a day name is unknown, or an `id` repeats. |
| `400` | There are more than 24 windows. |
| `400` | `adHoc.minutes` is out of range, or `adHoc.until` is not a time, or is in the past. |

**Notes**

- The three parts are applied in this order: `windows`, then `resume`, then `adHoc`. A silence started by a
  request therefore wins over a `resume` in the same request.
- `windows` replaces the schedule. To add one window, read the schedule, add to the list, and send the whole
  list back.
- `resume` ends an ad hoc silence and the current occurrence of every active window. The next occurrence of
  each window still applies.

A weekday schedule, as a second example:

```sh
curl -s -X PUT "$HERALD/v1/settings/quiet-hours" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"windows": [{"days": ["mon", "tue", "wed", "thu", "fri"], "start": "22:30", "end": "07:30",
                    "speech": true, "sounds": true}]}'
```

## Related

- [The Herald app](../../APP.md): the Settings window, tab by tab.
- [Quiet hours reference](../quiet-hours.md): windows, what is silenced, and urgent notifications.
- [Voice reference](../voice.md): engines, voices and the voice keys.
- [Apps API](apps.md#put-v1appssettings): settings that belong to one app.
- [MCP tools for apps and settings](../mcp/apps-and-settings.md#get_settings): the same operations for an agent.
