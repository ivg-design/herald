import Foundation
import HeraldClient

/// What Herald does with a notification from the cloud, given the user's mute and quiet hours.
public enum RelayDecision: Equatable, Sendable {
    /// Show it through the normal path. `silenceSpeech` is the reason when only speech is held back (a quiet window that
    /// silences speech but not banners): the banner shows, the speech does not, and the sender is told.
    case deliver(silenceSpeech: String?)
    /// Nothing is shown, played or spoken. The sender gets a `suppressed` receipt with this reason.
    case suppress(reason: String)
}

public enum RelayPolicy {
    /// `quiet` is the status already adjusted for this notification's priority (`QuietEvaluator.effective`).
    public static func decide(muted: Bool, quiet: HeraldQuietStatus) -> RelayDecision {
        if muted { return .suppress(reason: "muted") }
        if quiet.active && quiet.banners { return .suppress(reason: "quiet-hours") }
        if quiet.active && quiet.speech { return .deliver(silenceSpeech: "quiet-hours") }
        return .deliver(silenceSpeech: nil)
    }

    /// The Herald notification for a relay envelope. Text only, built here from a whitelist: whatever else a hostile relay
    /// might send is dropped, so no command, callback, script, shortcut, image or audio can come through this path.
    public static func notification(for e: RelayEnvelope, silenceSpeech: Bool) -> HeraldNotification {
        let p = e.payload
        let app = RelayDefaults.appPrefix + HeraldAgent.slug(e.key.name)
        var n = HeraldNotification(app: app, id: e.id, title: String(p.title.prefix(200)))
        n.subtitle = p.subtitle.map { String($0.prefix(200)) }
        n.body = p.body.map { String($0.prefix(8000)) }
        // A cloud link opens only if it is https; the banner's "Open link" is the user's own click.
        if let l = p.link, let u = URL(string: l), u.scheme == "https", u.host?.isEmpty == false { n.url = l }
        n.group = p.group.map { String($0.prefix(100)) }
        n.priority = p.priority == "urgent" ? "urgent" : nil
        let expects = p.expectReply == true
        n.persistent = expects ? true : nil
        var meta: [String: JSONValue] = ["source": .string("cloud-relay"), "relayKey": .string(e.key.name), "relayNotificationId": .string(e.notificationId)]
        for (k, v) in [("status", p.status), ("project", p.project), ("session", p.session), ("task", p.task), ("tool", p.tool), ("duration", p.duration), ("link", n.url)] {
            if let v, !v.isEmpty { meta[k] = .string(String(v.prefix(200))) }
        }
        if expects { meta["needsInput"] = .bool(true); if meta["status"] == nil { meta["status"] = .string("question") } }
        n.metadata = .object(meta)
        // Which of the manifest's actions this banner offers: Reply, Record (unless the sender turned it off), Open link.
        var ids = ["reply"]
        if p.allowVoiceReply != false { ids.append("record") }
        if n.url != nil { ids.append("open-link") }
        n.actionIds = ids
        if !silenceSpeech, let s = p.speak { n.speak = speak(from: s) }
        return n
    }

    private static func speak(from v: JSONValue) -> HeraldSpeak? {
        switch v {
        case .bool(let b): return b ? HeraldSpeak() : nil
        case .object(let o):
            var s = HeraldSpeak()
            if case .string(let t)? = o["text"] { s.text = String(t.prefix(2000)) }
            if case .string(let t)? = o["voice"], t.range(of: "^[A-Za-z0-9_]{1,40}$", options: .regularExpression) != nil { s.voice = t }
            if case .number(let n)? = o["speed"], n >= 0.5, n <= 2 { s.speed = n }
            if case .string(let t)? = o["lang"], t.range(of: "^[A-Za-z]{2,3}(-[A-Za-z0-9]{2,8})?$", options: .regularExpression) != nil { s.lang = t }
            return s
        default: return nil
        }
    }
}

/// The text a user pastes into a cloud agent's connector settings, for one agent key.
public enum ConnectorConfig {
    public static func mcpURL(relay: String) -> String {
        relay.trimmingCharacters(in: CharacterSet(charactersIn: "/ ")) + "/mcp"
    }

    /// A ready-to-paste block: the URL and Bearer for any remote-MCP client, then Claude Code and Codex forms.
    public static func block(relayURL: String, key: String, name: String) -> String {
        let url = mcpURL(relay: relayURL)
        let server = "herald"
        return """
        # Herald cloud relay: notifications only (send_notification, get_receipt, wait_for_reply, herald_status)
        # Key "\(name)". It is shown once. Anyone holding it can notify you, nothing else. Revoke it in Herald > Settings > Cloud.

        # Any remote MCP connector (Claude.ai custom connector, ChatGPT, others)
        URL:            \(url)
        Authorization:  Bearer \(key)

        # Claude Code
        claude mcp add --transport http \(server) \(url) --header "Authorization: Bearer \(key)"

        # Claude Code .mcp.json / Claude Agent SDK
        {"mcpServers":{"\(server)":{"type":"http","url":"\(url)","headers":{"Authorization":"Bearer \(key)"}}}}

        # Codex ~/.codex/config.toml (put the key in the environment: export HERALD_RELAY_KEY=\(key))
        [mcp_servers.\(server)]
        url = "\(url)"
        bearer_token_env_var = "HERALD_RELAY_KEY"
        """
    }
}
