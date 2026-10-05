# Connect an OpenAI dot

An OpenAI dot is an always-on cloud agent. By the end of this page your dot can send notifications to your Mac,
and your reply on the Mac can wake it. It is for people who run a dot and own a Herald relay.

A dot does not run while it waits for you, so a reply has to wake it, and only its host can do that. The host hands
out a wake-up address only for an MCP server it knows as an **app behind an installed plugin**. A connection the
dot makes from its own code, for example with the [device flow](device-flow.md), can send notifications and read
receipts, but it can never be woken by a reply. To be woken, Herald must be registered with the host as an app.
The folder [`integrations/dot-plugin`](../../integrations/dot-plugin/README.md) in the Herald repository holds the
plugin that does this, named `herald-connection`. Nothing in it is a secret.

## Before you start

- Your relay is set up and **Settings > Cloud** shows **Online**. See [Cloud relay](../CLOUD.md).
- You have a ChatGPT account with developer mode available, and a dot.
- You have the Herald repository, for the plugin folder.
- You know your relay's MCP address, `https://<your-relay>/mcp`. It is the **Connector URL** in **Settings > Cloud**.

## Steps

1. In ChatGPT, turn on developer mode and create a custom MCP app.

   | Field | Value |
   |---|---|
   | Name | `Herald Connection` |
   | MCP server URL | Your **Connector URL** from **Settings > Cloud**. |
   | Authentication | OAuth. Leave the client id and client secret empty. |

2. Press **Connect**.

   The relay's approval page opens, and a banner on your Mac asks whether to let the app send you
   notifications. Press **Approve**. If you missed the banner, the 6-digit code is in
   **Settings > Cloud > Connector approvals**.

   ![A banner titled Connector request asking whether to let Claude Desktop send notifications, with Approve and Deny buttons](../../web/public/shots/docs/banner-connector-consent.png "Approve the app once. Here the connector is Claude Desktop; yours names the app you registered. The approval is durable and also covers its reply subscriptions.")

3. Copy the id of the registered app. It starts with `asdk_app_`.

4. In the plugin folder, open `herald-connection/.app.json` and put the id in place of
   `REPLACE_WITH_REGISTERED_APP_ID`.

   If a package of the plugin was installed before, raise the version in the plugin's `plugin.json` so that
   the host takes the new one.

5. Install the plugin for your dot and activate it.

6. Ask the dot to subscribe to `notification.reply` on the Herald Connection app, through the host's MCP
   Events support.

   The host supplies the callback address and the secret. The relay verifies the callback with a signed
   challenge. Nothing is asked on the Mac.

## Check that it works

1. Ask the dot to send a notification that expects a reply.
2. Reply on the Mac.
3. Look at **Settings > Cloud > Reply subscriptions**. The subscription is listed, from the connector to the
   host's callback host, with nothing waiting.
4. Confirm that the dot actually ran and saw your answer.

> [!NOTE]
> A `2xx` answer from the callback is a receipt: it proves that the host received the event. It does not prove that
> the dot woke. Only step 4 does.

## What Herald shows afterwards

**Connector approvals** and **Agent keys** list a connector named after the name the host signs in with, for
example `ChatGPT`, and **Reply subscriptions** lists the subscription. If the dot connected earlier from its own code, that older connection is now redundant. You
can revoke it; the new connector is not affected, because each approval is its own key.

## If it does not work

| Symptom | Cause | Fix |
|---|---|---|
| The host's subscribe call fails with error `-32015`. | The relay could not verify the callback. | Read `data.reason`: `unreachable`, `bad_status`, `challenge_mismatch` or `host_not_allowed`. |
| **Reply subscriptions** says the relay does not support them. | The relay program is out of date. | Press **Update the relay** in **Settings > Cloud**. |
| The subscription is listed but the dot does not wake. | The host received the event and did not start the dot. | Check the plugin's app id and that the plugin is active for the dot. |
| The dot sends notifications but nothing is listed under **Reply subscriptions**. | The dot is connected from its own code, not through the plugin. | Follow the steps above. |

## Related

- [Reply events](reply-events.md): what a reply event carries and how subscriptions work.
- [Connect ChatGPT](connect-chatgpt.md): the approval flow used in step 2.
- [Relay API: reply events](../reference/relay/events.md): `events/subscribe` and the webhook format in full.
- [`relay_events`](../reference/mcp/relay.md#relay_events): list subscriptions from a local agent.
- [`DELETE /v1/relay/events/subscriptions/{id}`](../reference/api/relay.md#delete-v1relayeventssubscriptionsid): end a subscription from a script.
