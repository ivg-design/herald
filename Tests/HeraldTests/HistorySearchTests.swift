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

    // MARK: SQL search (#26)

    private func sqlStore(_ items: [HeraldHistoryItem], cap: Int = HistoryStore.cap) -> (HistoryStore, URL) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("herald-sq-\(UUID().uuidString)")
        let s = HistoryStore(directory: dir, cap: cap)
        s.upsert(contentsOf: items)
        return (s, dir)
    }

    private var corpus: [HeraldHistoryItem] {
        [item("bidbot", "1", 10, title: "Bid accepted", subtitle: "Acme RFP"),
         item("bidbot", "2", 9, title: "Bid lost", subtitle: "Globex"),
         item("mail", "3", 8, title: "Hi", subtitle: "From Acme"),
         item("mail", "4", 7, title: "Hi", body: "see [report](https://x.test)"),
         item("com.x.bidbot", "5", 6, title: "Hello"),
         item("cafe", "6", 5, title: "Caf\u{00E9} order ready", dismissed: true),
         item("cafe", "7", 4, title: "Discount 100% off", body: "code a_b and back\\slash"),
         item("cafe", "8", 3, title: "Discount 1000 off", body: "codeaxb"),
         item("misc", "9", 2, title: "\u{00DC}ber alles", subtitle: "Stra\u{00DF}e"),
         item("misc", "10", 1, title: "Z\u{00FC}rich", body: "ZÜRICH Airport")]
    }

    /// The SQL path and the in-memory path are two implementations of one rule: they must agree.
    func testSQLSearchAgreesWithTheInMemoryFilterOnEveryQuery() {
        let items = corpus
        let (s, dir) = sqlStore(items); defer { try? FileManager.default.removeItem(at: dir) }
        let names: (String) -> String? = { $0 == "com.x.bidbot" ? "BidBot Pro" : nil }
        let queries = ["", "   ", "accepted", "ACME", "bid acme", "bid nothing", "cafe", "CAF\u{00C9}", "report", "mail", "pro hello",
                       "bidbot", "100%", "1000", "a_b", "axb", "back\\slash", "%", "_", "uber", "\u{00FC}ber", "zurich", "ZURICH airport",
                       "strasse", "x.test", "https", "hi acme", "  bid   lost  "]
        for q in queries {
            let expected = HistorySearch.filter(HistorySearch.scoped(items, app: nil), query: q, appName: names).map(\.id)
            XCTAssertEqual(s.search(q, appName: names).map(\.id), expected, "query \"\(q)\"")
        }
    }

    func testSQLSearchTreatsLikeWildcardsAsPlainCharacters() {
        let (s, dir) = sqlStore(corpus); defer { try? FileManager.default.removeItem(at: dir) }
        XCTAssertEqual(s.search("100%").map(\.id), ["7"], "a percent sign is not a wildcard")
        XCTAssertEqual(s.search("a_b").map(\.id), ["7"], "an underscore is not a single-character wildcard")
        XCTAssertEqual(s.search("back\\slash").map(\.id), ["7"])
        XCTAssertTrue(s.search("zz%zz").isEmpty)
    }

    func testSQLSearchScopesToAnAppAndHonoursTheLimit() {
        let (s, dir) = sqlStore(corpus); defer { try? FileManager.default.removeItem(at: dir) }
        XCTAssertEqual(s.search("hi", app: "mail").map(\.id), ["3", "4"])
        XCTAssertEqual(s.search("hi", app: "bidbot").map(\.id), [])
        XCTAssertEqual(s.search("bid", limit: 1).map(\.id), ["1"], "newest first, then cut")
        XCTAssertEqual(s.search("bid", limit: 0).map(\.id), [])
        XCTAssertEqual(s.search("", app: "cafe").map(\.id), ["8", "7", "6"])
        XCTAssertEqual(s.search("   ", limit: 2).map(\.id), ["1", "2"])
        XCTAssertTrue(s.search("bid", app: "no-such-app").isEmpty)
    }

    func testSQLSearchResultsAreNewestDeliveryFirstEvenWhenInsertedOutOfOrder() {
        let (s, dir) = sqlStore([item("a", "old", 1, title: "match"), item("a", "new", 5, title: "match"), item("b", "mid", 3, title: "match")])
        defer { try? FileManager.default.removeItem(at: dir) }
        XCTAssertEqual(s.search("match").map(\.id), ["new", "mid", "old"])
    }

    func testSQLSearchFollowsEditsDeletesAndReopening() {
        let (s, dir) = sqlStore(corpus); defer { try? FileManager.default.removeItem(at: dir) }
        s.update(app: "bidbot", id: "2") { $0.notification.title = "Bid reopened" }
        XCTAssertEqual(s.search("reopened").map(\.id), ["2"])
        XCTAssertTrue(s.search("lost").isEmpty, "the search text was rewritten with the record")
        s.delete(app: "bidbot", id: "2")
        XCTAssertTrue(s.search("reopened").isEmpty)
        s.clear(app: "mail")
        XCTAssertTrue(s.search("acme", app: "mail").isEmpty)
        XCTAssertEqual(HistoryStore(directory: dir).search("acme").map(\.id), ["1"])
    }

    func testSQLSearchUsesTheDisplayNameOfTheAppOnlyWhenGiven() {
        let (s, dir) = sqlStore([item("com.x.bidbot", "1", 1, title: "Hello"), item("other", "2", 2, title: "Hello")])
        defer { try? FileManager.default.removeItem(at: dir) }
        XCTAssertTrue(s.search("pro hello").isEmpty)
        XCTAssertEqual(s.search("pro hello") { $0 == "com.x.bidbot" ? "BidBot Pro" : nil }.map(\.id), ["1"])
        XCTAssertEqual(s.search("hello").map(\.id), ["2", "1"])
    }

    func testSQLSearchIsFastOverALargeHistory() {
        let many = (0..<5000).map { i in item("app\(i % 5)", "n\(i)", TimeInterval(i), title: "Bid \(i) accepted", subtitle: "Acme RFP \(i % 97)") }
        let (s, dir) = sqlStore(many); defer { try? FileManager.default.removeItem(at: dir) }
        let t0 = DispatchTime.now().uptimeNanoseconds
        let hit = s.search("bid 4242 acme")
        let ms = Double(DispatchTime.now().uptimeNanoseconds - t0) / 1_000_000
        XCTAssertEqual(hit.map(\.id), ["n4242"])
        XCTAssertLessThan(ms, 500, "search over 5000 items took \(ms) ms")
    }

    func testStoreExportJSONRoundTripsAndFollowsTheScope() throws {
        let (s, dir) = sqlStore(corpus); defer { try? FileManager.default.removeItem(at: dir) }
        let all = try HeraldJSON.decoder().decode([HeraldHistoryItem].self, from: s.exportJSON())
        XCTAssertEqual(all.map(\.id), s.allItems().map(\.id))
        XCTAssertEqual(all.count, 10)
        let one = try s.exportJSON(app: "cafe")
        XCTAssertTrue(String(decoding: one, as: UTF8.self).contains("\n"))
        let back = try HeraldJSON.decoder().decode([HeraldHistoryItem].self, from: one)
        XCTAssertEqual(back, s.items(app: "cafe"))
        XCTAssertEqual(Set(back.map(\.id)), ["6", "7", "8"])
    }

    func testFoldIsCaseAndDiacriticInsensitive() {
        XCTAssertEqual(HistorySearch.fold("Caf\u{00E9}"), "cafe")
        XCTAssertEqual(HistorySearch.fold("CAFE"), "cafe")
        XCTAssertEqual(HistorySearch.fold("plain ascii"), "plain ascii")
        XCTAssertEqual(HistorySearch.fold("Z\u{00DC}RICH"), HistorySearch.fold("zurich"))
    }
}
