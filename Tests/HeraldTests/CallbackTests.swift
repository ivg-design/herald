import XCTest
@testable import HeraldCore

/// A loopback HTTP server that answers from a script: request N gets step N (the last step repeats).
final class ScriptedServer: @unchecked Sendable {
    enum Step { case status(Int), slow(seconds: Double, status: Int), redirect(Int, to: String) }

    private let lock = NSLock()
    private let steps: [Step]
    private var _received: [HTTPRequest] = []
    private var listener: HTTPLoopbackListener?

    init(_ steps: [Step]) { self.steps = steps }

    var received: [HTTPRequest] { lock.lock(); defer { lock.unlock() }; return _received }

    func start() throws -> URL {
        let l = HTTPLoopbackListener(port: 0) { [weak self] req in
            guard let self else { return .error(500, "gone") }
            return await self.answer(req)
        }
        try l.start()
        listener = l
        return URL(string: "http://127.0.0.1:\(l.port)/herald")!
    }

    func stop() { listener?.stop() }

    private func next(_ req: HTTPRequest) -> Step {
        lock.lock(); defer { lock.unlock() }
        _received.append(req)
        return steps[min(_received.count, steps.count) - 1]
    }

    private func answer(_ req: HTTPRequest) async -> HTTPResponse {
        switch next(req) {
        case .status(let code):
            return HTTPResponse(status: code)
        case .redirect(let code, let location):
            return HTTPResponse(status: code, headers: ["Location": location])
        case .slow(let seconds, let code):
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            return HTTPResponse(status: code)
        }
    }
}

/// A TCP port nothing is listening on (bind to port 0, read the number, close).
func unusedLoopbackPort() -> Int {
    let fd = socket(AF_INET, SOCK_STREAM, 0)
    defer { close(fd) }
    var addr = sockaddr_in()
    addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    addr.sin_family = sa_family_t(AF_INET)
    addr.sin_port = 0
    addr.sin_addr.s_addr = inet_addr("127.0.0.1")
    _ = withUnsafePointer(to: &addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }
    var len = socklen_t(MemoryLayout<sockaddr_in>.size)
    _ = withUnsafeMutablePointer(to: &addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &len) } }
    return Int(UInt16(bigEndian: addr.sin_port))
}

final class LogBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _lines: [String] = []
    func add(_ s: String) { lock.lock(); _lines.append(s); lock.unlock() }
    var lines: [String] { lock.lock(); defer { lock.unlock() }; return _lines }
}

final class CallbackTests: XCTestCase {
    private let event = HeraldCallbackEvent(notificationId: "bid-42", app: "bidbot", action: "Mark done",
                                            payload: .object(["bid": .number(42)]))
    private let quick = CallbackPolicy(timeout: 2, retries: 1, retryDelay: 0.05)

    private func delivery(_ policy: CallbackPolicy? = nil, log: LogBox = LogBox()) -> (CallbackDelivery, LogBox) {
        (CallbackDelivery(policy: policy ?? quick, log: { log.add($0) }), log)
    }

    private func serve(_ steps: [ScriptedServer.Step]) throws -> (ScriptedServer, URL) {
        let s = ScriptedServer(steps)
        let url = try s.start()
        addTeardownBlock { s.stop() }
        return (s, url)
    }

    func testDefaultPolicyIsFiveSecondsAndOneRetry() {
        XCTAssertEqual(CallbackPolicy.standard.timeout, 5)
        XCTAssertEqual(CallbackPolicy.standard.retries, 1)
    }

    func testDeliveredOnFirstAttemptWithTheEventAsJSON() async throws {
        let (server, url) = try serve([.status(200)])
        let (d, log) = delivery()
        let outcome = await d.deliver(event, to: url)
        XCTAssertEqual(outcome, .delivered(attempts: 1))
        XCTAssertTrue(log.lines.isEmpty)
        XCTAssertEqual(server.received.count, 1)
        let req = server.received[0]
        XCTAssertEqual(req.method, "POST")
        XCTAssertEqual(req.path, "/herald")
        XCTAssertEqual(req.headers["content-type"], "application/json")
        XCTAssertEqual(req.headers["x-herald-attempt"], "1")
        XCTAssertEqual(try HeraldJSON.decoder().decode(HeraldCallbackEvent.self, from: req.body), event)
    }

    func testAnyTwoHundredIsSuccess() async throws {
        for code in [201, 204] {
            let (server, url) = try serve([.status(code)])
            let (d, _) = delivery()
            let outcome = await d.deliver(event, to: url)
            XCTAssertEqual(outcome, .delivered(attempts: 1), "\(code)")
            XCTAssertEqual(server.received.count, 1)
        }
    }

    func testServerErrorIsRetriedOnceAndCanSucceed() async throws {
        let (server, url) = try serve([.status(500), .status(200)])
        let (d, log) = delivery()
        let outcome = await d.deliver(event, to: url)
        XCTAssertEqual(outcome, .delivered(attempts: 2))
        XCTAssertEqual(server.received.map { $0.headers["x-herald-attempt"] }, ["1", "2"])
        XCTAssertEqual(log.lines.count, 1, "the failed first attempt is logged")
        XCTAssertTrue(log.lines[0].contains("HTTP 500"))
    }

    func testGivesUpAfterExactlyOneRetry() async throws {
        let (server, url) = try serve([.status(503)])
        let (d, log) = delivery()
        let outcome = await d.deliver(event, to: url)
        XCTAssertEqual(outcome, .failed(attempts: 2, reason: "HTTP 503"))
        XCTAssertEqual(outcome.failureReason, "HTTP 503")
        XCTAssertFalse(outcome.isDelivered)
        XCTAssertEqual(server.received.count, 2)
        XCTAssertEqual(log.lines.count, 2, "every non-2xx answer is logged")
        XCTAssertTrue(log.lines.allSatisfy { $0.contains("HTTP 503") && $0.contains("bidbot") && $0.contains("Mark done") })
    }

    func testClientErrorIsNotRetried() async throws {
        let (server, url) = try serve([.status(404)])
        let (d, log) = delivery()
        let outcome = await d.deliver(event, to: url)
        XCTAssertEqual(outcome, .failed(attempts: 1, reason: "HTTP 404"))
        XCTAssertEqual(server.received.count, 1)
        XCTAssertEqual(log.lines.count, 1)
    }

    func testRetryLaterStatusesAreRetried() async throws {
        for code in [408, 429] {
            let (server, url) = try serve([.status(code), .status(200)])
            let (d, _) = delivery()
            let outcome = await d.deliver(event, to: url)
            XCTAssertEqual(outcome, .delivered(attempts: 2), "\(code)")
            XCTAssertEqual(server.received.count, 2)
        }
    }

    func testRetryClassification() {
        for s in [408, 429, 500, 502, 503, 599] { XCTAssertTrue(CallbackDelivery.isRetryable(status: s), "\(s)") }
        for s in [301, 400, 401, 403, 404, 409, 422] { XCTAssertFalse(CallbackDelivery.isRetryable(status: s), "\(s)") }
        XCTAssertTrue(CallbackDelivery.isRetryable(error: URLError(.timedOut)))
        XCTAssertTrue(CallbackDelivery.isRetryable(error: URLError(.cannotConnectToHost)))
        XCTAssertFalse(CallbackDelivery.isRetryable(error: URLError(.cancelled)))
        XCTAssertFalse(CallbackDelivery.isRetryable(error: URLError(.badURL)))
    }

    func testNoRetriesPolicyMakesOneAttempt() async throws {
        let (server, url) = try serve([.status(500)])
        let (d, _) = delivery(CallbackPolicy(timeout: 2, retries: 0, retryDelay: 0))
        let outcome = await d.deliver(event, to: url)
        XCTAssertEqual(outcome, .failed(attempts: 1, reason: "HTTP 500"))
        XCTAssertEqual(server.received.count, 1)
    }

    func testConnectionRefusedIsRetriedThenFails() async {
        let url = URL(string: "http://127.0.0.1:\(unusedLoopbackPort())/herald")!
        let (d, log) = delivery()
        let outcome = await d.deliver(event, to: url)
        XCTAssertEqual(outcome, .failed(attempts: 2, reason: "connection refused"))
        XCTAssertEqual(log.lines.count, 2)
    }

    func testTimeoutIsEnforcedPerAttemptAndRetried() async throws {
        let (server, url) = try serve([.slow(seconds: 3, status: 200)])
        let (d, _) = delivery(CallbackPolicy(timeout: 0.4, retries: 1, retryDelay: 0.05))
        let started = Date()
        let outcome = await d.deliver(event, to: url)
        let elapsed = Date().timeIntervalSince(started)
        XCTAssertEqual(outcome.failureReason, "timed out after 0.4 s")
        guard case .failed(let attempts, _) = outcome else { return XCTFail("\(outcome)") }
        XCTAssertEqual(attempts, 2)
        XCTAssertEqual(server.received.count, 2)
        XCTAssertLessThan(elapsed, 2.5, "two 0.4 s attempts, not the server's 3 s")
    }

    func testSlowFirstAttemptThenSuccess() async throws {
        let (server, url) = try serve([.slow(seconds: 3, status: 200), .status(200)])
        let (d, _) = delivery(CallbackPolicy(timeout: 0.4, retries: 1, retryDelay: 0.05))
        let outcome = await d.deliver(event, to: url)
        XCTAssertEqual(outcome, .delivered(attempts: 2))
        XCTAssertEqual(server.received.count, 2)
    }

    func testUnsupportedSchemeFailsWithoutAnyAttempt() async {
        let (d, log) = delivery()
        let outcome = await d.deliver(event, to: URL(string: "ftp://example.com/hook")!)
        XCTAssertEqual(outcome, .failed(attempts: 0, reason: "unsupported callback URL scheme"))
        XCTAssertEqual(log.lines.count, 1)
    }
}
