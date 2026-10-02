import XCTest
import HeraldClient
@testable import HeraldCore

/// Issue #58: arbitrary button arrangements. An `actions` cell lists the actions it is told to (`include`), aligns
/// and spaces them, a `button` binds one action by id (`actionId`), and an action is drawn in at most one cell.
final class ActionArrangementTests: XCTestCase {
    private func template(_ json: String) throws -> HeraldTemplate {
        try HeraldJSON.decoder().decode(HeraldTemplate.self, from: Data(json.utf8))
    }

    /// The WebWatcher email preset's four actions, as the resolved list a notification offers.
    private let resolved: [HeraldResolvedAction] = ["markRead", "archive", "delete", "spam"].map {
        HeraldResolvedAction(action: HeraldAction(id: $0, label: $0.capitalized, kind: .callback), origin: .issuer)
    }

    private func ids(_ list: [HeraldResolvedAction]?) -> [String]? { list?.map(\.action.id) }

    /// The layout the user asked for: the icon in column 1 rows 1-3, a button for markRead in column 1 row 4, and
    /// archive, delete and spam right-aligned in one merged cell spanning columns 2-4 of row 4.
    static let requested = """
    {"name":"email-split","app":"webwatcher.email","layoutVersion":2,"collapseEmpty":true,
     "grid":{"rows":4,"cols":4,"rowSizes":["auto","auto","auto","auto"],"colSizes":["72","fill","fill","fill"],"gap":8,"padding":14,"width":400},
     "cells":[
      {"id":"icon","row":0,"col":0,"rowSpan":3,"component":{"type":"issuerIcon","size":56,"shape":"rounded"}},
      {"id":"title","row":0,"col":1,"colSpan":3,"component":{"type":"text","binding":"{title}","style":"title","maxLines":1}},
      {"id":"sender","row":1,"col":1,"colSpan":3,"component":{"type":"text","binding":"{sender}","style":"subtitle","maxLines":1}},
      {"id":"subject","row":2,"col":1,"colSpan":3,"component":{"type":"text","binding":"{subject}","style":"caption","maxLines":1}},
      {"id":"read","row":3,"col":0,"component":{"type":"button","actionId":"markRead"}},
      {"id":"more","row":3,"col":1,"colSpan":3,"component":{"type":"actions","include":["archive","delete","spam"],"align":"trailing","wrap":false,"spacing":6}}]}
    """

    // MARK: Decoding

    func testNewKeysDecodeAndRoundTrip() throws {
        let t = try template(Self.requested)
        guard case .actions(let a) = t.cells.last!.component else { return XCTFail("actions cell") }
        XCTAssertEqual(a.include, ["archive", "delete", "spam"])
        XCTAssertEqual(a.align, .trailing)
        XCTAssertEqual(a.wrap, false)
        XCTAssertEqual(a.spacing, 6)
        XCTAssertFalse(a.wraps, "wrap: false keeps one line even for the default `wrap` layout")
        guard case .button(let b) = t.cells.first(where: { $0.id == "read" })!.component else { return XCTFail("button cell") }
        XCTAssertEqual(b.actionRef, "markRead", "actionId is another spelling of actionRef")
        let again = try HeraldJSON.decoder().decode(HeraldTemplate.self, from: try HeraldJSON.encoder().encode(t))
        XCTAssertEqual(again, t)
    }

    func testDefaultsKeepTheOldRowBehaviour() throws {
        let a = try HeraldJSON.decoder().decode(HeraldComponent.self, from: Data(#"{"type":"actions"}"#.utf8))
        guard case .actions(let c) = a else { return XCTFail() }
        XCTAssertEqual(c.includedIDs, [])
        XCTAssertEqual(c.effectiveAlign, .leading)
        XCTAssertEqual(c.effectiveSpacing, 6)
        XCTAssertTrue(c.wraps, "layout defaults to wrap")
        XCTAssertFalse(HeraldActionsComponent(layout: .row).wraps)
        XCTAssertTrue(HeraldActionsComponent(layout: .row, wrap: true).wraps)
        XCTAssertFalse(HeraldActionsComponent(layout: .stack, wrap: true).wraps, "stack is one per line")
    }

    // MARK: Which cell shows which action

    func testTheRequestedLayoutValidatesAndSplitsTheFourActions() throws {
        let t = try template(Self.requested)
        let issues = t.validate()
        XCTAssertEqual(issues.filter { $0.isError }.map(\.message), [], "no errors")
        XCTAssertEqual(issues.map(\.message), [], "and no warnings: nothing is claimed twice")

        let assignment = t.actionAssignment(actions: resolved)
        XCTAssertEqual(ids(assignment.actions(forCell: "read")), ["markRead"])
        XCTAssertEqual(ids(assignment.actions(forCell: "more")), ["archive", "delete", "spam"], "in the order of include")
        XCTAssertNil(assignment.actions(forCell: "title"))
        XCTAssertTrue(assignment.contested.isEmpty)
        XCTAssertEqual(t.emptyCellIDs(fields: ["title": .text("t"), "sender": .text("s"), "subject": .text("x")], actions: resolved), [])
    }

    func testIncludeOrderIsTheOrderShown() throws {
        var t = try template(Self.requested)
        t.cells[5].component = .actions(HeraldActionsComponent(include: ["spam", "archive", "markRead"]))
        XCTAssertEqual(ids(t.actionAssignment(actions: resolved).actions(forCell: "more")), ["spam", "archive"],
                       "markRead is the button's: the first cell in reading order keeps it")
    }

    func testAnActionsCellWithNoIncludeTakesWhatIsLeft() throws {
        var t = try template(Self.requested)
        t.cells[5].component = .actions(HeraldActionsComponent(source: .merged, layout: .wrap))
        let a = t.actionAssignment(actions: resolved)
        XCTAssertEqual(ids(a.actions(forCell: "read")), ["markRead"])
        XCTAssertEqual(ids(a.actions(forCell: "more")), ["archive", "delete", "spam"], "everything the button did not take")
    }

    func testAnActionIsDrawnInOneCellAndValidationWarnsAboutTheOther() throws {
        var t = try template(Self.requested)
        t.cells.append(HeraldCell(id: "again", row: 3, col: 3, component: .button(HeraldButtonComponent(actionRef: "archive"))))
        // reading order: "more" (col 1) comes before "again" (col 3), so "more" keeps archive
        let a = t.actionAssignment(actions: resolved)
        XCTAssertEqual(ids(a.actions(forCell: "more")), ["archive", "delete", "spam"])
        XCTAssertEqual(ids(a.actions(forCell: "again")), [], "the later button shows nothing")
        XCTAssertEqual(a.contested["archive"], ["more", "again"])
        XCTAssertTrue(t.emptyCellIDs(fields: [:], actions: resolved).contains("again"), "so it collapses like an absent action")
        let warning = t.validate().first { $0.message.contains("archive") && $0.message.contains("drawn once") }
        XCTAssertEqual(warning?.severity, .warning)
        XCTAssertEqual(warning?.cellId, "again")
    }

    func testIncludeWarnsAboutIdsNoActionHas() throws {
        let manifest = try HeraldJSON.decoder().decode(HeraldManifest.self, from: Data(
            #"{"app":"webwatcher.email","appName":"W","fields":[],"actions":[{"id":"markRead","label":"Mark as Read","kind":"callback"}]}"#.utf8))
        let t = try template(Self.requested)
        let issues = t.validate(manifest: manifest)
        XCTAssertTrue(issues.contains { $0.message.contains("'archive'") && !$0.isError })
        XCTAssertFalse(issues.contains { $0.isError })
    }

    func testBadSpacingAndBlankIdsAreErrors() throws {
        var t = try template(Self.requested)
        t.cells[5].component = .actions(HeraldActionsComponent(include: ["archive", " "], spacing: 100))
        let errors = t.validate().filter { $0.isError }.map(\.path)
        XCTAssertTrue(errors.contains { $0.hasSuffix(".spacing") })
        XCTAssertTrue(errors.contains { $0.hasSuffix(".include") })
    }

    func testSourceStillLimitsWhatAnIncludedActionCanBe() throws {
        let mixed = resolved + [HeraldResolvedAction(action: HeraldAction(id: "follow", label: "Follow", kind: .dismiss), origin: .template)]
        var t = try template(Self.requested)
        t.cells[5].component = .actions(HeraldActionsComponent(source: .template, include: ["archive", "follow"]))
        XCTAssertEqual(ids(t.actionAssignment(actions: mixed).actions(forCell: "more")), ["follow"])
    }

    // MARK: Frames

    /// The grid solved with button-sized rows, then the action row placed by `ActionRowMath`: the markRead button is
    /// in column 1 of row 4, the icon spans rows 1-3 of column 1, and archive, delete and spam sit against the
    /// right edge of the merged columns 2-4 cell.
    func testTheRequestedLayoutPutsTheButtonsWhereTheyAreAsked() throws {
        let t = try template(Self.requested)
        let line = 20.0, button = 24.0
        let solution = GridSolver.solve(
            grid: t.grid!, cells: t.cells, plan: t.plan(emptyCells: []),
            measure: GridMeasure(idealWidth: { _ in 0 }, height: { i, _ in
                ["read", "more"].contains(t.cells[i].id) ? button : (t.cells[i].id == "icon" ? 56 : line) }))
        func frame(_ id: String) throws -> GridRect { try XCTUnwrap(solution.frames[t.cells.firstIndex { $0.id == id }!], id) }
        let icon = try frame("icon"), read = try frame("read"), more = try frame("more")

        XCTAssertEqual(read.x, 14, accuracy: 0.001, "the markRead button is in column 1")
        XCTAssertEqual(read.width, 72, accuracy: 0.001)
        XCTAssertEqual(icon.x, 14, accuracy: 0.001)
        XCTAssertEqual(icon.y, 14, accuracy: 0.001, "the icon starts at row 1 and reaches row 3")
        XCTAssertLessThanOrEqual(icon.maxY, read.y, "the icon ends above the button row (row 4)")
        XCTAssertEqual(more.y, read.y, accuracy: 0.001, "both are in row 4")
        XCTAssertEqual(more.x, 14 + 72 + 8, accuracy: 0.001, "the merged cell starts at column 2")
        XCTAssertEqual(more.maxX, 400 - 14, accuracy: 0.001, "and ends at the right edge of column 4")

        guard case .actions(let a) = t.cells.first(where: { $0.id == "more" })!.component else { return XCTFail() }
        let sizes = [CGSize(width: 62, height: 24), CGSize(width: 54, height: 24), CGSize(width: 48, height: 24)]   // Archive, Delete, Spam
        let row = ActionRowMath.arrange(sizes: sizes, width: more.width, spacing: a.effectiveSpacing, lineSpacing: a.effectiveSpacing,
                                        wrap: a.wraps, align: a.effectiveAlign)
        let abs = row.frames.map { CGRect(x: more.x + $0.minX, y: more.y + $0.minY, width: $0.width, height: $0.height) }
        XCTAssertEqual(abs[2].maxX, more.maxX, accuracy: 0.001, "Spam touches the right edge")
        XCTAssertEqual(abs[1].maxX, abs[2].minX - 6, accuracy: 0.001, "6 pt between buttons")
        XCTAssertEqual(abs[0].maxX, abs[1].minX - 6, accuracy: 0.001)
        XCTAssertLessThan(abs[0].minX, abs[1].minX, "Archive, Delete, Spam in include order")
        XCTAssertGreaterThan(abs[0].minX, read.maxX, "all of them to the right of the markRead button")
        XCTAssertTrue(abs.allSatisfy { $0.minY == more.y && $0.height == 24 }, "one line")
        XCTAssertEqual(row.size.width, more.width, accuracy: 0.001, "the row fills the cell so trailing means the edge")
    }

    func testAlignmentsOfTheRowMath() {
        let sizes = [CGSize(width: 50, height: 24), CGSize(width: 50, height: 24), CGSize(width: 50, height: 24)]
        func frames(_ align: HeraldActionsAlign, width: CGFloat = 300, wrap: Bool = false, spacing: CGFloat = 6) -> [CGRect] {
            ActionRowMath.arrange(sizes: sizes, width: width, spacing: spacing, lineSpacing: 6, wrap: wrap, align: align).frames
        }
        XCTAssertEqual(frames(.leading).map(\.minX), [0, 56, 112])
        XCTAssertEqual(frames(.trailing).map(\.minX), [138, 194, 250])
        XCTAssertEqual(frames(.center).map(\.minX), [69, 125, 181])
        XCTAssertEqual(frames(.spaceBetween).map(\.minX), [0, 125, 250], "first at the start, last at the end, the middle between")
        XCTAssertEqual(frames(.leading, spacing: 20).map(\.minX), [0, 70, 140])
        // Wrapping: 120 pt fits two 50 pt buttons and a gap; the third goes to a second line, which is aligned on its own.
        let wrapped = frames(.trailing, width: 120, wrap: true)
        XCTAssertEqual(wrapped.map(\.minX), [14, 70, 70])
        XCTAssertEqual(wrapped.map(\.minY), [0, 0, 30])
        // Without wrap the row never breaks, even past the width.
        XCTAssertEqual(frames(.leading, width: 120).map(\.minY), [0, 0, 0])
        XCTAssertEqual(ActionRowMath.arrange(sizes: [], width: 100, spacing: 6, lineSpacing: 6, wrap: true, align: .center).frames, [])
    }
}
