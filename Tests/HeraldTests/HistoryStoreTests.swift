import XCTest
import SQLite3
@testable import HeraldCore

final class HistoryStoreTests: XCTestCase {
    var dir: URL!
    override func setUp() { dir = FileManager.default.temporaryDirectory.appendingPathComponent("herald-hist-\(UUID().uuidString)") }
    override func tearDown() { try? FileManager.default.removeItem(at: dir) }

    private func item(_ app: String, _ id: String, _ t: TimeInterval = 0, title: String = "t") -> HeraldHistoryItem {
        HeraldHistoryItem(id: id, app: app, notification: HeraldNotification(app: app, id: id, title: title),
                          deliveredAt: Date(timeIntervalSince1970: 1_700_000_000 + t))
    }

    func testNewestFirstReplaceAndPersistence() {
        let s = HistoryStore(directory: dir)
        s.upsert(item("a", "1", 0)); s.upsert(item("a", "2", 1)); s.upsert(item("a", "1", 2, title: "again"))
        XCTAssertEqual(s.items(app: "a").map(\.id), ["1", "2"])
        XCTAssertEqual(s.items(app: "a").first?.notification.title, "again")
        let reopened = HistoryStore(directory: dir)
        XCTAssertEqual(reopened.items(app: "a").map(\.id), ["1", "2"])
        XCTAssertEqual(reopened.apps(), ["a"])
    }

    func testCapAt1000() {
        let s = HistoryStore(directory: dir)
        for i in 0..<1005 { s.upsert(item("a", "\(i)", TimeInterval(i))) }
        let all = s.items(app: "a")
        XCTAssertEqual(all.count, 1000)
        XCTAssertEqual(all.first?.id, "1004"); XCTAssertEqual(all.last?.id, "5")
    }

    func testDismissUndismissedDeleteClear() {
        let s = HistoryStore(directory: dir)
        s.upsert(item("a", "1", 0)); s.upsert(item("b", "2", 1))
        XCTAssertEqual(s.undismissed().map(\.id), ["1", "2"])
        s.update(app: "a", id: "1") { $0.dismissedAt = Date(); $0.actionUsed = "Open" }
        XCTAssertEqual(s.undismissed().map(\.id), ["2"])
        XCTAssertEqual(s.item(app: "a", id: "1")?.actionUsed, "Open")
        s.delete(app: "b", id: "2")
        XCTAssertTrue(s.items(app: "b").isEmpty)
        s.clear(app: "a")
        XCTAssertEqual(s.apps(), [])
        XCTAssertEqual(s.allItems().count, 0)
    }

    func testAppsWithOddNamesDoNotCollide() {
        let s = HistoryStore(directory: dir)
        s.upsert(item("a/b", "1")); s.upsert(item("a_b", "2"))
        XCTAssertEqual(s.items(app: "a/b").map(\.id), ["1"])
        XCTAssertEqual(s.items(app: "a_b").map(\.id), ["2"])
    }

    func testImageCache() async throws {
        let s = HistoryStore(directory: dir)
        let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 1, 2, 3])
        let viaData = await s.cacheImage("data:image/png;base64," + png.base64EncodedString())
        XCTAssertNotNil(viaData)
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: viaData!)), png)
        let src = dir.appendingPathComponent("src.png"); try png.write(to: src)
        let viaPath = await s.cacheImage(src.path)
        XCTAssertEqual(viaPath, viaData)   // content-hash dedupe
        let missing = await s.cacheImage("/no/such/file.png")
        XCTAssertNil(missing)
    }

    // MARK: SQLite storage (#26)

    /// A full-size record: every optional section filled in so the payload column has to carry all of it.
    private func richItem(_ app: String, _ id: String, _ t: TimeInterval = 0) -> HeraldHistoryItem {
        var n = HeraldNotification(app: app, id: id, title: "Bid accepted", subtitle: "Acme RFP",
                                   body: "Your bid for the \u{201C}Rive demo\u{201D} was accepted. See [details](https://x.test/a?b=1&c=2).",
                                   url: "https://x.test/bids/\(id)", sound: "Glass", snooze: true,
                                   metadata: .object(["amount": .number(1200), "tags": .array([.string("a"), .string("b")])]))
        n.buttons = [HeraldButton(label: "Open", url: "https://x.test/open"), HeraldButton(label: "Archive", command: "echo hi")]
        var i = HeraldHistoryItem(id: id, app: app, notification: n, deliveredAt: Date(timeIntervalSince1970: 1_700_000_000 + t),
                                  dismissedAt: Date(timeIntervalSince1970: 1_700_000_050 + t), actionUsed: "Open",
                                  snoozedUntil: Date(timeIntervalSince1970: 1_700_009_000 + t), imagePath: nil,
                                  fields: ["amount": .number(1200), "client": .text("Acme"), "late": .bool(false), "tags": .list(["x", "y"])])
        i.speech = HeraldSpeech(text: "Bid accepted", voice: "af_heart", audioPath: "/tmp/x.wav", durationSeconds: 1.5)
        return i
    }

    private func sqliteRows(_ sql: String) -> [[String]] {
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open_v2(dir.appendingPathComponent("history.sqlite").path, &db, SQLITE_OPEN_READONLY, nil), SQLITE_OK)
        defer { sqlite3_close(db) }
        var stmt: OpaquePointer?
        XCTAssertEqual(sqlite3_prepare_v2(db, sql, -1, &stmt, nil), SQLITE_OK, sql)
        defer { sqlite3_finalize(stmt) }
        var rows: [[String]] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            rows.append((0..<sqlite3_column_count(stmt)).map { i in sqlite3_column_text(stmt, i).map { String(cString: $0) } ?? "NULL" })
        }
        return rows
    }

    func testHistoryLivesInOneSQLiteFileNotPerAppJSON() throws {
        let s = HistoryStore(directory: dir)
        s.upsert(item("a", "1", 0)); s.upsert(item("b", "2", 1))
        XCTAssertEqual(s.databaseURL.lastPathComponent, "history.sqlite")
        XCTAssertTrue(FileManager.default.fileExists(atPath: s.databaseURL.path))
        XCTAssertTrue(s.isPersistent)
        XCTAssertNil(s.migration)
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        XCTAssertFalse(names.contains { $0.hasSuffix(".json") }, "no per-app JSON files: \(names)")
        let perms = try FileManager.default.attributesOfItem(atPath: s.databaseURL.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(perms?.intValue, 0o600)
    }

    func testTableHasTheIndexesAndColumnsTheQueriesNeed() {
        let s = HistoryStore(directory: dir)
        s.upsert(item("a", "1"))
        let cols = sqliteRows("SELECT name FROM pragma_table_info('history')").map(\.[0])
        XCTAssertEqual(Set(cols), ["seq", "app", "id", "deliveredAt", "dismissedAt", "snoozedUntil", "imagePath", "search", "payload"])
        let indexed = Set(sqliteRows("SELECT DISTINCT ii.name FROM pragma_index_list('history') il, pragma_index_info(il.name) ii").map(\.[0]))
        XCTAssertTrue(indexed.isSuperset(of: ["app", "deliveredAt", "dismissedAt", "snoozedUntil"]), "\(indexed)")
        XCTAssertEqual(sqliteRows("PRAGMA user_version"), [["1"]])
        XCTAssertEqual(sqliteRows("PRAGMA journal_mode"), [["wal"]])
    }

    func testEveryFieldOfARecordSurvivesReopening() {
        let s = HistoryStore(directory: dir)
        let rich = richItem("a", "1")
        s.upsert(rich)
        let back = HistoryStore(directory: dir).item(app: "a", id: "1")
        XCTAssertEqual(back?.notification, rich.notification)
        XCTAssertEqual(back?.fields, rich.fields)
        XCTAssertEqual(back?.speech, rich.speech)
        XCTAssertEqual(back?.actionUsed, "Open")
        XCTAssertEqual(back?.dismissedAt?.timeIntervalSince1970 ?? 0, rich.dismissedAt!.timeIntervalSince1970, accuracy: 0.001)
        XCTAssertEqual(back?.snoozedUntil?.timeIntervalSince1970 ?? 0, rich.snoozedUntil!.timeIntervalSince1970, accuracy: 0.001)
    }

    func testIndexedColumnsFollowTheRecord() {
        let s = HistoryStore(directory: dir)
        s.upsert(item("a", "1", 0)); s.upsert(item("a", "2", 5))
        s.update(app: "a", id: "1") { $0.dismissedAt = Date(timeIntervalSince1970: 1_700_000_900); $0.snoozedUntil = nil }
        s.update(app: "a", id: "2") { $0.snoozedUntil = Date(timeIntervalSince1970: 1_700_005_000) }
        let rows = sqliteRows("SELECT id, deliveredAt, dismissedAt, snoozedUntil FROM history ORDER BY id")
        XCTAssertEqual(rows, [["1", "1700000000.0", "1700000900.0", "NULL"], ["2", "1700000005.0", "NULL", "1700005000.0"]])
    }

    func testUnreadCountSnoozedAndUndismissedComeFromTheDatabase() {
        let s = HistoryStore(directory: dir)
        for i in 0..<5 { s.upsert(item("a", "\(i)", TimeInterval(i))) }
        s.update(app: "a", id: "1") { $0.dismissedAt = Date() }
        s.update(app: "a", id: "3") { $0.snoozedUntil = Date(timeIntervalSince1970: 1_800_000_000) }
        s.update(app: "a", id: "0") { $0.snoozedUntil = Date(timeIntervalSince1970: 1_700_000_500); $0.dismissedAt = Date() }
        XCTAssertEqual(s.unreadCount(), 3)
        XCTAssertEqual(s.undismissed().map(\.id), ["2", "3", "4"], "oldest delivery first")
        XCTAssertEqual(s.snoozed().map(\.id), ["3"], "a dismissed item is no longer waiting for its snooze")
        XCTAssertEqual(s.counts(), ["a": HistoryCount(total: 5, unread: 3)])
    }

    func testPositionSurvivesAnUpdateAndAnUpsertMovesToTheFront() {
        let s = HistoryStore(directory: dir)
        s.upsert(item("a", "1", 0)); s.upsert(item("a", "2", 1)); s.upsert(item("a", "3", 2))
        s.update(app: "a", id: "2") { $0.actionUsed = "x" }
        XCTAssertEqual(s.items(app: "a").map(\.id), ["3", "2", "1"])
        XCTAssertEqual(HistoryStore(directory: dir).items(app: "a").map(\.id), ["3", "2", "1"])
        s.upsert(item("a", "1", 3))
        XCTAssertEqual(HistoryStore(directory: dir).items(app: "a").map(\.id), ["1", "3", "2"])
    }

    func testUpdateOfAnUnknownItemReturnsNilAndCannotMoveARecord() {
        let s = HistoryStore(directory: dir)
        s.upsert(item("a", "1"))
        XCTAssertNil(s.update(app: "a", id: "nope") { $0.actionUsed = "x" })
        XCTAssertNil(s.update(app: "b", id: "1") { $0.actionUsed = "x" })
        let moved = s.update(app: "a", id: "1") { $0.id = "other"; $0.app = "z" }
        XCTAssertEqual(moved?.id, "1"); XCTAssertEqual(moved?.app, "a")
        XCTAssertEqual(s.apps(), ["a"])
    }

    func testReadsOfOneItemAndALimitedListDoNotNeedTheWholeAppLoaded() {
        let s = HistoryStore(directory: dir)
        for i in 0..<30 { s.upsert(item("a", "\(i)", TimeInterval(i))) }
        let fresh = HistoryStore(directory: dir)    // nothing cached yet
        XCTAssertEqual(fresh.item(app: "a", id: "7")?.id, "7")
        XCTAssertEqual(fresh.items(app: "a", limit: 3).map(\.id), ["29", "28", "27"])
        XCTAssertEqual(fresh.allItems(limit: 2).map(\.id), ["29", "28"])
        XCTAssertEqual(fresh.items(app: "a").count, 30)
        XCTAssertEqual(fresh.items(app: "a", limit: 2).map(\.id), ["29", "28"])
        XCTAssertNil(fresh.item(app: "a", id: "nope"))
        XCTAssertNil(fresh.item(app: "zzz", id: "1"))
    }

    func testWritesAfterAReadKeepTheCachedListCurrent() {
        let s = HistoryStore(directory: dir)
        s.upsert(item("a", "1", 0)); s.upsert(item("a", "2", 1))
        XCTAssertEqual(s.items(app: "a").map(\.id), ["2", "1"])         // loads the cache
        s.upsert(item("a", "3", 2)); s.upsert(item("a", "1", 3))
        XCTAssertEqual(s.items(app: "a").map(\.id), ["1", "3", "2"])
        s.update(app: "a", id: "3") { $0.actionUsed = "go" }
        XCTAssertEqual(s.item(app: "a", id: "3")?.actionUsed, "go")
        s.delete(app: "a", id: "2")
        XCTAssertEqual(s.items(app: "a").map(\.id), ["1", "3"])
        s.delete(app: "a", ids: ["1", "3"])
        XCTAssertTrue(s.items(app: "a").isEmpty)
        XCTAssertEqual(s.apps(), [])
        for reopened in [HistoryStore(directory: dir)] { XCTAssertTrue(reopened.items(app: "a").isEmpty) }
    }

    func testBatchUpsertIsOneTransactionAndKeepsOrder() {
        let s = HistoryStore(directory: dir)
        s.upsert(contentsOf: (0..<50).map { item("a", "\($0)", TimeInterval($0)) } + [item("a", "10", 99)])
        XCTAssertEqual(s.items(app: "a").count, 50)
        XCTAssertEqual(s.items(app: "a").first?.id, "10")
        XCTAssertEqual(s.items(app: "a").last?.id, "0")
        s.upsert(contentsOf: [])
        XCTAssertEqual(HistoryStore(directory: dir).items(app: "a").count, 50)
    }

    // MARK: Configurable cap

    func testCapPerAppIsConfigurableAtInit() {
        let s = HistoryStore(directory: dir, cap: 5)
        for i in 0..<8 { s.upsert(item("a", "\(i)", TimeInterval(i))) }
        s.upsert(item("b", "x"))
        XCTAssertEqual(s.capPerApp, 5)
        XCTAssertEqual(s.items(app: "a").map(\.id), ["7", "6", "5", "4", "3"])
        XCTAssertEqual(s.items(app: "b").count, 1, "the cap is per app")
        XCTAssertEqual(s.counts()["a"]?.total, 5)
        XCTAssertEqual(HistoryStore(directory: dir, cap: 5).items(app: "a").count, 5)
    }

    func testLoweringTheCapTrimsEveryAppRaisingItLetsThemGrow() {
        let s = HistoryStore(directory: dir, cap: 10)
        for i in 0..<10 { s.upsert(item("a", "a\(i)", TimeInterval(i))); s.upsert(item("b", "b\(i)", TimeInterval(i))) }
        _ = s.items(app: "a")   // one app cached, the other not
        s.capPerApp = 4
        XCTAssertEqual(s.items(app: "a").map(\.id), ["a9", "a8", "a7", "a6"])
        XCTAssertEqual(s.items(app: "b").map(\.id), ["b9", "b8", "b7", "b6"])
        s.upsert(item("a", "a10", 10))
        XCTAssertEqual(s.items(app: "a").count, 4)
        s.capPerApp = 6
        for i in 11..<20 { s.upsert(item("a", "a\(i)", TimeInterval(i))) }
        XCTAssertEqual(s.items(app: "a").count, 6)
        XCTAssertEqual(HistoryStore(directory: dir, cap: 6).counts()["b"]?.total, 4)
    }

    func testReopeningWithASmallerCapTrimsTheDatabase() {
        let s = HistoryStore(directory: dir, cap: 10)
        for i in 0..<10 { s.upsert(item("a", "\(i)", TimeInterval(i))) }
        let small = HistoryStore(directory: dir, cap: 3)
        XCTAssertEqual(small.items(app: "a").map(\.id), ["9", "8", "7"])
    }

    func testCapIsClamped() {
        XCTAssertEqual(HistoryStore(directory: dir, cap: 0).capPerApp, 1)
        XCTAssertEqual(HistoryStore(directory: dir, cap: -5).capPerApp, 1)
        XCTAssertEqual(HistoryStore(directory: dir, cap: Int.max).capPerApp, HistoryStore.maxCap)
        XCTAssertEqual(HistoryStore(directory: dir).capPerApp, HistoryStore.cap)
    }

    func testEvictedImagesAreRemovedAtACustomCap() throws {
        let s = HistoryStore(directory: dir, cap: 2)
        let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 7])
        let path = try XCTUnwrap(s.storeImage(png))
        var first = item("a", "1", 0); first.imagePath = path
        s.upsert(first); s.upsert(item("a", "2", 1))
        XCTAssertTrue(FileManager.default.fileExists(atPath: path))
        s.upsert(item("a", "3", 2))
        XCTAssertFalse(FileManager.default.fileExists(atPath: path))
    }

    // MARK: Robustness

    func testAnUnreadableDatabaseFileIsMovedAsideAndReplaced() throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let db = dir.appendingPathComponent("history.sqlite")
        try Data("this is not a database, just text that is long enough to look like a file".utf8).write(to: db)
        let s = HistoryStore(directory: dir)
        XCTAssertTrue(s.isPersistent)
        s.upsert(item("a", "1"))
        XCTAssertEqual(HistoryStore(directory: dir).items(app: "a").map(\.id), ["1"])
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        XCTAssertTrue(names.contains { $0.hasPrefix("history.sqlite.corrupt-") }, "\(names)")
    }

    func testTwoStoresOnOneDirectoryShareTheData() {
        let a = HistoryStore(directory: dir), b = HistoryStore(directory: dir)
        a.upsert(item("x", "1", 0))
        XCTAssertEqual(b.item(app: "x", id: "1")?.id, "1")
        b.update(app: "x", id: "1") { $0.dismissedAt = Date() }
        XCTAssertEqual(a.unreadCount(), 0)
    }

    func testSurvivesConcurrentWriters() {
        let s = HistoryStore(directory: dir)
        DispatchQueue.concurrentPerform(iterations: 200) { i in
            s.upsert(item("app\(i % 4)", "n\(i)", TimeInterval(i)))
            _ = s.items(app: "app\(i % 4)", limit: 5); _ = s.unreadCount()
        }
        XCTAssertEqual(s.apps(), ["app0", "app1", "app2", "app3"])
        XCTAssertEqual(s.allItems().count, 200)
        XCTAssertEqual(HistoryStore(directory: dir).allItems().count, 200)
    }

    // MARK: Benchmark (target on this machine: 5,000 inserts and a search under 50 ms)

    private func benchItems(_ n: Int, apps: Int) -> [HeraldHistoryItem] {
        (0..<n).map { i in
            let app = "app\(i % apps)"
            let n = HeraldNotification(app: app, id: "n\(i)", title: "Bid \(i) accepted", subtitle: "Acme RFP \(i % 97)",
                                       body: "Your bid for project \(i) was accepted by the buyer, see the details page for the next steps.",
                                       url: "https://x.test/bids/\(i)", sound: "Glass", snooze: true)
            return HeraldHistoryItem(id: "n\(i)", app: app, notification: n, deliveredAt: Date(timeIntervalSince1970: 1_700_000_000 + Double(i)))
        }
    }

    private func milliseconds(_ body: () -> Void) -> Double {
        let t0 = DispatchTime.now().uptimeNanoseconds
        body()
        return Double(DispatchTime.now().uptimeNanoseconds - t0) / 1_000_000
    }

    func testBenchmarkFiveThousandInsertsAndASearch() {
        let items = benchItems(5000, apps: 5)
        let s = HistoryStore(directory: dir)
        var found: [HeraldHistoryItem] = []
        let batch = milliseconds { s.upsert(contentsOf: items) }
        let search = milliseconds { found = s.search("bid 4242 acme") }
        XCTAssertEqual(found.map(\.id), ["n4242"])
        let broad = milliseconds { found = s.search("accepted") }
        XCTAssertEqual(found.count, 5000)

        let dir2 = dir.appendingPathComponent("single")
        let single = HistoryStore(directory: dir2)
        let each = milliseconds { for item in items { single.upsert(item) } }
        XCTAssertEqual(single.allItems().count, 5000)
        print("HISTORY BENCH batch 5000 inserts: \(String(format: "%.1f", batch)) ms; 5000 single upserts (autocommit): \(String(format: "%.1f", each)) ms; "
              + "search (3 tokens, 1 hit) over 5000: \(String(format: "%.2f", search)) ms; search (all 5000 hits): \(String(format: "%.1f", broad)) ms")
        // Loose regression guards (the target is 50 ms; a loaded CI machine gets a 10x margin).
        XCTAssertLessThan(batch, 500); XCTAssertLessThan(each, 2000); XCTAssertLessThan(search, 500)
    }
}
