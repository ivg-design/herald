import Foundation
import CryptoKit

/// Per-app JSON history, newest first, capped at 1000 items per app.
public final class HistoryStore: @unchecked Sendable {
    public static let cap = 1000
    /// The largest image Herald will cache (a decoded hero image is far smaller than this).
    public static let maxImageBytes = 10 * 1024 * 1024

    public let directory: URL
    public var imagesDirectory: URL { directory.appendingPathComponent("images", isDirectory: true) }
    private let lock = NSLock()
    private var cache: [String: [HeraldHistoryItem]] = [:]
    /// Every app that has history. Seeded once from the files on disk, then kept current by `save`, so the
    /// hot paths (unread badge, History window) never decode the history files just to learn the app names.
    private var knownApps: Set<String>?

    public init(directory: URL) {
        self.directory = directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)
    }

    // MARK: Queries

    public func items(app: String, limit: Int? = nil) -> [HeraldHistoryItem] {
        lock.lock(); defer { lock.unlock() }
        let all = load(app)
        if let limit, limit >= 0 { return Array(all.prefix(limit)) }
        return all
    }

    public func allItems(limit: Int? = nil) -> [HeraldHistoryItem] {
        let merged = apps().flatMap { items(app: $0) }.sorted { $0.deliveredAt > $1.deliveredAt }
        if let limit { return Array(merged.prefix(limit)) }
        return merged
    }

    public func apps() -> [String] {
        lock.lock(); defer { lock.unlock() }
        return knownAppNames().sorted()
    }

    /// Items that were never dismissed, counted without building any list: this runs on every change to
    /// refresh the menu-bar badge.
    public func unreadCount() -> Int {
        lock.lock(); defer { lock.unlock() }
        return knownAppNames().reduce(0) { $0 + load($1).lazy.filter { $0.dismissedAt == nil }.count }
    }

    /// Lock held. The first call decodes the history files (and keeps what it decoded in `cache`); after that
    /// the set is maintained by `save` and `clear`.
    private func knownAppNames() -> Set<String> {
        if let known = knownApps { return known }
        var names = Set<String>()
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        for f in files where f.pathExtension == "json" {
            guard let data = try? Data(contentsOf: f),
                  let list = try? HeraldJSON.decoder().decode([HeraldHistoryItem].self, from: data),
                  let first = list.first else { continue }
            names.insert(first.app)
            if cache[first.app] == nil { cache[first.app] = list }
        }
        names.formUnion(cache.filter { !$0.value.isEmpty }.keys)
        knownApps = names
        return names
    }

    public func undismissed() -> [HeraldHistoryItem] {
        allItems().filter { $0.dismissedAt == nil }.sorted { $0.deliveredAt < $1.deliveredAt }
    }

    public func item(app: String, id: String) -> HeraldHistoryItem? {
        items(app: app).first { $0.id == id }
    }

    /// Per-app totals for the History sidebar. `unread` counts items whose banner was never dismissed.
    public func counts() -> [String: HistoryCount] {
        var out: [String: HistoryCount] = [:]
        for app in apps() {
            let list = items(app: app)
            out[app] = HistoryCount(total: list.count, unread: list.filter { $0.dismissedAt == nil }.count)
        }
        return out
    }

    /// Deletes several items of one app with a single file write (multi-select delete).
    public func delete(app: String, ids: Set<String>) {
        guard !ids.isEmpty else { return }
        lock.lock(); defer { lock.unlock() }
        var list = load(app)
        let removed = list.filter { ids.contains($0.id) }.map(\.imagePath)
        list.removeAll { ids.contains($0.id) }
        save(app, list)
        removeOrphanedImages(removed)
    }

    // MARK: Mutations

    /// Inserts at the front; an existing item with the same id is replaced.
    public func upsert(_ item: HeraldHistoryItem) {
        lock.lock(); defer { lock.unlock() }
        var list = load(item.app)
        var removed = list.filter { $0.id == item.id }.map(\.imagePath)
        list.removeAll { $0.id == item.id }
        list.insert(item, at: 0)
        if list.count > Self.cap {
            removed += list.suffix(list.count - Self.cap).map(\.imagePath)
            list.removeLast(list.count - Self.cap)
        }
        save(item.app, list)
        removeOrphanedImages(removed)
    }

    @discardableResult
    public func update(app: String, id: String, _ mutate: (inout HeraldHistoryItem) -> Void) -> HeraldHistoryItem? {
        lock.lock(); defer { lock.unlock() }
        var list = load(app)
        guard let idx = list.firstIndex(where: { $0.id == id }) else { return nil }
        let imageBefore = list[idx].imagePath
        mutate(&list[idx])
        save(app, list)
        if list[idx].imagePath != imageBefore { removeOrphanedImages([imageBefore]) }
        return list[idx]
    }

    public func delete(app: String, id: String) {
        lock.lock(); defer { lock.unlock() }
        var list = load(app)
        let removed = list.filter { $0.id == id }.map(\.imagePath)
        list.removeAll { $0.id == id }
        save(app, list)
        removeOrphanedImages(removed)
    }

    public func clear(app: String) {
        lock.lock(); defer { lock.unlock() }
        let removed = load(app).map(\.imagePath)
        cache[app] = []
        knownApps?.remove(app)
        try? FileManager.default.removeItem(at: file(for: app))
        removeOrphanedImages(removed)
    }

    // MARK: Images

    /// Stores image bytes under a content hash and returns the local path. Returns nil when the bytes are not
    /// an image Herald supports or are too large. The file extension comes from the detected format, never
    /// from the sender, so a payload cannot choose how LaunchServices will open the file it lands in.
    public func storeImage(_ data: Data) -> String? {
        guard data.count <= Self.maxImageBytes, let ext = ImageSniffer.fileExtension(for: data) else { return nil }
        let hash = SHA256.hash(data: data).prefix(8).map { String(format: "%02x", $0) }.joined()
        let url = imagesDirectory.appendingPathComponent("\(hash).\(ext)")
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)
            guard (try? data.write(to: url, options: .atomic)) != nil else { return nil }
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        }
        return url.path
    }

    /// Resolves a file path, `data:` URI or http(s) URL to a cached local file. Only real images are kept.
    public func cacheImage(_ spec: String) async -> String? {
        if spec.hasPrefix("data:") {
            guard let comma = spec.firstIndex(of: ","), spec[..<comma].contains(";base64"),
                  let data = Data(base64Encoded: String(spec[spec.index(after: comma)...]), options: .ignoreUnknownCharacters)
            else { return nil }
            return storeImage(data)
        }
        if spec.hasPrefix("http://") || spec.hasPrefix("https://") {
            guard let url = URL(string: spec) else { return nil }
            var req = URLRequest(url: url)
            req.timeoutInterval = 10
            guard let (data, resp) = try? await URLSession.shared.data(for: req),
                  (resp as? HTTPURLResponse)?.statusCode == 200, data.count <= Self.maxImageBytes else { return nil }
            return storeImage(data)
        }
        let path = (spec as NSString).expandingTildeInPath
        let size = (try? FileManager.default.attributesOfItem(atPath: path))?[.size] as? NSNumber
        guard let size, size.intValue <= Self.maxImageBytes,
              let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return nil }
        return storeImage(data)
    }

    /// Lock held. Deletes cached images that were referenced by the items just removed and are not referenced
    /// by any item that is left (images are content-addressed, so several items can share one file). Only
    /// files inside `images/` are ever touched.
    private func removeOrphanedImages(_ paths: [String?]) {
        let candidates = Set(paths.compactMap { $0 })
        guard !candidates.isEmpty else { return }
        var live = Set<String>()
        for app in knownAppNames() {
            for item in load(app) { if let p = item.imagePath { live.insert(p) } }
        }
        let root = imagesDirectory.standardizedFileURL.path + "/"
        for path in candidates where !live.contains(path) {
            guard URL(fileURLWithPath: path).standardizedFileURL.path.hasPrefix(root) else { continue }
            try? FileManager.default.removeItem(atPath: path)
        }
    }

    // MARK: Persistence

    private func file(for app: String) -> URL {
        let safe = String(app.map { $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" || $0 == "_" ? $0 : "_" })
        let suffix = safe == app ? "" : "-" + SHA256.hash(data: Data(app.utf8)).prefix(3).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(safe + suffix + ".json")
    }

    private func load(_ app: String) -> [HeraldHistoryItem] {
        if let c = cache[app] { return c }
        var list: [HeraldHistoryItem] = []
        if let data = try? Data(contentsOf: file(for: app)),
           let decoded = try? HeraldJSON.decoder().decode([HeraldHistoryItem].self, from: data) { list = decoded }
        cache[app] = list
        return list
    }

    private func save(_ app: String, _ list: [HeraldHistoryItem]) {
        cache[app] = list
        if list.isEmpty {
            knownApps?.remove(app)
            try? FileManager.default.removeItem(at: file(for: app))
            return
        }
        knownApps?.insert(app)
        if let data = try? HeraldJSON.encoder().encode(list) {
            try? data.write(to: file(for: app), options: .atomic)
        }
    }
}

/// Sidebar badge numbers for one app.
public struct HistoryCount: Equatable, Sendable {
    public var total: Int
    public var unread: Int
    public init(total: Int, unread: Int) { self.total = total; self.unread = unread }
}

/// Pure search/filter/export helpers for the History window, kept AppKit-free so they are unit tested.
public enum HistorySearch {
    /// Splits a query into lowercase-insensitive tokens; every token must match (AND), so
    /// "bid acme" finds an item with "bid" in the title and "Acme" in the subtitle.
    public static func tokens(_ query: String) -> [String] {
        query.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    }

    /// True when every token appears (case- and diacritic-insensitive) in title, subtitle, body,
    /// the app id, or the optional human display name of the app.
    public static func matches(_ item: HeraldHistoryItem, tokens: [String], appName: String? = nil) -> Bool {
        guard !tokens.isEmpty else { return true }
        let n = item.notification
        let fields = [n.title, n.subtitle ?? "", n.body ?? "", item.app, appName ?? ""]
        return tokens.allSatisfy { token in
            fields.contains { $0.range(of: token, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
        }
    }

    /// Filters newest-first `items` by `query`, preserving order. `appName` maps an app id to its display name.
    public static func filter(_ items: [HeraldHistoryItem], query: String,
                              appName: (String) -> String? = { _ in nil }) -> [HeraldHistoryItem] {
        let t = tokens(query)
        guard !t.isEmpty else { return items }
        return items.filter { matches($0, tokens: t, appName: appName($0.app)) }
    }

    /// Items for a sidebar selection: `nil` app means "All Apps". Always newest first.
    public static func scoped(_ items: [HeraldHistoryItem], app: String?) -> [HeraldHistoryItem] {
        let base = app.map { a in items.filter { $0.app == a } } ?? items
        return base.sorted { $0.deliveredAt > $1.deliveredAt }
    }

    /// Pretty-printed JSON array of full history records (what "Export JSON..." writes).
    public static func exportJSON(_ items: [HeraldHistoryItem]) throws -> Data {
        let e = HeraldJSON.encoder()
        e.outputFormatting.insert(.prettyPrinted)
        return try e.encode(items)
    }
}
