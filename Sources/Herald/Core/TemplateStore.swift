import Foundation
import CryptoKit

/// Templates on disk: `<directory>/<app>/<name>.json`, one human-editable file per template.
///
/// A file per template (rather than one blob per app, as history does) keeps them diffable and
/// lets the user copy a template between machines or hand-edit one. The file's own `app` and
/// `name` fields are authoritative; the path is only an index, so a renamed file still lists.
/// Errors are swallowed into `nil`/`false` like the other stores, because a missing or corrupt
/// template must never stop a notification from being delivered.
public final class TemplateStore: @unchecked Sendable {
    public let directory: URL
    private let lock = NSLock()

    /// `directory` is normally `~/Library/Application Support/Herald/templates`.
    public init(directory: URL) {
        self.directory = directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    // MARK: Queries

    /// Templates for one app, or for every app when `app` is nil or empty. Sorted by app, then name.
    public func list(app: String? = nil) -> [HeraldTemplate] {
        lock.lock(); defer { lock.unlock() }
        var found: [HeraldTemplate] = []
        if let app, !app.isEmpty {
            found = load(in: appDirectory(app)).filter { $0.app == app }
        } else {
            let dirs = (try? FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
            for d in dirs where (try? d.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                found += load(in: d)
            }
        }
        return found.sorted {
            if $0.app != $1.app { return $0.app.localizedCaseInsensitiveCompare($1.app) == .orderedAscending }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    public func get(app: String, name: String) -> HeraldTemplate? {
        lock.lock(); defer { lock.unlock() }
        if let t = read(file(app: app, name: name)), t.app == app, t.name == name { return t }
        // A hand-renamed file: fall back to matching on the names stored inside the app folder.
        return load(in: appDirectory(app)).first { $0.app == app && $0.name == name }
    }

    /// The template a notification names, if any (nil when it names none or the name is unknown).
    public func template(for n: HeraldNotification) -> HeraldTemplate? {
        guard let name = n.template, !name.isEmpty else { return nil }
        return get(app: n.app, name: name)
    }

    // MARK: Mutations

    /// Creates or replaces the template. False when `name`/`app` is empty or the write fails.
    @discardableResult
    public func put(_ t: HeraldTemplate) -> Bool {
        guard !t.name.isEmpty, !t.app.isEmpty else { return false }
        lock.lock(); defer { lock.unlock() }
        let url = file(app: t.app, name: t.name)
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = HeraldJSON.encoder()
            encoder.outputFormatting.insert(.prettyPrinted)   // meant to be read and edited by hand
            try encoder.encode(t).write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    /// Removes the template. False when there was none.
    @discardableResult
    public func delete(app: String, name: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        let fm = FileManager.default
        let dir = appDirectory(app)
        var removed = false
        let direct = file(app: app, name: name)
        if let t = read(direct), t.app == app, t.name == name {
            removed = (try? fm.removeItem(at: direct)) != nil
        } else if let url = jsonFiles(in: dir).first(where: { let t = read($0); return t?.app == app && t?.name == name }) {
            removed = (try? fm.removeItem(at: url)) != nil
        }
        // Do not leave an empty folder per app behind.
        if removed, jsonFiles(in: dir).isEmpty { try? fm.removeItem(at: dir) }
        return removed
    }

    // MARK: Paths and persistence

    private func appDirectory(_ app: String) -> URL {
        directory.appendingPathComponent(Self.component(app), isDirectory: true)
    }

    private func file(app: String, name: String) -> URL {
        appDirectory(app).appendingPathComponent(Self.component(name) + ".json")
    }

    /// Maps an arbitrary id to a single safe path component. Anything outside `[A-Za-z0-9._-]` is
    /// replaced and a short hash is appended so "a/b" and "a_b" do not collide; a leading dot is
    /// neutralised so ".." can never address a parent folder.
    static func component(_ s: String) -> String {
        var safe = String(s.map { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "-" || $0 == "_") ? $0 : "_" })
        if safe.hasPrefix(".") { safe = "_" + safe.dropFirst() }
        if safe.isEmpty { safe = "_" }
        guard safe != s else { return safe }
        return safe + "-" + SHA256.hash(data: Data(s.utf8)).prefix(3).map { String(format: "%02x", $0) }.joined()
    }

    private func jsonFiles(in dir: URL) -> [URL] {
        ((try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "json" }
    }

    private func load(in dir: URL) -> [HeraldTemplate] {
        jsonFiles(in: dir).compactMap { read($0) }
    }

    private func read(_ url: URL) -> HeraldTemplate? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? HeraldJSON.decoder().decode(HeraldTemplate.self, from: data)
    }
}
