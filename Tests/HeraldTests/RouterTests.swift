import XCTest
@testable import HeraldCore

final class MockBackend: HeraldBackend, @unchecked Sendable {
    var notified: [HeraldNotification] = []
    var dismissed: [(String, String)] = []
    func notify(_ n: HeraldNotification) async throws -> String { notified.append(n); return n.id ?? "gen" }
    func register(_ r: HeraldAppRegistration) async throws {}
    func dismiss(app: String, id: String) async throws { dismissed.append((app, id)) }
    func dismissAll(app: String?) async throws {}
    func history(app: String?, limit: Int) async throws -> [HeraldHistoryItem] { [] }
    func clearHistory(app: String?) async throws {}
    func apps() async throws -> [HeraldAppRegistration] { [HeraldAppRegistration(app: "a")] }
}

final class ComposeBackend: HeraldBackend, @unchecked Sendable {
    var composeCalls = 0
    func notify(_ n: HeraldNotification) async throws -> String { "x" }
    func register(_ r: HeraldAppRegistration) async throws {}
    func dismiss(app: String, id: String) async throws {}
    func dismissAll(app: String?) async throws {}
    func history(app: String?, limit: Int) async throws -> [HeraldHistoryItem] { [] }
    func clearHistory(app: String?) async throws {}
    func apps() async throws -> [HeraldAppRegistration] { [] }
    func compose() async throws { composeCalls += 1 }
}

final class RouterTests: XCTestCase {
    let token = "secret-token"
    var backend = MockBackend()
    var router: Router!

    override func setUp() {
        backend = MockBackend()
        router = Router(token: token, backend: backend, version: "1.0.0", pid: 42)
    }

    private func req(_ method: String, _ path: String, token: String? = "secret-token", body: String = "",
                     query: [String: String] = [:]) -> HTTPRequest {
        var h: [String: String] = [:]
        if let token { h["authorization"] = "Bearer \(token)" }
        return HTTPRequest(method: method, path: path, query: query, headers: h, body: Data(body.utf8))
    }

    func testPayloadActionsAreTheIssuersButtonsNotMetadata() async throws {
        // The documented name `actions`, in the manifest's wire form, reaches the backend as `buttons`.
        var r = await router.handle(req("POST", "/v1/notify", body: """
        {"app":"x","title":"T","actions":[{"id":"markRead","label":"Mark as Read","kind":"callback"},
                                          {"label":"Open","url":"https://example.com"}]}
        """))
        XCTAssertEqual(r.status, 200, String(data: r.body, encoding: .utf8) ?? "")
        var n = try XCTUnwrap(backend.notified.last)
        XCTAssertEqual(n.buttons?.map(\.label), ["Mark as Read", "Open"])
        XCTAssertNotNil(n.buttons?.first?.callback, "kind callback means call the issuer back")
        XCTAssertEqual(n.buttons?.last?.url, "https://example.com")
        XCTAssertNil(n.metadata, "not diverted into metadata")

        // `buttons` wins when both are sent, and `actionIds` is a notification property of its own.
        r = await router.handle(req("POST", "/v1/notify", body: #"{"app":"x","title":"T","buttons":[{"label":"A"}],"actions":[{"label":"B"}],"actionIds":["markRead"]}"#))
        XCTAssertEqual(r.status, 200)
        n = try XCTUnwrap(backend.notified.last)
        XCTAssertEqual(n.buttons?.map(\.label), ["A"])
        XCTAssertEqual(n.actionIds, ["markRead"])
        XCTAssertNil(n.metadata)

        // A list that is not made of objects is a manifest field that happens to be called `actions`.
        r = await router.handle(req("POST", "/v1/notify", body: #"{"app":"x","title":"T","actions":["a","b"]}"#))
        XCTAssertEqual(r.status, 200)
        n = try XCTUnwrap(backend.notified.last)
        XCTAssertNil(n.buttons)
        guard case .object(let meta)? = n.metadata else { return XCTFail("expected metadata") }
        XCTAssertEqual(meta["actions"], .array([.string("a"), .string("b")]))
    }

    func testHealthNeedsNoAuth() async throws {
        let r = await router.handle(req("GET", "/v1/health", token: nil))
        XCTAssertEqual(r.status, 200)
        let h = try HeraldJSON.decoder().decode(HeraldHealth.self, from: r.body)
        XCTAssertEqual(h, HeraldHealth(ok: true, version: "1.0.0", pid: 42))
    }

    func testAuthRequiredElsewhere() async {
        for t in [nil, "wrong", "secret-token-x"] as [String?] {
            let r = await router.handle(req("GET", "/v1/apps", token: t))
            XCTAssertEqual(r.status, 401)
            XCTAssertEqual(String(data: r.body, encoding: .utf8), "{\"error\":\"unauthorized\"}")
        }
        let ok = await router.handle(req("GET", "/v1/apps"))
        XCTAssertEqual(ok.status, 200)
    }

    func testNotifyValidation() async {
        var r = await router.handle(req("POST", "/v1/notify", body: "{\"app\":\"a\"}"))
        XCTAssertEqual(r.status, 400)
        XCTAssertTrue(String(data: r.body, encoding: .utf8)!.contains("title"))
        r = await router.handle(req("POST", "/v1/notify", body: "not json"))
        XCTAssertEqual(r.status, 400)
        r = await router.handle(req("POST", "/v1/notify", body: "{\"app\":\"\",\"title\":\"t\"}"))
        XCTAssertEqual(r.status, 400)
    }

    func testNotifyOK() async {
        let r = await router.handle(req("POST", "/v1/notify", body: "{\"app\":\"a\",\"id\":\"i1\",\"title\":\"T\"}"))
        XCTAssertEqual(r.status, 200)
        XCTAssertEqual(String(data: r.body, encoding: .utf8), "{\"id\":\"i1\",\"ok\":true}")
        XCTAssertEqual(backend.notified.first?.title, "T")
    }

    func testDismissAndRouting() async {
        var r = await router.handle(req("POST", "/v1/dismiss", body: "{\"app\":\"a\",\"id\":\"i1\"}"))
        XCTAssertEqual(r.status, 200)
        XCTAssertEqual(backend.dismissed.first?.1, "i1")
        r = await router.handle(req("POST", "/v1/dismiss", body: "{\"app\":\"a\"}"))
        XCTAssertEqual(r.status, 400)
        r = await router.handle(req("GET", "/v1/notify"))
        XCTAssertEqual(r.status, 405)
        r = await router.handle(req("GET", "/v1/nope"))
        XCTAssertEqual(r.status, 404)
        r = await router.handle(req("GET", "/v1/history", query: ["app": "a", "limit": "5"]))
        XCTAssertEqual(r.status, 200)
        r = await router.handle(req("DELETE", "/v1/history", query: ["app": "a"]))
        XCTAssertEqual(r.status, 200)
    }

    func testHTTPParser() {
        let raw = "POST /v1/notify?x=1&y=a%20b HTTP/1.1\r\nHost: x\r\nContent-Length: 5\r\nAuthorization: Bearer t\r\n\r\nhello"
        if case .request(let r, let used) = HTTPParser.parse(Data(raw.utf8)) {
            XCTAssertEqual(r.method, "POST"); XCTAssertEqual(r.path, "/v1/notify")
            XCTAssertEqual(r.query, ["x": "1", "y": "a b"]); XCTAssertEqual(r.headers["authorization"], "Bearer t")
            XCTAssertEqual(String(data: r.body, encoding: .utf8), "hello"); XCTAssertEqual(used, raw.utf8.count)
        } else { XCTFail("expected request") }
        guard case .needMore = HTTPParser.parse(Data(raw.dropLast(2).utf8)) else { return XCTFail("expected needMore") }
        guard case .needMore = HTTPParser.parse(Data("GET / HTTP/1.1\r\nHost".utf8)) else { return XCTFail("needMore headers") }
        guard case .bad = HTTPParser.parse(Data("garbage\r\n\r\n".utf8)) else { return XCTFail("expected bad") }
        guard case .bad = HTTPParser.parse(Data("POST / HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\n".utf8)) else { return XCTFail("chunked") }
    }

    func testLoopbackListenerEndToEnd() async throws {
        let l = HTTPLoopbackListener(port: 0) { [router] in await router!.handle($0) }
        try l.start(); defer { l.stop() }
        var rq = URLRequest(url: URL(string: "http://127.0.0.1:\(l.port)/v1/health")!)
        rq.timeoutInterval = 5
        let (data, resp) = try await URLSession.shared.data(for: rq)
        XCTAssertEqual((resp as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertTrue(String(data: data, encoding: .utf8)!.contains("\"ok\":true"))
    }

    func testTokenFile() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("herald-tok-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let t = try TokenStore.loadOrCreate(in: dir)
        XCTAssertEqual(t.count, 64)
        XCTAssertEqual(try TokenStore.loadOrCreate(in: dir), t)
        let attrs = try FileManager.default.attributesOfItem(atPath: HeraldPaths.tokenURL(in: dir).path)
        XCTAssertEqual((attrs[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        try TokenStore.writePort(48617, in: dir)
        XCTAssertEqual(HeraldPaths.readPort(in: dir), 48617)
    }

    func testComposeRoute() async {
        let unauthorized = await router.handle(req("POST", "/v1/compose", token: nil))
        XCTAssertEqual(unauthorized.status, 401)
        let wrongMethod = await router.handle(req("GET", "/v1/compose"))
        XCTAssertEqual(wrongMethod.status, 405)
        // A backend that does not implement compose answers 501 rather than pretending.
        let unsupported = await router.handle(req("POST", "/v1/compose"))
        XCTAssertEqual(unsupported.status, 501)
        let b = ComposeBackend()
        let r2 = Router(token: token, backend: b, version: "1.0.0", pid: 1)
        let ok = await r2.handle(req("POST", "/v1/compose"))
        XCTAssertEqual(ok.status, 200)
        XCTAssertEqual(b.composeCalls, 1)
    }
}
