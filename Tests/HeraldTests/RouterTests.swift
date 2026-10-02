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

// MARK: POST /v1/rive/check (issues #33 and #38: the headless Rive test hook)

final class RiveCheckBackend: HeraldBackend, @unchecked Sendable {
    var seen: [RiveCheckRequest] = []
    func notify(_ n: HeraldNotification) async throws -> String { "x" }
    func register(_ r: HeraldAppRegistration) async throws {}
    func dismiss(app: String, id: String) async throws {}
    func dismissAll(app: String?) async throws {}
    func history(app: String?, limit: Int) async throws -> [HeraldHistoryItem] { [] }
    func clearHistory(app: String?) async throws {}
    func apps() async throws -> [HeraldAppRegistration] { [] }
    func riveCheck(_ r: RiveCheckRequest) async throws -> RiveCheckReply {
        seen.append(r)
        return RiveCheckReply(loaded: true, inputs: ["count": "number"], applied: ["count": "3.0"], takesClicks: true,
                              pointerWrites: ["hover": "true"], clickedActions: ["go"])
    }
}

final class RiveCheckRouteTests: XCTestCase {
    private func call(_ router: Router, _ method: String, body: String, token: String? = "t") async -> HTTPResponse {
        var h: [String: String] = [:]
        if let token { h["authorization"] = "Bearer \(token)" }
        return await router.handle(HTTPRequest(method: method, path: "/v1/rive/check", headers: h, body: Data(body.utf8)))
    }

    func testDecodesComponentFieldsAndPointerStepsAndReturnsTheReport() async throws {
        let b = RiveCheckBackend()
        let r = Router(token: "t", backend: b, version: "1", pid: 1)
        let res = await call(r, "POST", body: #"{"app":"a","component":{"asset":"marble","inputBindings":{"step":"{count}","hover":"hover"},"actionRef":"go"},"fields":{"count":3},"simulate":["hoverIn","pressDown","pressUp"]}"#)
        XCTAssertEqual(res.status, 200, String(data: res.body, encoding: .utf8) ?? "")
        let req = try XCTUnwrap(b.seen.first)
        XCTAssertEqual(req.app, "a")
        XCTAssertEqual(req.component.asset, "marble")
        XCTAssertEqual(req.component.inputBindings["step"], "{count}")
        XCTAssertEqual(req.fields?["count"], .number(3))
        XCTAssertEqual(req.simulate, ["hoverIn", "pressDown", "pressUp"])
        let reply = try JSONDecoder().decode(RiveCheckReply.self, from: res.body)
        XCTAssertTrue(reply.loaded)
        XCTAssertEqual(reply.clickedActions, ["go"])
        XCTAssertEqual(reply.pointerWrites, ["hover": "true"])
    }

    func testNeedsTokenAppAndPostAndIsUnsupportedWithoutABackend() async {
        let r = Router(token: "t", backend: RiveCheckBackend(), version: "1", pid: 1)
        let noToken = await call(r, "POST", body: "{}", token: nil)
        XCTAssertEqual(noToken.status, 401)
        let noApp = await call(r, "POST", body: #"{"app":"","component":{"path":"/x.riv"}}"#)
        XCTAssertEqual(noApp.status, 400)
        let wrongVerb = await call(r, "GET", body: "")
        XCTAssertEqual(wrongVerb.status, 405)
        let plain = Router(token: "t", backend: MockBackend(), version: "1", pid: 1)
        let unsupported = await call(plain, "POST", body: #"{"app":"a","component":{"path":"/x.riv"}}"#)
        XCTAssertEqual(unsupported.status, 501)
    }
}

final class DesignerSnapshotRouteTests: XCTestCase {
    final class B: HeraldBackend, @unchecked Sendable {
        var seen: [(String?, Int, Int)] = []
        func notify(_ n: HeraldNotification) async throws -> String { "x" }
        func register(_ r: HeraldAppRegistration) async throws {}
        func dismiss(app: String, id: String) async throws {}
        func dismissAll(app: String?) async throws {}
        func history(app: String?, limit: Int) async throws -> [HeraldHistoryItem] { [] }
        func clearHistory(app: String?) async throws {}
        func apps() async throws -> [HeraldAppRegistration] { [] }
        func designerSnapshot(app: String?, template: String?, select: String?, width: Int, height: Int) async throws -> Data { seen.append((app, width, height)); return Data([0x89]) }
    }
    func testDefaultsSizeLimitsAndVerbs() async {
        let b = B(); let r = Router(token: "t", backend: b, version: "1", pid: 1)
        func call(_ m: String, _ q: [String: String] = [:], _ body: String = "") async -> HTTPResponse {
            await r.handle(HTTPRequest(method: m, path: "/v1/designer/snapshot", query: q, headers: ["authorization": "Bearer t"], body: Data(body.utf8)))
        }
        let a = await call("GET"); XCTAssertEqual(a.status, 200)
        XCTAssertEqual(b.seen.last?.1, 1100); XCTAssertEqual(b.seen.last?.2, 820)
        let p = await call("POST", [:], #"{"app":"x","width":1800,"height":900}"#); XCTAssertEqual(p.status, 200)
        XCTAssertEqual(b.seen.last?.0, "x"); XCTAssertEqual(b.seen.last?.1, 1800)
        let bad = await call("GET", ["width": "10"]); XCTAssertEqual(bad.status, 400)
        let del = await call("DELETE"); XCTAssertEqual(del.status, 405)
    }
}
