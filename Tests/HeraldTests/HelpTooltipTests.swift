import XCTest
@testable import HeraldCore

/// Tooltips on every control (issue #53): the catalog is complete and the two levels format as specified.
final class HelpTooltipTests: XCTestCase {
    func testEveryCatalogEntryHasANameAndADetail() {
        XCTAssertFalse(HeraldHelpCatalog.all.isEmpty)
        for e in HeraldHelpCatalog.all {
            XCTAssertFalse(e.name.trimmingCharacters(in: .whitespaces).isEmpty, "\(e.id) has no name")
            XCTAssertFalse(e.detail.trimmingCharacters(in: .whitespaces).isEmpty, "\(e.id) has no detail")
            XCTAssertFalse(e.name.hasSuffix("."), "\(e.id): names carry no full stop")
        }
    }

    func testCatalogIdsAreUnique() {
        let ids = HeraldHelpCatalog.all.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count, "duplicate ids: \(Dictionary(grouping: ids, by: { $0 }).filter { $1.count > 1 }.keys.sorted())")
    }

    func testNameOnlyShowsJustTheName() {
        XCTAssertEqual(HeraldHelpFormat.text(name: "Merge cells", detail: "join the selected cells into one slot", shortcut: "\u{2318}E", level: .nameOnly), "Merge cells")
    }

    func testFullLevelShowsNameDescriptionAndShortcut() {
        XCTAssertEqual(HeraldHelpFormat.text(name: "Merge cells", detail: "join the selected cells into one slot", shortcut: "\u{2318}E", level: .nameAndDescription),
                       "Merge cells \u{2014} join the selected cells into one slot \u{00B7} \u{2318}E")
        XCTAssertEqual(HeraldHelpFormat.text(name: "Apply", detail: "use the port", shortcut: nil, level: .nameAndDescription), "Apply \u{2014} use the port")
    }

    func testDefaultIsNameAndDescriptionAndBothLevelsAreOffered() {
        XCTAssertEqual(TooltipLevel.defaultLevel, .nameAndDescription)
        XCTAssertEqual(TooltipLevel.allCases.map(\.title), ["Name only", "Name and description"])
    }
}
