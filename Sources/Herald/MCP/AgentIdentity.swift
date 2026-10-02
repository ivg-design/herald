import Foundation

/// An installed MCP client as a notification issuer (issue #62): its own app id, manifest and default template, so
/// the agent's notifications arrive under their own identity and the user designs their look like any other issuer.
///
/// `agent.claude-code`, `agent.codex`, `agent.claude-desktop` are fixed; a generic client gets `agent.<slug>` from the
/// name the user types. The manifest declares what an agent has to say (title, body, a status badge, the project,
/// a session and task id, the last tool, a duration, a link back, whether it needs an answer) and the actions it
/// offers (open, reply, dismiss). The default template is `builtin.compact` with a body line, the status badge
/// carrying an SF Symbol per agent, the project and the action row.
public struct AgentIdentity: Equatable, Sendable {
    public enum Kind: String, CaseIterable, Sendable {
        case claudeCode, codex, claudeDesktop, generic
    }

    public let kind: Kind
    /// `claude-code`, `codex`, `claude-desktop`, or the slug of a generic client's name.
    public let slug: String
    public let name: String
    /// The SF Symbol on the status badge.
    public let symbol: String
    /// The app's default sound.
    public let sound: String
    /// Where the "Open" action goes when a notification names no link of its own.
    public let homepage: String

    public static let templateName = "agent"
    public var appID: String { HeraldAgent.prefix + slug }

    public init?(kind: Kind, genericName: String? = nil) {
        self.kind = kind
        switch kind {
        case .claudeCode: (slug, name, symbol, sound, homepage) = ("claude-code", "Claude Code", "terminal", "Glass", "https://claude.com/claude-code")
        case .codex: (slug, name, symbol, sound, homepage) = ("codex", "Codex", "sparkles", "Tink", "https://openai.com/codex")
        case .claudeDesktop: (slug, name, symbol, sound, homepage) = ("claude-desktop", "Claude Desktop", "message.circle", "Pop", "https://claude.ai")
        case .generic:
            let typed = (genericName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let s = HeraldAgent.slug(typed)
            guard !s.isEmpty else { return nil }
            (slug, name, symbol, sound, homepage) = (s, typed, "bolt.circle", "Glass", "https://modelcontextprotocol.io")
        }
    }

    /// By the client keys the API uses (`claudeCode`, `codex`, `claudeDesktop`, `generic`).
    public static func client(_ key: String, genericName: String? = nil) -> AgentIdentity? {
        Kind(rawValue: key).flatMap { AgentIdentity(kind: $0, genericName: genericName) }
    }

    /// `--agent <slug>`, written into the server's configuration.
    public var serverArguments: [String] { ["--agent", slug] }

    // MARK: Manifest

    public func manifest(icon: String? = nil) -> HeraldManifest {
        func text(_ key: String, _ sample: String, required: Bool? = nil) -> HeraldField {
            HeraldField(key: key, type: .text, required: required, sample: .text(sample))
        }
        let fields = [
            text("title", "Build finished", required: true),
            text("body", "All 214 tests passed in 38 s."),
            text("status", "done"),
            text("project", "herald"),
            text("session", "a1f3"),
            text("task", "fix-parity"),
            text("tool", "Bash"),
            text("duration", "2m 14s"),
            HeraldField(key: "link", type: .url, sample: .text("https://example.com/session/a1f3")),
            HeraldField(key: "needsInput", type: .bool, sample: .bool(false)),
        ]
        let actions = [
            HeraldButton(label: "Open", url: homepage),
            HeraldButton(label: "Reply", callback: HeraldCallback()),
            HeraldButton(label: "Dismiss"),
        ]
        return HeraldManifest(app: appID, appName: name, icon: icon, fields: fields, actions: actions,
                              actionIDs: ["open", "reply", "dismiss"], defaultTemplate: Self.templateName, family: "agent")
    }

    // MARK: Template

    public func template() -> HeraldTemplate {
        var t = BuiltinTemplates.template(layout: .compact, app: appID)
        t.name = Self.templateName
        let keep = t.cells.filter { ["icon", "title", "time", "close"].contains($0.id) }
        let actions = t.cells.first { $0.id == "actions" }
        var cells = keep
        cells.append(HeraldCell(id: "body", row: 1, col: 1, colSpan: 3, align: .leading,
                                component: .text(HeraldTextComponent(binding: "{body}", style: .body, maxLines: 2, emptyBehavior: .collapse))))
        cells.append(HeraldCell(id: "status", row: 2, col: 1, align: .leading,
                                component: .badge(HeraldBadgeComponent(binding: "{status}", emptyBehavior: .collapse,
                                                                       symbol: HeraldSymbol(name: symbol)))))
        cells.append(HeraldCell(id: "project", row: 2, col: 2, colSpan: 2, align: .leading,
                                component: .text(HeraldTextComponent(binding: "{project}", style: .caption, maxLines: 1, emptyBehavior: .collapse))))
        if var a = actions { a.row = 3; cells.append(a) }
        t.cells = cells.sorted { ($0.row, $0.col) < ($1.row, $1.col) }
        t.grid?.rows = 4
        t.grid?.rowSizes = [.auto, .auto, .auto, .auto]
        t.sound = sound
        return t
    }
}
