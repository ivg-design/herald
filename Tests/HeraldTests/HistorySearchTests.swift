import XCTest
@testable import HeraldCore

final class HistorySearchTests: XCTestCase {
    private func item(_ app: String, _ id: String, _ t: TimeInterval, title: String = "t",
                      subtitle: String? = nil, body: String? = nil, dismissed: Bool = false) -> HeraldHistoryItem {
        HeraldHistoryItem(id: id, app: app,
                          notification: HeraldNotification(app: app, id: id, title: title, subtitle: subtitle, body: body),
                          deliveredAt: Date(timeIntervalSince1970: 1_700_000_000 + t),
                          dismissedAt: dismissed ? Date(timeIntervalSince1970: 1_700_000_100 + t) : nil)
    }

    func testEmptyQueryKeepsEverythingInOrder() {
        let items = [item("a", "1", 2), item("a", "2", 1)]
        XCTAssertEqual(HistorySearch.filter(items, query: "   ").map(\.id), ["1", "2"])
    }

    func testMatchesTitleSubtitleBodyAndApp() {
        let items = [item("bidbot", "1", 3, title: "Bid accepted"),
                     item("mail", "2", 2, title: "Hi", subtitle: "From Acme"),
                     item("mail", "3", 1, title: "Hi", body: "see [report](https://x.test)")]
        XCTAssertEqual(HistorySearch.filter(items, query: "accepted").map(\.id), ["1"])
        XCTAssertEqual(HistorySearch.filter(items, query: "acme").map(\.id), ["2"])
        XCTAssertEqual(HistorySearch.filter(items, query: "REPORT").map(\.id), ["3"])
        XCTAssertEqual(HistorySearch.filter(items, query: "mail").map(\.id), ["2", "3"])
    }

    func testTokensAreAndedAcrossFields() {
        let items = [item("bidbot", "1", 2, title: "Bid won", subtitle: "Acme RFP"),
                     item("bidbot", "2", 1, title: "Bid lost", subtitle: "Globex")]
        XCTAssertEqual(HistorySearch.filter(items, query: "bid acme").map(\.id), ["1"])
        XCTAssertTrue(HistorySearch.filter(items, query: "bid nothing").isEmpty)
    }

    func testDiacriticAndCaseInsensitive() {
        let items = [item("a", "1", 0, title: "Caf\u{00E9} order ready")]
        XCTAssertEqual(HistorySearch.filter(items, query: "cafe").count, 1)
        XCTAssertEqual(HistorySearch.filter(items, query: "CAF\u{00C9}").count, 1)
    }

    func testDisplayNameIsSearchable() {
        let items = [item("com.x.bidbot", "1", 0, title: "Hello")]
        XCTAssertTrue(HistorySearch.filter(items, query: "BidBot Pro").isEmpty)
        let hit = HistorySearch.filter(items, query: "pro hello") { $0 == "com.x.bidbot" ? "BidBot Pro" : nil }
        XCTAssertEqual(hit.count, 1)
    }

    func testScopedFiltersByAppAndSortsNewestFirst() {
        let items = [item("a", "1", 1), item("b", "2", 5), item("a", "3", 9)]
        XCTAssertEqual(HistorySearch.scoped(items, app: nil).map(\.id), ["3", "2", "1"])
        XCTAssertEqual(HistorySearch.scoped(items, app: "a").map(\.id), ["3", "1"])
        XCTAssertTrue(HistorySearch.scoped(items, app: "zzz").isEmpty)
    }

    func testStoreCountsAndBulkDelete() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("herald-hs-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let s = HistoryStore(directory: dir)
        s.upsert(item("a", "1", 0)); s.upsert(item("a", "2", 1, dismissed: true)); s.upsert(item("b", "3", 2))
        XCTAssertEqual(s.counts(), ["a": HistoryCount(total: 2, unread: 1), "b": HistoryCount(total: 1, unread: 1)])
        s.delete(app: "a", ids: ["1", "2"])
        XCTAssertTrue(s.items(app: "a").isEmpty)
        XCTAssertEqual(s.items(app: "b").map(\.id), ["3"])
        s.delete(app: "b", ids: [])
        XCTAssertEqual(s.items(app: "b").count, 1)
    }

    func testExportJSONRoundTrips() throws {
        let items = [item("a", "1", 1, title: "One", body: "b"), item("a", "2", 0, title: "Two")]
        let data = try HistorySearch.exportJSON(items)
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains("\n"))
        let back = try HeraldJSON.decoder().decode([HeraldHistoryItem].self, from: data)
        XCTAssertEqual(back, items)
    }
}
