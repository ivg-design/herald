# Cloud relay API (local)

These endpoints control the cloud relay from this Mac: deploy it to your Cloudflare account, pair this Mac with
it, create and revoke the keys agents use, and watch its state. They are what the **Settings > Cloud** tab
calls. Use them to script a relay setup or to let a local agent do it for the user. The examples use the
`$HERALD` and `$TOKEN` variables from [Connect](README.md#connect).

> [!NOTE]
> This page documents the routes under `/v1/relay` on Herald's **local** API. The relay itself, running in the
> cloud, serves a different API to cloud agents. That one is the [relay API](../relay/README.md).

## What these endpoints manage

A cloud agent cannot reach your Mac. The **relay** is a small service in your own Cloudflare account that
holds a mailbox for your Mac: agents put notifications in, and Herald, which keeps one outgoing connection to
the relay, takes them out. The whole design is explained in [Cloud relay](../../CLOUD.md).

Four things exist around a relay, and each has endpoints here.

| Thing | What it is | Endpoints |
|---|---|---|
| **The deployment** | The relay program running in your Cloudflare account. | [Set up and deploy](#set-up-and-deploy) |
| **The pairing** | The link between this Mac and the relay, proved by a device token. | [Pair and status](#pair-and-status) |
| **Agent keys and connectors** | What a cloud agent presents to send you a notification. | [Agent keys and connectors](#agent-keys-and-connectors) |
| **Reply subscriptions** | A connector's request to be told when you reply. | [Reply subscriptions](#reply-subscriptions) |

No endpoint returns a secret that was stored earlier. A new agent key is shown once, in the reply that creates
it. The Cloudflare token, the pairing secret and the device token can be written or used, never read back.

![The Cloud tab of Herald's Settings with a paired relay that is online](../../../web/public/shots/docs/settings-cloud-paired.png "Settings > Cloud with a relay that is paired and online. The address, the agent keys and today's usage shown here come from the endpoints on this page.")

## Errors shared by the relay routes

Besides the [errors every endpoint shares](README.md#errors-shared-by-every-endpoint), the relay routes use
these.

| Status | When |
|---|---|
| `404` | The path is not a relay route. The message is `no such relay route`. |
| `409` | This Mac is not paired with a relay, and the route needs one. |
| `429` | The relay reported that a limit was reached. |
| `502` | The relay could not be reached, or it refused this Mac's token. |

A failure reported by Cloudflare during a deploy comes back with Cloudflare's own status and message.

## Pair and status

| Endpoint | Purpose |
|---|---|
| [`GET /v1/relay/status`](#get-v1relaystatus) | Everything about the relay in one reply. |
| [`GET /v1/relay/setup`](#get-v1relaysetup) | Where the setup stands and what to do next. |
| [`GET /v1/relay/usage`](#get-v1relayusage) | Today's traffic against this Mac's limits. |
| [`POST /v1/relay/pair`](#post-v1relaypair) | Pair this Mac with the relay. |
| [`POST /v1/relay/unpair`](#post-v1relayunpair) | End the pairing and wipe the mailbox. |

### `GET /v1/relay/status`

Returns the pairing, the connection, the agent keys, the Macs on the relay and the most recent notifications
that came through it. It is the first call to make: it tells you whether there is a relay and whether it is
working.

**Request**

No parameters.

**Example request**

```sh
curl -s "$HERALD/v1/relay/status" -H "Authorization: Bearer $TOKEN"
```

**Example response**

```json
{
  "paired": true,
  "online": true,
  "state": "Online",
  "relayURL": "https://herald-relay.example.workers.dev",
  "mcpURL": "https://herald-relay.example.workers.dev/mcp",
  "deviceId": "d_4f1c2a9e",
  "lastSeenAt": "2026-10-02T13:14:19.111Z",
  "keys": [
    {
      "id": "0a1b2c3d",
      "name": "build-bot",
      "client": "claude",
      "scope": "notify",
      "kind": "static",
      "createdAt": "2026-10-01T09:30:00.000Z",
      "lastUsedAt": "2026-10-02T13:00:04.000Z"
    }
  ],
  "devices": [
    {
      "id": "d_4f1c2a9e",
      "name": "Studio Mac",
      "online": true,
      "lastSeenAt": "2026-10-02T13:14:19.137Z",
      "thisDevice": true,
      "removable": false
    }
  ],
  "log": [
    {
      "id": "r_13cb91ec8efd0eab",
      "key": "build-bot",
      "title": "Build finished",
      "receivedAt": "2026-10-02T13:00:04.000Z",
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
    "bundledVersion": "3f2a9c0e",
    "deployedVersion": "3f2a9c0e",
    "updateAvailable": false,
    "steps": []
  }
}
```

**Response fields**

| Field | Type | Description |
|---|---|---|
| `paired` | boolean | `true` when this Mac holds a device token for a relay. |
| `online` | boolean | `true` when the connection to the relay is open. |
| `state` | string | The connection in words: `Not paired`, `Offline`, `Connecting…`, `Online`, or a message. |
| `relayURL` | string | The relay's address. Empty when there is no relay. |
| `mcpURL` | string | The address an agent connects to: the relay's address followed by `/mcp`. |
| `deviceId` | string | This Mac's id on the relay. |
| `lastSeenAt` | string | When the relay last heard from this Mac. |
| `keys` | array | The agent keys. See [`GET /v1/relay/keys`](#get-v1relaykeys). |
| `devices` | array | The Macs paired with this relay. See the next table. |
| `log` | array | The last 20 notifications that came through the relay. See the table after that. |
| `setup` | object | The setup state, as returned by [`GET /v1/relay/setup`](#get-v1relaysetup). |

Each entry of `devices`:

| Field | Type | Description |
|---|---|---|
| `id` | string | The Mac's id on the relay. |
| `name` | string | The Mac's name. |
| `online` | boolean | `true` when that Mac is connected now. |
| `lastSeenAt` | string | When the relay last heard from it. |
| `thisDevice` | boolean | `true` for the Mac you are asking. |
| `removable` | boolean | `true` when this Mac may remove the entry. |
| `removableReason` | string | Why the entry is removable, when it is. |

Each entry of `log`:

| Field | Type | Description |
|---|---|---|
| `id` | string | The relay's delivery id, which is also the notification id in History. |
| `key` | string | The name of the agent key that sent it. |
| `title` | string | The notification's title. |
| `receivedAt` | string | When Herald received it. |
| `displayed` | boolean | `true` when the banner was shown. |
| `spoken` | boolean | `true` when speech played to the end. |
| `replied` | boolean | `true` when the user answered. |
| `suppressed` | string | Why it was held back, such as `muted` or `quiet-hours`. Absent when it was not. |
| `duplicate` | boolean | `true` when it repeated a notification already delivered. |

**Notes**

- With several Macs on one relay, use `devices` to tell the user which Mac will show a banner.
- This endpoint never fails for a missing relay. It answers with `paired: false`.

### `GET /v1/relay/setup`

Returns where the setup stands as one state, with the facts behind it. Use it to decide the next step: ask
for a token, deploy, wait, or report a problem.

**Request**

No parameters.

**Example request**

```sh
curl -s "$HERALD/v1/relay/setup" -H "Authorization: Bearer $TOKEN"
```

**Example response**

```json
{
  "state": "online",
  "hasToken": true,
  "paired": true,
  "online": true,
  "relayURL": "https://herald-relay.example.workers.dev",
  "mcpURL": "https://herald-relay.example.workers.dev/mcp",
  "workersDevURL": "https://herald-relay.example.workers.dev",
  "customDomainRecommended": true,
  "bundledVersion": "3f2a9c0e",
  "deployedVersion": "3f2a9c0e",
  "updateAvailable": false,
  "steps": [],
  "usage": {
    "day": "2026-10-02",
    "requests": 34,
    "requestsPercent": 1,
    "notifications": 1,
    "queued": 0,
    "storageBytes": 90112,
    "wsMessages": 6,
    "pollSeconds": 0,
    "audioUploads": 0,
    "audioBytes": 0,
    "budgetExhausted": false
  }
}
```

**Response fields**

| Field | Type | Description |
|---|---|---|
| `state` | string | The setup state. See the next table. |
| `hasToken` | boolean | `true` when a Cloudflare token is stored. |
| `paired`, `online` | boolean | As in [`GET /v1/relay/status`](#get-v1relaystatus). |
| `relayURL`, `mcpURL` | string | The relay's address and the address agents use. |
| `workersDevURL` | string | The relay's `workers.dev` address. |
| `customURL` | string | The relay's custom-domain address, when one is set. |
| `customDomainRecommended` | boolean | `true` when the relay is paired and has no custom domain. |
| `bundledVersion` | string | The hash of the relay program inside this Herald. |
| `deployedVersion` | string | The hash of the relay program that is running. |
| `updateAvailable` | boolean | `true` when the two hashes differ. Deploy again to update. |
| `message` | string | A sentence for the user when something needs attention. |
| `steps` | array | The log of the last deploy: `step`, `title`, `phase` and `detail` for each step. |
| `usage` | object | Today's usage, as returned by [`GET /v1/relay/usage`](#get-v1relayusage). |

The `state` values:

| State | Meaning | What to do |
|---|---|---|
| `token-needed` | No relay and no Cloudflare token. | Get a token: [`GET /v1/relay/token-url`](#get-v1relaytoken-url). |
| `ready` | A token is stored, or a relay address is set, and nothing is paired. | Deploy or pair. |
| `deploying` | A deploy is running. | Wait and ask again. |
| `connecting` | Paired, and the connection is being opened. | Wait and ask again. |
| `online` | Paired and connected. | Nothing. |
| `offline` | Paired, and the connection is down. | Herald retries by itself. Read `message`. |
| `error` | The last deploy failed. | Read `message` and `steps`. |

### `GET /v1/relay/usage`

Returns today's traffic through the relay for this Mac. The relay runs on Cloudflare's free plan, so each Mac
has daily limits. Use this to see how close you are. The limits are explained in
[How the relay works](../../cloud/how-it-works.md#limits).

**Request**

No parameters.

**Example request**

```sh
curl -s "$HERALD/v1/relay/usage" -H "Authorization: Bearer $TOKEN"
```

**Example response**

```json
{
  "day": "2026-10-02",
  "requests": 34,
  "requestsPercent": 1,
  "notifications": 1,
  "queued": 0,
  "storageBytes": 90112,
  "wsMessages": 6,
  "pollSeconds": 0,
  "audioUploads": 0,
  "audioBytes": 0,
  "budgetExhausted": false
}
```

**Response fields**

| Field | Type | Description |
|---|---|---|
| `day` | string | The day the counts belong to, in UTC. Counts reset at midnight UTC. |
| `requests` | integer | Requests that reached this Mac's mailbox today. |
| `requestsPercent` | integer | `requests` as a percentage of the daily limit. |
| `notifications` | integer | Notifications accepted today. |
| `queued` | integer | Notifications waiting for this Mac right now. |
| `storageBytes` | integer | The size of the mailbox. |
| `wsMessages` | integer | Messages sent over the connection today. |
| `pollSeconds` | integer | Seconds agents spent waiting for replies today. |
| `audioUploads`, `audioBytes` | integer | Voice replies uploaded today, and their total size. |
| `budgetExhausted` | boolean | `true` when the daily request limit is used up. |

**Errors**

| Status | When |
|---|---|
| `409` | This Mac is not paired. |

### `POST /v1/relay/pair`

Pairs this Mac with the relay at the configured address. Herald asks the relay for a one-time code, redeems
it, and stores the device token it receives. Nothing is shown on screen.

You rarely call this yourself: [`POST /v1/relay/deploy`](#post-v1relaydeploy) pairs at the end of a deploy.
Use it for a relay that Herald did not deploy.

**Request**

No parameters. Send an empty body.

**Example request**

```sh
curl -s -X POST "$HERALD/v1/relay/pair" -H "Authorization: Bearer $TOKEN"
```

**Example response**

```json
{"paired": true, "code": "482913", "deviceId": "d_4f1c2a9e"}
```

**Response fields**

| Field | Type | Description |
|---|---|---|
| `paired` | boolean | Always `true` on success. |
| `code` | string | The one-time code that was redeemed. It is used up and has no further value. |
| `deviceId` | string | This Mac's id on the relay. |

**Errors**

| Status | When |
|---|---|
| `429` | The relay's pairing limit was reached. |
| `502` | The relay could not be reached. |

### `POST /v1/relay/unpair`

Ends the pairing. The relay wipes this Mac's mailbox, which revokes every agent key and connector and
discards waiting notifications and voice replies. Herald forgets the device token.

> [!WARNING]
> Every agent that could notify this Mac stops working and has to be connected again after a new pairing.

**Request**

No parameters.

**Example request**

```sh
curl -s -X POST "$HERALD/v1/relay/unpair" -H "Authorization: Bearer $TOKEN"
```

**Example response**

```json
{"unpaired": true}
```

**Notes**

- The relay program stays in your Cloudflare account. Remove it with
  [`POST /v1/relay/delete`](#post-v1relaydelete).

## Agent keys and connectors

An agent reaches the relay with one of two credentials. An **agent key** is a secret string that you create
here and paste into the agent. A **connector** is an agent that signed in through OAuth and that you approved
on the Mac; the relay stores it as a key of kind `oauth`. Both can only send notifications and read back what
they sent. See [Connect a cloud agent](../../cloud/connect-agent.md) and
[Connect ChatGPT](../../cloud/connect-chatgpt.md).

| Endpoint | Purpose |
|---|---|
| [`GET /v1/relay/keys`](#get-v1relaykeys) | List agent keys and connectors. |
| [`POST /v1/relay/keys`](#post-v1relaykeys) | Create an agent key. |
| [`DELETE /v1/relay/keys/{id}`](#delete-v1relaykeysid) | Revoke a key or a connector. |
| [`GET /v1/relay/connectors`](#get-v1relayconnectors) | List connectors and requests waiting for approval. |
| [`GET /v1/relay/instructions`](#get-v1relayinstructions) | Get the text to give an agent. |

### `GET /v1/relay/keys`

Lists every agent key and connector of this Mac, including revoked ones. It never returns a secret.

**Request**

No parameters.

**Example request**

```sh
curl -s "$HERALD/v1/relay/keys" -H "Authorization: Bearer $TOKEN"
```

**Example response**

```json
{
  "keys": [
    {
      "id": "0a1b2c3d",
      "name": "build-bot",
      "client": "claude",
      "scope": "notify",
      "kind": "static",
      "createdAt": "2026-10-01T09:30:00.000Z",
      "lastUsedAt": "2026-10-02T13:00:04.000Z"
    },
    {
      "id": "4e5f6a7b",
      "name": "chatgpt",
      "displayName": "ChatGPT",
      "client": "other",
      "scope": "notify",
      "kind": "oauth",
      "createdAt": "2026-10-02T08:27:58.940Z",
      "lastUsedAt": "2026-10-02T08:28:03.969Z"
    }
  ]
}
```

**Response fields**

| Field | Type | Description |
|---|---|---|
| `id` | string | The key's id: eight hexadecimal characters. Use it to revoke the key. |
| `name` | string | The key's name. Its notifications arrive as the app `cloud.<name>`. |
| `displayName` | string | For a connector: the name its client signed in with. |
| `client` | string | `claude`, `codex` or `other`. |
| `scope` | string | Always `notify`. |
| `kind` | string | `static` for an agent key, `oauth` for a connector. |
| `createdAt` | string | When it was created. |
| `lastUsedAt` | string | When it last sent something. |
| `revokedAt` | string | When it was revoked. Absent while the key works. |

### `POST /v1/relay/keys`

Creates an agent key. The reply holds the key itself and a ready configuration block for the agent. This is
the only time the key is shown: the relay keeps only a hash of it.

**Request**

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `name` | body | string | yes | A name for the key, such as `build-bot`. |
| `client` | body | string | no | `claude`, `codex` or `other`. It picks the agent's icon and the shape of the configuration block. Default `other`. |

**Example request**

```sh
curl -s -X POST "$HERALD/v1/relay/keys" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"name": "build-bot", "client": "claude"}'
```

**Example response**

The status is `201`.

```json
{
  "id": "0a1b2c3d",
  "name": "build-bot",
  "client": "claude",
  "scope": "notify",
  "key": "hrk_...",
  "mcpURL": "https://herald-relay.example.workers.dev/mcp",
  "connectorConfig": "claude mcp add --transport http herald https://herald-relay.example.workers.dev/mcp --header \"Authorization: Bearer hrk_...\""
}
```

**Response fields**

| Field | Type | Description |
|---|---|---|
| `key` | string | The agent key. Store it now: it cannot be read again. |
| `mcpURL` | string | The address the agent connects to. |
| `connectorConfig` | string | A command or configuration block for the chosen client, with the key filled in. |

**Errors**

| Status | When |
|---|---|
| `400` | `name` is missing. |
| `409` | A key with this name already exists, or this Mac is not paired. |

### `DELETE /v1/relay/keys/{id}`

Revokes an agent key or a connector at once. The agent's next request is refused.

**Request**

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `id` | path | string | yes | The key's id from [`GET /v1/relay/keys`](#get-v1relaykeys). |

**Example request**

```sh
curl -s -X DELETE "$HERALD/v1/relay/keys/0a1b2c3d" -H "Authorization: Bearer $TOKEN"
```

**Example response**

```json
{"revoked": true, "id": "0a1b2c3d"}
```

**Errors**

| Status | When |
|---|---|
| `400` | `id` is not eight hexadecimal characters. |

**Notes**

- Revoking a connector also ends its reply subscriptions.
- The app `cloud.<name>` and its History stay. Remove them with
  [`DELETE /v1/apps/{id}`](apps.md#delete-v1appsid).

### `GET /v1/relay/connectors`

Lists the connectors that signed in through OAuth, and the requests that are waiting for the user's approval.
Use it to tell the user which request belongs to which agent.

**Request**

No parameters.

**Example request**

```sh
curl -s "$HERALD/v1/relay/connectors" -H "Authorization: Bearer $TOKEN"
```

**Example response**

```json
{
  "connectors": [
    {
      "id": "4e5f6a7b",
      "name": "chatgpt",
      "displayName": "ChatGPT",
      "client": "other",
      "scope": "notify",
      "kind": "oauth",
      "createdAt": "2026-10-02T08:27:58.940Z",
      "lastUsedAt": "2026-10-02T08:28:03.969Z"
    }
  ],
  "pending": [
    {
      "id": "c_7d2e41",
      "clientName": "My cloud agent",
      "expiresAt": "2026-10-02T13:25:00.000Z",
      "userCode": "BDFG-HJKM"
    }
  ]
}
```

**Response fields**

| Field | Type | Description |
|---|---|---|
| `connectors` | array | The approved connectors, in the shape of [`GET /v1/relay/keys`](#get-v1relaykeys). |
| `pending[].id` | string | The id of a request that is waiting. |
| `pending[].clientName` | string | The name the agent gave when it registered. |
| `pending[].redirectHost` | string | For a browser sign-in: the host the agent returns to. |
| `pending[].expiresAt` | string | When the request expires. |
| `pending[].userCode` | string | For the device flow: the code the agent printed, to match against. |

**Notes**

- The 6-digit approval code is never returned. Approving happens on the Mac, in the banner or in
  **Settings > Cloud > Connector approvals**.
- No endpoint approves a request.

### `GET /v1/relay/instructions`

Returns ready-made instructions to give to an agent or its user, with this relay's address filled in.

**Request**

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `client` | query | string | yes | `chatgpt`, `claude`, `codex` or `device`. |

**Example request**

```sh
curl -s "$HERALD/v1/relay/instructions?client=claude" -H "Authorization: Bearer $TOKEN"
```

**Example response**

```json
{
  "client": "claude",
  "text": "Claude Code / Codex CLI (a static key)\n\nClaude Code:\nclaude mcp add --transport http herald https://herald-relay.example.workers.dev/mcp --header \"Authorization: Bearer <key>\""
}
```

**Errors**

| Status | When |
|---|---|
| `400` | `client` is not one of the four values. |

**Notes**

- `chatgpt` gives the OAuth connector steps, `claude` and `codex` give the agent-key steps, and `device`
  gives the device-flow sequence for an agent with no browser.

## Reply subscriptions

A connector can ask the relay to call a web address the moment you reply to one of its notifications, so that
it does not have to keep asking. That request is a **reply subscription**. The approval of the connector is
what authorises it; nothing more is asked on the Mac. See
[Reply events](../../cloud/reply-events.md).

| Endpoint | Purpose |
|---|---|
| [`GET /v1/relay/events`](#get-v1relayevents) | List the reply subscriptions. |
| [`DELETE /v1/relay/events/subscriptions/{id}`](#delete-v1relayeventssubscriptionsid) | End one subscription. |

### `GET /v1/relay/events`

Lists the live reply subscriptions: which connector is told about replies, and at which host.

**Request**

No parameters.

**Example request**

```sh
curl -s "$HERALD/v1/relay/events" -H "Authorization: Bearer $TOKEN"
```

**Example response**

```json
{
  "restrictedTo": [],
  "subscriptions": [
    {
      "id": "sub_0123456789abcdef0123",
      "event": "notification.reply",
      "host": "hooks.example.com",
      "key": {"id": "4e5f6a7b", "name": "chatgpt", "displayName": "ChatGPT"},
      "createdAt": "2026-10-02T08:35:49.713Z",
      "pending": 0
    }
  ]
}
```

**Response fields**

| Field | Type | Description |
|---|---|---|
| `restrictedTo` | array | The hosts callbacks may go to, when the relay limits them. Empty means any public host. |
| `subscriptions[].id` | string | The subscription's id. |
| `subscriptions[].event` | string | The event: `notification.reply`. |
| `subscriptions[].host` | string | The host that is called. The path and the secret are never shown. |
| `subscriptions[].key` | object | The connector that subscribed: `id`, `name` and `displayName`. |
| `subscriptions[].createdAt` | string | When it subscribed. |
| `subscriptions[].pending` | integer | Events waiting to be delivered to it. |

**Errors**

| Status | When |
|---|---|
| `409` | This Mac is not paired. |

### `DELETE /v1/relay/events/subscriptions/{id}`

Ends one reply subscription. The connector stays approved and can subscribe again.

**Request**

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `id` | path | string | yes | The subscription's id from [`GET /v1/relay/events`](#get-v1relayevents). |

**Example request**

```sh
curl -s -X DELETE "$HERALD/v1/relay/events/subscriptions/sub_0123456789abcdef0123" \
  -H "Authorization: Bearer $TOKEN"
```

**Example response**

```json
{"removed": true, "id": "sub_0123456789abcdef0123"}
```

**Errors**

| Status | When |
|---|---|
| `400` | `id` is not `sub_` followed by 20 hexadecimal characters. |

## Set up and deploy

These endpoints do what the **Enable relay** sheet does. The order is: get the token page, store the token,
deploy. The guided version with screenshots is [Set up the cloud relay](../../CLOUD.md).

| Endpoint | Purpose |
|---|---|
| [`GET /v1/relay/token-url`](#get-v1relaytoken-url) | Get the Cloudflare page that creates the right token. |
| [`POST /v1/relay/token`](#post-v1relaytoken) | Store the Cloudflare token. |
| [`POST /v1/relay/deploy`](#post-v1relaydeploy) | Deploy or update the relay, then pair. |
| [`GET /v1/relay/settings`](#get-v1relaysettings) | Read the advanced settings. |
| [`PUT /v1/relay/settings`](#put-v1relaysettings) | Change the advanced settings. |
| [`GET /v1/relay/zones`](#get-v1relayzones) | List the domains available for a custom address. |
| [`POST /v1/relay/test`](#post-v1relaytest) | Test the relay end to end. |
| [`POST /v1/relay/delete`](#post-v1relaydelete) | Delete the relay from Cloudflare. |

### `GET /v1/relay/token-url`

Returns a link to Cloudflare's token page with the needed permissions already selected, the reason for each
permission, and the steps to tell the user. Herald needs a Cloudflare API token to deploy the relay into the
user's own account.

**Request**

No parameters.

**Example request**

```sh
curl -s "$HERALD/v1/relay/token-url" -H "Authorization: Bearer $TOKEN"
```

**Example response**

The `permissions` and `steps` lists are shortened here.

```json
{
  "url": "https://dash.cloudflare.com/profile/api-tokens?permissionGroupKeys=%5B%5D&name=Herald%20relay",
  "signUpURL": "https://dash.cloudflare.com/sign-up",
  "permissions": [
    {
      "key": "workers_scripts",
      "type": "edit",
      "title": "Workers Scripts: Edit",
      "why": "upload the relay, switch on its workers.dev address, set its variables and secrets"
    }
  ],
  "steps": [
    "Open the link (a free Cloudflare account is enough; sign up first if you have none)."
  ]
}
```

**Response fields**

| Field | Type | Description |
|---|---|---|
| `url` | string | The pre-filled token page. |
| `signUpURL` | string | Cloudflare's sign-up page, for a user with no account. |
| `permissions` | array | The nine permissions: `key`, `type`, `title` and `why` for each. |
| `steps` | array | What to tell the user, one sentence per step. |

**Notes**

- Three permissions are needed to deploy. The other six are used only for a
  [custom domain](../../cloud/custom-domain.md). The full list is in
  [Set up the cloud relay](../../CLOUD.md#the-cloudflare-token).

### `POST /v1/relay/token`

Stores the Cloudflare API token in Herald's secret store on this Mac. The token is sent only to Cloudflare's
API and is never returned by any endpoint.

**Request**

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `token` | body | string | yes | The Cloudflare API token the user created. |

**Example request**

```sh
curl -s -X POST "$HERALD/v1/relay/token" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d "{\"token\": \"$CLOUDFLARE_API_TOKEN\"}"
```

**Example response**

```json
{"stored": true}
```

**Errors**

| Status | When |
|---|---|
| `400` | `token` is missing or empty. |

### `POST /v1/relay/deploy`

Deploys the relay into the user's Cloudflare account, waits until it answers, and pairs this Mac with it. If a
relay already exists, the same call updates it in place and keeps its data, its keys and its secrets. The
request returns when the work is done, which can take a minute.

**Request**

No parameters.

**Example request**

```sh
curl -s -X POST "$HERALD/v1/relay/deploy" -H "Authorization: Bearer $TOKEN" --max-time 300
```

**Example response**

The `steps` list is shortened here to two entries.

```json
{
  "deployed": true,
  "upgraded": false,
  "relayURL": "https://herald-relay.example.workers.dev",
  "workersDevURL": "https://herald-relay.example.workers.dev",
  "paired": true,
  "online": true,
  "warnings": [],
  "steps": [
    {"step": "verifyToken", "title": "Check the API token", "phase": "done", "detail": ""},
    {"step": "upload", "title": "Upload the relay", "phase": "done", "detail": ""}
  ]
}
```

**Response fields**

| Field | Type | Description |
|---|---|---|
| `deployed` | boolean | `true` when the relay is running. |
| `upgraded` | boolean | `true` when an existing relay was updated, `false` for a first deploy. |
| `relayURL` | string | The relay's address: the custom domain when one is set. |
| `workersDevURL` | string | The relay's `workers.dev` address. |
| `customURL` | string | The custom-domain address, when one is set. |
| `paired`, `online` | boolean | Whether this Mac is paired and connected after the deploy. |
| `steps` | array | Each step with its `phase`: `started`, `done` or `failed`. |
| `warnings` | array | Things to tell the user that did not stop the deploy. |

**Errors**

| Status | When |
|---|---|
| `4xx`, `5xx` | Cloudflare refused a step. The status and message are Cloudflare's. |
| `502` | Cloudflare could not be reached. |

**Notes**

- An update never changes the relay's signing secret, so this Mac's pairing and every agent key keep working.
- Deploying over a relay that was deleted creates new secrets. Herald then pairs again by itself and says so
  in `warnings`. Agent keys and connectors made before must be created again.

### `GET /v1/relay/settings`

Returns the advanced settings of the relay: where it is deployed and its limits.

**Request**

No parameters.

**Example request**

```sh
curl -s "$HERALD/v1/relay/settings" -H "Authorization: Bearer $TOKEN"
```

**Example response**

```json
{
  "settings": {
    "accountId": "0123456789abcdef0123456789abcdef",
    "workerName": "herald-relay",
    "subdomain": "example",
    "bucket": "herald-relay-audio",
    "audioRetentionDays": 7,
    "queueTTLHours": 24,
    "notificationsPerDay": 500,
    "maxQueue": 100,
    "bodyLimitBytes": 32768,
    "ratePerKey": 60,
    "maxDevices": 5,
    "deviceName": "",
    "pingSeconds": 300,
    "deployedHash": "3f2a9c0e",
    "deployedAt": "2026-10-01T09:20:14.000Z"
  },
  "pairingSecretSet": true,
  "errors": {},
  "redeployed": false,
  "steps": [],
  "warnings": []
}
```

**Response fields**

| Field | Type | Description |
|---|---|---|
| `settings` | object | The current values. See [Relay setting keys](#relay-setting-keys). |
| `pairingSecretSet` | boolean | `true` when a pairing secret is stored. The secret itself is never returned. |
| `errors` | object | Problems with the stored values, by key. Empty when all are valid. |
| `redeployed` | boolean | `true` in the reply to a change that redeployed the relay. |
| `steps` | array | The deploy steps, when the change redeployed. |
| `warnings` | array | Things to tell the user after a redeploy. |

### `PUT /v1/relay/settings`

Changes advanced settings. A change to a value that lives in the relay program, such as a limit, redeploys
the relay, so the request can take a minute.

**Request**

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| any [relay setting key](#relay-setting-keys) | body | varies | no | The new value for that key. |

#### Relay setting keys

| Key | Type | Description |
|---|---|---|
| `relayURL` | string | The relay's address. Set it to use a relay Herald did not deploy. Write-only. |
| `accountId` | string | The Cloudflare account id. Empty lets Herald find it. |
| `workerName` | string | The name of the relay program in Cloudflare. Default `herald-relay`. |
| `subdomain` | string | The account's `workers.dev` subdomain. |
| `bucket` | string | The storage bucket for voice replies. Default `herald-relay-audio`. |
| `audioRetentionDays` | integer | Days a voice reply is kept. Default `7`. |
| `queueTTLHours` | integer | Hours an undelivered notification is kept. Default `24`. |
| `notificationsPerDay` | integer | Notifications each Mac accepts per day. Default `500`. |
| `maxQueue` | integer | Notifications that may wait for a Mac at once. Default `100`. |
| `bodyLimitBytes` | integer | The largest notification request. Default `32768`. |
| `ratePerKey` | integer | Notifications one key may send per 10 minutes. Default `60`. |
| `maxDevices` | integer | Macs that may pair with the relay. Default `5`. |
| `deviceName` | string | This Mac's name on the relay. Empty uses the computer's name. |
| `pingSeconds` | integer | Seconds between keep-alive messages. Default `300`. |
| `customDomain` | object or null | A custom address: `zone` and `hostname`. `null` removes it. |
| `pairingSecret` | string | The secret a Mac must present to pair. At least 8 characters. Write-only. |

**Example request**

```sh
curl -s -X PUT "$HERALD/v1/relay/settings" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" --max-time 300 \
  -d '{"notificationsPerDay": 1000, "deviceName": "Studio Mac"}'
```

**Example response**

The reply has the shape of [`GET /v1/relay/settings`](#get-v1relaysettings). The `settings` part is shortened
here.

```json
{
  "settings": {"notificationsPerDay": 1000, "deviceName": "Studio Mac", "workerName": "herald-relay"},
  "pairingSecretSet": true,
  "errors": {},
  "redeployed": true,
  "steps": [{"step": "upload", "title": "Upload the relay", "phase": "done", "detail": ""}],
  "warnings": []
}
```

**Errors**

| Status | When |
|---|---|
| `400` | The body is not an object, a key is unknown, or a value is invalid. The message names the key. |
| `4xx`, `5xx` | The change needed a redeploy and Cloudflare refused a step. |

**Notes**

- Setting `customDomain` redeploys and attaches the address. The steps and their effects are in
  [Use a custom domain](../../cloud/custom-domain.md).
- `deployedHash` and `deployedAt` are read-only.

### `GET /v1/relay/zones`

Lists the domains in the user's Cloudflare account that the stored token can see. Use it to offer a choice for
a custom domain.

**Request**

No parameters.

**Example request**

```sh
curl -s "$HERALD/v1/relay/zones" -H "Authorization: Bearer $TOKEN"
```

**Example response**

```json
{
  "zones": [
    {
      "id": "0123456789abcdef0123456789abcdef",
      "name": "example.com",
      "status": "active",
      "suggestedHostname": "herald.example.com"
    }
  ]
}
```

**Errors**

| Status | When |
|---|---|
| `403` | The token lacks the Zone permissions. The message starts with `Token is missing Zone permissions`. |

### `POST /v1/relay/test`

Tests the whole path. Herald checks that the relay answers, then sends a notification through it with a
temporary key and waits for the receipt. The test notification, the key and their traces are removed
afterwards.

**Request**

No parameters.

**Example request**

```sh
curl -s -X POST "$HERALD/v1/relay/test" -H "Authorization: Bearer $TOKEN" --max-time 60
```

**Example response**

```json
{
  "healthy": true,
  "paired": true,
  "online": true,
  "roundTrip": true,
  "receipt": "displayed",
  "detail": "A test notification went through the relay and was shown on this Mac.",
  "browserCheckActive": true
}
```

**Response fields**

| Field | Type | Description |
|---|---|---|
| `healthy` | boolean | `true` when the relay answered its health check. |
| `paired`, `online` | boolean | Whether this Mac is paired and connected. |
| `roundTrip` | boolean | `true` when the test notification arrived and its receipt came back. |
| `receipt` | string | The receipt the test notification got. |
| `detail` | string | The result in words, for the user. |
| `browserCheckActive` | boolean | `true` when Cloudflare's browser check is active on the relay's address. |

**Errors**

| Status | When |
|---|---|
| `409` | No relay is set up. |

**Notes**

- The test shows a banner titled **Relay test** for a moment.
- When `browserCheckActive` is `true`, agents must send a custom `User-Agent` header. See
  [Use a custom domain](../../cloud/custom-domain.md).

### `POST /v1/relay/delete`

Deletes the relay from the user's Cloudflare account: the program, every mailbox and every key. The storage
bucket is deleted when it is empty.

> [!WARNING]
> This cannot be undone. Every Mac paired with the relay loses its pairing and every agent stops working.

**Request**

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `confirm` | body | boolean | yes | Must be `true`. |

**Example request**

```sh
curl -s -X POST "$HERALD/v1/relay/delete" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"confirm": true}'
```

**Example response**

```json
{"deleted": true, "note": "The bucket herald-relay-audio still holds voice replies and was kept."}
```

**Errors**

| Status | When |
|---|---|
| `400` | `confirm` is not `true`. |
| `4xx`, `5xx` | Cloudflare refused the deletion. |

**Notes**

- Cloudflare refuses to delete a bucket that still holds files. The `note` says so when that happens.
- A custom domain's DNS record and rules stay in the Cloudflare account. Delete them there.

## Related

- [Cloud relay](../../CLOUD.md): what the relay is and how to set it up by hand.
- [How the relay works](../../cloud/how-it-works.md): the security model and the limits.
- [Relay API](../relay/README.md): what the relay itself serves to cloud agents.
- [MCP relay tools](../mcp/relay.md): the same operations for a local agent.
