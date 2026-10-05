# Notifications API

These endpoints put a notification on screen and take it away again: show a banner, speak without a banner,
dismiss, and snooze. This is the part of the [HTTP API](README.md) most integrations need, and often the only
part. The examples use the `$HERALD` and `$TOKEN` variables from [Connect](README.md#connect).

## How a notification works

A notification is one JSON object sent by an **app**. The app is identified by an id you choose, such as
`example.bidbot`. You do not have to register the app first: Herald registers an unknown id the first time it
sends something.

Herald does four things with a notification:

1. It applies a **template** if the notification names one, or if the app's manifest sets a default. The
   template decides the layout. Without one, Herald uses a built-in layout.
2. It shows a **banner**, plays the app's sound, and speaks the text if you asked for speech.
3. It stores the notification in **History**, where it stays after the banner is gone.
4. It keeps the banner until the user closes it, a button is pressed, a `timeout` ends it, or you dismiss it.

Every notification has an `id`. If you send one, you can use it later to replace, dismiss or snooze that
banner. If you leave it out, Herald generates one and returns it.

![A Herald banner with a title, a subtitle, two lines of body text, the time and a close button](../../../web/public/shots/docs/banner-plain.png "One notification as a banner: the title, the subtitle, the body, the time it arrived and the close button.")

What happens when the user clicks a banner is described in [How banners behave](../banners.md).

## Endpoints

| Endpoint | Purpose |
|---|---|
| [`POST /v1/notify`](#post-v1notify) | Show a notification. |
| [`POST /v1/speak`](#post-v1speak) | Say text aloud with no banner. |
| [`POST /v1/dismiss`](#post-v1dismiss) | Close one banner. |
| [`POST /v1/dismissAll`](#post-v1dismissall) | Close every banner of an app, or one stack. |
| [`POST /v1/snooze`](#post-v1snooze) | Hide a banner and bring it back later. |
| [`POST /v1/unsnooze`](#post-v1unsnooze) | Bring a snoozed banner back now. |
| [`POST /v1/compose`](#post-v1compose) | Open the Composer window. |

### `POST /v1/notify`

Shows a notification as a banner and stores it in History. Sending the same `id` again replaces the banner
that is on screen in place, which is how you update a progress or count without stacking new banners.

**Request**

Only `app` is required, plus `title` unless the template supplies one. The fields are grouped below; all of
them go in the JSON body.

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `app` | body | string | yes | The id of the app that is sending. |
| `title` | body | string | yes | The headline. Optional when `template` names a template that sets a title. |
| `id` | body | string | no | Your id for this notification. Herald generates one when you omit it. |
| `subtitle` | body | string | no | A second line under the title. |
| `body` | body | string | no | The main text. Markdown links such as `[Open](https://example.com)` work. |
| `image` | body | string | no | A picture: a file path, an `https` URL or a `data:` URI. |
| `url` | body | string | no | A link the banner opens when clicked. Only `http`, `https` and `mailto` open. |
| `template` | body | string | no | The name of a template saved for this app. Default: the manifest's `defaultTemplate`. |
| `metadata` | body | object | no | Extra values for template tokens. Stored in History. |
| `group` | body | string | no | A key for stacking: banners of one app with the same `group` stack together. |

Fields that control how the banner behaves:

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `persistent` | body | boolean | no | `true` keeps the banner until it is dismissed. Default: the app's setting. |
| `timeout` | body | number | no | Seconds until the banner closes itself. Hovering pauses the countdown. |
| `sound` | body | string | no | `default`, a system sound name such as `Glass`, a file path, or `none`. |
| `priority` | body | string | no | `low`, `normal`, `high` or `urgent`. |
| `snooze` | body | boolean | no | `true` adds a clock menu to the banner for snoozing it. |
| `reminder` | body | object | no | Adds an **Add to Reminders** button. See [Reminder object](#reminder-object). |

Fields that add buttons:

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `buttons` | body | array | no | Up to 8 buttons. See [Button object](#button-object). |
| `actionIds` | body | array | no | Ids of actions the app's manifest declares, used when you send no `buttons`. |

Fields that add speech (explained in the [voice reference](../voice.md)):

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `speak` | body | boolean or object | no | `true` speaks the title and body. An object sets the text, voice, speed and language. |
| `audio` | body | string | no | A recorded voice message to play: a file path, an `https` URL or a `data:` URI. |
| `presentation` | body | string | no | `banner`, `voice` (speech only, no banner) or `both`. Default `banner`. |

Fields for the built-in layouts, used only when no template applies:

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `layout` | body | string | no | `imageLeft`, `imageRight`, `hero` or `compact`. Default `imageLeft`. |
| `accentColor` | body | string | no | A hex colour such as `#34C759`. |
| `showSubtitle` | body | boolean | no | `false` hides the subtitle. |
| `showBody` | body | boolean | no | `false` hides the body. |
| `showTimestamp` | body | boolean | no | `false` hides the time. |
| `maxBodyLines` | body | integer | no | The number of body lines shown before the text is cut. |

**Example request**

```sh
curl -s -X POST "$HERALD/v1/notify" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{
    "app": "example.bidbot",
    "id": "bid-42",
    "title": "Bid accepted",
    "subtitle": "Acme RFP",
    "body": "Your bid of $4,200 was accepted.",
    "url": "https://example.com/bids/42",
    "buttons": [{"label": "Open", "url": "https://example.com/bids/42"}]
  }'
```

**Example response**

```json
{"ok": true, "id": "bid-42"}
```

**Response fields**

| Field | Type | Description |
|---|---|---|
| `ok` | boolean | Always `true` on success. |
| `id` | string | The notification id: yours, or the one Herald generated. |

**Errors**

| Status | When |
|---|---|
| `400` | `app` is missing, or there is no `title` and no template that supplies one. |
| `400` | A `speak` value is invalid: `invalid voice`, `invalid lang`, or a `speed` outside 0.5 to 2.0. |
| `413` | A field is over its limit. The message names the field. See [Limits](README.md#limits). |
| `429` | The app id is new and 200 apps are already registered. |

**Notes**

- A top-level key that is not in the tables above is treated as a template field and moved into `metadata`.
  You can send `"amount": "$4,200"` at the top level and bind `{amount}` in a template. A top-level key wins
  over the same key inside `metadata`.
- An unknown `template` name is not an error while the notification has its own title. Herald shows it with
  the built-in layout.
- An `image` is checked by its bytes, not its name. PNG, JPEG, GIF, WebP, HEIC, AVIF, TIFF and BMP are
  accepted, up to 10 MB. Anything else is ignored and the banner shows without a picture.
- An explicit empty list, `"buttons": []`, means no buttons, even when the manifest declares actions.
- `priority: "urgent"` breaks through [quiet hours](../quiet-hours.md) only for apps where the user allowed it.

#### Button object

A button has a label and one thing it does. Give exactly one of `url`, `command`, `callback`, `openApp` or
`reply`. The full behaviour of each kind is in the [actions reference](../actions.md).

| Field | Type | Required | Description |
|---|---|---|---|
| `label` | string | yes | The text on the button. |
| `style` | string | no | `default`, `destructive` or `cancel`. |
| `url` | string | no | Opens this link. |
| `command` | string | no | Runs this shell command. The user must allow commands for the app first. |
| `callback` | object | no | Posts to your callback URL. Fields: `url` and `payload`, both optional. |
| `openApp` | object | no | Brings an app to the front. Fields: `bundleId` or `path`; empty means the sender. |
| `reply` | object | no | Shows a text field in the banner. Fields: `placeholder`, `callback`, `voice`. |

```json
{
  "app": "example.bidbot",
  "title": "Counter-offer from Acme",
  "body": "They offer $3,900. Accept?",
  "buttons": [
    {"label": "Accept", "callback": {"payload": {"decision": "accept"}}},
    {"label": "Decline", "style": "destructive", "callback": {"payload": {"decision": "decline"}}},
    {"label": "Reply", "reply": {"placeholder": "Message to Acme"}}
  ]
}
```

> [!NOTE]
> `actions` is accepted as another name for `buttons`. When a request has both, `buttons` is used.

#### Reminder object

| Field | Type | Required | Description |
|---|---|---|---|
| `title` | string | no | The reminder's title. Default: the notification's title. |
| `due` | string | no | When it is due, as an ISO 8601 date such as `2026-10-02T09:00:00-04:00`. |

### `POST /v1/speak`

Says text aloud and shows no banner. It is a shortcut for a notification with `presentation: "voice"`, and the
text is stored in History like any other notification. Use it for a short spoken status when a banner would be
noise.

**Request**

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `app` | body | string | yes | The id of the app that is speaking. |
| `text` | body | string | yes | What to say. At most 2000 characters are spoken. |
| `voice` | body | string | no | A voice id such as `af_bella`. Default: the app's voice, else the engine default. |
| `speed` | body | number | no | From 0.5 to 2.0. Default `1.0`. |
| `lang` | body | string | no | A language code such as `en-us`. |
| `id` | body | string | no | Your id for the History entry. |

**Example request**

```sh
curl -s -X POST "$HERALD/v1/speak" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"app": "example.bidbot", "text": "Deploy finished", "voice": "af_bella", "speed": 1.1}'
```

**Example response**

```json
{"ok": true, "id": "7C1D0E52-3F0B-4B8E-9A55-0F3A1C0D2E11"}
```

**Errors**

| Status | When |
|---|---|
| `400` | `app` or `text` is missing or empty. |
| `400` | `voice`, `lang` or `speed` is invalid. |

**Notes**

- If speech cannot play (Herald is muted, the app's **Speak** switch is off, or the engine is off), the text
  is shown as a normal banner instead, so it is never lost.
- The History title is the first 80 characters of the text.

### `POST /v1/dismiss`

Closes one banner. The notification stays in History. Use it when the event behind a banner is over, for
example when the user handled it in your own app.

**Request**

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `app` | body | string | yes | The app id the notification was sent with. |
| `id` | body | string | yes | The notification id. |

**Example request**

```sh
curl -s -X POST "$HERALD/v1/dismiss" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"app": "example.bidbot", "id": "bid-42"}'
```

**Example response**

```json
{"ok": true}
```

**Errors**

| Status | When |
|---|---|
| `400` | `app` or `id` is missing. |

**Notes**

- Dismissing an id that is not on screen is not an error. The reply is still `{"ok": true}`.

### `POST /v1/dismissAll`

Closes several banners at once. What it closes depends on the body.

**Request**

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `app` | body | string | no | Close only this app's banners. Omit it to close every banner of every app. |
| `group` | body | string | no | Close only the stack with this group. Requires `app`. |

**Example request**

```sh
curl -s -X POST "$HERALD/v1/dismissAll" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"app": "example.bidbot", "group": "acme"}'
```

**Example response**

```json
{"ok": true}
```

**Errors**

| Status | When |
|---|---|
| `400` | `group` is sent without `app`. |

**Notes**

- An empty body closes every banner on screen.
- Dismissed notifications stay in History.

### `POST /v1/snooze`

Hides a banner and shows it again, with the same id, after a number of minutes. A snooze survives a restart of
Herald, and History marks the notification as snoozed while it waits.

**Request**

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `app` | body | string | yes | The app id the notification was sent with. |
| `id` | body | string | yes | The notification id. |
| `minutes` | body | number | yes | How long to hide it. More than 0 and at most 43200 (30 days). Fractions are allowed. |

**Example request**

```sh
curl -s -X POST "$HERALD/v1/snooze" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"app": "example.bidbot", "id": "bid-42", "minutes": 15}'
```

**Example response**

```json
{"ok": true, "until": "2026-10-02T13:15:00.000Z"}
```

**Response fields**

| Field | Type | Description |
|---|---|---|
| `ok` | boolean | Always `true` on success. |
| `until` | string | When the banner comes back, as an ISO 8601 date. |

**Errors**

| Status | When |
|---|---|
| `400` | `app`, `id` or `minutes` is missing, or `minutes` is out of range. |
| `400` | The notification was already dismissed. |
| `404` | No notification with this `app` and `id` exists. |

**Notes**

- Sending a new notification with the same `id` cancels a pending snooze.
- The duration is elapsed time: one hour is one hour even across a daylight-saving change.

### `POST /v1/unsnooze`

Cancels a snooze and shows the banner again at once. It plays no sound, because it is not a new alert.

**Request**

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `app` | body | string | yes | The app id the notification was sent with. |
| `id` | body | string | yes | The notification id. |

**Example request**

```sh
curl -s -X POST "$HERALD/v1/unsnooze" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"app": "example.bidbot", "id": "bid-42"}'
```

**Example response**

```json
{"ok": true}
```

**Errors**

| Status | When |
|---|---|
| `400` | `app` or `id` is missing. |

### `POST /v1/compose`

Opens Herald's Composer window, where a person fills in a notification by hand and sends it. It is what
`herald compose` calls. It takes no body and shows no banner.

**Request**

No parameters.

**Example request**

```sh
curl -s -X POST "$HERALD/v1/compose" -H "Authorization: Bearer $TOKEN"
```

**Example response**

```json
{"ok": true}
```

## Related

- [Send your first notification](../../getting-started.md): a walk through the first `POST /v1/notify`.
- [How banners behave](../banners.md): clicking, expanding, closing and timeouts.
- [Templates](../../TEMPLATES.md): control the layout a notification is drawn with.
- [Actions](../../ACTIONS.md): buttons that call you back, run commands or take a reply.
- [Voice reference](../voice.md): the `speak`, `audio` and `presentation` fields in full.
- [History API](history.md): read back what was sent.
