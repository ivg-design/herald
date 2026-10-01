import XCTest
@testable import HeraldCore

final class AssetStoreTests: XCTestCase {
    var root: URL!
    var store: AssetStore!
    var source: URL!      // where "the issuer's" files live

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("herald-assets-\(UUID().uuidString)")
        source = root.appendingPathComponent("issuer", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        store = AssetStore(directory: root.appendingPathComponent("assets", isDirectory: true))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    @discardableResult
    private func makeFile(_ name: String, bytes: Int = 64, fill: UInt8 = 0x52) throws -> URL {
        let url = source.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: fill, count: bytes).write(to: url)
        return url
    }

    /// A sparse file of exactly `bytes` bytes, so the size cap can be tested without writing 10 MB.
    private func makeSparse(_ name: String, bytes: UInt64) throws -> URL {
        let url = source.appendingPathComponent(name)
        FileManager.default.createFile(atPath: url.path, contents: nil)
        let h = try FileHandle(forWritingTo: url)
        try h.truncate(atOffset: bytes)
        try h.close()
        return url
    }

    private func asset(_ id: String, _ path: String, type: String = "rive") -> HeraldAsset {
        HeraldAsset(id: id, type: type, path: path, stateMachine: "Main", inputs: ["count"])
    }

    private func assertThrows(_ expected: AssetError, file: StaticString = #filePath, line: UInt = #line,
                              _ body: () throws -> Void) {
        do { try body(); XCTFail("expected \(expected)", file: file, line: line) }
        catch let e as AssetError { XCTAssertEqual(e, expected, file: file, line: line) }
        catch { XCTFail("unexpected \(error)", file: file, line: line) }
    }

    // MARK: validate

    func testValidateAcceptsRivAnyCaseAndReturnsSize() throws {
        XCTAssertEqual(try AssetStore.validate(try makeFile("a.riv", bytes: 100)), 100)
        XCTAssertEqual(try AssetStore.validate(try makeFile("B.RIV", bytes: 7)), 7)
    }

    func testValidateRejectsOtherExtensions() throws {
        for name in ["a.png", "a.riv.txt", "a", "a.rive", "riv"] {
            let url = try makeFile(name)
            assertThrows(.notRiveFile(name)) { try AssetStore.validate(url) }
        }
    }

    func testValidateSizeCapIsInclusive() throws {
        let exact = try makeSparse("exact.riv", bytes: UInt64(AssetStore.maxBytes))
        XCTAssertEqual(try AssetStore.validate(exact), AssetStore.maxBytes)
        let over = try makeSparse("over.riv", bytes: UInt64(AssetStore.maxBytes) + 1)
        assertThrows(.tooLarge(name: "over.riv", bytes: AssetStore.maxBytes + 1, limit: AssetStore.maxBytes)) {
            try AssetStore.validate(over)
        }
    }

    func testValidateRejectsMissingEmptyAndFolders() throws {
        assertThrows(.missing(source.appendingPathComponent("nope.riv").path)) {
            try AssetStore.validate(source.appendingPathComponent("nope.riv"))
        }
        assertThrows(.empty("zero.riv")) { try AssetStore.validate(try makeFile("zero.riv", bytes: 0)) }
        let dir = source.appendingPathComponent("folder.riv", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        assertThrows(.notAFile("folder.riv")) { try AssetStore.validate(dir) }
    }

    func testValidateChecksWhatASymlinkPointsAt() throws {
        let secret = try makeFile("secret.txt")
        let link = source.appendingPathComponent("link.riv")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: secret)
        assertThrows(.notRiveFile("link.riv")) { try AssetStore.validate(link) }

        let real = try makeFile("real.riv", bytes: 9)
        let good = source.appendingPathComponent("good.riv")
        try FileManager.default.createSymbolicLink(at: good, withDestinationURL: real)
        XCTAssertEqual(try AssetStore.validate(good), 9)
    }

    // MARK: install

    func testInstallCopiesIntoTheAppFolder() throws {
        let src = try makeFile("bell.riv", bytes: 300, fill: 0x41)
        let dest = try store.install(asset("bell", src.path), app: "webwatcher.email")
        XCTAssertEqual(dest, store.folder(for: "webwatcher.email").appendingPathComponent("bell.riv"))
        XCTAssertEqual(try Data(contentsOf: dest), try Data(contentsOf: src))
        XCTAssertEqual(dest.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent, "assets")
        XCTAssertEqual(store.list(app: "webwatcher.email").map(\.lastPathComponent), ["bell.riv"])
    }

    func testInstallAcceptsFileURLs() throws {
        let src = try makeFile("bell.riv")
        let dest = try store.install(asset("bell", src.absoluteString), app: "a")
        XCTAssertEqual(try Data(contentsOf: dest), try Data(contentsOf: src))
    }

    func testInstallRefusesWrongTypeExtensionAndRemotePaths() throws {
        let png = try makeFile("pic.png")
        assertThrows(.unsupportedType("image")) { try store.install(asset("p", png.path, type: "image"), app: "a") }
        assertThrows(.notRiveFile("pic.png")) { try store.install(asset("p", png.path), app: "a") }
        assertThrows(.badPath("remote assets are not supported: https://example.com/a.riv")) {
            try store.install(asset("p", "https://example.com/a.riv"), app: "a")
        }
        assertThrows(.badPath("an asset needs an id")) { try store.install(asset(" ", try makeFile("x.riv").path), app: "a") }
        XCTAssertTrue(store.list(app: "a").isEmpty, "nothing is stored for a refused asset")
    }

    func testInstallRefusesOversizedFiles() throws {
        let big = try makeSparse("big.riv", bytes: UInt64(AssetStore.maxBytes) + 1)
        XCTAssertThrowsError(try store.install(asset("big", big.path), app: "a")) { error in
            guard case .tooLarge(let name, _, let limit)? = error as? AssetError else { return XCTFail("\(error)") }
            XCTAssertEqual(name, "big.riv"); XCTAssertEqual(limit, 10 * 1024 * 1024)
        }
        XCTAssertTrue(store.list(app: "a").isEmpty)
    }

    func testInstallRefreshesOnlyWhenTheContentChanged() throws {
        let src = try makeFile("bell.riv", bytes: 50, fill: 1)
        let dest = try store.install(asset("bell", src.path), app: "a")
        let first = try FileManager.default.attributesOfItem(atPath: dest.path)[.modificationDate] as? Date

        Thread.sleep(forTimeInterval: 0.05)
        _ = try store.install(asset("bell", src.path), app: "a")
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: dest.path)[.modificationDate] as? Date, first,
                       "an unchanged source is not copied again")

        try Data(repeating: 2, count: 80).write(to: src)
        _ = try store.install(asset("bell", src.path), app: "a")
        XCTAssertEqual(try Data(contentsOf: dest), Data(repeating: 2, count: 80))
        XCTAssertEqual(store.list(app: "a").count, 1)
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: store.folder(for: "a").path)
        XCTAssertEqual(leftovers, ["bell.riv"], "no temp files are left behind")
    }

    func testIdsAndAppsCannotEscapeTheStore() throws {
        let src = try makeFile("bell.riv")
        let dest = try store.install(asset("../../evil", src.path), app: "../../app")
        let base = store.directory.resolvingSymlinksInPath().path
        XCTAssertTrue(dest.resolvingSymlinksInPath().path.hasPrefix(base + "/"), "\(dest.path) is outside \(base)")
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("evil.riv").path))
        // Different spellings stay different files.
        let other = try store.install(asset("a_b", src.path), app: "x")
        let slashed = try store.install(asset("a/b", src.path), app: "x")
        XCTAssertNotEqual(other, slashed)
    }

    func testPerAppLimit() throws {
        let src = try makeFile("bell.riv")
        for i in 0..<AssetStore.maxAssetsPerApp { try store.install(asset("a\(i)", src.path), app: "a") }
        assertThrows(.limitReached(AssetStore.maxAssetsPerApp)) { try store.install(asset("one-too-many", src.path), app: "a") }
        // An existing id can still be refreshed, and another app has its own budget.
        XCTAssertNoThrow(try store.install(asset("a0", src.path), app: "a"))
        XCTAssertNoThrow(try store.install(asset("one", src.path), app: "b"))
    }

    func testInstallAllReportsEachAsset() throws {
        let good = try makeFile("good.riv")
        let png = try makeFile("pic.png")
        let manifest = HeraldManifest(app: "m", appName: "M", assets: [
            asset("good", good.path), asset("bad", png.path), asset("gone", source.appendingPathComponent("gone.riv").path)])
        let results = store.installAll(manifest)
        XCTAssertEqual(results.map(\.id), ["good", "bad", "gone"])
        XCTAssertEqual(results.map(\.ok), [true, false, false])
        XCTAssertEqual(results[1].error, .notRiveFile("pic.png"))
        guard case .missing? = results[2].error else { return XCTFail("\(String(describing: results[2].error))") }
        XCTAssertEqual(store.list(app: "m").map(\.lastPathComponent), ["good.riv"])
    }

    func testRemoveManifestKeepsHandDroppedFiles() throws {
        let src = try makeFile("bell.riv")
        let manifest = HeraldManifest(app: "m", appName: "M", assets: [asset("bell", src.path)])
        store.installAll(manifest)
        let mine = store.folder(for: "m").appendingPathComponent("mine.riv")
        try Data([1, 2, 3]).write(to: mine)
        XCTAssertEqual(store.remove(manifest: manifest), 1)
        XCTAssertEqual(store.remove(manifest: manifest), 0)
        XCTAssertEqual(store.list(app: "m").map(\.lastPathComponent), [mine.lastPathComponent])
    }

    // MARK: locate / resolve

    func testLocateRelativePathsStayInsideTheAppFolder() throws {
        let folder = store.folder(for: "a")
        XCTAssertEqual(try store.locate(path: "bell.riv", app: "a"), folder.appendingPathComponent("bell.riv"))
        XCTAssertEqual(try store.locate(path: "sub/bell.riv", app: "a"),
                       folder.appendingPathComponent("sub").appendingPathComponent("bell.riv"))
        assertThrows(.badPath("a relative asset path cannot leave the app's assets folder: ../x.riv")) {
            _ = try store.locate(path: "../x.riv", app: "a")
        }
        assertThrows(.badPath("a relative asset path cannot leave the app's assets folder: a/../../x.riv")) {
            _ = try store.locate(path: "a/../../x.riv", app: "a")
        }
        assertThrows(.badPath("the asset path is empty")) { _ = try store.locate(path: "  ", app: "a") }
        XCTAssertEqual(try store.locate(path: "/tmp/x.riv", app: "a").path, "/tmp/x.riv")
        XCTAssertEqual(try store.locate(path: "~/x.riv", app: "a").path, NSHomeDirectory() + "/x.riv")
    }

    func testResolveAssetInstallsLazilyFromTheManifest() throws {
        let src = try makeFile("bell.riv", bytes: 33)
        let manifest = HeraldManifest(app: "a", appName: "A", assets: [asset("bell", src.path)])
        let url = try store.resolve(HeraldRiveComponent(asset: "bell"), app: "a", manifest: manifest)
        XCTAssertEqual(url, store.storedURL(app: "a", assetID: "bell"))
        XCTAssertEqual(try AssetStore.validate(url), 33)

        // The issuer's file goes away: the stored copy keeps the banner playing.
        try FileManager.default.removeItem(at: src)
        XCTAssertEqual(try store.resolve(HeraldRiveComponent(asset: "bell"), app: "a", manifest: manifest), url)
        // And with no manifest at all, the stored copy still answers.
        XCTAssertEqual(try store.resolve(HeraldRiveComponent(asset: "bell"), app: "a", manifest: nil), url)
    }

    func testResolveAssetFailsWithAReadableReason() throws {
        assertThrows(.unknownAsset("ghost")) { _ = try store.resolve(HeraldRiveComponent(asset: "ghost"), app: "a", manifest: nil) }
        let manifest = HeraldManifest(app: "a", appName: "A", assets: [asset("bell", try makeFile("pic.png").path)])
        assertThrows(.notRiveFile("pic.png")) { _ = try store.resolve(HeraldRiveComponent(asset: "bell"), app: "a", manifest: manifest) }
        assertThrows(.unknownAsset("other")) { _ = try store.resolve(HeraldRiveComponent(asset: "other"), app: "a", manifest: manifest) }
        assertThrows(.noSource) { _ = try store.resolve(HeraldRiveComponent(), app: "a", manifest: manifest) }
        XCTAssertNotNil(AssetError.noSource.errorDescription)
        XCTAssertTrue(AssetError.tooLarge(name: "big.riv", bytes: 12 * 1_048_576, limit: AssetStore.maxBytes)
            .errorDescription!.contains("12 MB"))
    }

    func testResolvePathUsesTheFileInPlaceOrTheAppFolder() throws {
        let src = try makeFile("direct.riv", bytes: 12)
        XCTAssertEqual(try store.resolve(HeraldRiveComponent(path: src.path), app: "a", manifest: nil), src)
        XCTAssertTrue(store.list(app: "a").isEmpty, "a template path is used where it is, not copied")

        let dropped = store.folder(for: "a").appendingPathComponent("dropped.riv")
        try FileManager.default.createDirectory(at: dropped.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data([9, 9]).write(to: dropped)
        XCTAssertEqual(try store.resolve(HeraldRiveComponent(path: "dropped.riv"), app: "a", manifest: nil), dropped)

        assertThrows(.notRiveFile("direct.png")) {
            _ = try store.resolve(HeraldRiveComponent(path: try makeFile("direct.png").path), app: "a", manifest: nil)
        }
    }

    // MARK: Rive input binding

    func testPointerKeywords() {
        XCTAssertEqual(RiveInputBinding.pointerKeyword("hover"), "hover")
        XCTAssertEqual(RiveInputBinding.pointerKeyword(" Pressed "), "pressed")
        XCTAssertNil(RiveInputBinding.pointerKeyword("{hover}"))
        XCTAssertNil(RiveInputBinding.pointerKeyword("count"))
        XCTAssertNil(RiveInputBinding.value(for: "hover", fields: ["hover": .bool(true)]), "a keyword is never data")
    }

    func testSingleTokenKeepsTheFieldsOwnType() {
        let fields: [String: HeraldFieldValue] = ["count": .number(3), "unread": .bool(true), "to": .list(["a", "b"]),
                                                  "who.name": .text("Ann"), "blank": .text("  ")]
        XCTAssertEqual(RiveInputBinding.value(for: "{count}", fields: fields), .number(3))
        XCTAssertEqual(RiveInputBinding.value(for: " {unread} ", fields: fields), .bool(true))
        XCTAssertEqual(RiveInputBinding.value(for: "{to}", fields: fields), .list(["a", "b"]))
        XCTAssertEqual(RiveInputBinding.value(for: "{who.name}", fields: fields), .text("Ann"))
    }

    func testMixedAndLiteralBindingsBindAsText() {
        let fields: [String: HeraldFieldValue] = ["count": .number(3), "who": .text("Ann")]
        XCTAssertEqual(RiveInputBinding.value(for: "{count} from {who}", fields: fields), .text("3 from Ann"))
        XCTAssertEqual(RiveInputBinding.value(for: "5", fields: fields), .text("5"))
        XCTAssertEqual(RiveInputBinding.value(for: "{count}{count}", fields: fields), .text("33"))
    }

    func testAbsentOrBlankTokensBindToNothing() {
        let fields: [String: HeraldFieldValue] = ["blank": .text("  "), "none": .list([])]
        XCTAssertNil(RiveInputBinding.value(for: "{missing}", fields: fields))
        XCTAssertNil(RiveInputBinding.value(for: "{blank}", fields: fields))
        XCTAssertNil(RiveInputBinding.value(for: "{none}", fields: fields))
        XCTAssertNil(RiveInputBinding.value(for: "{missing} {blank}", fields: fields))
        XCTAssertNil(RiveInputBinding.value(for: "", fields: fields))
    }

    func testNumberCoercion() {
        XCTAssertEqual(RiveInputBinding.number(from: .number(2.5)), 2.5)
        XCTAssertEqual(RiveInputBinding.number(from: .bool(true)), 1)
        XCTAssertEqual(RiveInputBinding.number(from: .bool(false)), 0)
        XCTAssertEqual(RiveInputBinding.number(from: .text(" 7 ")), 7)
        XCTAssertEqual(RiveInputBinding.number(from: .list(["a", "b", "c"])), 3)
        XCTAssertNil(RiveInputBinding.number(from: .text("many")))
        XCTAssertNil(RiveInputBinding.number(from: .text("nan")))
        XCTAssertNil(RiveInputBinding.number(from: .number(.infinity)))
    }

    func testTruthiness() {
        XCTAssertTrue(RiveInputBinding.truthy(.bool(true)))
        XCTAssertFalse(RiveInputBinding.truthy(.bool(false)))
        XCTAssertTrue(RiveInputBinding.truthy(.number(2)))
        XCTAssertFalse(RiveInputBinding.truthy(.number(0)))
        XCTAssertTrue(RiveInputBinding.truthy(.list(["x"])))
        XCTAssertFalse(RiveInputBinding.truthy(.list([])))
        for s in ["", " ", "false", "FALSE", "no", "Off", "0"] { XCTAssertFalse(RiveInputBinding.truthy(.text(s)), "\(s)") }
        for s in ["true", "yes", "1", "Acme"] { XCTAssertTrue(RiveInputBinding.truthy(.text(s)), "\(s)") }
    }
}
