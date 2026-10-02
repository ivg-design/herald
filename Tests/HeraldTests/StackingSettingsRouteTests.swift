import XCTest
@testable import HeraldCore

/// `GET/PUT /v1/settings/stacking`: the global stacking default, changeable without the bell menu (DESIGN section 9).
final class StackingSettingsRouteTests: XCTestCase {
    final class StackingBackend: HeraldBackend, @unchecked Sendable {
        var level = StackingLevel.defaultLevel
        func notify(_ n: HeraldNotification) async throws -> String { "x" }
        func register(_ r: HeraldAppRegistration) async throws {}
        func dismiss(app: String, id: String) async throws {}
        func dismissAll(app: String?) async throws {}
        func history(app: String?, limit: Int) async throws -> [HeraldHistoryItem] { [] }
        func clearHistory(app: String?) async throws {}
        func apps() async throws -> [HeraldAppRegistration] { [] }
        func stackingLevel() async throws -> StackingLevel { level }
        func setStackingLevel(_ l: StackingLevel) async throws -> StackingLevel { level = l; return l }
    }

    private func call(_ router: Router, _ method: String, _ body: String = "", token: String = "t") async -> HTTPResponse {
        await router.handle(HTTPRequest(method: method, path: "/v1/settings/stacking", query: [:],
                                        headers: ["authorization": "Bearer \(token)"], body: Data(body.utf8)))
    }

    private func level(_ r: HTTPResponse) throws -> String {
        let o = try JSONSerialization.jsonObject(with: r.body) as? [String: Any]
        return try XCTUnwrap(o?["level"] as? String)
    }

    func testGetPutAndRejects() async throws {
        let backend = StackingBackend()
        let router = Router(token: "t", backend: backend, version: "1", pid: 1)
        var r = await call(router, "GET")
        XCTAssertEqual(r.status, 200); XCTAssertEqual(try level(r), "bySender")
        for l in StackingLevel.allCases {
            r = await call(router, "PUT", #"{"level":"\#(l.rawValue)"}"#)
            XCTAssertEqual(r.status, 200); XCTAssertEqual(try level(r), l.rawValue); XCTAssertEqual(backend.level, l)
        }
        r = await call(router, "PUT", #"{"level":"bogus"}"#)
        XCTAssertEqual(r.status, 400); XCTAssertEqual(backend.level, .never)
        r = await call(router, "PUT", "{}")
        XCTAssertEqual(r.status, 400)
        r = await call(router, "GET", token: "wrong")
        XCTAssertEqual(r.status, 401)
        r = await call(router, "POST")
        XCTAssertEqual(r.status, 405)
    }

    func testUnsupportedBackendIs501() async {
        let router = Router(token: "t", backend: MockBackend(), version: "1", pid: 1)
        let r = await call(router, "GET")
        XCTAssertEqual(r.status, 501)
    }
}
