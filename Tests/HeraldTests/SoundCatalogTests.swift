import XCTest
@testable import HeraldCore

final class SoundCatalogTests: XCTestCase {
    private var dir: URL!
    private var other: URL!

    override func setUpWithError() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("herald-sounds-\(UUID().uuidString)")
        dir = base.appendingPathComponent("system", isDirectory: true)
        other = base.appendingPathComponent("user", isDirectory: true)
        for d in [dir!, other!] { try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true) }
        for name in ["Glass.aiff", "Ping.aiff", "notes.txt"] { FileManager.default.createFile(atPath: dir.appendingPathComponent(name).path, contents: Data([0])) }
        for name in ["Glass.wav", "Custom.WAV"] { FileManager.default.createFile(atPath: other.appendingPathComponent(name).path, contents: Data([0])) }
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("Folder.aiff"), withIntermediateDirectories: true)
    }

    override func tearDown() { try? FileManager.default.removeItem(at: dir.deletingLastPathComponent()) }

    private var dirs: [String] { [dir.path, other.path] }

    func testNoneAndEmptyAreSilent() {
        for s in ["none", "None", "NONE", "", "  "] { XCTAssertEqual(SoundCatalog.resolve(s, directories: dirs), .silent, "'\(s)'") }
    }

    func testDefaultIsLeftToTheCaller() {
        XCTAssertEqual(SoundCatalog.resolve("default", directories: dirs), .useDefault)
        XCTAssertEqual(SoundCatalog.resolve("Default", directories: dirs), .useDefault)
    }

    func testNamesMatchCaseInsensitivelyWithOrWithoutExtension() {
        let glass = SoundChoice.file(dir.appendingPathComponent("Glass.aiff").path)
        for s in ["Glass", "glass", "GLASS", "Glass.aiff", "glass.AIFF"] {
            XCTAssertEqual(SoundCatalog.resolve(s, directories: dirs), glass, s)
        }
    }

    func testEarlierDirectoriesWinAndLaterOnesAreSearched() {
        XCTAssertEqual(SoundCatalog.resolve("Glass", directories: dirs), .file(dir.appendingPathComponent("Glass.aiff").path))
        XCTAssertEqual(SoundCatalog.resolve("Glass", directories: [other.path, dir.path]), .file(other.appendingPathComponent("Glass.wav").path))
        XCTAssertEqual(SoundCatalog.resolve("custom", directories: dirs), .file(other.appendingPathComponent("Custom.WAV").path))
    }

    func testUnknownNamesAreInvalid() {
        for s in ["Nope", "Glas", "notes", "notes.txt", "Folder"] {
            guard case .invalid(let why) = SoundCatalog.resolve(s, directories: dirs) else { return XCTFail("\(s) should be invalid") }
            XCTAssertTrue(why.contains(s), why)
        }
        XCTAssertFalse(SoundCatalog.isValid("Nope", directories: dirs))
        XCTAssertTrue(SoundCatalog.isValid("Ping", directories: dirs))
        XCTAssertTrue(SoundCatalog.isValid("none", directories: dirs))
        XCTAssertTrue(SoundCatalog.isValid("default", directories: dirs))
    }

    func testFilePaths() {
        let ping = dir.appendingPathComponent("Ping.aiff").path
        XCTAssertEqual(SoundCatalog.resolve(ping, directories: []), .file(ping))
        for bad in [dir.appendingPathComponent("notes.txt").path,          // not audio
                    dir.appendingPathComponent("missing.aiff").path,        // does not exist
                    dir.appendingPathComponent("Folder.aiff").path,         // a directory
                    "/definitely/not/here.wav"] {
            guard case .invalid = SoundCatalog.resolve(bad, directories: []) else { return XCTFail(bad) }
        }
    }

    func testTildeIsExpanded() throws {
        let name = "herald-test-\(UUID().uuidString).wav"
        let home = FileManager.default.homeDirectoryForCurrentUser
        let file = home.appendingPathComponent(name)
        FileManager.default.createFile(atPath: file.path, contents: Data([0]))
        defer { try? FileManager.default.removeItem(at: file) }
        XCTAssertEqual(SoundCatalog.resolve("~/\(name)", directories: []), .file(file.path))
    }

    func testNamesListsOnlyAudioFilesSorted() {
        XCTAssertEqual(SoundCatalog.names(in: dir.path), ["Glass", "Ping"], "no notes.txt, no Folder.aiff directory")
    }

    func testRealSystemSounds() throws {
        try XCTSkipUnless(FileManager.default.fileExists(atPath: SoundCatalog.systemDirectory), "no system sounds here")
        let names = SoundCatalog.names()
        XCTAssertTrue(names.contains("Glass"), "\(names)")
        XCTAssertEqual(SoundCatalog.resolve("Glass"), .file("\(SoundCatalog.systemDirectory)/Glass.aiff"))
        XCTAssertEqual(SoundCatalog.resolve("glass"), .file("\(SoundCatalog.systemDirectory)/Glass.aiff"))
        XCTAssertFalse(SoundCatalog.isValid("Definitely Not A Sound"))
        XCTAssertEqual(SoundCatalog.defaultDirectories.first, SoundCatalog.systemDirectory, "system sounds can not be shadowed")
    }
}
