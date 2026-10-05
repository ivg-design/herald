# Stacks API

These endpoints show which banners are stacked, open or close a stack, and set how Herald groups banners into
stacks. Use them to inspect what is on screen or to control stacking from a script. The examples use the
`$HERALD` and `$TOKEN` variables from [Connect](README.md#connect).

## What a stack is

When several notifications that belong together are on screen, Herald folds them into one **stack**: a single
card with a count, so that ten emails do not cover the screen. Clicking a stack opens it into a list.

What "belong together" means is the **stacking level**.

| Level | Notifications that stack together |
|---|---|
| `byApp` | Those of one product, even when it sends under several app ids. |
| `byIssuer` | Those of one app id. |
| `bySender` | Those of one app id with the same `group` value. |
| `never` | None. Every notification is its own banner. |

There is one global level, and each app can override it. The concept is explained in full, with examples, in
the [stacking reference](../stacking.md).

![A closed stack of banners with a count badge](../../../web/public/shots/docs/banner-stack-closed.png "A closed stack. The card on top is the newest notification and the badge counts the rest.")

## Endpoints

| Endpoint | Purpose |
|---|---|
| [`GET /v1/stacks`](#get-v1stacks) | List the stacks on screen. |
| [`POST /v1/stacks/expand`](#post-v1stacksexpand) | Open or close a stack. |
| [`GET /v1/settings/stacking`](#get-v1settingsstacking) | Read the global stacking level. |
| [`PUT /v1/settings/stacking`](#put-v1settingsstacking) | Set the global stacking level. |

### `GET /v1/stacks`

Lists the stacks that are on screen now, with the notifications in each.

**Request**

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `app` | query | string | no | Return only this app's stacks. Default: every app. |

**Example request**

```sh
curl -s "$HERALD/v1/stacks?app=example.bidbot" -H "Authorization: Bearer $TOKEN"
```

**Example response**

```json
{
  "stacks": [
    {
      "level": "bySender",
      "app": "example.bidbot",
      "group": "acme",
      "count": 2,
      "expanded": false,
      "members": [
        {
          "app": "example.bidbot",
          "id": "bid-43",
          "title": "Counter-offer from Acme",
          "group": "acme",
          "deliveredAt": "2026-10-02T13:02:11.000Z"
        },
        {
          "app": "example.bidbot",
          "id": "bid-42",
          "title": "Bid accepted",
          "group": "acme",
          "deliveredAt": "2026-10-02T13:00:04.237Z"
        }
      ],
      "frame": {"x": 1508, "y": 44, "width": 400, "height": 96}
    }
  ]
}
```

**Response fields**

| Field | Type | Description |
|---|---|---|
| `stacks[].level` | string | The level that formed the stack: `byApp`, `byIssuer` or `bySender`. |
| `stacks[].app` | string | The app id, or the product family for `byApp`. |
| `stacks[].group` | string | The group that keys the stack. Without a `group`, it is the app id. |
| `stacks[].count` | integer | How many notifications are in the stack. |
| `stacks[].expanded` | boolean | `true` when the stack is open as a list. |
| `stacks[].members` | array | The notifications, newest first. The first is the card on top. |
| `stacks[].frame` | object | Where the stack is on screen, in points. Absent when it has no panel. |

**Notes**

- When nothing is stacked the reply is an empty list.

### `POST /v1/stacks/expand`

Opens a stack into a list of its banners, or closes it back into one card. This is what a click on the stack
does.

**Request**

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `app` | body | string | yes | The app whose stack to change. |
| `group` | body | string | no | The stack's group. Default: the app id. |
| `expanded` | body | boolean | no | `true` opens the stack, `false` closes it. Default `true`. |

**Example request**

```sh
curl -s -X POST "$HERALD/v1/stacks/expand" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"app": "example.bidbot", "group": "acme", "expanded": true}'
```

**Example response**

```json
{"ok": true}
```

**Errors**

| Status | When |
|---|---|
| `400` | `app` is missing. |
| `404` | There is no stack of two or more notifications for this app and group. |

### `GET /v1/settings/stacking`

Returns the global stacking level and the levels you can choose from.

**Request**

No parameters.

**Example request**

```sh
curl -s "$HERALD/v1/settings/stacking" -H "Authorization: Bearer $TOKEN"
```

**Example response**

```json
{"level": "bySender", "levels": ["byApp", "byIssuer", "bySender", "never"]}
```

### `PUT /v1/settings/stacking`

Sets the global stacking level. Apps with their own level keep it.

**Request**

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `level` | body | string | yes | `byApp`, `byIssuer`, `bySender` or `never`. |

**Example request**

```sh
curl -s -X PUT "$HERALD/v1/settings/stacking" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"level": "byIssuer"}'
```

**Example response**

```json
{"level": "byIssuer", "levels": ["byApp", "byIssuer", "bySender", "never"]}
```

**Errors**

| Status | When |
|---|---|
| `400` | `level` is missing or not one of the four values. |

**Notes**

- The same value is the `stacking` key of [`PUT /v1/settings`](settings.md#put-v1settings). Use either.
- To give one app its own level, set `stacking` with
  [`PUT /v1/apps/settings`](apps.md#put-v1appssettings).

## Related

- [Stacking reference](../stacking.md): the levels explained with examples, and how a stack looks.
- [Notifications API](notifications.md#post-v1dismissall): `POST /v1/dismissAll` with a `group` closes one stack.
- [`stackBadge` component](../components/stackBadge.md): show the count in your own template.
