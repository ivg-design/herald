import XCTest
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
}
