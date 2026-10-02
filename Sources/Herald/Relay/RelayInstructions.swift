import Foundation

/// The two ready-made instruction blocks shown under "Enable relay" in Settings > Cloud. Pure text, so the wording is tested.
public enum RelayInstructions {
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
        \(key == nil ? "\nCreate a key below to fill this in. A key is shown once; revoke it any time in Settings > Cloud." : "")
        """
    }
}
