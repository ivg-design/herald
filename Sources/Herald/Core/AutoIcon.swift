import AppKit
import Foundation

/// The icon an app gets when it did not bring one (issue #86): the product's own icon when this Mac has it (ChatGPT.app, Claude,
/// Codex), else an SF Symbol tile drawn as a PNG ("cloud" for a relay connector, "key" for a static key, "terminal" for an
/// agent). Never a bare letter.
public enum AutoIcon {
    public enum Flavor: String, Sendable { case chatgpt, claude, codex, other }
    public enum Source: String, Sendable {
        case connector, staticKey, agent
        public var symbol: String {
            switch self { case .connector: return "cloud"; case .staticKey: return "key"; case .agent: return "terminal" }
        }
    }

    /// Which product a client is, from any of the texts that name it (the OAuth `client_name`, the registration's `software_id`,
    /// the key name, the key's client). ChatGPT or OpenAI first, then Codex, Claude.
    public static func flavor(_ texts: [String?]) -> Flavor {
        let t = texts.compactMap { $0 }.joined(separator: " ").lowercased()
        if t.contains("chatgpt") { return .chatgpt }
        if t.contains("codex") { return .codex }
        if t.contains("openai") { return .chatgpt }
        if t.contains("claude") || t.contains("anthropic") { return .claude }
        return .other
    }

    /// What Finder draws for an application bundle, as PNG; nil when that is the generic placeholder.
    public static func finderPNG(of app: URL) -> Data? {
        guard let png = IconArt.png(of: NSWorkspace.shared.icon(forFile: app.path)), IconArt.isUsableAppIcon(png) else { return nil }
        return png
    }

    /// The real icon of the product on this Mac, or nil.
    public static func productPNG(_ flavor: Flavor, roots: AgentIconSources.Roots = .standard(),
                                  finder: (URL) -> Data? = AutoIcon.finderPNG(of:)) -> Data? {
        let names: [String]
        let kind: AgentIdentity.Kind?
        switch flavor {
        case .chatgpt: names = ["ChatGPT.app"]; kind = nil
        case .claude: names = []; kind = .claudeCode
        case .codex: names = []; kind = .codex
        case .other: return nil
        }
        var bundles = roots.applications.flatMap { f in names.map { f.appendingPathComponent($0) } }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
        if let kind { bundles += AgentIconSources.appBundles(for: kind, in: roots) }
        for b in bundles { if let png = finder(b) { return png } }
        if let kind, let png = AgentIconSources.png(for: kind, roots: roots)?.data { return png }
        return nil
    }

    /// The automatic icon: the product's own, else the tile for the source.
    public static func png(flavor: Flavor, source: Source, roots: AgentIconSources.Roots = .standard()) -> Data? {
        productPNG(flavor, roots: roots) ?? IconArt.symbolTilePNG(symbol: source.symbol)
    }

    public static func file(for app: String, in support: URL) -> URL {
        AgentIssuer.iconsFolder(in: support).appendingPathComponent("auto-" + app + ".png")
    }

    /// True when the app shows no icon of its own: none registered, or a file that is gone.
    public static func isIconless(_ r: AppRecord) -> Bool {
        if let i = r.registration.icon, !i.isEmpty {
            if i.hasPrefix("data:") { return false }
            if FileManager.default.fileExists(atPath: (i as NSString).expandingTildeInPath) { return false }
        }
        if let b = r.registration.bundleId, !b.isEmpty, NSWorkspace.shared.urlForApplication(withBundleIdentifier: b) != nil { return false }
        return true
    }

    /// Gives an icon-less app its automatic icon: `agent-icons/auto-<app>.png`, registered as the app's icon. False when the app has
    /// an icon already (nothing is changed) or the PNG could not be written.
    @discardableResult
    public static func assign(app: String, png: Data, supportDirectory: URL, registry: AppRegistry) -> Bool {
        guard let rec = registry.record(for: app), isIconless(rec) else { return false }
        let file = file(for: app, in: supportDirectory)
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try png.write(to: file, options: .atomic)
        } catch { return false }
        registry.update(app) { $0.registration.icon = file.path }
        return true
    }

    /// The source and flavor of an app that has no key information: `cloud.*` is a connector, `agent.*` an agent.
    public static func guess(app: String, name: String) -> (Flavor, Source)? {
        let slug = app.split(separator: ".", maxSplits: 1).dropFirst().first.map(String.init) ?? app
        if app.hasPrefix(AgentIdentity.cloudPrefix) { return (flavor([name, slug]), .connector) }
        if app.hasPrefix(HeraldAgent.prefix) { return (flavor([name, slug]), .agent) }
        return nil
    }

    /// Startup pass: every icon-less `cloud.*` and `agent.*` app gets the automatic icon. `keys` (the relay's agent keys, when known)
    /// tell a static key from a connector. Returns the apps changed.
    @discardableResult
    public static func applyToIconless(registry: AppRegistry, supportDirectory: URL, keys: [RelayKeyInfo] = [],
                                       roots: AgentIconSources.Roots = .standard()) -> [String] {
        var changed: [String] = []
        for r in registry.all() where isIconless(r) {
            let app = r.registration.app
            guard var (flavor, source) = guess(app: app, name: r.displayName) else { continue }
            if app.hasPrefix(AgentIdentity.cloudPrefix),
               let k = keys.first(where: { AgentIdentity.cloudPrefix + HeraldAgent.slug($0.name) == app }) {
                source = k.isOAuth ? .connector : .staticKey
                flavor = self.flavor([k.isOAuth ? k.displayName : nil, k.name, k.isOAuth ? nil : k.client])
            }
            guard let png = png(flavor: flavor, source: source, roots: roots) else { continue }
            if assign(app: app, png: png, supportDirectory: supportDirectory, registry: registry) { changed.append(app) }
        }
        return changed
    }
}
