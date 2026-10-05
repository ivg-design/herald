import Foundation

/// The two ready-made instruction blocks shown under "Enable relay" in Settings > Cloud. Pure text, so the wording is tested.
public enum RelayInstructions {
    /// Cloudflare's Browser Integrity Check rejects Python's default `Python-urllib/3.x` User-Agent with Error 1010 before the
    /// request reaches the relay (on every Cloudflare-fronted host). Any other value works.
    public static func userAgentNote(withKey: Bool = true) -> String {
        """
        Send a custom User-Agent (for example Herald-Agent/1.0). Cloudflare rejects Python's default "Python-urllib/3.x" with Error 1010 before the request reaches the relay; any other value works. In Python:
          req = urllib.request.Request(url, headers={"User-Agent": "Herald-Agent/1.0"\(withKey ? ", \"Authorization\": \"Bearer <key>\"" : "")})
        Other stacks (curl, requests, fetch, aiohttp) are fine as they are. A custom domain (Settings > Cloud > Advanced) turns the check off, so even default library User-Agents work.
        """
    }

    /// An agent with no usable browser (a sandbox whose browser reports net::ERR_BLOCKED_BY_CLIENT): the OAuth device flow.
    public static func deviceFlow(origin: String) -> String {
        let o = origin.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        return """
        No browser? Use the device flow (RFC 8628). The approval is still the user's, on their Mac; you only print a code.
        Send a custom User-Agent (for example Herald-Agent/1.0) on every call.

        1. Register once (no redirect URL needed). Keep client_id:
           POST \(o)/register  {"client_name":"My agent","grant_types":["urn:ietf:params:oauth:grant-type:device_code"]}
        2. Ask for a code:
           POST \(o)/device_authorization  client_id=<client_id>&scope=notify   (form-encoded)
           It returns device_code, user_code (like BDFG-HJKM), verification_uri, expires_in 600 and interval 5.
        3. TELL THE USER the user_code: "Approve my Herald request in the banner on your Mac. The code is BDFG-HJKM."
           Herald shows "Approve <you> to send you notifications? Code BDFG-HJKM" and lists it in Settings > Cloud > Connector approvals.
        4. Poll every `interval` seconds:
           POST \(o)/token  grant_type=urn:ietf:params:oauth:grant-type:device_code&client_id=<client_id>&device_code=<device_code>
           authorization_pending: keep polling. slow_down: add 5 seconds to your interval. access_denied: the user said no, stop.
           expired_token: 10 minutes passed, start again at step 2. Success returns access_token and refresh_token.
        5. Call \(o)/mcp with  Authorization: Bearer <access_token>. Keep it: the connection is durable. The token does not expire and is
           never replaced; it works until the user revokes you in Herald. You never need to refresh, and nothing is lost if you do.

        To be told when the user replies, instead of polling: subscribe once to the notification.reply event (MCP Events, protocol 2026-07-28).
        Your approval already covers it; the user does nothing. POST \(o)/mcp  events/subscribe
          {"name":"notification.reply","arguments":{},"delivery":{"mode":"webhook","url":"<your https callback>","secret":"whsec_<base64 of 24-64 random bytes>"}}
        The relay first POSTs {"type":"verification","challenge":...} to the callback: answer 2xx with the same challenge. After that each reply to one
        of your notifications arrives as a signed POST (Standard Webhooks headers) with data {notificationId, id, kind}; read the answer with get_receipt.
        The subscription does not expire: it lasts until you unsubscribe or the user revokes you.
        """
    }

    /// ChatGPT and other cloud agents that sign in with OAuth: nothing is copied but the URL; the approval happens in Herald.
    public static func oauth(mcpURL: String) -> String {
        """
        ChatGPT / OpenAI cloud agents (and any connector that signs in with OAuth)

        1. In ChatGPT open Settings > Connectors (under Advanced, turn on Developer mode if you do not see Create) and make a new connector.
        2. Name: Herald
           MCP server URL: \(mcpURL)
           Authentication: OAuth (leave the client ID and secret empty)
        3. Press Connect. A page opens in your browser and a banner appears on this Mac: press Approve on the banner. If you miss it, type the 6-digit code from Settings > Cloud > Connector approvals on the browser page.
        4. Ask the agent to use Herald, for example: "Send me a Herald notification when you are done."

        The connector can send notifications and read their receipts, nothing else. Revoke it any time in Settings > Cloud.

        No browser to sign in with (the agent cannot open the consent page)? Use the device flow: ask for client "device" in relay_instructions,
        or see docs/CLOUD.md, "No browser? Use the device flow".

        If the agent calls the relay with its own HTTP code (not as a connector):
        \(userAgentNote(withKey: false))
        """
    }

    /// Claude Code, Codex CLI and anything that takes a static key. `key` nil shows a placeholder until a key is made.
    public static func staticKey(mcpURL: String, key: String? = nil) -> String {
        let k = key ?? "<your key>"
        return """
        Claude Code / Codex CLI (a static key)

        Claude Code:
        claude mcp add --transport http herald \(mcpURL) --header "Authorization: Bearer \(k)"

        Codex ~/.codex/config.toml (put the key in the environment: export HERALD_RELAY_KEY=\(k)):
        [mcp_servers.herald]
        url = "\(mcpURL)"
        bearer_token_env_var = "HERALD_RELAY_KEY"

        Any other MCP client: URL \(mcpURL), header Authorization: Bearer \(k)

        Scripts that call the relay over HTTP:
        \(userAgentNote())
        \(key == nil ? "\nCreate a key below to fill this in. A key is shown once; revoke it any time in Settings > Cloud." : "")
        """
    }
}
