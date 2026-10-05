import Foundation

/// The two ready-made instruction blocks shown under "Enable relay" in Settings > Cloud. Pure text, so the wording is tested.
public enum RelayInstructions {
    /// One line, not a lesson: Cloudflare's Browser Integrity Check rejects Python's default `Python-urllib/3.x` User-Agent
    /// with Error 1010; the docs page explains. Any other value works.
    public static func userAgentNote(withKey: Bool = true) -> String {
        "Calling the relay from your own HTTP code? Send a custom User-Agent such as Herald-Agent/1.0 (Cloudflare blocks Python's default). Details: \(docsLink(for: .other))"
    }

    // MARK: The agents of the picker in Settings > Cloud > Connect an agent

    public enum Agent: String, CaseIterable, Identifiable, Sendable {
        case chatgpt, claudeCode, codex, other
        public var id: String { rawValue }
        public var title: String {
            switch self {
            case .chatgpt: return "ChatGPT or an OpenAI dot"
            case .claudeCode: return "Claude Code"
            case .codex: return "Codex"
            case .other: return "Other"
            }
        }
        /// The docs page that explains it, under docs/ (see `HeraldDocs`).
        public var docsPage: String {
            switch self {
            case .chatgpt: return "cloud/connect-chatgpt"
            case .claudeCode, .codex, .other: return "cloud/connect-agent"
            }
        }
    }

    public static func docsLink(for agent: Agent) -> String { HeraldDocs.baseURL + "/" + agent.docsPage }

    /// A value to copy: a URL, a command or a config block.
    public struct CopyLine: Equatable, Sendable { public var label: String; public var text: String }

    /// At most five short steps for one agent. `key` nil shows a placeholder until a key is made.
    public static func steps(for agent: Agent, key: String? = nil) -> [String] {
        let keyStep = key == nil ? "Create a key below (Agent keys) and copy it. It is shown once."
                                 : "Use the key you just created. It is shown once; revoke it any time in Settings > Cloud."
        switch agent {
        case .chatgpt:
            return ["In ChatGPT's settings, add a custom MCP server (connector). Developer mode may be required. An OpenAI dot takes the same URL.",
                    "Name it Herald, paste the MCP server URL below and choose Authentication: OAuth (leave client ID and secret empty).",
                    "Press Connect, then press Approve on the banner on this Mac. Missed it? Type the 6-digit code from Settings > Cloud > Connector approvals into the browser page.",
                    "Ask the agent to send you a Herald notification. Revoke the connector any time in Settings > Cloud."]
        case .claudeCode:
            return [keyStep, "Run this command in a terminal.", "Ask Claude Code to send you a Herald notification."]
        case .codex:
            return [keyStep, "Put the key in the environment.", "Add the server to ~/.codex/config.toml.", "Ask Codex to send you a Herald notification."]
        case .other:
            return [keyStep, "Use the MCP URL below and send the key in the Authorization header.",
                    "From your own HTTP code, also send a custom User-Agent such as Herald-Agent/1.0 (Cloudflare blocks Python's default)."]
        }
    }

    /// The values the steps point at, each worth one copy button.
    public static func copyLines(for agent: Agent, mcpURL: String, key: String? = nil) -> [CopyLine] {
        let k = key ?? "<your key>"
        switch agent {
        case .chatgpt: return [CopyLine(label: "MCP server URL", text: mcpURL)]
        case .claudeCode: return [CopyLine(label: "Command", text: "claude mcp add --transport http herald \(mcpURL) --header \"Authorization: Bearer \(k)\"")]
        case .codex:
            return [CopyLine(label: "Environment", text: "export HERALD_RELAY_KEY=\(k)"),
                    CopyLine(label: "~/.codex/config.toml", text: "[mcp_servers.herald]\nurl = \"\(mcpURL)\"\nbearer_token_env_var = \"HERALD_RELAY_KEY\"")]
        case .other: return [CopyLine(label: "MCP URL", text: mcpURL), CopyLine(label: "Header", text: "Authorization: Bearer \(k)")]
        }
    }

    /// Everything for one agent as plain text: numbered steps, the values, and the guide's address.
    public static func text(for agent: Agent, mcpURL: String, key: String? = nil) -> String {
        var out = [agent.title, ""]
        for (i, step) in steps(for: agent, key: key).enumerated() { out.append("\(i + 1). \(step)") }
        for line in copyLines(for: agent, mcpURL: mcpURL, key: key) { out += ["", "\(line.label):", line.text] }
        if agent == .chatgpt { out += ["", "No browser to sign in with? Use the device flow: ask relay_instructions for client \"device\", or read \(HeraldDocs.baseURL)/cloud/device-flow"] }
        out += ["", userAgentNote(), "Guide: \(docsLink(for: agent))"]
        return out.joined(separator: "\n")
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

        To be told when the user replies instead of polling, subscribe to the notification.reply event: \(HeraldDocs.baseURL)/cloud/reply-events
        Guide: \(HeraldDocs.baseURL)/cloud/device-flow
        """
    }

    /// ChatGPT, an OpenAI dot and other cloud agents that sign in with OAuth: nothing is copied but the URL; the approval happens in Herald.
    public static func oauth(mcpURL: String) -> String { text(for: .chatgpt, mcpURL: mcpURL) }

    /// Claude Code, Codex CLI and anything that takes a static key. `key` nil shows a placeholder until a key is made.
    public static func staticKey(mcpURL: String, key: String? = nil) -> String {
        [Agent.claudeCode, .codex, .other].map { text(for: $0, mcpURL: mcpURL, key: key) }.joined(separator: "\n\n")
    }
}
