import XCTest
import SwiftUI
import AppKit
import HeraldClient
@testable import HeraldCore

final class SymbolBrowserStateTests: XCTestCase {
    private func catalog() -> SymbolCatalog {
        SymbolCatalog(names: ["bell", "bell.fill", "wifi", "star", "envelope"], terms: ["envelope": ["mail"]],
                      categories: [SymbolCategory(key: "communication", title: "Communication", icon: "message"),
                                   SymbolCategory(key: "connectivity", title: "Connectivity", icon: "wifi")],
                      categoryKeys: ["bell": ["communication"], "bell.fill": ["communication"],
                                     "envelope": ["communication"], "wifi": ["connectivity"]])
    }

    func testScopesAndSearchCombine() {
        let sl = SymbolShortlist(defaults: UserDefaults(suiteName: "herald-browser-\(UUID().uuidString)")!)
        sl.noteUsed("wifi"); sl.noteUsed("star"); sl.toggleFavorite("bell")
        var s = SymbolBrowserState()
        XCTAssertEqual(s.visible(catalog: catalog(), shortlist: sl).count, 5)
        s.scope = .recents; XCTAssertEqual(s.visible(catalog: catalog(), shortlist: sl), ["star", "wifi"])
        s.scope = .favorites; XCTAssertEqual(s.visible(catalog: catalog(), shortlist: sl), ["bell"])
        s.scope = .category("communication")
        XCTAssertEqual(Set(s.visible(catalog: catalog(), shortlist: sl)), ["bell", "bell.fill", "envelope"])
        s.query = "fill"; XCTAssertEqual(s.visible(catalog: catalog(), shortlist: sl), ["bell.fill"])
        s.query = "mail"; XCTAssertEqual(s.visible(catalog: catalog(), shortlist: sl), ["envelope"], "keywords work inside a category")
        s.scope = .favorites; s.query = "zzz"; XCTAssertEqual(s.visible(catalog: catalog(), shortlist: sl), [])
    }

    func testGridSizeIsClamped() {
        XCTAssertEqual(SymbolBrowserState.clampedGridSize(1), SymbolBrowserState.gridSizeRange.lowerBound)
        XCTAssertEqual(SymbolBrowserState.clampedGridSize(999), SymbolBrowserState.gridSizeRange.upperBound)
        XCTAssertEqual(SymbolBrowserState.clampedGridSize(.nan), SymbolBrowserState.defaultGridSize)
    }

    @MainActor func testModelPersistsGridSizeAndFavourites() {
        let suite = "herald-browser-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        let m = SymbolBrowserModel(catalog: catalog(), defaults: d)
        m.gridSize = 120; m.toggleFavorite("star"); m.noteUsed("bell")
        let again = SymbolBrowserModel(catalog: catalog(), defaults: UserDefaults(suiteName: suite)!)
        XCTAssertEqual(again.gridSize, 120)
        XCTAssertEqual(again.shortlist.favorites, ["star"])
        XCTAssertEqual(again.shortlist.recents, ["bell"])
        m.gridSize = 5000; XCTAssertEqual(m.gridSize, SymbolBrowserState.gridSizeRange.upperBound)
        m.state.scope = .favorites; XCTAssertEqual(m.results, ["star"])
        m.toggleFavorite("star"); XCTAssertEqual(m.results, [])
    }

    func testPreviewColourSpecs() {
        XCTAssertNotNil(SymbolPreviewGlyph.color("#FF8800"))
        XCTAssertNotNil(SymbolPreviewGlyph.color("accent"))
        XCTAssertNil(SymbolPreviewGlyph.color("{tint}"))
    }

    /// The whole browser drawn offscreen (no window, no focus), written to the scratch folder for a look.
    @MainActor func testBrowserRendersOffscreen() throws {
        guard let cat = SymbolCatalog.load() else { throw XCTSkip("no CoreGlyphs bundle on this machine") }
        let d = UserDefaults(suiteName: "herald-browser-\(UUID().uuidString)")!
        let m = SymbolBrowserModel(catalog: cat, defaults: d)
        m.state.scope = .category("weather")
        m.selected = "cloud.sun.rain.fill"
        m.toggleFavorite("cloud.rain")
        var style = HeraldSymbol(name: "x")
        style.weight = .bold; style.renderingMode = .palette; style.colors = ["#FF6A00", "#2D7DFF", "#34C759"]
        let view = SymbolBrowserView(model: m, style: style, onUse: { _ in }, onClose: {}, onFloat: {}, offscreen: true)
            .frame(width: 940, height: 640)
        let r = ImageRenderer(content: view)
        r.scale = 1
        let image = try XCTUnwrap(r.nsImage)
        let tiff = try XCTUnwrap(image.tiffRepresentation)
        let rep = try XCTUnwrap(NSBitmapImageRep(data: tiff))
        XCTAssertEqual(rep.pixelsWide, 940)
        XCTAssertEqual(rep.pixelsHigh, 640)
        // Drawn, not blank: more than a few distinct colours in the picture.
        var seen = Set<UInt32>()
        for y in stride(from: 0, to: 640, by: 7) { for x in stride(from: 0, to: 940, by: 7) {
            if let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) {
                seen.insert(UInt32(c.redComponent * 255) << 16 | UInt32(c.greenComponent * 255) << 8 | UInt32(c.blueComponent * 255))
            }
        } }
        XCTAssertGreaterThan(seen.count, 8)
        if let png = rep.representation(using: .png, properties: [:]) {
            let out = ProcessInfo.processInfo.environment["HERALD_SNAPSHOT_DIR"] ?? NSTemporaryDirectory()
            try png.write(to: URL(fileURLWithPath: out).appendingPathComponent("symbol-browser.png"))
        }
    }
}
