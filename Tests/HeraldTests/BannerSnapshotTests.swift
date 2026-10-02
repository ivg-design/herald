import XCTest
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import HeraldClient
@testable import HeraldCore

// Issue #34: automated coverage for what a banner looks like.
//
// The SwiftUI renderer (`GridBannerView`, drawn offscreen by `PreviewRenderer` for `POST /v1/preview`) lives in
// the Xcode app target, which the package test host cannot link. So the visual tests here talk to a running
// Debug Herald over the same HTTP preview route the Designer, the MCP and agents use, and compare the PNG with a
// reference stored in Tests/Fixtures. They are opt-in:
//
//   HERALD_UI_TESTS=1                       run the live tests (without it they are skipped)
//   HERALD_UI_APP=/path/to/Herald.app       launch that build on a free port with a throwaway support folder
//                                           (otherwise an instance that is already running is used: set
//                                           HERALD_SUPPORT_DIR, and HERALD_PORT if its port file is not there)
//   HERALD_UI_RECORD=1                      write the references instead of comparing against them
//
//   xcodegen generate && xcodebuild -project Herald.xcodeproj -scheme Herald -configuration Debug \
//     -derivedDataPath /tmp/herald-dd build CODE_SIGNING_ALLOWED=NO
//   HERALD_UI_TESTS=1 HERALD_UI_APP=/tmp/herald-dd/Build/Products/Debug/Herald.app swift test --filter BannerSnapshotTests
//
// Everything that does not need the app (the PNG comparator, the fixture inventory, the collapse/keep matrix and
// the action overflow rules through the pure solver) always runs under plain `swift test`.
//
// References are pixels, so they depend on the macOS version's text rendering. The comparison is tolerant (a few
// stray pixels and a small mean difference pass, see `PNGCompare.Tolerance`); after an OS update that moves text
// by more than that, re-record and look at the diff in git before committing.

// MARK: - Reference images and the comparator

/// Pixels of an image as 8-bit premultiplied sRGB RGBA, so two PNGs compare the same whatever their encoding.
struct Bitmap {
    var width: Int
    var height: Int
    var pixels: [UInt8]

    init(width: Int, height: Int, pixels: [UInt8]) { self.width = width; self.height = height; self.pixels = pixels }

    init?(png: Data) {
        guard let source = CGImageSourceCreateWithData(png as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        let w = image.width, h = image.height
        guard w > 0, h > 0, let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        var px = [UInt8](repeating: 0, count: w * h * 4)
        let drawn = px.withUnsafeMutableBytes { raw -> Bool in
            guard let ctx = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard drawn else { return nil }
        self.init(width: w, height: h, pixels: px)
    }

    func pixel(_ x: Int, _ y: Int) -> (r: Int, g: Int, b: Int, a: Int) {
        let i = (y * width + x) * 4
        return (Int(pixels[i]), Int(pixels[i + 1]), Int(pixels[i + 2]), Int(pixels[i + 3]))
    }

    func pngData() -> Data? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        var copy = pixels
        let image: CGImage? = copy.withUnsafeMutableBytes { raw in
            CGContext(data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage()
        }
        guard let image else { return nil }
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, nil)
        return CGImageDestinationFinalize(dest) ? out as Data : nil
    }
}

enum PNGCompare {
    /// How far an image may stray from its reference and still match.
    struct Tolerance {
        /// A pixel differs when any of its channels is further than this from the reference (0 to 255).
        var channelThreshold = 12
        /// At most this share of the pixels may differ (a clock that ticked over, text anti-aliasing).
        var maxDifferingFraction = 0.004
        /// Mean absolute difference per channel, over all pixels (0 to 255).
        var maxMeanDifference = 1.0
        static let standard = Tolerance()
        static let exact = Tolerance(channelThreshold: 0, maxDifferingFraction: 0, maxMeanDifference: 0)
        /// For two renders of the same request: the renderer's resampling jitters a few pixels by 1 or 2 levels.
        static let sameRequest = Tolerance(channelThreshold: 4, maxDifferingFraction: 0.0005, maxMeanDifference: 0.05)
    }

    struct Result {
        var sizeMatches: Bool
        var differing: Int
        var total: Int
        var meanDifference: Double
        var largest: Int
        var tolerance: Tolerance

        var differingFraction: Double { total == 0 ? 0 : Double(differing) / Double(total) }
        var matches: Bool {
            sizeMatches && differingFraction <= tolerance.maxDifferingFraction && meanDifference <= tolerance.maxMeanDifference
        }
        var summary: String {
            guard sizeMatches else { return "image sizes differ" }
            return String(format: "%d of %d pixels differ by more than %d (%.3f%%, allowed %.3f%%), mean difference %.3f (allowed %.3f), largest %d",
                          differing, total, tolerance.channelThreshold, differingFraction * 100,
                          tolerance.maxDifferingFraction * 100, meanDifference, tolerance.maxMeanDifference, largest)
        }
    }

    static func compare(_ actual: Bitmap, _ reference: Bitmap, tolerance: Tolerance = .standard) -> Result {
        guard actual.width == reference.width, actual.height == reference.height else {
            return Result(sizeMatches: false, differing: 0, total: 0, meanDifference: 0, largest: 0, tolerance: tolerance)
        }
        let total = actual.width * actual.height
        var differing = 0, sum = 0, largest = 0
        actual.pixels.withUnsafeBufferPointer { a in
            reference.pixels.withUnsafeBufferPointer { b in
                var i = 0
                while i < total * 4 {
                    var worst = 0
                    for c in 0..<3 {
                        let d = abs(Int(a[i + c]) - Int(b[i + c]))
                        sum += d
                        worst = max(worst, d)
                    }
                    let alpha = abs(Int(a[i + 3]) - Int(b[i + 3]))
                    worst = max(worst, alpha)
                    largest = max(largest, worst)
                    if worst > tolerance.channelThreshold { differing += 1 }
                    i += 4
                }
            }
        }
        return Result(sizeMatches: true, differing: differing, total: total,
                      meanDifference: Double(sum) / Double(max(total * 3, 1)), largest: largest, tolerance: tolerance)
    }

    /// The actual image with every pixel that differs from the reference painted red, for a failure report.
    static func diffImage(_ actual: Bitmap, _ reference: Bitmap, threshold: Int) -> Bitmap? {
        guard actual.width == reference.width, actual.height == reference.height else { return nil }
        var out = actual
        var i = 0
        while i < actual.pixels.count {
            let worst = (0..<4).map { abs(Int(actual.pixels[i + $0]) - Int(reference.pixels[i + $0])) }.max() ?? 0
            if worst > threshold { out.pixels[i] = 255; out.pixels[i + 1] = 0; out.pixels[i + 2] = 0; out.pixels[i + 3] = 255 }
            i += 4
        }
        return out
    }

    /// Pixel size from the IHDR chunk, without decoding the image.
    static func size(ofPNG data: Data) -> (width: Int, height: Int)? {
        guard data.count >= 24, Array(data.prefix(8)) == [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A] else { return nil }
        func be(_ at: Int) -> Int { data[at...(at + 3)].reduce(0) { ($0 << 8) | Int($1) } }
        return (be(16), be(20))
    }
}

/// The reference PNGs in Tests/Fixtures (next to this test folder).
enum Fixtures {
    static let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Fixtures", isDirectory: true)
    static func url(_ name: String) -> URL { directory.appendingPathComponent(name + ".png") }

    /// Every reference the live tests use, so a missing or damaged one is caught without the app.
    static var all: [String] {
        var names: [String] = []
        for template in BuiltinTemplates.names {
            for appearance in BannerSnapshotTests.appearances {
                names.append("\(template.replacingOccurrences(of: ".", with: "-"))-\(appearance)")
            }
        }
        for appearance in BannerSnapshotTests.appearances { names.append("grid3x4-\(appearance)") }
        names += ["matrix-collapse-light", "matrix-keep-light"]
        names += ["actions-row-6-light", "actions-row-max2-light", "actions-wrap-6-light", "actions-stack-max2-light"]
        return names
    }
}

// MARK: - A running Herald for the live tests

/// The Herald the live tests render with: one that is already running, or the build named by HERALD_UI_APP,
/// launched once for the whole run on a free port with its own support folder (so the installed Herald, its
/// history and its token are never touched) and quit when the run ends.
enum LiveHerald {
    struct Unavailable: Error, CustomStringConvertible { var description: String }

    private static let lock = NSLock()
    private static var cached: Result<HeraldClient, Unavailable>?
    private static var process: Process?
    private static var folder: URL?

    static func client() throws -> HeraldClient {
        lock.lock(); defer { lock.unlock() }
        if let cached { return try cached.get() }
        let made = Result { try start() }.mapError { Unavailable(description: "\($0)") }
        cached = made
        return try made.get()
    }

    static func shutdown() {
        lock.lock(); defer { lock.unlock() }
        if let process, process.isRunning { process.terminate(); process.waitUntilExit() }
        process = nil
        if let folder { try? FileManager.default.removeItem(at: folder) }
        folder = nil
        cached = nil
    }

    private static func start() throws -> HeraldClient {
        let env = ProcessInfo.processInfo.environment
        guard let app = env["HERALD_UI_APP"], !app.isEmpty else {
            let client = HeraldClient(port: env["HERALD_PORT"].flatMap(Int.init))
            guard waitForHealth(client, seconds: 3) else {
                throw Unavailable(description: "no Herald answers on port \(client.port) (support folder \(client.supportDirectory.path)). "
                    + "Start a Debug build with HERALD_PORT and HERALD_SUPPORT_DIR set, point these tests at it with the same variables, "
                    + "or set HERALD_UI_APP=/path/to/Herald.app to let the tests launch it.")
            }
            return client
        }

        var executable = URL(fileURLWithPath: (app as NSString).expandingTildeInPath)
        if executable.pathExtension == "app" { executable.appendPathComponent("Contents/MacOS/Herald") }
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw Unavailable(description: "HERALD_UI_APP does not point at a Herald build: \(executable.path)")
        }
        guard let port = env["HERALD_UI_PORT"].flatMap(Int.init) ?? freePort() else {
            throw Unavailable(description: "no free loopback port for the test instance")
        }
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("herald-ui-tests-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        folder = dir

        let p = Process()
        p.executableURL = executable
        var childEnv = env
        childEnv["HERALD_PORT"] = String(port)
        childEnv["HERALD_SUPPORT_DIR"] = dir.path
        p.environment = childEnv
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try p.run()
        process = p

        let client = HeraldClient(supportDirectory: dir, port: port)
        guard waitForHealth(client, seconds: 30) else {
            throw Unavailable(description: "\(executable.lastPathComponent) did not answer on port \(port) within 30 s")
        }
        return client
    }

    private static func waitForHealth(_ client: HeraldClient, seconds: Int) -> Bool {
        let deadline = Date().addingTimeInterval(TimeInterval(seconds))
        while Date() < deadline {
            if client.token != nil, client.isAvailable { return true }
            Thread.sleep(forTimeInterval: 0.4)
        }
        return false
    }

    private static func freePort() -> Int? {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = 0
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        let size = socklen_t(MemoryLayout<sockaddr_in>.size)
        let bound = withUnsafePointer(to: &addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, size) } }
        guard bound == 0 else { return nil }
        var length = size
        let named = withUnsafeMutablePointer(to: &addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &length) } }
        guard named == 0 else { return nil }
        return Int(UInt16(bigEndian: addr.sin_port))
    }
}

// MARK: - Live snapshot tests

/// Renders templates through a running Debug Herald and compares them with the references (see the header).
final class BannerSnapshotTests: XCTestCase {
    static let appearances = ["light", "dark"]
    static let app = "ui-tests"

    override class func tearDown() {
        registered = false
        LiveHerald.shutdown()
        super.tearDown()
    }

    override func setUpWithError() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["HERALD_UI_TESTS"] == "1",
                          "live banner tests are opt-in: HERALD_UI_TESTS=1 (and HERALD_UI_APP=/path/to/Herald.app, see BannerSnapshotTests.swift)")
        continueAfterFailure = true
    }

    // MARK: Data

    /// A deterministic picture for `{image}`: a diagonal gradient, as a data URI.
    static let pictureURI: String = {
        let w = 160, h = 160
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let colors = [CGColor(red: 0.95, green: 0.55, blue: 0.20, alpha: 1), CGColor(red: 0.25, green: 0.35, blue: 0.85, alpha: 1)] as CFArray
        let gradient = CGGradient(colorsSpace: space, colors: colors, locations: [0, 1])!
        ctx.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: w, y: h), options: [])
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.9))
        ctx.fillEllipse(in: CGRect(x: 50, y: 50, width: 60, height: 60))
        let out = NSMutableData()
        let dest = CGImageDestinationCreateWithData(out, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
        CGImageDestinationFinalize(dest)
        return "data:image/png;base64," + (out as Data).base64EncodedString()
    }()

    /// The test app's icon, registered so the preview draws it. Without one Herald draws a letter tile whose hue
    /// comes from `String.hashValue`, which Swift seeds per process: the same app would be a different colour in
    /// every run and no reference could hold.
    static let iconURI: String = {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = CGContext(data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 0.20, green: 0.55, blue: 0.60, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fillEllipse(in: CGRect(x: 18, y: 18, width: 28, height: 28))
        let out = NSMutableData()
        let dest = CGImageDestinationCreateWithData(out, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
        CGImageDestinationFinalize(dest)
        return "data:image/png;base64," + (out as Data).base64EncodedString()
    }()

    static func json(_ text: String) -> JSONValue {
        do { return try HeraldJSON.decoder().decode(JSONValue.self, from: Data(text.utf8)) }
        catch { fatalError("bad test JSON: \(error)") }
    }

    /// What every built-in layout is drawn with: all the standard fields, a picture and three buttons.
    static var builtinData: JSONValue {
        var o: [String: JSONValue] = [
            "title": .string("Build finished"),
            "subtitle": .string("herald / main"),
            "body": .string("All 214 tests passed in 38 s. [Open the log](https://example.com/log)"),
            "image": .string(pictureURI),
            "buttons": json(#"[{"label":"Open","url":"https://example.com"},{"label":"Rerun","callback":{}},{"label":"Dismiss","style":"cancel"}]"#),
        ]
        o["url"] = .string("https://example.com/build/214")
        o["frozenClock"] = .string(frozenClock)
        return .object(o)
    }

    /// A 3 x 4 grid of the kind the Designer makes: an image over two rows, a title and a badge, a subtitle and the
    /// issuer icon, an action row. No clock, so the picture is the same every minute.
    static let grid3x4 = """
    {"name":"grid-3x4","app":"\(app)","layoutVersion":2,"collapseEmpty":true,
     "grid":{"rows":3,"cols":4,"rowSizes":["auto","auto","auto"],"colSizes":["72","fill","fill","56"],"gap":8,"padding":14,"width":400},
     "cells":[
      {"id":"img","row":0,"col":0,"rowSpan":2,"component":{"type":"image","binding":"{image}","fit":"cover","cornerRadius":10,"aspectRatio":1}},
      {"id":"title","row":0,"col":1,"colSpan":2,"component":{"type":"text","binding":"{title}","style":"title","maxLines":2}},
      {"id":"badge","row":0,"col":3,"align":"topTrailing","component":{"type":"badge","binding":"{count}","color":"#E53935"}},
      {"id":"sub","row":1,"col":1,"colSpan":2,"component":{"type":"text","binding":"{subtitle}","style":"subtitle","maxLines":2}},
      {"id":"icon","row":1,"col":3,"align":"topTrailing","component":{"type":"issuerIcon","size":22,"shape":"rounded"}},
      {"id":"acts","row":2,"col":0,"colSpan":4,"component":{"type":"actions","source":"issuer","layout":"row","maxVisible":4}}]}
    """

    static var grid3x4Data: JSONValue {
        json("""
        {"title":"2 new invoices","subtitle":"Acme Billing \\u00b7 #4021","count":2,"image":"\(pictureURI)",
         "buttons":[{"label":"Open","url":"https://example.com"},{"label":"Mark paid","callback":{}}]}
        """)
    }

    // MARK: Rendering and comparing

    private func render(_ template: JSONValue, data: JSONValue, appearance: String = "light", scale: Double = 1,
                        client: HeraldClient) async throws -> Data {
        try await client.preview(HeraldPreviewRequest(template: template, app: Self.app, data: data,
                                                      appearance: appearance, scale: scale))
    }

    private static let registrationLock = NSLock()
    private static var registered = false

    /// The live instance, with the test app registered (once per run) so its icon is a fixed picture.
    private func client() async throws -> HeraldClient {
        let client: HeraldClient
        do { client = try LiveHerald.client() }
        catch { XCTFail("\(error)"); throw error }
        Self.registrationLock.lock()
        let needed = !Self.registered
        Self.registrationLock.unlock()
        if needed {
            try await client.register(HeraldAppRegistration(app: Self.app, appName: "UI Tests", icon: Self.iconURI))
            Self.registrationLock.lock(); Self.registered = true; Self.registrationLock.unlock()
        }
        return client
    }

    /// Compares `png` with the reference `name`, or writes the reference when HERALD_UI_RECORD=1. On a mismatch the
    /// actual image and a diff (differing pixels in red) are written to a temp folder and attached to the report.
    private func assertSnapshot(_ png: Data, named name: String, tolerance: PNGCompare.Tolerance = .standard,
                                file: StaticString = #filePath, line: UInt = #line) {
        let reference = Fixtures.url(name)
        guard let actual = Bitmap(png: png) else {
            return XCTFail("\(name): the preview is not a decodable PNG", file: file, line: line)
        }
        if ProcessInfo.processInfo.environment["HERALD_UI_RECORD"] == "1" {
            do {
                try FileManager.default.createDirectory(at: Fixtures.directory, withIntermediateDirectories: true)
                try png.write(to: reference)
                print("recorded \(reference.path) (\(actual.width) x \(actual.height))")
            } catch { XCTFail("\(name): cannot write the reference: \(error)", file: file, line: line) }
            return
        }
        guard let stored = try? Data(contentsOf: reference), let expected = Bitmap(png: stored) else {
            return XCTFail("\(name): no reference at \(reference.path); record it with HERALD_UI_RECORD=1", file: file, line: line)
        }
        let result = PNGCompare.compare(actual, expected, tolerance: tolerance)
        guard !result.matches else { return }

        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("herald-ui-tests-failures", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let actualURL = folder.appendingPathComponent(name + "-actual.png")
        try? png.write(to: actualURL)
        add(XCTAttachment(data: png, uniformTypeIdentifier: UTType.png.identifier))
        var message = "\(name): \(result.summary). Actual: \(actualURL.path)"
        if let diff = PNGCompare.diffImage(actual, expected, threshold: tolerance.channelThreshold)?.pngData() {
            let diffURL = folder.appendingPathComponent(name + "-diff.png")
            try? diff.write(to: diffURL)
            add(XCTAttachment(data: diff, uniformTypeIdentifier: UTType.png.identifier))
            message += ", diff: \(diffURL.path)"
        }
        XCTFail(message, file: file, line: line)
    }

    private func pixelSize(_ png: Data, _ what: String, file: StaticString = #filePath, line: UInt = #line) -> (width: Int, height: Int) {
        guard let size = PNGCompare.size(ofPNG: png) else {
            XCTFail("\(what): not a PNG", file: file, line: line)
            return (0, 0)
        }
        return size
    }

    // MARK: Layouts

    /// Today at 09:41 in the local time zone: what the frozen clock shows, whatever the time of day or the zone
    /// ("9:41 AM", or "09:41" in a 24-hour locale: a timestamp on the day of delivery is only a time).
    static let frozenClock: String = {
        var parts = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        parts.hour = 9; parts.minute = 41; parts.second = 0
        return ISODate.string(from: Calendar.current.date(from: parts) ?? Date())
    }()

    /// A built-in template whose timestamp reads a fixed `{frozenClock}` field instead of the delivery time: same
    /// cell, same component, same style. The live clock's text width moves everything to its right by fractions
    /// of a point (imageRight puts the picture there), so with a live clock the picture's edges would differ from
    /// minute to minute and no tolerance short of "ignore the picture" could hold. Every other cell is the
    /// built-in's.
    static func builtinWithFrozenClock(_ name: String) throws -> HeraldTemplate {
        var template = try XCTUnwrap(BuiltinTemplates.named(name, app: app), "\(name) is not a built-in template")
        var replaced = false
        for i in template.cells.indices where template.cells[i].id == "time" {
            template.cells[i].component = .timestamp(HeraldTimestampComponent(binding: "{frozenClock}", style: .caption, fontSize: 10))
            replaced = true
        }
        XCTAssertTrue(replaced, "\(name) has no `time` cell to freeze")
        template.name = "frozen-" + name.replacingOccurrences(of: ".", with: "-")
        return template
    }

    /// Every built-in template (`builtin.imageLeft`, `imageRight`, `hero`, `compact`) in both appearances, drawn
    /// with a frozen clock (see `builtinWithFrozenClock`), and the same built-in asked for by name draws the same
    /// card (width exactly, height to a pixel).
    func testEveryBuiltinTemplateMatchesItsReference() async throws {
        let client = try await client()
        XCTAssertEqual(BuiltinTemplates.names.count, 4, "a new built-in template needs references: add it to Fixtures.all")
        for name in BuiltinTemplates.names {
            let frozen = try Self.builtinWithFrozenClock(name)
            for appearance in Self.appearances {
                let reference = "\(name.replacingOccurrences(of: ".", with: "-"))-\(appearance)"
                let png = try await client.preview(HeraldPreviewRequest(template: frozen, data: Self.builtinData,
                                                                         appearance: appearance, scale: 1))
                assertSnapshot(png, named: reference)

                let byName = try await render(.string(name), data: Self.builtinData, appearance: appearance, client: client)
                let (a, b) = (pixelSize(png, reference), pixelSize(byName, "\(reference) by name"))
                // The live clock's text is a different width than "9:41 AM", which can move a line break or round a
                // line height by a pixel; the card itself is the same.
                XCTAssertEqual(a.width, b.width, "\(name) by name is as wide as its frozen-clock twin")
                XCTAssertLessThanOrEqual(abs(a.height - b.height), 2, "\(name) by name (\(b.height) px) is as tall as its frozen-clock twin (\(a.height) px)")
            }
        }
    }

    func testCustom3x4GridMatchesItsReference() async throws {
        let client = try await client()
        for appearance in Self.appearances {
            let png = try await render(Self.json(Self.grid3x4), data: Self.grid3x4Data, appearance: appearance, client: client)
            assertSnapshot(png, named: "grid3x4-\(appearance)")
            let size = pixelSize(png, "grid3x4-\(appearance)")
            XCTAssertEqual(size.width, 400 + 32, "the card is the grid's width plus the preview's 16 pt frame on each side")
        }
    }

    // MARK: SF Symbols (issue #45)

    private static func symbolTemplate(_ symbol: String) -> JSONValue {
        json(##"{"name":"sym","app":"\##(app)","layoutVersion":2,"grid":{"rows":1,"cols":2,"rowSizes":["auto"],"colSizes":[60,"fill"],"gap":8,"padding":14,"width":240},"cells":[{"id":"i","row":0,"col":0,"component":{"type":"iconButton","size":36,"symbol":\##(symbol),"action":{"id":"d","label":"D","kind":"dismiss"}}},{"id":"t","row":0,"col":1,"component":{"type":"text","binding":"{title}"}}]}"##)
    }

    /// Counts pixels near a colour (so a hierarchical red symbol and a palette red + blue one can be told apart).
    private func count(_ png: Data, near rgb: (Int, Int, Int)) throws -> Int {
        let bmp = try XCTUnwrap(Bitmap(png: png))
        var n = 0
        for y in 0..<bmp.height { for x in 0..<bmp.width {
            let p = bmp.pixel(x, y)
            if abs(p.r - rgb.0) < 40, abs(p.g - rgb.1) < 40, abs(p.b - rgb.2) < 40, p.a > 200 { n += 1 }
        } }
        return n
    }

    func testHierarchicalAndPaletteSymbolsRenderTheirColours() async throws {
        let client = try await client()
        let data = Self.json(#"{"title":"Symbols"}"#)
        let hier = try await render(Self.symbolTemplate(##"{"name":"bell.badge.fill","renderingMode":"hierarchical","colors":["#FF3B30"],"weight":"bold"}"##), data: data, client: client)
        let pal = try await render(Self.symbolTemplate(##"{"name":"bell.badge.fill","renderingMode":"palette","colors":["#FF3B30","#007AFF"],"weight":"bold"}"##), data: data, client: client)
        let mono = try await render(Self.symbolTemplate(#""bell.badge.fill""#), data: data, client: client)
        assertSnapshot(hier, named: "symbol-hierarchical-light")
        assertSnapshot(pal, named: "symbol-palette-light")
        XCTAssertGreaterThan(try count(hier, near: (255, 59, 48)), 2, "hierarchical draws the red")
        XCTAssertEqual(try count(hier, near: (0, 122, 255)), 0, "and no blue")
        XCTAssertGreaterThan(try count(pal, near: (255, 59, 48)), 2, "palette draws the first colour")
        XCTAssertGreaterThan(try count(pal, near: (0, 122, 255)), 2, "and the second")
        XCTAssertEqual(try count(mono, near: (255, 59, 48)), 0, "a plain name keeps the current look")
    }

    /// The references are only useful if the same request draws (almost) the same pixels twice.
    func testTheSameRequestRendersTheSameImage() async throws {
        let client = try await client()
        let a = try await render(Self.json(Self.grid3x4), data: Self.grid3x4Data, client: client)
        let b = try await render(Self.json(Self.grid3x4), data: Self.grid3x4Data, client: client)
        let result = PNGCompare.compare(try XCTUnwrap(Bitmap(png: a)), try XCTUnwrap(Bitmap(png: b)), tolerance: .sameRequest)
        XCTAssertTrue(result.matches, result.summary)
    }

    /// ImageRenderer cannot draw an AppKit-backed view (an `NSViewRepresentable`, even one hidden in a
    /// `.background`): it paints its stand-in instead, a saturated yellow with a "prohibited" sign, over the whole
    /// card. Every `/v1/preview` PNG, and so the Designer, `render_preview` and these references, would be ruined
    /// by one such view in the banner. A healthy preview has transparent corners (the backdrop is clipped to a
    /// rounded rectangle) and nothing that yellow.
    func testPreviewShowsNoImageRendererPlaceholder() async throws {
        let client = try await client()
        for appearance in Self.appearances {
            let png = try await render(Self.json(Self.grid3x4), data: Self.grid3x4Data, appearance: appearance, client: client)
            let bitmap = try XCTUnwrap(Bitmap(png: png))
            for (x, y) in [(1, 1), (bitmap.width - 2, 1), (1, bitmap.height - 2), (bitmap.width - 2, bitmap.height - 2)] {
                XCTAssertLessThan(bitmap.pixel(x, y).a, 128, "\(appearance): the corner at \(x),\(y) is painted: a view in the banner is one ImageRenderer cannot draw (an NSViewRepresentable?)")
            }
            var yellow = 0
            for y in 0..<bitmap.height { for x in 0..<bitmap.width {
                let p = bitmap.pixel(x, y)
                if p.a > 200, p.r > 230, (170...225).contains(p.g), p.b < 60 { yellow += 1 }
            } }
            XCTAssertEqual(yellow, 0, "\(appearance): \(yellow) pixels are ImageRenderer's placeholder yellow")
        }
    }

    // MARK: Collapse / keep

    /// Title, subtitle and body, one row each, full width. The subtitle is the cell under test.
    private func matrixTemplate(collapseEmpty: Bool, subtitleBehavior: String?) -> JSONValue {
        let behavior = subtitleBehavior.map { #","emptyBehavior":"\#($0)""# } ?? ""
        return Self.json("""
        {"name":"matrix","app":"\(Self.app)","layoutVersion":2,"collapseEmpty":\(collapseEmpty),
         "grid":{"rows":3,"cols":4,"rowSizes":["auto","auto","auto"],"colSizes":["fill","fill","fill","fill"],"gap":8,"padding":14,"width":400},
         "cells":[
          {"id":"title","row":0,"col":0,"colSpan":4,"component":{"type":"text","binding":"{title}","style":"title","maxLines":1}},
          {"id":"sub","row":1,"col":0,"colSpan":4,"component":{"type":"text","binding":"{subtitle}","style":"subtitle","maxLines":1\(behavior)}},
          {"id":"body","row":2,"col":0,"colSpan":4,"component":{"type":"text","binding":"{body}","style":"body","maxLines":2}}]}
        """)
    }

    /// The documented rule (TEMPLATES.md, "Collapse semantics"): an empty component takes its own
    /// `emptyBehavior`, else the template's `collapseEmpty`; collapse removes its row and the gap, keep leaves the
    /// banner the shape it has with data. All six combinations, measured on the real renderer.
    func testCollapseKeepMatrixOnTheRealRenderer() async throws {
        let client = try await client()
        let full = Self.json(#"{"title":"Title","subtitle":"Subtitle","body":"Body text"}"#)
        let empty = Self.json(#"{"title":"Title","body":"Body text"}"#)
        func height(collapseEmpty: Bool, _ behavior: String?, data: JSONValue) async throws -> Int {
            let png = try await render(matrixTemplate(collapseEmpty: collapseEmpty, subtitleBehavior: behavior), data: data, client: client)
            return pixelSize(png, "matrix \(collapseEmpty) \(behavior ?? "default")").height
        }
        // data present: nothing collapses, whatever the settings
        let withData = try await height(collapseEmpty: true, nil, data: full)
        let dataKeepDefault = try await height(collapseEmpty: false, nil, data: full)
        let dataCollapseOverride = try await height(collapseEmpty: true, "collapse", data: full)
        let dataKeepOverride = try await height(collapseEmpty: false, "keep", data: full)
        XCTAssertEqual(dataKeepDefault, withData)
        XCTAssertEqual(dataCollapseOverride, withData)
        XCTAssertEqual(dataKeepOverride, withData)

        // collapsed: the template default, the component's own override, or both
        let collapsed = try await height(collapseEmpty: true, nil, data: empty)
        let collapsedOwn = try await height(collapseEmpty: true, "collapse", data: empty)
        let collapsedOverKeeping = try await height(collapseEmpty: false, "collapse", data: empty)
        XCTAssertEqual(collapsedOwn, collapsed)
        XCTAssertEqual(collapsedOverKeeping, collapsed, "the component overrides a template that keeps")

        // kept: the template default, the component's own override, or both
        let kept = try await height(collapseEmpty: false, nil, data: empty)
        let keptOwn = try await height(collapseEmpty: false, "keep", data: empty)
        let keptOverCollapsing = try await height(collapseEmpty: true, "keep", data: empty)
        XCTAssertEqual(keptOwn, kept)
        XCTAssertEqual(keptOverCollapsing, kept, "the component overrides a template that collapses")

        XCTAssertEqual(kept, withData, "a kept empty row holds its place, so the banner keeps the shape it has with data")
        XCTAssertLessThan(collapsed, kept, "a collapsed row is gone")
        XCTAssertGreaterThan(kept - collapsed, 8, "collapsing removes the row and its 8 pt gap")

        assertSnapshot(try await render(matrixTemplate(collapseEmpty: true, subtitleBehavior: nil), data: empty, client: client),
                       named: "matrix-collapse-light")
        assertSnapshot(try await render(matrixTemplate(collapseEmpty: false, subtitleBehavior: nil), data: empty, client: client),
                       named: "matrix-keep-light")
    }

    // MARK: Action row overflow

    /// A title over an `actions` row; `width` is the banner's.
    private func actionsTemplate(layout: String, maxVisible: Int?, width: Int = 400) -> JSONValue {
        let cap = maxVisible.map { #","maxVisible":\#($0)"# } ?? ""
        return Self.json("""
        {"name":"actions","app":"\(Self.app)","layoutVersion":2,"collapseEmpty":true,
         "grid":{"rows":2,"cols":1,"rowSizes":["auto","auto"],"colSizes":["fill"],"gap":8,"padding":14,"width":\(width)},
         "cells":[
          {"id":"title","row":0,"col":0,"component":{"type":"text","binding":"{title}","style":"title","maxLines":1}},
          {"id":"acts","row":1,"col":0,"component":{"type":"actions","source":"issuer","layout":"\(layout)"\(cap)}}]}
        """)
    }

    private static func buttons(_ count: Int) -> JSONValue {
        let labels = ["Open bid", "Mark seen", "Follow up", "Archive", "Snooze day", "Escalate", "Reassign", "Delete"]
        let items = labels.prefix(count).map { #"{"label":"\#($0)","url":"https://example.com/\#($0.count)"}"# }
        return json(#"{"title":"Overflow","buttons":[\#(items.joined(separator: ","))]}"#)
    }

    /// Six buttons do not fit one 400 pt line. `row` keeps to one line and puts the rest behind "+N", `wrap` flows
    /// onto more lines, `stack` takes one per line, `maxVisible` caps all three; and whatever the buttons, the
    /// banner stays as wide as its grid.
    func testActionRowOverflowOnTheRealRenderer() async throws {
        let client = try await client()
        func png(_ layout: String, _ cap: Int?, buttons count: Int = 6, width: Int = 400) async throws -> Data {
            try await render(actionsTemplate(layout: layout, maxVisible: cap, width: width), data: Self.buttons(count), client: client)
        }
        let oneButton = pixelSize(try await png("row", nil, buttons: 1), "one button")
        let row6 = try await png("row", nil)
        let rowCap2 = try await png("row", 2)
        let wrap6 = try await png("wrap", nil)
        let wrapCap2 = try await png("wrap", 2)
        let stack6 = try await png("stack", nil)
        let stackCap2 = try await png("stack", 2)
        let stackCap1 = try await png("stack", 1)

        // One line stays one line: six buttons in a row are as tall as one.
        XCTAssertEqual(pixelSize(row6, "row 6").height, oneButton.height, "row overflows into +N instead of growing")
        XCTAssertEqual(pixelSize(rowCap2, "row cap 2").height, oneButton.height)
        XCTAssertGreaterThan(pixelSize(wrap6, "wrap 6").height, oneButton.height, "wrap flows onto a second line")
        XCTAssertEqual(pixelSize(wrapCap2, "wrap cap 2").height, oneButton.height, "maxVisible applies to wrap too: two buttons and +4 fit one line")
        XCTAssertGreaterThan(pixelSize(stack6, "stack 6").height, pixelSize(wrap6, "wrap 6").height)
        XCTAssertLessThan(pixelSize(stackCap2, "stack cap 2").height, pixelSize(stack6, "stack 6").height)
        XCTAssertLessThan(pixelSize(stackCap1, "stack cap 1").height, pixelSize(stackCap2, "stack cap 2").height)

        // The cap changes what is drawn, not only how much room it takes.
        let uncapped = try XCTUnwrap(Bitmap(png: row6)), capped = try XCTUnwrap(Bitmap(png: rowCap2))
        XCTAssertFalse(PNGCompare.compare(uncapped, capped).matches, "maxVisible: 2 draws fewer buttons than none")

        // Never wider than the grid, however many buttons and however narrow the banner.
        for width in [280, 300, 400] {
            for count in [1, 6, 8] {
                let size = pixelSize(try await png("row", nil, buttons: count, width: width), "row \(count) buttons at \(width)")
                XCTAssertEqual(size.width, width + 32, "\(count) buttons in a \(width) pt banner")
                XCTAssertEqual(size.height, oneButton.height, "\(count) buttons in a \(width) pt banner stay on one line")
            }
        }

        assertSnapshot(row6, named: "actions-row-6-light")
        assertSnapshot(rowCap2, named: "actions-row-max2-light")
        assertSnapshot(wrap6, named: "actions-wrap-6-light")
        assertSnapshot(stackCap2, named: "actions-stack-max2-light")
    }
}

// MARK: - The comparator and the fixture inventory (no app needed)

final class SnapshotInfrastructureTests: XCTestCase {
    private func solid(_ w: Int, _ h: Int, _ rgb: (UInt8, UInt8, UInt8)) -> Bitmap {
        var px = [UInt8](repeating: 255, count: w * h * 4)
        for i in 0..<(w * h) { px[i * 4] = rgb.0; px[i * 4 + 1] = rgb.1; px[i * 4 + 2] = rgb.2 }
        return Bitmap(width: w, height: h, pixels: px)
    }

    private func paint(_ b: inout Bitmap, x: Range<Int>, y: Range<Int>, _ rgb: (UInt8, UInt8, UInt8)) {
        for yy in y { for xx in x {
            let i = (yy * b.width + xx) * 4
            b.pixels[i] = rgb.0; b.pixels[i + 1] = rgb.1; b.pixels[i + 2] = rgb.2
        } }
    }

    func testIdenticalImagesMatchEvenExactly() {
        let a = solid(40, 30, (10, 120, 200))
        let r = PNGCompare.compare(a, a, tolerance: .exact)
        XCTAssertTrue(r.matches, r.summary)
        XCTAssertEqual(r.differing, 0)
        XCTAssertEqual(r.meanDifference, 0)
    }

    func testAnImageSurvivesAPNGRoundTrip() throws {
        var a = solid(40, 30, (10, 120, 200))
        paint(&a, x: 5..<15, y: 5..<9, (255, 255, 255))
        let png = try XCTUnwrap(a.pngData())
        let back = try XCTUnwrap(Bitmap(png: png))
        XCTAssertEqual(back.width, 40)
        XCTAssertEqual(back.height, 30)
        XCTAssertTrue(PNGCompare.compare(a, back, tolerance: .exact).matches)
        XCTAssertEqual(PNGCompare.size(ofPNG: png).map { [$0.width, $0.height] }, [40, 30])
    }

    func testAMovedBlockIsCaught() {
        var base = solid(200, 100, (240, 240, 240))
        paint(&base, x: 20..<80, y: 20..<40, (0, 0, 0))
        var moved = solid(200, 100, (240, 240, 240))
        paint(&moved, x: 20..<80, y: 24..<44, (0, 0, 0))
        let r = PNGCompare.compare(moved, base)
        XCTAssertFalse(r.matches, "a 4 px shift of a 60 x 20 block is a different banner: \(r.summary)")
        XCTAssertEqual(r.differing, 2 * 4 * 60)
        XCTAssertNotNil(PNGCompare.diffImage(moved, base, threshold: PNGCompare.Tolerance.standard.channelThreshold))
    }

    func testSmallNoiseAndAFewStrayPixelsAreTolerated() {
        let base = solid(200, 100, (200, 200, 200))
        var noisy = base
        for i in stride(from: 0, to: noisy.pixels.count, by: 4) { noisy.pixels[i] = 202 }      // +2 on one channel everywhere
        XCTAssertTrue(PNGCompare.compare(noisy, base).matches, "anti-aliasing level noise passes")
        var stray = base
        paint(&stray, x: 0..<10, y: 0..<5, (0, 0, 0))                                          // 50 of 20,000 pixels
        let r = PNGCompare.compare(stray, base)
        XCTAssertEqual(r.differing, 50)
        XCTAssertTrue(r.matches, "a clock's worth of pixels passes: \(r.summary)")
        var many = base
        paint(&many, x: 0..<40, y: 0..<10, (0, 0, 0))                                          // 400 pixels = 2%
        XCTAssertFalse(PNGCompare.compare(many, base).matches)
    }

    func testDifferentSizesNeverMatch() {
        let r = PNGCompare.compare(solid(10, 10, (1, 2, 3)), solid(10, 11, (1, 2, 3)))
        XCTAssertFalse(r.matches)
        XCTAssertFalse(r.sizeMatches)
        XCTAssertNil(PNGCompare.diffImage(solid(10, 10, (1, 2, 3)), solid(10, 11, (1, 2, 3)), threshold: 0))
    }

    func testPNGSizeReaderRejectsOtherData() {
        XCTAssertNil(PNGCompare.size(ofPNG: Data([1, 2, 3])))
        XCTAssertNil(PNGCompare.size(ofPNG: Data(repeating: 0, count: 64)))
    }

    /// Every reference the live tests compare against is committed, decodes, and is a plausible banner.
    func testEveryReferenceImageIsPresentAndReadable() throws {
        XCTAssertEqual(Set(Fixtures.all).count, Fixtures.all.count, "reference names are unique")
        for name in Fixtures.all {
            let data = try XCTUnwrap(try? Data(contentsOf: Fixtures.url(name)), "missing reference Tests/Fixtures/\(name).png: record with HERALD_UI_RECORD=1")
            let bitmap = try XCTUnwrap(Bitmap(png: data), "\(name).png is not a readable PNG")
            XCTAssertTrue((200...800).contains(bitmap.width), "\(name): width \(bitmap.width)")
            XCTAssertTrue((40...600).contains(bitmap.height), "\(name): height \(bitmap.height)")
            // The banner sits on the preview's gradient backdrop: no reference is blank or one flat colour.
            let first = bitmap.pixels.prefix(4)
            XCTAssertTrue(stride(from: 0, to: bitmap.pixels.count, by: 4).contains { Array(bitmap.pixels[$0..<($0 + 4)]) != Array(first) },
                          "\(name) is a flat image")
        }
    }
}

// MARK: - Collapse / keep: the pure arithmetic

/// The same matrix as `testCollapseKeepMatrixOnTheRealRenderer`, through the model the renderer is built on:
/// `HeraldTemplate.plan` decides what collapses, `GridSolver` turns that into sizes. The oracle is the documented
/// rule written out independently, so a change to either half shows up. Runs without the app.
final class CollapseKeepMatrixTests: XCTestCase {
    private let line = 16.0, gap = 8.0, pad = 14.0, width = 400.0

    private let behaviors: [HeraldEmptyBehavior?] = [nil, .collapse, .keep]

    private func effective(_ override: HeraldEmptyBehavior?, collapseEmpty: Bool) -> HeraldEmptyBehavior {
        override ?? (collapseEmpty ? .collapse : .keep)
    }

    /// A kept empty cell is drawn blank and holds one line, like the renderer's; a collapsed one has no frame.
    private func measure(_ cells: [HeraldCell], badgeWidth: Double = 0) -> GridMeasure {
        GridMeasure(idealWidth: { cells[$0].id == "badge" ? badgeWidth : 0 }, height: { _, _ in self.line })
    }

    private func text(_ binding: String, _ behavior: HeraldEmptyBehavior?) -> HeraldComponent {
        .text(HeraldTextComponent(binding: binding, emptyBehavior: behavior))
    }

    // MARK: Rows

    func testEveryRowCombinationFollowsTheRule() throws {
        let tokens = ["title", "subtitle", "body"]
        for target in 0..<3 {
            for collapseEmpty in [true, false] {
                for override in behaviors {
                    for hasData in [true, false] {
                        let label = "row \(target), collapseEmpty \(collapseEmpty), override \(String(describing: override)), data \(hasData)"
                        let grid = HeraldGrid(rows: 3, cols: 4, rowSizes: [.auto, .auto, .auto],
                                              colSizes: [.fill, .fill, .fill, .fill], gap: gap, padding: pad, width: width)
                        let cells = (0..<3).map { r in
                            HeraldCell(id: "c\(r)", row: r, col: 0, rowSpan: 1, colSpan: 4,
                                       component: text("{\(tokens[r])}", r == target ? override : nil))
                        }
                        let template = HeraldTemplate(name: "m", app: "a", grid: grid, cells: cells, collapseEmpty: collapseEmpty)
                        var fields: [String: HeraldFieldValue] = [:]
                        for (r, t) in tokens.enumerated() where hasData || r != target { fields[t] = .text("x") }

                        // The oracle.
                        let collapses = !hasData && effective(override, collapseEmpty: collapseEmpty) == .collapse
                        let live = (0..<3).filter { !(collapses && $0 == target) }
                        let expectedHeight = 2 * pad + Double(live.count) * line + gap * Double(live.count - 1)

                        let plan = template.plan(fields: fields, actions: [])
                        XCTAssertEqual(plan.collapsedRows, collapses ? [target] : [], label)
                        XCTAssertEqual(plan.collapsedCells, collapses ? ["c\(target)"] : [], label)
                        XCTAssertTrue(plan.collapsedCols.isEmpty, label)

                        let s = GridSolver.solve(grid: grid, cells: cells, plan: plan, measure: measure(cells))
                        XCTAssertEqual(s.height, expectedHeight, accuracy: 0.001, label)
                        XCTAssertEqual(s.rowHeights[target], collapses ? 0 : line, label)
                        // Each live row starts after the live rows above it and their gaps.
                        for (position, r) in live.enumerated() {
                            let frame = try XCTUnwrap(s.frames[r], "\(label): row \(r) should be drawn")
                            XCTAssertEqual(frame.y, pad + Double(position) * (line + gap), accuracy: 0.001, "\(label): row \(r)")
                            XCTAssertEqual(frame.height, line, accuracy: 0.001, label)
                        }
                        if collapses { XCTAssertNil(s.frames[target], label) }
                    }
                }
            }
        }
    }

    /// A row that no cell touches collapses only under `collapseEmpty` (it has no component to say "keep").
    func testARowWithNoCellFollowsTheTemplateDefault() {
        let grid = HeraldGrid(rows: 3, cols: 1, rowSizes: [.auto, .auto, .auto], colSizes: [.fill], gap: gap, padding: pad, width: width)
        let cells = [HeraldCell(id: "a", row: 0, col: 0, component: text("{title}", nil)),
                     HeraldCell(id: "c", row: 2, col: 0, component: text("{body}", nil))]
        let fields: [String: HeraldFieldValue] = ["title": .text("x"), "body": .text("y")]
        let collapsing = HeraldTemplate(name: "m", app: "a", grid: grid, cells: cells, collapseEmpty: true)
        let keeping = HeraldTemplate(name: "m", app: "a", grid: grid, cells: cells, collapseEmpty: false)
        XCTAssertEqual(collapsing.plan(fields: fields, actions: []).collapsedRows, [1])
        XCTAssertEqual(keeping.plan(fields: fields, actions: []).collapsedRows, [])
        let kept = GridSolver.solve(grid: grid, cells: cells, plan: keeping.plan(fields: fields, actions: []), measure: measure(cells))
        let gone = GridSolver.solve(grid: grid, cells: cells, plan: collapsing.plan(fields: fields, actions: []), measure: measure(cells))
        XCTAssertEqual(kept.height - gone.height, gap, accuracy: 0.001, "an empty kept row is zero tall but its gap stays")
    }

    // MARK: Columns

    /// One row: a 40 pt label column, two fill columns, an auto badge column. The badge is the cell under test:
    /// collapsed, its column and gap go and the fill columns take the room.
    func testEveryColumnCombinationFollowsTheRule() throws {
        let badgeWidth = 30.0
        for collapseEmpty in [true, false] {
            for override in behaviors {
                for hasData in [true, false] {
                    let label = "collapseEmpty \(collapseEmpty), override \(String(describing: override)), data \(hasData)"
                    let grid = HeraldGrid(rows: 1, cols: 4, rowSizes: [.auto], colSizes: [.points(40), .fill, .fill, .auto],
                                          gap: gap, padding: pad, width: width)
                    let cells = [
                        HeraldCell(id: "label", row: 0, col: 0, component: .issuerIcon(HeraldIssuerIconComponent())),
                        HeraldCell(id: "t1", row: 0, col: 1, component: text("{title}", nil)),
                        HeraldCell(id: "t2", row: 0, col: 2, component: text("{subtitle}", nil)),
                        HeraldCell(id: "badge", row: 0, col: 3, component: .badge(HeraldBadgeComponent(binding: "{count}", emptyBehavior: override))),
                    ]
                    let template = HeraldTemplate(name: "m", app: "a", grid: grid, cells: cells, collapseEmpty: collapseEmpty)
                    var fields: [String: HeraldFieldValue] = ["title": .text("x"), "subtitle": .text("y")]
                    if hasData { fields["count"] = .number(3) }

                    let collapses = !hasData && effective(override, collapseEmpty: collapseEmpty) == .collapse
                    let plan = template.plan(fields: fields, actions: [])
                    XCTAssertEqual(plan.collapsedCols, collapses ? [3] : [], label)
                    XCTAssertTrue(plan.collapsedRows.isEmpty, label)

                    let s = GridSolver.solve(grid: grid, cells: cells, plan: plan, measure: measure(cells, badgeWidth: hasData ? badgeWidth : 0))   // a blank badge measures as nothing
                    let liveColumns = collapses ? 3.0 : 4.0
                    let auto = collapses || !hasData ? 0.0 : badgeWidth
                    let fill = (width - 2 * pad - gap * (liveColumns - 1) - 40 - auto) / 2
                    XCTAssertEqual(s.colWidths[1], fill, accuracy: 0.001, label)
                    XCTAssertEqual(s.colWidths[2], fill, accuracy: 0.001, label)
                    XCTAssertEqual(s.colWidths[3], collapses ? 0 : auto, accuracy: 0.001, label)
                    XCTAssertEqual(s.width, width, label)
                }
            }
        }
    }

    // MARK: Whole banners

    /// The four built-in layouts with nothing but a title keep only the title row, and a row comes back with its
    /// field: the v1 behaviour the built-ins reproduce by collapse.
    func testBuiltinLayoutsCollapseDownToTheTitleAndGrowBackWithData() {
        for layout in HeraldLayout.allCases {
            let t = BuiltinTemplates.template(layout: layout)
            let bare = t.plan(fields: ["title": .text("Hello")], actions: [])
            let present = Set(t.cells.map(\.id))     // compact has no subtitle or body cell at all
            XCTAssertTrue(bare.collapsedCells.isSuperset(of: present.intersection(["subtitle", "body", "actions"])), "\(layout)")
            XCTAssertFalse(bare.collapsedCells.contains("title"), "\(layout)")

            let rich = t.plan(fields: ["title": .text("Hello"), "subtitle": .text("There"), "body": .text("Text"), "image": .text("/tmp/a.png")],
                              actions: [HeraldResolvedAction(action: HeraldAction(id: "x", label: "X", kind: .dismiss), origin: .issuer)])
            XCTAssertTrue(rich.collapsedCells.isDisjoint(with: ["title", "subtitle", "body", "actions"]), "\(layout)")
            XCTAssertLessThan(rich.collapsedRows.count, bare.collapsedRows.count, "\(layout): rows come back with their fields")
        }
    }
}

// MARK: - Action row overflow: the pure rules

/// How many of an action row's buttons are drawn and what the "+N" menu says, and how rules change which
/// buttons those are. The wrap/row/stack geometry is measured on the real renderer above.
final class ActionsRowOverflowTests: XCTestCase {
    private func resolved(_ n: Int) -> [HeraldResolvedAction] {
        (0..<n).map { HeraldResolvedAction(action: HeraldAction(id: "a\($0)", label: "Action \($0)", kind: .url, url: "https://example.com/\($0)"), origin: .issuer) }
    }

    func testVisibleCountMatrix() {
        let caps: [Int?] = [nil, -3, 0, 1, 2, 3, 8, 100]
        for total in 0...8 {
            for cap in caps {
                let expected: Int
                if total == 0 { expected = 0 }
                else if let cap { expected = min(total, max(cap, 1)) }
                else { expected = total }
                XCTAssertEqual(ActionOverflow.visibleCount(total: total, maxVisible: cap), expected,
                               "\(total) actions, maxVisible \(String(describing: cap))")
            }
        }
    }

    func testTheCapNeverHidesEverythingAndTheMenuCountsTheRest() {
        for total in 1...8 {
            for cap in [0, 1, 2, 5] {
                let shown = ActionOverflow.visibleCount(total: total, maxVisible: cap)
                XCTAssertGreaterThanOrEqual(shown, 1, "a typo in maxVisible must not leave only a menu")
                let hidden = total - shown
                if hidden > 0 { XCTAssertEqual(ActionOverflow.menuTitle(hidden: hidden), "+\(hidden)") }
            }
        }
        XCTAssertEqual(ActionOverflow.menuTitle(hidden: 4), "+4")
    }

    func testSixIssuerButtonsWithACapOfTwoShowTwoAndHideFour() {
        let buttons = (0..<6).map { HeraldButton(label: "Button \($0)", url: "https://example.com/\($0)") }
        let n = HeraldNotification(app: "a", title: "t", buttons: buttons)
        let actions = BannerData.actions(for: n, manifest: nil, rules: [])
        XCTAssertEqual(actions.count, 6)
        let shown = ActionOverflow.visibleCount(total: actions.count, maxVisible: 2)
        XCTAssertEqual(actions.prefix(shown).map(\.action.label), ["Button 0", "Button 1"])
        XCTAssertEqual(actions.dropFirst(shown).map(\.action.label), ["Button 2", "Button 3", "Button 4", "Button 5"])
        XCTAssertEqual(ActionOverflow.menuTitle(hidden: actions.count - shown), "+4")
    }

    /// Rules decide which buttons are the visible ones: position moves one in front of the cap, hide removes it
    /// from the count, an added template action takes the last place.
    func testRulesDecideWhichButtonsSurviveTheCap() {
        let buttons = (0..<6).map { HeraldButton(label: "Button \($0)", url: "https://example.com/\($0)") }
        let n = HeraldNotification(app: "a", title: "t", buttons: buttons)

        let moved = BannerData.actions(for: n, manifest: nil, rules: [HeraldActionRule(match: "Button 5", position: 0)])
        XCTAssertEqual(moved.prefix(ActionOverflow.visibleCount(total: moved.count, maxVisible: 2)).map(\.action.label), ["Button 5", "Button 0"])

        let trimmed = BannerData.actions(for: n, manifest: nil, rules: [HeraldActionRule(match: "Button 1", hide: true), HeraldActionRule(match: "Button 2", hide: true)])
        XCTAssertEqual(trimmed.count, 4)
        XCTAssertEqual(ActionOverflow.visibleCount(total: trimmed.count, maxVisible: 4), 4, "four left, four allowed: no menu")

        let extra = HeraldAction(id: "followup", label: "Follow up", kind: .shortcut, shortcut: "Follow-up")
        let added = BannerData.actions(for: n, manifest: nil, rules: [HeraldActionRule(add: extra)])
        XCTAssertEqual(added.last?.action.id, "followup")
        XCTAssertEqual(added.last?.origin, .template)
        XCTAssertEqual(added.count, 7)
    }

    /// An `actions` component keeps only the origin it is asked for, so a template-only row is not capped by the
    /// issuer's buttons.
    func testActionSourcesSplitTheListByOrigin() {
        let extra = HeraldAction(id: "followup", label: "Follow up", kind: .shortcut, shortcut: "Follow-up")
        let n = HeraldNotification(app: "a", title: "t", buttons: (0..<3).map { HeraldButton(label: "B\($0)", url: "https://example.com") })
        let all = BannerData.actions(for: n, manifest: nil, rules: [HeraldActionRule(add: extra)])
        XCTAssertEqual(all.filter { HeraldActionSource.issuer.includes($0.origin) }.count, 3)
        XCTAssertEqual(all.filter { HeraldActionSource.template.includes($0.origin) }.map(\.action.id), ["followup"])
        XCTAssertEqual(all.filter { HeraldActionSource.merged.includes($0.origin) }.count, 4)
    }
}
