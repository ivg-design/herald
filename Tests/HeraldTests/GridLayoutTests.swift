import XCTest
@testable import HeraldCore

/// The renderer's arithmetic (Sources/Herald/Core/GridLayout.swift): track sizes, spans, gaps, collapse of
/// empty components, rows and columns, and the overflow rule of the action row. The SwiftUI side
/// (`GridCanvasLayout`) only supplies measurements and places the views.
final class GridLayoutTests: XCTestCase {
    // MARK: Helpers

    private func cell(_ id: String, _ row: Int, _ col: Int, rows: Int = 1, cols: Int = 1, pad: Double = 0,
                      _ component: HeraldComponent = .spacer) -> HeraldCell {
        HeraldCell(id: id, row: row, col: col, rowSpan: rows, colSpan: cols, padding: pad, component: component)
    }

    private func text(_ binding: String, behavior: HeraldEmptyBehavior? = nil) -> HeraldComponent {
        .text(HeraldTextComponent(binding: binding, emptyBehavior: behavior))
    }

    /// Measures by cell id: ideal widths from a table, height = lineHeight per line of text that wraps in the
    /// given width (`textWidth` is how wide the text is on one line), or a fixed height.
    private func measure(_ cells: [HeraldCell], widths: [String: Double] = [:], heights: [String: Double] = [:],
                         lineHeight: Double = 16) -> GridMeasure {
        GridMeasure(
            idealWidth: { widths[cells[$0].id] ?? 0 },
            height: { i, w in
                let id = cells[i].id
                if let h = heights[id] { return h }
                guard let tw = widths[id], tw > 0 else { return 0 }
                return (tw / max(w, 1)).rounded(.up) * lineHeight
            })
    }

    private func solve(_ grid: HeraldGrid, _ cells: [HeraldCell], plan: HeraldGridPlan = HeraldGridPlan(),
                       widths: [String: Double] = [:], heights: [String: Double] = [:],
                       width: Double? = nil) -> GridSolution {
        GridSolver.solve(grid: grid, cells: cells, plan: plan, width: width,
                         measure: measure(cells, widths: widths, heights: heights))
    }

    private func frame(_ s: GridSolution, _ cells: [HeraldCell], _ id: String) throws -> GridRect {
        let i = try XCTUnwrap(cells.firstIndex { $0.id == id })
        return try XCTUnwrap(s.frames[i], "cell \(id) has no frame")
    }

    private func grid(rows: Int = 3, cols: Int = 4, rowSizes: [HeraldSize]? = nil, colSizes: [HeraldSize]? = nil,
                      gap: Double = 8, padding: Double = 14, width: Double = 400) -> HeraldGrid {
        HeraldGrid(rows: rows, cols: cols, rowSizes: rowSizes, colSizes: colSizes, gap: gap, padding: padding, width: width)
    }

    private func fields(_ pairs: [String: String]) -> [String: HeraldFieldValue] { pairs.mapValues { .text($0) } }

    // MARK: Column sizes

    func testPointsAutoAndFillColumns() {
        // 400 wide, 14 padding, 8 gap: inner 372, three gaps 24.
        let g = grid(rows: 1, cols: 4, rowSizes: [.auto], colSizes: [.points(72), .fill, .fill, .auto])
        let cells = [cell("a", 0, 0), cell("meta", 0, 3)]
        let s = solve(g, cells, widths: ["meta": 40])
        XCTAssertEqual(s.colWidths[0], 72)
        XCTAssertEqual(s.colWidths[3], 40)
        // 372 - 24 - 72 - 40 = 236, shared by the two fill columns.
        XCTAssertEqual(s.colWidths[1], 118, accuracy: 0.001)
        XCTAssertEqual(s.colWidths[2], 118, accuracy: 0.001)
        XCTAssertEqual(s.width, 400)
        // Tracks follow each other with the gap between them.
        XCTAssertEqual(s.colOrigins[0], 14)
        XCTAssertEqual(s.colOrigins[1], 14 + 72 + 8)
        XCTAssertEqual(s.colOrigins[3], 14 + 72 + 8 + 118 + 8 + 118 + 8, accuracy: 0.001)
        XCTAssertEqual(s.colOrigins[3] + s.colWidths[3], 400 - 14, accuracy: 0.001)
    }

    func testAutoColumnIsWidestSingleCellPlusItsPadding() {
        let g = grid(rows: 2, cols: 2, rowSizes: [.auto, .auto], colSizes: [.auto, .fill])
        let cells = [cell("a", 0, 0, pad: 3), cell("b", 1, 0)]
        let s = solve(g, cells, widths: ["a": 30, "b": 50])
        XCTAssertEqual(s.colWidths[0], 50)                       // b is wider than a + 2 * 3
        let wider = solve(g, cells, widths: ["a": 50, "b": 40])
        XCTAssertEqual(wider.colWidths[0], 56)                   // 50 + padding on both sides
    }

    func testAutoColumnsAreTrimmedWideFirstAndFillGetsNothing() {
        // inner 200 - gap 10 = 190 for two auto columns that want 40 and 400: the small one keeps its size.
        let g = grid(rows: 1, cols: 3, rowSizes: [.auto], colSizes: [.auto, .auto, .fill], gap: 10, padding: 10, width: 220)
        let cells = [cell("small", 0, 0), cell("long", 0, 1), cell("rest", 0, 2)]
        let s = solve(g, cells, widths: ["small": 40, "long": 400])
        XCTAssertEqual(s.colWidths[0], 40)
        XCTAssertEqual(s.colWidths[1], 200 - 20 - 40, accuracy: 0.001)   // what is left after the gaps and `small`
        XCTAssertEqual(s.colWidths[2], 0, accuracy: 0.001)
    }

    func testFixedColumnsLargerThanTheBannerLeaveFillAtZero() {
        let g = grid(rows: 1, cols: 3, rowSizes: [.auto], colSizes: [.points(300), .points(300), .fill], width: 400)
        let s = solve(g, [cell("a", 0, 0)])
        XCTAssertEqual(s.colWidths[2], 0)
        XCTAssertEqual(s.colWidths[0], 300)
    }

    func testNegativePointSizesAreZero() {
        let g = grid(rows: 1, cols: 2, rowSizes: [.points(-5)], colSizes: [.points(-10), .fill])
        let s = solve(g, [cell("a", 0, 0)])
        XCTAssertEqual(s.colWidths[0], 0)
        XCTAssertEqual(s.rowHeights[0], 0)
    }

    func testBannerWidthComesFromTheGridAndIsClamped() {
        let cells = [cell("a", 0, 0)]
        XCTAssertEqual(solve(grid(width: 520), cells).width, 520)
        XCTAssertEqual(solve(grid(width: 20), cells).width, HeraldTemplate.widthRange.lowerBound)
        XCTAssertEqual(solve(grid(width: 5000), cells).width, HeraldTemplate.widthRange.upperBound)
        XCTAssertEqual(solve(grid(width: 520), cells, width: 300).width, 300, "an explicit width wins")
        XCTAssertEqual(GridSolver.clampedWidth(.nan), 400)
    }

    func testSpanningCellLendsItsWidthToAutoColumnsOnly() {
        let g = grid(rows: 1, cols: 3, rowSizes: [.auto], colSizes: [.auto, .auto, .points(50)], gap: 10, padding: 0, width: 400)
        let cells = [cell("wide", 0, 0, cols: 2)]
        let s = solve(g, cells, widths: ["wide": 100])
        // 100 wide across two auto columns with a 10 gap: 45 each.
        XCTAssertEqual(s.colWidths[0], 45, accuracy: 0.001)
        XCTAssertEqual(s.colWidths[1], 45, accuracy: 0.001)

        // A span that covers a fill column does not widen anything: fill absorbs it.
        let g2 = grid(rows: 1, cols: 3, rowSizes: [.auto], colSizes: [.auto, .fill, .auto], gap: 10, padding: 0, width: 400)
        let s2 = solve(g2, [cell("wide", 0, 0, cols: 3)], widths: ["wide": 300])
        XCTAssertEqual(s2.colWidths[0], 0)
        XCTAssertEqual(s2.colWidths[2], 0)
    }

    // MARK: Row sizes and spans

    func testRowsAreAsTallAsTheirTallestCellAndGapsSeparateThem() {
        let g = grid(rows: 3, cols: 1, rowSizes: [.auto, .auto, .auto], colSizes: [.fill], gap: 6, padding: 10, width: 300)
        let cells = [cell("t", 0, 0), cell("s", 1, 0), cell("b", 2, 0)]
        let s = solve(g, cells, heights: ["t": 20, "s": 14, "b": 40])
        XCTAssertEqual(s.rowHeights, [20, 14, 40])
        XCTAssertEqual(s.rowOrigins, [10, 36, 56])
        XCTAssertEqual(s.height, 106)
    }

    func testPointsRowIgnoresContentAndFillRowActsAsAuto() {
        let g = grid(rows: 2, cols: 1, rowSizes: [.points(30), .fill], colSizes: [.fill], gap: 0, padding: 0, width: 300)
        let cells = [cell("a", 0, 0), cell("b", 1, 0)]
        let s = solve(g, cells, heights: ["a": 90, "b": 22])
        XCTAssertEqual(s.rowHeights, [30, 22])
        XCTAssertEqual(s.height, 52)
    }

    func testCellPaddingAddsToTheRowAndInsetsTheContent() throws {
        let g = grid(rows: 1, cols: 1, rowSizes: [.auto], colSizes: [.fill], gap: 0, padding: 0, width: 200)
        let cells = [cell("a", 0, 0, pad: 5)]
        var seenWidth = 0.0
        let m = GridMeasure(idealWidth: { _ in 0 }, height: { _, w in seenWidth = w; return 20 })
        let s = GridSolver.solve(grid: g, cells: cells, plan: HeraldGridPlan(), measure: m)
        XCTAssertEqual(seenWidth, 190, "the content is measured inside the padding")
        XCTAssertEqual(s.rowHeights[0], 30)
        XCTAssertEqual(try frame(s, cells, "a"), GridRect(x: 0, y: 0, width: 200, height: 30))
    }

    func testMergedCellFrameSpansTracksAndGaps() throws {
        // The image-left look: a 72 pt image over three rows, text over two fill columns.
        let g = grid(rows: 3, cols: 4, rowSizes: [.auto, .auto, .auto],
                     colSizes: [.points(72), .fill, .fill, .auto], gap: 8, padding: 12, width: 380)
        let cells = [cell("image", 0, 0, rows: 3), cell("title", 0, 1, cols: 2), cell("sub", 1, 1, cols: 2),
                     cell("body", 2, 1, cols: 2), cell("time", 2, 3)]
        let s = solve(g, cells, widths: ["title": 100, "sub": 60, "body": 100, "time": 30],
                      heights: ["image": 72, "title": 18, "sub": 15, "body": 30, "time": 12])
        let image = try frame(s, cells, "image")
        let title = try frame(s, cells, "title")
        // Rows: 18, 15, 30; text is 63 + two gaps = 79 > 72, so the image is shorter and nothing grows.
        XCTAssertEqual(s.rowHeights, [18, 15, 30])
        XCTAssertEqual(image.height, 18 + 8 + 15 + 8 + 30)
        XCTAssertEqual(image.width, 72)
        XCTAssertEqual(title.x, 92)
        // Two fill columns and the gap between them.
        XCTAssertEqual(title.width, s.colWidths[1] + 8 + s.colWidths[2], accuracy: 0.001)
        XCTAssertEqual(title.maxX + 8 + s.colWidths[3], 380 - 12, accuracy: 0.001)
    }

    func testTallSpanningCellGrowsTheLastRowSoTextStaysAtTheTop() throws {
        let g = grid(rows: 3, cols: 2, rowSizes: [.auto, .auto, .auto], colSizes: [.points(72), .fill],
                     gap: 6, padding: 0, width: 300)
        let cells = [cell("image", 0, 0, rows: 3), cell("t", 0, 1), cell("s", 1, 1), cell("b", 2, 1)]
        let s = solve(g, cells, heights: ["image": 100, "t": 10, "s": 10, "b": 10])
        // 100 - (10 + 10 + 10 + two gaps of 6) = 58 lent to the last row.
        XCTAssertEqual(s.rowHeights, [10, 10, 68])
        XCTAssertEqual(try frame(s, cells, "image").height, 100)
        XCTAssertEqual(s.height, 100)
    }

    func testSpanOverOnlyPointsRowsDoesNotGrowThem() throws {
        let g = grid(rows: 2, cols: 1, rowSizes: [.points(10), .points(10)], colSizes: [.fill], gap: 4, padding: 0, width: 200)
        let cells = [cell("a", 0, 0, rows: 2)]
        let s = solve(g, cells, heights: ["a": 500])
        XCTAssertEqual(s.rowHeights, [10, 10])
        XCTAssertEqual(try frame(s, cells, "a").height, 24)
    }

    func testTextWrapsToTheColumnWidthAndTheRowGrows() {
        // A body that needs 380 pt on one line, in a 100 pt column, is four lines tall.
        let g = grid(rows: 1, cols: 1, rowSizes: [.auto], colSizes: [.points(100)], gap: 0, padding: 0, width: 400)
        let s = solve(g, [cell("body", 0, 0)], widths: ["body": 380])
        XCTAssertEqual(s.rowHeights[0], 64)
    }

    func testCellOutsideTheGridHasNoFrame() {
        let g = grid(rows: 2, cols: 2)
        let cells = [cell("in", 0, 0), cell("out", 5, 5)]
        let s = solve(g, cells)
        XCTAssertNotNil(s.frames[0])
        XCTAssertNil(s.frames[1])
    }

    // MARK: Collapse

    /// imageLeft-like grid: title, subtitle, body rows, an action row; image column on the left.
    private func emailTemplate(collapseEmpty: Bool = true, bodyBehavior: HeraldEmptyBehavior? = nil) -> HeraldTemplate {
        let g = grid(rows: 4, cols: 3, rowSizes: [.auto, .auto, .auto, .auto], colSizes: [.points(72), .fill, .auto],
                     gap: 6, padding: 12, width: 380)
        let cells = [
            cell("image", 0, 0, rows: 3, .image(HeraldImageComponent(binding: "{image}"))),
            cell("title", 0, 1, text("{title}")),
            cell("sub", 1, 1, text("{subtitle}")),
            cell("body", 2, 1, text("{body}", behavior: bodyBehavior)),
            cell("time", 0, 2, .timestamp(HeraldTimestampComponent())),
            cell("actions", 3, 0, cols: 3, .actions(HeraldActionsComponent())),
        ]
        return HeraldTemplate(name: "t", app: "a", grid: g, cells: cells, collapseEmpty: collapseEmpty)
    }

    private let heights = ["image": 72.0, "title": 18, "sub": 15, "body": 30, "time": 12, "actions": 24]
    private let widths = ["time": 36.0]

    func testEmptyComponentsCollapseTheirRowsAndColumns() throws {
        let t = emailTemplate()
        // Only a title: no image, subtitle, body or buttons.
        let plan = t.plan(fields: fields(["title": "Hello"]), actions: [])
        XCTAssertEqual(plan.collapsedRows, [1, 2, 3])
        XCTAssertEqual(plan.collapsedCols, [0])
        let s = solve(t.grid!, t.cells, plan: plan, widths: widths, heights: heights)
        XCTAssertEqual(s.rowHeights, [18, 0, 0, 0])
        XCTAssertEqual(s.colWidths[0], 0)
        // Height is title + padding only: no gaps for collapsed rows.
        XCTAssertEqual(s.height, 12 + 18 + 12)
        // The text column starts at the left padding now that the image column is gone.
        let title = try frame(s, t.cells, "title")
        XCTAssertEqual(title.x, 12)
        XCTAssertNil(s.frames[t.cells.firstIndex { $0.id == "sub" }!])
        // Fill takes everything the 36 pt time column and the gap leave.
        XCTAssertEqual(s.colWidths[1], 380 - 24 - 6 - 36, accuracy: 0.001)
    }

    func testRowsComeBackWhenTheirComponentsHaveContent() throws {
        let t = emailTemplate()
        let full = fields(["title": "Hello", "subtitle": "There", "body": "Text", "image": "/tmp/a.png"])
        let action = HeraldResolvedAction(action: HeraldAction(id: "x", label: "X", kind: .dismiss), origin: .issuer)
        let plan = t.plan(fields: full, actions: [action])
        XCTAssertTrue(plan.collapsedRows.isEmpty)
        XCTAssertTrue(plan.collapsedCols.isEmpty)
        let s = solve(t.grid!, t.cells, plan: plan, widths: widths, heights: heights)
        XCTAssertEqual(s.rowHeights, [18, 15, 30, 24])
        // Title, subtitle and body (63) plus two gaps (12) are taller than the 72 pt image, so it grows to fit them.
        XCTAssertEqual(try frame(s, t.cells, "image").height, 75)
        XCTAssertEqual(s.height, 129)   // 12 + (18 + 15 + 30 + 24) + three gaps of 6 + 12
    }

    func testKeepBehaviourHoldsTheRowOpen() throws {
        // collapseEmpty off: an empty body stays, drawn blank, and its row keeps the height measured for it.
        let t = emailTemplate(collapseEmpty: false)
        let plan = t.plan(fields: fields(["title": "Hello"]), actions: [])
        XCTAssertTrue(plan.collapsedRows.isEmpty)
        XCTAssertTrue(plan.collapsedCols.isEmpty)
        XCTAssertTrue(plan.collapsedCells.isEmpty)
        let s = solve(t.grid!, t.cells, plan: plan, widths: widths, heights: heights)
        XCTAssertEqual(s.rowHeights[2], 30)
        XCTAssertEqual(s.colWidths[0], 72)
        XCTAssertNotNil(s.frames[t.cells.firstIndex { $0.id == "body" }!])
        XCTAssertEqual(s.height, 129)
    }

    func testPerComponentBehaviourOverridesTheTemplateDefault() throws {
        // Template collapses, but the body says keep: its row stays; the others still go.
        let t = emailTemplate(collapseEmpty: true, bodyBehavior: .keep)
        let plan = t.plan(fields: fields(["title": "Hello"]), actions: [])
        XCTAssertEqual(plan.collapsedRows, [1, 3])
        XCTAssertFalse(plan.collapsedCells.contains("body"))
        let s = solve(t.grid!, t.cells, plan: plan, widths: widths, heights: heights)
        XCTAssertEqual(s.rowHeights, [18, 0, 30, 0])
        XCTAssertEqual(s.height, 78)

        // And the reverse: the template keeps, the body says collapse.
        let t2 = emailTemplate(collapseEmpty: false, bodyBehavior: .collapse)
        let plan2 = t2.plan(fields: fields(["title": "Hello"]), actions: [])
        XCTAssertEqual(plan2.collapsedCells, ["body"])
        XCTAssertTrue(plan2.collapsedRows.isEmpty, "the kept image still covers the body's row")
    }

    func testRowNoCellTouchesCollapsesOnlyWhenCollapseEmptyIsOn() {
        let g = grid(rows: 3, cols: 1, rowSizes: [.auto, .auto, .points(20)], colSizes: [.fill], gap: 6, padding: 0, width: 200)
        let cells = [cell("a", 0, 0, text("{title}"))]
        let on = HeraldTemplate(name: "n", app: "a", grid: g, cells: cells, collapseEmpty: true)
        let off = HeraldTemplate(name: "n", app: "a", grid: g, cells: cells, collapseEmpty: false)
        let f = fields(["title": "x"])
        let sOn = solve(g, cells, plan: on.plan(fields: f, actions: []), heights: ["a": 10])
        let sOff = solve(g, cells, plan: off.plan(fields: f, actions: []), heights: ["a": 10])
        XCTAssertEqual(sOn.height, 10)
        XCTAssertEqual(sOn.rowHeights, [10, 0, 0])
        // Off: the unused rows stay, the points row at its 20 pt, the auto row at 0, with their gaps.
        XCTAssertEqual(sOff.rowHeights, [10, 0, 20])
        XCTAssertEqual(sOff.height, 42)
    }

    func testSpanningCellKeepsEveryTrackItCoversAlive() throws {
        // The image spans rows 0-2 although only its top row has other content.
        let t = emailTemplate()
        let plan = t.plan(fields: fields(["title": "Hello", "image": "/tmp/a.png"]), actions: [])
        XCTAssertEqual(plan.collapsedRows, [3], "the image covers rows 0 to 2; only the empty action row goes")
        XCTAssertTrue(plan.collapsedCols.isEmpty)
        let s = solve(t.grid!, t.cells, plan: plan, widths: widths, heights: heights)
        // Rows 1 and 2 carry no text, but the 72 pt image needs them: 72 = 18 + 6 + 0 + 6 + 42 (the last row grows).
        XCTAssertEqual(s.rowHeights, [18, 0, 42, 0])
        XCTAssertEqual(try frame(s, t.cells, "image").height, 72)
    }

    func testEverythingEmptyLeavesJustThePadding() {
        let t = emailTemplate()
        let plan = t.plan(emptyCells: Set(t.cells.map(\.id)))
        let s = solve(t.grid!, t.cells, plan: plan, widths: widths, heights: heights)
        XCTAssertEqual(s.height, 24)
        XCTAssertTrue(s.frames.allSatisfy { $0 == nil })
    }

    func testBuiltinTemplatesCollapseLikeV1() throws {
        // v1 imageLeft with only a title: no image column, no subtitle or body rows, no action row.
        let t = BuiltinTemplates.template(layout: .imageLeft)
        let plan = t.plan(fields: fields(["title": "Hi"]), actions: [])
        XCTAssertEqual(plan.collapsedCols, [0], "the image column goes")
        // The action row goes too. The subtitle and body rows stay: the app icon and the time sit on them in the
        // meta column, exactly the column v1 stacked under the close button.
        XCTAssertEqual(plan.collapsedRows, [3])
        XCTAssertTrue(plan.collapsedCells.isSuperset(of: ["image", "subtitle", "body", "actions"]))
        let s = solve(t.grid!, t.cells, plan: plan, widths: ["icon": 22, "close": 18, "time": 30],
                      heights: ["title": 17, "icon": 22, "close": 18, "time": 12])
        XCTAssertEqual(s.width, 380)
        XCTAssertEqual(s.rowHeights, [18, 22, 12, 0])
        XCTAssertEqual(s.height, 88)
    }

    // MARK: Action overflow

    func testVisibleActionCount() {
        XCTAssertEqual(ActionOverflow.visibleCount(total: 0, maxVisible: 3), 0)
        XCTAssertEqual(ActionOverflow.visibleCount(total: 5, maxVisible: nil), 5)
        XCTAssertEqual(ActionOverflow.visibleCount(total: 5, maxVisible: 2), 2)
        XCTAssertEqual(ActionOverflow.visibleCount(total: 2, maxVisible: 9), 2)
        XCTAssertEqual(ActionOverflow.visibleCount(total: 5, maxVisible: 0), 1, "a typo cannot hide every button")
        XCTAssertEqual(ActionOverflow.menuTitle(hidden: 3), "+3")
    }

    func testWaterFill() {
        let r = Dictionary(uniqueKeysWithValues: GridSolver.waterFill([(0, 10), (1, 500), (2, 500)], budget: 210))
        XCTAssertEqual(r[0], 10)
        XCTAssertEqual(r[1], 100)
        XCTAssertEqual(r[2], 100)
        let plenty = Dictionary(uniqueKeysWithValues: GridSolver.waterFill([(0, 10), (1, 20)], budget: 500))
        XCTAssertEqual(plenty[0], 10)
        XCTAssertEqual(plenty[1], 20)
        XCTAssertTrue(GridSolver.waterFill([], budget: 10).isEmpty)
    }

    // MARK: Banner data (fields and actions)

    private func notification(_ build: (inout HeraldNotification) -> Void = { _ in }) -> HeraldNotification {
        var n = HeraldNotification(app: "webwatcher.email", id: "n1", title: "2 new from Acme")
        build(&n)
        return n
    }

    private func emailManifest() -> HeraldManifest {
        HeraldManifest(app: "webwatcher.email", appName: "Email",
                       actions: [HeraldButton(label: "Mark as Read", callback: HeraldCallback()),
                                 HeraldButton(label: "Archive", style: "destructive", callback: HeraldCallback())],
                       actionIDs: ["markRead", "archive"])
    }

    func testActionsCarryTheIdsTheManifestDeclared() {
        let n = notification { $0.buttons = [HeraldButton(label: "Mark as Read", callback: HeraldCallback()),
                                              HeraldButton(label: "Open", url: "https://example.com")] }
        let list = BannerData.actions(for: n, manifest: emailManifest(), rules: [])
        XCTAssertEqual(list.map(\.id), ["markRead", "open"], "a declared id for a manifest action, a label slug otherwise")
        XCTAssertEqual(list.map(\.origin), [.issuer, .issuer])
        XCTAssertEqual(list[0].action.kind, .callback)
        XCTAssertEqual(list[1].action.kind, .url)
    }

    func testButtonsActionsAndActionIdsResolveToTheSameListThePreviewShows() throws {
        let m = emailManifest()
        // `actionIds` look the actions up in the manifest; `actions` reaches the model as `buttons` (see RouterTests).
        let viaIds = BannerData.actions(for: notification { $0.actionIds = ["markRead", "archive"] }, manifest: m, rules: [])
        let viaButtons = BannerData.actions(for: notification { $0.buttons = m.actions }, manifest: m, rules: [])
        XCTAssertEqual(viaIds.map(\.action), viaButtons.map(\.action))
        XCTAssertEqual(viaIds.map(\.id), ["markRead", "archive"])

        // The sample preview is an issuer that names every declared action, through the same function.
        let plan = try PreviewPlan.make(PreviewSpec(app: "webwatcher.email"), manifest: m, stored: { _ in nil })
        XCTAssertEqual(plan.actions.map(\.action), viaIds.map(\.action))
        let live = BannerData.actions(for: plan.notification, manifest: m, rules: [])
        XCTAssertEqual(live.map(\.id), plan.actions.map(\.id), "what the banner would resolve from the preview's own notification")

        // Manifest actions are not shown just because the manifest declares them.
        XCTAssertTrue(BannerData.actions(for: notification(), manifest: m, rules: []).isEmpty)
        let real = try PreviewPlan.make(PreviewSpec(app: "webwatcher.email", data: notification()), manifest: m, stored: { _ in nil })
        XCTAssertTrue(real.actions.isEmpty, "a real payload that names no action gets none, in a preview too")

        // Unknown ids are skipped, repeated ids collapse, case does not matter.
        let odd = BannerData.actions(for: notification { $0.actionIds = ["ARCHIVE", "nope", "archive"] }, manifest: m, rules: [])
        XCTAssertEqual(odd.map(\.id), ["archive"])
        XCTAssertTrue(BannerData.actions(for: notification { $0.actionIds = ["archive"] }, manifest: nil, rules: []).isEmpty)

        // At delivery the ids become buttons, and an explicit `buttons` is left alone.
        let made = ActionResolver.materializingActionIDs(notification { $0.actionIds = ["archive"] }, manifest: m)
        XCTAssertEqual(made.buttons?.map(\.label), ["Archive"])
        let kept = ActionResolver.materializingActionIDs(notification { $0.buttons = []; $0.actionIds = ["archive"] }, manifest: m)
        XCTAssertEqual(kept.buttons, [], "an explicit empty array means no buttons")
    }

    func testSnoozeFlagBecomesAnIssuerActionTheRulesCanHide() {
        let n = notification { $0.snooze = true; $0.buttons = [HeraldButton(label: "Open", url: "https://example.com")] }
        let plain = BannerData.actions(for: n, manifest: nil, rules: [])
        XCTAssertEqual(plain.map(\.id), ["open", "snooze"])
        XCTAssertEqual(plain.last?.action.kind, .snooze)
        XCTAssertNil(plain.last?.action.snoozeMinutes, "no fixed minutes means the whole snooze menu")
        XCTAssertEqual(plain.last?.origin, .issuer)

        let hidden = BannerData.actions(for: n, manifest: nil, rules: [HeraldActionRule(match: "snooze", hide: true)])
        XCTAssertEqual(hidden.map(\.id), ["open"])

        XCTAssertEqual(BannerData.actions(for: notification(), manifest: nil, rules: []).count, 0)
    }

    func testTemplateRulesHideRelabelReorderAndAddActions() throws {
        let n = notification { $0.buttons = [HeraldButton(label: "Mark as Read", callback: HeraldCallback()),
                                              HeraldButton(label: "Archive", style: "destructive", callback: HeraldCallback())] }
        let shortcut = HeraldAction(id: "follow-up", label: "Follow up", kind: .shortcut, shortcut: "Create follow-up",
                                    input: "{title}")
        let rules = [HeraldActionRule(match: "archive", relabel: "Archive it", position: 0),
                     HeraldActionRule(match: "markRead", hide: true),
                     HeraldActionRule(add: shortcut)]
        let list = BannerData.actions(for: n, manifest: emailManifest(), rules: rules)
        XCTAssertEqual(list.map(\.id), ["archive", "follow-up"])
        XCTAssertEqual(list[0].action.label, "Archive it")
        XCTAssertEqual(list[0].origin, .issuer, "relabelling keeps where it came from")
        XCTAssertEqual(list[1].origin, .template)
        XCTAssertEqual(list[1].action.shortcut, "Create follow-up")
    }

    func testFieldsComeFromTheNotificationWhenNothingIsStored() {
        var n = notification { $0.subtitle = "Invoice"; $0.metadata = .object(["count": .number(2)]) }
        n.body = nil
        let f = BannerData.fields(for: n, stored: nil, override: nil, manifest: nil, extra: [:],
                                  deliveredAt: Date(timeIntervalSince1970: 0), hasPicture: false)
        XCTAssertEqual(f["title"], .text("2 new from Acme"))
        XCTAssertEqual(f["subtitle"], .text("Invoice"))
        XCTAssertEqual(f["count"], .number(2))
        XCTAssertNil(f["body"])
        XCTAssertNil(f["image"])
    }

    func testAFailureLineReplacesTheStoredSubtitle() {
        // The failure line is shown by swapping the notification's subtitle; the item's stored fields are untouched.
        let stored: [String: HeraldFieldValue] = ["title": .text("2 new from Acme"), "subtitle": .text("Invoice")]
        let n = notification { $0.subtitle = "Action failed \u{00B7} no callback URL" }
        let f = BannerData.fields(for: n, stored: stored, override: nil, manifest: nil, extra: [:],
                                  deliveredAt: Date(), hasPicture: false)
        XCTAssertEqual(f["subtitle"], .text("Action failed \u{00B7} no callback URL"))
        XCTAssertEqual(stored["subtitle"], .text("Invoice"))
    }

    func testDesignerSampleFieldsAreNotOverlaid() {
        let samples: [String: HeraldFieldValue] = ["title": .text("Sample title"), "sender": .text("Acme")]
        let n = notification { $0.subtitle = "From the notification" }
        let f = BannerData.fields(for: n, stored: ["title": .text("stored")], override: samples, manifest: nil,
                                  extra: [:], deliveredAt: Date(), hasPicture: false)
        XCTAssertEqual(f["title"], .text("Sample title"))
        XCTAssertNil(f["subtitle"])
        XCTAssertEqual(f["sender"], .text("Acme"))
    }

    func testTemplateExtraValuesAreBindableAndBlankOnesSkipped() {
        let f = BannerData.fields(for: notification(), stored: nil, override: nil, manifest: nil,
                                  extra: ["queue": "inbox", "empty": "  "], deliveredAt: Date(), hasPicture: false)
        XCTAssertEqual(f["extra.queue"], .text("inbox"))
        XCTAssertNil(f["extra.empty"])
        XCTAssertEqual(TemplateResolver.bind("Queue: {extra.queue}", fields: f), "Queue: inbox")
    }

    func testAPictureMakesTheImageFieldPresentWithoutOverridingARealOne() {
        let withPicture = BannerData.fields(for: notification(), stored: nil, override: nil, manifest: nil,
                                            extra: [:], deliveredAt: Date(), hasPicture: true)
        XCTAssertEqual(withPicture["image"], .text(BannerData.cachedImageToken))
        let real = BannerData.fields(for: notification { $0.image = "/tmp/a.png" }, stored: nil, override: nil,
                                     manifest: nil, extra: [:], deliveredAt: Date(), hasPicture: true)
        XCTAssertEqual(real["image"], .text("/tmp/a.png"))
    }

    // MARK: Component values

    func testProgressFraction() {
        XCTAssertEqual(GridFormat.progressFraction("0.4"), 0.4)
        XCTAssertEqual(GridFormat.progressFraction("40"), 0.4)
        XCTAssertEqual(GridFormat.progressFraction(" 40% "), 0.4)
        XCTAssertEqual(GridFormat.progressFraction("1"), 1)
        XCTAssertEqual(GridFormat.progressFraction("150"), 1)
        XCTAssertEqual(GridFormat.progressFraction("-3"), 0)
        XCTAssertNil(GridFormat.progressFraction("soon"))
        XCTAssertNil(GridFormat.progressFraction(""))
    }

    func testDateFormatting() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let us = Locale(identifier: "en_US")
        let now = ISODate.parse("2026-10-01T15:00:00Z")!
        let sameDay = ISODate.parse("2026-10-01T14:14:00Z")!
        let earlier = ISODate.parse("2026-09-28T08:05:00Z")!
        let time = GridFormat.absolute(sameDay, now: now, calendar: cal, locale: us)
        XCTAssertTrue(time.contains("2:14"), time)
        XCTAssertFalse(time.contains("Oct"), time)
        let day = GridFormat.absolute(earlier, now: now, calendar: cal, locale: us)
        XCTAssertTrue(day.contains("Sep") && day.contains("28") && day.contains("8:05"), day)

        let ago = GridFormat.relative(ISODate.parse("2026-10-01T14:55:00Z")!, now: now, locale: us)
        XCTAssertTrue(ago.contains("5") && ago.contains("ago"), ago)
    }
}
