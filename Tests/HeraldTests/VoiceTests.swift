import XCTest
import Foundation
@testable import HeraldClient
@testable import HeraldCore

// MARK: - Fakes

@MainActor
private final class FakePlayer: SpeechPlayer {
    var started: [SpeechUtterance] = []
    var finished: [SpeechUtterance] = []
    var overlapped = false
    private var current: SpeechUtterance?
    private var cont: CheckedContinuation<Void, Never>?
    /// How long each utterance "plays".
    var duration: UInt64 = 20_000_000

    func play(_ u: SpeechUtterance) async {
        if current != nil { overlapped = true }
        current = u
        started.append(u)
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            cont = c
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: self?.duration ?? 0)
                self?.end(u)
            }
        }
    }

    func stop() { if let u = current { end(u) } }

    private func end(_ u: SpeechUtterance) {
        guard current == u, let c = cont else { return }
        current = nil; cont = nil
        finished.append(u)
        c.resume()
    }
}

private final class FakeProcess: TTSProcess, @unchecked Sendable {
    var onLine: (@Sendable (String) -> Void)?
    var onExit: (@Sendable () -> Void)?
    let behaviour: @Sendable (FakeProcess, TTSRequest) -> Void
    private(set) var sent: [TTSRequest] = []
    init(_ b: @escaping @Sendable (FakeProcess, TTSRequest) -> Void) { behaviour = b }
    func start(onLine: @escaping @Sendable (String) -> Void, onExit: @escaping @Sendable () -> Void) throws {
        self.onLine = onLine; self.onExit = onExit
    }
    func send(_ data: Data) {
        let line = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(line.hasSuffix("\n"))
        guard let r = try? JSONDecoder().decode(TTSRequest.self, from: data) else { return }
        sent.append(r)
        behaviour(self, r)
    }
    func terminate() {}
    func reply(_ json: String) { onLine?(json) }
    func die() { onExit?() }
}

private func wavURL(_ name: String) -> URL { URL(fileURLWithPath: "/tmp/\(name).wav") }

// MARK: - HeraldSpeak

final class HeraldSpeakTests: XCTestCase {
    private func decode(_ json: String) throws -> HeraldNotification {
        try JSONDecoder().decode(HeraldNotification.self, from: Data(json.utf8))
    }

    func testTrueDecodesToDefaultSpeak() throws {
        let n = try decode(#"{"app":"a","title":"t","speak":true}"#)
        XCTAssertEqual(n.speak, HeraldSpeak())
    }

    func testObjectDecodes() throws {
        let n = try decode(#"{"app":"a","title":"t","speak":{"text":"hi","voice":"af_bella","speed":1.2,"lang":"en-gb"},"audio":"/x.wav","presentation":"both"}"#)
        XCTAssertEqual(n.speak, HeraldSpeak(text: "hi", voice: "af_bella", speed: 1.2, lang: "en-gb"))
        XCTAssertEqual(n.audio, "/x.wav")
        XCTAssertEqual(n.presentation, .both)
    }

    func testFalseIsRejectedByTheTypeAndDroppedByTheRouter() throws {
        XCTAssertThrowsError(try decode(#"{"app":"a","title":"t","speak":false}"#))
    }

    func testRoundTrip() throws {
        var n = HeraldNotification(app: "a", title: "t")
        n.speak = HeraldSpeak()
        n.presentation = .voice
        let data = try JSONEncoder().encode(n)
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains(#""speak":true"#))
        XCTAssertEqual(try JSONDecoder().decode(HeraldNotification.self, from: data), n)
        n.speak = HeraldSpeak(text: "x", speed: 1.5)
        XCTAssertEqual(try JSONDecoder().decode(HeraldNotification.self, from: JSONEncoder().encode(n)), n)
    }

    func testHistoryItemCarriesSpeech() throws {
        var item = HeraldHistoryItem(id: "1", app: "a", notification: HeraldNotification(app: "a", title: "t"), deliveredAt: Date())
        item.speech = HeraldSpeech(text: "hello", voice: "af_heart", audioPath: "/x.wav", durationSeconds: 1.5)
        let back = try HeraldJSON.decoder().decode(HeraldHistoryItem.self, from: HeraldJSON.encoder().encode(item))
        XCTAssertEqual(back.speech, item.speech)
    }

    func testTextCapAndCleaning() {
        let long = String(repeating: "word ", count: 2_000)
        XCTAssertEqual(HeraldSpeak.clean(long).count, HeraldSpeak.maxTextLength)
        XCTAssertEqual(HeraldSpeak.clean("See [the docs](https://x.y/z)  now\n\nplease"), "See the docs now please")
        let s = HeraldSpeak()
        XCTAssertEqual(s.resolvedText(title: "Bid accepted", body: "Acme paid"), "Bid accepted. Acme paid.")
        XCTAssertEqual(s.resolvedText(title: "Done!", body: nil), "Done!")
        XCTAssertEqual(HeraldSpeak(text: "Custom").resolvedText(title: "T", body: "B"), "Custom")
        XCTAssertLessThanOrEqual(HeraldSpeak(text: long).resolvedText(title: "T", body: nil).count, 2_000)
    }

    func testValidation() {
        XCTAssertTrue(HeraldSpeak.isValidVoice("af_heart"))
        XCTAssertFalse(HeraldSpeak.isValidVoice("af_heart; rm -rf /"))
        XCTAssertFalse(HeraldSpeak.isValidVoice(""))
        XCTAssertTrue(HeraldSpeak.isValidLang("en-us"))
        XCTAssertFalse(HeraldSpeak.isValidLang("en us"))
    }

    func testSpeakRequestBecomesVoiceNotification() {
        let n = HeraldSpeakRequest(app: "a", text: "Build finished", voice: "af_bella", speed: 1.1).notification()
        XCTAssertEqual(n.presentation, .voice)
        XCTAssertEqual(n.speak?.text, "Build finished")
        XCTAssertEqual(n.title, "Build finished")
        let long = HeraldSpeakRequest(app: "a", text: String(repeating: "x", count: 500)).notification()
        XCTAssertLessThanOrEqual(long.title.count, 80)
        XCTAssertEqual(long.speak?.text?.count, 500)
    }
}

// MARK: - Queue

@MainActor
final class SpeechQueueTests: XCTestCase {
    func testPlaysInOrderWithoutOverlapEvenWhenSynthesisFinishesOutOfOrder() async {
        let player = FakePlayer()
        let q = SpeechQueue(player: player)
        // The first job is slow to prepare, the others instant: order must still be 1, 2, 3.
        q.enqueue(.init(key: "1") { try? await Task.sleep(nanoseconds: 80_000_000); return .file(wavURL("1")) })
        q.enqueue(.init(key: "2") { .file(wavURL("2")) })
        q.enqueue(.init(key: "3") { .file(wavURL("3")) })
        await q.waitUntilIdle()
        XCTAssertEqual(player.started, [.file(wavURL("1")), .file(wavURL("2")), .file(wavURL("3"))])
        XCTAssertFalse(player.overlapped)
        XCTAssertTrue(q.isIdle)
    }

    func testFailedPreparationIsSkipped() async {
        let player = FakePlayer()
        let q = SpeechQueue(player: player)
        q.enqueue(.init(key: "a") { nil })
        q.enqueue(.init(key: "b") { .file(wavURL("b")) })
        await q.waitUntilIdle()
        XCTAssertEqual(player.started, [.file(wavURL("b"))])
    }

    /// The cloud relay's `spoken` receipt hangs on this: true only when the audio played to the end.
    func testFinishedCallbackSaysWhetherTheSpeechPlayedToTheEnd() async {
        let player = FakePlayer()
        var results: [String: Bool] = [:]
        let q = SpeechQueue(player: player, isMuted: { false })
        q.enqueue(.init(key: "ok", finished: { results["ok"] = $0 }) { .file(wavURL("ok")) })
        q.enqueue(.init(key: "none", finished: { results["none"] = $0 }) { nil })
        await q.waitUntilIdle()
        XCTAssertEqual(results, ["ok": true, "none": false])

        let muted = SpeechQueue(player: FakePlayer(), isMuted: { true })
        muted.enqueue(.init(key: "m", finished: { results["m"] = $0 }) { .file(wavURL("m")) })
        await muted.waitUntilIdle()
        XCTAssertEqual(results["m"], false)

        let slow = FakePlayer(); slow.duration = 400_000_000
        let cut = SpeechQueue(player: slow)
        cut.enqueue(.init(key: "c", finished: { results["c"] = $0 }) { .file(wavURL("c")) })
        try? await Task.sleep(nanoseconds: 60_000_000)
        cut.cancel(key: "c")
        await cut.waitUntilIdle()
        XCTAssertEqual(results["c"], false)
    }

    func testMuteSkipsButReplayIgnoresIt() async {
        let player = FakePlayer()
        let q = SpeechQueue(player: player, isMuted: { true })
        q.enqueue(.init(key: "a") { .file(wavURL("a")) })
        q.enqueue(.init(key: "r", ignoresMute: true) { .file(wavURL("r")) })
        await q.waitUntilIdle()
        XCTAssertEqual(player.started, [.file(wavURL("r"))])
    }

    func testCancelInterruptsOnlyThatNotification() async {
        let player = FakePlayer()
        player.duration = 400_000_000
        let q = SpeechQueue(player: player)
        q.enqueue(.init(key: "x") { .file(wavURL("x1")) })
        q.enqueue(.init(key: "x") { .file(wavURL("x2")) })
        q.enqueue(.init(key: "y") { .file(wavURL("y1")) })
        try? await Task.sleep(nanoseconds: 50_000_000)
        q.cancel(key: "x")
        await q.waitUntilIdle()
        XCTAssertEqual(player.started, [.file(wavURL("x1")), .file(wavURL("y1"))])
        XCTAssertEqual(player.finished.first, .file(wavURL("x1")))   // cut off, not played out
    }

    func testStopAllClearsTheQueue() async {
        let player = FakePlayer()
        player.duration = 400_000_000
        let q = SpeechQueue(player: player)
        for i in 0..<5 { q.enqueue(.init(key: "k\(i)") { .file(wavURL("s\(i)")) }) }
        try? await Task.sleep(nanoseconds: 50_000_000)
        q.stopAll()
        await q.waitUntilIdle()
        XCTAssertEqual(player.started.count, 1)
        XCTAssertTrue(q.isIdle)
    }

    func testPendingIsBounded() async {
        let player = FakePlayer()
        player.duration = 1_000_000
        let q = SpeechQueue(player: player)
        for i in 0..<(SpeechQueue.maxPending + 10) { q.enqueue(.init(key: "k\(i)") { .file(wavURL("b\(i)")) }) }
        await q.waitUntilIdle()
        XCTAssertLessThanOrEqual(player.started.count, SpeechQueue.maxPending + 1)
        XCTAssertEqual(player.started.last, .file(wavURL("b\(SpeechQueue.maxPending + 9)")))
    }
}

// MARK: - Worker protocol

final class TTSWorkerTests: XCTestCase {
    func testEncodeIsOneLineOfJSON() throws {
        let line = try TTSWorkerProtocol.encode(TTSRequest(text: "line one\nline \"two\" $(rm -rf /)", voice: "af_heart", speed: 1.1, lang: "en-us", out: "/tmp/a.wav"))
        let s = String(decoding: line, as: UTF8.self)
        XCTAssertEqual(s.filter { $0 == "\n" }.count, 1)
        XCTAssertTrue(s.hasSuffix("\n"))
        let back = try JSONDecoder().decode(TTSRequest.self, from: line)
        XCTAssertEqual(back.text, "line one\nline \"two\" $(rm -rf /)")
        XCTAssertEqual(back.out, "/tmp/a.wav")
    }

    func testParseResponses() throws {
        let ok = try TTSWorkerProtocol.parse(line: #"{"ok": true, "out": "/tmp/a.wav", "duration": 2.4}"#)
        XCTAssertEqual(ok, TTSResponse(ok: true, out: "/tmp/a.wav", duration: 2.4))
        let bad = try TTSWorkerProtocol.parse(line: #"{"ok": false, "error": "boom"}"#)
        XCTAssertEqual(bad.error, "boom")
        XCTAssertThrowsError(try TTSWorkerProtocol.parse(line: "Traceback (most recent call last):"))
    }

    func testSynthesizeThroughAFakeProcess() async throws {
        let proc = FakeProcess { p, r in p.reply(#"{"ok":true,"out":"\#(r.out ?? "")","duration":1.25}"#) }
        let worker = TTSWorker { proc }
        let d = try await worker.synthesize(text: "hello", voice: "af_heart", speed: 1, lang: "en-us", out: URL(fileURLWithPath: "/tmp/h.wav"))
        XCTAssertEqual(d, 1.25)
        XCTAssertEqual(proc.sent.first?.text, "hello")
        XCTAssertEqual(proc.sent.first?.voice, "af_heart")
    }

    func testWorkerErrorSurfaces() async {
        let proc = FakeProcess { p, _ in p.reply(#"{"ok":false,"error":"no such voice"}"#) }
        let worker = TTSWorker { proc }
        do {
            _ = try await worker.synthesize(text: "x", voice: "zz", speed: 1, lang: "en-us", out: URL(fileURLWithPath: "/tmp/h.wav"))
            XCTFail("expected a failure")
        } catch { XCTAssertEqual(error as? TTSWorkerError, .failed("no such voice")) }
    }

    func testRestartsAfterACrashAndRetries() async throws {
        let counter = Counter()
        let worker = TTSWorker {
            let n = counter.next()
            // The first process dies on its first request; the second one answers.
            return FakeProcess { p, r in
                if n == 1 { p.die() } else { p.reply(#"{"ok":true,"out":"\#(r.out ?? "")","duration":0.5}"#) }
            }
        }
        let d = try await worker.synthesize(text: "again", voice: "af_heart", speed: 1, lang: "en-us", out: URL(fileURLWithPath: "/tmp/h.wav"))
        XCTAssertEqual(d, 0.5)
        let launches = await worker.launches
        XCTAssertEqual(launches, 2)
    }

    func testRequestsAreSerialized() async throws {
        let proc = FakeProcess { p, r in
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.03) { p.reply(#"{"ok":true,"out":"\#(r.out ?? "")","duration":1}"#) }
        }
        let worker = TTSWorker { proc }
        try await withThrowingTaskGroup(of: Double.self) { g in
            for i in 0..<4 { g.addTask { try await worker.synthesize(text: "t\(i)", voice: "v", speed: 1, lang: "en-us", out: URL(fileURLWithPath: "/tmp/\(i).wav")) } }
            for try await _ in g {}
        }
        XCTAssertEqual(proc.sent.count, 4)
    }

    func testTimeoutKillsAndFails() async {
        let proc = FakeProcess { _, _ in }   // never answers
        let worker = TTSWorker(requestTimeout: 0.1) { proc }
        do {
            _ = try await worker.request(TTSRequest(text: "x", out: "/tmp/x.wav"))
            XCTFail("expected a timeout")
        } catch { XCTAssertEqual(error as? TTSWorkerError, .timedOut) }
    }
}

private final class Counter: @unchecked Sendable {
    private var n = 0
    private let lock = NSLock()
    func next() -> Int { lock.lock(); defer { lock.unlock() }; n += 1; return n }
}

// MARK: - Audio and layout

final class AudioCacheTests: XCTestCase {
    private var dir: URL!
    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("herald-audio-\(UUID().uuidString)")
    }
    override func tearDown() { try? FileManager.default.removeItem(at: dir) }

    private func wav(_ extra: Int = 0) -> Data {
        Data("RIFF".utf8) + Data([0, 0, 0, 0]) + Data("WAVEfmt ".utf8) + Data(repeating: 0, count: 20 + extra)
    }

    func testSignatures() {
        XCTAssertEqual(AudioSniffer.fileExtension(for: wav()), "wav")
        XCTAssertEqual(AudioSniffer.fileExtension(for: Data("ID3".utf8) + Data(count: 20)), "mp3")
        XCTAssertEqual(AudioSniffer.fileExtension(for: Data([0, 0, 0, 0x20]) + Data("ftypM4A ".utf8)), "m4a")
        XCTAssertNil(AudioSniffer.fileExtension(for: Data("#!/bin/sh\necho hi".utf8)))
        XCTAssertNil(AudioSniffer.fileExtension(for: Data("\u{89}PNG\r\n".utf8)))
    }

    func testCachesDataURIAndFileAndRejectsNonAudio() async throws {
        let cache = AudioCache(directory: dir)
        let uri = "data:audio/wav;base64," + wav().base64EncodedString()
        let a = await cache.cache(uri)
        XCTAssertEqual(a?.pathExtension, "wav")
        XCTAssertTrue(FileManager.default.fileExists(atPath: a!.path))
        let again = await cache.cache(uri)
        XCTAssertEqual(a, again)   // content-addressed

        let src = FileManager.default.temporaryDirectory.appendingPathComponent("src-\(UUID().uuidString).bin")
        try wav(10).write(to: src)
        defer { try? FileManager.default.removeItem(at: src) }
        let b = await cache.cache(src.path)
        XCTAssertEqual(b?.pathExtension, "wav")   // extension from the bytes, not the name

        try Data("not audio".utf8).write(to: src)
        let c = await cache.cache(src.path)
        XCTAssertNil(c)
        let d = await cache.cache("data:audio/wav;base64,!!!")
        XCTAssertNil(d)
        let e = await cache.cache("/nonexistent/file.wav")
        XCTAssertNil(e)
    }

    func testSizeLimit() async throws {
        let big = FileManager.default.temporaryDirectory.appendingPathComponent("big-\(UUID().uuidString).wav")
        try wav(AudioCache.maxBytes).write(to: big)
        defer { try? FileManager.default.removeItem(at: big) }
        let r = await AudioCache(directory: dir).cache(big.path)
        XCTAssertNil(r)
    }

    func testPruneKeepsNewest() throws {
        let cache = AudioCache(directory: dir)
        for _ in 0..<6 { _ = try { let u = cache.newSpeechURL(); try wav().write(to: u); return u }() }
        cache.prune(keep: 3)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: dir.path).count, 3)
    }
}

final class KokoroLayoutTests: XCTestCase {
    func testUseExistingLinksWithoutCopying() throws {
        let fm = FileManager.default
        let base = fm.temporaryDirectory.appendingPathComponent("herald-kokoro-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: base) }
        let src = KokoroLayout(root: base.appendingPathComponent("existing"))
        try fm.createDirectory(at: src.venv.appendingPathComponent("bin"), withIntermediateDirectories: true)
        try Data("m".utf8).write(to: src.model)
        try Data("v".utf8).write(to: src.voices)
        fm.createFile(atPath: src.python.path, contents: Data("#!/bin/sh\n".utf8), attributes: [.posixPermissions: 0o755])
        XCTAssertTrue(src.isInstalled)

        let mine = KokoroLayout(supportDirectory: base.appendingPathComponent("support"))
        XCTAssertFalse(mine.isInstalled)
        XCTAssertEqual(Set(mine.missing), [KokoroLayout.modelFile, KokoroLayout.voicesFile, "Python environment"])
        try mine.link(to: src)
        XCTAssertTrue(mine.isInstalled)
        XCTAssertNotNil(try? fm.destinationOfSymbolicLink(atPath: mine.model.path))
        try mine.link(to: src)   // idempotent
        XCTAssertTrue(mine.isInstalled)
    }

    func testSHA256() throws {
        let u = FileManager.default.temporaryDirectory.appendingPathComponent("sha-\(UUID().uuidString)")
        try Data("abc".utf8).write(to: u)
        defer { try? FileManager.default.removeItem(at: u) }
        XCTAssertEqual(try KokoroLayout.sha256(of: u), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }
}

// MARK: - Router

final class VoiceRouteTests: XCTestCase {
    private func post(_ router: Router, _ path: String, _ body: String) async -> HTTPResponse {
        await router.handle(HTTPRequest(method: "POST", path: path, query: [:],
                                        headers: ["authorization": "Bearer t"], body: Data(body.utf8)))
    }

    func testSpeakRouteSendsAVoiceOnlyNotification() async throws {
        let backend = MockBackend()
        let router = Router(token: "t", backend: backend, version: "1", pid: 1)
        let r = await post(router, "/v1/speak", #"{"app":"a","text":"Build finished","voice":"af_bella","speed":1.1}"#)
        XCTAssertEqual(r.status, 200)
        let n = try XCTUnwrap(backend.notified.first)
        XCTAssertEqual(n.presentation, .voice)
        XCTAssertEqual(n.speak, HeraldSpeak(text: "Build finished", voice: "af_bella", speed: 1.1))
    }

    func testSpeakRouteValidates() async {
        let router = Router(token: "t", backend: MockBackend(), version: "1", pid: 1)
        var r = await post(router, "/v1/speak", #"{"app":"a","text":"   "}"#)
        XCTAssertEqual(r.status, 400)
        r = await post(router, "/v1/speak", #"{"app":"a","text":"hi","speed":9}"#)
        XCTAssertEqual(r.status, 400)
        r = await post(router, "/v1/speak", #"{"app":"a","text":"hi","voice":"x; y"}"#)
        XCTAssertEqual(r.status, 400)
    }

    func testNotifyAcceptsSpeakTrueObjectAndFalse() async throws {
        let backend = MockBackend()
        let router = Router(token: "t", backend: backend, version: "1", pid: 1)
        _ = await post(router, "/v1/notify", #"{"app":"a","title":"t","speak":true}"#)
        _ = await post(router, "/v1/notify", #"{"app":"a","title":"t","speak":{"text":"hi"},"audio":"/x.wav","presentation":"both"}"#)
        _ = await post(router, "/v1/notify", #"{"app":"a","title":"t","speak":false}"#)
        XCTAssertEqual(backend.notified.count, 3)
        XCTAssertEqual(backend.notified[0].speak, HeraldSpeak())
        XCTAssertEqual(backend.notified[1].speak?.text, "hi")
        XCTAssertEqual(backend.notified[1].presentation, .both)
        XCTAssertNil(backend.notified[2].speak)
        XCTAssertNil(backend.notified[0].metadata)   // speak/audio/presentation are not folded into metadata
        let bad = await post(router, "/v1/notify", #"{"app":"a","title":"t","presentation":"loud"}"#)
        XCTAssertEqual(bad.status, 400)
    }
}

// MARK: - CLI

final class VoiceCLITests: XCTestCase {
    private func body(_ args: [String]) throws -> [String: Any] {
        guard case .request(let r) = try CLIArguments.parse(args).action else { XCTFail(); return [:] }
        return try XCTUnwrap(r.body)
    }

    func testSpeakFlagAlone() throws {
        let b = try body(["notify", "--app", "a", "--title", "t", "--speak"])
        XCTAssertEqual(b["speak"] as? Bool, true)
    }

    func testSpeakDetailsAudioAndPresentation() throws {
        let b = try body(["notify", "--app", "a", "--title", "t", "--speak-text", "Hello", "--voice", "af_bella",
                          "--speed", "1.25", "--lang", "en-gb", "--audio", "/tmp/m.wav", "--presentation", "voice"])
        let s = try XCTUnwrap(b["speak"] as? [String: Any])
        XCTAssertEqual(s["text"] as? String, "Hello")
        XCTAssertEqual(s["voice"] as? String, "af_bella")
        XCTAssertEqual(s["speed"] as? Double, 1.25)
        XCTAssertEqual(s["lang"] as? String, "en-gb")
        XCTAssertEqual(b["audio"] as? String, "/tmp/m.wav")
        XCTAssertEqual(b["presentation"] as? String, "voice")
    }

    func testBadValues() {
        XCTAssertThrowsError(try body(["notify", "--app", "a", "--title", "t", "--speed", "9"]))
        XCTAssertThrowsError(try body(["notify", "--app", "a", "--title", "t", "--presentation", "loud"]))
    }

    func testSpeakCommand() throws {
        guard case .request(let r) = try CLIArguments.parse(["speak", "--app", "a", "--text", "Done", "--voice", "af_heart"]).action else { return XCTFail() }
        XCTAssertEqual(r.path, "/v1/speak")
        XCTAssertEqual(r.body?["text"] as? String, "Done")
        XCTAssertThrowsError(try CLIArguments.parse(["speak", "--app", "a"]))
    }
}

// MARK: - Kokoro download and environment (issue #37)
//
// Runtime checklist, done by hand with the app's own installer code (KokoroInstaller) on an empty support folder:
//  1. Download: voices-v1.0.bin then kokoro-v1.0.onnx from the kokoro-onnx release; each file's SHA-256 is shown
//     (models verified byte-identical to the ~/.claude/tts copies).
//  2. Interrupt at about a third of the model and press Download again: it continues from the `.part` file (a 206
//     answer), finishes, and the SHA is the same. Cancel returns to idle, not to a red "cancelled" error.
//  3. Environment: `uv venv --python 3.12` + `uv pip install kokoro-onnx soundfile` (python3 -m venv + pip when uv
//     is absent, also checked), then `import kokoro_onnx, soundfile` must pass before the venv counts as installed.
//  4. Synthesis from the fresh install through the real tts_worker.py (voices listed, WAV written, second call warm).
//  5. A spoken notification shows the replay speaker beside the timestamp of its live banner; History rows do not.
//  6. Quiet hours: a window with "speak summary" ends and the one-line summary is synthesized; menu items
//     "Quiet for 1 Hour" / "Quiet until HH:MM" / "Resume Now" change what GET /v1/settings/quiet-hours reports.

final class DownloadResumeTests: XCTestCase {
    func testRangeHeaderOnlyWhenThereAreBytes() {
        XCTAssertNil(DownloadResume.rangeHeader(have: 0))
        XCTAssertEqual(DownloadResume.rangeHeader(have: 105_397_983), "bytes=105397983-")
    }

    func testTotalFromContentRange() {
        XCTAssertEqual(DownloadResume.total(fromContentRange: "bytes 100-299/300"), 300)
        XCTAssertEqual(DownloadResume.total(fromContentRange: "bytes */325532387"), 325_532_387)
        XCTAssertNil(DownloadResume.total(fromContentRange: "bytes 0-9/*"))
        XCTAssertNil(DownloadResume.total(fromContentRange: "bytes 0-9"))
        XCTAssertNil(DownloadResume.total(fromContentRange: nil))
    }

    func testPartialContentContinuesFromTheOffset() {
        XCTAssertEqual(DownloadResume.decide(status: 206, have: 100, contentLength: 200, contentRange: "bytes 100-299/300"), .resume(total: 300))
        // No Content-Range: the total is what is on disk plus what is coming.
        XCTAssertEqual(DownloadResume.decide(status: 206, have: 100, contentLength: 200, contentRange: nil), .resume(total: 300))
        // Unknown length (-1): progress is not reported, the download still continues.
        XCTAssertEqual(DownloadResume.decide(status: 206, have: 100, contentLength: -1, contentRange: nil), .resume(total: 0))
    }

    func testServerThatIgnoresTheRangeRestartsFromZero() {
        XCTAssertEqual(DownloadResume.decide(status: 200, have: 100, contentLength: 300, contentRange: nil), .restart(total: 300))
        XCTAssertEqual(DownloadResume.decide(status: 200, have: 0, contentLength: -1, contentRange: nil), .restart(total: 0))
    }

    func testUnsatisfiableRange() {
        // The part file is the whole file: finish by moving it into place.
        XCTAssertEqual(DownloadResume.decide(status: 416, have: 300, contentLength: 0, contentRange: "bytes */300"), .alreadyComplete)
        // More bytes on disk than the file has: not a prefix, so it must be thrown away rather than shipped.
        XCTAssertEqual(DownloadResume.decide(status: 416, have: 400, contentLength: 0, contentRange: "bytes */300"), .discardPart)
        // Fewer cannot be a 416, but if a server says so the bytes are not trusted either.
        XCTAssertEqual(DownloadResume.decide(status: 416, have: 100, contentLength: 0, contentRange: "bytes */300"), .discardPart)
        // No total to compare with: the long-standing assumption (it is complete) stands.
        XCTAssertEqual(DownloadResume.decide(status: 416, have: 300, contentLength: 0, contentRange: nil), .alreadyComplete)
    }

    func testOtherStatusesFail() {
        for code in [301, 403, 404, 429, 500, 503] {
            XCTAssertEqual(DownloadResume.decide(status: code, have: 0, contentLength: 0, contentRange: nil), .fail(code))
        }
    }
}

final class KokoroEnvironmentTests: XCTestCase {
    private var base: URL!
    override func setUpWithError() throws {
        base = FileManager.default.temporaryDirectory.appendingPathComponent("herald-kenv-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    }
    override func tearDown() { try? FileManager.default.removeItem(at: base) }

    private func makeVenv(in layout: KokoroLayout) throws {
        try FileManager.default.createDirectory(at: layout.venv.appendingPathComponent("bin"), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: layout.python.path, contents: Data("#!/bin/sh\n".utf8),
                                       attributes: [.posixPermissions: 0o755])
    }

    func testAVenvWithoutTheMarkerIsIncompleteUntilItIsWritten() throws {
        let l = KokoroLayout(root: base.appendingPathComponent("tts"))
        XCTAssertFalse(l.hasPython)
        XCTAssertFalse(l.environmentIncomplete, "no venv at all is missing, not incomplete")
        try makeVenv(in: l)
        XCTAssertTrue(l.hasPython)
        XCTAssertTrue(l.environmentIncomplete, "a venv Herald built but never finished (quit between uv venv and pip install)")
        try Data().write(to: l.environmentMarker)
        XCTAssertFalse(l.environmentIncomplete)
    }

    func testALinkedInstallationIsTheUsersOwnAndNeverRebuilt() throws {
        let fm = FileManager.default
        let src = KokoroLayout(root: base.appendingPathComponent("existing"))
        try makeVenv(in: src)
        try Data("m".utf8).write(to: src.model)
        try Data("v".utf8).write(to: src.voices)
        let mine = KokoroLayout(supportDirectory: base.appendingPathComponent("support"))
        try mine.link(to: src)
        XCTAssertTrue(mine.venvIsLinked)
        XCTAssertTrue(mine.isInstalled)
        XCTAssertFalse(fm.fileExists(atPath: mine.environmentMarker.path.replacingOccurrences(of: mine.venv.path, with: src.venv.path)),
                       "the source venv has no marker and must not get one")
        XCTAssertFalse(mine.environmentIncomplete)
    }
}
