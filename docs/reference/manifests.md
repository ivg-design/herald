# Manifests

A **manifest** is what an issuing app tells Herald about itself: the data it can send (fields, with types and
sample values), the buttons it offers (actions) and the files it ships (Rive assets). The Designer, the
validator, the MCP server and the previews all read it. A manifest is optional: without one Herald still shows
notifications, and templates still bind to any field the payload carries.

One manifest per `app` id. `PUT /v1/manifest` replaces the previous one. Stored at
`~/Library/Application Support/Herald/manifests/<app>.json` (override the folder with `HERALD_SUPPORT_DIR`).

## Shape

```json
{"app":"webwatcher.email","appName":"WebWatcher - Email","icon":"/path/icon.png","version":1,
 "family":"webwatcher","defaultTemplate":"email-accumulated",
 "fields":[
  {"key":"title","type":"text","required":true,"sample":"2 new from Acme Billing"},
  {"key":"subject","type":"text","sample":"Invoice #4021"},
  {"key":"count","type":"number","sample":2},
  {"key":"image","type":"image","sample":"/path/sample.png"},
  {"key":"receivedAt","type":"date","sample":"2026-10-01T14:14:00Z"},
  {"key":"url","type":"url"},
  {"key":"tags","type":"list","sample":["billing","urgent"]},
  {"key":"unread","type":"bool","sample":true}],
 "actions":[
  {"id":"markRead","label":"Mark as Read","kind":"callback"},
  {"id":"archive","label":"Archive","kind":"callback","style":"destructive"},
  {"id":"open","label":"Open","kind":"url","url":"https://mail.example.com"}],
 "assets":[{"id":"bell","type":"rive","path":"/path/bell.riv","stateMachine":"Main","inputs":["count","hover"]}]}
```

Only `app` is required: `{"app":"x"}` is a valid, empty manifest.

## Top-level properties

| Property | Type | Default | Meaning |
|---|---|---|---|
| `app` | string | required | The issuer id. At most 128 bytes. The same id notifications are sent as. |
| `appName` | string | the app id | Display name for banners, History and Settings. If the issuer did not register its own name, the manifest's `appName` and `icon` are used. `POST /v1/register` always wins. |
| `icon` | string | none | A file path or `data:image/png;base64,...`, at most 256 KB. |
| `version` | integer | 1 | Must be 1 or greater. Informational: bump it when the fields change. |
| `fields` | array | `[]` | The data the issuer sends (below). At most 200. |
| `actions` | array | `[]` | The issuer's own buttons (below). At most 32. |
| `assets` | array | `[]` | Files the issuer ships: Rive animations. At most 32. See [rive.md](rive.md). |
| `defaultTemplate` | string | none | Name of the template (of this app) used when a notification names none. |
| `appBundleId` | string | none | The issuing application's bundle identifier (`com.ivg.webwatcher`), so an `openApp` action and a template's `onClick: openApp` can bring it to the front. See [actions.md](actions.md#open-app). |
| `appPath` | string | none | The issuing application's path (`/Applications/WebWatcher.app`, must end in `.app`); used when `appBundleId` finds nothing. Without either, the app named `appName` is looked for. |
| `family` | string | the issuer id up to its first dot | The product family `byApp` stacking groups issuers by (`webwatcher` for `webwatcher.web` and `webwatcher.email`). See [stacking.md](stacking.md). |

## Fields

A field declares one token a template can bind. `key` is both the payload name (a top-level key or a
`metadata` key) and the token name (`{key}`).

| Property | Type | Default | Meaning |
|---|---|---|---|
| `key` | string | required | Letters, digits, `_`, `.`, `-`; at most 128 bytes; unique in the manifest. |
| `type` | string | `text` | `text`, `number`, `date`, `url`, `image`, `bool`, `list`. Drives the Designer palette (an `image` field offers an image component, a `date` a timestamp), the number/boolean coercion, and the sample stand-ins. |
| `required` | boolean | none | Informational (the Designer marks it). |
| `sample` | string, number, boolean or list of strings | none | Drives previews and the Designer. Text and list samples are at most 16 KB (lists at most 100 items). |

`{"key":"subject"}` alone is a complete declaration (type text). Fields you did not declare still arrive in
`metadata` and show in the palette as "custom".

## Actions

The issuer's own buttons, offered to the user. An issuer action is one of:

| `kind` | Extra fields | Does |
|---|---|---|
| `url` | `url` | Opens an http, https or mailto URL. |
| `callback` | `callback` (optional `{url?, payload?}`) | Tells the issuing app: POSTs to its callback URL. A bare `"kind":"callback"` means "call the issuer back". |
| `command` | `command` | Runs a shell command, only with the app's command permission. |
| `dismiss` | none | Closes the banner. |

Properties: `id` (stable name that `actionRules.match` and `actionRef` use; derived from the label as a slug
when omitted, `"Mark as Read"` becomes `mark-as-read`; duplicate ids are an error), `label` (required, at most
1024 bytes), `kind`, `style` (`normal`, `prominent`, `destructive`, `cancel`; `default` means `normal`), and the kind-specific fields.

`script`, `shortcut` and `snooze` actions are **not** issuer actions: they are the user's, authored in
templates (the manifest decoder says so: `'shortcut' actions are authored in templates, not declared by an
issuer`).

The manifest's actions are **not shown just because they are declared**. A notification must send them as
`actions` (or `buttons`) in full, or name them with `"actionIds":["markRead"]`. A *sample* preview stands in
for an issuer that names every declared action, and says so. See [actions.md](actions.md).

## Assets

```jsonc
// one entry of "assets"
{"id":"bell","type":"rive","path":"/path/bell.riv","stateMachine":"Main","inputs":["count","hover"]}
```

| Property | Required | Meaning |
|---|---|---|
| `id` | yes | Letters, digits, `_`, `.`, `-`; unique. What a `rive` component's `asset` names. |
| `type` | yes | `"rive"`. |
| `path` | yes | An absolute path, `~/` path, `file://` URL, or a name in the app's assets folder. At most 2048 bytes. |
| `stateMachine` | no | Default state machine for components that name none. |
| `inputs` | no | Input names the file has; used to warn about misspelt bindings. |

On save Herald copies each file into `~/Library/Application Support/Herald/assets/<app>/<id>.riv`. Full guide:
[rive.md](rive.md).

## Limits

| Limit | Value |
|---|---|
| Manifests | 200 (HTTP 429 beyond) |
| Registered apps | 200 (HTTP 429) |
| Fields / actions / assets | 200 / 32 / 32 |
| `app` | 128 bytes |
| `appName`, `defaultTemplate`, `family`, action `url`/`command`/`style` | 2048 bytes |
| Action `label` | 1024 bytes |
| `icon` | 256 KB |
| Sample text | 16 KB |
| Request body | 1 MB |

`PUT /v1/manifest` returns `400 {"error":"invalid manifest: <path>: <why>; ..."}` listing everything wrong at
once, for example `actions[1].kind: 'shortcut' actions are authored in templates, not declared by an issuer`.

## Endpoints

| Call | Use |
|---|---|
| `PUT /v1/manifest` | Create or replace. Body is the manifest. `{"ok":true}`. |
| `GET /v1/manifest?app=` | One manifest, 404 if none. |
| `GET /v1/manifests` | `{"items":[...]}` all of them. |
| `DELETE /v1/manifest?app=` | Delete it and the copies of the assets it declared (files you dropped there stay). 404 if none. |
| MCP `put_manifest`, `get_manifest`, `list_manifests` | The same, see [mcp-tools.md](mcp-tools.md). |
| Resource `herald://manifests/<app>` | The manifest as MCP data. |

There is no `herald` CLI command for manifests; use the API.

## Agents as issuers

Installing an MCP client registers a manifest for it ([../MCP.md](../MCP.md#agents-as-issuers)): app `agent.claude-code`,
`agent.codex`, `agent.claude-desktop` or `agent.<slug>`, `family: "agent"`, `defaultTemplate: "agent"`. It declares `title` (required),
`body`, `status` (`done`, `failed`, `waiting`, `question`: the badge), `project`, `session`, `task`, `tool`, `duration`, `link` (a
`url`) and `needsInput` (a `bool`), each with a sample, and the actions `open` (a link), `reply` (a callback) and `dismiss`. Herald
rewrites it on every install; edit the **template**, not the manifest, because the template is kept.

## A good manifest

- Declare every field a template might bind, with a realistic `sample`, so previews look like the real thing.
- Give actions stable `id`s: users' `actionRules` and `actionRef`s depend on them.
- Set `family` if several issuers belong to one product and you want `byApp` stacking to fold them together.
- Ship Rive files as `assets` and let templates use `asset` ids (they survive moves and travel in bundles).
- Re-send the manifest on every launch of the issuer: it is cheap, and it refreshes copied assets.
