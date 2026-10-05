import XCTest
import Foundation
@testable import HeraldClient
@testable import HeraldCore

// MARK: - Fakes

final class FakeRelaySocket: RelaySocket, @unchecked Sendable {
    private let lock = NSLock()
    private var incoming: [String]
    private(set) var sent: [String] = []
    /// True: after the script, `receive` waits (a quiet connection) until `close()`.
    var hold = false
    private var closed = false
    init(incoming: [String]) { self.incoming = incoming }

    func send(_ text: String) async throws { record(text) }
    func receive() async throws -> String {
        while true {
            if let next = pop() { return next }
            if !hold || isClosed { throw RelayError.transport("closed") }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
    }
    private func record(_ t: String) { lock.lock(); sent.append(t); lock.unlock() }
    private func pop() -> String? { lock.lock(); defer { lock.unlock() }; return incoming.isEmpty ? nil : incoming.removeFirst() }
    func close() { lock.lock(); closed = true; lock.unlock() }
    private var isClosed: Bool { lock.lock(); defer { lock.unlock() }; return closed }

    var frames: [[String: Any]] {
        lock.lock(); defer { lock.unlock() }
        return sent.compactMap { ($0.data(using: .utf8)).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } }
    }
    func receipts(_ kind: String) -> [[String: Any]] { frames.filter { $0["type"] as? String == "receipt" && $0["kind"] as? String == kind } }
}

@MainActor
final class FakeRelayHost: RelayHost {
    var muted = false
    var quiet = HeraldQuietStatus()
    var delivered: [HeraldNotification] = []
    var issuers: [String] = []
    var failDelivery = false
    func relayInputs(for envelope: RelayEnvelope) -> (muted: Bool, quiet: HeraldQuietStatus) { (muted, quiet) }
    func relayStatusNow() -> (muted: Bool, quiet: HeraldQuietStatus) { (muted, quiet) }
    func relayEnsureIssuer(_ key: RelayKeyRef) async { issuers.append(key.id) }
    func relayDeliver(_ notification: HeraldNotification) async throws {
        if failDelivery { throw BackendError(500, "no") }
        delivered.append(notification)
    }
}

private func tmp(_ name: String = UUID().uuidString) -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("herald-relay-tests-\(name)")
}

private func notifyFrame(id: String = "r_aaa", nid: String = "build-1", key: String = "build-bot", keyId: String = "k1",
                         client: String = "claude", payload: [String: Any] = ["title": "Build finished", "body": "214 passed"]) -> String {
    let o: [String: Any] = ["type": "notify", "id": id, "notificationId": nid, "createdAt": "2026-10-02T10:00:00Z",
                            "key": ["id": keyId, "name": key, "client": client], "payload": payload]
    return String(data: try! JSONSerialization.data(withJSONObject: o), encoding: .utf8)!
}

private let welcome = #"{"type":"welcome","ttlSeconds":86400}"#

@MainActor
final class RelayClientTests: XCTestCase {
    private func make(host: FakeRelayHost, dedupeFile: URL? = nil) -> (RelayClient, RelayStateStore) {
        let store = RelayStateStore(file: nil)
        store.update { $0.deviceId = "dev" }
        let c = RelayClient(host: host, store: store, dedupe: RelayDedupe(file: dedupeFile), tokens: MemoryTokenStore(token: "hrd_x"),
                            socketFactory: URLSessionRelaySocketFactory())
        return (c, store)
    }

    private func run(_ c: RelayClient, _ socket: FakeRelaySocket) async {
        do { try await c.session(socket) } catch { /* the fake closes when its script ends */ }
    }

    func testEnqueueShowsOneBannerUnderCloudAppAndSendsDisplayedReceipt() async {
        let host = FakeRelayHost()
        let (c, store) = make(host: host)
        let socket = FakeRelaySocket(incoming: [welcome, notifyFrame(payload: ["title": "Which branch?", "expectReply": true, "link": "https://example.com/x", "speak": true])])
        await run(c, socket)

        XCTAssertEqual(host.delivered.count, 1)
        let n = host.delivered[0]
        XCTAssertEqual(n.app, "cloud.build-bot")
        XCTAssertEqual(n.id, "r_aaa")
        XCTAssertEqual(n.persistent, true)
        XCTAssertEqual(n.url, "https://example.com/x")
        XCTAssertEqual(n.actionIds, ["reply", "record", "open-link"])
        XCTAssertNotNil(n.speak)
        XCTAssertEqual(host.issuers, ["k1"])
        // The relay was told: hello (status), ack, and a displayed receipt for that delivery id.
        XCTAssertEqual(socket.frames.first?["type"] as? String, "hello")
        XCTAssertEqual(socket.frames.filter { $0["type"] as? String == "ack" }.count, 1)
        let displayed = socket.receipts("displayed")
        XCTAssertEqual(displayed.count, 1)
        XCTAssertEqual(displayed.first?["id"] as? String, "r_aaa")
        XCTAssertEqual(store.value.log.first?.summary, "displayed")
        XCTAssertEqual(c.state, .online)   // set by the welcome frame
    }

    func testTheRelayTestIsAHeraldNotificationAndRegistersNoCloudApp() async {
        let host = FakeRelayHost()
        let (c, _) = make(host: host)
        let socket = FakeRelaySocket(incoming: [welcome, notifyFrame(id: "r_t1", nid: "test-1", key: "herald-test-ab12cd", keyId: "kt", payload: ["title": "Relay test", "body": "The relay works."])])
        await run(c, socket)
        XCTAssertEqual(host.delivered.count, 1)
        XCTAssertEqual(host.delivered[0].app, "herald")           // never cloud.herald-test-ab12cd
        XCTAssertEqual(host.delivered[0].title, "Relay test")
        XCTAssertEqual(host.issuers, [], "no issuer (app, manifest, icon) is made for the throw-away key")
        XCTAssertEqual(socket.receipts("displayed").count, 1)      // the test still gets its receipt
        // an ordinary key is untouched
        let host2 = FakeRelayHost()
        let (c2, _) = make(host: host2)
        await run(c2, FakeRelaySocket(incoming: [welcome, notifyFrame()]))
        XCTAssertEqual(host2.delivered.first?.app, "cloud.build-bot"); XCTAssertEqual(host2.issuers, ["k1"])
    }

    func testRelayTestItemsAreRecognisedByTheirNotificationId() {
        var n = HeraldNotification(app: "herald", id: "r_t1", title: "Relay test")
        n.metadata = .object(["relayNotificationId": .string("test-1")])
        let item = HeraldHistoryItem(id: "r_t1", app: "herald", notification: n, deliveredAt: Date())
        XCTAssertTrue(HeraldIdentity.isRelayTestItem(item, notificationId: "test-1"))
        XCTAssertFalse(HeraldIdentity.isRelayTestItem(item, notificationId: "test-2"))
        var other = item; other.app = "cloud.x"
        XCTAssertFalse(HeraldIdentity.isRelayTestItem(other, notificationId: "test-1"))
    }

    func testQuietHoursSuppressWithReasonAndShowNothing() async {
        let host = FakeRelayHost()
        host.quiet = HeraldQuietStatus(active: true, speech: true, sounds: true, banners: true, until: Date().addingTimeInterval(3600), source: "window")
        let (c, store) = make(host: host)
        let socket = FakeRelaySocket(incoming: [welcome, notifyFrame()])
        await run(c, socket)
        XCTAssertTrue(host.delivered.isEmpty)
        let s = socket.receipts("suppressed")
        XCTAssertEqual(s.count, 1)
        XCTAssertEqual(s.first?["reason"] as? String, "quiet-hours")
        XCTAssertEqual(s.first?["scope"] as? String, "all")
        XCTAssertTrue(socket.receipts("displayed").isEmpty)
        XCTAssertEqual(store.value.log.first?.suppressed, "quiet-hours")
        // the hello told the relay quiet hours are on
        XCTAssertEqual(socket.frames.first?["quietActive"] as? Bool, true)
    }

    func testMuteSuppresses() async {
        let host = FakeRelayHost()
        host.muted = true
        let (c, _) = make(host: host)
        let socket = FakeRelaySocket(incoming: [welcome, notifyFrame()])
        await run(c, socket)
        XCTAssertTrue(host.delivered.isEmpty)
        XCTAssertEqual(socket.receipts("suppressed").first?["reason"] as? String, "muted")
    }

    func testQuietWindowThatOnlySilencesSpeechShowsBannerButNotSpeech() async {
        let host = FakeRelayHost()
        host.quiet = HeraldQuietStatus(active: true, speech: true, sounds: false, banners: false, source: "window")
        let (c, _) = make(host: host)
        let socket = FakeRelaySocket(incoming: [welcome, notifyFrame(payload: ["title": "t", "speak": true])])
        await run(c, socket)
        XCTAssertEqual(host.delivered.count, 1)
        XCTAssertNil(host.delivered[0].speak)
        XCTAssertEqual(socket.receipts("displayed").count, 1)
        let s = socket.receipts("suppressed")
        XCTAssertEqual(s.first?["scope"] as? String, "speech")
        XCTAssertEqual(s.first?["reason"] as? String, "quiet-hours")
    }

    func testDuplicateIdProducesOneBannerEvenAcrossReconnectsAndRestarts() async {
        let host = FakeRelayHost()
        let file = tmp("dedupe.json")
        defer { try? FileManager.default.removeItem(at: file) }
        let (c, _) = make(host: host, dedupeFile: file)
        // Same delivery twice on one connection, then again on a second connection, and the same sender id under a new delivery id.
        await run(c, FakeRelaySocket(incoming: [welcome, notifyFrame(), notifyFrame()]))
        let again = FakeRelaySocket(incoming: [welcome, notifyFrame(), notifyFrame(id: "r_bbb", nid: "build-1")])
        await run(c, again)
        XCTAssertEqual(host.delivered.count, 1)
        // The duplicate is answered again with what is already known, so the relay can settle.
        XCTAssertEqual(again.receipts("displayed").count, 2)

        // A new process reads the same file: still one banner.
        let (c2, _) = make(host: host, dedupeFile: file)
        await run(c2, FakeRelaySocket(incoming: [welcome, notifyFrame()]))
        XCTAssertEqual(host.delivered.count, 1)
    }

    func testDedupeForgetsAfter24Hours() {
        let d = RelayDedupe(file: nil)
        let t0 = Date()
        XCTAssertFalse(d.seenBefore(id: "a", keyId: "k", notificationId: "n", now: t0))
        XCTAssertTrue(d.seenBefore(id: "a", keyId: "k", notificationId: "n", now: t0.addingTimeInterval(23 * 3600)))
        XCTAssertFalse(d.seenBefore(id: "a", keyId: "k", notificationId: "n", now: t0.addingTimeInterval(25 * 3600)))
    }

    func testFailedDeliveryIsReportedAndNeverRetriedIntoADoubleBanner() async {
        let host = FakeRelayHost()
        host.failDelivery = true
        let (c, _) = make(host: host)
        let socket = FakeRelaySocket(incoming: [welcome, notifyFrame()])
        await run(c, socket)
        XCTAssertEqual(socket.receipts("suppressed").first?["reason"] as? String, "delivery-failed")
        XCTAssertTrue(socket.receipts("displayed").isEmpty)
    }

    func testReceiptsGoOverTheSocketAndWaitWhenThereIsNone() async {
        let host = FakeRelayHost()
        let (c, _) = make(host: host)
        // No connection: spoken and replied wait.
        c.reportSpoken(id: "r_aaa")
        c.reportReply(id: "r_aaa", text: "release/1.7")
        try? await Task.sleep(nanoseconds: 50_000_000)
        let socket = FakeRelaySocket(incoming: [welcome])
        await run(c, socket)
        XCTAssertEqual(socket.receipts("spoken").count, 1)
        let replied = socket.receipts("replied")
        XCTAssertEqual(replied.first?["text"] as? String, "release/1.7")
    }

    func testIgnoresFramesThatAreNotNotifications() async {
        let host = FakeRelayHost()
        let (c, _) = make(host: host)
        await run(c, FakeRelaySocket(incoming: [welcome, "pong", "not json", #"{"type":"unknown"}"#]))
        XCTAssertTrue(host.delivered.isEmpty)
    }

    /// Every message costs budget on the relay's free plan: a status goes up only when it changed.
    func testStatusIsPublishedOnlyWhenItChanges() async throws {
        let host = FakeRelayHost()
        let (c, _) = make(host: host)
        let socket = FakeRelaySocket(incoming: [welcome])
        socket.hold = true
        let t = Task { await run(c, socket) }
        try await Task.sleep(nanoseconds: 150_000_000)
        func statusFrames() -> Int { socket.frames.filter { $0["type"] as? String == "status" }.count }
        c.publishStatus(); c.publishStatus(); c.publishStatus()
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(statusFrames(), 0, "nothing changed since the hello")
        host.quiet = HeraldQuietStatus(active: true, speech: true, sounds: true, banners: false, until: Date().addingTimeInterval(600), source: "adhoc")
        c.publishStatus(); c.publishStatus()
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(statusFrames(), 1)
        host.muted = true
        c.publishStatus()
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(statusFrames(), 2)
        socket.close()
        await t.value
    }

    func testBackoffGrowsAndCapsAtFiveMinutes() {
        XCTAssertEqual(RelayBackoff.delay(attempt: 0, jitter: 0.5), 1, accuracy: 0.001)
        XCTAssertEqual(RelayBackoff.delay(attempt: 3, jitter: 0.5), 8, accuracy: 0.001)
        XCTAssertEqual(RelayBackoff.delay(attempt: 20, jitter: 0.5), 300, accuracy: 0.001)
        XCTAssertGreaterThanOrEqual(RelayBackoff.delay(attempt: 4, jitter: 0), 12.7)
        XCTAssertLessThanOrEqual(RelayBackoff.delay(attempt: 4, jitter: 1), 19.3)
    }

    func testUnpairedClientDoesNotConnect() {
        let host = FakeRelayHost()
        let c = RelayClient(host: host, store: RelayStateStore(file: nil), dedupe: RelayDedupe(file: nil), tokens: MemoryTokenStore())
        c.start()
        XCTAssertEqual(c.state, .unpaired)
        XCTAssertFalse(c.isPaired)
    }

    func testStreamURLUsesWssAndNoToken() {
        let host = FakeRelayHost()
        let store = RelayStateStore(file: nil)
        store.update { $0.relayURL = "https://herald-relay.example.workers.dev" }
        let c = RelayClient(host: host, store: store, dedupe: RelayDedupe(file: nil), tokens: MemoryTokenStore(token: "t"))
        XCTAssertEqual(c.streamURL?.absoluteString, "wss://herald-relay.example.workers.dev/v1/device/stream")
    }
}

private func metaString(_ n: HeraldNotification, _ key: String) -> String? {
    if case .object(let o)? = n.metadata, case .string(let s)? = o[key] { return s }
    return nil
}

final class RelayPolicyTests: XCTestCase {
    private func env(_ payload: [String: Any]) -> RelayEnvelope {
        try! JSONDecoder().decode(RelayEnvelope.self, from: notifyFrame(payload: payload).data(using: .utf8)!)
    }

    func testDecisions() {
        XCTAssertEqual(RelayPolicy.decide(muted: false, quiet: HeraldQuietStatus()), .deliver(silenceSpeech: nil))
        XCTAssertEqual(RelayPolicy.decide(muted: true, quiet: HeraldQuietStatus()), .suppress(reason: "muted"))
        XCTAssertEqual(RelayPolicy.decide(muted: false, quiet: HeraldQuietStatus(active: true, speech: true, sounds: true, banners: true)), .suppress(reason: "quiet-hours"))
        XCTAssertEqual(RelayPolicy.decide(muted: false, quiet: HeraldQuietStatus(active: true, speech: true, sounds: false, banners: false)), .deliver(silenceSpeech: "quiet-hours"))
        XCTAssertEqual(RelayPolicy.decide(muted: false, quiet: HeraldQuietStatus(active: true, speech: false, sounds: true, banners: false)), .deliver(silenceSpeech: nil))
    }

    func testNotificationIsBuiltFromAWhitelistOnly() {
        let e = env(["title": "T", "body": "B", "status": "done", "project": "p", "link": "http://insecure.example.com", "priority": "urgent",
                     "speak": ["text": "hi", "voice": "af_heart", "speed": 1.2, "lang": "en-us"],
                     // a hostile relay might send these; none can come through
                     "command": "rm -rf /", "buttons": [["label": "x", "command": "ls"]], "callback": ["url": "https://evil.example"], "audio": "/etc/passwd", "image": "file:///x"])
        let n = RelayPolicy.notification(for: e, silenceSpeech: false)
        XCTAssertEqual(n.app, "cloud.build-bot")
        XCTAssertNil(n.url, "a non-https link is dropped")
        XCTAssertNil(n.buttons); XCTAssertNil(n.audio); XCTAssertNil(n.image); XCTAssertNil(n.template); XCTAssertNil(n.reminder)
        XCTAssertEqual(n.priority, "urgent")
        XCTAssertEqual(n.speak?.voice, "af_heart")
        XCTAssertEqual(n.speak?.speed, 1.2)
        XCTAssertEqual(n.actionIds, ["reply", "record"])
        XCTAssertEqual(metaString(n, "status"), "done")
    }

    func testVoiceReplyCanBeTurnedOffAndSpeechCanBeSilenced() {
        let n = RelayPolicy.notification(for: env(["title": "T", "allowVoiceReply": false, "speak": true]), silenceSpeech: true)
        XCTAssertEqual(n.actionIds, ["reply"])
        XCTAssertNil(n.speak)
    }

    func testExpectReplyOnlyAddsReplyAndRecord() {
        let plain = RelayPolicy.notification(for: env(["title": "T", "status": "done"]), silenceSpeech: false)
        let ask = RelayPolicy.notification(for: env(["title": "T", "status": "done", "expectReply": true]), silenceSpeech: false)
        XCTAssertEqual(ask.title, plain.title)
        XCTAssertEqual(ask.persistent, plain.persistent, "persistence is the same with and without expectReply")
        XCTAssertEqual(ask.presentation, plain.presentation)
        XCTAssertEqual(ask.template, plain.template)
        XCTAssertEqual(metaString(ask, "status"), "done", "the badge is the sender's own")
        XCTAssertEqual(ask.actionIds, ["reply", "record"])
        // No status of its own either: it must not become a question.
        XCTAssertNil(metaString(RelayPolicy.notification(for: env(["title": "T", "expectReply": true]), silenceSpeech: false), "status"))
    }

    func testARelayNotificationStaysUntilDismissedByDefault() {
        XCTAssertEqual(RelayPolicy.notification(for: env(["title": "T"]), silenceSpeech: false).persistent, true)
        let n = RelayPolicy.notification(for: env(["title": "T", "speak": true, "persistent": true]), silenceSpeech: false)
        XCTAssertEqual(n.persistent, true)
        XCTAssertNotNil(n.speak)
        XCTAssertNil(n.timeout)
    }

    func testPersistentFalseAndTimeoutSecondsReachHerald() {
        let off = RelayPolicy.notification(for: env(["title": "T", "persistent": false]), silenceSpeech: false)
        XCTAssertEqual(off.persistent, false)
        let t = RelayPolicy.notification(for: env(["title": "T", "timeoutSeconds": 20]), silenceSpeech: false)
        XCTAssertNil(t.persistent, "a timeout without persistent: Herald's own default applies, not forever")
        XCTAssertEqual(t.timeout, 20)
        let both = RelayPolicy.notification(for: env(["title": "T", "timeoutSeconds": 20, "persistent": true]), silenceSpeech: false)
        XCTAssertEqual(both.persistent, true)
        XCTAssertNil(both.timeout, "persistent wins over a timeout")
        XCTAssertEqual(RelayPolicy.notification(for: env(["title": "T", "timeoutSeconds": 99999, "persistent": false]), silenceSpeech: false).timeout, 3600)
    }

    func testSoundIsANameNeverAPath() {
        XCTAssertEqual(RelayPolicy.notification(for: env(["title": "T", "sound": "Glass"]), silenceSpeech: false).sound, "Glass")
        XCTAssertEqual(RelayPolicy.notification(for: env(["title": "T", "sound": "none"]), silenceSpeech: false).sound, "none")
        XCTAssertEqual(RelayPolicy.notification(for: env(["title": "T", "sound": "default"]), silenceSpeech: false).sound, "default")
        XCTAssertNil(RelayPolicy.notification(for: env(["title": "T", "sound": "/System/Library/Sounds/Glass.aiff"]), silenceSpeech: false).sound)
        XCTAssertNil(RelayPolicy.notification(for: env(["title": "T", "sound": "../../etc/passwd"]), silenceSpeech: false).sound)
    }

    func testSpeakAsTextAndVoiceAndSpeedBesideIt() {
        let t = RelayPolicy.notification(for: env(["title": "T", "speak": "Build finished"]), silenceSpeech: false)
        XCTAssertEqual(t.speak?.text, "Build finished")
        let v = RelayPolicy.notification(for: env(["title": "T", "speak": true, "voice": "bf_emma", "speed": 1.3]), silenceSpeech: false)
        XCTAssertEqual(v.speak?.voice, "bf_emma")
        XCTAssertEqual(v.speak?.speed, 1.3)
        let alone = RelayPolicy.notification(for: env(["title": "T", "voice": "am_michael"]), silenceSpeech: false)
        XCTAssertEqual(alone.speak?.voice, "am_michael", "a voice alone turns speaking on")
        XCTAssertNil(RelayPolicy.notification(for: env(["title": "T", "speak": true, "voice": "x y; rm"]), silenceSpeech: false).speak?.voice)
    }

    func testPresentationVoiceAndBothImplySpeech() {
        let v = RelayPolicy.notification(for: env(["title": "T", "presentation": "voice"]), silenceSpeech: false)
        XCTAssertEqual(v.presentation, .voice)
        XCTAssertNotNil(v.speak)
        XCTAssertEqual(RelayPolicy.notification(for: env(["title": "T", "presentation": "both", "speak": "hi"]), silenceSpeech: false).presentation, .both)
        XCTAssertEqual(RelayPolicy.notification(for: env(["title": "T", "presentation": "banner"]), silenceSpeech: false).presentation, .banner)
        XCTAssertNil(RelayPolicy.notification(for: env(["title": "T", "presentation": "popup"]), silenceSpeech: false).presentation)
        // quiet hours that silence speech never leave a voice-only notification with nothing: the banner shows
        let q = RelayPolicy.notification(for: env(["title": "T", "presentation": "voice", "speak": true]), silenceSpeech: true)
        XCTAssertNil(q.speak)
        XCTAssertNil(q.presentation)
    }

    func testPriorityGroupSubtitleImageAndTags() {
        let n = RelayPolicy.notification(for: env(["title": "T", "priority": "high", "group": "ci", "subtitle": "main", "imageURL": "https://example.com/a.png", "tags": ["ci", " main ", ""]]), silenceSpeech: false)
        XCTAssertEqual(n.priority, "high")
        XCTAssertEqual(n.group, "ci")
        XCTAssertEqual(n.subtitle, "main")
        XCTAssertEqual(n.image, "https://example.com/a.png")
        if case .object(let o)? = n.metadata { XCTAssertEqual(o["tags"], .array([.string("ci"), .string("main")])) } else { XCTFail("no metadata") }
        XCTAssertNil(RelayPolicy.notification(for: env(["title": "T", "imageURL": "http://example.com/a.png"]), silenceSpeech: false).image)
        XCTAssertNil(RelayPolicy.notification(for: env(["title": "T", "imageURL": "file:///etc/passwd"]), silenceSpeech: false).image)
        XCTAssertNil(RelayPolicy.notification(for: env(["title": "T", "priority": "normal"]), silenceSpeech: false).priority)
    }

    func testIconSourceAcceptsOnlyHttpsAndSmallDataImages() {
        XCTAssertEqual(RelayPolicy.iconSource(for: env(["title": "T", "icon": "https://example.com/i.png"])), "https://example.com/i.png")
        XCTAssertNotNil(RelayPolicy.iconSource(for: env(["title": "T", "icon": "data:image/png;base64,iVBORw0KGgo="])))
        XCTAssertNil(RelayPolicy.iconSource(for: env(["title": "T", "icon": "http://example.com/i.png"])))
        XCTAssertNil(RelayPolicy.iconSource(for: env(["title": "T", "icon": "/Users/me/i.png"])))
        XCTAssertNil(RelayPolicy.iconSource(for: env(["title": "T", "icon": "file:///etc/passwd"])))
        XCTAssertNil(RelayPolicy.iconSource(for: env(["title": "T"])))
    }

    func testTheRelayDropsEveryExecutableFieldEvenIfAHostileRelaySendsIt() {
        let n = RelayPolicy.notification(for: env(["title": "T", "command": "rm -rf /", "buttons": [["label": "x", "command": "ls"]], "callback": ["url": "https://evil.example"],
                                                    "script": "a.sh", "shortcut": "Run", "audio": "/tmp/a.wav", "url": "https://evil.example", "template": "x"]), silenceSpeech: false)
        XCTAssertNil(n.buttons)
        XCTAssertNil(n.url)
        XCTAssertNil(n.template)
        XCTAssertNil(n.reminder)
        let json = String(data: try! JSONEncoder().encode(n), encoding: .utf8)!
        for bad in ["rm -rf", "evil.example", "a.sh", "Run", "a.wav"] { XCTAssertFalse(json.contains(bad), bad) }
    }
}

final class ConnectorConfigTests: XCTestCase {
    func testBlockHasUrlBearerAndClientForms() {
        let b = ConnectorConfig.block(relayURL: "https://r.example.workers.dev/", key: "hrk_k", name: "build-bot")
        XCTAssertEqual(ConnectorConfig.mcpURL(relay: "https://r.example.workers.dev/"), "https://r.example.workers.dev/mcp")
        XCTAssertTrue(b.contains("URL:            https://r.example.workers.dev/mcp"))
        XCTAssertTrue(b.contains("Authorization:  Bearer hrk_k"))
        XCTAssertTrue(b.contains(#"claude mcp add --transport http herald https://r.example.workers.dev/mcp --header "Authorization: Bearer hrk_k""#))
        XCTAssertTrue(b.contains("[mcp_servers.herald]"))
        XCTAssertTrue(b.contains(#"bearer_token_env_var = "HERALD_RELAY_KEY""#))
        XCTAssertTrue(b.contains(#""headers":{"Authorization":"Bearer hrk_k"}"#))
        XCTAssertFalse(b.contains("//mcp"))
    }
}

final class RelayStoreTests: XCTestCase {
    func testStatePersistsAndTheLogKeepsTheLast20() {
        let file = tmp("state.json")
        defer { try? FileManager.default.removeItem(at: file) }
        let a = RelayStateStore(file: file)
        XCTAssertEqual(a.value.relayURL, "")
        a.update { $0.relayURL = "https://other.example"; $0.deviceId = "dev1"; $0.pairedAt = Date(timeIntervalSince1970: 1_000_000) }
        for i in 0..<25 {
            a.logEntry("r\(i)", create: RelayLogEntry(id: "r\(i)", key: "k", title: "t\(i)", receivedAt: Date())) { $0.displayed = true }
        }
        let b = RelayStateStore(file: file)
        XCTAssertEqual(b.value.relayURL, "https://other.example")
        XCTAssertEqual(b.value.deviceId, "dev1")
        XCTAssertEqual(b.value.log.count, 20)
        XCTAssertEqual(b.value.log.first?.id, "r24", "newest first")
        XCTAssertEqual(b.value.log.first?.summary, "displayed")
    }

    func testLogEntryUpdatesInPlace() {
        let s = RelayStateStore(file: nil)
        s.logEntry("x", create: RelayLogEntry(id: "x", key: "k", title: "t", receivedAt: Date())) { _ in }
        s.logEntry("x", create: RelayLogEntry(id: "x", key: "k", title: "t", receivedAt: Date())) { $0.spoken = true; $0.replied = true }
        XCTAssertEqual(s.value.log.count, 1)
        XCTAssertEqual(s.value.log[0].summary, "spoken, replied")
    }

    func testTokenStoreRoundTrip() {
        let t = MemoryTokenStore()
        XCTAssertNil(t.load())
        XCTAssertTrue(t.save("hrd_abc"))
        XCTAssertEqual(t.load(), "hrd_abc")
        t.delete()
        XCTAssertNil(t.load())
    }
}

final class RecordingHTTP: RelayHTTP, @unchecked Sendable {
    var requests: [URLRequest] = []
    var status = 200
    var body = "{}"
    var headers: [String: String] = [:]
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let r = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: headers)!
        return (Data(body.utf8), r)
    }
}

final class RelayAPITests: XCTestCase {
    private let base = URL(string: "https://relay.example")!

    func testPairingCallsAreUnauthenticatedAndKeyCallsCarryTheToken() async throws {
        let http = RecordingHTTP()
        http.body = #"{"code":"ABCD-EFGH","expiresInSeconds":600}"#
        let api = RelayAPI(baseURL: base, token: nil, http: http)
        let start = try await api.startPairing(deviceName: "Mac")
        XCTAssertEqual(start.code, "ABCD-EFGH")
        XCTAssertEqual(http.requests[0].url?.path, "/v1/pair/start")
        XCTAssertNil(http.requests[0].value(forHTTPHeaderField: "Authorization"))

        http.body = #"{"deviceId":"d","deviceToken":"hrd_x"}"#
        let paired = try await api.pair(code: "ABCD-EFGH", deviceName: "Mac")
        XCTAssertEqual(paired.deviceToken, "hrd_x")

        var authed = RelayAPI(baseURL: base, token: "hrd_x", http: http)
        http.body = #"{"id":"a1b2c3d4","name":"bot","client":"claude","scope":"notify","key":"hrk_secret"}"#
        let k = try await authed.createKey(name: "bot", client: "claude")
        XCTAssertEqual(k.key, "hrk_secret")
        let last = http.requests.last!
        XCTAssertEqual(last.url?.path, "/v1/device/keys")
        XCTAssertEqual(last.value(forHTTPHeaderField: "Authorization"), "Bearer hrd_x")
        let sent = try JSONSerialization.jsonObject(with: last.httpBody!) as! [String: String]
        XCTAssertEqual(sent["scope"], "notify", "Herald only ever asks for the notify scope")

        authed.token = nil
        do { _ = try await authed.listKeys(); XCTFail("needs a token") } catch { XCTAssertEqual(error as? RelayError, .notPaired) }
    }

    func testAudioUploadIsRawM4aAndCappedAtOneMegabyte() async throws {
        let http = RecordingHTTP()
        let api = RelayAPI(baseURL: base, token: "hrd_x", http: http)
        try await api.uploadAudio(id: "r_aaa", m4a: Data(count: 1000))
        let r = http.requests[0]
        XCTAssertEqual(r.httpMethod, "PUT")
        XCTAssertEqual(r.url?.path, "/v1/device/reply/r_aaa/audio")
        XCTAssertEqual(r.value(forHTTPHeaderField: "Content-Type"), "audio/mp4")
        XCTAssertEqual(r.httpBody?.count, 1000)
        do { try await api.uploadAudio(id: "r_aaa", m4a: Data(count: RelayAPI.maxAudioBytes + 1)); XCTFail("too big") }
        catch { XCTAssertEqual(error as? RelayError, .http(413, "audio is larger than 1 MB")) }
        XCTAssertEqual(http.requests.count, 1, "an oversize file never leaves the Mac")
        try await api.uploadAudio(id: "r_aaa", m4a: Data(count: RelayAPI.maxAudioBytes))
    }

    func testVoiceReplyReceiptGoesToTheReplyRoute() async throws {
        let http = RecordingHTTP()
        let api = RelayAPI(baseURL: base, token: "hrd_x", http: http)
        try await api.sendReceipt(RelayReceipt(id: "r_aaa", kind: .replied, transcript: "ship it", durationSeconds: 3.5))
        XCTAssertEqual(http.requests[0].url?.path, "/v1/device/reply")
        let o = try JSONSerialization.jsonObject(with: http.requests[0].httpBody!) as! [String: Any]
        XCTAssertEqual(o["transcript"] as? String, "ship it")
        XCTAssertEqual(o["durationSeconds"] as? Double, 3.5)
        try await api.sendReceipt(RelayReceipt(id: "r_aaa", kind: .displayed))
        XCTAssertEqual(http.requests[1].url?.path, "/v1/device/receipt")
    }

    func testLimitsAreRecognisedWithRetryAfter() async {
        let http = RecordingHTTP()
        http.status = 503
        http.body = #"{"error":"budget_exhausted","message":"the relay's daily request budget is used up"}"#
        http.headers = ["Retry-After": "3600"]
        let api = RelayAPI(baseURL: base, token: "hrd_x", http: http)
        do { _ = try await api.usage(); XCTFail() }
        catch { XCTAssertEqual(error as? RelayError, .limited("the relay's daily request budget is used up", retryAfter: 3600)) }
        XCTAssertEqual(RelayConnectionState.limited("x").label, "Relay offline \u{2014} limit reached")
    }
}

final class RelayRoutesTests: XCTestCase {
    final class FakeBackend: RelayBackend, @unchecked Sendable {
        var revoked: [String] = []
        func relayStatus() async -> RelayStatusReply {
            RelayStatusReply(paired: true, state: "Online", online: true, relayURL: "https://r", mcpURL: "https://r/mcp", deviceId: "d", lastSeenAt: nil, keys: [], log: [])
        }
        func relayConnectors() async -> RelayConnectorsReply { RelayConnectorsReply() }
        func relayPair() async throws -> (code: String, deviceId: String) { ("ABCD-EFGH", "d") }
        func relayUnpair() async throws {}
        func relayCreateKey(name: String, client: String) async throws -> RelayKeyCreated {
            RelayKeyCreated(id: "a1b2c3d4", name: name, client: client, scope: "notify", key: "hrk_x", mcpURL: "https://r/mcp", connectorConfig: "cfg")
        }
        func relayRevokeKey(id: String) async throws { revoked.append(id) }
        func relayUsage() async throws -> RelayUsage { throw RelayError.notPaired }
    }

    private func req(_ m: String, _ p: String, body: String = "", token: String? = "tok") -> HTTPRequest {
        HTTPRequest(method: m, path: p, headers: token.map { ["authorization": "Bearer \($0)"] } ?? [:], body: Data(body.utf8))
    }

    func testRoutesNeedTheTokenAndIgnoreOthers() async {
        let b = FakeBackend()
        let none = await RelayRoutes.handle(req("GET", "/v1/health"), token: "tok", backend: b)
        XCTAssertNil(none)
        let denied = await RelayRoutes.handle(req("GET", "/v1/relay/status", token: nil), token: "tok", backend: b)
        XCTAssertEqual(denied?.status, 401)
        let ok = await RelayRoutes.handle(req("GET", "/v1/relay/status"), token: "tok", backend: b)
        XCTAssertEqual(ok?.status, 200)
    }

    func testCreateAndRevokeKey() async throws {
        let b = FakeBackend()
        let created = await RelayRoutes.handle(req("POST", "/v1/relay/keys", body: #"{"name":"bot","client":"codex"}"#), token: "tok", backend: b)
        XCTAssertEqual(created?.status, 201)
        let o = try JSONSerialization.jsonObject(with: created!.body) as! [String: Any]
        XCTAssertEqual(o["key"] as? String, "hrk_x")
        XCTAssertEqual(o["scope"] as? String, "notify")
        let noName = await RelayRoutes.handle(req("POST", "/v1/relay/keys", body: "{}"), token: "tok", backend: b)
        XCTAssertEqual(noName?.status, 400)
        let revoked = await RelayRoutes.handle(req("DELETE", "/v1/relay/keys/a1b2c3d4"), token: "tok", backend: b)
        XCTAssertEqual(revoked?.status, 200)
        XCTAssertEqual(b.revoked, ["a1b2c3d4"])
        let bad = await RelayRoutes.handle(req("DELETE", "/v1/relay/keys/../../x"), token: "tok", backend: b)
        XCTAssertEqual(bad?.status, 400)
    }

    func testNoRouteExposesPermissionsOrCommands() async {
        let b = FakeBackend()
        for p in ["/v1/relay/permissions", "/v1/relay/admin", "/v1/relay/exec", "/v1/relay/settings"] {
            let r = await RelayRoutes.handle(req("POST", p, body: "{}"), token: "tok", backend: b)
            XCTAssertEqual(r?.status, 404, p)
        }
    }

    func testNotPairedMapsTo409() async {
        let r = await RelayRoutes.handle(req("GET", "/v1/relay/usage"), token: "tok", backend: FakeBackend())
        XCTAssertEqual(r?.status, 409)
    }
}

final class CloudIdentityTests: XCTestCase {
    func testCloudIssuerHasReplyRecordAndLinkAndNoOpen() throws {
        let claude = try XCTUnwrap(AgentIdentity(cloudKeyName: "Build Bot", client: "claude"))
        XCTAssertEqual(claude.appID, "cloud.build-bot")
        XCTAssertTrue(claude.isCloud)
        XCTAssertEqual(claude.kind, .claudeCode, "a Claude key takes Claude's icon")
        let m = claude.manifest()
        XCTAssertEqual(m.family, "cloud")
        XCTAssertEqual(m.actionIDs, ["reply", "record", "open-link"])
        XCTAssertNil(m.appBundleId); XCTAssertNil(m.appPath)
        XCTAssertEqual(AgentIdentity(cloudKeyName: "x", client: "codex")?.kind, .codex)
        XCTAssertEqual(AgentIdentity(cloudKeyName: "x", client: "other")?.kind, .generic)
        XCTAssertNil(AgentIdentity(cloudKeyName: "!!!", client: "claude"))
        XCTAssertEqual(AgentIdentity(kind: .claudeCode)?.appID, "agent.claude-code", "installed agents are unchanged")
    }

    func testRecordActionSurvivesTheManifestRoundTrip() throws {
        let m = AgentIdentity(cloudKeyName: "bot", client: "claude")!.manifest()
        let data = try HeraldJSON.encoder().encode(m)
        let back = try HeraldJSON.decoder().decode(HeraldManifest.self, from: data)
        let record = try XCTUnwrap(back.actions.first { $0.label == "Record" })
        XCTAssertEqual(record.reply?.voice, true)
        XCTAssertNil(back.actions.first { $0.label == "Reply" }?.reply?.voice)
    }

    func testRecordButtonResolvesToAVoiceReplyAction() throws {
        let m = AgentIdentity(cloudKeyName: "bot", client: "claude")!.manifest()
        var n = HeraldNotification(app: "cloud.bot", id: "r_1", title: "t")
        n.actionIds = ["reply", "record"]
        let resolved = ActionRunner.resolvedActions(notification: ActionResolver.materializingActionIDs(n, manifest: m), manifest: m, template: nil)
        let rec = try XCTUnwrap(resolved.first { $0.action.label == "Record" })
        XCTAssertEqual(rec.action.kind, .reply)
        XCTAssertEqual(rec.action.reply?.voice, true)
    }
}

// MARK: - Voice reply

@MainActor
private final class FakeRecorder: AudioRecording {
    var started: URL?
    var seconds = 4.2
    var cancelled = false
    var failToStart = false
    var bytes = 3000
    func start(to url: URL) throws {
        if failToStart { throw NSError(domain: "t", code: 1, userInfo: [NSLocalizedDescriptionKey: "no mic"]) }
        started = url
        try? Data(count: bytes).write(to: url)
    }
    func stop() -> Double { seconds }
    func cancel() { cancelled = true; if let u = started { try? FileManager.default.removeItem(at: u) } }
}

private struct FakeTranscriber: Transcribing {
    var text: String?
    var delay: UInt64 = 0
    func transcribe(_ url: URL) async -> String? {
        if delay > 0 { try? await Task.sleep(nanoseconds: delay) }
        return text
    }
}

@MainActor
final class VoiceReplySessionTests: XCTestCase {
    private func make(rec: FakeRecorder? = nil, transcript: String? = "ship it", allowed: Bool = true, delay: UInt64 = 0,
                      timeout: TimeInterval = 5) -> (VoiceReplySession, FakeRecorder, URL) {
        let rec = rec ?? FakeRecorder()
        let file = tmp("voice-\(UUID().uuidString).m4a")
        let s = VoiceReplySession(recorder: rec, transcriber: FakeTranscriber(text: transcript, delay: delay), permission: { allowed },
                                  file: file, transcribeTimeout: timeout)
        return (s, rec, file)
    }

    func testNothingStartsUntilStartIsCalled() {
        let (s, rec, _) = make()
        XCTAssertEqual(s.phase, .requestingPermission)
        XCTAssertNil(rec.started)
    }

    func testRecordsStopsTranscribesAndSends() async throws {
        let (s, rec, file) = make()
        defer { try? FileManager.default.removeItem(at: file) }
        var phases: [BannerRecordPrompt.Phase] = []
        s.onChange = { phases.append($0.phase) }
        await s.start()
        XCTAssertEqual(s.phase, .recording)
        XCTAssertEqual(rec.started, file)
        s.tick(1.5)
        XCTAssertEqual(s.prompt.elapsedText, "0:01")
        s.stop()
        XCTAssertEqual(s.phase, .recorded)
        var got: VoiceReplySession.Result?
        let result = await s.send { got = $0 }
        XCTAssertNotNil(result)
        XCTAssertEqual(got?.transcript, "ship it")
        XCTAssertEqual(got?.m4a.count, 3000)
        XCTAssertEqual(got?.seconds ?? 0, 4.2, accuracy: 0.001)
        XCTAssertTrue(phases.contains(.sending))
    }

    func testSendWhileRecordingStopsFirst() async {
        let (s, _, file) = make()
        defer { try? FileManager.default.removeItem(at: file) }
        await s.start()
        var n = 0
        _ = await s.send { _ in n += 1 }
        XCTAssertEqual(n, 1)
    }

    func testStopsByItselfAtSixtySeconds() async {
        let (s, _, file) = make()
        defer { try? FileManager.default.removeItem(at: file) }
        await s.start()
        for _ in 0..<700 { s.tick(0.1) }
        XCTAssertEqual(s.phase, .recorded)
        XCTAssertLessThanOrEqual(s.prompt.elapsed, 60.001)
        XCTAssertEqual(s.prompt.maxSeconds, 60)
    }

    func testNoTranscriptStillSendsTheAudio() async {
        for text in [nil, "   "] as [String?] {
            let (s, _, file) = make(transcript: text)
            await s.start(); s.stop()
            var got: VoiceReplySession.Result?
            _ = await s.send { got = $0 }
            XCTAssertNotNil(got, "the audio goes even with no transcript")
            XCTAssertNil(got?.transcript)
            try? FileManager.default.removeItem(at: file)
        }
    }

    func testSlowTranscriptionTimesOutToNoTranscript() async {
        let (s, _, file) = make(delay: 3_000_000_000, timeout: 0.1)
        defer { try? FileManager.default.removeItem(at: file) }
        await s.start(); s.stop()
        var got: VoiceReplySession.Result?
        _ = await s.send { got = $0 }
        XCTAssertNotNil(got)
        XCTAssertNil(got?.transcript)
    }

    func testDeniedMicrophoneFailsWithAnExplanationAndNeverRecords() async {
        let (s, rec, _) = make(allowed: false)
        await s.start()
        if case .failed(let why) = s.phase { XCTAssertTrue(why.contains("Microphone")) } else { XCTFail("\(s.phase)") }
        XCTAssertNil(rec.started)
    }

    func testRecorderErrorFails() async {
        let rec = FakeRecorder(); rec.failToStart = true
        let (s, _, _) = make(rec: rec)
        await s.start()
        if case .failed(let why) = s.phase { XCTAssertTrue(why.contains("no mic")) } else { XCTFail() }
    }

    func testOversizeRecordingIsNotUploaded() async {
        let rec = FakeRecorder(); rec.bytes = VoiceReplyLimits.maxUploadBytes + 1
        let (s, _, file) = make(rec: rec)
        defer { try? FileManager.default.removeItem(at: file) }
        await s.start(); s.stop()
        var called = false
        let r = await s.send { _ in called = true }
        XCTAssertNil(r)
        XCTAssertFalse(called)
        if case .failed = s.phase {} else { XCTFail() }
    }

    func testDeliveryFailureShowsAndKeepsTheRecording() async {
        let (s, _, file) = make()
        defer { try? FileManager.default.removeItem(at: file) }
        await s.start(); s.stop()
        let r = await s.send { _ in throw RelayError.transport("offline") }
        XCTAssertNil(r)
        if case .failed(let why) = s.phase { XCTAssertTrue(why.contains("offline")) } else { XCTFail() }
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
    }

    func testCancelDeletesTheFile() async {
        let (s, rec, file) = make()
        await s.start()
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        s.cancel()
        XCTAssertTrue(rec.cancelled)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }
}

// MARK: - Connector approvals (OAuth)

private func consentFrame(id: String = String(repeating: "a", count: 72), name: String = "ChatGPT", code: String = "042917",
                          expiresAt: String = "2099-01-01T00:00:00.000Z") -> String {
    let o: [String: Any] = ["type": "consent", "id": id, "clientId": "hc_1", "clientName": name, "redirectHost": "chatgpt.com",
                            "scope": "notify", "code": code, "status": "pending", "createdAt": "2026-10-02T10:00:00.000Z", "expiresAt": expiresAt]
    return String(data: try! JSONSerialization.data(withJSONObject: o), encoding: .utf8)!
}

@MainActor
final class ConnectorConsentHost: RelayHost {
    var requested: [RelayConsent] = []
    var resolved: [(String, String)] = []
    func relayInputs(for envelope: RelayEnvelope) -> (muted: Bool, quiet: HeraldQuietStatus) { (false, HeraldQuietStatus()) }
    func relayStatusNow() -> (muted: Bool, quiet: HeraldQuietStatus) { (false, HeraldQuietStatus()) }
    func relayEnsureIssuer(_ key: RelayKeyRef) async {}
    func relayDeliver(_ notification: HeraldNotification) async throws {}
    func relayConsentRequested(_ consent: RelayConsent) { requested.append(consent) }
    func relayConsentResolved(id: String, status: String) { resolved.append((id, status)) }
}

@MainActor
final class RelayConsentTests: XCTestCase {
    private func make(_ host: ConnectorConsentHost) -> RelayClient {
        let store = RelayStateStore(file: nil)
        store.update { $0.deviceId = "dev" }
        return RelayClient(host: host, store: store, dedupe: RelayDedupe(file: nil), tokens: MemoryTokenStore(token: "hrd_x"))
    }

    func testAConsentFrameReachesTheHostWithTheCodeAndTheClientName() async {
        let host = ConnectorConsentHost()
        let socket = FakeRelaySocket(incoming: [welcome, consentFrame()])
        try? await make(host).session(socket)
        XCTAssertEqual(host.requested.count, 1)
        let c = host.requested[0]
        XCTAssertEqual(c.clientName, "ChatGPT")
        XCTAssertEqual(c.redirectHost, "chatgpt.com")
        XCTAssertEqual(c.code, "042917")
        XCTAssertEqual(c.spacedCode, "042 917")
        XCTAssertEqual(c.scope, "notify")
        XCTAssertTrue(c.isPending())
        XCTAssertTrue(socket.receipts("displayed").isEmpty, "a consent is not a notification: no receipt, no ack")
        XCTAssertTrue(socket.frames.filter { $0["type"] as? String == "ack" }.isEmpty)
    }

    func testAResolvedFrameTellsTheHost() async {
        let host = ConnectorConsentHost()
        let socket = FakeRelaySocket(incoming: [welcome, #"{"type":"consent_resolved","id":"abc","status":"approved"}"#])
        try? await make(host).session(socket)
        XCTAssertEqual(host.resolved.count, 1)
        XCTAssertEqual(host.resolved[0].0, "abc")
        XCTAssertEqual(host.resolved[0].1, "approved")
    }

    func testAMalformedConsentIsIgnoredAndAHostWithoutConsentSupportIsUnaffected() async {
        let host = ConnectorConsentHost()
        let socket = FakeRelaySocket(incoming: [welcome, #"{"type":"consent","id":"x"}"#])
        try? await make(host).session(socket)
        XCTAssertTrue(host.requested.isEmpty)
        // The older fake host has no consent methods: the defaults ignore the frame.
        let plain = FakeRelayHost()
        let store = RelayStateStore(file: nil); store.update { $0.deviceId = "dev" }
        let c = RelayClient(host: plain, store: store, dedupe: RelayDedupe(file: nil), tokens: MemoryTokenStore(token: "hrd_x"))
        try? await c.session(FakeRelaySocket(incoming: [welcome, consentFrame()]))
        XCTAssertTrue(plain.delivered.isEmpty)
    }

    func testARedeliveredFlagReachesTheHost() async {
        let host = ConnectorConsentHost()
        let again = consentFrame().replacingOccurrences(of: #""type":"consent""#, with: #""type":"consent","redelivered":true"#)
        try? await make(host).session(FakeRelaySocket(incoming: [welcome, consentFrame(), again]))
        XCTAssertEqual(host.requested.map(\.redelivered), [nil, true])
    }

    // One request, one banner (the ConsentBook rules the controller follows).

    private func consent(_ id: String = "r1", code: String = "111111", userCode: String? = "BDFG-HJKM", redelivered: Bool? = nil,
                         expires: String = "2099-01-01T00:00:00Z", status: String = "pending") -> RelayConsent {
        RelayConsent(id: id, clientId: "hc_1", clientName: "Cloud agent", code: code, status: status, expiresAt: expires,
                     flow: userCode == nil ? "code" : "device", userCode: userCode, redelivered: redelivered)
    }

    func testARepeatRequestIsOnePendingAndOneBannerUpdatedInPlace() {
        var book = ConsentBook()
        XCTAssertEqual(book.receive(consent()), .banner)                                  // the first: a banner
        XCTAssertEqual(book.receive(consent(code: "222222", userCode: "WXZT-QRNM")), .banner)   // the same request, a new code: updated in place
        XCTAssertEqual(book.receive(consent(code: "222222", userCode: "WXZT-QRNM")), .none)     // an identical repeat: nothing
        XCTAssertEqual(book.pending.count, 1)                                              // never a second entry
        XCTAssertEqual(book.pending.first?.userCode, "WXZT-QRNM")
        XCTAssertEqual(book.receive(consent("r2")), .banner)                               // a different request is its own
        XCTAssertEqual(book.pending.map(\.id), ["r2", "r1"])
    }

    func testAReconnectRefreshesTheListAndShowsNoBanner() {
        var book = ConsentBook()
        XCTAssertEqual(book.receive(consent()), .banner)
        XCTAssertEqual(book.receive(consent(redelivered: true)), .listOnly)              // the relay re-sent it after a reconnect
        XCTAssertEqual(book.receive(consent("r9", redelivered: true)), .listOnly)        // even one Herald had not seen (it was shown before a restart)
        XCTAssertEqual(book.pending.count, 2)
    }

    func testAnExpiredRequestIsDroppedFromThePendingList() {
        var book = ConsentBook()
        let soon = ISO8601DateFormatter().string(from: Date().addingTimeInterval(60))
        book.receive(consent("a", expires: soon)); book.receive(consent("b"))
        XCTAssertEqual(book.nextExpiry.map { $0 < Date().addingTimeInterval(120) }, true)
        XCTAssertEqual(book.receive(consent("c", expires: "2020-01-01T00:00:00Z")), .none)   // arrives already expired: not kept, no banner
        XCTAssertEqual(book.pending.map(\.id), ["b", "a"])
        let gone = book.expire(now: Date().addingTimeInterval(120))
        XCTAssertEqual(gone.map(\.id), ["a"]); XCTAssertEqual(book.pending.map(\.id), ["b"])
        // the relay says it expired (or was decided elsewhere): the same, by id
        XCTAssertTrue(book.remove(id: "b")); XCTAssertFalse(book.remove(id: "b")); XCTAssertTrue(book.pending.isEmpty)
    }

    func testAnApprovedOrDeniedFrameRemovesTheRequestEverywhere() {
        var book = ConsentBook()
        book.receive(consent())
        // a settled consent frame (status approved) is not pending: the entry goes
        XCTAssertEqual(book.receive(consent(status: "approved")), .listOnly)
        XCTAssertTrue(book.pending.isEmpty)
        XCTAssertEqual(book.receive(consent(status: "superseded")), .none)
    }

    func testTheRelaysListIsReadSilently() {
        var book = ConsentBook()
        book.receive(consent("known"))
        let fresh = book.replaceAll(with: [consent("known"), consent("new"), consent("old", expires: "2020-01-01T00:00:00Z"), consent("done", status: "approved")])
        XCTAssertEqual(fresh.map(\.id), ["new"])                                           // not known before, still no banner is implied
        XCTAssertEqual(Set(book.pending.map(\.id)), ["known", "new"])
    }

    func testTheBannerNamesTheClientAndTheCodeTheAgentPrinted() {
        let q = BannerConfirmation.connectorConsent(name: "Cloud agent", host: "", code: "BDFG-HJKM")
        XCTAssertTrue(q.title.contains("Cloud agent")); XCTAssertTrue(q.title.contains("BDFG-HJKM"))
        XCTAssertTrue(q.detail.contains("BDFG-HJKM"))
        XCTAssertEqual(q.buttons.map(\.title), ["Approve", "Deny"])
    }

    func testAnExpiredConsentIsNotPending() {
        let past = RelayConsent(id: "i", clientName: "X", code: "123456", expiresAt: "2020-01-01T00:00:00.000Z")
        XCTAssertFalse(past.isPending())
        XCTAssertTrue(RelayConsent(id: "i", clientName: "X", code: "123456", expiresAt: "2099-01-01T00:00:00Z").isPending())
        XCTAssertFalse(RelayConsent(id: "i", clientName: "X", code: "123456", status: "approved").isPending())
    }

    func testKeyListShowsAnOAuthKeyUnderTheConnectorsName() throws {
        let json = #"{"keys":[{"id":"a1b2c3d4","name":"chatgpt","client":"other","scope":"notify","kind":"oauth","displayName":"ChatGPT","createdAt":"2026-10-02T10:00:00.000Z"},{"id":"e5f6a7b8","name":"bot","client":"claude","scope":"notify","kind":"static"},{"id":"11112222","name":"old","client":"claude","scope":"notify"}]}"#
        struct R: Decodable { var keys: [RelayKeyInfo] }
        let keys = try JSONDecoder().decode(R.self, from: Data(json.utf8)).keys
        XCTAssertTrue(keys[0].isOAuth)
        XCTAssertEqual(keys[0].title, "ChatGPT")
        XCTAssertFalse(keys[1].isOAuth)
        XCTAssertEqual(keys[1].title, "bot")
        XCTAssertFalse(keys[2].isOAuth, "a relay from before OAuth sends no kind")
    }

    func testTheBannerAsksApproveOrDenyAndNeverAnythingElse() {
        let c = BannerConfirmation.connectorConsent(name: "ChatGPT", host: "chatgpt.com")
        XCTAssertEqual(c.kind, .connectorConsent)
        XCTAssertEqual(c.title, "Let ChatGPT send you notifications?")
        XCTAssertEqual(c.buttons.map(\.title), ["Approve", "Deny"])
        XCTAssertEqual(c.buttons.map(\.choice), [.approve, .deny])
        XCTAssertTrue(c.detail.contains("chatgpt.com"))
        XCTAssertTrue(c.detail.contains("Nothing else"))
        XCTAssertFalse(c.offers(.always), "no lasting approval for a connector")
        let p = try? BannerConfirmation.fromPreview("connectorConsent", defaultName: "ChatGPT")
        XCTAssertEqual(p?.kind, .connectorConsent)
    }

    func testADeviceConsentCarriesTheUserCodeToTheHostAndTheList() async {
        let host = ConnectorConsentHost()
        let frame = #"{"type":"consent","id":"d1","clientId":"hc_1","clientName":"Cloud agent","redirectHost":"","scope":"notify","code":"042917","status":"pending","flow":"device","userCode":"BDFG-HJKM","createdAt":"2026-10-02T10:00:00.000Z","expiresAt":"2099-10-02T10:10:00.000Z"}"#
        try? await make(host).session(FakeRelaySocket(incoming: [welcome, frame]))
        XCTAssertEqual(host.requested.count, 1)
        let c = host.requested[0]
        XCTAssertTrue(c.isDevice)
        XCTAssertEqual(c.userCode, "BDFG-HJKM")
        XCTAssertEqual(c.code, "042917", "the 6-digit approval code stays for the /activate page")
        XCTAssertEqual(c.clientName, "Cloud agent")
        XCTAssertTrue(c.isPending())
        // the Settings list (GET /v1/device/consents) decodes the same fields
        struct R: Decodable { var consents: [RelayConsent] }
        let list = try? JSONDecoder().decode(R.self, from: Data(#"{"consents":[\#(frame)]}"#.utf8))
        XCTAssertEqual(list?.consents.first?.userCode, "BDFG-HJKM")
        // a browser-flow consent from the same relay has no user code
        XCTAssertFalse(RelayConsent(id: "i", clientName: "X", code: "123456", flow: "code").isDevice)
        XCTAssertFalse(RelayConsent(id: "i", clientName: "X", code: "123456").isDevice, "an older relay sends neither flow nor userCode")
    }

    func testTheDeviceBannerAsksToApproveWithTheCode() {
        let c = BannerConfirmation.connectorConsent(name: "Cloud agent", host: "its own site", code: "BDFG-HJKM")
        XCTAssertEqual(c.kind, .connectorConsent)
        XCTAssertEqual(c.title, "Approve Cloud agent to send you notifications? Code BDFG-HJKM")
        XCTAssertEqual(c.buttons.map(\.title), ["Approve", "Deny"])
        XCTAssertTrue(c.detail.contains("BDFG-HJKM"))
        XCTAssertTrue(c.detail.contains("Nothing else"))
        let p = try? BannerConfirmation.fromPreview(["kind": "connectorConsent", "code": "BDFG-HJKM"], defaultName: "Cloud agent")
        XCTAssertEqual(p?.title, c.title)
    }

    func testTheConsentStripResolvesOnTheBannerAndCancelLeavesItPending() {
        let surface = FakeSurface()
        surface.up = ["herald.connectors/r1"]
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("herald-consent-\(UUID().uuidString)")
        let flow = ConfirmationFlow(registry: AppRegistry(file: dir.appendingPathComponent("apps.json")),
                                    approvals: TemplateCommandApprovals(file: dir.appendingPathComponent("a.json")))
        flow.surface = surface
        defer { try? FileManager.default.removeItem(at: dir) }
        var answers: [ConfirmationChoice] = []
        flow.ask(.connectorConsent(name: "ChatGPT", host: "chatgpt.com"), app: "herald.connectors", id: "r1") { answers.append($0) }
        XCTAssertEqual(surface.shown["herald.connectors/r1"]?.kind, .connectorConsent)
        XCTAssertFalse(flow.answer(app: "herald.connectors", id: "r1", .once), "only Approve and Deny are offered")
        XCTAssertTrue(flow.answer(app: "herald.connectors", id: "r1", .approve))
        XCTAssertEqual(answers, [.approve])
        // a banner that goes away without an answer cancels: the caller treats that as "still pending"
        flow.ask(.connectorConsent(name: "ChatGPT", host: "chatgpt.com"), app: "herald.connectors", id: "r1") { answers.append($0) }
        flow.drop(app: "herald.connectors", id: "r1")
        XCTAssertEqual(answers, [.approve, .cancel])
    }

    func testApprovingAndDenyingGoToTheRelayAsDeviceConsentCalls() async throws {
        let http = RecordingHTTP()
        let api = RelayAPI(baseURL: URL(string: "https://r.example")!, token: "hrd_x", http: http)
        try await api.decideConsent(id: "rid", approve: true)
        try await api.decideConsent(id: "rid", approve: false)
        XCTAssertEqual(http.requests.map { $0.url?.path }, ["/v1/device/consent", "/v1/device/consent"])
        XCTAssertEqual(http.requests.map(\.httpMethod), ["POST", "POST"])
        XCTAssertEqual(http.requests[0].value(forHTTPHeaderField: "Authorization"), "Bearer hrd_x")
        let bodies = try http.requests.map { try JSONSerialization.jsonObject(with: $0.httpBody!) as! [String: String] }
        XCTAssertEqual(bodies[0], ["id": "rid", "decision": "approve"])
        XCTAssertEqual(bodies[1], ["id": "rid", "decision": "deny"])
    }

    func testTheConnectorsRouteNeedsTheTokenAndNeverCarriesACode() async throws {
        let b = RelayRoutesTests.FakeBackend()
        let denied = await RelayRoutes.handle(HTTPRequest(method: "GET", path: "/v1/relay/connectors", headers: [:], body: Data()), token: "tok", backend: b)
        XCTAssertEqual(denied?.status, 401)
        let ok = await RelayRoutes.handle(HTTPRequest(method: "GET", path: "/v1/relay/connectors", headers: ["authorization": "Bearer tok"], body: Data()), token: "tok", backend: b)
        XCTAssertEqual(ok?.status, 200)
        let o = try JSONSerialization.jsonObject(with: ok!.body) as! [String: Any]
        XCTAssertNotNil(o["connectors"])
        XCTAssertNotNil(o["pending"])
        let withPending = try JSONEncoder().encode(RelayConnectorsReply(pending: [.init(id: "i", clientName: "ChatGPT", redirectHost: "chatgpt.com", expiresAt: nil)]))
        XCTAssertFalse(String(decoding: withPending, as: UTF8.self).lowercased().contains("code"), "the 6-digit code stays on the Mac's screen")
    }
}

final class DeviceFlowInstructionsTests: XCTestCase {
    func testTheDeviceFlowTextHasTheExactSequence() {
        let t = RelayInstructions.deviceFlow(origin: "https://r.example.com/")
        for needle in ["POST https://r.example.com/register", "POST https://r.example.com/device_authorization", "TELL THE USER", "user_code",
                       "urn:ietf:params:oauth:grant-type:device_code", "authorization_pending", "slow_down", "access_denied", "expired_token", "https://r.example.com/mcp"] {
            XCTAssertTrue(t.contains(needle), needle)
        }
        XCTAssertFalse(t.contains("//register"))
        XCTAssertTrue(RelayInstructions.oauth(mcpURL: "https://r.example.com/mcp").contains("device flow"))
    }
}

final class RelayEventsRouteTests: XCTestCase {
    final class Backend: RelayBackend, @unchecked Sendable {
        var removed: [String] = []
        func relayStatus() async -> RelayStatusReply {
            RelayStatusReply(paired: true, state: "Online", online: true, relayURL: "https://r", mcpURL: "https://r/mcp", deviceId: "d", lastSeenAt: nil, keys: [], log: [])
        }
        func relayConnectors() async -> RelayConnectorsReply { RelayConnectorsReply() }
        func relayPair() async throws -> (code: String, deviceId: String) { ("ABCD-EFGH", "d") }
        func relayUnpair() async throws {}
        func relayCreateKey(name: String, client: String) async throws -> RelayKeyCreated { throw RelayError.notPaired }
        func relayRevokeKey(id: String) async throws {}
        func relayUsage() async throws -> RelayUsage { throw RelayError.notPaired }
        func relayEvents() async throws -> RelayEvents {
            RelayEvents(restrictedTo: [], subscriptions: [.init(id: "sub_0123456789abcdef0123", event: "notification.reply", host: "hooks.example.com",
                                                                 key: .init(id: "2ed25251", name: "dot-cloud", displayName: "Dot cloud computer"), createdAt: nil, pending: 0)])
        }
        func relayRemoveEventSubscription(id: String) async throws { removed.append(id) }
    }

    private func call(_ method: String, _ path: String, _ b: RelayBackend, auth: Bool = true) async -> HTTPResponse? {
        await RelayRoutes.handle(HTTPRequest(method: method, path: path, headers: auth ? ["authorization": "Bearer tok"] : [:], body: Data()), token: "tok", backend: b)
    }

    func testTheEventsRouteListsSubscriptionsWithoutPathsOrSecrets() async throws {
        let b = Backend()
        let denied = await call("GET", "/v1/relay/events", b, auth: false)
        XCTAssertEqual(denied?.status, 401)
        let ok = await call("GET", "/v1/relay/events", b)
        XCTAssertEqual(ok?.status, 200)
        let text = String(decoding: ok!.body, as: UTF8.self)
        XCTAssertTrue(text.contains("hooks.example.com"))
        XCTAssertTrue(text.contains("Dot cloud computer"))
        XCTAssertFalse(text.contains("whsec_"))
        XCTAssertFalse(text.contains("https://"))
    }

    func testEndingASubscriptionChecksTheIdShape() async {
        let b = Backend()
        let bad = await call("DELETE", "/v1/relay/events/subscriptions/nope", b)
        XCTAssertEqual(bad?.status, 400)
        let ok = await call("DELETE", "/v1/relay/events/subscriptions/sub_0123456789abcdef0123", b)
        XCTAssertEqual(ok?.status, 200)
        XCTAssertEqual(b.removed, ["sub_0123456789abcdef0123"])
    }

    func testABackendWithoutEventsAnswersNotPaired() async {
        let r = await call("GET", "/v1/relay/events", RelayRoutesTests.FakeBackend())
        XCTAssertEqual(r?.status, 409)
    }

    func testTheRelaysEventsAnswerDecodes() throws {
        let json = #"{"restrictedTo":[],"subscriptions":[{"id":"sub_0123456789abcdef0123","event":"notification.reply","host":"h.example.com","key":{"id":"2ed25251","name":"dot"},"createdAt":"2026-10-04T10:00:00.000Z","pending":2}]}"#
        let e = try HeraldJSONCoding.decoder.decode(RelayEvents.self, from: Data(json.utf8))
        XCTAssertEqual(e.subscriptions.first?.pending, 2)
        XCTAssertEqual(e.subscriptions.first?.key.title, "dot")
    }
}
