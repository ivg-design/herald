import Foundation
import CryptoKit

/// What the one-time import of the old per-app JSON history files did (nil on a store that had nothing to import).
public struct HistoryMigrationReport: Equatable, Sendable {
    /// JSON files whose items were imported.
    public var files: Int
    /// History items read from them (before the per-app cap was applied).
    public var items: Int
    /// Apps those items belonged to.
    public var apps: Int
    /// Files that could not be decoded; they are in the backup folder untouched.
    public var unreadable: [String]
    /// Where the original JSON files were moved. Nil when the database is in-memory and they were left in place.
    public var backupDirectory: URL?
}

/// History persisted in SQLite (`history.sqlite` inside `directory`), newest first per app, capped per app
/// (`capPerApp`, 1000 by default). Reads of one app are served from a lazily filled in-memory copy that every
/// write keeps current; every write is an incremental statement, never a rewrite of a whole app's history.
public final class HistoryStore: @unchecked Sendable {
    public static let cap = 1000
    /// Upper bound for `capPerApp`.
    public static let maxCap = 100_000
    /// The largest image Herald will cache (a decoded hero image is far smaller than this).
    public static let maxImageBytes = 10 * 1024 * 1024

    public let directory: URL
    public var imagesDirectory: URL { directory.appendingPathComponent("images", isDirectory: true) }
    public var databaseURL: URL { directory.appendingPathComponent(HistoryDatabase.fileName) }
    /// Set when this store imported the old JSON files while opening; nil otherwise.
    public private(set) var migration: HistoryMigrationReport?
    /// False when `history.sqlite` could not be opened and history is only kept in memory for this run.
    public var isPersistent: Bool { db.isPersistent }

    private let lock = NSLock()
    private let db: HistoryDatabase
    private var cap: Int
    /// Decoded per-app lists, newest first. Filled by the first read of an app and kept in step by every write;
    /// an app that was only written to is never loaded just to be updated.
    private var cache: [String: [HeraldHistoryItem]] = [:]
    /// Item count of every app that has history. Read from the database once, when the store opens, and then
    /// maintained by the writes, so the app list and the cap check never touch the database.
    private var appCounts: [String: Int]

    public init(directory: URL, cap: Int = HistoryStore.cap) {
        self.directory = directory
        self.cap = Self.clamp(cap)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: directory.appendingPathComponent("images", isDirectory: true),
                                                 withIntermediateDirectories: true)
        let db = HistoryDatabase(url: directory.appendingPathComponent(HistoryDatabase.fileName))
        self.db = db
        migration = Self.importJSONFiles(from: directory, into: db)
        appCounts = db.totalsByApp()
        var removed: [String?] = []
        db.transaction {
            for (app, n) in appCounts where n > self.cap { removed += self.enforceCap(app) }
        }
        removeOrphanedImages(removed)
    }

    private static func clamp(_ cap: Int) -> Int { min(max(cap, 1), maxCap) }

    /// How many items one app keeps; the oldest beyond it are deleted (with their cached images). Lowering it
    /// trims every app at once.
    public var capPerApp: Int {
        get { lock.lock(); defer { lock.unlock() }; return cap }
        set {
            lock.lock(); defer { lock.unlock() }
            cap = Self.clamp(newValue)
            var removed: [String?] = []
            db.transaction { for (app, n) in appCounts where n > cap { removed += enforceCap(app) } }
            removeOrphanedImages(removed)
        }
    }

    // MARK: Queries

    public func items(app: String, limit: Int? = nil) -> [HeraldHistoryItem] {
        lock.lock(); defer { lock.unlock() }
        if cache[app] == nil, let limit, limit >= 0 { return db.items(app: app, limit: limit) }
        let all = load(app)
        if let limit, limit >= 0 { return Array(all.prefix(limit)) }
        return all
    }

    /// Every app's items, newest delivery first. With a `limit` only that many rows are read and decoded.
    public func allItems(limit: Int? = nil) -> [HeraldHistoryItem] {
        if let limit, limit >= 0 {
            lock.lock(); defer { lock.unlock() }
            return db.allItems(limit: limit)
        }
        return apps().flatMap { items(app: $0) }.sorted { $0.deliveredAt > $1.deliveredAt }
    }

    public func apps() -> [String] {
        lock.lock(); defer { lock.unlock() }
        return appCounts.keys.sorted()
    }

    /// Items that were never dismissed, counted by the database without building any list: this runs on every
    /// change to refresh the menu-bar badge.
    public func unreadCount() -> Int {
        lock.lock(); defer { lock.unlock() }
        return db.unreadCount()
    }

    /// Items whose banner was never dismissed, oldest delivery first (snoozed ones included).
    public func undismissed() -> [HeraldHistoryItem] {
        lock.lock(); defer { lock.unlock() }
        return db.undismissed()
    }

    /// Undismissed items that are snoozed, soonest wake-up first.
    public func snoozed() -> [HeraldHistoryItem] {
        lock.lock(); defer { lock.unlock() }
        return db.snoozed()
    }

    public func item(app: String, id: String) -> HeraldHistoryItem? {
        lock.lock(); defer { lock.unlock() }
        if let cached = cache[app] { return cached.first { $0.id == id } }
        return db.item(app: app, id: id)
    }

    /// Per-app totals for the History sidebar. `unread` counts items whose banner was never dismissed.
    public func counts() -> [String: HistoryCount] {
        lock.lock(); defer { lock.unlock() }
        let unread = db.unreadByApp()
        return appCounts.reduce(into: [:]) { $0[$1.key] = HistoryCount(total: $1.value, unread: unread[$1.key] ?? 0) }
    }

    /// Search with SQL `LIKE`, newest delivery first. Same rules as `HistorySearch.filter`: the query is split
    /// into whitespace-separated tokens, every token must appear (case- and diacritic-insensitively) in the
    /// title, subtitle, body or app id, or in the display name `appName` gives the app. `app` limits the search
    /// to one app, `limit` caps the number of results. An empty query returns everything in scope.
    public func search(_ query: String, app: String? = nil, limit: Int? = nil,
                       appName: (String) -> String? = { _ in nil }) -> [HeraldHistoryItem] {
        let tokens = HistorySearch.tokens(query)
        guard !tokens.isEmpty else {
            if let app { return items(app: app, limit: limit) }
            return allItems(limit: limit)
        }
        // Display names come from the caller's registry: resolve them before taking the store lock.
        let names = apps().map { ($0, HistorySearch.fold(appName($0) ?? "")) }
        let prepared = tokens.map { token -> (like: String, apps: [String]) in
            let folded = HistorySearch.fold(token)
            return ("%" + Self.escapeLike(folded) + "%", names.filter { !$0.1.isEmpty && $0.1.contains(folded) }.map { $0.0 })
        }
        lock.lock(); defer { lock.unlock() }
        return db.search(tokens: prepared, app: app, limit: limit.map { max(0, $0) })
    }

    private static func escapeLike(_ s: String) -> String {
        var out = ""
        for ch in s {
            if ch == "\\" || ch == "%" || ch == "_" { out.append("\\") }
            out.append(ch)
        }
        return out
    }

    /// Pretty-printed JSON array of the full records of `app` (all apps when nil), newest first: what
    /// "Export JSON..." writes.
    public func exportJSON(app: String? = nil) throws -> Data {
        try HistorySearch.exportJSON(app.map { items(app: $0) } ?? allItems())
    }

    // MARK: Mutations

    /// Inserts at the front; an existing item with the same id is replaced.
    public func upsert(_ item: HeraldHistoryItem) {
        lock.lock(); defer { lock.unlock() }
        var removed: [String?] = []
        db.transaction { upsertLocked(item, row: nil, removed: &removed, touchCache: true) }
        removeOrphanedImages(removed)
    }

    /// Inserts many items in one transaction (`items[0]` is stored first, so the last one ends up newest).
    /// Much faster than a loop of `upsert` for imports and bulk tests.
    public func upsert(contentsOf items: [HeraldHistoryItem]) {
        guard !items.isEmpty else { return }
        lock.lock(); defer { lock.unlock() }
        var removed: [String?] = []
        let rows = HistoryDatabase.prepare(items)   // encoded in parallel, outside the transaction
        db.transaction {
            for (item, row) in zip(items, rows) { upsertLocked(item, row: row, removed: &removed, touchCache: false) }
        }
        for app in Set(items.map(\.app)) { cache[app] = nil }
        removeOrphanedImages(removed)
    }

    /// Lock held, inside a transaction.
    private func upsertLocked(_ item: HeraldHistoryItem, row: HistoryDatabase.PreparedRow?, removed: inout [String?],
                              touchCache: Bool) {
        let previous = db.imagePath(app: item.app, id: item.id)
        guard db.upsert(item, prepared: row) else { return }
        if let previous { removed.append(previous) } else { appCounts[item.app, default: 0] += 1 }
        if touchCache, cache[item.app] != nil {
            cache[item.app]!.removeAll { $0.id == item.id }
            cache[item.app]!.insert(item, at: 0)
        }
        removed += enforceCap(item.app)   // after the cache has the new item, so it trims that copy too
    }

    @discardableResult
    public func update(app: String, id: String, _ mutate: (inout HeraldHistoryItem) -> Void) -> HeraldHistoryItem? {
        lock.lock(); defer { lock.unlock() }
        var item: HeraldHistoryItem
        if let cached = cache[app] {
            guard let hit = cached.first(where: { $0.id == id }) else { return nil }
            item = hit
        } else {
            guard let hit = db.item(app: app, id: id) else { return nil }
            item = hit
        }
        let imageBefore = item.imagePath
        mutate(&item)
        item.id = id; item.app = app   // an update never moves a record to another key
        db.update(item)
        if let i = cache[app]?.firstIndex(where: { $0.id == id }) { cache[app]![i] = item }
        if item.imagePath != imageBefore { removeOrphanedImages([imageBefore]) }
        return item
    }

    public func delete(app: String, id: String) { delete(app: app, ids: [id]) }

    /// Deletes several items of one app in one transaction (multi-select delete).
    public func delete(app: String, ids: Set<String>) {
        guard !ids.isEmpty else { return }
        lock.lock(); defer { lock.unlock() }
        var removed: [String?] = []
        db.transaction {
            for id in ids {
                guard let image = db.delete(app: app, id: id) else { continue }
                removed.append(image)
                dropCount(app)
            }
        }
        cache[app]?.removeAll { ids.contains($0.id) }
        removeOrphanedImages(removed)
    }

    /// Moves every item of `from` to `to` (the notification's own `app` too) and, when the item has no group, gives it `group`.
    /// An item whose id already exists under `to` is replaced. Returns how many moved. The folded `herald.connectors` -> `herald` uses it.
    @discardableResult
    public func reassign(from: String, to: String, group: String? = nil) -> Int {
        guard from != to else { return 0 }
        let moved: [HeraldHistoryItem] = items(app: from).reversed().map { old in
            var item = old
            item.app = to; item.notification.app = to
            if let group, item.notification.group == nil { item.notification.group = group }
            return item
        }
        guard !moved.isEmpty else { return 0 }
        // The two lists are merged by delivery time and written oldest first, so the new app's list stays newest first (rows are
        // ordered by when they were written; rewriting the existing ones keeps them in line with the moved ones).
        let merged = (items(app: to).reversed() + moved).enumerated()
            .sorted { $0.element.deliveredAt != $1.element.deliveredAt ? $0.element.deliveredAt < $1.element.deliveredAt : $0.offset < $1.offset }
            .map(\.element)
        upsert(contentsOf: merged)
        clear(app: from)
        return moved.count
    }

    public func clear(app: String) {
        lock.lock(); defer { lock.unlock() }
        let removed = db.deleteApp(app)
        appCounts[app] = nil
        cache[app] = nil
        removeOrphanedImages(removed)
    }

    /// Lock held. One item of `app` is gone; the app leaves the list when it was the last.
    private func dropCount(_ app: String) {
        let n = (appCounts[app] ?? 1) - 1
        appCounts[app] = n > 0 ? n : nil
    }

    /// Lock held, inside a transaction. Deletes the oldest items of `app` beyond the cap and returns the image
    /// paths they referenced.
    private func enforceCap(_ app: String) -> [String?] {
        let excess = (appCounts[app] ?? 0) - cap
        guard excess > 0 else { return [] }
        let images = db.removeOldest(app: app, count: excess)
        appCounts[app] = max(0, (appCounts[app] ?? 0) - images.count)
        if let c = cache[app], c.count > cap { cache[app] = Array(c.prefix(cap)) }
        return images
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

    /// Deletes cached images that were referenced by the items just removed and are not referenced by any item
    /// that is left (images are content-addressed, so several items can share one file). Only files inside
    /// `images/` are ever touched. Call it after the rows are gone.
    private func removeOrphanedImages(_ paths: [String?]) {
        let candidates = Set(paths.compactMap { $0 })
        guard !candidates.isEmpty else { return }
        let root = imagesDirectory.standardizedFileURL.path + "/"
        for path in candidates where !db.isImageReferenced(path) {
            guard URL(fileURLWithPath: path).standardizedFileURL.path.hasPrefix(root) else { continue }
            try? FileManager.default.removeItem(atPath: path)
        }
    }

    // MARK: Persistence

    /// Lock held. One app's items, newest first, from the in-memory copy (read from the database once).
    private func load(_ app: String) -> [HeraldHistoryItem] {
        if let c = cache[app] { return c }
        let list = db.items(app: app, limit: nil)
        cache[app] = list
        return list
    }

    /// Imports the per-app JSON files Herald 1.0 and 1.1 wrote (`<app>.json` directly inside `directory`) into
    /// the database, then moves every one of them into `json-backup-<yyyyMMdd-HHmmss>/` so nothing is imported
    /// twice and the originals stay available. Items whose (app, id) is already in the database are kept as the
    /// database has them. Returns nil when there was no JSON file. A file that does not decode is not imported
    /// and goes to the backup folder like the others. When the database is only in memory the files are left
    /// where they are, since they are then the only copy on disk.
    private static func importJSONFiles(from directory: URL, into db: HistoryDatabase) -> HistoryMigrationReport? {
        let fm = FileManager.default
        let entries = (try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        let files = entries.filter { $0.pathExtension.lowercased() == "json" }
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) != true }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        guard !files.isEmpty else { return nil }

        let decoder = HeraldJSON.decoder()
        var perApp: [String: [HeraldHistoryItem]] = [:]   // newest first, as the files held them
        var unreadable: [String] = []
        var imported = 0
        for file in files {
            guard let data = try? Data(contentsOf: file),
                  let list = try? decoder.decode([HeraldHistoryItem].self, from: data) else {
                unreadable.append(file.lastPathComponent); continue
            }
            imported += 1
            for item in list { perApp[item.app, default: []].append(item) }
        }
        var itemCount = 0
        var ordered: [HeraldHistoryItem] = []
        for app in perApp.keys.sorted() {
            var seen = Set<String>()
            let list = perApp[app]!.filter { seen.insert($0.id).inserted }
            itemCount += list.count
            // Oldest first, so the newest item gets the highest sequence number and stays at the front.
            ordered += list.reversed()
        }
        let rows = HistoryDatabase.prepare(ordered)
        db.transaction {
            for (item, row) in zip(ordered, rows) where db.imagePath(app: item.app, id: item.id) == nil {
                db.upsert(item, prepared: row)
            }
        }
        var backup: URL?
        if db.isPersistent {
            let stamp = DateFormatter()
            stamp.locale = Locale(identifier: "en_US_POSIX"); stamp.dateFormat = "yyyyMMdd-HHmmss"
            var dir = directory.appendingPathComponent("json-backup-" + stamp.string(from: Date()), isDirectory: true)
            var n = 2
            while fm.fileExists(atPath: dir.path) {
                dir = directory.appendingPathComponent("json-backup-" + stamp.string(from: Date()) + "-\(n)", isDirectory: true)
                n += 1
            }
            if (try? fm.createDirectory(at: dir, withIntermediateDirectories: true)) != nil {
                backup = dir
                for file in files {
                    let target = dir.appendingPathComponent(file.lastPathComponent)
                    if (try? fm.moveItem(at: file, to: target)) == nil, (try? fm.copyItem(at: file, to: target)) != nil {
                        try? fm.removeItem(at: file)
                    }
                }
            }
        }
        NSLog("Herald: imported %d history items from %d JSON files into history.sqlite%@", itemCount, imported,
              backup.map { "; originals are in " + $0.lastPathComponent } ?? "")
        return HistoryMigrationReport(files: imported, items: itemCount, apps: perApp.count, unreadable: unreadable,
                                      backupDirectory: backup)
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

    /// Case- and diacritic-insensitive form of `s`: the form the database's search column and a query token are
    /// both reduced to, so a plain `LIKE` on it matches what `matches` would.
    public static func fold(_ s: String) -> String {
        if s.utf8.allSatisfy({ $0 < 0x80 }) { return s.lowercased() }
        return s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    /// What the database searches for `item`: title, subtitle, body and app id, folded and one per line (a
    /// token never contains a newline, so it cannot match across two fields).
    public static func searchText(for item: HeraldHistoryItem) -> String {
        let n = item.notification
        return fold([n.title, n.subtitle ?? "", n.body ?? "", item.app].joined(separator: "\n"))
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
