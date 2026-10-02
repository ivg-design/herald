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

    /// The Herald notification for a relay envelope. Text and presentation only, built here from a whitelist: whatever else a
    /// hostile relay might send is dropped, so no command, callback, script, shortcut or audio can come through this path.
    /// `expectReply` only adds the Reply and Record buttons: it changes neither the title, the badge, the template nor how long
    /// the banner stays.
    public static func notification(for e: RelayEnvelope, silenceSpeech: Bool) -> HeraldNotification {
        let p = e.payload
        let app = RelayDefaults.appPrefix + HeraldAgent.slug(e.key.name)
        var n = HeraldNotification(app: app, id: e.id, title: String(p.title.prefix(200)))
        n.subtitle = p.subtitle.map { String($0.prefix(200)) }
        n.body = p.body.map { String($0.prefix(8000)) }
        // A cloud link opens only if it is https; the banner's "Open link" is the user's own click.
        if let l = p.link, let u = URL(string: l), u.scheme == "https", u.host?.isEmpty == false { n.url = l }
        n.group = p.group.map { String($0.prefix(100)) }
        if let pr = p.priority, ["low", "high", "urgent"].contains(pr) { n.priority = pr }
        let expects = p.expectReply == true

        // Stays until dismissed unless the sender asks otherwise: persistent: false, or a timeout.
        let timeout = p.timeoutSeconds.flatMap { $0.isFinite ? min(3600, max(1, $0)) : nil }
        if let keep = p.persistent { n.persistent = keep } else if timeout == nil { n.persistent = true }
        if n.persistent != true { n.timeout = timeout }
        if let s = p.sound, s.range(of: soundPattern, options: .regularExpression) != nil { n.sound = s }
        if let u = p.imageURL, let url = URL(string: u), url.scheme == "https", url.host?.isEmpty == false { n.image = u }

        var meta: [String: JSONValue] = ["source": .string("cloud-relay"), "relayKey": .string(e.key.name), "relayNotificationId": .string(e.notificationId)]
        for (k, v) in [("status", p.status), ("project", p.project), ("session", p.session), ("task", p.task), ("tool", p.tool), ("duration", p.duration), ("link", n.url)] {
            if let v, !v.isEmpty { meta[k] = .string(String(v.prefix(200))) }
        }
        if let tags = p.tags?.map({ String($0.trimmingCharacters(in: .whitespaces).prefix(32)) }).filter({ !$0.isEmpty }), !tags.isEmpty {
            meta["tags"] = .array(tags.prefix(10).map { .string($0) })
        }
        if expects { meta["needsInput"] = .bool(true) }
        n.metadata = .object(meta)
        // Which of the manifest's actions this banner offers: Reply, Record (unless the sender turned it off), Open link.
        var ids = ["reply"]
        if p.allowVoiceReply != false { ids.append("record") }
        if n.url != nil { ids.append("open-link") }
        n.actionIds = ids

        let presentation = p.presentation.flatMap { HeraldPresentation(rawValue: $0) }
        if !silenceSpeech {
            var sp: HeraldSpeak? = p.speak.flatMap { speak(from: $0) }
            if sp == nil, p.speak == nil, (p.voice != nil || p.speed != nil || presentation == .voice || presentation == .both) { sp = HeraldSpeak() }
            if var s = sp {
                if s.voice == nil, let v = p.voice, v.range(of: voicePattern, options: .regularExpression) != nil { s.voice = v }
                if s.speed == nil, let v = p.speed, v >= 0.5, v <= 2 { s.speed = v }
                n.speak = s
            }
            if let presentation, n.speak != nil || presentation == .banner { n.presentation = presentation }
        } else if presentation == .banner {
            n.presentation = .banner
        }   // speech held back by quiet hours: the banner shows, whatever presentation asked for
        return n
    }

    private static let soundPattern = "^[A-Za-z0-9][A-Za-z0-9 ._-]{0,39}$"
    private static let voicePattern = "^[A-Za-z0-9_]{1,40}$"

    /// The sender's icon, when the payload carries an acceptable one: an https URL, or a `data:` PNG/JPEG/GIF/WebP of at most 256 KB.
    public static func iconSource(for e: RelayEnvelope) -> String? {
        guard let i = e.payload.icon, !i.isEmpty else { return nil }
        if i.hasPrefix("data:image/") { return i.utf8.count <= 350_000 ? i : nil }
        if let u = URL(string: i), u.scheme == "https", u.host?.isEmpty == false, i.count <= 2048 { return i }
        return nil
    }

    private static func speak(from v: JSONValue) -> HeraldSpeak? {
        switch v {
        case .bool(let b): return b ? HeraldSpeak() : nil
        case .string(let t):
            var s = HeraldSpeak()
            if !t.isEmpty { s.text = String(t.prefix(2000)) }
            return s
        case .object(let o):
            var s = HeraldSpeak()
            if case .string(let t)? = o["text"] { s.text = String(t.prefix(2000)) }
            if case .string(let t)? = o["voice"], t.range(of: voicePattern, options: .regularExpression) != nil { s.voice = t }
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
