import XCTest
@testable import HeraldCore

final class CallbackSafetyTests: XCTestCase {
    private let event = HeraldCallbackEvent(notificationId: "n", app: "a", action: "Archive", payload: .object(["accountId": .string("u")]))
    private func delivery() -> CallbackDelivery {
        CallbackDelivery(policy: CallbackPolicy(timeout: 2, retries: 0, retryDelay: 0), log: { _ in })
    }

    func testOnlyLoopbackIsExemptFromApproval() {
        for u in ["http://127.0.0.1:5000/h", "http://localhost/h", "http://LOCALHOST:1/h", "http://[::1]:5000/h"] {
            XCTAssertFalse(CallbackDelivery.needsApproval(URL(string: u)!), u)
        }
        for u in ["https://attacker.example/c", "http://192.168.1.20/c", "http://127.0.0.2/c", "http://localhost.evil.example/c",
                  "http://127.0.0.1.evil.example/c", "http://10.0.0.1:80/c"] {
            XCTAssertTrue(CallbackDelivery.needsApproval(URL(string: u)!), u)
        }
    }

    /// Nothing is sent to a host the user has not approved (the reserved 192.0.2.0/24 range would never answer
    /// anyway, so a send attempt would show up as a timeout, not as this reason).
    func testANonLoopbackHostIsRefusedUntilApproved() async {
        let url = URL(string: "http://192.0.2.1:9/herald")!
        let outcome = await delivery().deliver(event, to: url)
        XCTAssertEqual(outcome, .failed(attempts: 0, reason: "callback host not approved"))
        let elsewhere = await delivery().deliver(event, to: url, approvedHosts: ["other.example"])
        XCTAssertEqual(elsewhere, .failed(attempts: 0, reason: "callback host not approved"))
    }

    func testAnApprovedHostPassesTheGate() async {
        // `.invalid` never resolves, so the attempt fails on the network, which proves the gate let it through.
        let outcome = await delivery().deliver(event, to: URL(string: "http://callback.invalid/herald")!, approvedHosts: ["callback.invalid"])
        guard case .failed(let attempts, let reason) = outcome else { return XCTFail("unexpected \(outcome)") }
        XCTAssertEqual(attempts, 1)
        XCTAssertNotEqual(reason, "callback host not approved")
    }

    func testLoopbackNeedsNoApproval() async throws {
        let server = ScriptedServer([.status(200)])
        let url = try server.start(); defer { server.stop() }
        let outcome = await delivery().deliver(event, to: url)
        XCTAssertEqual(outcome, .delivered(attempts: 1))
    }

    /// A 307 would make URLSession re-POST the body to the Location. It must come back as a failure instead.
    func testRedirectsAreNeverFollowed() async throws {
        let target = ScriptedServer([.status(200)])
        let targetURL = try target.start(); defer { target.stop() }
        for code in [301, 302, 307, 308] {
            let first = ScriptedServer([.redirect(code, to: targetURL.absoluteString)])
            let url = try first.start()
            let outcome = await delivery().deliver(event, to: url)
            first.stop()
            XCTAssertEqual(outcome, .failed(attempts: 1, reason: "HTTP \(code)"), "status \(code)")
            XCTAssertEqual(first.received.count, 1)
        }
        XCTAssertEqual(target.received.count, 0, "the redirect target never saw the event")
    }

    func testRegistryKeepsAnApprovedHostAcrossRelaunch() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("herald-ch-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("apps.json")
        let reg = AppRegistry(file: file)
        reg.register(HeraldAppRegistration(app: "a", callbackURL: "https://Hooks.Example:8443/x"))
        XCTAssertEqual(reg.record(for: "a")?.registeredCallbackHost, "hooks.example")
        XCTAssertNil(reg.record(for: "a")?.callbackHostApproved)
        reg.update("a") { $0.callbackHostApproved = "hooks.example" }
        XCTAssertEqual(AppRegistry(file: file).record(for: "a")?.callbackHostApproved, "hooks.example")
    }

    func testRecordsWrittenBeforeTheApprovalFieldStillDecode() throws {
        let legacy = Data(#"{"registration":{"app":"a"},"commandsConfirmed":true}"#.utf8)
        let rec = try HeraldJSON.decoder().decode(AppRecord.self, from: legacy)
        XCTAssertTrue(rec.commandsConfirmed)
        XCTAssertNil(rec.callbackHostApproved)
    }

    // MARK: The callback server's answer

    private func post(_ server: HeraldCallbackServer) async throws -> Int {
        var req = URLRequest(url: URL(string: server.callbackURL)!)
        req.httpMethod = "POST"
        req.httpBody = try HeraldJSON.encoder().encode(event)
        let (_, resp) = try await URLSession.shared.data(for: req)
        return (resp as! HTTPURLResponse).statusCode
    }

    func testCallbackServerAnswersWithTheStatusTheHandlerReturns() async throws {
        for status in [200, 409, 403, 504] {
            let server = HeraldCallbackServer(statusHandler: { _ in status })
            try server.start(); defer { server.stop() }
            let got = try await post(server)
            XCTAssertEqual(got, status)
        }
    }

    func testTheHandlerIsAwaitedBeforeTheAnswer() async throws {
        let server = HeraldCallbackServer(statusHandler: { _ in
            try? await Task.sleep(nanoseconds: 400_000_000)
            return 409
        })
        try server.start(); defer { server.stop() }
        let started = Date()
        let got = try await post(server)
        XCTAssertEqual(got, 409)
        XCTAssertGreaterThanOrEqual(Date().timeIntervalSince(started), 0.35)
    }
}
