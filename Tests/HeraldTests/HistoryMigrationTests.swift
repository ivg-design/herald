import XCTest
@testable import HeraldCore

/// The one-time import of the per-app JSON history files Herald 1.0/1.1 wrote into `history.sqlite` (#26).
final class HistoryMigrationTests: XCTestCase {
    var dir: URL!
    override func setUp() {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("herald-mig-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    override func tearDown() { try? FileManager.default.removeItem(at: dir) }

    private func item(_ app: String, _ id: String, _ t: TimeInterval = 0, title: String = "t",
                      dismissed: Bool = false) -> HeraldHistoryItem {
        HeraldHistoryItem(id: id, app: app, notification: HeraldNotification(app: app, id: id, title: title),
                          deliveredAt: Date(timeIntervalSince1970: 1_700_000_000 + t),
                          dismissedAt: dismissed ? Date(timeIntervalSince1970: 1_700_000_100 + t) : nil)
    }

    /// The file name 1.1 used for an app (safe characters, plus a hash suffix when the name had to be changed).
    private func legacyName(_ app: String) -> String {
        let safe = String(app.map { $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" || $0 == "_" ? $0 : "_" })
        return (safe == app ? safe : safe + "-abc123") + ".json"
    }

    @discardableResult
    private func writeLegacy(_ app: String, _ items: [HeraldHistoryItem]) throws -> Data {
        let data = try HeraldJSON.encoder().encode(items)
        try data.write(to: dir.appendingPathComponent(legacyName(app)))
        return data
    }

    private func topLevelJSON() -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []).filter { $0.hasSuffix(".json") }.sorted()
    }

    private func backupFolders() -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []).filter { $0.hasPrefix("json-backup-") }.sorted()
    }

    func testFirstLaunchImportsEveryAppFileAndKeepsTheOrder() throws {
        try writeLegacy("bidbot", [item("bidbot", "3", 3), item("bidbot", "2", 2), item("bidbot", "1", 1)])
        try writeLegacy("mail", [item("mail", "b", 5, dismissed: true), item("mail", "a", 4)])
        try writeLegacy("a/b", [item("a/b", "x", 9)])
        let s = HistoryStore(directory: dir)
        XCTAssertEqual(s.apps(), ["a/b", "bidbot", "mail"])
        XCTAssertEqual(s.items(app: "bidbot").map(\.id), ["3", "2", "1"])
        XCTAssertEqual(s.items(app: "mail").map(\.id), ["b", "a"])
        XCTAssertEqual(s.items(app: "a/b").map(\.id), ["x"])
        XCTAssertEqual(s.counts()["mail"], HistoryCount(total: 2, unread: 1))
        XCTAssertEqual(s.unreadCount(), 5)
        XCTAssertEqual(s.allItems().map(\.id), ["x", "b", "a", "3", "2", "1"])
        // The next write goes in front of everything that was imported.
        s.upsert(item("bidbot", "4", 10))
        XCTAssertEqual(s.items(app: "bidbot").map(\.id), ["4", "3", "2", "1"])
    }

    func testReportDescribesTheImport() throws {
        try writeLegacy("a", [item("a", "1"), item("a", "2")])
        try writeLegacy("b", [item("b", "3")])
        let report = try XCTUnwrap(HistoryStore(directory: dir).migration)
        XCTAssertEqual(report.files, 2)
        XCTAssertEqual(report.items, 3)
        XCTAssertEqual(report.apps, 2)
        XCTAssertEqual(report.unreadable, [])
        XCTAssertNotNil(report.backupDirectory)
    }

    func testOriginalsMoveIntoATimestampedBackupByteForByte() throws {
        let aBytes = try writeLegacy("a", [item("a", "1"), item("a", "2")])
        let bBytes = try writeLegacy("a/b", [item("a/b", "3")])
        let s = HistoryStore(directory: dir)
        XCTAssertEqual(topLevelJSON(), [], "no JSON file is left to be imported again")
        let backup = try XCTUnwrap(s.migration?.backupDirectory)
        XCTAssertTrue(backup.lastPathComponent.hasPrefix("json-backup-"))
        XCTAssertEqual(backupFolders(), [backup.lastPathComponent])
        XCTAssertEqual(try Data(contentsOf: backup.appendingPathComponent(legacyName("a"))), aBytes)
        XCTAssertEqual(try Data(contentsOf: backup.appendingPathComponent(legacyName("a/b"))), bBytes)
    }

    func testNothingIsImportedTwice() throws {
        try writeLegacy("a", [item("a", "1"), item("a", "2")])
        let first = HistoryStore(directory: dir)
        XCTAssertNotNil(first.migration)
        first.update(app: "a", id: "1") { $0.dismissedAt = Date() }
        first.delete(app: "a", id: "2")
        let second = HistoryStore(directory: dir)
        XCTAssertNil(second.migration, "the files are gone, there is nothing to migrate")
        XCTAssertEqual(second.items(app: "a").map(\.id), ["1"])
        XCTAssertEqual(second.unreadCount(), 0)
        XCTAssertEqual(backupFolders().count, 1)
    }

    func testAnUnreadableFileIsKeptInTheBackupAndTheRestStillImports() throws {
        try writeLegacy("good", [item("good", "1")])
        let junk = Data("{ this is not history".utf8)
        try junk.write(to: dir.appendingPathComponent("broken.json"))
        let s = HistoryStore(directory: dir)
        XCTAssertEqual(s.items(app: "good").map(\.id), ["1"])
        XCTAssertEqual(s.apps(), ["good"])
        let report = try XCTUnwrap(s.migration)
        XCTAssertEqual(report.files, 1)
        XCTAssertEqual(report.unreadable, ["broken.json"])
        let backup = try XCTUnwrap(report.backupDirectory)
        XCTAssertEqual(try Data(contentsOf: backup.appendingPathComponent("broken.json")), junk)
        XCTAssertEqual(topLevelJSON(), [])
    }

    func testEveryFieldOfAnImportedRecordIsKept() throws {
        var n = HeraldNotification(app: "a", id: "1", title: "Bid accepted", subtitle: "Acme", body: "See [x](https://x.test)",
                                   url: "https://x.test", sound: "Glass", snooze: true)
        n.buttons = [HeraldButton(label: "Open", url: "https://x.test/o")]
        var rich = HeraldHistoryItem(id: "1", app: "a", notification: n, deliveredAt: Date(timeIntervalSince1970: 1_700_000_000.25),
                                     dismissedAt: Date(timeIntervalSince1970: 1_700_000_500), actionUsed: "Open",
                                     snoozedUntil: Date(timeIntervalSince1970: 1_700_009_000), imagePath: "/nowhere/img.png",
                                     fields: ["amount": .number(3), "who": .text("Acme")])
        rich.speech = HeraldSpeech(text: "Bid accepted", voice: "af_heart", audioPath: "/tmp/a.wav", durationSeconds: 2)
        try writeLegacy("a", [rich])
        let back = try XCTUnwrap(HistoryStore(directory: dir).item(app: "a", id: "1"))
        XCTAssertEqual(back.notification, rich.notification)
        XCTAssertEqual(back.fields, rich.fields)
        XCTAssertEqual(back.speech, rich.speech)
        XCTAssertEqual(back.actionUsed, "Open")
        XCTAssertEqual(back.imagePath, "/nowhere/img.png")
        XCTAssertEqual(back.deliveredAt.timeIntervalSince1970, 1_700_000_000.25, accuracy: 0.001)
        XCTAssertEqual(back.snoozedUntil?.timeIntervalSince1970 ?? 0, 1_700_009_000, accuracy: 0.001)
        // The queried columns were filled from the record, not just the payload.
        let s = HistoryStore(directory: dir)
        XCTAssertEqual(s.unreadCount(), 0)
        XCTAssertEqual(s.snoozed().count, 0, "dismissed, so no longer snoozed")
    }

    func testRecordsFromBeforeTheNewerFieldsStillImport() throws {
        // What 1.0 wrote: no `fields`, no `speech`, no actionIds.
        let legacy = #"""
        [{"app":"a","deliveredAt":"2026-09-01T10:00:00.000Z","id":"1",
          "notification":{"app":"a","id":"1","title":"Old one","persistent":true}}]
        """#
        try Data(legacy.utf8).write(to: dir.appendingPathComponent("a.json"))
        let s = HistoryStore(directory: dir)
        XCTAssertEqual(s.item(app: "a", id: "1")?.notification.title, "Old one")
        XCTAssertNil(s.item(app: "a", id: "1")?.fields)
        XCTAssertEqual(s.search("old").map(\.id), ["1"])
    }

    func testTheCapAppliesToImportedHistory() throws {
        try writeLegacy("a", (0..<8).reversed().map { item("a", "\($0)", TimeInterval($0)) })
        let s = HistoryStore(directory: dir, cap: 3)
        XCTAssertEqual(s.items(app: "a").map(\.id), ["7", "6", "5"])
        XCTAssertEqual(s.migration?.items, 8)
        XCTAssertEqual(HistoryStore(directory: dir, cap: 3).counts()["a"]?.total, 3)
    }

    func testAFileHoldingSeveralAppsAndDuplicateIdsIsGroupedByTheItemsOwnApp() throws {
        try writeLegacy("mixed", [item("a", "1", 3), item("b", "9", 2), item("a", "1", 1), item("a", "0", 0)])
        let s = HistoryStore(directory: dir)
        XCTAssertEqual(s.apps(), ["a", "b"])
        XCTAssertEqual(s.items(app: "a").map(\.id), ["1", "0"], "the first (newest) copy of a duplicate wins")
        XCTAssertEqual(s.migration?.items, 3)
    }

    func testStrayJSONAfterAMigrationIsMergedWithoutDuplicates() throws {
        try writeLegacy("a", [item("a", "2", 2), item("a", "1", 1)])
        _ = HistoryStore(directory: dir)
        // A 1.1 build run again afterwards and wrote its own file for the same app.
        try writeLegacy("a", [item("a", "3", 3, title: "newer"), item("a", "2", 2, title: "from the old file")])
        let s = HistoryStore(directory: dir)
        XCTAssertEqual(s.migration?.files, 1)
        XCTAssertEqual(Set(s.items(app: "a").map(\.id)), ["1", "2", "3"])
        XCTAssertEqual(s.items(app: "a").count, 3)
        XCTAssertEqual(s.item(app: "a", id: "2")?.notification.title, "t", "an item the database has is not overwritten")
        XCTAssertEqual(backupFolders().count, 2)
    }

    func testAnEmptyOrNonHistoryDirectoryNeedsNoMigration() throws {
        XCTAssertNil(HistoryStore(directory: dir).migration)
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("audio"), withIntermediateDirectories: true)
        try Data("x".utf8).write(to: dir.appendingPathComponent("audio/clip.json"))   // not at the top level
        XCTAssertNil(HistoryStore(directory: dir).migration)
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("audio/clip.json").path))
        XCTAssertEqual(backupFolders(), [])
    }

    func testCachedImagesAreLeftAloneByTheImport() async throws {
        let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 4, 5])
        let first = HistoryStore(directory: dir)
        let path = try XCTUnwrap(first.storeImage(png))
        var withImage = item("a", "1"); withImage.imagePath = path
        try writeLegacy("a", [withImage])
        let s = HistoryStore(directory: dir)
        XCTAssertEqual(s.item(app: "a", id: "1")?.imagePath, path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: path))
        s.delete(app: "a", id: "1")
        XCTAssertFalse(FileManager.default.fileExists(atPath: path), "deleting the last reference still frees the image")
    }

    func testWhenTheDatabaseCannotBeOpenedHistoryStaysInMemoryAndTheFilesStay() throws {
        try writeLegacy("a", [item("a", "1")])
        // A directory where the database file should be: SQLite cannot open it.
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("history.sqlite"), withIntermediateDirectories: true)
        let s = HistoryStore(directory: dir)
        XCTAssertFalse(s.isPersistent)
        XCTAssertEqual(s.items(app: "a").map(\.id), ["1"], "still readable this run")
        s.upsert(item("a", "2", 1))
        XCTAssertEqual(s.items(app: "a").map(\.id), ["2", "1"])
        XCTAssertEqual(topLevelJSON(), [legacyName("a")], "the only copy on disk is not moved")
        XCTAssertNil(s.migration?.backupDirectory)
    }

    func testALargeHistoryImportsQuickly() throws {
        for a in 0..<10 {
            let app = "app\(a)"
            try writeLegacy(app, (0..<1000).reversed().map { item(app, "n\($0)", TimeInterval($0)) })
        }
        let t0 = DispatchTime.now().uptimeNanoseconds
        let s = HistoryStore(directory: dir)
        let ms = Double(DispatchTime.now().uptimeNanoseconds - t0) / 1_000_000
        print("HISTORY MIGRATION 10 files x 1000 items imported in \(String(format: "%.0f", ms)) ms")
        XCTAssertEqual(s.migration?.items, 10_000)
        XCTAssertEqual(s.counts().values.map(\.total), Array(repeating: 1000, count: 10))
        XCTAssertLessThan(ms, 5000)
    }
}
