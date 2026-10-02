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

    func testExpectReplyMakesItPersistentWithAQuestionStatus() {
        let n = RelayPolicy.notification(for: env(["title": "T", "expectReply": true]), silenceSpeech: false)
        XCTAssertEqual(n.persistent, true)
        XCTAssertEqual(metaString(n, "status"), "question")
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
        XCTAssertEqual(a.value.relayURL, RelayDefaults.url)
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
