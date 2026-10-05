# How the relay works

This page explains the design of the cloud relay: what the parts are, which credential does what, what the
relay can and cannot see, and the limits it enforces. Read it when you want to judge whether the relay is safe
to use, or when you need to understand a limit you ran into. To set a relay up, see
[Cloud relay](../CLOUD.md).

## The parts

Three programs take part in a cloud notification.

| Part | Where it runs | What it does |
|---|---|---|
| **The agent** | In the cloud. | Sends a notification to the relay and asks later what happened to it. |
| **The relay** | In your Cloudflare account. | Checks the agent's credential, validates the notification and keeps it in a mailbox. |
| **Herald** | On your Mac. | Keeps one outgoing connection to the relay, takes notifications out and shows them. |

The relay keeps one **mailbox** per Mac. A mailbox holds the notifications waiting for that Mac, the keys that
may send to it, and the receipts and replies going back.

```text
agent ──▶ relay: "show this"            (agent key or connector token)
          relay ──▶ mailbox: stored
Herald ◀── mailbox: delivered           (over Herald's outgoing connection)
Herald ──▶ relay: "displayed", "replied: yes, ship it"
agent ──▶ relay: "what happened?"  ◀── receipt and reply
```

If your Mac is asleep or offline, the notification waits in the mailbox for up to 24 hours and is delivered
when Herald reconnects.

## What an agent can do

An agent that holds a valid credential can do exactly four things:

1. Send a notification made of text and presentation choices.
2. Read the receipt of a notification it sent.
3. Wait for your reply to a notification it sent.
4. Ask whether your Mac is online and whether quiet hours are on.

It cannot run commands, scripts or Shortcuts. It cannot add a follow-up. It cannot add buttons that call a server,
show a picture from a file, or play audio. It cannot read your History, see another agent's notifications, change
settings, or create or approve keys. The fields and endpoints are in the [relay API](../reference/relay/README.md).

You can give a connector's notifications a follow-up in the Designer. See
[Forward a notification you missed](../FORWARD-MISSED.md).

A cloud notification arrives in Herald as an ordinary notification of an app named `cloud.` followed by the
key's name, so it has its own entry in **Settings > Apps**, its own History and its own template.

## Receipts

An agent learns what happened to a notification from its **receipt**. A receipt is a set of separate facts,
each recorded by the part that knows it.

| Receipt | Recorded by | Meaning |
|---|---|---|
| `received` | The relay. | The relay accepted the notification. It may still be waiting for the Mac. |
| `displayed` | Herald. | The banner was shown. |
| `spoken` | Herald. | Speech played to the end. |
| `replied` | Herald. | You answered. The reply text or transcript comes with it. |
| `suppressed` | Herald. | Your settings held it back. A reason says why. |

The reasons for `suppressed` are `muted`, `quiet-hours`, `expired` (it waited 24 hours) and
`delivery-failed`. Quiet hours can hold back only the speech and still show the banner; the receipt then
carries the scope `speech`.

Mute and quiet hours are enforced on the Mac, by Herald, with your real settings. The relay only learns
whether quiet hours are on, so that an agent can ask.

## Credentials

Each kind of caller has its own credential, and none of them works in another's place.

| Credential | Looks like | Held by | Allows |
|---|---|---|---|
| **Device token** | `hrd_...` | Herald on one Mac. | Reading that Mac's mailbox and managing its keys. |
| **Agent key** | `hrk_...` | An agent you gave it to. | The four agent actions, for one Mac. |
| **Connector tokens** | `hra_...`, `hrr_...` | An agent that signed in with OAuth. | The same four agent actions. |

- **A device token** is created when a Mac pairs with the relay. Herald stores it on the Mac and the relay
  stores only its hash.
- **An agent key** can be created only by a paired Mac. The only scope that exists is `notify`. The relay
  stores keys as hashes, compares them in constant time, and can revoke one instantly. A key is bound to one
  Mac and sees only the notifications sent with it.
- **A connector** is an agent that signed in through OAuth and that you approved on your Mac. It gets the same
  access as a key. Its tokens do not expire and are never rotated: the connector works until you revoke it.

Agent credentials are refused on the device routes, and a device token is refused on the agent routes. No
route changes permissions, settings or quiet hours on the Mac.

## Why a hostile relay cannot harm your Mac

The notification is filtered twice. The relay accepts only a fixed list of fields and rejects a request that
contains anything else. Herald then rebuilds the notification from its own fixed list, ignoring whatever else
the relay sent.

So even a relay that someone tampered with can at most show you text. It cannot make Herald run a command,
call a server or play a file. A sound is a name, never a path. The only things Herald fetches are an icon and
a preview image from `https` addresses the sender names, and both are decoded as images and limited in size.
A link opens only when you press its button.

## Pairing

A Mac pairs with a one-time code that is valid for 10 minutes and can be used once. Herald does this for you
at the end of a deploy.

Herald also sets a **pairing secret** on the relay when it deploys it. The relay demands that secret before it
hands out a pairing code, so a stranger who finds the relay's address cannot pair a Mac with it. A relay can
serve up to five Macs.

## What Herald stores where

| What | Where it is kept |
|---|---|
| Cloudflare API token | Herald's secret store on this Mac. Sent only to `api.cloudflare.com`. |
| Pairing secret | Herald's secret store, and as a secret on the relay. |
| Relay signing secret | Herald's secret store, and as a secret on the relay. It signs device ids. |
| Device token | Herald's secret store. |
| Account id, names, limits | The file `relay-cloudflare.json` in Herald's support folder. It holds no secrets. |

Herald's **secret store** is the macOS data-protection keychain, limited to this device. It never shows a
password prompt. On a build where that keychain is not available, Herald keeps each secret in a file readable
only by your user account, in `~/Library/Application Support/Herald/secrets/`. The `herald` command and the MCP
server never read these secrets.

## What the relay can read

Notification text and your replies pass through the relay. They stay in the mailbox for up to 24 hours, and a
voice reply stays for 7 days. The relay runs in your own Cloudflare account, so this data is under your
control and Cloudflare's, and nobody else's.

Voice replies are transcribed on your Mac, not in the cloud. The audio file is uploaded so that the agent can
fetch it through a signed link that is valid for one hour.

## Limits

The relay is built to live within Cloudflare's free plan. Every paired Mac has its own mailbox, so **every
limit is per Mac**: one busy Mac or key cannot use up another's allowance.

| Limit, per Mac | Default | What the agent gets when it is reached |
|---|---|---|
| Notifications per day | 500 | `429` with `daily_cap`, until midnight UTC. |
| Notifications waiting for the Mac | 100 | `429` with `queue_full`. |
| Requests to the mailbox per day | 5,000 | `503` with `budget_exhausted`, until midnight UTC. |
| Voice replies per day | 40, and 20 MB | `429` with `daily_cap`. |
| Seconds agents may wait for replies per day | 3,000 | Waits answer at once. |
| How long an undelivered notification is kept | 24 hours | A `suppressed` receipt with `expired`. |
| Notifications per key per 10 minutes | 60 | `429` with a `Retry-After` header. |
| Largest notification request | 32 KB | `413`. |
| Receipt and reply reads per key per 10 minutes | 600 | `429`. |
| Macs that may pair | 5 | `403` with `device_limit`. |

You can change most of these under **Settings > Cloud > Advanced**. The setting behind each one is listed in
the [relay setting keys](../reference/api/relay.md#relay-setting-keys).

Pairing has its own limits, counted per network address: 6 pairing attempts an hour and 10 wrong codes in 10
minutes. One address cannot lock the others out.

### How the limits fit the free plan

| Cloudflare resource | Free plan allowance | How the relay stays inside it |
|---|---|---|
| Requests | 100,000 a day | Each Mac is capped at 5,000 mailbox requests a day. Junk without a credential is rejected early. |
| Storage rows written | 100,000 a day | A notification writes about 10 rows. Counters are written once a minute. |
| Mailbox running time | 13,000 GB-seconds a day | Herald's idle connection does not keep the mailbox awake. Only waiting for replies does, and that is capped. |
| Mailbox storage | 5 GB | Notifications are deleted after 25 hours. |
| File storage | 10 GB a month | Only voice replies, at most 1 MB each, deleted after 7 days. |

With every Mac at every limit, about 20 Macs fill the free plan. In normal use, a few dozen notifications a
day, a Mac uses about one percent of its limits.

### When a limit is reached

Agents get `429` or `503` with a `Retry-After` header. Herald shows `Relay offline — limit reached` in
**Settings > Cloud** and retries by itself. Nothing is lost silently: notifications already accepted stay in
the mailbox and are delivered when the Mac reconnects.

To see today's numbers, look at **Usage today** in **Settings > Cloud**, or call
[`GET /v1/relay/usage`](../reference/api/relay.md#get-v1relayusage).

## Related

- [Cloud relay](../CLOUD.md): set the relay up.
- [Operate the relay](operating.md): change limits, add Macs, update or delete the relay.
- [Relay API](../reference/relay/README.md): the endpoints, fields and error codes in full.
