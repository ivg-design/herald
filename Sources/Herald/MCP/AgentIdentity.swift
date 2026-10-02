import Foundation

/// An installed MCP client as a notification issuer (issue #62): its own app id, manifest and default template, so
/// the agent's notifications arrive under their own identity and the user designs their look like any other issuer.
///
/// `agent.claude-code`, `agent.codex`, `agent.claude-desktop` are fixed; a generic client gets `agent.<slug>` from the
/// name the user types. The manifest declares what an agent has to say (title, body, a status badge, the project,
/// a session and task id, the last tool, a duration, a link back, whether it needs an answer) and the actions it
/// offers: Open (brings the agent's host application to the front: Claude.app, or the terminal or editor the
/// agent runs in), Reply (an inline text field in the banner) and Open link (only when the notification has a
/// `link`). There is no Dismiss and no Done: the banner's close button already dismisses, and a second control
/// with the same effect is what this template exists not to have. The default template is icon, title and body,
/// the status badge (carrying an SF Symbol per agent) and the action row.
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
    /// `agent.` for an installed MCP client, `cloud.` for an agent key of the cloud relay (docs/CLOUD.md).
    public let idPrefix: String
    public var isCloud: Bool { idPrefix == Self.cloudPrefix }
    public static let cloudPrefix = "cloud."
    public var appID: String { idPrefix + slug }

    /// The issuer of one cloud agent key: `cloud.<key name>`. `client` is the key's client (`claude`, `codex`, anything else);
    /// the first two take the real client's icon and symbol, the rest a generic one.
    public init?(cloudKeyName: String, client: String) {
        let s = HeraldAgent.slug(cloudKeyName)
        guard !s.isEmpty else { return nil }
        let base: AgentIdentity?
        switch client {
        case "claude": base = AgentIdentity(kind: .claudeCode)
        case "codex": base = AgentIdentity(kind: .codex)
        default: base = AgentIdentity(kind: .generic, genericName: s)
        }
        guard let b = base else { return nil }
        kind = b.kind; slug = s; name = cloudKeyName.trimmingCharacters(in: .whitespacesAndNewlines)
        symbol = b.kind == .generic ? "cloud" : b.symbol; sound = b.sound; homepage = b.homepage
        idPrefix = Self.cloudPrefix
    }

    public init?(kind: Kind, genericName: String? = nil) {
        self.kind = kind
        self.idPrefix = HeraldAgent.prefix
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

    // MARK: Opens

    /// What "Open" brings to the front when nothing else was chosen: Claude Desktop is `Claude.app`; Claude Code,
    /// Codex and a generic client run in a terminal or editor, `detectedHost` (see `HeraldHostApp`), else Terminal.app.
    public func defaultOpens(detectedHost: String? = nil) -> HeraldHostApp.Target {
        if kind == .claudeDesktop { return .bundleId(HeraldHostApp.claudeDesktopBundleID) }
        return .bundleId(detectedHost ?? HeraldHostApp.terminalBundleID)
    }

    // MARK: Manifest

    public func manifest(icon: String? = nil, opens: HeraldHostApp.Target? = nil) -> HeraldManifest {
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
        // Open: the host application (`appBundleId` below), never a URL. Reply: the inline field. Open link: the
        // notification's own `link`, and only when it has one (`ActionResolver.fillingLinks`).
        let actions = [
            HeraldButton(label: "Open", openApp: HeraldOpenApp()),
            HeraldButton(label: "Reply", reply: HeraldReply(placeholder: "Reply to \(name)\u{2026}")),
            HeraldButton(label: "Open link", url: "{link}"),
        ]
        if isCloud {
            // A cloud agent runs somewhere else: there is nothing on this Mac to "Open". The user answers by text (Reply) or by
            // voice (Record, transcribed on this Mac), and a notification's own https link opens from "Open link".
            let cloudActions = [
                HeraldButton(label: "Reply", reply: HeraldReply(placeholder: "Reply to \(name)\u{2026}")),
                HeraldButton(label: "Record", reply: HeraldReply(voice: true)),
                HeraldButton(label: "Open link", url: "{link}"),
            ]
            return HeraldManifest(app: appID, appName: name, icon: icon, fields: fields, actions: cloudActions,
                                  actionIDs: ["reply", "record", "open-link"], defaultTemplate: Self.templateName, family: "cloud")
        }
        let target = opens ?? defaultOpens()
        var m = HeraldManifest(app: appID, appName: name, icon: icon, fields: fields, actions: actions,
                               actionIDs: ["open", "reply", "open-link"], defaultTemplate: Self.templateName, family: "agent")
        switch target {
        case .bundleId(let b): m.appBundleId = b
        case .path(let p): m.appPath = p
        }
        return m
    }

    /// The target an existing manifest already opens, if any.
    public static func opens(of m: HeraldManifest?) -> HeraldHostApp.Target? {
        if let b = m?.appBundleId, !b.isEmpty { return .bundleId(b) }
        if let p = m?.appPath, !p.isEmpty { return .path(p) }
        return nil
    }

    // MARK: Template

    /// icon | title and body | status badge, a quiet row for the project and the time, then the buttons: Open,
    /// Reply (and Open link when the notification has one). The close button on the title row dismisses, so
    /// no button repeats it.
    public func template() -> HeraldTemplate {
        var t = BuiltinTemplates.template(layout: .compact, app: appID)
        t.name = Self.templateName
        let close = t.cells.first { $0.id == "close" }
        let title = t.cells.first { $0.id == "title" }
        let time = t.cells.first { $0.id == "time" }
        var cells: [HeraldCell] = []
        cells.append(HeraldCell(id: "icon", row: 0, col: 0, rowSpan: 2, align: .topLeading,
                                component: .issuerIcon(HeraldIssuerIconComponent(size: 36, cornerRadius: 8, shape: .rounded))))
        if var c = title { c.row = 0; c.col = 1; c.align = .leading; cells.append(c) }
        cells.append(HeraldCell(id: "status", row: 0, col: 2, align: .center,
                                component: .badge(HeraldBadgeComponent(binding: "{status}", emptyBehavior: .collapse,
                                                                       symbol: HeraldSymbol(name: symbol)))))
        if var c = close { c.row = 0; c.col = 3; c.align = .center; cells.append(c) }
        cells.append(HeraldCell(id: "body", row: 1, col: 1, colSpan: 3, align: .topLeading,
                                component: .text(HeraldTextComponent(binding: "{body}", style: .body, maxLines: 3, emptyBehavior: .collapse))))
        cells.append(HeraldCell(id: "project", row: 2, col: 1, colSpan: 2, align: .leading,
                                component: .text(HeraldTextComponent(binding: "{project}", style: .caption, maxLines: 1, emptyBehavior: .collapse))))
        if var c = time { c.row = 2; c.col = 3; c.align = .trailing; cells.append(c) }
        cells.append(HeraldCell(id: "actions", row: 3, col: 1, colSpan: 3, align: .leading,
                                component: .actions(HeraldActionsComponent(source: .merged, layout: .wrap))))
        t.cells = cells.sorted { ($0.row, $0.col) < ($1.row, $1.col) }
        t.grid = HeraldGrid(rows: 4, cols: 4, rowSizes: [.auto, .auto, .auto, .auto], colSizes: [.auto, .fill, .auto, .auto],
                            gap: 8, padding: 12, width: t.grid?.width ?? 400)
        t.sound = sound
        return t
    }

    /// The template Herald generated before the Open/Reply fix (a compact skeleton with the status badge under the
    /// title). A stored template equal to this was never edited by the user, so the new default replaces it.
    public func previousTemplate() -> HeraldTemplate {
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

    // MARK: Duplicate effects

    /// What pressing an action does, as a comparable key: two actions with the same key are one control twice.
    public static func effect(of a: HeraldAction) -> String {
        switch a.kind {
        case .dismiss: return "dismiss"
        case .url: return "url:" + (a.url ?? "")
        case .openApp: return "openApp:" + (a.bundleId ?? a.path ?? "")
        case .reply: return "reply"
        case .callback: return "callback:" + (a.callback?.url ?? "")
        case .command: return "command:" + (a.command ?? "")
        case .script: return "script:" + (a.script ?? "")
        case .shortcut: return "shortcut:" + (a.shortcut ?? "")
        case .snooze: return "snooze"
        }
    }

    /// Effects that more than one control of the banner has: the manifest's actions the template shows, the
    /// template's own actions and its icon buttons (the close button is a dismiss). Empty for a sound template.
    public func duplicateEffects(manifest: HeraldManifest, template t: HeraldTemplate) -> [String] {
        var all: [HeraldAction] = manifest.actions.map { HeraldAction(button: $0) }
        for cell in t.cells { all += cell.component.inlineActions }
        all += t.actionRules.compactMap(\.add)
        var seen = Set<String>(), dup = Set<String>()
        for a in all where !seen.insert(Self.effect(of: a)).inserted { dup.insert(Self.effect(of: a)) }
        return dup.sorted()
    }
}
