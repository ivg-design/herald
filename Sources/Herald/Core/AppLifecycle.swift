import Foundation

/// What removing an app took with it.
public struct AppRemoval: Equatable, Sendable {
    public var app: String
    public var wasRegistered = false
    public var historyItems = 0
    public var templates = 0
    public var manifest = false
    public var iconFiles = 0
}

/// Removing an app and the housekeeping that keeps Herald's lists free of apps that no longer exist.
public enum AppLifecycle {
    /// Removes the app's record, History, templates, manifest (and its Rive copies) and the icon files Herald made for it,
    /// together. A user's own icon outside Herald's support folder is never touched.
    @discardableResult
    public static func remove(app: String, supportDirectory: URL, registry: AppRegistry, history: HistoryStore,
                              templates: TemplateStore, manifests: ManifestStore, assets: AssetStore? = nil) -> AppRemoval {
        var r = AppRemoval(app: app)
        let record = registry.record(for: app)
        r.historyItems = history.counts()[app]?.total ?? 0
        history.clear(app: app)
        for t in templates.list(app: app) where templates.delete(app: app, name: t.name) { r.templates += 1 }
        if let m = manifests.get(app: app) {
            assets?.remove(manifest: m)
            r.manifest = manifests.delete(app: app)
        }
        r.wasRegistered = registry.remove(app)
        r.iconFiles = removeIcons(of: app, record: record, supportDirectory: supportDirectory, registry: registry)
        return r
    }

    /// `agent.claude-code` and `cloud.my-bot` keep their icon as `agent-icons/<slug>.png` and `<slug>.custom.png`; any other icon that
    /// lives inside the support folder (the registered path) goes too.
    static func removeIcons(of app: String, record: AppRecord?, supportDirectory: URL, registry: AppRegistry) -> Int {
        let fm = FileManager.default
        let folder = AgentIssuer.iconsFolder(in: supportDirectory)
        var targets: [URL] = []
        func slug(_ id: String) -> String? { id.contains(".") ? id.split(separator: ".", maxSplits: 1).last.map(String.init) : nil }
        // agent.x and cloud.x share a slug (and so the icon file): another app that still uses it keeps it.
        if let s = slug(app), !registry.all().contains(where: { $0.registration.app != app && slug($0.registration.app) == s }) {
            targets += [folder.appendingPathComponent(s + ".png"), folder.appendingPathComponent(s + ".custom.png")]
        }
        if let icon = record?.registration.icon, !icon.hasPrefix("data:") {
            let url = URL(fileURLWithPath: (icon as NSString).expandingTildeInPath).standardizedFileURL
            if url.path.hasPrefix(supportDirectory.standardizedFileURL.path + "/") { targets.append(url) }
        }
        var removed = 0
        for t in Set(targets) where fm.fileExists(atPath: t.path) {
            if (try? fm.removeItem(at: t)) != nil { removed += 1 }
        }
        return removed
    }
}

/// What the startup passes changed.
public struct HeraldMigrationReport: Equatable, Sendable {
    public var foldedConnectors = 0
    public var purgedOrphans: [String] = []
    public var removedLeftovers: [String] = []
    public var isEmpty: Bool { foldedConnectors == 0 && purgedOrphans.isEmpty && removedLeftovers.isEmpty }
}

public enum HeraldMigrations {
    static let leftoversMarker = "migrated-leftovers-1"

    /// Runs at every start: the connectors fold, the `herald` identity, History of apps that no longer exist; and once: the known test
    /// and demo leftovers.
    @discardableResult
    public static func run(supportDirectory: URL, registry: AppRegistry, history: HistoryStore, templates: TemplateStore,
                           manifests: ManifestStore, assets: AssetStore? = nil, iconPNG: Data? = nil) -> HeraldMigrationReport {
        var report = HeraldMigrationReport()

        // 1. `herald.connectors` is folded into `herald`: its History moves (group "connectors"), its record, manifest and templates go.
        let legacy = HeraldIdentity.legacyConnectorsApp
        if registry.record(for: legacy) != nil || history.apps().contains(legacy) || manifests.get(app: legacy) != nil {
            report.foldedConnectors = history.reassign(from: legacy, to: HeraldIdentity.app, group: HeraldIdentity.connectorsGroup)
            AppLifecycle.remove(app: legacy, supportDirectory: supportDirectory, registry: registry, history: history,
                                templates: templates, manifests: manifests, assets: assets)
        }

        // 2. One Herald entry, with its name and icon.
        HeraldIdentity.ensureRegistered(registry: registry, supportDirectory: supportDirectory, iconPNG: iconPNG)

        // 3. Once: leftovers of testing and demos.
        let marker = supportDirectory.appendingPathComponent(leftoversMarker)
        if !FileManager.default.fileExists(atPath: marker.path) {
            var candidates = Set(registry.all().map(\.registration.app)).union(history.apps()).union(manifests.list().map(\.app))
            candidates = candidates.filter { $0.hasPrefix("cloud." + HeraldIdentity.relayTestKeyPrefix) }
            // The `bidbot` example was only ever a throw-away registration; one with a manifest or templates was installed on purpose.
            if (registry.record(for: "bidbot") != nil || history.apps().contains("bidbot")),
               manifests.get(app: "bidbot") == nil, templates.list(app: "bidbot").isEmpty { candidates.insert("bidbot") }
            for app in candidates.sorted() {
                AppLifecycle.remove(app: app, supportDirectory: supportDirectory, registry: registry, history: history,
                                    templates: templates, manifests: manifests, assets: assets)
                report.removedLeftovers.append(app)
            }
            try? FileManager.default.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
            try? Data().write(to: marker)
        }

        // 4. History of an app that is not registered any more (a removed app, an old id such as `webwatcher`) is not shown or kept.
        for app in history.apps() where registry.record(for: app) == nil {
            history.clear(app: app)
            report.purgedOrphans.append(app)
        }
        return report
    }
}
