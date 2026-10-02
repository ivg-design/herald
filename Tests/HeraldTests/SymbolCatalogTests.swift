import XCTest
@testable import HeraldCore

final class SymbolCatalogTests: XCTestCase {
    private func folder() throws -> URL {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("herald-glyphs-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        let avail: [String: Any] = ["symbols": ["bell": "2019", "bell.fill": "2019", "bell.badge": "2019", "bell.ar": "2022",
                                                "star": "2019", "wifi": "2019", "envelope": "2019"], "year_to_release": [:]]
        try PropertyListSerialization.data(fromPropertyList: avail, format: .xml, options: 0).write(to: d.appendingPathComponent("name_availability.plist"))
        let search: [String: [String]] = ["bell": ["notification", "alarm"], "envelope": ["mail", "email"], "star": ["favorite"]]
        try PropertyListSerialization.data(fromPropertyList: search, format: .xml, options: 0).write(to: d.appendingPathComponent("symbol_search.plist"))
        return d
    }

    func testLoadsNamesWithoutLocaleVariants() throws {
        let c = try XCTUnwrap(SymbolCatalog.load(from: folder()))
        XCTAssertEqual(c.names, ["bell", "bell.badge", "bell.fill", "envelope", "star", "wifi"])
        XCTAssertNil(SymbolCatalog.load(from: URL(fileURLWithPath: "/nonexistent")))
    }

    func testSearchByNameWordsAndTerms() throws {
        let c = try XCTUnwrap(SymbolCatalog.load(from: folder()))
        XCTAssertEqual(c.search("bell"), ["bell", "bell.badge", "bell.fill"])
        XCTAssertEqual(c.search("bell fill"), ["bell.fill"])
        XCTAssertEqual(c.search("mail"), ["envelope"], "found through a search term")
        XCTAssertEqual(c.search("notification"), ["bell", "bell.badge", "bell.fill"], "a term, plus the synonym bell")
        XCTAssertEqual(c.search("zzz"), [])
        XCTAssertEqual(c.search("").count, 6)
        XCTAssertEqual(c.search("", limit: 2).count, 2)
        XCTAssertEqual(c.search("wif"), ["wifi"])
    }

    func testTheRealSystemCatalogHasTheBasics() throws {
        guard let c = SymbolCatalog.load() else { throw XCTSkip("no CoreGlyphs bundle on this machine") }
        XCTAssertTrue(c.contains("bell.badge"))
        XCTAssertTrue(c.search("wifi").contains("wifi"))
        XCTAssertGreaterThan(c.names.count, 1000)
    }

    func testTheRealCatalogHasThousandsOfSymbolsWithApplesCategories() throws {
        guard let c = SymbolCatalog.load() else { throw XCTSkip("no CoreGlyphs bundle on this machine") }
        XCTAssertGreaterThanOrEqual(c.names.count, 5000)
        let titles = Set(c.categories.map(\.title))
        for want in ["Communication", "Weather", "Objects & Tools", "Devices", "Gaming", "Connectivity", "Transportation", "Automotive", "Accessibility", "Privacy & Security", "Human", "Home", "Fitness", "Nature", "Editing", "Text Formatting", "Media", "Keyboard", "Commerce", "Time", "Health", "Shapes", "Arrows", "Indices", "Math"] {
            XCTAssertTrue(titles.contains(want), want)
        }
        XCTAssertFalse(c.categories.contains { $0.key == "all" })
        XCTAssertTrue(c.names(in: "weather").contains("cloud.rain"))
        XCTAssertFalse(c.categoryKeys(of: "trash").isEmpty)
        XCTAssertGreaterThan(c.names(in: "communication").count, 50)
    }

    func testSearchFindsTrashForBinAndKnowsAppleKeywords() throws {
        guard let c = SymbolCatalog.load() else { throw XCTSkip("no CoreGlyphs bundle on this machine") }
        XCTAssertTrue(c.search("bin").contains("trash"), "everyday synonym")
        XCTAssertTrue(c.search("mail").contains("envelope"), "Apple's own keyword")
        XCTAssertTrue(c.search("bin", category: "objectsandtools").allSatisfy { c.names(in: "objectsandtools").contains($0) })
        XCTAssertGreaterThan(c.search("", limit: .max).count, 5000, "an unlimited empty search lists everything")
    }

    func testCatalogCacheRoundTripsAndInvalidates() throws {
        let d = try folder()
        let cache = d.appendingPathComponent("cache.json")
        let first = try XCTUnwrap(SymbolCatalog.load(from: d, cache: cache))
        XCTAssertTrue(FileManager.default.fileExists(atPath: cache.path))
        // Remove the source: a current cache still serves, proving it was read rather than reparsed.
        let again = try XCTUnwrap(SymbolCatalog.load(from: d, cache: cache))
        XCTAssertEqual(again.names, first.names)
        XCTAssertEqual(again.search("mail"), ["envelope"])
        try Data("{}".utf8).write(to: cache)
        XCTAssertEqual(SymbolCatalog.load(from: d, cache: cache)?.names, first.names, "a corrupt cache is reparsed")
    }

    func testFavouritesAndRecentsPersistAcrossInstances() {
        let suite = "herald-sym-\(UUID().uuidString)"
        let a = SymbolShortlist(defaults: UserDefaults(suiteName: suite)!)
        a.toggleFavorite("star"); a.noteUsed("bell")
        let b = SymbolShortlist(defaults: UserDefaults(suiteName: suite)!)
        XCTAssertEqual(b.favorites, ["star"])
        XCTAssertEqual(b.recents, ["bell"])
    }

    func testRecentsAndFavourites() {
        let d = UserDefaults(suiteName: "herald-sym-\(UUID().uuidString)")!
        let s = SymbolShortlist(defaults: d)
        for i in 0..<60 { s.noteUsed("s\(i)") }
        s.noteUsed("s5")
        XCTAssertEqual(s.recents.first, "s5")
        XCTAssertEqual(s.recents.count, SymbolShortlist.maxRecents)
        XCTAssertEqual(s.recents.filter { $0 == "s5" }.count, 1)
        s.noteUsed("{token}"); XCTAssertFalse(s.recents.contains("{token}"))
        s.toggleFavorite("star"); XCTAssertTrue(s.isFavorite("star"))
        s.toggleFavorite("star"); XCTAssertFalse(s.isFavorite("star"))
    }
}
