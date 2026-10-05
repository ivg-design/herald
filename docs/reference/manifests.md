# Manifests

A manifest is what an app tells Herald about itself: the data it can send, the buttons it offers and the files it
ships. Herald uses it to build the Designer's palette, to draw previews that look like the real thing, to check
templates, and to offer the app's buttons by name. This page is the reference for the manifest object and everything
inside it. The calls that store and read manifests are in the [manifests API](api/manifests.md).

## Concepts

### What a manifest is for

Herald shows any notification without knowing anything about the app that sent it. That works, but a template author
has to guess which fields the app sends and what they look like. A manifest removes the guessing. By registering one,
an app says "I send a `subject`, a `count` and a `receivedAt`, here is an example of each, and I offer these two
buttons". The Designer then lists those fields in its palette, fills the preview with the examples, and warns when a
template binds something that does not exist.

A manifest is optional. Without one, Herald still shows notifications, and a template can still bind any field the
payload carries. With one, designing, previewing and validating all become easier, and the app's buttons can be
offered by id instead of being repeated in every notification.

### One manifest per app

There is one manifest per app id. Saving a manifest replaces the one stored for that app. Herald keeps it in
`~/Library/Application Support/Herald/manifests/APP.json`. Set `HERALD_SUPPORT_DIR` to use another folder.

Send the manifest every time your app starts. It costs one request, it keeps Herald in step with your code, and it
refreshes the animation files the manifest points at.

### Manifest and registration

A manifest and an app's [registration](api/apps.md#post-v1register) are separate. Registration carries the callback
address, the command permission and the app's own name and icon. The manifest carries the app's fields, actions and
assets. When an app has not registered its own name or icon, Herald uses the manifest's `appName` and `icon`. A
registration always wins.

### Who reads it

| Reader | What it uses |
|---|---|
| The Designer | `fields` for the palette and samples, `actions` for the **Actions** tab, `assets` for Rive animations. |
| Previews | The `sample` of each field. |
| The template validator | `fields` to check tokens, `actions` to check `actionRef`, `assets` to check Rive inputs. |
| Notifications | `defaultTemplate`, and `actionIds` to offer actions by name. |
| Agents | The same data through the MCP tools and the `herald://manifests/APP` resource. |

## Manifest object

Only `app` is required. `{"app": "example.bidbot"}` is a valid, empty manifest.

| Field | Type | Required | Description |
|---|---|---|---|
| `app` | string | yes | The app id: the same one notifications are sent with. At most 128 bytes. |
| `appName` | string | no | The display name for banners, History and Settings. Default: the app id. |
| `icon` | string | no | The app's icon: a file path or a `data:image/png;base64,...` URI, at most 256 KB. |
| `version` | integer | no | A number you raise when the fields change. Informational. Must be 1 or greater. Default `1`. |
| `fields` | array | no | The data the app sends. At most 200. See [Fields](#fields). |
| `actions` | array | no | The app's own buttons. At most 32. See [Actions](#actions). |
| `assets` | array | no | Files the app ships, such as Rive animations. At most 32. See [Assets](#assets). |
| `followUp` | object | no | A default follow-up: one action to run when a banner goes unanswered. See [Follow-up](#follow-up). |
| `defaultTemplate` | string | no | The name of the app's template that Herald uses when a notification names none. |
| `family` | string | no | The product family used by `byApp` stacking. Default: the app id up to its first dot. |
| `appBundleId` | string | no | The app's bundle identifier, so an `openApp` action can bring it to the front. |
| `appPath` | string | no | The app's path, ending in `.app`. Used when `appBundleId` finds nothing. |

Three of these fields need a word more:

- `defaultTemplate` makes banners from this app use a template without every notification having to name one. A
  notification's own `template` wins. A template saved by [`set_default_template`](mcp/templates.md#set_default_template)
  writes this field.
- `family` groups several apps into one stack. WebWatcher sends as `webwatcher.web` and `webwatcher.email`, both with
  family `webwatcher`, so the `byApp` level folds them together. Without `family`, the part of the id before the first
  dot is the family. See [Stacking](stacking.md).
- `appBundleId` and `appPath` tell Herald which application "Open" means. [`openApp` actions](actions.md#openapp-action)
  explains the order Herald tries.

**Minimal example**

```json
{"app": "example.bidbot"}
```

**Realistic example**

```json
{
  "app": "example.bidbot",
  "appName": "BidBot",
  "version": 3,
  "family": "bidbot",
  "defaultTemplate": "bid-update",
  "appBundleId": "com.example.bidbot",
  "fields": [
    {"key": "title", "type": "text", "required": true, "sample": "Bid accepted"},
    {"key": "customer", "type": "text", "sample": "Acme"},
    {"key": "amount", "type": "number", "sample": 4200},
    {"key": "closesAt", "type": "date", "sample": "2026-10-09T17:00:00Z"},
    {"key": "link", "type": "url", "sample": "https://example.com/bids/42"},
    {"key": "tags", "type": "list", "sample": ["rfp", "urgent"]},
    {"key": "won", "type": "bool", "sample": true}
  ],
  "actions": [
    {"id": "accept", "label": "Accept", "kind": "callback"},
    {"id": "decline", "label": "Decline", "kind": "callback", "style": "destructive"},
    {"id": "open-link", "label": "Open bid", "kind": "url", "url": "{link}"}
  ],
  "assets": [
    {"id": "bell", "type": "rive", "path": "~/BidBot/bell.riv", "stateMachine": "Main", "inputs": ["count"]}
  ]
}
```

## Fields

A field declares one value the app can send. `key` is the name in the notification, either a top-level key or a key
inside `metadata`, and it is also the name a template binds with `{key}`.

| Field | Type | Required | Description |
|---|---|---|---|
| `key` | string | yes | Letters, digits, `_`, `.` and `-`. At most 128 bytes. Unique in the manifest. |
| `type` | string | no | `text`, `number`, `date`, `url`, `image`, `bool` or `list`. Default `text`. |
| `required` | boolean | no | Marks the field as always sent. Informational: the Designer shows it. |
| `sample` | string, number, boolean or list of strings | no | An example value for previews and the Designer. |

The `type` tells the Designer what the field is: an `image` field offers an image component, a `date` a timestamp, and
so on. It also decides the stand-in the preview uses when you give no `sample`. The stand-ins are listed in
[Sample values](bindings.md#sample-values). An `image` field with no sample shows nothing.

Rules for a `sample`:

- A text sample is at most 16 KB.
- A list sample has at most 100 items and 16 KB in all.
- Numbers and booleans inside a list are kept as text, and `null` items are dropped.
- A nested list or object is rejected.

`{"key": "subject"}` alone is a complete declaration of a text field. Fields you did not declare still arrive in
`metadata`, and a template can bind them by typing the token name.

**Minimal example**

```json
{"key": "subject"}
```

**Realistic example**

```json
{"key": "receivedAt", "type": "date", "required": true, "sample": "2026-10-01T14:14:00Z"}
```

## Actions

The app's own buttons. Declare them once with a stable id, then offer them from a notification with
`"actionIds": ["accept"]` or send them in full as `buttons`. A declared action is not shown on its own: a notification
has to name it. The Designer's sample preview stands in for a notification that names them all, and says so.

An issuer action is one of eight kinds. The fields and behaviour of each kind are in the
[actions reference](actions.md#fields-by-kind).

| Field | Type | Required | Description |
|---|---|---|---|
| `id` | string | no | The stable name that rules and `actionRef` use. Default: a slug of the label, so `Mark as Read` becomes `mark-as-read`. Unique. |
| `label` | string | yes | The button text. At most 1024 bytes. |
| `kind` | string | no | `url`, `callback`, `command`, `script`, `shortcut`, `openApp`, `reply` or `dismiss`. Inferred from the field when omitted. |
| `style` | string | no | `normal`, `prominent`, `destructive` or `cancel`. |
| `url` | string | no | The link, for `url`. At most 2048 bytes. |
| `command` | string | no | The shell command, for `command`. Runs only with the app's command permission. |
| `script` | string | no | A plain file name in Herald's scripts folder, for `script`. Runs only with the app's command permission. |
| `shortcut`, `input` | string | no | The name of an installed Shortcut, and optional text with `{tokens}` to hand it, for `shortcut`. Runs only with the app's command permission. |
| `callback` | object | no | `url` and `payload`, for `callback`. An empty callback means "call the app back". |
| `bundleId`, `path` | string | no | The application to open, for `openApp`. |
| `placeholder`, `voice` | string, boolean | no | The field's hint and a voice switch, for `reply`. |

A manifest can declare `script` and `shortcut` actions. A script is a file name in the scripts folder, not a path. A
`script` or `shortcut` kind without its name is rejected. They run only when the app is allowed to run commands,
scripts and Shortcuts (**Settings > Apps**), and the banner's question names the script with its SHA-256 or the
Shortcut with its input. A manifest cannot declare `snooze`: it changes how the banner behaves, so it is authored in a
template.

```json
[
  {"id": "fwd", "label": "Forward", "kind": "shortcut", "shortcut": "Forward to phone", "input": "{title}"},
  {"id": "log", "label": "Log", "kind": "script", "script": "log.sh"}
]
```

A `url` action whose value is exactly one token, such as `{link}`, is a link taken from the notification. Herald fills it
from the field of that name and leaves the button out when the notification has no value. A button that has nothing to
open never appears. Any other `url` is used as declared.

**Minimal example**

```json
{"label": "Mark as Read", "kind": "callback"}
```

**Realistic example**

```json
[
  {"id": "reply", "label": "Reply", "kind": "reply", "placeholder": "Message to Acme"},
  {"id": "open", "label": "Open BidBot", "kind": "openApp"},
  {"id": "open-link", "label": "Open bid", "kind": "url", "url": "{link}"}
]
```

## Follow-up

A manifest can declare a default follow-up: one action to run when a banner from this app goes unanswered, such as
forwarding it with a Shortcut. It is a suggestion from the app. The person decides: the Designer shows it as **From
the issuer: LABEL after DURATION** with a switch to turn it off, and **Settings > Apps** shows **Declares a follow-up:
LABEL after DURATION**.

| Field | Type | Required | Description |
|---|---|---|---|
| `after` | number or string | yes | Seconds from 5 to 604800, or a string such as `"90s"`, `"10m"` or `"2h"`. |
| `actionRef` | string | no | The id of one of the manifest's `actions`. |
| `action` | object | no | An action written inline. |
| `enabled` | boolean | no | `false` switches it off. Default `true`. |

Give exactly one of `actionRef` and `action`. The kind must be `shortcut`, `script`, `command` or `callback`. A
template's follow-up, and then a notification's, take priority over the manifest's. How the timer works, what the
action receives and what the banner shows is in [Follow-ups](actions.md#follow-ups).

**Minimal example**

```json
{"after": "10m", "actionRef": "fwd"}
```

**Realistic example**

```json
{
  "followUp": {
    "after": "15m",
    "action": {"id": "fwd", "label": "Forward", "kind": "shortcut",
               "shortcut": "Forward to phone", "input": "{title}"}
  }
}
```

A follow-up that runs code needs the app's permission, the same as a button of the same kind. Until you allow it,
the question appears on the banner when the timer ends and nothing runs.

## Assets

An asset is a file the app ships for templates to use, such as a Rive animation. A `rive` component names the
asset by its `id`, so the template survives the file moving, and the asset travels inside exported template bundles.

| Field | Type | Required | Description |
|---|---|---|---|
| `id` | string | yes | Letters, digits, `_`, `.` and `-`. Unique. What a `rive` component's `asset` names. |
| `type` | string | yes | The kind of file. Herald installs `rive`. |
| `path` | string | yes | Where the file is. At most 2048 bytes. See below. |
| `stateMachine` | string | no | The state machine components use when they name none. |
| `inputs` | array of strings | no | The input names the file has. Herald uses them to warn about a misspelt binding. |

The `path` is an absolute path, a `~/` path, a `file://` URL, or a name inside the app's assets folder. A relative path
may not climb out of that folder, and web addresses are refused. When you save the manifest, Herald copies each file to
`~/Library/Application Support/Herald/assets/APP/ID.riv`. The copy is refreshed only when the content changed. A file
that cannot be installed is reported when a banner tries to draw it. It never blocks the manifest.

**Minimal example**

```json
{"id": "bell", "type": "rive", "path": "~/BidBot/bell.riv"}
```

**Realistic example**

```json
{"id": "bell", "type": "rive", "path": "bell.riv", "stateMachine": "Main", "inputs": ["count", "hover"]}
```

The animation guide is [Rive](rive.md). Files can also be uploaded with the [assets API](api/assets.md).

## Validation

Herald checks the whole manifest and reports every problem at once, so you can fix them in one pass. A bad manifest is
rejected with status `400` and an `error` that begins `invalid manifest:` and lists each problem, separated by
semicolons.

```json
{
  "error": "invalid manifest: fields[1].key 'sub ject' must be letters, digits, '_', '.' or '-' (it is the name used as {key} in bindings); actions[2].id 'archive' is declared twice"
}
```

The rules:

- `app` is required and is at most 128 bytes.
- `version` is 1 or greater.
- A field `key` is made of letters, digits, `_`, `.` and `-`, and is unique.
- An action has a label, a `kind` from the eight issuer kinds, a `shortcut` or `script` name when it has that kind, and a `style` of `default`, `normal`, `prominent`,
  `destructive` or `cancel`.
- Action ids are unique, whether declared or taken from the label.
- `appBundleId` looks like `com.example.App`: two or more parts of letters, digits, `-` and `_`, separated by dots.
- `appPath` ends in `.app`.
- An asset has a unique `id` made of letters, digits, `_`, `.` and `-`, and it has a `type` and a `path`.

The limits:

| Limit | Value |
|---|---|
| Fields, actions, assets in one manifest | 200, 32 and 32. |
| `app` | 128 bytes. |
| Field `key` | 128 bytes. |
| `appName`, `defaultTemplate`, `family`, `appBundleId`, `appPath`, asset `path` | 2048 bytes each. |
| Action `label` | 1024 bytes. |
| Action `url`, `command`, `style`, `bundleId`, `path` | 2048 bytes each. |
| `icon` | 256 KB. |
| A field `sample` | 16 KB, and 100 list items. |
| Manifests, and registered apps | 200 each. A new one beyond that gets `429`. |
| Request body | 1 MB. |

## Agents as issuers

Installing the MCP server in a client registers a manifest for it, so the agent's notifications get a template of their
own. The manifest has family `agent` and `defaultTemplate` `agent`. Cloud agents that reach Herald through the relay use
family `cloud`.

| Client | App id |
|---|---|
| Claude Code | `agent.claude-code` |
| Codex | `agent.codex` |
| Claude Desktop | `agent.claude-desktop` |
| Another client | `agent.NAME` |

The manifest declares these fields, each with a sample.

| Field | Type | Description |
|---|---|---|
| `title` | text | Required. The headline. |
| `body` | text | The detail. |
| `status` | text | `done`, `failed`, `waiting` or `question`, shown as the badge. |
| `project`, `session`, `task`, `tool`, `duration` | text | Further text fields the agent can fill. |
| `link` | `url` | A link to open. |
| `needsInput` | `bool` | Whether the agent waits for you. |

Its actions are:

| Id | Kind | What it does |
|---|---|---|
| `open` | `openApp` | Brings the host application to the front. Set by the manifest's `appBundleId`. Local agents only. |
| `reply` | `reply` | Shows a text field in the banner. |
| `record` | `reply` | Records a voice reply. Cloud agents only. |
| `open-link` | `url` | Opens `{link}`. Appears only when the notification has a `link`. |

There is no `dismiss`: the banner's close button already does that. Herald rewrites this manifest on every install, so
edit the agent's **template**, not its manifest, because the template is kept. See [MCP](../MCP.md).

## Writing a good manifest

- Declare every field a template might bind, with a realistic `sample`, so previews look like the real thing.
- Give actions stable ids. A user's action rules and `actionRef` bindings depend on them.
- Set `family` when several apps belong to one product and you want `byApp` stacking to fold them together.
- Ship Rive files as assets and let templates name the asset id.
- Set `appBundleId` or `appPath` if your app has an **Open** button.

## Where manifests are used

The calls are documented once, each in its own block. Pick the way in you use.

| Task | HTTP API | MCP tool |
|---|---|---|
| Save a manifest | [`PUT /v1/manifest`](api/manifests.md#put-v1manifest) | [`put_manifest`](mcp/templates.md#put_manifest) |
| Read one manifest | [`GET /v1/manifest`](api/manifests.md#get-v1manifest) | [`get_manifest`](mcp/templates.md#get_manifest) |
| List every manifest | [`GET /v1/manifests`](api/manifests.md#get-v1manifests) | [`list_manifests`](mcp/templates.md#list_manifests) |
| Delete a manifest | [`DELETE /v1/manifest`](api/manifests.md#delete-v1manifest) | [`delete_manifest`](mcp/templates.md#delete_manifest) |

An agent can also read a manifest as the resource `herald://manifests/APP`. The only manifest command in the CLI is
[`herald manifest delete`](cli.md#herald-manifest-delete), which deletes one.

## Related

- [Manifests API](api/manifests.md): store, read and delete manifests.
- [Actions](actions.md): the kinds, fields and rules behind a manifest's `actions`.
- [Follow-ups](actions.md#follow-ups): the timer, the approval and what the banner shows.
- [Two-way notifications](../ACTIONS.md): offer a declared action from a notification.
- [Rive](rive.md): the animations a manifest's `assets` ship.
- [Stacking](stacking.md): what `family` does.
- [BidBot example](../examples/bidbot/README.md): an app that registers a manifest and sends notifications.
