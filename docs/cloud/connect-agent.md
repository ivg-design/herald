# Connect an agent with a key

This guide connects a cloud agent to your relay with an **agent key**: a secret string you create in Herald and
paste into the agent. Use it for Claude Code, Codex, a script, a build server, or any client that can send an
HTTP header. At the end, the agent can put a notification on your Mac and read your reply.

ChatGPT cannot take a pasted key. For it, see [Connect ChatGPT](connect-chatgpt.md).

## Before you start

- Your relay is set up and **Settings > Cloud** shows **Online**. See [Cloud relay](../CLOUD.md).
- You can edit the agent's configuration, or run a command on the machine where it runs.

## Steps

1. Open **Settings > Cloud** and find the **Agent keys** section.

   ![The Cloud tab of Settings with the Agent keys section](../../web/public/shots/docs/settings-cloud-paired.png#focus=74 "Agent keys is near the bottom of the Cloud tab: a name field, the Agent menu and the Create key button.")

2. Type a name for the key, for example `build-bot`, choose the agent in the **Agent** menu (**Claude**,
   **Codex** or **Other**), and press **Create key**.

   A sheet shows the key and says to copy it now, because it is not shown again. The relay keeps only a hash
   of the key, so Herald cannot show it later.

3. Press **Copy connector config**, then **Done**.

   The clipboard now holds a ready configuration for the agent you chose, with the address and the key filled
   in.

4. Give the configuration to the agent. What you paste depends on the agent:

   | Agent | What to do |
   |---|---|
   | Claude Code | Run the copied `claude mcp add` command in a terminal. |
   | Codex | Add the copied block to `~/.codex/config.toml` and set the environment variable it names. |
   | Any other MCP client | Add a remote MCP server with the address and an `Authorization: Bearer` header. |
   | A script | Call the relay over HTTPS with the same header. See the example below. |

   For Claude Code the command looks like this:

   ```sh
   claude mcp add --transport http herald "$RELAY/mcp" --header "Authorization: Bearer $KEY"
   ```

   For Codex the block looks like this, with the key in the `HERALD_RELAY_KEY` environment variable:

   ```toml
   [mcp_servers.herald]
   url = "https://herald-relay.example.workers.dev/mcp"
   bearer_token_env_var = "HERALD_RELAY_KEY"
   ```

5. Ask the agent to send you a notification, for example "Send me a Herald notification saying hello".

   A banner appears on your Mac. Its sender is the key's name.

> [!TIP]
> The **Connect an agent** section of the Cloud tab has a shortcut for Claude Code: **Create a key and copy
> the config** does steps 2 and 3 in one press, with a key named `claude-code`.

## Send from a script

A script does not need MCP. It posts JSON to the relay with the key in a header.

```sh
RELAY="https://herald-relay.example.workers.dev"
KEY="hrk_..."
curl -s -X POST "$RELAY/v1/notify" \
  -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" \
  -H "User-Agent: Herald-Agent/1.0" \
  -d '{"title": "Build finished", "body": "All 214 tests passed."}'
```

> [!WARNING]
> Send a `User-Agent` header of your own, as above. Cloudflare rejects the default header of some libraries,
> Python's `urllib` among them, with error 1010 before the request reaches your relay. See
> [Use a custom domain](custom-domain.md) for the cause and the alternative.

Every field a notification may carry, and the other endpoints, are in the
[relay API](../reference/relay/README.md).

## Check that it works

Look at **Last relay items** in **Settings > Cloud**. The notification is listed with the key's name and what
happened to it: displayed, spoken, replied, or the reason it was held back.

## What you see on the Mac

Notifications sent with a key arrive from an app named `cloud.` followed by the key's name, for example
`cloud.build-bot`. The app appears in **Settings > Apps** like any other, with its own sound and History. A key
made for Claude or Codex gets that product's icon when it is installed on your Mac.

To change how the agent's banners look, press **Design…** beside the key. The Designer opens with the agent's
template.

Every cloud banner has two buttons for answering:

- **Reply** opens a text field in the banner. What you type goes back to the agent.

  ![A banner with the inline reply field open](../../web/public/shots/docs/banner-reply.png "Reply turns the buttons into a text field. The agent reads your answer from the relay.")

- **Record** opens a recording strip in the banner, for a voice reply of up to 60 seconds. Nothing records
  until you press it, and macOS asks for the microphone the first time. The recording is transcribed on your
  Mac, and the agent receives the transcript and a link to the audio.

  ![A banner with the recording strip open: a red dot, 0:07 of 60 s, a Stop button and a cancel cross](../../web/public/shots/docs/banner-record.png "Record shows the elapsed time out of 60 seconds, with Stop and a button to cancel.")

An agent can hide **Record** for a notification, and it can ask the relay to tell it the moment you reply. See
[Reply events](reply-events.md).

## Revoke a key

Press **Revoke** beside the key in **Agent keys**. The key stops working at once. The agent's app and its
History stay in Herald until you remove the app in **Settings > Apps**.

## If it does not work

| Symptom | Cause | Fix |
|---|---|---|
| The agent gets `401`. | The key was revoked, was mistyped, or belongs to another relay. | Create a new key and paste it again. |
| The agent gets `403` with error 1010. | Cloudflare's browser check rejected the request's `User-Agent`. | Send a custom `User-Agent`. See [Use a custom domain](custom-domain.md). |
| The agent gets `429`. | It sent more than 60 notifications in 10 minutes, or a daily limit was reached. | Wait for the time in the `Retry-After` header. See [limits](how-it-works.md#limits). |
| The agent gets `400` with `forbidden_fields`. | The notification has a field the relay does not accept. | Remove the fields the error lists. |
| The receipt says `suppressed`. | Mute or quiet hours held the notification back. | Nothing is wrong. Your settings win. |
| No banner, and **Last relay items** is empty. | The agent is sending to another address. | Compare its address with the **Connector URL**. |

## Related

- [Relay API](../reference/relay/README.md): every field, endpoint and error an agent can meet.
- [How the relay works](how-it-works.md): what a key can and cannot do.
- [`POST /v1/relay/keys`](../reference/api/relay.md#post-v1relaykeys): create a key from a script.
- [`create_agent_key`](../reference/mcp/relay.md#create_agent_key): let a local agent create the key.
