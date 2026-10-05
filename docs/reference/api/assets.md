# Assets API

These endpoints manage the files an app's templates draw: Rive animations and images. Upload a file, list what
an app has, and delete what you do not need. The examples use the `$HERALD` and `$TOKEN` variables from
[Connect](README.md#connect).

## What an asset is

An **asset** is a file Herald keeps for one app so that its templates can use it. There are two kinds.

| Kind | Used by | Stored as |
|---|---|---|
| Rive animation | The [`rive` component](../components/rive.md). | `assets/<app>/<id>.riv` in Herald's support folder. |
| Image | The [`image` component](../components/image.md), as a fixed picture or a field value. | `assets/<app>/images/<name>`. |

A notification can already carry a picture in its `image` field. Upload an image as an asset when the same
picture is part of the design, such as a logo, and should not be sent with every notification.

Rive files can also be declared in the app's [manifest](../manifests.md), which installs them when the manifest
is saved. Uploading here is the direct way and needs no manifest.

## Endpoints

| Endpoint | Purpose |
|---|---|
| [`GET /v1/assets`](#get-v1assets) | List an app's Rive files and images. |
| [`POST /v1/assets`](#post-v1assets) | Upload a Rive file or an image. |
| [`DELETE /v1/assets`](#delete-v1assets) | Delete one file. |

### `GET /v1/assets`

Lists the Rive files and images stored for one app, and for each Rive file which templates use it.

**Request**

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `app` | query | string | yes | The app whose assets to list. |

**Example request**

```sh
curl -s "$HERALD/v1/assets?app=example.bidbot" -H "Authorization: Bearer $TOKEN"
```

**Example response**

```json
{
  "app": "example.bidbot",
  "folder": "/Users/you/Library/Application Support/Herald/assets/example.bidbot",
  "limits": {"bytes": 10485760, "riveFiles": 32},
  "assets": [
    {
      "kind": "rive",
      "id": "confetti",
      "file": "confetti.riv",
      "path": "/Users/you/Library/Application Support/Herald/assets/example.bidbot/confetti.riv",
      "bytes": 48211,
      "declared": false,
      "usedBy": ["bid-accepted"],
      "component": {"type": "rive", "path": "confetti.riv"}
    },
    {
      "kind": "image",
      "file": "logo.png",
      "path": "/Users/you/Library/Application Support/Herald/assets/example.bidbot/images/logo.png",
      "bytes": 9120
    }
  ]
}
```

**Response fields**

| Field | Type | Description |
|---|---|---|
| `folder` | string | The app's asset folder. |
| `limits` | object | The largest file in bytes, and how many Rive files an app may hold. |
| `assets[].kind` | string | `rive` or `image`. |
| `assets[].file` | string | The file name. Use it with [`DELETE /v1/assets`](#delete-v1assets). |
| `assets[].path` | string | The full path of the stored file. |
| `assets[].bytes` | integer | The file size. |
| `assets[].id` | string | Rive only: the asset id, which is the file name without `.riv`. |
| `assets[].declared` | boolean | Rive only: `true` when the app's manifest declares this file. |
| `assets[].usedBy` | array | Rive only: the templates that play this animation. |
| `assets[].component` | object | Rive only: a ready `rive` component that plays this file. |

**Errors**

| Status | When |
|---|---|
| `400` | `app` is missing. |

### `POST /v1/assets`

Stores a Rive animation or an image for an app. Uploading a file with the name of an existing one replaces it.

**Request**

Give the file in exactly one of two ways: `path` for a file that is already on this Mac, or `base64` for
content sent in the request.

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `app` | body | string | yes | The app that will own the file. |
| `path` | body | string | no | A file on this Mac. `~` is expanded. |
| `base64` | body | string | no | The file's bytes as base64. Requires `name`. |
| `name` | body | string | no | The file name to store, such as `logo.png`. Default with `path`: the file's own name. |
| `kind` | body | string | no | `rive` or `image`. Default: decided from the file extension. |

**Example request**

```sh
curl -s -X POST "$HERALD/v1/assets" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"app": "example.bidbot", "path": "~/Designs/confetti.riv"}'
```

**Example response**

```json
{
  "ok": true,
  "kind": "rive",
  "app": "example.bidbot",
  "id": "confetti",
  "file": "confetti.riv",
  "path": "/Users/you/Library/Application Support/Herald/assets/example.bidbot/confetti.riv",
  "bytes": 48211,
  "replaced": false,
  "component": {"type": "rive", "path": "confetti.riv"}
}
```

**Response fields**

| Field | Type | Description |
|---|---|---|
| `kind` | string | `rive` or `image`. |
| `file` | string | The stored file name. |
| `path` | string | The full path of the stored file. For an image, use it as an `image` value. |
| `bytes` | integer | The stored size. |
| `replaced` | boolean | `true` when a file with this name existed and was overwritten. |
| `id` | string | Rive only: the asset id to use in a `rive` component. |
| `component` | object | Rive only: a ready `rive` component that plays this file. |
| `format` | string | Image only: the detected format, such as `png`. |

**Errors**

| Status | When |
|---|---|
| `400` | Both or neither of `path` and `base64` were sent, or `name` is missing with `base64`. |
| `400` | The file does not exist, is empty, or its name contains a folder. |
| `400` | The kind cannot be decided from the name, or the bytes are not an image Herald can draw. |
| `413` | The file is larger than 10 MB. |
| `429` | The app already holds 100 images. |

**Notes**

- A request body is limited to 1 MB, so `base64` suits files up to about 700 KB. Use `path` for anything
  larger.
- Images are checked by their bytes, not their names. PNG, JPEG, GIF, WebP, HEIC, TIFF and BMP are accepted.
- An app can hold 32 Rive files and 100 images, each up to 10 MB.

### `DELETE /v1/assets`

Deletes one stored file. Templates are not changed, so the reply tells you which templates still refer to a
deleted animation.

**Request**

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `app` | query | string | yes | The app that owns the file. |
| `file` | query | string | yes | The file name from [`GET /v1/assets`](#get-v1assets), such as `confetti.riv`. |

**Example request**

```sh
curl -s -X DELETE "$HERALD/v1/assets?app=example.bidbot&file=confetti.riv" \
  -H "Authorization: Bearer $TOKEN"
```

**Example response**

```json
{"ok": true, "deleted": "confetti.riv", "stillReferencedBy": ["bid-accepted"]}
```

**Errors**

| Status | When |
|---|---|
| `400` | `app` or `file` is missing, or `file` is not a `.riv` or image file name. |
| `404` | The app has no file with this name. |

**Notes**

- A template that plays a deleted animation draws a labelled placeholder in its place.

## Related

- [Rive in Herald](../rive.md): preparing an animation and driving it from notification fields.
- [`rive` component](../components/rive.md) and [`image` component](../components/image.md).
- [Template bundles](templates.md#get-v1templatesexport): move a template together with its Rive files.
- [MCP tools for templates](../mcp/templates.md#upload_asset): the same operations for an agent.
