import XCTest
import Foundation
@testable import HeraldClient
@testable import HeraldCore

// Issue #37: the in-app Kokoro download flow, run end to end by `swift test` against a loopback server that
// stands in for the GitHub release (no 340 MB download, no network, no UI). The Python environment step is
// exercised with a stub `python` that passes the import check, which is the branch a venv Herald left behind takes.

@MainActor
final class KokoroInstallerTests: XCTestCase {
    private var base: URL!
    private var server: HTTPLoopbackListener?
    private let model = Data((0..<10_000).map { UInt8($0 % 251) })
    private let voices = Data((0..<2_000).map { UInt8(($0 * 7) % 253) })

    override func setUpWithError() throws {
        base = FileManager.default.temporaryDirectory.appendingPathComponent("herald-kinst-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    }
    override func tearDown() { server?.stop(); try? FileManager.default.removeItem(at: base) }

    private final class Seen: @unchecked Sendable {
        private let lock = NSLock(); private var items: [(path: String, range: String?)] = []
        func add(_ p: String, _ r: String?) { lock.lock(); items.append((p, r)); lock.unlock() }
        var all: [(path: String, range: String?)] { lock.lock(); defer { lock.unlock() }; return items }
    }

    /// Serves the two files with `Range` support (206 + Content-Range), like the real release host.
    private func serve(delay: TimeInterval = 0, seen: Seen = Seen()) throws -> (String, Seen) {
        let files = ["/" + KokoroLayout.modelFile: model, "/" + KokoroLayout.voicesFile: voices]
        let l = HTTPLoopbackListener(port: 0) { req in
            let range = req.headers["range"]
            seen.add(req.path, range)
            if delay > 0 { try? await Task.sleep(nanoseconds: UInt64(delay * 1e9)) }
            guard let data = files[req.path] else { return HTTPResponse(status: 404) }
            if let range, range.hasPrefix("bytes="), let from = Int(range.dropFirst(6).dropLast()), from > 0, from < data.count {
                return HTTPResponse(status: 206, body: data.suffix(from: from),
                                    headers: ["Content-Range": "bytes \(from)-\(data.count - 1)/\(data.count)"],
                                    contentType: "application/octet-stream")
            }
            return HTTPResponse(status: 200, body: data, contentType: "application/octet-stream")
        }
        try l.start()
        server = l
        return ("http://127.0.0.1:\(l.port)/", seen)
    }

    /// A venv Herald "left behind": a python that exits 0 for the import check, no marker yet.
    private func makeStubVenv(_ layout: KokoroLayout) throws {
        try FileManager.default.createDirectory(at: layout.venv.appendingPathComponent("bin"), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: layout.python.path, contents: Data("#!/bin/sh\nexit 0\n".utf8),
                                       attributes: [.posixPermissions: 0o755])
    }

    private func wait(_ inst: KokoroInstaller, until done: (KokoroInstaller.Phase) -> Bool, timeout: TimeInterval = 20) async {
        let end = Date().addingTimeInterval(timeout)
        while !done(inst.phase), Date() < end { try? await Task.sleep(nanoseconds: 20_000_000) }
    }

    func testFreshInstallDownloadsBothFilesChecksumsThemAndMarksTheEnvironmentReady() async throws {
        let (url, seen) = try serve()
        let layout = KokoroLayout(supportDirectory: base)
        try makeStubVenv(layout)
        XCTAssertFalse(layout.isInstalled)
        let inst = KokoroInstaller(layout: layout, releaseBase: url)
        let changed = expectation(forNotification: .heraldVoiceEngineChanged, object: nil)
        inst.install()
        XCTAssertTrue(inst.isBusy, "busy at once: a second press before the task starts must be ignored")
        await wait(inst) { $0 == .done || { if case .failed = $0 { return true } else { return false } }($0) }
        XCTAssertEqual(inst.phase, .done, "log: \(inst.log)")
        XCTAssertEqual(try Data(contentsOf: layout.model), model)
        XCTAssertEqual(try Data(contentsOf: layout.voices), voices)
        XCTAssertEqual(inst.checksums[KokoroLayout.modelFile], try KokoroLayout.sha256(of: layout.model))
        XCTAssertEqual(inst.checksums[KokoroLayout.voicesFile], try KokoroLayout.sha256(of: layout.voices))
        XCTAssertEqual(inst.checksums[KokoroLayout.voicesFile]?.count, 64)
        XCTAssertTrue(FileManager.default.fileExists(atPath: layout.environmentMarker.path))
        XCTAssertFalse(layout.environmentIncomplete)
        XCTAssertTrue(layout.isInstalled)
        XCTAssertGreaterThan(inst.revision, 0)
        XCTAssertEqual(seen.all.map(\.path), ["/" + KokoroLayout.voicesFile, "/" + KokoroLayout.modelFile], "voices first, then the model")
        XCTAssertFalse(FileManager.default.fileExists(atPath: layout.model.appendingPathExtension("part").path))
        await fulfillment(of: [changed], timeout: 1)
    }

    func testAnInterruptedDownloadContinuesFromThePartFile() async throws {
        let (url, seen) = try serve()
        let layout = KokoroLayout(supportDirectory: base)
        try makeStubVenv(layout)
        try FileManager.default.createDirectory(at: layout.root, withIntermediateDirectories: true)
        let cut = 3_333
        try model.prefix(cut).write(to: layout.model.appendingPathExtension("part"))
        let inst = KokoroInstaller(layout: layout, releaseBase: url)
        inst.install()
        await wait(inst) { $0 == .done || { if case .failed = $0 { return true } else { return false } }($0) }
        XCTAssertEqual(inst.phase, .done, "log: \(inst.log)")
        XCTAssertEqual(try Data(contentsOf: layout.model), model, "the resumed file is byte-identical")
        XCTAssertEqual(seen.all.first { $0.path.hasSuffix(KokoroLayout.modelFile) }?.range, "bytes=\(cut)-")
    }

    func testAServerErrorFailsWithTheStatusAndAllowsARetry() async throws {
        let layout = KokoroLayout(supportDirectory: base)
        try makeStubVenv(layout)
        let (url, _) = try serve()
        let inst = KokoroInstaller(layout: layout, releaseBase: url + "missing/")
        inst.install()
        await wait(inst) { if case .failed = $0 { return true } else { return false } }
        guard case .failed(let why) = inst.phase else { return XCTFail("expected failure, got \(inst.phase)") }
        XCTAssertTrue(why.contains("404"), why)
        XCTAssertFalse(inst.isBusy)
        XCTAssertFalse(layout.isInstalled)
    }

    func testCancelReturnsToIdleNotToAnError() async throws {
        let (url, _) = try serve(delay: 3)
        let layout = KokoroLayout(supportDirectory: base)
        try makeStubVenv(layout)
        let inst = KokoroInstaller(layout: layout, releaseBase: url)
        inst.install()
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertTrue(inst.isBusy)
        inst.cancel()
        XCTAssertEqual(inst.phase, .idle)
        try await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertEqual(inst.phase, .idle, "the unwinding download must not publish a failure after cancel")
        XCTAssertFalse(layout.isInstalled)
    }

    func testUseExistingInstallationLinksWithoutDownloading() throws {
        let src = KokoroLayout(root: base.appendingPathComponent("existing"))
        try makeStubVenv(src)
        try model.write(to: src.model); try voices.write(to: src.voices)
        let mine = KokoroLayout(supportDirectory: base.appendingPathComponent("support"))
        let inst = KokoroInstaller(layout: mine, releaseBase: "http://127.0.0.1:1/")
        inst.useExisting(src)
        XCTAssertEqual(inst.phase, .done)
        XCTAssertTrue(mine.isInstalled)
    }
}
