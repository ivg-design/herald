import XCTest
import AppKit
@testable import HeraldCore

/// Herald's own icon export and the SF Symbol tiles (issues #84, #86).
final class IconArtTests: XCTestCase {
    private var root: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("herald-iconart-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDown() { try? FileManager.default.removeItem(at: root) }

    static let artwork: NSImage = {
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return NSImage(contentsOf: repo.appendingPathComponent("Resources/Assets.xcassets/AppIcon.appiconset/icon_256x256@2x.png"))!
    }()

    func testTheExportedAppIconIsTheArtworkNotTheSystemPlaceholder() throws {
        let png = try XCTUnwrap(IconArt.appIconPNG(candidates: [{ NSWorkspace.shared.icon(for: .applicationBundle) }, { Self.artwork }]))
        let rep = try XCTUnwrap(NSBitmapImageRep(data: png))
        XCTAssertEqual(rep.pixelsWide, 256); XCTAssertEqual(rep.pixelsHigh, 256)
        XCTAssertGreaterThanOrEqual(IconArt.opaqueFraction(of: png), 0.30)
        XCTAssertFalse(IconArt.isGenericApplicationIcon(png))
        XCTAssertTrue(IconArt.isUsableAppIcon(png))
    }

    func testThePlaceholderAndEmptyImagesAreNeverExported() {
        let generic = NSWorkspace.shared.icon(for: .applicationBundle)
        let blank = NSImage(size: NSSize(width: 256, height: 256))
        XCTAssertNil(IconArt.appIconPNG(candidates: [{ generic }, { blank }, { nil }]))
        let generic256 = IconArt.genericApplicationPNG()!
        XCTAssertTrue(IconArt.isGenericApplicationIcon(generic256))
        XCTAssertFalse(IconArt.isUsableAppIcon(generic256))
    }

    func testAGenericIconFileFromAnEarlyExportIsReplacedByTheRealIcon() throws {
        let registry = AppRegistry(file: root.appendingPathComponent("apps.json"))
        let file = HeraldIdentity.iconFile(in: root)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try IconArt.genericApplicationPNG()!.write(to: file)
        let good = try XCTUnwrap(IconArt.png(of: Self.artwork))
        HeraldIdentity.ensureRegistered(registry: registry, supportDirectory: root, iconPNG: good)
        XCTAssertEqual(try Data(contentsOf: file), good)
        // a good file stays
        HeraldIdentity.ensureRegistered(registry: registry, supportDirectory: root, iconPNG: IconArt.symbolTilePNG(symbol: "key"))
        XCTAssertEqual(try Data(contentsOf: file), good)
    }

    func testSymbolTilesAreRealPictures() throws {
        for s in ["cloud", "key", "terminal"] {
            let png = try XCTUnwrap(IconArt.symbolTilePNG(symbol: s))
            XCTAssertGreaterThanOrEqual(IconArt.opaqueFraction(of: png), 0.5, s)
            XCTAssertFalse(IconArt.isGenericApplicationIcon(png))
        }
        XCTAssertNotEqual(IconArt.symbolTilePNG(symbol: "cloud"), IconArt.symbolTilePNG(symbol: "key"))
    }
}
