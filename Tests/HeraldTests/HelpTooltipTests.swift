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

    // MARK: Names and explanations, never click instructions

    func testNoDetailIsAnInteractionInstruction() {
        let banned = try! NSRegularExpression(pattern: #"\b(drag\w*|click\w*|tap\w*|press\w*|select|double-click|shift-click)\b"#, options: [.caseInsensitive])
        for e in HeraldHelpCatalog.all {
            let range = NSRange(e.detail.startIndex..., in: e.detail)
            XCTAssertNil(banned.firstMatch(in: e.detail, range: range), "\(e.id) explains how to click, not what it is: \(e.detail)")
        }
    }

    func testNoTwoEntriesShareADetail() {
        let groups = Dictionary(grouping: HeraldHelpCatalog.all, by: { $0.detail.lowercased() }).filter { $1.count > 1 }
        XCTAssertTrue(groups.isEmpty, "shared details: \(groups.mapValues { $0.map(\.id) })")
    }

    func testEveryDetailIsASentenceOfSixToOneHundredFortyCharacters() {
        for e in HeraldHelpCatalog.all {
            XCTAssertTrue((6...140).contains(e.detail.count), "\(e.id): \(e.detail.count) characters")
            XCTAssertTrue(e.detail.first?.isUppercase == true || e.detail.first == "." , "\(e.id) should start with a capital: \(e.detail)")
            XCTAssertFalse(e.detail.hasSuffix("."), "\(e.id): details carry no full stop")
        }
    }

    func testEveryPaletteComponentExplainsWhatItRenders() {
        let renders: [String: String] = [
            "text": "text", "image": "picture", "issuerIcon": "icon", "timestamp": "time", "button": "button", "actions": "buttons",
            "iconButton": "symbol", "badge": "capsule", "stackBadge": "count", "progress": "bar", "rive": "rive", "spacer": "space",
        ]
        for c in DesignerPalette.components {
            guard let e = HeraldHelpCatalog.component(c.type) else { return XCTFail("no catalog entry for palette component \(c.type)") }
            XCTAssertNotNil(renders[c.type], "add what \(c.type) renders to this test")
            XCTAssertTrue(e.detail.lowercased().contains(renders[c.type] ?? "\u{0}"), "\(c.type): \(e.detail)")
            XCTAssertFalse(e.name.lowercased().hasPrefix("drag"), c.type)
        }
        XCTAssertEqual(HeraldHelpCatalog.component("badge")?.detail, "A small capsule showing a short status or count, such as {status} or {count}")
    }

    // MARK: Version label

    func testVersionLabelFormatsVersionAndBuild() {
        XCTAssertEqual(HeraldVersionLabel.text(version: "1.4.1", build: "8"), "Herald 1.4.1 (Build 8)")
        XCTAssertEqual(HeraldVersionLabel.text(version: "1.4.1", build: nil), "Herald 1.4.1")
        XCTAssertEqual(HeraldVersionLabel.text(version: nil, build: "8"), "Herald (Build 8)")
        XCTAssertEqual(HeraldVersionLabel.text(version: " ", build: ""), "Herald")
        XCTAssertEqual(HeraldHelpCatalog.entry("settings.appVersion")?.name, "Version")
    }
}
