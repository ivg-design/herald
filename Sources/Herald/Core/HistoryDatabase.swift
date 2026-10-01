import Foundation
import SQLite3

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// The SQLite file behind `HistoryStore` (the system `SQLite3` module, no third-party code).
///
/// One table, one row per history record. The full record is a JSON `payload` (the same encoding the old
/// per-app files used, so nothing about `HeraldHistoryItem` changes), and the columns that are queried
/// carry their own copy: `app`, `deliveredAt`, `dismissedAt`, `snoozedUntil`, `imagePath`, plus a folded
/// `search` text that `LIKE` runs against. `seq` is the insertion order, so "newest first" for one app is
/// `ORDER BY seq DESC` exactly like the list the JSON files held.
///
/// Not thread-safe by itself: `HistoryStore` calls it with its lock held. Every statement is prepared once and
/// reused, and a write is one WAL append (`journal_mode = WAL`, `synchronous = NORMAL`), so a single upsert
/// no longer rewrites a whole per-app file.
final class HistoryDatabase: @unchecked Sendable {
    static let fileName = "history.sqlite"
    static let schemaVersion = 1

    /// False when the file could not be opened or repaired and the store fell back to a private in-memory
    /// database: history still works for this run, it just is not saved.
    let isPersistent: Bool
    private var handle: OpaquePointer?
    private var statements: [String: OpaquePointer] = [:]
    private var transactionDepth = 0
    private var transactionOpen = false
    private let encoder = HistoryDatabase.makeEncoder()
    private let decoder = HeraldJSON.decoder()

    private static func makeEncoder() -> JSONEncoder {
        // Same JSON as `HeraldJSON.encoder()` minus the key sorting: key order carries no meaning inside the
        // database, and skipping the sort is measurably faster.
        let e = HeraldJSON.encoder()
        e.outputFormatting = [.withoutEscapingSlashes]
        return e
    }

    /// The two pieces of a row that cost real work to build: the JSON payload and the folded search text.
    struct PreparedRow {
        var payload: Data
        var search: String
    }

    /// Builds the rows for `items` (same order, nil where an item could not be encoded). Large batches are
    /// encoded on up to eight threads: encoding, not SQLite, is what a bulk insert spends its time on (more
    /// threads do not help, `JSONEncoder` stops scaling there).
    static func prepare(_ items: [HeraldHistoryItem]) -> [PreparedRow?] {
        func row(_ item: HeraldHistoryItem, _ encoder: JSONEncoder) -> PreparedRow? {
            (try? encoder.encode(item)).map { PreparedRow(payload: $0, search: HistorySearch.searchText(for: item)) }
        }
        let chunk = max(256, (items.count + 7) / 8)
        guard items.count > chunk else {
            let e = makeEncoder()
            return items.map { row($0, e) }
        }
        var out = [PreparedRow?](repeating: nil, count: items.count)
        out.withUnsafeMutableBufferPointer { buffer in
            let slots = buffer
            DispatchQueue.concurrentPerform(iterations: (items.count + chunk - 1) / chunk) { c in
                let e = makeEncoder()
                for i in (c * chunk)..<min(items.count, (c + 1) * chunk) { slots[i] = row(items[i], e) }
            }
        }
        return out
    }

    // MARK: Opening

    private enum Opened { case ok(OpaquePointer), corrupt, failed }

    init(url: URL) {
        switch Self.openFile(url) {
        case .ok(let h):
            handle = h; isPersistent = true
        case .corrupt:
            // Not a database (or damaged beyond use): keep the bytes for the user, start a fresh file.
            Self.quarantine(url)
            if case .ok(let h) = Self.openFile(url) { handle = h; isPersistent = true }
            else { handle = Self.openMemory(); isPersistent = false }
        case .failed:
            handle = Self.openMemory(); isPersistent = false
        }
        if !isPersistent { NSLog("Herald: history.sqlite could not be opened; history is kept in memory for this run") }
    }

    deinit {
        for s in statements.values { sqlite3_finalize(s) }
        if let handle { sqlite3_close_v2(handle) }
    }

    private static func openFile(_ url: URL) -> Opened {
        var h: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(url.path, &h, flags, nil) == SQLITE_OK, let h else {
            sqlite3_close(h)
            return .failed
        }
        sqlite3_busy_timeout(h, 5000)
        // History can be private: the file (and the WAL files SQLite derives from its mode) is owner-only.
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        let rc = configure(h)
        guard rc == SQLITE_OK else {
            sqlite3_close(h)
            return rc == SQLITE_CORRUPT || rc == SQLITE_NOTADB ? .corrupt : .failed
        }
        return .ok(h)
    }

    private static func openMemory() -> OpaquePointer? {
        var h: OpaquePointer?
        guard sqlite3_open_v2(":memory:", &h, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK,
              let h else { sqlite3_close(h); return nil }
        guard configure(h) == SQLITE_OK else { sqlite3_close(h); return nil }
        return h
    }

    /// Pragmas, schema, version. Returns the first SQLite error code, SQLITE_OK on success.
    private static func configure(_ h: OpaquePointer) -> Int32 {
        let statements = [
            "PRAGMA journal_mode = WAL",
            "PRAGMA synchronous = NORMAL",
            "PRAGMA temp_store = MEMORY",
            """
            CREATE TABLE IF NOT EXISTS history (
                seq          INTEGER PRIMARY KEY,
                app          TEXT NOT NULL,
                id           TEXT NOT NULL,
                deliveredAt  REAL NOT NULL,
                dismissedAt  REAL,
                snoozedUntil REAL,
                imagePath    TEXT,
                search       TEXT NOT NULL,
                payload      TEXT NOT NULL,
                UNIQUE (app, id)
            )
            """,
            "CREATE INDEX IF NOT EXISTS history_app ON history (app)",
            "CREATE INDEX IF NOT EXISTS history_delivered ON history (deliveredAt)",
            "CREATE INDEX IF NOT EXISTS history_dismissed ON history (dismissedAt, deliveredAt)",
            "CREATE INDEX IF NOT EXISTS history_snoozed ON history (snoozedUntil) WHERE snoozedUntil IS NOT NULL",
            "CREATE INDEX IF NOT EXISTS history_image ON history (imagePath) WHERE imagePath IS NOT NULL",
            "PRAGMA user_version = \(schemaVersion)",
        ]
        for sql in statements {
            let rc = sqlite3_exec(h, sql, nil, nil, nil)
            if rc != SQLITE_OK { return rc }
        }
        return SQLITE_OK
    }

    /// Moves a database that cannot be read (and its WAL files) aside as `history.sqlite.corrupt-<time>`.
    private static func quarantine(_ url: URL) {
        let fm = FileManager.default
        let stamp = String(Int(Date().timeIntervalSince1970))
        for suffix in ["", "-wal", "-shm"] {
            let src = URL(fileURLWithPath: url.path + suffix)
            guard fm.fileExists(atPath: src.path) else { continue }
            let dst = URL(fileURLWithPath: url.path + ".corrupt-" + stamp + suffix)
            try? fm.removeItem(at: dst)
            try? fm.moveItem(at: src, to: dst)
        }
        NSLog("Herald: history.sqlite was not a readable database; moved aside as history.sqlite.corrupt-%@", stamp)
    }

    // MARK: Statement plumbing

    private func fail(_ what: String, _ rc: Int32) {
        let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "no connection"
        NSLog("Herald: history database %@ failed (%d): %@", what, rc, message)
    }

    /// A reusable prepared statement, reset and with its bindings cleared.
    private func prepared(_ sql: String) -> OpaquePointer? {
        if let s = statements[sql] {
            sqlite3_reset(s); sqlite3_clear_bindings(s)
            return s
        }
        guard let handle else { return nil }
        var s: OpaquePointer?
        let rc = sqlite3_prepare_v3(handle, sql, -1, UInt32(SQLITE_PREPARE_PERSISTENT), &s, nil)
        guard rc == SQLITE_OK, let s else { fail("prepare", rc); return nil }
        statements[sql] = s
        return s
    }

    private func text(_ s: OpaquePointer, _ i: Int32, _ v: String?) {
        if let v { sqlite3_bind_text(s, i, v, -1, sqliteTransient) } else { sqlite3_bind_null(s, i) }
    }
    private func real(_ s: OpaquePointer, _ i: Int32, _ v: Date?) {
        if let v { sqlite3_bind_double(s, i, v.timeIntervalSince1970) } else { sqlite3_bind_null(s, i) }
    }
    private func int(_ s: OpaquePointer, _ i: Int32, _ v: Int) { sqlite3_bind_int64(s, i, Int64(v)) }

    /// Runs a statement that returns no rows.
    @discardableResult
    private func execute(_ s: OpaquePointer) -> Bool {
        let rc = sqlite3_step(s)
        sqlite3_reset(s)
        if rc != SQLITE_DONE && rc != SQLITE_ROW { fail("step", rc); return false }
        return true
    }

    private func columnText(_ s: OpaquePointer, _ i: Int32) -> String? {
        sqlite3_column_text(s, i).map { String(cString: $0) }
    }

    private func decodeItem(_ s: OpaquePointer, column i: Int32) -> HeraldHistoryItem? {
        guard let p = sqlite3_column_text(s, i) else { return nil }
        let data = Data(bytesNoCopy: UnsafeMutableRawPointer(mutating: p), count: Int(sqlite3_column_bytes(s, i)),
                        deallocator: .none)
        return try? decoder.decode(HeraldHistoryItem.self, from: data)
    }

    /// Steps `s` to the end, decoding column 0 (`payload`) of every row.
    private func collect(_ s: OpaquePointer) -> [HeraldHistoryItem] {
        defer { sqlite3_reset(s) }
        var out: [HeraldHistoryItem] = []
        while sqlite3_step(s) == SQLITE_ROW { if let item = decodeItem(s, column: 0) { out.append(item) } }
        return out
    }

    private func counts(_ sql: String) -> [String: Int] {
        guard let s = prepared(sql) else { return [:] }
        defer { sqlite3_reset(s) }
        var out: [String: Int] = [:]
        while sqlite3_step(s) == SQLITE_ROW {
            if let app = columnText(s, 0) { out[app] = Int(sqlite3_column_int64(s, 1)) }
        }
        return out
    }

    // MARK: Transactions

    /// Groups the writes inside `body` into one commit. Nested calls join the outermost transaction.
    @discardableResult
    func transaction<T>(_ body: () -> T) -> T {
        if transactionDepth == 0 {
            transactionOpen = sqlite3_exec(handle, "BEGIN IMMEDIATE", nil, nil, nil) == SQLITE_OK
        }
        transactionDepth += 1
        defer {
            transactionDepth -= 1
            if transactionDepth == 0, transactionOpen {
                transactionOpen = false
                if sqlite3_exec(handle, "COMMIT", nil, nil, nil) != SQLITE_OK {
                    fail("commit", sqlite3_errcode(handle))
                    sqlite3_exec(handle, "ROLLBACK", nil, nil, nil)
                }
            }
        }
        return body()
    }

    // MARK: Writes

    /// Inserts `item` as the newest of its app, replacing a row with the same (app, id). False when it could not
    /// be stored (the previous row, if any, is then left alone).
    @discardableResult
    func upsert(_ item: HeraldHistoryItem, prepared row: PreparedRow? = nil) -> Bool {
        guard let row = row ?? (try? encoder.encode(item)).map({ PreparedRow(payload: $0, search: HistorySearch.searchText(for: item)) }),
              let s = prepared("""
              INSERT OR REPLACE INTO history (app, id, deliveredAt, dismissedAt, snoozedUntil, imagePath, search, payload)
              VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)
              """) else { return false }
        text(s, 1, item.app); text(s, 2, item.id)
        real(s, 3, item.deliveredAt); real(s, 4, item.dismissedAt); real(s, 5, item.snoozedUntil)
        text(s, 6, item.imagePath); text(s, 7, row.search)
        row.payload.withUnsafeBytes {
            _ = sqlite3_bind_text(s, 8, $0.baseAddress?.assumingMemoryBound(to: CChar.self), Int32($0.count), sqliteTransient)
        }
        return execute(s)
    }

    /// Rewrites the row of `item` in place (its position, `seq`, does not change).
    @discardableResult
    func update(_ item: HeraldHistoryItem) -> Bool {
        guard let payload = try? encoder.encode(item),
              let s = prepared("""
              UPDATE history SET deliveredAt = ?3, dismissedAt = ?4, snoozedUntil = ?5, imagePath = ?6, search = ?7, payload = ?8
              WHERE app = ?1 AND id = ?2
              """) else { return false }
        text(s, 1, item.app); text(s, 2, item.id)
        real(s, 3, item.deliveredAt); real(s, 4, item.dismissedAt); real(s, 5, item.snoozedUntil)
        text(s, 6, item.imagePath); text(s, 7, HistorySearch.searchText(for: item))
        payload.withUnsafeBytes {
            _ = sqlite3_bind_text(s, 8, $0.baseAddress?.assumingMemoryBound(to: CChar.self), Int32($0.count), sqliteTransient)
        }
        return execute(s)
    }

    /// Deletes one row and says what it held: nil when there was no such row, else its image path (which may be nil).
    func delete(app: String, id: String) -> Optional<String?> {
        guard let s = prepared("DELETE FROM history WHERE app = ?1 AND id = ?2 RETURNING imagePath") else { return nil }
        text(s, 1, app); text(s, 2, id)
        defer { sqlite3_reset(s) }
        var found: Optional<String?> = nil
        while true {
            let rc = sqlite3_step(s)
            if rc == SQLITE_ROW { found = .some(columnText(s, 0)) }
            else { if rc != SQLITE_DONE { fail("delete", rc) }; break }
        }
        return found
    }

    /// Deletes every row of `app` and returns the image paths they referenced.
    func deleteApp(_ app: String) -> [String?] {
        var images: [String?] = []
        if let s = prepared("DELETE FROM history WHERE app = ?1 RETURNING imagePath") {
            text(s, 1, app)
            while sqlite3_step(s) == SQLITE_ROW { images.append(columnText(s, 0)) }
            sqlite3_reset(s)
        }
        return images
    }

    /// Deletes the `count` oldest rows of `app` and returns the image paths they referenced.
    func removeOldest(app: String, count: Int) -> [String?] {
        guard count > 0, let pick = prepared("SELECT seq, imagePath FROM history WHERE app = ?1 ORDER BY seq ASC LIMIT ?2")
        else { return [] }
        text(pick, 1, app); int(pick, 2, count)
        var images: [String?] = []
        var last: Int64 = -1
        while sqlite3_step(pick) == SQLITE_ROW { last = sqlite3_column_int64(pick, 0); images.append(columnText(pick, 1)) }
        sqlite3_reset(pick)
        guard last >= 0, let del = prepared("DELETE FROM history WHERE app = ?1 AND seq <= ?2") else { return [] }
        text(del, 1, app); int(del, 2, Int(last))
        execute(del)
        return images
    }

    // MARK: Reads

    /// The image path of the row (nil outer = no such row).
    func imagePath(app: String, id: String) -> Optional<String?> {
        guard let s = prepared("SELECT imagePath FROM history WHERE app = ?1 AND id = ?2") else { return nil }
        text(s, 1, app); text(s, 2, id)
        defer { sqlite3_reset(s) }
        return sqlite3_step(s) == SQLITE_ROW ? .some(columnText(s, 0)) : nil
    }

    func item(app: String, id: String) -> HeraldHistoryItem? {
        guard let s = prepared("SELECT payload FROM history WHERE app = ?1 AND id = ?2") else { return nil }
        text(s, 1, app); text(s, 2, id)
        defer { sqlite3_reset(s) }
        return sqlite3_step(s) == SQLITE_ROW ? decodeItem(s, column: 0) : nil
    }

    /// Newest first (insertion order), at most `limit` (nil = all).
    func items(app: String, limit: Int?) -> [HeraldHistoryItem] {
        guard let s = prepared("SELECT payload FROM history WHERE app = ?1 ORDER BY seq DESC LIMIT ?2") else { return [] }
        text(s, 1, app); int(s, 2, limit ?? -1)
        return collect(s)
    }

    /// Newest delivery first across every app, at most `limit` (nil = all).
    func allItems(limit: Int?) -> [HeraldHistoryItem] {
        guard let s = prepared("SELECT payload FROM history ORDER BY deliveredAt DESC, seq DESC LIMIT ?1") else { return [] }
        int(s, 1, limit ?? -1)
        return collect(s)
    }

    /// Items whose banner was never dismissed, oldest delivery first.
    func undismissed() -> [HeraldHistoryItem] {
        guard let s = prepared("SELECT payload FROM history WHERE dismissedAt IS NULL ORDER BY deliveredAt ASC, seq ASC")
        else { return [] }
        return collect(s)
    }

    /// Undismissed items that are snoozed, soonest wake-up first.
    func snoozed() -> [HeraldHistoryItem] {
        guard let s = prepared("""
              SELECT payload FROM history WHERE snoozedUntil IS NOT NULL AND dismissedAt IS NULL ORDER BY snoozedUntil ASC, seq ASC
              """) else { return [] }
        return collect(s)
    }

    func unreadCount() -> Int {
        guard let s = prepared("SELECT COUNT(*) FROM history WHERE dismissedAt IS NULL") else { return 0 }
        defer { sqlite3_reset(s) }
        return sqlite3_step(s) == SQLITE_ROW ? Int(sqlite3_column_int64(s, 0)) : 0
    }

    func totalsByApp() -> [String: Int] { counts("SELECT app, COUNT(*) FROM history GROUP BY app") }
    func unreadByApp() -> [String: Int] { counts("SELECT app, COUNT(*) FROM history WHERE dismissedAt IS NULL GROUP BY app") }

    /// True when some row still points at the cached image `path`.
    func isImageReferenced(_ path: String) -> Bool {
        guard let s = prepared("SELECT 1 FROM history WHERE imagePath = ?1 LIMIT 1") else { return false }
        text(s, 1, path)
        defer { sqlite3_reset(s) }
        return sqlite3_step(s) == SQLITE_ROW
    }

    /// One `LIKE` per token (all must match) against the folded search text, newest delivery first. A token also
    /// matches every row of the apps in `apps` (those whose display name contains it).
    func search(tokens: [(like: String, apps: [String])], app: String?, limit: Int?) -> [HeraldHistoryItem] {
        guard let handle else { return [] }
        var clauses: [String] = []
        var binds: [String] = []
        for t in tokens {
            var clause = "search LIKE ? ESCAPE '\\'"
            binds.append(t.like)
            if !t.apps.isEmpty {
                clause += " OR app IN (" + Array(repeating: "?", count: t.apps.count).joined(separator: ",") + ")"
                binds += t.apps
            }
            clauses.append("(" + clause + ")")
        }
        if let app { clauses.append("app = ?"); binds.append(app) }
        var sql = "SELECT payload FROM history"
        if !clauses.isEmpty { sql += " WHERE " + clauses.joined(separator: " AND ") }
        sql += " ORDER BY deliveredAt DESC, seq DESC"
        if let limit { sql += " LIMIT \(max(0, limit))" }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            fail("prepare search", sqlite3_errcode(handle)); return []
        }
        defer { sqlite3_finalize(stmt) }
        for (i, b) in binds.enumerated() { sqlite3_bind_text(stmt, Int32(i + 1), b, -1, sqliteTransient) }
        return collect(stmt)
    }

    // MARK: Introspection (tests, diagnostics)

    /// Names of the indexes on the history table.
    func indexNames() -> [String] {
        guard let s = prepared("SELECT name FROM sqlite_master WHERE type = 'index' AND tbl_name = 'history' ORDER BY name")
        else { return [] }
        defer { sqlite3_reset(s) }
        var out: [String] = []
        while sqlite3_step(s) == SQLITE_ROW { if let n = columnText(s, 0) { out.append(n) } }
        return out
    }

    /// The query plan SQLite would use for `sql` (one line per step).
    func queryPlan(_ sql: String) -> [String] {
        guard let handle else { return [] }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, "EXPLAIN QUERY PLAN " + sql, -1, &stmt, nil) == SQLITE_OK, let stmt else { return [] }
        defer { sqlite3_finalize(stmt) }
        var out: [String] = []
        while sqlite3_step(stmt) == SQLITE_ROW { if let p = sqlite3_column_text(stmt, 3) { out.append(String(cString: p)) } }
        return out
    }
}
