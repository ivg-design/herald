# Connect an agent without a browser

This guide connects an agent that cannot open a web page: a sandboxed cloud agent, a job on a build server, or
anything headless. The agent prints a short code, and you approve it on your Mac. The guide is written for
whoever builds or instructs the agent; the part the user does is one click.

This is the OAuth device flow. The result is the same durable connector as in
[Connect ChatGPT](connect-chatgpt.md), with the same access.

## How it works

1. The agent registers with the relay and asks for a code.
2. The relay gives the agent a **user code** such as `BDFG-HJKM`, and shows a banner on your Mac with the same
   code.
3. The agent tells you the code. You compare it with the banner and press **Approve**.
4. The agent, which has been asking the relay whether you approved, receives its tokens.

The code exists so that you can tell that the request on your Mac is the one your agent just made.

## Before you start

- The relay is set up and **Settings > Cloud** shows **Online**. See [Cloud relay](../CLOUD.md).
- The agent can make HTTPS requests and knows the relay's address. The examples use these variables:

  ```sh
  RELAY="https://herald-relay.example.workers.dev"
  UA="User-Agent: Herald-Agent/1.0"
  ```

  Send a `User-Agent` of your own on every request. Cloudflare rejects some library defaults. See
  [Use a custom domain](custom-domain.md).

## Steps for the agent

1. Register once and keep the `client_id` from the reply.

   ```sh
   curl -s "$RELAY/register" -H "$UA" -H "Content-Type: application/json" \
     -d '{"client_name": "My cloud agent", "grant_types": ["urn:ietf:params:oauth:grant-type:device_code"]}'
   ```

   The `client_name` is the name the user will see.

2. Ask for a device code.

   ```sh
   curl -s "$RELAY/device_authorization" -H "$UA" -d client_id="$CLIENT_ID" -d scope=notify
   ```

   The reply holds the codes and says which Mac will be asked:

   ```json
   {
     "device_code": "hrv_...",
     "user_code": "BDFG-HJKM",
     "verification_uri": "https://herald-relay.example.workers.dev/activate",
     "verification_uri_complete": "https://herald-relay.example.workers.dev/activate?user_code=BDFG-HJKM",
     "expires_in": 600,
     "interval": 5,
     "device_name": "Studio Mac",
     "device_count": 1,
     "device_index": 1,
     "device_online": true
   }
   ```

3. Tell the user the code, in words like: "Approve my Herald request on your Mac. The code is BDFG-HJKM."

   On the Mac, a banner appears the moment step 2 returns: **Approve My cloud agent to send you
   notifications? Code BDFG-HJKM**, with **Approve** and **Deny**.

4. Ask for the tokens every `interval` seconds until the answer changes.

   ```sh
   curl -s "$RELAY/token" -H "$UA" \
     -d grant_type=urn:ietf:params:oauth:grant-type:device_code \
     -d client_id="$CLIENT_ID" -d device_code="$DEVICE_CODE"
   ```

   While the user has not decided, the reply is a `400` with an `error`:

   | `error` | Meaning | What to do |
   |---|---|---|
   | `authorization_pending` | The user has not answered yet. | Keep asking. |
   | `slow_down` | You asked more often than `interval`. | Add 5 seconds to your interval. |
   | `access_denied` | The user pressed **Deny**. | Stop. |
   | `expired_token` | 10 minutes passed. | Start again at step 2. |

   When the user approves, the reply is the tokens:

   ```json
   {
     "access_token": "hra_...",
     "refresh_token": "hrr_...",
     "token_type": "Bearer",
     "expires_in": 315360000,
     "scope": "notify"
   }
   ```

5. Use the access token as a bearer token on the relay.

   ```sh
   curl -s -X POST "$RELAY/v1/notify" -H "$UA" \
     -H "Authorization: Bearer $ACCESS_TOKEN" -H "Content-Type: application/json" \
     -d '{"title": "Connected", "body": "This agent can now notify you."}'
   ```

   Keep the token. It does not expire and is never replaced, so there is nothing to refresh. It works until
   the user revokes the connector in Herald.

## What the user does

The user compares the code the agent printed with the code in the banner and presses **Approve** if they
match.

![A banner titled Connector request asking whether to let Claude Desktop send notifications, with Approve and Deny buttons](../../web/public/shots/docs/banner-connector-consent.png "The approval banner for a browser sign-in. It names the connector and where it returns to. For an agent without a browser the question also shows the code the agent printed.")

If the banner was missed, the request is in **Settings > Cloud > Connector approvals**, with the agent's code
in large type and **Approve** and **Deny** beside it.

The relay also serves a page at `/activate` for a person who prefers a browser. It asks for the agent's code
and then for the 6-digit approval code that Herald shows. The agent's code alone is not enough there, because
the agent knows it.

## Rules worth knowing

- A request that nobody answers expires after 10 minutes. At most 3 wait at once, and 12 an hour.
- Asking for a device code again replaces your open request. The old `device_code` stops working and the
  banner is updated with the new code.
- With several Macs paired, the relay asks the Mac that is connected right now, or else the one seen most
  recently. Add `-d device=2` in step 2 to choose the second Mac in pairing order. Tell the user which Mac
  will show the banner, using `device_name` from the reply.
- A repeated poll after approval returns the tokens again, so a lost response costs nothing.

## Related

- [Relay API: device flow](../reference/relay/device-flow.md): every parameter of these requests.
- [Reply events](reply-events.md): be told when the user replies.
- [`GET /v1/relay/instructions`](../reference/api/relay.md#get-v1relayinstructions): get this sequence as text, with the relay's address filled in.
