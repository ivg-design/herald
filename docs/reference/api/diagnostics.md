# Diagnostics API

These endpoints help you check Herald without showing anything on screen: confirm that it is running, draw the
Designer window to an image, and load a Rive animation to see what is inside it. They are made for test
scripts and for agents that must verify their work. The examples use the `$HERALD` and `$TOKEN` variables from
[Connect](README.md#connect).

## Checking without a window

A banner is a window, and a test that opens windows disturbs whoever is using the Mac. The endpoints here do
the same work **offscreen**: Herald runs the real code and hands back the result as data or as a picture.
Nothing appears, nothing takes focus, and nothing is stored in History.

To render a banner template offscreen, use [`POST /v1/preview`](templates.md#post-v1preview) in the Templates
API. This page covers the rest.

## Endpoints

| Endpoint | Purpose |
|---|---|
| [`GET /v1/health`](#get-v1health) | Check that Herald is running. |
| [`GET /v1/designer/snapshot`](#get-v1designersnapshot) | Draw the Designer window to a PNG. |
| [`POST /v1/designer/snapshot`](#post-v1designersnapshot) | The same, with the options in a JSON body. |
| [`POST /v1/rive/check`](#post-v1rivecheck) | Load a Rive component and report what it contains. |

### `GET /v1/health`

Tells you that Herald is running and which version it is. It is the only endpoint that needs no token, so a
program can use it to detect Herald before it has read the token file.

**Request**

No parameters.

**Example request**

```sh
curl -s "$HERALD/v1/health"
```

**Example response**

```json
{"ok": true, "pid": 4821, "version": "1.8.1"}
```

**Response fields**

| Field | Type | Description |
|---|---|---|
| `ok` | boolean | Always `true`. |
| `pid` | integer | The process id of the running Herald. |
| `version` | string | The version of the running Herald. |

**Notes**

- If the request cannot connect, Herald is not running, or it listens on another port. Read the `port` file
  again.

### `GET /v1/designer/snapshot`

Draws the content of the Designer window to a PNG image, without opening the window. Use it to verify a
layout, or to capture what the Designer shows for a template.

**Request**

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `app` | query | string | no | The app whose templates the Designer shows. |
| `template` | query | string | no | The saved template to open. |
| `select` | query | string | no | The id of a cell to select, so that its inspector is drawn. |
| `width` | query | integer | no | The image width in points, from 600 to 4000. Default `1100`. |
| `height` | query | integer | no | The image height in points, from 400 to 3000. Default `820`. |

**Example request**

```sh
curl -s "$HERALD/v1/designer/snapshot?app=example.bidbot&template=bid-accepted&select=title" \
  -H "Authorization: Bearer $TOKEN" -o designer.png
```

**Example response**

The reply is the image itself, with `Content-Type: image/png`.

```text
designer.png: PNG image data, 2200 x 1640, 8-bit/color RGBA
```

**Errors**

| Status | When |
|---|---|
| `400` | `width` or `height` is out of range. |

**Notes**

- A `rive` cell is drawn as a labelled placeholder, as in a banner preview.

The picture is the whole Designer window, like this one:

![The Designer window as drawn by a snapshot, with a title text cell selected](../../../web/public/shots/docs/designer-cell-selected.png "A snapshot with select set to a cell id shows that cell selected and its properties in the inspector.")

### `POST /v1/designer/snapshot`

The same snapshot, with the options sent as a JSON object. Use this form when you already build JSON bodies
for the other endpoints.

**Request**

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `app` | body | string | no | The app whose templates the Designer shows. |
| `template` | body | string | no | The saved template to open. |
| `select` | body | string | no | The id of a cell to select. |
| `width` | body | integer | no | From 600 to 4000. Default `1100`. |
| `height` | body | integer | no | From 400 to 3000. Default `820`. |

**Example request**

```sh
curl -s -X POST "$HERALD/v1/designer/snapshot" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"app": "example.bidbot", "template": "bid-accepted", "width": 1400, "height": 900}' \
  -o designer.png
```

**Example response**

The reply is a PNG image, as for [`GET /v1/designer/snapshot`](#get-v1designersnapshot).

```text
designer.png: PNG image data, 2800 x 1800, 8-bit/color RGBA
```

**Errors**

| Status | When |
|---|---|
| `400` | `width` or `height` is out of range. |

**Notes**

- Options may also be sent in the query string. A key in the body wins over the same key in the query.

### `POST /v1/rive/check`

Loads a `rive` component the way a banner would, with no window, and reports what it found: whether the file
loads, its artboards, state machines and inputs, and which input values your notification fields would set.
It can also simulate the pointer, so you can see what a hover or a click would do. Nothing is shown or stored,
and no action is run.

Use it after uploading an animation and before putting it in a template, because a preview image cannot play
Rive. The walk-through is in [Rive: testing without a window](../rive.md#testing-without-a-window).

**Request**

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `app` | body | string | yes | The app that owns the animation. |
| `component` | body | object | yes | A [`rive` component](../components/rive.md) object, as it would appear in a cell. |
| `fields` | body | object | no | Notification field values to apply: strings, numbers, booleans or lists of strings. |
| `simulate` | body | array | no | Pointer steps to run in order: `hoverIn`, `hoverOut`, `pressDown`, `pressUp`. |

**Example request**

```sh
curl -s -X POST "$HERALD/v1/rive/check" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{
    "app": "webwatcher.email",
    "component": {
      "type": "rive",
      "asset": "bell",
      "stateMachine": "Main",
      "inputBindings": {"count": "{count}", "hover": "hover"},
      "actionRef": "markRead"
    },
    "fields": {"count": 3},
    "simulate": ["hoverIn", "pressDown", "pressUp", "hoverOut"]
  }'
```

**Example response**

```json
{
  "loaded": true,
  "inputs": {"count": "number", "hover": "bool"},
  "applied": {"count": "3.0"},
  "artboards": [
    {
      "name": "Bell",
      "width": 64,
      "height": 64,
      "defaultMachine": "Main",
      "machines": [
        {
          "name": "Main",
          "inputs": [{"name": "count", "kind": "number"}, {"name": "hover", "kind": "bool"}]
        }
      ],
      "animations": []
    }
  ],
  "takesClicks": true,
  "pointerWrites": {"hover": "false"},
  "clickedActions": ["markRead"]
}
```

**Response fields**

| Field | Type | Description |
|---|---|---|
| `loaded` | boolean | `true` when the animation loads and plays. |
| `error` | string | Why it did not load, in the words the banner's placeholder would show. |
| `inputs` | object | The inputs of the state machine in use, each as `number`, `bool` or `trigger`. |
| `applied` | object | The values written to inputs from `fields`, as text. |
| `artboards` | array | Every artboard in the file with its size, state machines and animations. |
| `takesClicks` | boolean | `true` when the component captures clicks. `false` lets them reach the banner. |
| `pointerWrites` | object | The last value each simulated pointer step wrote to an input. |
| `clickedActions` | array | The ids of the actions a simulated click would run. They are not run. |

**Errors**

| Status | When |
|---|---|
| `400` | `app` is missing, or `component` is not a valid `rive` component. |

**Notes**

- A file that cannot be loaded is not an error status. The reply is `200` with `loaded: false` and an
  `error`.

## Related

- [Testing Herald](../../TESTING.md): running a second instance and the test suites.
- [Templates API](templates.md#post-v1preview): render a banner template to an image.
- [Rive in Herald](../rive.md): preparing an animation and binding its inputs.
- [MCP tools for templates](../mcp/templates.md#rive_check): `rive_check` and `designer_snapshot` for an agent.
