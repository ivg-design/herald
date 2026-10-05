# History API

These endpoints read and manage the record Herald keeps of every notification: list recent ones, search, show
one again, delete one, clear an app's History, and export it. Use them to audit what an integration sent, or to
build your own view of past notifications. The examples use the `$HERALD` and `$TOKEN` variables from
[Connect](README.md#connect).

## What History holds

Every notification is stored when it is delivered, whether or not a banner was shown. The record stays after
the banner is closed. It holds the notification as it was drawn, when it arrived, how it ended, and what the
user replied.

Herald keeps a fixed number of notifications per app, 1000 unless the user changed it in
**Settings > General**. When an app goes over the limit, its oldest records are removed.

![Herald's History window with the app list on the left and notifications on the right](../../../web/public/shots/docs/history.png "The History window shows the same records these endpoints return. All Apps, at the top of the list, corresponds to a request with no app parameter.")

### The history record

Every endpoint that returns notifications returns them in this shape.

| Field | Type | Description |
|---|---|---|
| `id` | string | The notification id. |
| `app` | string | The app that sent it. |
| `notification` | object | The notification as drawn, after the template was applied. Same fields as [`POST /v1/notify`](notifications.md#post-v1notify). |
| `deliveredAt` | string | When it arrived, as an ISO 8601 date. |
| `dismissedAt` | string | When its banner closed. Absent while the banner is still showing or snoozed. |
| `actionUsed` | string | How it ended: a button's label, `open` for a click on the banner, or `timeout`. |
| `actionNote` | string | A note about an action that could not do its job. |
| `snoozedUntil` | string | When a snoozed banner returns. |
| `imagePath` | string | The local copy of the notification's picture. |
| `fields` | object | The values the template's tokens resolved to at delivery. |
| `speech` | object | What was spoken: `text`, `voice`, `audioPath`, `durationSeconds`, `suppressed`. |
| `reply` | string | What the user typed into the banner's reply field. |
| `repliedAt` | string | When the user replied. |
| `replyAudioPath` | string | The recording of a voice reply. |
| `replyTranscript` | string | The transcript of a voice reply, made on this Mac. |

Fields that do not apply to a notification are absent from its record.

## Endpoints

| Endpoint | Purpose |
|---|---|
| [`GET /v1/history`](#get-v1history) | List the most recent notifications. |
| [`GET /v1/history/search`](#get-v1historysearch) | Search by words. |
| [`POST /v1/history/reshow`](#post-v1historyreshow) | Show a past notification again. |
| [`DELETE /v1/history/item`](#delete-v1historyitem) | Delete one notification. |
| [`DELETE /v1/history`](#delete-v1history) | Clear an app's History, or all of it. |
| [`GET /v1/history/export`](#get-v1historyexport) | Export full records as JSON. |

### `GET /v1/history`

Lists the most recent notifications, newest first.

**Request**

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `app` | query | string | no | Return only this app's notifications. Default: every app. |
| `limit` | query | integer | no | The most records to return. Default `50`. |

**Example request**

```sh
curl -s "$HERALD/v1/history?app=example.bidbot&limit=1" -H "Authorization: Bearer $TOKEN"
```

**Example response**

```json
{
  "items": [
    {
      "id": "bid-42",
      "app": "example.bidbot",
      "deliveredAt": "2026-10-02T13:00:04.237Z",
      "dismissedAt": "2026-10-02T13:00:19.462Z",
      "actionUsed": "Open",
      "notification": {
        "app": "example.bidbot",
        "id": "bid-42",
        "title": "Bid accepted",
        "subtitle": "Acme RFP",
        "body": "Your bid of $4,200 was accepted.",
        "url": "https://example.com/bids/42",
        "buttons": [{"label": "Open", "url": "https://example.com/bids/42"}],
        "sound": "Glass",
        "persistent": true
      },
      "fields": {
        "app": "example.bidbot",
        "appName": "BidBot",
        "id": "bid-42",
        "title": "Bid accepted",
        "subtitle": "Acme RFP",
        "body": "Your bid of $4,200 was accepted.",
        "deliveredAt": "2026-10-02T13:00:04.237Z",
        "sound": "Glass"
      }
    }
  ]
}
```

**Response fields**

| Field | Type | Description |
|---|---|---|
| `items` | array | [History records](#the-history-record), newest first. |

**Errors**

| Status | When |
|---|---|
| `400` | `limit` is negative or not a whole number. |

### `GET /v1/history/search`

Finds notifications that contain every word of a query. The search looks in the title, subtitle, body, app id
and app name. It ignores case and accents.

**Request**

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `q` | query | string | no | The words to find. An empty query returns the most recent notifications. |
| `app` | query | string | no | Search only this app. Default: every app. |
| `limit` | query | integer | no | The most records to return, up to 1000. Default `50`. |

**Example request**

```sh
curl -s -G "$HERALD/v1/history/search" -H "Authorization: Bearer $TOKEN" \
  --data-urlencode "q=acme accepted" --data-urlencode "limit=5"
```

**Example response**

```json
{
  "query": "acme accepted",
  "count": 1,
  "items": [
    {
      "id": "bid-42",
      "app": "example.bidbot",
      "deliveredAt": "2026-10-02T13:00:04.237Z",
      "dismissedAt": "2026-10-02T13:00:19.462Z",
      "actionUsed": "Open",
      "notification": {
        "app": "example.bidbot",
        "id": "bid-42",
        "title": "Bid accepted",
        "subtitle": "Acme RFP",
        "body": "Your bid of $4,200 was accepted."
      }
    }
  ]
}
```

**Response fields**

| Field | Type | Description |
|---|---|---|
| `query` | string | The query as Herald read it. |
| `count` | integer | How many records are in `items`. |
| `items` | array | [History records](#the-history-record), newest first. |

**Errors**

| Status | When |
|---|---|
| `400` | `limit` is negative or not a whole number. |

### `POST /v1/history/reshow`

Shows a stored notification again as a new banner, with its sound and a fresh delivery time. Use it to bring
back something the user dismissed too early.

**Request**

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `app` | body | string | yes | The app that sent the notification. |
| `id` | body | string | yes | The notification id. |

**Example request**

```sh
curl -s -X POST "$HERALD/v1/history/reshow" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"app": "example.bidbot", "id": "bid-42"}'
```

**Example response**

```json
{"ok": true, "id": "bid-42"}
```

**Errors**

| Status | When |
|---|---|
| `400` | `app` or `id` is missing. |
| `404` | History has no notification with this `app` and `id`. |

### `DELETE /v1/history/item`

Deletes one notification from History. If its banner is still on screen, the banner is closed.

**Request**

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `app` | query | string | yes | The app that sent the notification. |
| `id` | query | string | yes | The notification id. |

**Example request**

```sh
curl -s -X DELETE "$HERALD/v1/history/item?app=example.bidbot&id=bid-42" \
  -H "Authorization: Bearer $TOKEN"
```

**Example response**

```json
{"ok": true}
```

**Errors**

| Status | When |
|---|---|
| `400` | `app` or `id` is missing. |
| `404` | History has no notification with this `app` and `id`. |

### `DELETE /v1/history`

Clears History: one app's, or everything.

> [!WARNING]
> Without `app`, this deletes the History of every app. It cannot be undone.

**Request**

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `app` | query | string | no | Clear only this app's History. Default: every app. |

**Example request**

```sh
curl -s -X DELETE "$HERALD/v1/history?app=example.bidbot" -H "Authorization: Bearer $TOKEN"
```

**Example response**

```json
{"ok": true}
```

### `GET /v1/history/export`

Returns every stored record, of one app or of all apps, as JSON. Herald either returns the records in the
reply or writes them to a file you name.

**Request**

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `app` | query | string | no | Export only this app. Default: every app. |
| `path` | query | string | no | Write the records to this file. Must end in `.json`. |

**Example request**

```sh
curl -s -G "$HERALD/v1/history/export" -H "Authorization: Bearer $TOKEN" \
  --data-urlencode "app=example.bidbot" --data-urlencode "path=$HOME/Desktop/bidbot-history.json"
```

**Example response**

```json
{"count": 128, "path": "/Users/you/Desktop/bidbot-history.json", "bytes": 214530}
```

**Response fields**

| Field | Type | Description |
|---|---|---|
| `count` | integer | How many records were exported. |
| `path` | string | Where the file was written. Present when you sent `path`. |
| `bytes` | integer | The size of the written file. Present when you sent `path`. |
| `items` | array | The [history records](#the-history-record). Present when you did not send `path`. |

**Errors**

| Status | When |
|---|---|
| `400` | `path` does not end in `.json`, or its folder does not exist. |

## Related

- [The Herald app](../../APP.md): the History window, including the **All Apps** selection.
- [Replies API](replies.md): read what the user typed into a banner.
- [Settings API](settings.md#put-v1settings): the `historyCapPerApp` key sets how much History is kept.
- [MCP tools for apps and settings](../mcp/apps-and-settings.md#list_history): the same operations for an agent.
