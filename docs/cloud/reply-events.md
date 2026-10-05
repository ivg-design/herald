# Reply events

A cloud agent that asks you a question needs your answer. It can keep asking the relay whether you replied, or
it can subscribe once and be called the moment you do. This page explains reply subscriptions, shows where you
see and end them on the Mac, and points to the guide for connecting an OpenAI dot, an always-on cloud agent that wakes
only when its host is called.

It is for people who build or run a cloud agent. If your agent only sends notifications and never waits for an
answer, you do not need this page.

## Polling and subscribing

There are two ways for an agent to get your reply.

| Way | How it works | Good for |
|---|---|---|
| **Polling** | The agent calls `wait_for_reply`, which holds the request open until you answer or a timeout passes. | An agent that is running anyway while it waits. |
| **Subscribing** | The agent gives the relay a web address. The relay calls that address when you reply. | An agent that is not running while it waits, and must be woken. |

A subscription is the MCP Events mechanism, protocol version `2026-07-28`. The event is named
`notification.reply`.

## What a reply event carries

The event fires once per notification, the first time you answer it, whether you typed or recorded. It fires
only for notifications sent by the same connector that subscribed.

The event carries ids, never your answer:

```json
{"notificationId": "question-17", "id": "r_13cb91ec8efd0eab", "kind": "text"}
```

| Field | Type | Description |
|---|---|---|
| `notificationId` | string | The id the agent gave the notification. |
| `id` | string | The relay's delivery id. |
| `kind` | string | `text` for a typed reply, `voice` for a recorded one. |

The agent then reads the answer itself, with `get_receipt` or `wait_for_reply`. Your words therefore travel
only over the agent's own authenticated connection, not to a callback address.

## Nothing to approve

You approved the connector when it connected. That approval is what authorises its subscriptions: there is no
code, no password and no second question on the Mac.

A subscription is as durable as the connection. It does not expire and needs no renewing. It ends when the
agent unsubscribes, when you end it in Settings, or when you revoke the connector. A connector may hold up to
5 subscriptions.

## See and end subscriptions on the Mac

**Settings > Cloud > Reply subscriptions** lists every subscription: which connector, which host it calls, and
whether anything is waiting to be delivered. Press **End** to stop one. The connector stays approved and may
subscribe again.

![The Cloud tab of Settings with the Reply subscriptions section showing one subscription and an End button](../../web/public/shots/docs/settings-cloud-paired.png#focus=52 "Reply subscriptions sits below Connector approvals. Each row names the connector and the host that is called, with an End button.")

The path of the callback address and its secret are never shown, in Settings or through any API. From a
script, use [`GET /v1/relay/events`](../reference/api/relay.md#get-v1relayevents).

## How an agent subscribes

An agent subscribes by calling `events/subscribe` on the relay's `/mcp` endpoint with the event name and a
delivery target. The full protocol, with requests and responses, is in the
[relay API](../reference/relay/events.md). In outline:

1. The agent makes a secret and sends `events/subscribe` with a webhook address and that secret.
2. The relay posts a signed challenge to the address. The address must answer with the same challenge.
3. From then on, each reply produces one signed request to the address.

The rules the relay applies:

| Rule | Detail |
|---|---|
| Address | `https`, on the default port, on a public host, with no credentials in it, at most 2048 characters. |
| Local addresses | Local, private and reserved addresses are always refused. |
| Verification | A callback that cannot be reached, answers with an error, or returns the wrong challenge is refused. The error says which. |
| Signature | Each request is signed with the secret, in the Standard Webhooks format. |
| Retries | Network errors and the statuses `408`, `429` and `5xx` are retried with growing pauses, for up to a day. |
| Ending | An answer of `410` ends the subscription. Any other `4xx` drops that one event. |
| Missed events | Subscribing with a cursor replays up to 100 later replies of the last 30 days. |

On a relay you operate yourself, you can limit callbacks to named hosts with the relay variable
`EVENT_CALLBACK_HOSTS`. See [Operate the relay](operating.md#run-your-own-relay).

## Connect an OpenAI dot

An OpenAI dot wakes only when its host is called, and the host does that only for an MCP server registered as an app
behind an installed plugin. [Connect an OpenAI dot](connect-dot.md) walks through the one-time steps.

## Related

- [Relay API: reply events](../reference/relay/events.md): `events/subscribe` and the webhook format in full.
- [Connect ChatGPT](connect-chatgpt.md): the approval flow used in step 2.
- [`DELETE /v1/relay/events/subscriptions/{id}`](../reference/api/relay.md#delete-v1relayeventssubscriptionsid): end a subscription from a script.
- [`relay_events`](../reference/mcp/relay.md#relay_events): list subscriptions from a local agent.
