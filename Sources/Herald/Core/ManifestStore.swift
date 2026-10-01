import Foundation

/// Manifests on disk: `<directory>/<app>.json`, one human-editable file per issuer
/// (normally `~/Library/Application Support/Herald/manifests`).
///
/// Same conventions as `TemplateStore`: the file's own `app` field is authoritative and the file name
/// is only an index (so a hand-renamed file still lists and is found), and every failure is swallowed
/// into `nil`/`false` because a missing or corrupt manifest must never stop a notification from being
/// delivered. Nothing is cached, so a hand edit is picked up by the next notification.
public final class ManifestStore: @unchecked Sendable {
    /// Matches `AppRegistry.maxApps`: a manifest belongs to an app.
    public static let maxManifests = 200

    public let directory: URL
    private let lock = NSLock()

    public init(directory: URL) {
        self.directory = directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    // MARK: Queries

    /// Every manifest, sorted by app id.
    public func list() -> [HeraldManifest] {
        lock.lock(); defer { lock.unlock() }
        return loadAll().sorted { $0.app.localizedCaseInsensitiveCompare($1.app) == .orderedAscending }
    }

    public func get(app: String) -> HeraldManifest? {
        guard !app.isEmpty else { return nil }
        lock.lock(); defer { lock.unlock() }
        if let m = read(file(app)), m.app == app { return m }
        // A hand-renamed file: fall back to matching on the app id stored inside.
        return loadAll().first { $0.app == app }
    }

    /// False when `app` has no manifest yet and the store is full.
    public func hasRoom(for app: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        if read(file(app))?.app == app { return true }
        return jsonFiles().count < Self.maxManifests
    }

    // MARK: Mutations

    /// Creates or replaces the manifest of `m.app`. False when `app` is empty or the write fails.
    @discardableResult
    public func put(_ m: HeraldManifest) -> Bool {
        guard !m.app.isEmpty else { return false }
        lock.lock(); defer { lock.unlock() }
        let url = file(m.app)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let encoder = HeraldJSON.encoder()
            encoder.outputFormatting.insert(.prettyPrinted)   // meant to be read and edited by hand
            try encoder.encode(m).write(to: url, options: .atomic)
            // The same app stored under another file name (a hand-renamed file) must not shadow the new one.
            for other in jsonFiles() where other != url && read(other)?.app == m.app {
                try? FileManager.default.removeItem(at: other)
            }
            return true
        } catch {
            return false
        }
    }

    /// Removes the manifest. False when there was none.
    @discardableResult
    public func delete(app: String) -> Bool {
        guard !app.isEmpty else { return false }
        lock.lock(); defer { lock.unlock() }
        let fm = FileManager.default
        var removed = false
        let direct = file(app)
        if read(direct)?.app == app {
            removed = (try? fm.removeItem(at: direct)) != nil
        }
        for url in jsonFiles() where read(url)?.app == app {
            if (try? fm.removeItem(at: url)) != nil { removed = true }
        }
        return removed
    }

    // MARK: Paths and persistence

    /// `TemplateStore.component` maps any id to one safe path component, so "../x" can never leave the folder.
    private func file(_ app: String) -> URL {
        directory.appendingPathComponent(TemplateStore.component(app) + ".json")
    }

    private func jsonFiles() -> [URL] {
        ((try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "json" }
    }

    private func loadAll() -> [HeraldManifest] {
        jsonFiles().compactMap { read($0) }
    }

    private func read(_ url: URL) -> HeraldManifest? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? HeraldJSON.decoder().decode(HeraldManifest.self, from: data)
    }
}
