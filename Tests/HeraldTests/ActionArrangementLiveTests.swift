import XCTest
import HeraldClient
@testable import HeraldCore

/// Issue #58 on the real renderer: the requested layout is drawn offscreen through `POST /v1/preview` (the same
/// `GridBannerView` a live banner uses, rendered with `ImageRenderer`, no window) and the buttons' frames are read
/// back from the PNG. Opt-in like BannerSnapshotTests: HERALD_UI_TESTS=1 HERALD_UI_APP=/path/to/Herald.app.
final class ActionArrangementLiveTests: XCTestCase {
    static let app = "arrange.email"

    override func setUpWithError() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["HERALD_UI_TESTS"] == "1",
                          "live banner tests are opt-in: HERALD_UI_TESTS=1 (and HERALD_UI_APP=/path/to/Herald.app, see BannerSnapshotTests.swift)")
        continueAfterFailure = true
    }

    private func client() async throws -> HeraldClient {
        let client = try LiveHerald.client()
        try await client.register(HeraldAppRegistration(app: Self.app, appName: "Arrange", icon: BannerSnapshotTests.iconURI))
        let manifest = try HeraldJSON.decoder().decode(HeraldManifest.self, from: Data("""
        {"app":"\(Self.app)","appName":"Arrange","version":1,
         "fields":[{"key":"title","type":"text","sample":"2 new from Acme"},{"key":"sender","type":"text","sample":"Acme Billing"},
                   {"key":"subject","type":"text","sample":"Invoice 4021"}],
         "actions":[{"id":"markRead","label":"Mark as Read","kind":"callback"},{"id":"archive","label":"Archive","kind":"callback"},
                    {"id":"delete","label":"Delete","kind":"callback"},{"id":"spam","label":"Spam","kind":"callback"}]}
        """.utf8))
        try await client.putManifest(manifest)
        return client
    }

    /// The columns (in pixels, [min, max)) where button-tinted pixels run, inside the band of the last row.
    private func buttonRuns(_ bmp: Bitmap, y: ClosedRange<Int>) -> [Range<Int>] {
        var hot = [Bool](repeating: false, count: bmp.width)
        for x in 16..<(bmp.width - 16) {   // the card, not the preview's margin
            var n = 0
            for yy in y { let p = bmp.pixel(x, yy); if p.a > 200, p.b - p.r >= 20 { n += 1 } }
            hot[x] = n >= 4
        }
        var runs: [Range<Int>] = []
        var start: Int?
        var gap = 0
        for x in 16..<(bmp.width - 16) {
            if hot[x] { if start == nil { start = x }; gap = 0 }
            else if let s = start { gap += 1; if gap >= 3 { runs.append(s..<(x - gap + 1)); start = nil; gap = 0 } }
        }
        if let s = start { runs.append(s..<(bmp.width - 16)) }
        return runs
    }

    func testTheRequestedLayoutRendersTheButtonsWhereTheyAreAsked() async throws {
        let client = try await client()
        var template = ActionArrangementTests.requested.replacingOccurrences(of: "webwatcher.email", with: Self.app)
        template = template.replacingOccurrences(of: "\"collapseEmpty\":true,", with: "\"collapseEmpty\":true,\"accentColor\":\"#0000FF\",")
        let json = try HeraldJSON.decoder().decode(JSONValue.self, from: Data(template.utf8))
        let data = try HeraldJSON.decoder().decode(JSONValue.self, from: Data(
            #"{"title":"2 new from Acme","sender":"Acme Billing","subject":"Invoice 4021","actionIds":["markRead","archive","delete","spam"]}"#.utf8))

        // validate_template: no errors, and no warnings (nothing is drawn twice).
        let t = try HeraldJSON.decoder().decode(HeraldTemplate.self, from: Data(template.utf8))
        XCTAssertEqual(t.validate().map(\.message), [])

        let png = try await client.preview(HeraldPreviewRequest(template: json, app: Self.app, data: data, appearance: "light", scale: 1))
        let bmp = try XCTUnwrap(Bitmap(png: png))
        XCTAssertEqual(bmp.width, 400 + 32, "the card is the grid's width plus the preview's 16 pt frame on each side")
        let frame = 16, pad = 14
        // The button row is the last one: 24 pt tall, ending `pad` above the card's bottom edge.
        let bottom = bmp.height - frame - pad
        let runs = buttonRuns(bmp, y: (bottom - 22)...(bottom - 2))
        XCTAssertEqual(runs.count, 4, "Mark as Read, then Archive, Delete and Spam: \(runs)")
        guard runs.count == 4 else { return }

        let colOneEnd = frame + pad + 104, mergedStart = colOneEnd + 8, mergedEnd = frame + 400 - pad
        XCTAssertEqual(runs[0].lowerBound, frame + pad, accuracy: 3, "the markRead button starts at column 1")
        XCTAssertLessThanOrEqual(runs[0].upperBound, colOneEnd + 1, "and stays inside it")
        for r in runs[1...] { XCTAssertGreaterThanOrEqual(r.lowerBound, mergedStart - 1, "Archive, Delete and Spam are in the merged cell") }
        XCTAssertEqual(runs[3].upperBound, mergedEnd, accuracy: 3, "right-aligned: Spam ends at the right edge of columns 2-4")
        for i in 1..<3 { XCTAssertEqual(runs[i + 1].lowerBound - runs[i].upperBound, 6, accuracy: 3, "6 pt between buttons") }
        XCTAssertLessThan(runs[1].lowerBound, runs[2].lowerBound)
        XCTAssertLessThan(runs[2].lowerBound, runs[3].lowerBound)
        // The icon is in column 1 above the button row: some icon-coloured pixels there, none inside the merged cell.
        let iconPixels = (frame + pad..<colOneEnd).reduce(0) { n, x in
            n + (frame + pad..<(frame + pad + 56)).reduce(0) { m, y in
                let p = bmp.pixel(x, y); return m + (p.a > 200 && abs(p.r - 51) < 40 && abs(p.g - 140) < 40 && abs(p.b - 153) < 40 ? 1 : 0) }
        }
        XCTAssertGreaterThan(iconPixels, 200, "the issuer icon fills the top of column 1")
    }

    /// Alignment and spacing change the frames of the same three buttons.
    func testAlignAndSpacingMoveTheButtons() async throws {
        let client = try await client()
        func runs(align: String, spacing: Int) async throws -> [Range<Int>] {
            let template = """
            {"name":"align","app":"\(Self.app)","layoutVersion":2,"collapseEmpty":true,"accentColor":"#0000FF",
             "grid":{"rows":1,"cols":1,"rowSizes":["auto"],"colSizes":["fill"],"gap":8,"padding":14,"width":400},
             "cells":[{"id":"more","row":0,"col":0,"component":{"type":"actions","include":["archive","delete","spam"],"align":"\(align)","wrap":false,"spacing":\(spacing)}}]}
            """
            let json = try HeraldJSON.decoder().decode(JSONValue.self, from: Data(template.utf8))
            let png = try await client.preview(HeraldPreviewRequest(template: json, app: Self.app, data: .string("sample"), appearance: "light", scale: 1))
            let bmp = try XCTUnwrap(Bitmap(png: png))
            return buttonRuns(bmp, y: (16 + 14 + 2)...(16 + 14 + 22))
        }
        let left = try await runs(align: "leading", spacing: 6)
        let right = try await runs(align: "trailing", spacing: 6)
        let middle = try await runs(align: "center", spacing: 6)
        let spread = try await runs(align: "spaceBetween", spacing: 6)
        let wide = try await runs(align: "leading", spacing: 20)
        for r in [left, right, middle, spread, wide] { XCTAssertEqual(r.count, 3, "\(r)") }
        guard [left, right, middle, spread, wide].allSatisfy({ $0.count == 3 }) else { return }
        XCTAssertEqual(left[0].lowerBound, 16 + 14, accuracy: 3, "leading starts at the left edge")
        XCTAssertEqual(right[2].upperBound, 16 + 400 - 14, accuracy: 3, "trailing ends at the right edge")
        let centre = Double(middle[0].lowerBound + middle[2].upperBound) / 2
        XCTAssertEqual(centre, Double(16 + 200), accuracy: 3, "centre is the middle of the cell")
        XCTAssertEqual(spread[0].lowerBound, 16 + 14, accuracy: 3, "spaceBetween: first at the left")
        XCTAssertEqual(spread[2].upperBound, 16 + 400 - 14, accuracy: 3, "last at the right")
        XCTAssertGreaterThan(spread[1].lowerBound - spread[0].upperBound, 20, "and the gaps open up")
        XCTAssertEqual(left[1].lowerBound - left[0].upperBound, 6, accuracy: 3)
        XCTAssertEqual(wide[1].lowerBound - wide[0].upperBound, 20, accuracy: 3, "spacing sets the gap")
    }

    /// Issue #61: a fixed image (a file in the support folder) is drawn with no `image` field at all, and a prominent
    /// button is drawn filled (issue #60); both through the real renderer.
    func testAFixedImageAndAProminentButtonRender() async throws {
        let client = try await client()
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("herald-live-img-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let png = try XCTUnwrap(Data(base64Encoded: String(BannerSnapshotTests.pictureURI.dropFirst("data:image/png;base64,".count))))
        let file = dir.appendingPathComponent("fixed.png"); try png.write(to: file)
        let stored = try TemplateImageStore(directory: dir.appendingPathComponent("store")).install(file, app: Self.app)
        let template = """
        {"name":"fixed","app":"\(Self.app)","layoutVersion":2,"collapseEmpty":true,"accentColor":"#0000FF",
         "grid":{"rows":2,"cols":1,"rowSizes":["auto","auto"],"colSizes":["fill"],"gap":8,"padding":14,"width":300},
         "cells":[{"id":"pic","row":0,"col":0,"component":{"type":"image","binding":"\(stored.path)","height":60}},
                  {"id":"go","row":1,"col":0,"component":{"type":"button","actionRef":"markRead","style":"prominent"}}]}
        """
        let json = try HeraldJSON.decoder().decode(JSONValue.self, from: Data(template.utf8))
        let out = try await client.preview(HeraldPreviewRequest(template: json, app: Self.app, data: .string("sample"), appearance: "light", scale: 1))
        let bmp = try XCTUnwrap(Bitmap(png: out))
        // The picture: orange-ish gradient pixels in the first row; none if the fixed image were missing (collapsed).
        var picture = 0
        for y in 30..<90 { for x in 30..<300 { let p = bmp.pixel(x, y); if p.r > 200, p.g > 100, p.b < 120 { picture += 1 } } }
        XCTAssertGreaterThan(picture, 100, "the fixed picture is drawn without an image field")
        // The prominent button: a solid accent (blue) capsule, not a 12% tint.
        var solid = 0
        for y in 0..<bmp.height { for x in 16..<(bmp.width - 16) { let p = bmp.pixel(x, y); if p.a > 200, p.b > 200, p.r < 40, p.g < 40 { solid += 1 } } }
        XCTAssertGreaterThan(solid, 400, "prominent fills the capsule with the accent")
    }
}
