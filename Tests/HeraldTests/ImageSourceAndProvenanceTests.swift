import XCTest
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import HeraldClient
@testable import HeraldCore

/// Issue #61: the Image component's Source (issuer / fixed image / field) and the provenance every token picker
/// groups by.
final class ImageSourceAndProvenanceTests: XCTestCase {
    var dir: URL!
    override func setUp() { dir = FileManager.default.temporaryDirectory.appendingPathComponent("herald-img-\(UUID().uuidString)") }
    override func tearDown() { try? FileManager.default.removeItem(at: dir) }

    private func writePNG(_ name: String, color: CGFloat = 0.5) throws -> URL {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let ctx = CGContext(data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: color, green: 0.2, blue: 0.7, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        let url = dir.appendingPathComponent(name)
        let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, ctx.makeImage()!, nil); CGImageDestinationFinalize(dest)
        return url
    }

    // MARK: Source

    func testTheBindingSaysWhereThePictureComesFrom() {
        XCTAssertEqual(ImageSourceChoice.classify("{image}"), .issuer)
        XCTAssertEqual(ImageSourceChoice.classify(" {image} "), .issuer)
        XCTAssertEqual(ImageSourceChoice.classify(""), .issuer, "a blank binding is the default")
        XCTAssertEqual(ImageSourceChoice.classify("{thumbnail}"), .field("thumbnail"))
        XCTAssertEqual(ImageSourceChoice.classify("/Users/me/Library/Application Support/Herald/template-images/a/logo-1234.png"),
                       .fixed("/Users/me/Library/Application Support/Herald/template-images/a/logo-1234.png"))
        XCTAssertEqual(ImageSourceChoice.classify("data:image/png;base64,AAAA"), .fixed("data:image/png;base64,AAAA"))
        XCTAssertEqual(ImageSourceChoice.classify("https://x/{id}.png"), .custom("https://x/{id}.png"))
        XCTAssertEqual(ImageSourceChoice.classify("{a}{b}"), .custom("{a}{b}"))
        for c: ImageSourceChoice in [.issuer, .field("thumbnail"), .fixed("/tmp/a.png")] { XCTAssertEqual(ImageSourceChoice.classify(c.binding), c) }
    }

    func testAFixedImageIsCopiedIntoTheSupportFolderOnce() throws {
        let store = TemplateImageStore(directory: dir.appendingPathComponent("store"))
        let src = try writePNG("My Logo.png")
        let a = try store.install(src, app: "webwatcher.email")
        XCTAssertTrue(FileManager.default.fileExists(atPath: a.path))
        XCTAssertTrue(store.contains(a.path), "the copy is inside the store")
        XCTAssertTrue(store.contains(a.absoluteString), "also as a file: URL")
        XCTAssertFalse(store.contains(src.path), "the original is not")
        XCTAssertEqual(try store.install(src, app: "webwatcher.email"), a, "the same content again is the same copy")
        try FileManager.default.removeItem(at: src)
        XCTAssertTrue(FileManager.default.fileExists(atPath: a.path), "the template keeps working when the original goes")
        let other = try store.install(try writePNG("My Logo.png", color: 0.9), app: "webwatcher.email")
        XCTAssertNotEqual(other, a, "a changed file never overwrites the copy other templates point at")
        XCTAssertEqual(ImageSourceChoice.classify(a.path), .fixed(a.path))
    }

    func testOnlyPicturesAreAccepted() throws {
        let store = TemplateImageStore(directory: dir.appendingPathComponent("store"))
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let text = dir.appendingPathComponent("notes.txt"); try Data("hi".utf8).write(to: text)
        XCTAssertThrowsError(try store.install(text, app: "a")) { XCTAssertTrue("\($0)".contains("not a picture") || ($0 as? TemplateImageError)?.message.contains("not a picture") == true) }
        let fake = dir.appendingPathComponent("fake.png"); try Data("not a picture".utf8).write(to: fake)
        XCTAssertThrowsError(try store.install(fake, app: "a"))
        XCTAssertThrowsError(try store.install(dir.appendingPathComponent("missing.png"), app: "a"))
        XCTAssertThrowsError(try store.install(dir, app: "a"), "a folder")
    }

    func testAFixedPathCountsAsContentAndAnIssuerImageDoesNot() throws {
        let t = try HeraldJSON.decoder().decode(HeraldTemplate.self, from: Data("""
        {"name":"i","app":"a","layoutVersion":2,"grid":{"rows":1,"cols":2,"rowSizes":["auto"],"colSizes":["fill","fill"],"gap":8,"padding":10,"width":300},
         "cells":[{"id":"fixed","row":0,"col":0,"component":{"type":"image","binding":"/tmp/logo.png"}},
                  {"id":"issuer","row":0,"col":1,"component":{"type":"image","binding":"{image}"}}]}
        """.utf8))
        XCTAssertEqual(t.emptyCellIDs(fields: [:], actions: []), ["issuer"], "the fixed picture is there without any field; the issuer's needs one")
        XCTAssertTrue(t.validate().filter { $0.isError }.isEmpty)
    }

    // MARK: Provenance

    @MainActor func testEveryTokenHasOneOfThreeProvenances() {
        var b = DesignerBackend()
        b.manifest = { _ in HeraldManifest(app: "demo", appName: "Demo", fields: [
            HeraldField(key: "sender", type: .text, sample: .text("Acme")), HeraldField(key: "thumbnail", type: .image)]) }
        let m = DesignerModel(backend: b, app: "demo")
        m.draft.extra = ["queue": "inbox"]
        m.addCustomToken("made.up")
        func provenance(_ key: String) -> TokenSuggestion.Provenance? { m.tokenSuggestions.first { $0.key == key }?.provenance }
        XCTAssertEqual(provenance("sender"), .issuer, "a manifest field")
        XCTAssertEqual(provenance("thumbnail"), .issuer)
        XCTAssertEqual(provenance("title"), .notification, "a standard payload key")
        XCTAssertEqual(provenance("made.up"), .notification, "a key a notification may carry")
        XCTAssertEqual(provenance("extra.queue"), .fixed, "a value set in the template")
        XCTAssertEqual(TokenSuggestion.Provenance.allCases.map(\.title), [
            "From the issuer app (manifest field)", "From the notification (payload field)", "Set here (fixed value)"])
        // A dynamic token shows its sample, a fixed one its value.
        XCTAssertEqual(m.tokenSuggestions.first { $0.key == "sender" }?.sampleText, "Acme")
        XCTAssertEqual(m.tokenSuggestions.first { $0.key == "extra.queue" }?.sampleText, "inbox")
        let long = TokenSuggestion(key: "k", type: .text, group: .issuer, sample: String(repeating: "x", count: 80))
        XCTAssertEqual(long.sampleText?.count, 30, "long samples are cut for the menu")
        XCTAssertNil(TokenSuggestion(key: "k", type: nil, group: .custom, sample: nil).sampleText)
    }
}
