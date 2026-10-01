import XCTest
@testable import HeraldCore

final class ClientTests: XCTestCase {
    func testClientAgainstLocalServer() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("herald-client-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let token = try TokenStore.loadOrCreate(in: dir)
        let backend = MockBackend()
        let router = Router(token: token, backend: backend, version: "1.0.0")
        let l = HTTPLoopbackListener(port: 0) { await router.handle($0) }
        try l.start(); defer { l.stop() }
        try TokenStore.writePort(l.port, in: dir)

        let client = HeraldClient(supportDirectory: dir)
        XCTAssertTrue(client.isAvailable)
        let id = try await client.notify(HeraldNotification(app: "a", id: "n1", title: "Hi", buttons: [HeraldButton(label: "Go", url: "https://x")]))
        XCTAssertEqual(id, "n1")
        XCTAssertEqual(backend.notified.first?.buttons?.first?.label, "Go")
        try await client.dismiss(app: "a", id: "n1")
        XCTAssertEqual(backend.dismissed.count, 1)
        let h = try await client.health()
        XCTAssertTrue(h.ok)

        try "bad".write(to: HeraldPaths.tokenURL(in: dir), atomically: true, encoding: .utf8)
        do { _ = try await client.notify(HeraldNotification(app: "a", title: "x")); XCTFail() }
        catch { XCTAssertEqual(error as? HeraldError, .unauthorized) }
    }

    func testClientWhenNotRunning() async {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("herald-none-\(UUID().uuidString)")
        let client = HeraldClient(supportDirectory: dir)
        XCTAssertFalse(client.isAvailable)
        do { _ = try await client.notify(HeraldNotification(app: "a", title: "x")); XCTFail() }
        catch { XCTAssertEqual(error as? HeraldError, .notRunning) }
    }

    func testCallbackServerDeliversEvents() async throws {
        let got = expectation(description: "callback")
        let box = EventBox()
        let server = HeraldCallbackServer { e in box.event = e; got.fulfill() }
        try server.start(); defer { server.stop() }
        XCTAssertGreaterThan(server.port, 0)
        var req = URLRequest(url: URL(string: server.callbackURL)!)
        req.httpMethod = "POST"
        req.httpBody = try HeraldJSON.encoder().encode(
            HeraldCallbackEvent(notificationId: "n", app: "a", action: "Mark done", payload: .object(["bid": .number(42)])))
        let (_, resp) = try await URLSession.shared.data(for: req)
        XCTAssertEqual((resp as? HTTPURLResponse)?.statusCode, 200)
        await fulfillment(of: [got], timeout: 3)
        XCTAssertEqual(box.event?.action, "Mark done")
        XCTAssertEqual(box.event?.payload, .object(["bid": .number(42)]))
    }
    final class EventBox: @unchecked Sendable { var event: HeraldCallbackEvent? }
}
