# Manifests API

These endpoints store an app's manifest: save one, read it, list them all, delete one. Use them when your app
sends its own named fields, offers reusable buttons, ships Rive animations, or should have a default template.
The examples use the `$HERALD` and `$TOKEN` variables from [Connect](README.md#connect).

## What a manifest is

A **manifest** is an app's description of itself for Herald. It answers three questions:

- **What data does the app send?** A list of fields, each with a key, a type and a sample value. The Designer
  offers these fields as tokens to bind, and previews draw the sample values.
- **What buttons does the app offer?** A list of actions with ids. A notification can then name actions by id
  in `actionIds`, without repeating each button.
- **What files does it ship?** Rive animations that Herald copies into the app's asset folder.

A manifest is optional. Without one, Herald still shows the app's notifications; you only lose named fields in
the Designer, sample previews and the default template. Every field of the manifest object is documented in
the [manifest reference](../manifests.md). This page covers the endpoints.

## Endpoints

| Endpoint | Purpose |
|---|---|
| [`PUT /v1/manifest`](#put-v1manifest) | Create or replace an app's manifest. |
| [`GET /v1/manifest`](#get-v1manifest) | Read one app's manifest. |
| [`GET /v1/manifests`](#get-v1manifests) | List every manifest. |
| [`DELETE /v1/manifest`](#delete-v1manifest) | Delete an app's manifest. |

### `PUT /v1/manifest`

Creates an app's manifest or replaces the one it has. The manifest is validated first. Herald then copies the
Rive files it declares into the app's asset folder.

**Request**

The body is one manifest object. Only `app` is required. The most used fields are below; the complete list is
in the [manifest reference](../manifests.md).

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `app` | body | string | yes | The app the manifest describes. |
| `appName` | body | string | no | The display name. A name set with `POST /v1/register` wins over it. |
| `fields` | body | array | no | The fields the app sends: `key`, `type`, `sample`, `required`. |
| `actions` | body | array | no | The buttons the app offers: `id`, `label`, `kind`. |
| `assets` | body | array | no | Rive files to install: `id`, `type`, `path`. |
| `defaultTemplate` | body | string | no | The template used when a notification names none. |

**Example request**

```sh
curl -s -X PUT "$HERALD/v1/manifest" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{
    "app": "example.bidbot",
    "appName": "BidBot",
    "fields": [
      {"key": "title", "type": "text", "required": true, "sample": "Bid accepted"},
      {"key": "amount", "type": "text", "sample": "$4,200"},
      {"key": "link", "type": "url", "sample": "https://example.com/bids/42"}
    ],
    "actions": [
      {"id": "open", "label": "Open bid", "kind": "url", "url": "{link}"},
      {"id": "accept", "label": "Accept", "kind": "callback"}
    ],
    "defaultTemplate": "bid-accepted"
  }'
```

**Example response**

```json
{"ok": true}
```

**Errors**

| Status | When |
|---|---|
| `400` | The manifest is invalid. The message starts with `invalid manifest:` and names the path. |
| `429` | The app is new and 200 manifests, or 200 apps, already exist. |
| `500` | The file could not be written. |

**Notes**

- A validation message names where the problem is, for example
  `invalid manifest: actions[1].kind: 'shortcut' actions are authored in templates`.
- A Rive file that cannot be installed does not block the manifest. The problem is reported when a banner
  tries to draw the animation. Check a file with [`POST /v1/rive/check`](diagnostics.md#post-v1rivecheck).

### `GET /v1/manifest`

Returns one app's manifest.

**Request**

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `app` | query | string | yes | The app whose manifest to read. |

**Example request**

```sh
curl -s "$HERALD/v1/manifest?app=example.bidbot" -H "Authorization: Bearer $TOKEN"
```

**Example response**

```json
{
  "app": "example.bidbot",
  "appName": "BidBot",
  "version": 1,
  "fields": [
    {"key": "title", "type": "text", "required": true, "sample": "Bid accepted"},
    {"key": "amount", "type": "text", "sample": "$4,200"},
    {"key": "link", "type": "url", "sample": "https://example.com/bids/42"}
  ],
  "actions": [
    {"id": "open", "label": "Open bid", "kind": "url", "url": "{link}"},
    {"id": "accept", "label": "Accept", "kind": "callback"}
  ],
  "assets": [],
  "defaultTemplate": "bid-accepted"
}
```

**Errors**

| Status | When |
|---|---|
| `400` | `app` is missing. |
| `404` | The app has no manifest. |

### `GET /v1/manifests`

Lists the manifests of every app. Each item is a whole manifest object, as returned by
[`GET /v1/manifest`](#get-v1manifest).

**Request**

No parameters.

**Example request**

```sh
curl -s "$HERALD/v1/manifests" -H "Authorization: Bearer $TOKEN"
```

**Example response**

```json
{
  "items": [
    {
      "app": "example.bidbot",
      "appName": "BidBot",
      "version": 1,
      "fields": [{"key": "title", "type": "text", "required": true, "sample": "Bid accepted"}],
      "actions": [{"id": "open", "label": "Open bid", "kind": "url", "url": "{link}"}],
      "assets": [],
      "defaultTemplate": "bid-accepted"
    }
  ]
}
```

### `DELETE /v1/manifest`

Deletes an app's manifest and the copies of the Rive files it declared. The app, its templates and its History
stay.

**Request**

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `app` | query | string | yes | The app whose manifest to delete. |

**Example request**

```sh
curl -s -X DELETE "$HERALD/v1/manifest?app=example.bidbot" -H "Authorization: Bearer $TOKEN"
```

**Example response**

```json
{"ok": true}
```

**Errors**

| Status | When |
|---|---|
| `400` | `app` is missing. |
| `404` | The app has no manifest. |

## Related

- [Manifest reference](../manifests.md): every field of the manifest object and its validation rules.
- [Bindings and tokens](../bindings.md): how a manifest field becomes a `{token}` in a template.
- [Actions reference](../actions.md): the action kinds a manifest can declare.
- [MCP tools for templates](../mcp/templates.md#put_manifest): the same operations for an agent.
