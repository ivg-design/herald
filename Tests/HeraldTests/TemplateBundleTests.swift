import XCTest
@testable import HeraldClient
@testable import HeraldCore

/// The `.heraldtemplate` bundle (issue #30): the zip container, packing and unpacking, installing the Rive
/// files without clobbering, and the app-side service over the real stores.
final class TemplateBundleTests: XCTestCase {
    typealias Bundle = HeraldTemplateBundle
    var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("herald-bundle-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    // MARK: Helpers

    private let limits = HeraldZip.Limits(maxEntries: 100, maxEntryBytes: 1 << 20, maxTotalBytes: 4 << 20)

    private func riveData(_ seed: UInt8, count: Int = 300) -> Data {
        Data((0..<count).map { UInt8(truncatingIfNeeded: Int($0) &* 7 &+ Int(seed)) })
    }

    @discardableResult
    private func file(_ name: String, _ data: Data, in dir: URL? = nil) throws -> URL {
        let d = dir ?? root.appendingPathComponent("src", isDirectory: true)
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        let u = d.appendingPathComponent(name)
        try data.write(to: u)
        return u
    }

    private func riveCell(_ id: String, row: Int = 0, asset: String? = nil, path: String? = nil) -> HeraldCell {
        HeraldCell(id: id, row: row, col: 0, component: .rive(HeraldRiveComponent(asset: asset, path: path, stateMachine: "Main")))
    }

    private func template(name: String = "Bell", app: String = "demo", cells: [HeraldCell]) -> HeraldTemplate {
        var t = HeraldTemplate.blank(name: name, app: app)
        t.grid = HeraldGrid(rows: 6, cols: 4)
        t.cells = cells
        return t
    }

    private func riveComponents(_ t: HeraldTemplate) -> [HeraldRiveComponent] {
        t.cells.compactMap { if case .rive(let r) = $0.component { return r }; return nil }
    }

    private func run(_ tool: String, _ args: [String]) throws -> (status: Int32, out: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe; p.standardError = pipe
        try p.run(); p.waitUntilExit()
        return (p.terminationStatus, String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self))
    }

    // MARK: Zip container

    func testZipRoundTripStoredAndDeflated() throws {
        let text = Data(String(repeating: "herald banner template ", count: 400).utf8)   // compresses well
        let noise = riveData(9, count: 40)                                                  // too small to deflate
        let entries = [HeraldZip.Entry(name: "a.txt", data: text), .init(name: "dir/b.bin", data: noise), .init(name: "empty", data: Data())]
        let zip = HeraldZip.write(entries)
        XCTAssertLessThan(zip.count, text.count, "the repetitive entry is deflated")
        XCTAssertEqual(try HeraldZip.read(zip, limits: limits), entries)
    }

    func testZipIsReadableBySystemUnzip() throws {
        let zip = HeraldZip.write([.init(name: "template.json", data: Data("{}".utf8)),
                                   .init(name: "assets/x.riv", data: Data(String(repeating: "riv", count: 500).utf8))])
        let url = root.appendingPathComponent("t.zip")
        try zip.write(to: url)
        let r = try run("/usr/bin/unzip", ["-tq", url.path])
        XCTAssertEqual(r.status, 0, r.out)
    }

    func testReadsZipsMadeBySystemTools() throws {
        let src = root.appendingPathComponent("pack", isDirectory: true)
        try file("template.json", Data("{\"a\":1}".utf8), in: src)
        try file("x.riv", Data(String(repeating: "riv", count: 800).utf8), in: src.appendingPathComponent("assets"))

        // zip(1): plain local headers.
        let z1 = root.appendingPathComponent("zip1.zip")
        let r1 = try run("/bin/sh", ["-c", "cd '\(src.path)' && /usr/bin/zip -qr '\(z1.path)' template.json assets"])
        XCTAssertEqual(r1.status, 0, r1.out)
        let e1 = try HeraldZip.read(Data(contentsOf: z1), limits: limits)
        XCTAssertEqual(Set(e1.map(\.name)), ["template.json", "assets/x.riv"])

        // ditto (Finder's Compress): data descriptors, a wrapping folder, __MACOSX entries.
        let z2 = root.appendingPathComponent("zip2.zip")
        let r2 = try run("/usr/bin/ditto", ["-c", "-k", "--keepParent", src.path, z2.path])
        XCTAssertEqual(r2.status, 0, r2.out)
        let e2 = try HeraldZip.read(Data(contentsOf: z2), limits: limits)
        XCTAssertTrue(e2.contains { $0.name == "pack/template.json" && $0.data == Data("{\"a\":1}".utf8) })
    }

    func testZipRejectsDamageAndHostileArchives() throws {
        XCTAssertThrowsError(try HeraldZip.read(Data("not a zip at all, just text".utf8), limits: limits))
        XCTAssertThrowsError(try HeraldZip.read(Data(), limits: limits))

        // Flipped content byte: the checksum catches it.
        var zip = HeraldZip.write([.init(name: "a", data: Data("hello hello hello".utf8))])
        zip[30 + 1] ^= 0xFF
        XCTAssertThrowsError(try HeraldZip.read(zip, limits: limits)) { XCTAssertTrue("\($0)".contains("corrupt") || "\($0)".contains("unsafe")) }
        var body = HeraldZip.write([.init(name: "a", data: Data("hello hello hello".utf8))])
        body[30 + 1 + 3] ^= 0xFF
        XCTAssertThrowsError(try HeraldZip.read(body, limits: limits))

        // Names that climb out of the archive, are absolute, or carry a backslash.
        for bad in ["../evil", "a/../../evil", "/etc/passwd", "a\\b", "x\u{1}y"] {
            XCTAssertThrowsError(try HeraldZip.read(HeraldZip.write([.init(name: bad, data: Data("x".utf8))]), limits: limits), bad) {
                XCTAssertEqual($0 as? HeraldZip.ZipError, .unsafeName(bad))
            }
        }
        // Duplicate names.
        XCTAssertThrowsError(try HeraldZip.read(HeraldZip.write([.init(name: "a", data: Data("1".utf8)), .init(name: "a", data: Data("2".utf8))]), limits: limits))
    }

    func testZipLimitsAreEnforcedBeforeInflating() throws {
        let big = Data(repeating: 7, count: 5000)
        let zip = HeraldZip.write([.init(name: "big", data: big)])
        XCTAssertThrowsError(try HeraldZip.read(zip, limits: .init(maxEntries: 10, maxEntryBytes: 1000, maxTotalBytes: 10_000)))
        XCTAssertThrowsError(try HeraldZip.read(HeraldZip.write([.init(name: "a", data: big), .init(name: "b", data: big)]),
                                                limits: .init(maxEntries: 10, maxEntryBytes: 6000, maxTotalBytes: 8000)))
        let many = HeraldZip.write((0..<12).map { .init(name: "f\($0)", data: Data("x".utf8)) })
        XCTAssertThrowsError(try HeraldZip.read(many, limits: .init(maxEntries: 10, maxEntryBytes: 100, maxTotalBytes: 1000))) {
            XCTAssertEqual($0 as? HeraldZip.ZipError, .tooManyEntries(10))
        }
        // An entry that lies about its size inflates to something else and fails.
        var lie = HeraldZip.write([.init(name: "big", data: big)])
        // Central directory entry: uncompressed size at offset 24 from its signature.
        let cd = lie.range(of: Data([0x50, 0x4B, 0x01, 0x02]))!.lowerBound
        lie.replaceSubrange((cd + 24)..<(cd + 28), with: [0x10, 0x00, 0x00, 0x00])
        XCTAssertThrowsError(try HeraldZip.read(lie, limits: limits))
    }

    func testCRC32KnownValue() {
        XCTAssertEqual(HeraldZip.crc32(Data("123456789".utf8)), 0xCBF4_3926)
        XCTAssertEqual(HeraldZip.crc32(Data()), 0)
    }

    // MARK: Names

    func testComponentMatchesTheStoresRule() {
        for s in ["bell", "my bell", "a/b", "a_b", ".hidden", "", "caf\u{E9}", "x.y-z_1", "../up"] {
            XCTAssertEqual(Bundle.component(s), TemplateStore.component(s), s)
        }
        XCTAssertEqual(Bundle.fileName(for: .asset("bell")), "bell.riv")
        XCTAssertEqual(Bundle.fileName(for: .asset("Bell.RIV")), "Bell.riv")
        XCTAssertEqual(Bundle.fileName(for: .path("/Users/me/art/hero.riv")), "hero.riv")
        XCTAssertTrue(Bundle.fileName(for: .path("my file.riv")).hasPrefix("my_file-"))
    }

    @MainActor func testTemplateNameHelpers() {
        XCTAssertEqual(Bundle.sanitizedTemplateName("  Mail: new/old  "), "Mail- new-old")
        XCTAssertEqual(Bundle.sanitizedTemplateName("._hidden"), "hidden")
        XCTAssertEqual(Bundle.sanitizedTemplateName("///"), "---")
        XCTAssertEqual(Bundle.sanitizedTemplateName("."), "Imported template")
        XCTAssertTrue(DesignerModel.isValidName(Bundle.sanitizedTemplateName("../../x")))
        XCTAssertEqual(Bundle.sanitizedTemplateName(String(repeating: "a", count: 300)).count, HeraldTemplateName.maxBytes)
        XCTAssertEqual(Bundle.uniqueName("Bell", taken: []), "Bell")
        XCTAssertEqual(Bundle.uniqueName("Bell", taken: ["bell"]), "Bell 2")
        XCTAssertEqual(Bundle.uniqueName("Bell", taken: ["Bell", "Bell 2", "bell 3"]), "Bell 4")
    }

    // MARK: Export and unpack

    func testRiveRefsAreUniqueAndAssetWins() {
        let t = template(cells: [riveCell("a", asset: "bell"), riveCell("b", row: 1, asset: "bell", path: "/x/other.riv"),
                                 riveCell("c", row: 2, path: "/x/hero.riv"), riveCell("d", row: 3, path: "/x/hero.riv")])
        XCTAssertEqual(Bundle.riveRefs(in: t), [.asset("bell"), .path("/x/hero.riv")])
    }

    func testExportAndUnpackRoundTrip() throws {
        let bell = riveData(1), hero = riveData(2, count: 900)
        let bellURL = try file("bell.riv", bell), heroURL = try file("hero.riv", hero)
        let t = template(cells: [riveCell("a", asset: "bell"), riveCell("b", row: 1, path: heroURL.path)])

        let out = try Bundle.export(t) { ref in
            switch ref { case .asset("bell"): return bellURL; case .path(let p): return URL(fileURLWithPath: p); default: return nil }
        }
        XCTAssertEqual(Set(out.assetFiles), ["bell.riv", "hero.riv"])
        XCTAssertTrue(out.warnings.isEmpty, "\(out.warnings)")
        // The loose path became a bundle-relative name; the asset id stays an id.
        XCTAssertEqual(riveComponents(out.template).map { $0.asset ?? $0.path }, ["bell", "hero.riv"])

        let c = try Bundle.unpack(out.data)
        XCTAssertEqual(c.template, out.template)
        XCTAssertEqual(Dictionary(uniqueKeysWithValues: c.assets.map { ($0.file, $0.data) }), ["bell.riv": bell, "hero.riv": hero])
        let names = try HeraldZip.read(out.data, limits: limits).map(\.name)
        XCTAssertEqual(names, ["bundle.json", "template.json", "assets/bell.riv", "assets/hero.riv"])
    }

    func testExportWarnsAboutMissingAndStayBehindThings() throws {
        var t = template(cells: [riveCell("a", asset: "gone"), riveCell("b", row: 1, path: "/nowhere/x.riv")])
        t.actionRules = [HeraldActionRule(add: HeraldAction(id: "s", label: "Run", kind: .script, script: "go.sh")),
                         HeraldActionRule(add: HeraldAction(id: "k", label: "Shortcut", kind: .shortcut, shortcut: "Follow up"))]
        let out = try Bundle.export(t) { _ in nil }
        XCTAssertTrue(out.assetFiles.isEmpty)
        XCTAssertEqual(out.warnings.count, 4, "\(out.warnings)")
        XCTAssertTrue(out.warnings.contains { $0.contains("gone") })
        XCTAssertTrue(out.warnings.contains { $0.contains("script") })
        XCTAssertTrue(out.warnings.contains { $0.contains("Follow up") })
        // Still a valid bundle, with the path left as it was.
        XCTAssertEqual(try Bundle.unpack(out.data).template.cells, t.cells)
    }

    func testExportTakesAFreeNameForLoosePathsAndMergesIdenticalOnes() throws {
        let a = try file("hero.riv", riveData(1), in: root.appendingPathComponent("a"))
        let b = try file("hero.riv", riveData(2), in: root.appendingPathComponent("b"))
        let same = try file("hero.riv", riveData(1), in: root.appendingPathComponent("c"))
        let assetFile = try file("hero.riv", riveData(3), in: root.appendingPathComponent("d"))
        let t = template(cells: [riveCell("1", asset: "hero"), riveCell("2", row: 1, path: a.path),
                                 riveCell("3", row: 2, path: b.path), riveCell("4", row: 3, path: same.path)])
        let out = try Bundle.export(t) { ref in
            switch ref { case .asset: return assetFile; case .path(let p): return URL(fileURLWithPath: p) }
        }
        // asset "hero" owns hero.riv; the loose files take hero-2, hero-3 (the identical third one reuses hero-2).
        XCTAssertEqual(out.assetFiles, ["hero.riv", "hero-2.riv", "hero-3.riv"])
        XCTAssertEqual(riveComponents(out.template).map { $0.asset ?? $0.path }, ["hero", "hero-2.riv", "hero-3.riv", "hero-2.riv"])
    }

    func testExportSkipsOversizeAndEmptyFiles() throws {
        let empty = try file("e.riv", Data()), notRiv = try file("x.txt", Data("hi".utf8))
        let t = template(cells: [riveCell("a", asset: "e"), riveCell("b", row: 1, asset: "x")])
        let out = try Bundle.export(t) { ref in if case .asset("e") = ref { return empty }; return notRiv }
        XCTAssertTrue(out.assetFiles.isEmpty)
        XCTAssertEqual(out.warnings.count, 2)
    }

    // MARK: Unpack validation

    private func zip(_ entries: [(String, Data)]) -> Data {
        HeraldZip.write(entries.map { HeraldZip.Entry(name: $0.0, data: $0.1) })
    }
    private func json(_ t: HeraldTemplate) throws -> Data { try HeraldJSON.encoder().encode(t) }

    func testUnpackAcceptsAHandMadeBundleAndAFinderWrappedOne() throws {
        let t = template(cells: [riveCell("a", asset: "bell")])
        let bell = riveData(4)
        let plain = zip([("template.json", try json(t)), ("assets/bell.riv", bell)])
        XCTAssertEqual(try Bundle.unpack(plain).assets, [.init(file: "bell.riv", data: bell)])

        let wrapped = zip([("Bell.heraldtemplate/template.json", try json(t)), ("Bell.heraldtemplate/assets/bell.riv", bell),
                           ("__MACOSX/Bell.heraldtemplate/._template.json", Data("junk".utf8)), ("Bell.heraldtemplate/.DS_Store", Data("x".utf8))])
        let c = try Bundle.unpack(wrapped)
        XCTAssertEqual(c.template, t)
        XCTAssertEqual(c.assets.map(\.file), ["bell.riv"])
    }

    func testUnpackRejectsBadBundles() throws {
        let t = template(cells: [])
        func fails(_ data: Data, _ why: String, file: StaticString = #filePath, line: UInt = #line) {
            XCTAssertThrowsError(try Bundle.unpack(data), why, file: file, line: line)
        }
        fails(Data("nope".utf8), "not a zip")
        fails(zip([("readme.txt", Data("x".utf8))]), "no template.json")
        fails(zip([("template.json", Data("{not json".utf8))]), "bad json")
        var noApp = t; noApp.app = " "
        fails(zip([("template.json", try json(noApp))]), "no app")
        fails(zip([("template.json", try json(t)), ("bundle.json", Data(#"{"format":"other","version":1,"app":"a","name":"n","assets":[]}"#.utf8))]), "wrong format")
        fails(zip([("template.json", try json(t)), ("bundle.json", Data(#"{"format":"heraldtemplate","version":9,"app":"a","name":"n","assets":[]}"#.utf8))]), "future version")
        fails(zip([("template.json", try json(t)), ("assets/e.riv", Data())]), "empty asset")
        fails(zip((0..<(Bundle.maxAssets + 1)).map { ("assets/f\($0).riv", Data("riv\($0)".utf8)) } + [("template.json", try json(t))]), "too many assets")
        fails(zip([("template.json", Data(repeating: 0x20, count: Bundle.maxTemplateBytes + 1))]), "huge template")
    }

    @MainActor func testUnpackIgnoresStrayEntriesAndNormalisesNames() throws {
        var t = template(name: "../../Mail: x", cells: [])
        t.app = "demo"
        let data = zip([("template.json", try json(t)), ("assets/ok.riv", riveData(1)), ("assets/readme.txt", Data("x".utf8)),
                        ("assets/nested/deep.riv", riveData(2)), ("elsewhere/other.riv", riveData(3)), ("assets/my file.riv", riveData(4))])
        let c = try Bundle.unpack(data)
        XCTAssertTrue(DesignerModel.isValidName(c.template.name), c.template.name)
        XCTAssertEqual(c.assets.count, 2)
        XCTAssertTrue(c.assets.contains { $0.file == "ok.riv" })
        XCTAssertTrue(c.assets.contains { $0.file.hasPrefix("my_file-") })
    }

    // MARK: Install

    private func contents(_ cells: [HeraldCell], _ assets: [Bundle.Asset]) -> Bundle.Contents {
        .init(template: template(cells: cells), assets: assets)
    }

    func testInstallWritesReusesAndRenames() throws {
        let folder = root.appendingPathComponent("assets/demo", isDirectory: true)
        let c = contents([riveCell("a", asset: "bell"), riveCell("b", row: 1, path: "hero.riv")],
                         [.init(file: "bell.riv", data: riveData(1)), .init(file: "hero.riv", data: riveData(2))])

        // First time: both are new.
        let first = try Bundle.installAssets(c, into: folder)
        XCTAssertEqual(Set(first.report.installed), ["bell.riv", "hero.riv"])
        XCTAssertTrue(first.report.renamed.isEmpty)
        XCTAssertEqual(first.template, c.template)
        XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent("bell.riv")), riveData(1))

        // Same bundle again: nothing new, nothing rewritten.
        let again = try Bundle.installAssets(c, into: folder)
        XCTAssertTrue(again.report.installed.isEmpty)
        XCTAssertEqual(Set(again.report.reused), ["bell.riv", "hero.riv"])

        // A different bell under the same name: the file the folder already has is not touched.
        let other = contents([riveCell("a", asset: "bell"), riveCell("b", row: 1, path: "hero.riv")],
                             [.init(file: "bell.riv", data: riveData(8)), .init(file: "hero.riv", data: riveData(2))])
        let renamed = try Bundle.installAssets(other, into: folder)
        XCTAssertEqual(renamed.report.renamed, ["bell.riv": "bell-2.riv"])
        XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent("bell.riv")), riveData(1))
        XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent("bell-2.riv")), riveData(8))
        XCTAssertEqual(riveComponents(renamed.template).first?.asset, "bell-2")
        XCTAssertEqual(riveComponents(renamed.template).last?.path, "hero.riv")

        // The same different bell once more finds its earlier copy instead of making bell-3.
        let third = try Bundle.installAssets(other, into: folder)
        XCTAssertEqual(third.report.renamed, ["bell.riv": "bell-2.riv"])
        XCTAssertTrue(third.report.installed.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent("bell-3.riv").path))
    }

    func testInstallReportsMissingAnimationsAndHonoursTheFileCap() throws {
        let folder = root.appendingPathComponent("assets/demo", isDirectory: true)
        let c = contents([riveCell("a", asset: "bell"), riveCell("b", row: 1, asset: "have")], [])
        _ = try file("have.riv", riveData(1), in: folder)
        XCTAssertEqual(try Bundle.installAssets(c, into: folder).report.missing, ["bell.riv"])

        let two = contents([], [.init(file: "x.riv", data: riveData(1)), .init(file: "y.riv", data: riveData(2))])
        XCTAssertThrowsError(try Bundle.installAssets(two, into: root.appendingPathComponent("capped"), maxFiles: 1))
    }

    // MARK: Service over the real stores

    private func service() -> (TemplateBundleService, TemplateStore, AssetStore) {
        let templates = TemplateStore(directory: root.appendingPathComponent("templates"))
        let assets = AssetStore(directory: root.appendingPathComponent("assets"))
        return (TemplateBundleService(templates: templates, assets: assets) { _ in nil }, templates, assets)
    }

    func testServiceExportsAndImportsAcrossApps() throws {
        let (svc, templates, assets) = service()
        // The issuer installed bell as an asset copy; hero is a loose file the template points at.
        let bellSrc = try file("src-bell.riv", riveData(1))
        try assets.install(HeraldAsset(id: "bell", type: "rive", path: bellSrc.path), app: "demo")
        let heroSrc = try file("hero.riv", riveData(2))
        let t = template(cells: [riveCell("a", asset: "bell"), riveCell("b", row: 1, path: heroSrc.path)])
        XCTAssertTrue(templates.put(t))

        let out = try svc.export(app: "demo", name: "Bell")
        XCTAssertEqual(Set(out.assetFiles), ["bell.riv", "hero.riv"])
        XCTAssertThrowsError(try svc.export(app: "demo", name: "Nope"))

        let p = try svc.preview(out.data, intoApp: "other")
        XCTAssertEqual(p, .init(name: "Bell", app: "other", assetFiles: ["bell.riv", "hero.riv"], nameTaken: false))
        XCTAssertTrue(try svc.preview(out.data).nameTaken)

        let r = try svc.importBundle(out.data, intoApp: "other")
        XCTAssertEqual(r.template.app, "other")
        XCTAssertEqual(r.template.name, "Bell")
        XCTAssertNil(r.renamedFrom)
        XCTAssertEqual(templates.get(app: "other", name: "Bell"), r.template)
        XCTAssertEqual(assets.list(app: "other").map(\.lastPathComponent), ["bell.riv", "hero.riv"])
        // The imported template resolves its animations through the normal asset path.
        let comps = riveComponents(r.template)
        XCTAssertEqual(try assets.resolve(comps[0], app: "other", manifest: nil).lastPathComponent, "bell.riv")
        XCTAssertEqual(try assets.resolve(comps[1], app: "other", manifest: nil).lastPathComponent, "hero.riv")
    }

    func testServiceNameConflicts() throws {
        let (svc, templates, _) = service()
        var existing = template(cells: [])
        existing.title = "mine"
        XCTAssertTrue(templates.put(existing))
        var incoming = template(cells: [])
        incoming.title = "theirs"
        let data = try Bundle.export(incoming) { _ in nil }.data

        XCTAssertThrowsError(try svc.importBundle(data, onConflict: .fail)) { XCTAssertEqual($0 as? Bundle.BundleError, .nameExists("Bell")) }
        XCTAssertEqual(templates.get(app: "demo", name: "Bell")?.title, "mine")

        let both = try svc.importBundle(data)
        XCTAssertEqual(both.template.name, "Bell 2")
        XCTAssertEqual(both.renamedFrom, "Bell")
        XCTAssertFalse(both.replaced)
        XCTAssertEqual(templates.get(app: "demo", name: "Bell")?.title, "mine")
        XCTAssertEqual(templates.get(app: "demo", name: "Bell 2")?.title, "theirs")

        let over = try svc.importBundle(data, onConflict: .replace)
        XCTAssertTrue(over.replaced)
        XCTAssertEqual(over.template.name, "Bell")
        XCTAssertEqual(templates.get(app: "demo", name: "Bell")?.title, "theirs")
        XCTAssertEqual(templates.list(app: "demo").count, 2)
    }

    func testServiceSavesThroughTheCallerAndLeavesNothingBehindOnRefusal() throws {
        let (svc, templates, assets) = service()
        let src = try file("b.riv", riveData(5))
        let t = template(cells: [riveCell("a", path: src.path)])
        XCTAssertTrue(templates.put(t))
        let data = try svc.export(t).data

        var saved: [HeraldTemplate] = []
        let r = try svc.importBundle(data, intoApp: "fresh") { saved.append($0) }
        XCTAssertEqual(saved, [r.template])
        XCTAssertNil(templates.get(app: "fresh", name: "Bell"), "a custom save replaces the store write")

        // A refused import (name taken, .fail) must not have copied any animation.
        XCTAssertTrue(templates.put(r.template))
        let before = assets.list(app: "fresh")
        XCTAssertThrowsError(try svc.importBundle(data, intoApp: "fresh", onConflict: .fail))
        XCTAssertEqual(assets.list(app: "fresh"), before)
    }

    func testServiceFallsBackToTheManifestAssetPath() throws {
        let src = try file("issuer-bell.riv", riveData(6))
        let templates = TemplateStore(directory: root.appendingPathComponent("templates"))
        let assets = AssetStore(directory: root.appendingPathComponent("assets"))
        let m = HeraldManifest(app: "demo", appName: "Demo", assets: [HeraldAsset(id: "bell", type: "rive", path: src.path)])
        let svc = TemplateBundleService(templates: templates, assets: assets) { $0 == "demo" ? m : nil }
        // Nothing installed yet, but the manifest names the file.
        let out = try svc.export(template(cells: [riveCell("a", asset: "bell")]))
        XCTAssertEqual(out.assetFiles, ["bell.riv"])
    }

    // MARK: Command line

    private func action(_ args: [String]) throws -> CLIAction { try CLIArguments.parse(args).action }

    func testCLIParsesTemplateExport() throws {
        guard case .templateExport(let e) = try action(["template", "export", "--app", "mail", "--name", "Digest"]) else { return XCTFail() }
        XCTAssertEqual(e, CLITemplateExport(app: "mail", name: "Digest", output: nil))
        guard case .templateExport(let o) = try action(["template", "export", "--name=Digest", "--app", "mail", "-o", "~/x.heraldtemplate"]) else { return XCTFail() }
        XCTAssertEqual(o.output, "~/x.heraldtemplate")
        XCTAssertThrowsError(try action(["template", "export", "--app", "mail"]))
        XCTAssertThrowsError(try action(["template", "export", "--name", "x"]))
        XCTAssertThrowsError(try action(["template"]))
        XCTAssertThrowsError(try action(["template", "share"]))
    }

    func testCLIParsesTemplateImport() throws {
        guard case .templateImport(let a) = try action(["template", "import", "Digest.heraldtemplate"]) else { return XCTFail() }
        XCTAssertEqual(a, CLITemplateImport(file: "Digest.heraldtemplate", app: nil, conflict: .keepBoth))
        guard case .templateImport(let b) = try action(["template", "import", "d.heraldtemplate", "--app", "other", "--replace"]) else { return XCTFail() }
        XCTAssertEqual(b, CLITemplateImport(file: "d.heraldtemplate", app: "other", conflict: .replace))
        guard case .templateImport(let c) = try action(["template", "import", "--fail", "--file", "d.heraldtemplate"]) else { return XCTFail() }
        XCTAssertEqual(c.conflict, .fail)
        XCTAssertEqual(c.file, "d.heraldtemplate")
        XCTAssertThrowsError(try action(["template", "import"]))
        XCTAssertThrowsError(try action(["template", "import", "a.heraldtemplate", "--replace", "--fail"]))
        XCTAssertThrowsError(try action(["template", "import", "a.heraldtemplate", "--file", "b.heraldtemplate"]))
        XCTAssertTrue(CLIArguments.usage.contains("template export"))
    }

    func testLocatorFindsStoredCopiesManifestFilesAndRelativePaths() throws {
        let support = root.appendingPathComponent("support", isDirectory: true)
        let folder = HeraldTemplateBundle.assetsFolder(app: "demo", supportDirectory: support)
        XCTAssertEqual(folder.path, support.appendingPathComponent("assets/demo").path)
        let stored = try file("bell.riv", riveData(1), in: folder)
        let issuer = try file("issuer.riv", riveData(2))
        _ = try file("loose.riv", riveData(3), in: folder.appendingPathComponent("sub"))
        let m = HeraldManifest(app: "demo", appName: "Demo", assets: [HeraldAsset(id: "hero", type: "rive", path: issuer.path)])
        let find = HeraldTemplateBundle.locator(app: "demo", supportDirectory: support, manifest: m)
        XCTAssertEqual(find(.asset("bell"))?.path, stored.path)
        XCTAssertEqual(find(.asset("hero"))?.path, issuer.path)
        XCTAssertNil(find(.asset("none")))
        XCTAssertEqual(find(.path("sub/loose.riv"))?.lastPathComponent, "loose.riv")
        XCTAssertNil(find(.path("../escape.riv")))
        XCTAssertNil(find(.path("https://example.com/x.riv")))
        XCTAssertEqual(find(.path("file://\(issuer.path)"))?.path, issuer.path)
    }

    func testUnpackRunsTheSameValidationAsThePutRoute() throws {
        var bad = template(cells: [HeraldCell(id: "a", row: 0, col: 9, component: .spacer)])   // outside the 3 x 4 grid
        bad.grid = .standard
        XCTAssertFalse(bad.validate().filter(\.isError).isEmpty)
        XCTAssertThrowsError(try Bundle.unpack(zip([("template.json", try json(bad))]))) {
            XCTAssertTrue("\($0)".contains("does not fit"), "\($0)")
        }
    }
}
