# Cloud relay tools

These MCP tools set up and manage the cloud relay from an agent running on the user's Mac: store the Cloudflare token,
deploy the relay, pair this Mac, create and revoke the keys that cloud agents use, and check that everything works. They
are for an agent that is asked "set up the cloud relay" or "give my cloud agent a key". Cloud agents themselves do not use
these tools: they talk to the relay's own remote endpoint, described in [Relay API](../relay-api.md). Each tool here
wraps one route of the local [relay API](../api/relay.md).

## Concepts

**The cloud relay** is a small Cloudflare Worker in the user's own Cloudflare account. A cloud agent cannot reach a Mac,
so it puts notifications into a mailbox on the relay, and Herald, which keeps one outbound connection open to it, takes them
out and shows them as banners. Nothing is opened on the Mac and there is no shared relay: every user deploys their own.
[Cloud relay](../../CLOUD.md) explains the design and the free plan limits, and
[How the cloud relay works](../../cloud/how-it-works.md) covers security.

**The setup order.** Set the relay up in this order. The setup state in [`relay_status`](#relay_status) (`setup.state`)
tells you where you are; the states are listed in its reply, under **Response fields**.

1. [`relay_status`](#relay_status): read the state. Skip the steps that are already done.
2. [`relay_token_url`](#relay_token_url): get the page where the user creates a Cloudflare API token.
3. The user creates the token and gives it to you.
4. [`relay_set_cloudflare_token`](#relay_set_cloudflare_token): store it.
5. [`relay_deploy`](#relay_deploy): deploy the relay and pair this Mac. The state becomes `online`.
6. [`relay_test`](#relay_test): send a test notification through the relay.
7. [`create_agent_key`](#create_agent_key) or [`relay_instructions`](#relay_instructions): connect a cloud agent.

A custom domain is optional: [`relay_zones`](#relay_zones) lists the zones, then [`relay_settings`](#relay_settings) sets
`customDomain`.

**What needs the user.** Some steps cannot be done by an agent, on purpose.

| Step | Why the user does it |
|---|---|
| Create the Cloudflare API token | The token is the user's own credential. Herald only opens the page that fills in the permissions. |
| Approve a connector | A connector that signs in with OAuth, such as ChatGPT, is approved on the Mac, in a banner or with a code in **Settings > Cloud**. No tool approves it. |
| Delete or unpair | Both revoke every agent key and connector, or remove the relay for good. Ask first. |
| Paste a key into the cloud agent | The agent key is shown once, in the reply to `create_agent_key`. The user, or you on their behalf, puts it in the cloud agent's connector settings. |

**Secrets are never returned.** The Cloudflare API token is stored on this Mac and no tool or route reads it back. The
pairing secret is write-only: `relay_settings` reports only whether one is set. Agent keys are stored on the relay as a hash,
so the one secret you ever see is the key in the reply to `create_agent_key`, once. Do not repeat a token or a key in
messages or logs.

![Settings > Cloud with the relay switched on, showing Online, the connector URL and the agent keys](../../../web/public/shots/docs/settings-cloud-paired.png "Settings > Cloud after setup. Everything on this tab is also reachable through the tools on this page.")

## Tools

- [Status and usage](#status-and-usage)
  - [`relay_status`](#relay_status)
  - [`relay_usage`](#relay_usage)
  - [`relay_test`](#relay_test)
- [Set up the relay](#set-up-the-relay)
  - [`relay_token_url`](#relay_token_url)
  - [`relay_set_cloudflare_token`](#relay_set_cloudflare_token)
  - [`relay_deploy`](#relay_deploy)
  - [`relay_pair`](#relay_pair)
  - [`relay_unpair`](#relay_unpair)
  - [`relay_delete`](#relay_delete)
- [Advanced settings and custom domain](#advanced-settings-and-custom-domain)
  - [`relay_settings`](#relay_settings)
  - [`relay_zones`](#relay_zones)
- [Agent keys and connectors](#agent-keys-and-connectors)
  - [`create_agent_key`](#create_agent_key)
  - [`revoke_agent_key`](#revoke_agent_key)
  - [`list_connectors`](#list_connectors)
  - [`relay_instructions`](#relay_instructions)
- [Reply subscriptions](#reply-subscriptions)
  - [`relay_events`](#relay_events)
  - [`relay_remove_event_subscription`](#relay_remove_event_subscription)

## Status and usage

These tools report the state of the relay, what today's traffic has used, and whether a notification really goes through.
None of them changes the setup.

### `relay_status`

Reports whether this Mac is paired with a relay and online, the relay and connector URLs, the agent keys, the Macs on the
relay and the last 20 relay items with what happened to each. Call it first, and again after any change.

**Arguments**

No arguments.

**Example call**

```json
{}
```

**Example result**

The reply is shortened: `setup.steps` and `setup.usage` are empty here.

```json
{
  "paired": true,
  "state": "Online",
  "online": true,
  "relayURL": "https://herald-relay.example.workers.dev",
  "mcpURL": "https://herald-relay.example.workers.dev/mcp",
  "deviceId": "dev_0000",
  "lastSeenAt": "2026-10-04T10:15:00.000Z",
  "keys": [
    {
      "id": "a1b2c3d4",
      "name": "build-bot",
      "client": "claude",
      "scope": "notify",
      "kind": "static",
      "createdAt": "2026-10-01T09:00:00.000Z",
      "lastUsedAt": "2026-10-04T10:12:00.000Z"
    }
  ],
  "log": [
    {
      "id": "r_0000",
      "key": "build-bot",
      "title": "Build finished",
      "receivedAt": "2026-10-04T10:12:00.000Z",
      "displayed": true,
      "spoken": false,
      "replied": false,
      "duplicate": false
    }
  ],
  "setup": {
    "state": "online",
    "hasToken": true,
    "paired": true,
    "online": true,
    "relayURL": "https://herald-relay.example.workers.dev",
    "mcpURL": "https://herald-relay.example.workers.dev/mcp",
    "workersDevURL": "https://herald-relay.example.workers.dev",
    "customDomainRecommended": true,
    "bundledVersion": "1.0.0",
    "deployedVersion": "1.0.0",
    "updateAvailable": false,
    "steps": []
  },
  "devices": [
    {"id": "dev_0000", "name": "Studio Mac", "online": true, "lastSeenAt": "2026-10-04T10:15:00.000Z", "thisDevice": true, "removable": false}
  ]
}
```

**Response fields**

| Field | Type | Description |
|---|---|---|
| `paired` | boolean | Whether this Mac is paired with a relay. |
| `state` | string | The connection as the Settings screen words it: `Not paired`, `Offline`, `Connecting…`, `Online`, or an offline message with a reason. |
| `online` | boolean | Whether the connection to the relay is up. |
| `relayURL` | string | The relay's address. Empty before the first deploy. |
| `mcpURL` | string | The connector URL for cloud agents: the relay address plus `/mcp`. |
| `deviceId` | string | This Mac's id on the relay. Absent when not paired. |
| `lastSeenAt` | string | When the relay last heard from this Mac. |
| `keys` | array | The agent keys, never a secret. The fields of a key are listed under the table. |
| `log` | array | The last 20 relay items. The flags of an item are listed under the table. |
| `setup` | object | The setup state machine. Its fields are listed under the table. |
| `devices` | array | The Macs on the relay. Absent when not paired. |

The fields of a key in `keys`:

| Field | Meaning |
|---|---|
| `id` | The key's id. |
| `name` | The key's name. |
| `client` | The kind of client the key is for. |
| `scope` | What the key may do. It is `notify`. |
| `kind` | `static` for a key made in Settings or by `create_agent_key`, `oauth` for a connector. |

The fields of a Mac in `devices`:

| Field | Meaning |
|---|---|
| `name` | The Mac's name. |
| `online` | Whether it is connected to the relay. |
| `lastSeenAt` | When the relay last heard from it. |
| `thisDevice` | `true` for this Mac. |
| `removable` | Whether this Mac may remove it. |

Each item of `log` has the `key` that sent it, its `title`, when it arrived, and these flags for what happened:

| Flag | Meaning |
|---|---|
| `displayed` | Herald showed the banner. |
| `spoken` | Herald read the notification aloud. |
| `replied` | The user answered the notification. |
| `duplicate` | The relay had already seen this notification. |
| `suppressed` | Herald held the item back. The flag carries the reason. |

The `setup` object has these fields:

| Field | Meaning |
|---|---|
| `state` | Where setup stands. The values are in the next table. |
| `hasToken` | Whether a Cloudflare API token is stored. |
| `bundledVersion`, `deployedVersion` | The relay version inside this Herald and the one deployed. |
| `updateAvailable` | Whether the deployed relay is older than the bundled one. |
| `steps` | The step log of the last deploy. |
| `message` | A plain sentence, present when something is wrong. |

| `setup.state` | Meaning |
|---|---|
| `token-needed` | No relay is deployed and no Cloudflare token is stored. |
| `ready` | No relay is deployed or paired yet, and a token is stored. |
| `deploying` | A deploy is running. |
| `connecting` | This Mac is paired and the connection is not up yet. |
| `online` | This Mac is paired and connected. |
| `offline` | This Mac is paired and the connection is down. |
| `error` | The last deploy or pairing failed. `message` says why. |

**HTTP route**

[`GET /v1/relay/status`](../api/relay.md#get-v1relaystatus)

**Side effects**

None. Read-only. It asks the relay for the current keys and devices when this Mac is paired.

### `relay_usage`

Reports what today's relay traffic has used of the Cloudflare free plan. Call it when notifications stop arriving, to see
whether a daily limit was reached, or when the user asks how much of the plan is used.

**Arguments**

No arguments.

**Example call**

```json
{}
```

**Example result**

```json
{
  "day": "2026-10-04",
  "requests": 212,
  "wsMessages": 96,
  "notifications": 14,
  "pollSeconds": 0,
  "audioUploads": 0,
  "audioBytes": 0,
  "queued": 0,
  "storageBytes": 24576,
  "requestsPercent": 4,
  "budgetExhausted": false
}
```

**Response fields**

| Field | Type | Description |
|---|---|---|
| `day` | string | The UTC date these counters belong to. They reset daily. |
| `requests` | number | Requests that reached this Mac's mailbox today. |
| `wsMessages` | number | Messages sent over the connection between the relay and this Mac. |
| `notifications` | number | Notifications accepted from agents today. |
| `pollSeconds` | number | Seconds the mailbox held long-poll requests open. |
| `audioUploads` | number | Voice replies uploaded today. `audioBytes` is their total size. |
| `queued` | number | Notifications waiting for this Mac to collect them. |
| `storageBytes` | number | The size of this Mac's mailbox storage. |
| `requestsPercent` | number | `requests` as a percentage of the daily request limit. |
| `budgetExhausted` | boolean | `true` when the daily request limit is reached. The relay refuses requests until the day resets. |

**HTTP route**

[`GET /v1/relay/usage`](../api/relay.md#get-v1relayusage)

**Side effects**

None. Read-only. A Mac that is not paired gets a `409` error.

### `relay_test`

Checks the relay's `/health`, then sends a real test notification through the relay with a temporary key and waits for
its receipt. Call it after `relay_deploy`, or when a cloud agent says it cannot reach the Mac. It also reports whether
Cloudflare's Browser Integrity Check blocks Python's default User-Agent on the relay's hostname.

**Arguments**

No arguments.

**Example call**

```json
{}
```

**Example result**

```json
{
  "healthy": true,
  "paired": true,
  "online": true,
  "roundTrip": true,
  "receipt": "displayed",
  "detail": "A test notification went through the relay and was shown on this Mac. Browser Integrity Check is active on this hostname (expected on workers.dev): Python's default User-Agent (Python-urllib/3.x) is rejected with Error 1010. Agents must send a custom User-Agent such as Herald-Agent/1.0, or set up a custom domain.",
  "browserCheckActive": true
}
```

**Response fields**

| Field | Type | Description |
|---|---|---|
| `healthy` | boolean | Whether the relay answered `GET /health`. |
| `paired` | boolean | Whether this Mac is paired. |
| `online` | boolean | Whether the connection to the relay is up. |
| `roundTrip` | boolean | Whether the test notification came back with a receipt. |
| `receipt` | string | `displayed`, or `suppressed` when the user's settings held the banner back. Absent when there was no round trip. |
| `detail` | string | One or two sentences saying what happened and, on failure, where it stopped. |
| `browserCheckActive` | boolean | `true` when Cloudflare's Browser Integrity Check rejects `Python-urllib/3.x` on this hostname, which is expected on `workers.dev`. `false` when it does not. Absent when Herald could not tell. |

**HTTP route**

[`POST /v1/relay/test`](../api/relay.md#post-v1relaytest)

**Side effects**

Shows a banner titled **Relay test** on this Mac, unless the user's settings hold it back. It makes a temporary key, then removes the key,
the History item and the log line. A relay that is not set up is a `409`.

## Set up the relay

These tools take the relay from nothing to online and back. They are the tools behind **Settings > Cloud > Enable relay**,
**Unpair** and **Delete relay from Cloudflare**.

![The Enable relay sheet in Settings > Cloud, with the Cloudflare token field and the Deploy button](../../../web/public/shots/docs/settings-cloud-deploy.png "The sheet that relay_set_cloudflare_token and relay_deploy do the work of.")

### `relay_token_url`

Returns the Cloudflare page where the user creates the API token that Herald deploys the relay with, and the permissions
the token needs. The page opens with every permission filled in and the token named `Herald relay`. Call it when
`relay_status` shows `token-needed`, then tell the user to open the page, create the token and give it to you.

**Arguments**

No arguments.

**Example call**

```json
{}
```

**Example result**

The `url` is shortened to two permissions and `permissions` to three entries.

```json
{
  "url": "https://dash.cloudflare.com/profile/api-tokens?permissionGroupKeys=%5B%7B%22key%22%3A%22workers_scripts%22%2C%22type%22%3A%22edit%22%7D%5D&accountId=%2A&zoneId=all&name=Herald%20relay",
  "signUpURL": "https://dash.cloudflare.com/sign-up",
  "permissions": [
    {"key": "workers_scripts", "type": "edit", "title": "Workers Scripts: Edit", "why": "upload the relay, switch on its workers.dev address, set its variables"},
    {"key": "workers_r2", "type": "edit", "title": "Workers R2 Storage: Edit", "why": "create the bucket that holds voice replies and its 7-day expiry"},
    {"key": "account_settings", "type": "read", "title": "Account Settings: Read", "why": "find your account id"}
  ],
  "steps": [
    "Open the link (a free Cloudflare account is enough; sign up first if you have none).",
    "Cloudflare shows the token page with the permissions already filled in and the name \"Herald relay\". Press Continue to summary, then Create Token.",
    "Copy the token it shows once, and give it to Herald (Settings > Cloud > Enable relay, or relay_set_cloudflare_token)."
  ]
}
```

**Response fields**

| Field | Type | Description |
|---|---|---|
| `url` | string | Cloudflare's token page, filled in. The user opens it. |
| `signUpURL` | string | Cloudflare's sign-up page, for a user with no account. A free account is enough. |
| `permissions` | array | The nine permissions the token needs, each with `key`, `type` (`edit` or `read`), `title` and `why`. The last six are for the optional custom domain. |
| `steps` | array | The steps to tell the user, in order. |

**HTTP route**

[`GET /v1/relay/token-url`](../api/relay.md#get-v1relaytoken-url)

**Side effects**

None. Read-only. It does not open the page: the user does.

### `relay_set_cloudflare_token`

Stores the Cloudflare API token on this Mac. Herald uses it only to call `api.cloudflare.com` for the deploy, and no tool or
route ever returns it. This is the one tool that carries a secret in its arguments: do not repeat the token in messages or
logs.

**Arguments**

| Name | Type | Required | Description |
|---|---|---|---|
| `token` | string | yes | The API token the user created on the page from `relay_token_url`. It must be at least 20 characters with no spaces. |

**Example call**

```json
{"token": "cf_example_token_value_0000"}
```

**Example result**

```json
{"stored": true}
```

**HTTP route**

[`POST /v1/relay/token`](../api/relay.md#post-v1relaytoken)

**Side effects**

Stores the token in Herald's secret store on this Mac and clears an earlier deploy error. Shows nothing. A value that does not
look like a token is a `400`.

### `relay_deploy`

Deploys the relay Worker to the user's Cloudflare account, waits until it answers, applies the custom domain when one is set
in `relay_settings`, and pairs this Mac with it. Running it again upgrades the Worker in place with the same name, secrets and
data, so it is safe to repeat. It takes up to about a minute.

**Arguments**

No arguments.

**Example call**

```json
{}
```

**Example result**

```json
{
  "deployed": true,
  "upgraded": false,
  "relayURL": "https://herald-relay.example.workers.dev",
  "paired": true,
  "online": true,
  "steps": [
    {"step": "verifyToken", "title": "Check the API token", "phase": "done", "detail": "Token is valid."},
    {"step": "upload", "title": "Upload the relay", "phase": "done", "detail": "Uploaded herald-relay."},
    {"step": "health", "title": "Wait for the relay to answer", "phase": "done", "detail": "The relay answered."}
  ],
  "workersDevURL": "https://herald-relay.example.workers.dev",
  "warnings": []
}
```

**Response fields**

| Field | Type | Description |
|---|---|---|
| `deployed` | boolean | Always `true` on success. |
| `upgraded` | boolean | `true` when a relay was already running and was updated in place. |
| `relayURL` | string | The address Herald and agents should use: the custom domain when one is attached, otherwise the `workers.dev` address. |
| `paired` | boolean | Whether this Mac is paired. |
| `online` | boolean | Whether the connection is up. |
| `steps` | array | The step log. Each step has `step`, `title`, `phase` (`started`, `done` or `failed`) and a `detail` sentence. The example shows three of them. |
| `workersDevURL` | string | The always-on `workers.dev` address. |
| `customURL` | string | The custom domain's address, when one is set up. |
| `warnings` | array | Things the user should know, such as connectors that must be added again after a custom domain, or Bot Fight Mode on the zone. |

**HTTP route**

[`POST /v1/relay/deploy`](../api/relay.md#post-v1relaydeploy)

**Side effects**

Creates or updates a Worker and a storage bucket in the user's Cloudflare account, pairs this Mac and turns the relay on. It
needs the token from `relay_set_cloudflare_token`. An upgrade keeps the signing secret, so the pairing and every key survive.
When a deploy does change it, this Mac pairs again by itself, the step log shows **Pair this Mac again**, a warning says so,
and agent keys and connectors must be created again. Another deploy already running is a `409`.

### `relay_pair`

Pairs this Mac with the configured relay. `relay_deploy` does this itself, so call `relay_pair` only for a relay that already
exists and was not deployed by Herald. Then:

1. Set its address with [`relay_settings`](#relay_settings): `relayURL`, and `pairingSecret` if the relay asks for one.
2. Call `relay_pair`.

**Arguments**

No arguments.

**Example call**

```json
{}
```

**Example result**

```json
{"paired": true, "code": "000000", "deviceId": "dev_0000"}
```

**Response fields**

| Field | Type | Description |
|---|---|---|
| `paired` | boolean | `true` on success. |
| `code` | string | The one-time pairing code Herald used. It is already spent, and the user never types it. |
| `deviceId` | string | This Mac's id on the relay. |

**HTTP route**

[`POST /v1/relay/pair`](../api/relay.md#post-v1relaypair)

**Side effects**

Changes state: this Mac becomes a device on the relay and starts a connection. It shows nothing. A relay address that is
missing or invalid is an error.

### `relay_unpair`

Turns the relay off for this Mac. It revokes every agent key and connector and forgets the pairing. The Worker stays in the
user's Cloudflare account until `relay_delete` removes it. Ask the user first, because every cloud agent loses access.

**Arguments**

No arguments.

**Example call**

```json
{}
```

**Example result**

```json
{"unpaired": true}
```

**HTTP route**

[`POST /v1/relay/unpair`](../api/relay.md#post-v1relayunpair)

**Side effects**

Destructive. Revokes all keys and connectors. If the relay cannot be reached to revoke them, the call fails and changes
nothing.

### `relay_delete`

Deletes the relay Worker from the user's Cloudflare account with every mailbox, key and queued notification, and the voice-reply
bucket when it is empty. Cloud agents lose access for good. Ask the user first: it only runs with `confirm: true`.

**Arguments**

| Name | Type | Required | Description |
|---|---|---|---|
| `confirm` | boolean | yes | Must be `true`. Any other value is refused and nothing is deleted. |

**Example call**

```json
{"confirm": true}
```

**Example result**

```json
{"deleted": true, "note": "The Worker is deleted. The bucket herald-relay-audio still holds voice replies (Cloudflare only deletes empty buckets); delete it in the dashboard under R2."}
```

**Response fields**

| Field | Type | Description |
|---|---|---|
| `deleted` | boolean | `true` when the Worker is gone. |
| `note` | string | What Herald could not remove, for example a bucket that still holds voice replies. Absent when everything was removed. |

**HTTP route**

[`POST /v1/relay/delete`](../api/relay.md#post-v1relaydelete)

**Side effects**

Destructive and not undoable. Unpairs this Mac first, deletes the Worker through the Cloudflare API, and forgets the pairing and
relay secrets and the relay address. The Cloudflare token stays stored.

## Advanced settings and custom domain

The relay has settings: its limits, how long it keeps things, its name and an optional custom domain. These tools read and
change them.

### `relay_settings`

Without arguments, returns every Advanced setting, whether a pairing secret is set, and the deployed state. With `settings`,
validates and saves the ones you list. A change to a value that lives in the Worker, or to the custom domain, redeploys the
relay and the reply says so with the step log. The Cloudflare token is never returned.

**Arguments**

| Name | Type | Required | Description |
|---|---|---|---|
| `settings` | object | no | The settings to change, by name. Omit it to read them. The names, types and ranges are in [`PUT /v1/relay/settings`](../api/relay.md#put-v1relaysettings). |

`customDomain` takes an object with a `zone` and a `hostname`, or `null` to remove it. A custom domain puts the relay on a hostname in the user's own Cloudflare zone, switches Browser Integrity Check off for that hostname only, and points Herald at it. It is optional.

- It lets agents with default library User-Agents work, and gives the relay a stable address.
- Without it, an agent sends a custom User-Agent such as `Herald-Agent/1.0`.
- Pick the zone with [`relay_zones`](#relay_zones).
- It needs the token's Zone permissions from [`relay_token_url`](#relay_token_url).
- Connectors already added to a cloud agent keep the old address and must be added again with the new one.

**Example call**

```json
{"settings": {"maxQueue": 50}}
```

**Example result**

```json
{
  "settings": {
    "accountId": "00000000000000000000000000000000",
    "workerName": "herald-relay",
    "subdomain": "example",
    "bucket": "herald-relay-audio",
    "audioRetentionDays": 7,
    "queueTTLHours": 24,
    "notificationsPerDay": 500,
    "maxQueue": 50,
    "bodyLimitBytes": 32768,
    "ratePerKey": 60,
    "maxDevices": 5,
    "deviceName": "",
    "pingSeconds": 300,
    "deployedHash": "0000000000000000",
    "deployedAt": "2026-10-04T09:00:00.000Z"
  },
  "pairingSecretSet": true,
  "errors": {},
  "redeployed": true,
  "steps": [
    {"step": "upload", "title": "Upload the relay", "phase": "done", "detail": "Uploaded herald-relay."}
  ],
  "warnings": []
}
```

**Response fields**

| Field | Type | Description |
|---|---|---|
| `settings` | object | Every Advanced setting with its value, plus `customDomain` (`zone`, `hostname`, `attached`) when one is set. |
| `pairingSecretSet` | boolean | Whether a pairing secret is stored. The secret itself is never returned. |
| `errors` | object | Setting names that are invalid, each with a reason. Empty after a successful change. |
| `redeployed` | boolean | `true` when the change redeployed the relay. |
| `steps` | array | The deploy's step log. Empty when nothing was redeployed. |
| `warnings` | array | Notes from the deploy, such as connectors that must be added again. |

**HTTP route**

- To read: [`GET /v1/relay/settings`](../api/relay.md#get-v1relaysettings)
- To change: [`PUT /v1/relay/settings`](../api/relay.md#put-v1relaysettings)

**Side effects**

Without `settings`, none. With it, changes the relay's settings, and redeploys the Worker when a value that lives in it, or the
custom domain, changed. An invalid value changes nothing and is a `400`.

### `relay_zones`

Lists the zones (domains) in the user's Cloudflare account that the stored token can see, each with a suggested hostname.
Call it to pick a zone for the `customDomain` setting of `relay_settings`.

**Arguments**

No arguments.

**Example call**

```json
{}
```

**Example result**

```json
{
  "zones": [
    {"id": "00000000000000000000000000000000", "name": "example.com", "status": "active", "suggestedHostname": "herald.example.com"}
  ]
}
```

**Response fields**

| Field | Type | Description |
|---|---|---|
| `zones` | array | One entry per zone: its `id`, `name`, `status` and a `suggestedHostname` of the form `herald.<zone>`. |

**HTTP route**

[`GET /v1/relay/zones`](../api/relay.md#get-v1relayzones)

**Side effects**

None. Read-only. It calls the Cloudflare API with the stored token. A token without the Zone: Read permission fails with a
clear message: the user then creates a new token from the page in `relay_token_url`.

## Agent keys and connectors

A cloud agent signs in to the relay in one of two ways:

- A **key** is a secret string you create here and paste into the agent.
- A **connector** is an agent that signs in with OAuth, such as ChatGPT, and the user approves on the Mac.

Both can send notifications and read their receipts and replies, and nothing else: they cannot run commands, set callbacks or change anything on this Mac. Their notifications arrive as the app `cloud.<name>`. [Connect a cloud agent](../../cloud/connect-agent.md) is the task guide.

### `create_agent_key`

Creates a notify-only key for a cloud agent, the same as **Settings > Cloud > Agent keys**. The reply holds the key once,
because the relay keeps only a hash, and a connector block with the URL and `Bearer` header for Claude, Codex and any remote
MCP client. The Mac must be paired.

**Arguments**

| Name | Type | Required | Description |
|---|---|---|---|
| `name` | string | yes | A short name for the agent: 1 to 32 characters of `a-z`, `0-9` and hyphens, for example `build-bot`. A name already in use is a `409`. |
| `client` | string | no | `claude`, `codex` or `other`. The first two use that product's icon. Default `other`. |

**Example call**

```json
{"name": "build-bot", "client": "claude"}
```

**Example result**

`connectorConfig` is a multi-line text and is shortened here to its first lines.

```json
{
  "id": "a1b2c3d4",
  "name": "build-bot",
  "client": "claude",
  "scope": "notify",
  "key": "hrk_...",
  "mcpURL": "https://herald-relay.example.workers.dev/mcp",
  "connectorConfig": "# Herald cloud relay: notifications only (send_notification, get_receipt, wait_for_reply, herald_status)\n# Key \"build-bot\". It is shown once. Anyone holding it can notify you, nothing else. Revoke it in Herald > Settings > Cloud.\n\nURL:            https://herald-relay.example.workers.dev/mcp\nAuthorization:  Bearer hrk_..."
}
```

**Response fields**

| Field | Type | Description |
|---|---|---|
| `id` | string | The key's id, 8 hex characters. Pass it to `revoke_agent_key`. |
| `name` | string | The key's name. Its notifications arrive as `cloud.<name>`. |
| `client` | string | `claude`, `codex` or `other`. |
| `scope` | string | Always `notify`. |
| `key` | string | The secret. Shown once. |
| `mcpURL` | string | The connector URL for the agent. |
| `connectorConfig` | string | A ready-to-paste block: the URL and header for any remote MCP client, then the Claude Code command, a `.mcp.json` entry and the Codex configuration. |

**HTTP route**

[`POST /v1/relay/keys`](../api/relay.md#post-v1relaykeys)

**Side effects**

Creates a key on the relay and registers the app `cloud.<name>` on this Mac. A Mac that is not paired is a `409`. At most 20
keys can be active at once.

### `revoke_agent_key`

Revokes a key or a connector by its id. It stops working at once, and notifications it already queued are still delivered.
Call it when a cloud agent should lose access, or to remove a connector from [`list_connectors`](#list_connectors).

**Arguments**

| Name | Type | Required | Description |
|---|---|---|---|
| `id` | string | yes | The key id, 8 hex characters, from `relay_status` or `list_connectors`. |

**Example call**

```json
{"id": "a1b2c3d4"}
```

**Example result**

```json
{"revoked": true, "id": "a1b2c3d4"}
```

**HTTP route**

[`DELETE /v1/relay/keys/{id}`](../api/relay.md#delete-v1relaykeysid)

**Side effects**

Destructive. The agent cannot send again, and its reply subscriptions end. A malformed id is a `400`, and an unknown one is
an error from the relay.

### `list_connectors`

Lists the connectors that signed in to the relay with OAuth, such as ChatGPT and clients that cannot send a custom key, and
the requests still waiting for the user's approval. A connector appears as an agent key of kind `oauth`, so
`revoke_agent_key` removes it. Approval happens only on the Mac, in a banner or with the 6-digit code in **Settings > Cloud**:
no tool approves a request, and the approval code is never returned.

**Arguments**

No arguments.

**Example call**

```json
{}
```

**Example result**

```json
{
  "connectors": [
    {
      "id": "e5f6a7b8",
      "name": "chatgpt",
      "client": "other",
      "scope": "notify",
      "kind": "oauth",
      "displayName": "ChatGPT",
      "createdAt": "2026-10-02T14:00:00.000Z",
      "lastUsedAt": "2026-10-04T08:30:00.000Z"
    }
  ],
  "pending": [
    {
      "id": "req_0000",
      "clientName": "My agent",
      "redirectHost": "agent.example.com",
      "expiresAt": "2026-10-04T10:25:00.000Z",
      "userCode": "BDFG-HJKM"
    }
  ]
}
```

**Response fields**

| Field | Type | Description |
|---|---|---|
| `connectors` | array | The approved connectors, in the same shape as the keys in `relay_status`. `displayName` is the connector's own name and `name` is its slug. |
| `pending` | array | Requests waiting for approval, each with `id`, the `clientName` it gave, the `redirectHost` it will return to, and when it expires. |
| `pending[].userCode` | string | The code the agent printed, for an agent that signs in without a browser (the device flow). Use it to tell the user which request is which. Absent for other requests. |

**HTTP route**

[`GET /v1/relay/connectors`](../api/relay.md#get-v1relayconnectors)

**Side effects**

None. Read-only.

### `relay_instructions`

Returns the exact text to give a cloud agent so that it connects: the connector URL, the steps and the User-Agent note. Call it
after the relay is online, then show or paste the text for the user.

**Arguments**

| Name | Type | Required | Description |
|---|---|---|---|
| `client` | string | yes | The kind of agent: `chatgpt`, `claude`, `codex` or `device`. The values are explained under the table. |

The `client` values:

| Value | For |
|---|---|
| `chatgpt` | ChatGPT and other OAuth connectors. |
| `claude` | A static key made with `create_agent_key`, for Claude. |
| `codex` | A static key made with `create_agent_key`, for Codex. |
| `device` | An agent with no usable browser, which uses the OAuth device flow. |

**Example call**

```json
{"client": "claude"}
```

**Example result**

The `text` is shortened to its first lines.

```json
{
  "client": "claude",
  "text": "Claude Code / Codex CLI (a static key)\n\nClaude Code:\nclaude mcp add --transport http herald https://herald-relay.example.workers.dev/mcp --header \"Authorization: Bearer <your key>\"\n\nAny other MCP client: URL https://herald-relay.example.workers.dev/mcp, header Authorization: Bearer <your key>"
}
```

**Response fields**

| Field | Type | Description |
|---|---|---|
| `client` | string | The value you sent. |
| `text` | string | The instructions, as plain text with the relay's real URL in them. A key appears as the placeholder `<your key>`: put the real key in yourself. |

**HTTP route**

[`GET /v1/relay/instructions`](../api/relay.md#get-v1relayinstructions)

**Side effects**

None. Read-only. Any other `client` value is a `400`.

## Reply subscriptions

A cloud agent can ask the relay to call it when the user replies to one of its notifications, instead of polling. That request is
a **subscription**. A connector's approval is all a subscription needs, so the user does nothing more. These tools show the live
subscriptions and end one. [Reply events](../../cloud/reply-events.md) explains how an agent subscribes.

### `relay_events`

Lists the live reply subscriptions: which connector is called, at which host, and how many events are waiting for it. It never
returns a URL path or a secret.

**Arguments**

No arguments.

**Example call**

```json
{}
```

**Example result**

```json
{
  "restrictedTo": [],
  "subscriptions": [
    {
      "id": "sub_00000000000000000000",
      "event": "notification.reply",
      "host": "agent.example.com",
      "key": {"id": "e5f6a7b8", "name": "chatgpt", "displayName": "ChatGPT"},
      "createdAt": "2026-10-03T12:00:00.000Z",
      "pending": 0
    }
  ]
}
```

**Response fields**

| Field | Type | Description |
|---|---|---|
| `restrictedTo` | array | The hosts the relay's owner limited callbacks to. Empty means any public host. |
| `subscriptions` | array | The live subscriptions. |
| `subscriptions[].id` | string | The subscription id: `sub_` and 20 hex characters. |
| `subscriptions[].event` | string | The event. It is `notification.reply`. |
| `subscriptions[].host` | string | The host the relay calls. |
| `subscriptions[].key` | object | The connector that owns it: `id`, `name` and `displayName`. |
| `subscriptions[].pending` | number | Events queued for this subscription that its callback has not accepted yet. |

**HTTP route**

[`GET /v1/relay/events`](../api/relay.md#get-v1relayevents)

**Side effects**

None. Read-only. A Mac that is not paired gets a `409` error.

### `relay_remove_event_subscription`

Ends one reply subscription. The connector stays approved and can subscribe again. Call it when a cloud agent should stop
being called, but keep its access. To remove the agent entirely, use `revoke_agent_key`, which ends all of its subscriptions.

**Arguments**

| Name | Type | Required | Description |
|---|---|---|---|
| `id` | string | yes | The subscription id, `sub_` and 20 hex characters, from `relay_events`. |

**Example call**

```json
{"id": "sub_00000000000000000000"}
```

**Example result**

```json
{"removed": true, "id": "sub_00000000000000000000"}
```

**HTTP route**

[`DELETE /v1/relay/events/subscriptions/{id}`](../api/relay.md#delete-v1relayeventssubscriptionsid)

**Side effects**

Destructive for that subscription only. A malformed id is a `400`.

## Related

- [Cloud relay](../../CLOUD.md): what the relay is and how to set it up by hand.
- [Connect a cloud agent](../../cloud/connect-agent.md): the task guide for creating a key and pasting it into an agent.
- [Reply events](../../cloud/reply-events.md): how a cloud agent subscribes to replies.
- [Relay API](../api/relay.md): the local routes behind these tools.
- [Relay's remote API](../relay-api.md): the endpoints a cloud agent calls.
- [Apps and settings tools](apps-and-settings.md): the tools for apps, approvals, settings and History.
- [MCP tool index and conventions](README.md): how the server reports errors and what every tool shares.
