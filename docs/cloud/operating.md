# Operate the relay

This page covers everything you do with a relay after it is set up: update it, change its settings, use it
from several Macs, run one you deployed yourself, and delete it. It ends with the full troubleshooting table.
It is for the person who owns the relay. To set one up, see [Cloud relay](../CLOUD.md).

Everything here is under **Settings > Cloud**, mostly in the **Advanced** section at the bottom of the tab.

![The Cloud tab of Settings with Advanced open: Custom domain, Devices on this relay, the relay fields and the action buttons at the bottom](../../web/public/shots/docs/settings-cloud-advanced.png#focus=88 "Advanced shows every setting of the relay, with the action buttons below the fields.")

## Update the relay

Each version of Herald carries the relay program that matches it. When the relay that is running differs from
the one inside your Herald, the **Relay** section says that a newer relay is bundled and shows an
**Update the relay** button.

Press it. Herald uploads the new program over the old one. The relay keeps its name, its address, its data and
its secrets, so this Mac stays paired and every agent key and connector keeps working.

**Redeploy** under **Advanced** does the same thing at any time.

> [!NOTE]
> An update never changes the relay's signing secret. Only a deploy over a relay that was deleted makes a new
> one. In that case this Mac's old pairing is refused, Herald pairs again by itself, and agent keys and
> connectors made before must be created again. The deploy log says "Pair this Mac again" when this happens.

## Advanced settings

Every field is visible and editable. Change a value and press **Apply settings**. A value that lives in the
relay program, such as a limit, makes Herald redeploy the relay.

| Field in Settings | What it controls | Default |
|---|---|---|
| **Relay URL** | The relay this Mac connects to. | Your deployed relay. |
| **Account id** | The Cloudflare account the relay lives in. Empty finds it from the token. | Empty. |
| **Worker name** | The relay's name in Cloudflare, which is part of its address. | `herald-relay` |
| **workers.dev subdomain** | The account's `workers.dev` address. Empty uses the account's own. | Empty. |
| **R2 bucket** | The storage bucket that holds voice replies. | `herald-relay-audio` |
| **Voice replies kept (days)** | How long a voice reply is kept before Cloudflare deletes it. | 7 |
| **Undelivered kept (hours)** | How long a notification waits for this Mac while it is offline. | 24 |
| **Notifications per day** | The most notifications agents may send this Mac in a day. | 500 |
| **Most waiting at once** | The most undelivered notifications the relay holds for this Mac. | 100 |
| **Largest request (bytes)** | The size limit of one notification request. | 32768 |
| **Per key, per 10 minutes** | The most notifications one agent key may send in 10 minutes. | 60 |
| **Macs that may pair** | How many Macs may pair with this relay. | 5 |
| **This Mac's name** | How this Mac introduces itself to the relay. Empty uses the Mac's name. | Empty. |
| **Keep-alive (seconds)** | How often Herald pings the relay to keep the connection open. | 300 |
| **Pairing secret** | The secret a Mac must present to pair. **Show secret** reveals it. | Set at the first deploy. |

The buttons below the fields:

| Button | What it does |
|---|---|
| **Apply settings** | Saves the fields, and redeploys when a relay value changed. |
| **Redeploy** | Uploads the relay program again, keeping data and secrets. |
| **Test connection** | Checks the relay and sends a notification through it and back. |
| **Pair with a code** | Pairs this Mac with the relay at **Relay URL**. For a relay Herald did not deploy. |
| **Unpair** | Ends this Mac's pairing and wipes its mailbox on the relay. |
| **Forget token** | Deletes the stored Cloudflare token from this Mac. |
| **Delete relay from Cloudflare…** | Removes the relay from your Cloudflare account. |

The same settings are available to scripts through
[`PUT /v1/relay/settings`](../reference/api/relay.md#put-v1relaysettings).

## Several Macs

One relay can serve several Macs, five by default. Each Mac has its own mailbox, its own keys and its own
limits. Set the relay up on the first Mac, then on each other Mac enter the same **Relay URL** and
**Pairing secret** under **Advanced** and press **Pair with a code**.

**Advanced > Devices on this relay** lists every Mac with its name, whether it is connected or when it was last
seen, and which one is this Mac.

How an agent reaches the right Mac:

- A key belongs to the Mac that created it, so a key always reaches that Mac.
- A connector that signs in is offered the Mac that is connected right now, or else the one seen most
  recently. The approval page names the Mac and links to the others.

The relay keeps the list clean by itself:

- A Mac that pairs again under the same name replaces its old entry, and the old mailbox is wiped.
- Unpairing removes the Mac's entry and wipes its mailbox.
- An entry is dropped when its credentials fail to verify, its mailbox is gone, or it has not connected for
  30 days.

**Remove** beside an entry is offered only for an entry this Mac may remove: one with the same name as this
Mac, one whose credentials fail to verify, or one that has not connected for a week. A different Mac that is
in use can never be removed from another Mac.

## Delete the relay

**Advanced > Delete relay from Cloudflare…** asks for confirmation and then removes the relay from your
Cloudflare account, with every mailbox, key and waiting notification.

> [!WARNING]
> This cannot be undone. Every Mac loses its pairing and every agent stops working.

The storage bucket is deleted only when it is empty. Cloudflare refuses to delete a bucket that still holds
voice replies, and Herald says so. A custom domain's DNS record and rules stay in your Cloudflare account.

To stop using the relay without deleting it, turn **Enable relay** off instead. See
[Turn the relay off](../CLOUD.md#turn-the-relay-off).

## Run your own relay

Herald's deploy is a convenience. Any relay that speaks the same protocol works: enter its address in
**Advanced > Relay URL** and press **Pair with a code**.

To deploy the same relay program yourself with Cloudflare's `wrangler` tool, from the Herald repository:

```sh
cd relay
npm install
npm test
wrangler secret put RELAY_SECRET
wrangler secret put PAIRING_SECRET
npm run r2:setup
npm run deploy
```

| Command | What it does |
|---|---|
| `npm test` | Runs the relay's tests locally. |
| `wrangler secret put RELAY_SECRET` | Sets the signing secret, once. Use 32 or more random bytes. |
| `wrangler secret put PAIRING_SECRET` | Sets the secret a Mac must present to pair. |
| `npm run r2:setup` | Creates the voice-reply bucket and its 7-day expiry rule, once. |
| `npm run deploy` | Deploys the relay to your `workers.dev` address. |

For local development, `wrangler dev` needs a file `relay/.dev.vars` that sets `RELAY_SECRET`.

Limits are set with variables on the relay program. Their names are in the
[relay API](../reference/relay-api.md#limits-and-error-codes). To restrict where
[reply events](reply-events.md) may be delivered, set `EVENT_CALLBACK_HOSTS` to a comma-separated list of host
names.

If you write your own implementation, the folder `conformance/` in the repository is a test suite that checks
any relay from the outside:

```sh
RELAY_URL="https://herald-relay.example.workers.dev" npm test -w conformance
```

## What Herald does in your Cloudflare account

Herald calls Cloudflare's API only when you deploy, change a relay setting or delete the relay. These are all
the calls it makes, so that you can check them against the token's permissions.

| Purpose | Cloudflare API call |
|---|---|
| Check that the token is active. | `GET /user/tokens/verify` |
| Find the account id. | `GET /accounts` |
| Find or create the `workers.dev` subdomain. | `GET` and `PUT /accounts/{id}/workers/subdomain` |
| Create the voice-reply bucket. | `POST /accounts/{id}/r2/buckets` |
| Set voice replies to expire. | `PUT /accounts/{id}/r2/buckets/{bucket}/lifecycle` |
| See whether the relay already exists. | `GET /accounts/{id}/workers/scripts/{name}/settings` |
| Upload the relay program and its secrets. | `PUT /accounts/{id}/workers/scripts/{name}` |
| Switch on the `workers.dev` address. | `POST /accounts/{id}/workers/scripts/{name}/subdomain` |
| Attach a custom domain. | `PUT /accounts/{id}/workers/domains` |
| Delete the relay and its bucket. | `DELETE` on the script and on the bucket. |

After a deploy, Herald asks the relay's own `/health` address until it answers.

## If it does not work

| Symptom | Cause | Fix |
|---|---|---|
| The status stays **Offline** and keeps retrying. | The Mac has no network. | Herald retries with growing pauses and reconnects at once on wake or when the network returns. |
| "the relay rejected this Mac's token". | The pairing was removed, or the relay was reset. | Press **Reconnect**, or turn **Enable relay** off and on. |
| `Relay offline — limit reached`. | A daily limit was reached. | It clears at midnight UTC. See [limits](how-it-works.md#limits). |
| An agent gets `401`. | Its key or connector was revoked, or belongs to another relay. | Check **Agent keys** and connect the agent again. |
| An agent gets `403` with error 1010. | Cloudflare's browser check rejected its `User-Agent`. | Send a custom `User-Agent`, or [use a custom domain](custom-domain.md). |
| An agent gets `429` or `503`. | A rate or daily limit was reached. | Wait for the time in `Retry-After`. Raise the limit under **Advanced** if you need to. |
| A receipt says `suppressed` with `muted` or `quiet-hours`. | Your settings held the notification back. | Nothing is wrong. |
| A receipt says `suppressed` with `expired`. | The Mac was offline for longer than **Undelivered kept (hours)**. | Nothing to fix. The notification was not shown. |
| A connector request reaches the wrong Mac. | Several Macs are paired, and another was connected. | Use the link to the right Mac on the approval page, and remove stale entries under **Devices on this relay**. |
| A connector's approval page waits and no banner shows. | Herald is not running or not online, or banners are muted. | Use the 6-digit code under **Connector approvals**. |
| **Reply subscriptions** says the relay does not support them. | The relay program is older than this Herald. | Press **Update the relay**. |

## Related

- [How the relay works](how-it-works.md): the design, the credentials and the limits.
- [Use a custom domain](custom-domain.md): give the relay an address you own.
- [Cloud relay API (local)](../reference/api/relay.md): every operation on this page, for scripts.
- [MCP relay tools](../reference/mcp/relay.md): the same, for a local agent.
