import XCTest
@testable import HeraldCore

// The Designer's live preview is a first-class pane: never below half the design area.
final class DesignerSplitTests: XCTestCase {
    func testThePreviewKeepsAtLeastAQuarterAndStartsAtHalf() {
        XCTAssertEqual(DesignerSplit.minPreviewFraction, 0.25)
        XCTAssertEqual(DesignerSplit.defaultPreviewFraction, 0.5)
        XCTAssertEqual(DesignerSplit(axis: .vertical, fraction: 0.1).fraction, 0.25)
    }

    func testThePreviewIsNeverSmallerThanHalfTheDesignArea() {
        for (w, h) in [(1020.0, 640.0), (1100, 760), (1400, 820), (1700, 900), (2560, 1300)] {
            for f in [0.0, 0.2, 0.5, 0.6, 0.75, 0.9, 1.0, -3, .nan, .infinity] {
                let s = DesignerSplit.make(width: w, fraction: f)
                let total = s.axis == .horizontal ? w : h
                XCTAssertGreaterThanOrEqual(s.fraction, DesignerSplit.minPreviewFraction, "w=\(w) f=\(f)")
                XCTAssertLessThanOrEqual(s.fraction, DesignerSplit.maxPreviewFraction)
                // Half of what is left once the divider is taken out: the preview's share of the area is at least 49 %.
                XCTAssertGreaterThanOrEqual(s.previewLength(total: total) / total, 0.24, "w=\(w) f=\(f)")
                XCTAssertEqual(s.previewLength(total: total) + DesignerSplit.dividerThickness + s.editorLength(total: total), total, accuracy: 1.001)
            }
        }
    }

    func testWideWindowsSplitSideBySideNarrowOnesStack() {
        XCTAssertEqual(DesignerSplit.axis(forWidth: 1100), .vertical, "the preview sits above the canvas, in the centre column")
        XCTAssertEqual(DesignerSplit.axis(forWidth: 5000), .vertical)
    }

    func testDraggingTheDividerIsClampedAndConvertsToAFraction() {
        let total = 800.0
        // Drag the editor to 100 pt: it keeps its minimum, the preview its share below the maximum.
        let f1 = DesignerSplit.fraction(forEditorLength: 100, total: total)
        XCTAssertEqual(f1, 1 - 280 / 792, accuracy: 0.0001)
        // A stored 0.75 on a short window still leaves the editor its minimum.
        XCTAssertGreaterThanOrEqual(DesignerSplit(axis: .vertical, fraction: 0.75).editorLength(total: 700), DesignerSplit.minEditorLength)
        // Drag the editor bigger than three quarters: the preview stops at its quarter.
        XCTAssertEqual(DesignerSplit.fraction(forEditorLength: 790, total: total), DesignerSplit.minPreviewFraction)
        // A middle position round-trips: editor 300 of 792 usable.
        let f = DesignerSplit.fraction(forEditorLength: 300, total: total)
        XCTAssertEqual(f, 1 - 300 / 792, accuracy: 0.0001)
        XCTAssertEqual(DesignerSplit(axis: .vertical, fraction: f).editorLength(total: total), 300, accuracy: 1)
    }

    func testThePositionIsPersistedAndClampedOnLoad() {
        let d = UserDefaults(suiteName: "herald-split-\(UUID().uuidString)")!
        XCTAssertEqual(DesignerSplit.load(from: d), DesignerSplit.defaultPreviewFraction)
        DesignerSplit.save(0.66, to: d)
        XCTAssertEqual(DesignerSplit.load(from: d), 0.66, accuracy: 0.0001)
        d.set(0.1, forKey: DesignerSplit.defaultsKey)
        XCTAssertEqual(DesignerSplit.load(from: d), DesignerSplit.minPreviewFraction, "a stale or hand-edited value cannot shrink the preview below a quarter")
        DesignerSplit.save(5, to: d)
        XCTAssertEqual(DesignerSplit.load(from: d), DesignerSplit.maxPreviewFraction)
    }

    func testSidebarWidthsAreClampedAndPersisted() {
        XCTAssertEqual(DesignerPanes.clampLeft(10), 180); XCTAssertEqual(DesignerPanes.clampLeft(999), 360)
        XCTAssertEqual(DesignerPanes.clampRight(10), 280); XCTAssertEqual(DesignerPanes.clampRight(999), 480)
        // A narrow window leaves the centre column its minimum.
        XCTAssertLessThanOrEqual(DesignerPanes.clampRight(480, window: 1020) + DesignerPanes.leftRange.lowerBound + DesignerPanes.minCenter, 1020 + 0.001)
        let d = UserDefaults(suiteName: "herald-panes-\(UUID().uuidString)")!
        XCTAssertEqual(DesignerPanes.load(from: d), DesignerPanes())
        var p = DesignerPanes(); p.left = 300; p.right = 400; p.setZoom(.editor, 1.5); p.setZoom(.preview, 9)
        p.save(to: d)
        let q = DesignerPanes.load(from: d)
        XCTAssertEqual(q.left, 300); XCTAssertEqual(q.right, 400); XCTAssertEqual(q.editorZoom, 1.5); XCTAssertEqual(q.previewZoom, 3.0)
    }

    func testZoomStepsPinchAndLabels() {
        XCTAssertEqual(DesignerZoom.zoomIn(1), 1.1); XCTAssertEqual(DesignerZoom.zoomOut(1), 0.9)
        XCTAssertEqual(DesignerZoom.zoomIn(3), 3); XCTAssertEqual(DesignerZoom.zoomOut(0.5), 0.5)
        XCTAssertEqual(DesignerZoom.zoomIn(1.3), 1.5)
        XCTAssertEqual(DesignerZoom.pinched(from: 1, magnification: 10), 3); XCTAssertEqual(DesignerZoom.pinched(from: 1, magnification: 0.01), 0.5)
        XCTAssertEqual(DesignerZoom.pinched(from: 2, magnification: .nan), 2)
        XCTAssertEqual(DesignerZoom.label(1.25), "125%"); XCTAssertEqual(DesignerZoom.clamped(.nan), 1)
        // Every stop is inside the 50-300 % range the popover offers.
        XCTAssertTrue(DesignerZoom.steps.allSatisfy { DesignerZoom.range.contains($0) })
    }
}
