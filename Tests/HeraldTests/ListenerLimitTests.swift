import XCTest
@testable import HeraldCore

/// A bare TCP client, so a test can send a head and nothing else, or just sit on a connection.
final class RawSocket {
    private let fd: Int32

    init?(port: Int) {
        fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = UInt16(port).bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        let rc = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        guard rc == 0 else { close(fd); return nil }
    }

    deinit { close(fd) }

    func send(_ text: String) { _ = text.withCString { Darwin.send(fd, $0, strlen($0), 0) } }

    /// Reads until the peer closes or `timeout` passes. `closed` is true when the peer hung up.
    func read(timeout: TimeInterval) -> (text: String, closed: Bool) {
        var tv = timeval(tv_sec: Int(timeout), tv_usec: Int32((timeout - Double(Int(timeout))) * 1_000_000))
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        var out = Data()
        var buf = [UInt8](repeating: 0, count: 4096)
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let n = recv(fd, &buf, buf.count, 0)
            if n > 0 { out.append(contentsOf: buf[0..<n]); continue }
            if n == 0 { return (String(decoding: out, as: UTF8.self), true) }
            if errno == EAGAIN || errno == EWOULDBLOCK { break }
            return (String(decoding: out, as: UTF8.self), true)   // reset: the server dropped us
        }
        return (String(decoding: out, as: UTF8.self), false)
    }
}

final class ListenerLimitTests: XCTestCase {
    private let token = "secret"

    private final class Counter: @unchecked Sendable {
        private let lock = NSLock(); private var n = 0
        func bump() { lock.lock(); n += 1; lock.unlock() }
        var value: Int { lock.lock(); defer { lock.unlock() }; return n }
    }

    private func makeListener(readTimeout: TimeInterval = 10, maxConnections: Int = 32, calls: Counter = Counter()) throws -> HTTPLoopbackListener {
        let l = HTTPLoopbackListener(port: 0, readTimeout: readTimeout, maxConnections: maxConnections,
                                     headCheck: BearerAuth.headCheck(token: token)) { req in
            calls.bump()
            return .json(200, ["bytes": req.body.count])
        }
        try l.start()
        return l
    }

    private func head(port: Int, method: String = "POST", path: String = "/v1/notify", length: Int, extra: String = "") -> String {
        "\(method) \(path) HTTP/1.1\r\nHost: 127.0.0.1:\(port)\r\nContent-Length: \(length)\r\n\(extra)\r\n"
    }

    // MARK: Refused before the body

    /// The attacker sends only a head that promises a 900 KB body. The answer comes straight away, so the body
    /// is neither awaited nor buffered.
    func testUnauthenticatedRequestIsAnsweredFromTheHeadAlone() throws {
        let calls = Counter()
        let l = try makeListener(calls: calls); defer { l.stop() }
        let s = try XCTUnwrap(RawSocket(port: l.port))
        s.send(head(port: l.port, length: 900_000))
        let r = s.read(timeout: 3)
        XCTAssertTrue(r.text.hasPrefix("HTTP/1.1 401"), r.text)
        XCTAssertTrue(r.closed)
        XCTAssertEqual(calls.value, 0)
    }

    func testAnnouncedBodyOverTheCapIsRefusedWithTheTokenToo() throws {
        let l = try makeListener(); defer { l.stop() }
        let s = try XCTUnwrap(RawSocket(port: l.port))
        s.send(head(port: l.port, length: HTTPParser.maxBodyBytes + 1, extra: "Authorization: Bearer \(token)\r\n"))
        XCTAssertTrue(s.read(timeout: 3).text.hasPrefix("HTTP/1.1 413"))
    }

    func testBrowserAndReboundHostRequestsAreRefused() throws {
        let calls = Counter()
        let l = try makeListener(calls: calls); defer { l.stop() }
        let auth = "Authorization: Bearer \(token)\r\n"
        let withOrigin = try XCTUnwrap(RawSocket(port: l.port))
        withOrigin.send(head(port: l.port, length: 0, extra: auth + "Origin: https://evil.example\r\n"))
        XCTAssertTrue(withOrigin.read(timeout: 3).text.hasPrefix("HTTP/1.1 403"))

        let rebound = try XCTUnwrap(RawSocket(port: l.port))
        rebound.send("POST /v1/notify HTTP/1.1\r\nHost: evil.example:\(l.port)\r\nContent-Length: 0\r\n\(auth)\r\n")
        XCTAssertTrue(rebound.read(timeout: 3).text.hasPrefix("HTTP/1.1 403"))
        XCTAssertEqual(calls.value, 0)
    }

    func testLoopbackHostSpellings() {
        for h in ["127.0.0.1", "127.0.0.1:48617", "localhost", "LOCALHOST:80", "[::1]", "[::1]:48617"] {
            XCTAssertTrue(HTTPParser.isLoopbackHost(h), h)
        }
        for h in ["evil.example", "evil.example:80", "127.0.0.1.evil.example", "localhost.evil.example", "[::2]:80", "10.0.0.1"] {
            XCTAssertFalse(HTTPParser.isLoopbackHost(h), h)
        }
    }

    // MARK: Still works

    func testAuthorizedRequestWithABodyReachesTheHandler() async throws {
        let calls = Counter()
        let l = try makeListener(calls: calls); defer { l.stop() }
        var req = URLRequest(url: URL(string: "http://127.0.0.1:\(l.port)/v1/notify")!)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.httpBody = Data(repeating: 65, count: 300_000)
        let (data, resp) = try await URLSession.shared.data(for: req)
        XCTAssertEqual((resp as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertEqual(String(decoding: data, as: UTF8.self), "{\"bytes\":300000}")
        XCTAssertEqual(calls.value, 1)

        var health = URLRequest(url: URL(string: "http://127.0.0.1:\(l.port)/v1/health")!)
        health.httpMethod = "GET"
        let (_, hr) = try await URLSession.shared.data(for: health)
        XCTAssertEqual((hr as? HTTPURLResponse)?.statusCode, 200, "health needs no token")
    }

    // MARK: Deadline and connection cap

    func testAnIdleOrDribblingConnectionIsClosed() throws {
        let l = try makeListener(readTimeout: 0.4); defer { l.stop() }
        let idle = try XCTUnwrap(RawSocket(port: l.port))
        XCTAssertTrue(idle.read(timeout: 3).closed, "nothing sent: reaped")

        let partial = try XCTUnwrap(RawSocket(port: l.port))
        partial.send("POST /v1/notify HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Length: 100\r\n\r\nonly a few bytes")
        XCTAssertTrue(partial.read(timeout: 3).closed, "body never completes: reaped")
    }

    func testConnectionsAreCappedAndTheSlotsComeBack() async throws {
        let l = try makeListener(maxConnections: 2); defer { l.stop() }
        var held: [RawSocket] = [try XCTUnwrap(RawSocket(port: l.port)), try XCTUnwrap(RawSocket(port: l.port))]
        try await Task.sleep(nanoseconds: 300_000_000)
        let third = try XCTUnwrap(RawSocket(port: l.port))
        XCTAssertTrue(third.read(timeout: 3).closed, "over the cap: dropped without being served")

        held.removeAll()   // closing the sockets frees both slots
        try await Task.sleep(nanoseconds: 600_000_000)
        var health = URLRequest(url: URL(string: "http://127.0.0.1:\(l.port)/v1/health")!)
        health.httpMethod = "GET"
        let (_, resp) = try await URLSession.shared.data(for: health)
        XCTAssertEqual((resp as? HTTPURLResponse)?.statusCode, 200)
    }

    // MARK: Parser

    func testHeadIsAvailableBeforeTheBody() {
        let partial = Data("POST /v1/notify?x=1 HTTP/1.1\r\nHost: h\r\nContent-Length: 50\r\n\r\n{\"half".utf8)
        guard case .head(let h) = HTTPParser.parseHead(partial) else { return XCTFail("head expected") }
        XCTAssertEqual(h.method, "POST"); XCTAssertEqual(h.path, "/v1/notify"); XCTAssertEqual(h.contentLength, 50)
        XCTAssertEqual(h.headers["host"], "h")
        guard case .needMore = HTTPParser.parse(partial) else { return XCTFail("body is incomplete") }
    }

    func testHeadLimits() {
        guard case .needMore = HTTPParser.parseHead(Data("POST / HTTP/1.1\r\nHost: h\r\n".utf8)) else { return XCTFail() }
        let big = Data("POST / HTTP/1.1\r\nX: \(String(repeating: "a", count: HTTPParser.maxHeaderBytes))\r\n\r\n".utf8)
        guard case .bad(let s, _) = HTTPParser.parseHead(big) else { return XCTFail("a long head is refused even once it is terminated") }
        XCTAssertEqual(s, 400)
        guard case .bad(let s2, _) = HTTPParser.parse(Data("POST / HTTP/1.1\r\nContent-Length: \(HTTPParser.maxBodyBytes + 1)\r\n\r\n".utf8)) else { return XCTFail() }
        XCTAssertEqual(s2, 413)
        XCTAssertLessThanOrEqual(HTTPParser.maxBodyBytes, 1024 * 1024)
    }

    func testResponseHeadersAreWrittenAndCannotInjectOthers() {
        let r = HTTPResponse(status: 307, headers: ["Location": "http://x/\r\nSet-Cookie: a=b"])
        let text = String(decoding: r.serialize(), as: UTF8.self)
        XCTAssertTrue(text.hasPrefix("HTTP/1.1 307 "))
        XCTAssertTrue(text.contains("Location: http://x/Set-Cookie: a=b\r\n"))
        XCTAssertFalse(text.contains("\r\nSet-Cookie"))
    }
}
