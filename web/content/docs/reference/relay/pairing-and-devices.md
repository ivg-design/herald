# Pairing and devices

A Mac joins a relay by pairing, and from then on it manages its mailbox and the list of Macs on the relay with
its device token. This page documents the two pairing endpoints and the device-management endpoints: the list of
Macs, pruning, removal, unpairing, and the mailbox summary, usage and status routes. Herald calls them for you from
**Settings > Cloud**, so you need them only to implement a relay or a compatible client, or to script a setup. The
routes Herald uses to receive notifications, keys and approvals are on the [device side](device-side.md) page.

Examples use `$RELAY` from the [relay API overview](README.md) and a variable for the device token.

```sh
RELAY="https://herald-relay.example.workers.dev"
DEVICE_TOKEN="hrd_..."
```

## Concepts

**Pairing** is a two-step handshake. The first call asks the relay for a one-time code. The second call trades
that code for the device token. Neither call needs a credential, and the relay limits them per client address.

**The device token** is the Mac's credential for every `/v1/device/*` route. It is shown once, in the reply to
`POST /v1/pair`. The relay stores only its hash, so a lost token cannot be read back. Pair again instead.

**The registry** is the relay's list of paired Macs. Every Mac on a relay can read the list. A Mac can remove
only the entries that cannot be in active use: one with the same name as itself, one whose credentials were
rotated, or one with no connection for 7 days. It can never remove a different Mac that is active.

> [!NOTE]
> The first pairing is trust on first use. Pair soon after you deploy the relay, or deploy it with a pairing
> secret so that a stranger cannot start. When the relay has a pairing secret, `POST /v1/pair/start` needs it in
> the `X-Pairing-Secret` header.

## Endpoints

| Endpoint | Purpose |
|---|---|
| [`POST /v1/pair/start`](#post-v1pairstart) | Ask the relay for a one-time pairing code. |
| [`POST /v1/pair`](#post-v1pair) | Trade the code for the device token. |
| [`GET /v1/device/devices`](#get-v1devicedevices) | List the Macs on this relay. |
| [`POST /v1/device/prune`](#post-v1deviceprune) | Remove this Mac's stale siblings. |
| [`DELETE /v1/device/devices/{deviceId}`](#delete-v1devicedevicesdeviceid) | Remove one entry from the list. |
| [`DELETE /v1/device`](#delete-v1device) | Unpair this Mac. |
| [`GET /v1/device/info`](#get-v1deviceinfo) | Read a short summary of this Mac's mailbox. |
| [`GET /v1/device/usage`](#get-v1deviceusage) | Read today's traffic against the limits. |
| [`POST /v1/device/status`](#post-v1devicestatus) | Report quiet hours and mute. |

### `POST /v1/pair/start`

Asks the relay for a one-time pairing code. The code lasts 10 minutes and works once.

**Request**

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `X-Pairing-Secret` | header | string | no | The relay's pairing secret. Required when the relay was deployed with one. |
| `deviceName` | body | string | no | A name for the Mac. The relay keeps the first 60 characters. |

**Example request**

```sh
curl -s -X POST "$RELAY/v1/pair/start" \
  -H "Content-Type: application/json" \
  -H "X-Pairing-Secret: $PAIRING_SECRET" \
  -d '{"deviceName":"Studio Mac"}'
```

**Example response**

The reply is `201`.

```json
{
  "code": "K7QM-2XPD",
  "expiresInSeconds": 600
}
```

**Response fields**

| Field | Type | Description |
|---|---|---|
| `code` | string | The pairing code, 8 characters shown as `XXXX-XXXX`. |
| `expiresInSeconds` | integer | How long the code works. Always `600`. |

**Errors**

| Status | When |
|---|---|
| `401` | The relay has a pairing secret and the header is missing or wrong (`unauthorized`). |
| `403` | The relay already has its maximum number of paired Macs (`device_limit`). |
| `429` | Too many pairing attempts from this address or in total, or codes are already waiting (`rate_limited`). |

**Notes**

- The relay compares codes without case and without the dash.
- A body that is empty or not JSON is treated as no body. A `deviceName` that is not a string is ignored.
- Pairing again under a name that is already paired does not count against the maximum, because the new entry
  takes the place of the old one. The maximum is 5 Macs unless the relay's owner changes `MAX_DEVICES`.
- Each client address may start 6 codes per hour and have 3 codes waiting. The relay as a whole accepts 300
  starts per hour and holds 60 waiting codes. The `429` body carries `retryAfterSeconds` (`3600`, or `600` when
  codes are waiting) and no `Retry-After` header.
- A relay's owner can change the per-address and total hourly limits with `PAIR_STARTS_PER_HOUR` and
  `PAIR_STARTS_GLOBAL_PER_HOUR`. See [Limits and errors](limits-and-errors.md).

### `POST /v1/pair`

Trades a pairing code for the device token. After this call, the Mac holds the credential for everything under
`/v1/device`.

**Request**

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `code` | body | string | yes | The code from `POST /v1/pair/start`. |
| `deviceName` | body | string | no | A name for the Mac. The relay keeps the first 60 characters. It takes precedence over the name given at the start. |

**Example request**

```sh
curl -s -X POST "$RELAY/v1/pair" \
  -H "Content-Type: application/json" \
  -d '{"code":"K7QM-2XPD","deviceName":"Studio Mac"}'
```

**Example response**

The reply is `200`.

```json
{
  "deviceId": "a1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718",
  "deviceToken": "hrd_..."
}
```

**Response fields**

| Field | Type | Description |
|---|---|---|
| `deviceId` | string | The Mac's id: 48 hex characters. |
| `deviceToken` | string | The device token, `hrd_<deviceId>_<secret>`. It is shown once. |

**Errors**

| Status | When |
|---|---|
| `403` | The code is wrong, already used or expired (`bad_code`). A body that is not JSON counts as a wrong code. |
| `429` | This address entered 10 wrong codes in 10 minutes (`rate_limited`). |

**Notes**

- A Mac that pairs again under the same name takes the place of its earlier entry. The relay deletes the earlier
  entry's mailbox, keys and stored voice replies. A reinstall or a redeploy therefore leaves no dead entry behind.
- A correct code is used up by the call. The same code again is `403 bad_code`.
- The `429` body carries `retryAfterSeconds` of `600` and no `Retry-After` header. Wrong codes from other
  addresses do not count against this one.

### `GET /v1/device/devices`

Lists the Macs paired with this relay and says which of them this Mac may remove. Use it to show the user the
entries and offer to clean up the ones that are safe to remove.

**Request**

No parameters. The call needs the device token.

**Example request**

```sh
curl -s "$RELAY/v1/device/devices" -H "Authorization: Bearer $DEVICE_TOKEN"
```

**Example response**

```json
{
  "removed": [],
  "devices": [
    {
      "id": "a1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718",
      "name": "Studio Mac",
      "online": true,
      "lastSeenAt": "2026-10-02T13:14:19.137Z",
      "createdAt": "2026-10-01T09:00:00.000Z",
      "thisDevice": true,
      "removable": false
    },
    {
      "id": "0f1e2d3c4b5a69788796a5b4c3d2e1f00f1e2d3c4b5a6978",
      "name": "Old laptop",
      "online": false,
      "lastSeenAt": "2026-09-20T08:00:00.000Z",
      "createdAt": "2026-09-01T09:00:00.000Z",
      "thisDevice": false,
      "removable": true,
      "removableReason": "idle"
    }
  ]
}
```

**Response fields**

| Field | Type | Description |
|---|---|---|
| `removed` | array | Always empty for this call. It has the same shape as the reply of `POST /v1/device/prune`. |
| `devices` | array | One entry per paired Mac, oldest first. |
| `devices[].id` | string | The Mac's id. |
| `devices[].name` | string | The name it paired under. `null` when it paired without one. |
| `devices[].online` | boolean | `true` while its stream is open and it was heard from in the last 11 minutes. |
| `devices[].lastSeenAt` | string | When it was last seen. |
| `devices[].createdAt` | string | When it paired. |
| `devices[].thisDevice` | boolean | `true` for the Mac making the request. |
| `devices[].removable` | boolean | `true` when this Mac may remove the entry. |
| `devices[].removableReason` | string | Present when `removable` is `true`: `same_name`, `credentials_rotated` or `idle`. |

`removableReason` says why. `same_name` means the entry has the same name as this Mac. `credentials_rotated`
means the relay's signing secret changed and the entry's id does not verify. `idle` means the entry is not
online and has not been seen for 7 days. When more than one applies, the order is `same_name`, then
`credentials_rotated`, then `idle`.

**Errors**

| Status | When |
|---|---|
| `404` | This Mac is not in the relay's registry (`not_found`). |

### `POST /v1/device/prune`

Removes this Mac's own stale siblings in one call: other entries with the same name, entries whose credentials
were rotated, entries whose mailbox was wiped, and entries with no connection for 30 days. It never removes this
Mac, and it never removes a different Mac that is active.

**Request**

No parameters. The call needs the device token.

**Example request**

```sh
curl -s -X POST "$RELAY/v1/device/prune" -H "Authorization: Bearer $DEVICE_TOKEN"
```

**Example response**

```json
{
  "removed": ["0f1e2d3c4b5a69788796a5b4c3d2e1f00f1e2d3c4b5a6978"],
  "devices": [
    {
      "id": "a1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718",
      "name": "Studio Mac",
      "online": true,
      "lastSeenAt": "2026-10-02T13:14:19.137Z",
      "createdAt": "2026-10-01T09:00:00.000Z",
      "thisDevice": true,
      "removable": false
    }
  ]
}
```

**Response fields**

| Field | Type | Description |
|---|---|---|
| `removed` | array | The ids of the entries the call removed. |
| `devices` | array | The Macs that remain, in the shape of [`GET /v1/device/devices`](#get-v1devicedevices). |

**Errors**

| Status | When |
|---|---|
| `404` | This Mac is not in the relay's registry (`not_found`). |

**Notes**

- Removing an entry deletes its mailbox, its keys and its stored voice replies.
- Prune uses 30 days for idle entries. [`DELETE /v1/device/devices/{deviceId}`](#delete-v1devicedevicesdeviceid)
  accepts an idle entry after 7 days.

### `DELETE /v1/device/devices/{deviceId}`

Removes one entry from the relay's list of Macs, with its mailbox. The relay refuses unless the entry has the same
name as this Mac, has rotated credentials, or has been idle for 7 days. Use it when the user picks one entry to
clean up.

**Request**

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `deviceId` | path | string | yes | The 48-character id of the entry to remove. |

**Example request**

```sh
curl -s -X DELETE "$RELAY/v1/device/devices/0f1e2d3c4b5a69788796a5b4c3d2e1f00f1e2d3c4b5a6978" \
  -H "Authorization: Bearer $DEVICE_TOKEN"
```

**Example response**

```json
{"removed": ["0f1e2d3c4b5a69788796a5b4c3d2e1f00f1e2d3c4b5a6978"]}
```

**Errors**

| Status | When |
|---|---|
| `400` | The id is this Mac. Use `DELETE /v1/device` to unpair it (`invalid_request`). |
| `403` | The entry is a different Mac that is active (`not_removable`). |
| `404` | No entry has that id (`not_found`), or this Mac is not in the registry. |

**Notes**

- A path segment that is not 48 hex characters does not match this route and gets `404 not_found` with the
  message `no such device endpoint`.

### `DELETE /v1/device`

Unpairs this Mac. The relay closes the stream with code `4001`, deletes the mailbox (the queue, the keys, the
approvals and the subscriptions) and the stored voice replies, removes the Mac from its list, and forgets the
device token. Every agent key and access token stops working.

**Request**

No parameters. The call needs the device token.

**Example request**

```sh
curl -s -X DELETE "$RELAY/v1/device" -H "Authorization: Bearer $DEVICE_TOKEN"
```

**Example response**

```json
{"unpaired": true}
```

> [!WARNING]
> Unpairing deletes the relay's copy of everything for this Mac and cannot be undone. Agents must be given new
> keys after the Mac pairs again.

### `GET /v1/device/info`

Returns a short summary of this Mac's mailbox: whether the Mac is connected, how many notifications wait, and the
quiet-hours state it last reported.

**Request**

No parameters. The call needs the device token.

**Example request**

```sh
curl -s "$RELAY/v1/device/info" -H "Authorization: Bearer $DEVICE_TOKEN"
```

**Example response**

```json
{
  "online": true,
  "lastSeenAt": "2026-10-02T13:14:19.111Z",
  "pending": 0,
  "quietHours": {"active": false},
  "keys": 2
}
```

**Response fields**

| Field | Type | Description |
|---|---|---|
| `online` | boolean | `true` while the stream is open and the relay heard from it in the last 11 minutes. |
| `lastSeenAt` | string | When the relay last heard from the Mac. Absent until the relay has heard from it. |
| `pending` | integer | How many notifications wait for the Mac. |
| `quietHours` | object | `active` (boolean) and, while quiet hours are on and the Mac reported an end, `until` (string). |
| `keys` | integer | How many agent keys and connector approvals are active. |

### `GET /v1/device/usage`

Returns today's traffic against this Mac's limits. The call does not count toward the request budget it reports.

**Request**

No parameters. The call needs the device token.

**Example request**

```sh
curl -s "$RELAY/v1/device/usage" -H "Authorization: Bearer $DEVICE_TOKEN"
```

**Example response**

```json
{
  "day": "2026-10-02",
  "requests": 120,
  "wsMessages": 40,
  "notifications": 18,
  "pollSeconds": 90,
  "audioUploads": 1,
  "audioBytes": 53214,
  "queued": 0,
  "storageBytes": 24576,
  "limits": {
    "audioUploadsPerDay": 40,
    "audioBytesPerDay": 20971520,
    "requestsPerDay": 5000,
    "freePlanRequestsPerDay": 100000,
    "notificationsPerDay": 500,
    "pollSecondsPerDay": 3000,
    "queueMax": 100
  },
  "requestsPercent": 2,
  "budgetExhausted": false
}
```

**Response fields**

| Field | Type | Description |
|---|---|---|
| `day` | string | The UTC date the counters cover. They reset at midnight UTC. |
| `requests` | integer | Requests that reached this mailbox today, except usage reads and stream connections. |
| `wsMessages` | integer | Messages Herald sent on the stream. |
| `notifications` | integer | Notifications queued today. |
| `pollSeconds` | integer | Seconds of long polling used today. |
| `audioUploads` | integer | Voice replies uploaded today. |
| `audioBytes` | integer | Bytes of voice replies uploaded today. |
| `queued` | integer | Notifications waiting for the Mac. |
| `storageBytes` | integer | The size of this mailbox's storage. |
| `limits` | object | The limits in force for this Mac. `freePlanRequestsPerDay` is Cloudflare's free-plan figure, not a relay limit. |
| `requestsPercent` | integer | `requests` as a percent of `requestsPerDay`, rounded. |
| `budgetExhausted` | boolean | `true` when `requests` has reached `requestsPerDay`. |

**Notes**

- The relay keeps the counters in memory and writes them to storage at most once a minute, so a restart can lose
  up to a minute of counting.
- `limits` shows the defaults unless the relay's owner changed them. See [Limits and errors](limits-and-errors.md).
- When `budgetExhausted` is `true`, agent routes answer `503 budget_exhausted`. The Mac can still connect, collect
  its queue and read this route.

### `POST /v1/device/status`

Reports the Mac's quiet-hours and mute state. It is how `GET /v1/status` knows whether quiet hours are on. The same
information can travel as a `status` message on the [stream](device-side.md#get-v1devicestream). The call also
marks the Mac as seen.

**Request**

| Name | In | Type | Required | Description |
|---|---|---|---|---|
| `quietActive` | body | boolean | no | `true` while quiet hours are on. Any other value counts as `false`. |
| `quietUntil` | body | string | no | When quiet hours end. The relay keeps the first 40 characters. |
| `muted` | body | boolean | no | `true` while Herald is muted. Any other value counts as `false`. |

**Example request**

```sh
curl -s -X POST "$RELAY/v1/device/status" \
  -H "Authorization: Bearer $DEVICE_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"quietActive":true,"quietUntil":"2026-10-03T07:00:00Z","muted":false}'
```

**Example response**

```json
{"ok": true}
```

**Errors**

| Status | When |
|---|---|
| `400` | The body is not JSON (`invalid_request`). |

**Notes**

- Each call overwrites the whole stored state. A field you leave out is stored as `false`, or as no end time.
- Agents see only `quietActive` and `quietUntil`, through [`GET /v1/status`](agent.md#get-v1status). The relay
  stores `muted` and does not report it.

## Related

- [Device side](device-side.md): the stream, receipts, keys, approvals and subscriptions that Herald uses.
- [Relay API overview](README.md): credentials and the error shape.
- [Limits and errors](limits-and-errors.md): every limit and error code.
- [Cloud relay](../../CLOUD.md): set up and pair a relay from **Settings > Cloud**.
- [Operating the relay](../../cloud/operating.md): clean up Macs and read usage.
- [Cloud relay API (local)](../api/relay.md): the local routes that pair and manage the relay for you.
