import Foundation

/// Finds an application's icon on disk and turns it into a PNG (issue #62): the `.icns` the bundle names in its
/// `Info.plist` (or the largest `.icns` in Resources), converted with `sips` at up to 512 px. The app prefers what
/// Finder draws (`NSWorkspace`, which also reads asset catalogs) and falls back to this.
public enum IconExtractor {
    /// The `.icns` of an application bundle: `CFBundleIconFile` when it exists, else the largest `.icns` in Resources.
    public static func icnsURL(inBundle bundle: URL) -> URL? {
        let resources = bundle.appendingPathComponent("Contents/Resources", isDirectory: true)
        let fm = FileManager.default
        if let info = NSDictionary(contentsOf: bundle.appendingPathComponent("Contents/Info.plist")),
           var name = info["CFBundleIconFile"] as? String, !name.isEmpty {
            if (name as NSString).pathExtension.isEmpty { name += ".icns" }
            let url = resources.appendingPathComponent(name)
            if fm.fileExists(atPath: url.path) { return url }
        }
        let all = ((try? fm.contentsOfDirectory(at: resources, includingPropertiesForKeys: [.fileSizeKey])) ?? [])
            .filter { $0.pathExtension.lowercased() == "icns" }
        return all.max { size($0) < size($1) }
    }

    private static func size(_ u: URL) -> Int { (try? u.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0 }

    /// PNG bytes (at most `maxPixels` on the long side) of an `.icns` or image file, via `sips`. nil when it cannot be converted.
    public static func png(from file: URL, maxPixels: Int = 512,
                           run: (_ exe: String, _ args: [String]) -> Int32 = IconExtractor.runProcess) -> Data? {
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("herald-icon-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: out) }
        let status = run("/usr/bin/sips", ["-s", "format", "png", "-Z", String(maxPixels), file.path, "--out", out.path])
        guard status == 0, let data = try? Data(contentsOf: out), data.count > 8,
              data.prefix(4) == Data([0x89, 0x50, 0x4E, 0x47]) else { return nil }
        return data
    }

    /// The icon of an application bundle as PNG; nil when it has none.
    public static func png(fromBundle bundle: URL, maxPixels: Int = 512) -> Data? {
        icnsURL(inBundle: bundle).flatMap { png(from: $0, maxPixels: maxPixels) }
    }

    public static func runProcess(_ exe: String, _ args: [String]) -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do { try p.run(); p.waitUntilExit(); return p.terminationStatus } catch { return -1 }
    }
}

/// Registers an agent as an issuer when its MCP client is installed (issue #62): the app (name, icon, sound), the
/// manifest and the default template. Running it again is safe: the manifest is brought up to date, but what the
/// user changed stays: their template (never overwritten once it exists), the app's sound, name and own icon, and
/// a default template they picked.
public enum AgentIssuer {
    public struct Report: Equatable, Sendable {
        public var appID: String
        /// True when the manifest was new or changed.
        public var manifestWritten: Bool
        /// False when a template named `agent` already existed and was left alone.
        public var templateCreated: Bool
        /// What the agent's "Open" button brings to the front (the manifest's `appBundleId` or `appPath`).
        public var opens: HeraldHostApp.Target?
        /// The old default template was replaced by the current one (the user had not edited it).
        public var templateUpgraded: Bool = false
        /// The PNG inside Herald's support folder the app's icon points to; nil when no icon is set.
        public var iconPath: String?
        /// No PNG was given and the app has none: Settings > MCP asks the user to choose one.
        public var iconMissing: Bool
    }

    /// The manifest with its "Open" target changed: a bundle id sets `appBundleId`, an application path `appPath` (the other
    /// is cleared, so the resolver sees exactly one choice). An app without a manifest gets a bare one.
    public static func manifest(settingOpens target: HeraldHostApp.Target, app: String, appName: String?, current: HeraldManifest?) -> HeraldManifest {
        var m = current ?? HeraldManifest(app: app, appName: appName)
        switch target {
        case .bundleId(let b): m.appBundleId = b; m.appPath = nil
        case .path(let p): m.appPath = p; m.appBundleId = nil
        }
        return m
    }

    /// The identity an installed agent app was registered under, from its manifest; nil for an app that is not an agent.
    public static func identity(of manifest: HeraldManifest) -> AgentIdentity? {
        guard manifest.family == "agent", manifest.app.hasPrefix(HeraldAgent.prefix) else { return nil }
        let slug = String(manifest.app.dropFirst(HeraldAgent.prefix.count))
        for kind in [AgentIdentity.Kind.claudeCode, .codex, .claudeDesktop] {
            if let id = AgentIdentity(kind: kind), id.slug == slug { return id }
        }
        guard HeraldAgent.slug(manifest.appName) == slug else { return nil }
        return AgentIdentity(kind: .generic, genericName: manifest.appName)
    }

    /// Brings every installed agent up to the current default at launch: the manifest (Open, Reply, Open link; no Dismiss),
    /// and the default template when it is still the one Herald generated. What the user changed stays (see `register`).
    /// Returns the apps whose manifest or template changed.
    @discardableResult
    public static func refreshInstalled(supportDirectory: URL, registry: AppRegistry, manifests: ManifestStore, templates: TemplateStore,
                                        detectedHost: String? = nil) -> [String] {
        var changed: [String] = []
        for m in manifests.list() {
            guard let agent = identity(of: m),
                  let r = try? register(agent, iconPNG: nil, detectedHost: detectedHost, supportDirectory: supportDirectory,
                                        registry: registry, manifests: manifests, templates: templates) else { continue }
            if r.manifestWritten || r.templateUpgraded { changed.append(agent.appID) }
        }
        return changed
    }

    public static func iconsFolder(in support: URL) -> URL { support.appendingPathComponent("agent-icons", isDirectory: true) }

    @discardableResult
    public static func register(_ agent: AgentIdentity, iconPNG: Data?, opens: HeraldHostApp.Target? = nil,
                                detectedHost: String? = nil, supportDirectory: URL,
                                registry: AppRegistry, manifests: ManifestStore, templates: TemplateStore) throws -> Report {
        let existing = registry.record(for: agent.appID)?.registration

        // Icon: the copy lives in Herald's own folder (the source apps move). A user's own icon (one that does not
        // point into that folder) is kept.
        let folder = iconsFolder(in: supportDirectory)
        let ours = folder.appendingPathComponent(agent.slug + ".png")
        var iconPath: String?
        if let png = iconPNG {
            let userOwn = existing?.icon.map { !$0.hasPrefix(folder.path) && !$0.isEmpty } ?? false
            if !userOwn {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                try png.write(to: ours, options: .atomic)
                iconPath = ours.path
            }
        }
        let currentIcon = iconPath ?? existing?.icon

        guard registry.hasRoom(for: agent.appID), manifests.hasRoom(for: agent.appID) else {
            throw BackendError(429, "too many apps or manifests to add \(agent.appID)")
        }
        var reg = HeraldAppRegistration(app: agent.appID)
        if existing?.appName == nil { reg.appName = agent.name }
        if let iconPath { reg.icon = iconPath }
        if existing?.defaults?.sound == nil { reg.defaults = HeraldAppDefaults(sound: agent.sound) }
        registry.register(reg)

        // Manifest: ours, with what the user may have set kept (their default template, their assets).
        // "Opens": what the caller chose, else what the user already has, else the host (Claude.app, or the terminal
        // or editor this was installed from).
        let old = manifests.get(app: agent.appID)
        let target = opens ?? AgentIdentity.opens(of: old) ?? agent.defaultOpens(detectedHost: detectedHost)
        var manifest = agent.manifest(icon: currentIcon, opens: target)
        if let d = old?.defaultTemplate { manifest.defaultTemplate = d }
        if let a = old?.assets { manifest.assets = a }
        let written = old != manifest
        if written, !manifests.put(manifest) { throw BackendError(500, "could not save the manifest of \(agent.appID)") }

        var created = false, upgraded = false
        if let stored = templates.get(app: agent.appID, name: AgentIdentity.templateName) {
            // Herald's own earlier default, untouched by the user, becomes the current one; anything else is theirs.
            if stored == agent.previousTemplate() {
                guard templates.put(agent.template()) else { throw BackendError(500, "could not save the template of \(agent.appID)") }
                upgraded = true
            }
        } else {
            guard templates.put(agent.template()) else { throw BackendError(500, "could not save the template of \(agent.appID)") }
            created = true
        }
        return Report(appID: agent.appID, manifestWritten: written, templateCreated: created, opens: target,
                      templateUpgraded: upgraded, iconPath: currentIcon, iconMissing: currentIcon == nil)
    }
}
