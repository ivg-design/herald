import XCTest
@testable import HeraldCore
@testable import herald_mcp

// MARK: - A fake Herald

/// A stand-in for Herald.app's loopback API: it answers the endpoints the MCP tools use from in-memory
/// fixtures and records every request, so a tool call can be checked end to end (HeraldClient -> HTTP ->
/// here) without the app.
final class FakeHerald: @unchecked Sendable {
    struct Call {
        var method: String
        var path: String
        var query: [String: String]
        var body: Data
        var authorization: String?
        var json: JSONValue? { try? JSONDecoder().decode(JSONValue.self, from: body) }
    }

    static let token = "test-token"
    let directory: URL
    private let lock = NSLock()
    private var _calls: [Call] = []
    private var listener: HTTPLoopbackListener?

    // Fixtures (mutated by PUT/DELETE like the real thing).
    var manifests: [String: JSONValue] = [:]
    var templates: [String: [String: JSONValue]] = [:]
    var shortcuts: [String] = ["Create follow-up", "Log to Notes"]
    var history: [JSONValue] = []
    var components: JSONValue?
    var previewPNG = FakeHerald.png(width: 760, height: 400)
    var healthVersion = "1.1.0"

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("herald-mcp-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Self.token.write(to: HeraldPaths.tokenURL(in: directory), atomically: true, encoding: .utf8)
    }

    func start() throws {
        let l = HTTPLoopbackListener(port: 0) { [weak self] req in
            guard let self else { return .error(500, "gone") }
            return self.handle(req)
        }
        try l.start()
        listener = l
        try "\(l.port)".write(to: HeraldPaths.portURL(in: directory), atomically: true, encoding: .utf8)
    }

    func stop() {
        listener?.stop()
        try? FileManager.default.removeItem(at: directory)
    }

    var calls: [Call] { lock.lock(); defer { lock.unlock() }; return _calls }
    func calls(_ method: String, _ path: String) -> [Call] { calls.filter { $0.method == method && $0.path == path } }

    var client: HeraldClient { HeraldClient(supportDirectory: directory) }

    /// A PNG signature and IHDR chunk (not decodable as an image, which the tools never need).
    static func png(width: Int, height: Int) -> Data {
        func be(_ n: Int) -> [UInt8] { [UInt8(n >> 24 & 255), UInt8(n >> 16 & 255), UInt8(n >> 8 & 255), UInt8(n & 255)] }
        return Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A] + be(13) + Array("IHDR".utf8) + be(width) + be(height)
                    + [8, 6, 0, 0, 0] + be(0) + be(0) + Array("IEND".utf8) + be(0))
    }

    private func handle(_ req: HTTPRequest) -> HTTPResponse {
        lock.lock()
        _calls.append(Call(method: req.method, path: req.path, query: req.query, body: req.body,
                           authorization: req.headers["authorization"]))
        lock.unlock()

        if req.path == "/v1/health" { return .json(200, HeraldHealth(ok: true, version: healthVersion, pid: 4242)) }
        guard req.headers["authorization"] == "Bearer \(Self.token)" else { return .error(401, "unauthorized") }
        let body = (try? JSONDecoder().decode(JSONValue.self, from: req.body)) ?? .null
        lock.lock(); defer { lock.unlock() }

        switch (req.method, req.path) {
        case ("GET", "/v1/apps"):
            return .json(200, JSONValue.object(["apps": .array(manifests.keys.sorted().map { .object(["app": .string($0)]) })]))
        case ("GET", "/v1/manifests"):
            return .json(200, JSONValue.object(["items": .array(manifests.keys.sorted().compactMap { manifests[$0] })]))
        case ("GET", "/v1/manifest"):
            guard let m = manifests[req.query["app"] ?? ""] else { return .error(404, "manifest not found") }
            return .json(200, m)
        case ("PUT", "/v1/manifest"):
            guard let app = body["app"]?.stringValue else { return .error(400, "app is required") }
            manifests[app] = body
            return .json(200, ["ok": true])
        case ("GET", "/v1/templates"):
            let app = req.query["app"]
            let items = templates.keys.sorted().filter { app == nil || $0 == app }.flatMap { a in
                templates[a]!.keys.sorted().map { templates[a]![$0]! }
            }
            return .json(200, JSONValue.object(["items": .array(items)]))
        case ("PUT", "/v1/templates"):
            guard let app = body["app"]?.stringValue, let name = body["name"]?.stringValue else { return .error(400, "invalid template") }
            templates[app, default: [:]][name] = body
            return .json(200, ["ok": true])
        case ("DELETE", "/v1/templates"):
            guard templates[req.query["app"] ?? ""]?.removeValue(forKey: req.query["name"] ?? "") != nil else {
                return .error(404, "template not found")
            }
            return .json(200, ["ok": true])
        case ("GET", "/v1/components"):
            guard let c = components else { return .error(404, "not found") }
            return .json(200, c)
        case ("GET", "/v1/shortcuts"):
            return .json(200, JSONValue.object(["items": .array(shortcuts.map { .string($0) })]))
        case ("POST", "/v1/preview"):
            return HTTPResponse(status: 200, body: previewPNG)
        case ("POST", "/v1/notify"):
            return .json(200, JSONValue.object(["ok": .bool(true), "id": body["id"] ?? .string("generated-1")]))
        case ("POST", "/v1/dismiss"), ("POST", "/v1/dismissAll"):
            return .json(200, ["ok": true])
        case ("GET", "/v1/history"):
            return .json(200, JSONValue.object(["items": .array(history)]))
        default:
            return .error(404, "not found")
        }
    }
}

// MARK: - The real router behind the tools

/// An in-memory Herald backend behind the app's real `Router`, so the MCP tools are also checked against the
/// actual wire format (the fake above is hand-made from it).
final class MCPRouterBackend: HeraldBackend, @unchecked Sendable {
    private let lock = NSLock()
    private func locked<T>(_ body: () -> T) -> T { lock.lock(); defer { lock.unlock() }; return body() }

    var notified: [HeraldNotification] = []
    var manifestsByApp: [String: HeraldManifest] = [:]
    var templatesByKey: [String: HeraldTemplate] = [:]
    var previews: [PreviewSpec] = []
    var shortcutNames = ["Create follow-up", "Log to Notes"]

    func notify(_ n: HeraldNotification) async throws -> String { locked { notified.append(n) }; return n.id ?? "generated" }
    func register(_ r: HeraldAppRegistration) async throws {}
    func dismiss(app: String, id: String) async throws {}
    func dismissAll(app: String?) async throws {}
    func history(app: String?, limit: Int) async throws -> [HeraldHistoryItem] { [] }
    func clearHistory(app: String?) async throws {}
    func apps() async throws -> [HeraldAppRegistration] { [] }
    func templates(app: String?) async throws -> [HeraldTemplate] {
        locked { templatesByKey.values.filter { app == nil || $0.app == app }.sorted { $0.name < $1.name } }
    }
    func putTemplate(_ t: HeraldTemplate) async throws { locked { templatesByKey[t.app + "/" + t.name] = t } }
    func deleteTemplate(app: String, name: String) async throws {
        guard locked({ templatesByKey.removeValue(forKey: app + "/" + name) }) != nil else { throw BackendError(404, "template not found") }
    }
    func manifests() async throws -> [HeraldManifest] { locked { manifestsByApp.values.sorted { $0.app < $1.app } } }
    func manifest(app: String) async throws -> HeraldManifest? { locked { manifestsByApp[app] } }
    func putManifest(_ m: HeraldManifest) async throws { locked { manifestsByApp[m.app] = m } }
    func deleteManifest(app: String) async throws {}
    func shortcuts() async throws -> [String] { shortcutNames }
    func preview(_ request: PreviewSpec) async throws -> Data {
        locked { previews.append(request) }
        return FakeHerald.png(width: 700, height: 220)
    }
}

// MARK: - Fixtures

enum MCPFixtures {
    static let manifest = """
    {"app":"webwatcher.email","appName":"WebWatcher Email","version":1,
     "fields":[{"key":"title","type":"text","required":true,"sample":"2 new from Acme Billing"},
               {"key":"subject","type":"text","sample":"Invoice #4021"},{"key":"sender","type":"text","sample":"Acme Billing"},
               {"key":"count","type":"number","sample":2},{"key":"receivedAt","type":"date","sample":"2026-10-01T14:14:00Z"},
               {"key":"url","type":"url"}],
     "actions":[{"id":"markRead","label":"Mark as Read","kind":"callback"},
                {"id":"archive","label":"Archive","kind":"callback","style":"destructive"}]}
    """

    /// The schema's own e-mail example: three actionRules, six cells.
    static var template: String { ComponentSchema.emailExample }

    static func json(_ s: String) -> JSONValue { try! JSONDecoder().decode(JSONValue.self, from: Data(s.utf8)) }

    /// A well-formed v2 template with the given cells JSON.
    static func template(name: String = "draft", cells: String, extra: String = "") -> String {
        """
        {"name":"\(name)","app":"webwatcher.email","layoutVersion":2,
         "grid":{"rows":2,"cols":2,"rowSizes":["auto","auto"],"colSizes":["fill","auto"],"gap":6,"padding":12,"width":380},
         "cells":[\(cells)]\(extra)}
        """
    }

    static func historyItem(id: String, title: String, fields: [String: HeraldFieldValue]) -> JSONValue {
        let n = HeraldNotification(app: "webwatcher.email", id: id, title: title)
        let item = HeraldHistoryItem(id: id, app: n.app, notification: n, deliveredAt: Date(timeIntervalSince1970: 1_790_000_000), fields: fields)
        return try! JSONValue(encoding: item)
    }
}

// MARK: - Tests

final class MCPProtocolTests: XCTestCase {
    var fake: FakeHerald!
    var server: MCPServer!
    var previews: URL!

    override func setUpWithError() throws {
        fake = try FakeHerald()
        try fake.start()
        fake.manifests["webwatcher.email"] = MCPFixtures.json(MCPFixtures.manifest)
        fake.templates["webwatcher.email"] = ["email-accumulated": MCPFixtures.json(MCPFixtures.template)]
        previews = fake.directory.appendingPathComponent("previews")
        server = MCPServer(client: fake.client, previewDirectory: previews)
    }

    override func tearDown() { fake.stop() }

    // MARK: Helpers

    @discardableResult
    func rpc(_ method: String, _ params: JSONValue? = nil, id: Int = 1, using s: MCPServer? = nil) async throws -> JSONValue {
        var m: [String: JSONValue] = ["jsonrpc": .string("2.0"), "id": .number(Double(id)), "method": .string(method)]
        if let params { m["params"] = params }
        let reply = await (s ?? server).process(line: RPC.encode(.object(m)))
        let line = try XCTUnwrap(reply, "no reply to \(method)")
        return MCPFixtures.json(line)
    }

    /// Calls a tool; returns the CallToolResult object.
    func call(_ name: String, _ args: JSONValue = .object([:]), using s: MCPServer? = nil) async throws -> JSONValue {
        let reply = try await rpc("tools/call", .object(["name": .string(name), "arguments": args]), using: s)
        return try XCTUnwrap(reply["result"], "tools/call \(name) returned \(reply)")
    }

    func text(_ result: JSONValue) throws -> String {
        try XCTUnwrap(result["content"]?.arrayValue?.first { $0["type"]?.stringValue == "text" }?["text"]?.stringValue)
    }

    func payload(_ result: JSONValue) throws -> JSONValue { MCPFixtures.json(try text(result)) }

    func isError(_ result: JSONValue) -> Bool { result["isError"]?.boolValue == true }

    func assertFails(_ name: String, _ args: JSONValue = .object([:]), _ message: String = "", file: StaticString = #filePath, line: UInt = #line) async throws {
        let r = try await call(name, args)
        XCTAssertTrue(isError(r), message.isEmpty ? "\(name) should fail" : message, file: file, line: line)
    }

    func assertSucceeds(_ name: String, _ args: JSONValue = .object([:]), _ message: String = "", file: StaticString = #filePath, line: UInt = #line) async throws {
        let r = try await call(name, args)
        XCTAssertFalse(isError(r), message.isEmpty ? ((try? text(r)) ?? name) : message, file: file, line: line)
    }

    func assertRPCError(_ method: String, _ params: JSONValue, _ code: Int, file: StaticString = #filePath, line: UInt = #line) async throws {
        let reply = try await rpc(method, params)
        XCTAssertEqual(reply["error"]?["code"]?.numberValue, Double(code), method, file: file, line: line)
    }

    func assertRPCError(_ method: String, _ code: Int, file: StaticString = #filePath, line: UInt = #line) async throws {
        let reply = try await rpc(method)
        XCTAssertEqual(reply["error"]?["code"]?.numberValue, Double(code), method, file: file, line: line)
    }

    func strings(_ v: JSONValue?) -> [String] { (v?.arrayValue ?? []).compactMap(\.stringValue) }

    // MARK: Frames

    func testFrameParsing() {
        XCTAssertEqual(RPC.parse(line: #"{"jsonrpc":"2.0","id":1,"method":"ping"}"#),
                       .single(.request(id: .number(1), method: "ping", params: nil)))
        XCTAssertEqual(RPC.parse(line: #"{"jsonrpc":"2.0","id":"abc","method":"tools/list","params":{}}"#),
                       .single(.request(id: .string("abc"), method: "tools/list", params: .object([:]))))
        XCTAssertEqual(RPC.parse(line: #"{"jsonrpc":"2.0","method":"notifications/initialized"}"#),
                       .single(.notification(method: "notifications/initialized", params: nil)))
        XCTAssertEqual(RPC.parse(line: #"{"jsonrpc":"2.0","id":3,"result":{}}"#), .single(.response))

        // A batch yields one message per element.
        guard case .batch(let batch) = RPC.parse(line: #"[{"jsonrpc":"2.0","id":1,"method":"ping"},{"jsonrpc":"2.0","method":"x"}]"#) else {
            return XCTFail("expected a batch")
        }
        XCTAssertEqual(batch.count, 2)

        func invalid(_ line: String, code: Int, id: JSONValue, file: StaticString = #filePath, line l: UInt = #line) {
            guard case .single(.invalid(let gotID, let error)) = RPC.parse(line: line) else {
                return XCTFail("expected an invalid message for \(line)", file: file, line: l)
            }
            XCTAssertEqual(error.code, code, line, file: file, line: l)
            XCTAssertEqual(gotID, id, file: file, line: l)
        }
        invalid("not json", code: -32700, id: .null)
        invalid("", code: -32700, id: .null)
        invalid("[]", code: -32600, id: .null)
        invalid("42", code: -32600, id: .null)
        invalid(#"{"id":7,"method":"ping"}"#, code: -32600, id: .number(7))                         // no jsonrpc
        invalid(#"{"jsonrpc":"1.0","id":7,"method":"ping"}"#, code: -32600, id: .number(7))
        invalid(#"{"jsonrpc":"2.0","id":null,"method":"ping"}"#, code: -32600, id: .null)           // MCP: id is never null
        invalid(#"{"jsonrpc":"2.0","id":true,"method":"ping"}"#, code: -32600, id: .null)
        invalid(#"{"jsonrpc":"2.0","id":9}"#, code: -32600, id: .number(9))                        // neither method nor result
        invalid(#"{"jsonrpc":"2.0","id":9,"method":"ping","params":"x"}"#, code: -32600, id: .number(9))
        invalid(#"{"jsonrpc":"2.0","id":9,"method":5}"#, code: -32600, id: .number(9))
    }

    func testEncodedFramesAreOneLine() throws {
        let reply = RPC.result(id: .number(1), .object(["text": .string("line one\nline two\r\n\"quoted\" https://x.example/a")]))
        let line = RPC.encode(reply)
        XCTAssertFalse(line.contains("\n"))
        XCTAssertFalse(line.contains("\r"))
        XCTAssertTrue(line.contains("https://x.example/a"), "slashes are not escaped")
        XCTAssertTrue(line.contains(#""id":1"#), "an integer id stays an integer: \(line)")
        XCTAssertEqual(MCPFixtures.json(line)["result"]?["text"]?.stringValue, "line one\nline two\r\n\"quoted\" https://x.example/a")

        let failure = RPC.encode(RPC.failure(id: .string("a"), .methodNotFound("x/y")))
        XCTAssertEqual(MCPFixtures.json(failure)["error"]?["code"]?.numberValue, -32601)
    }

    func testProcessLineBatchAndGarbage() async throws {
        // A notification alone produces no output.
        let silent = await server.process(line: #"{"jsonrpc":"2.0","method":"notifications/initialized"}"#)
        XCTAssertNil(silent)
        // Garbage gets a parse error with a null id; the server keeps going.
        let garbageReply = await server.process(line: "{{{")
        let garbage = try XCTUnwrap(garbageReply)
        XCTAssertEqual(MCPFixtures.json(garbage)["error"]?["code"]?.numberValue, -32700)
        XCTAssertEqual(MCPFixtures.json(garbage)["id"], .null)
        // A batch is answered with an array, omitting the notification's slot.
        let batchReply = await server.process(
            line: #"[{"jsonrpc":"2.0","id":1,"method":"ping"},{"jsonrpc":"2.0","method":"notifications/initialized"},{"jsonrpc":"2.0","id":2,"method":"nope"}]"#)
        let batch = try XCTUnwrap(batchReply)
        let replies = try XCTUnwrap(MCPFixtures.json(batch).arrayValue)
        XCTAssertEqual(replies.count, 2)
        XCTAssertEqual(replies[0]["id"]?.numberValue, 1)
        XCTAssertEqual(replies[1]["error"]?["code"]?.numberValue, -32601)
    }

    // MARK: Handshake

    func testInitializeHandshake() async throws {
        let reply = try await rpc("initialize", .object([
            "protocolVersion": .string("2025-06-18"), "capabilities": .object([:]),
            "clientInfo": .object(["name": .string("test"), "version": .string("1")]),
        ]))
        XCTAssertEqual(reply["jsonrpc"]?.stringValue, "2.0")
        XCTAssertEqual(reply["id"]?.numberValue, 1)
        let result = try XCTUnwrap(reply["result"])
        XCTAssertEqual(result["protocolVersion"]?.stringValue, "2025-06-18")
        XCTAssertNotNil(result["capabilities"]?["tools"])
        XCTAssertNotNil(result["capabilities"]?["resources"])
        XCTAssertNil(result["capabilities"]?["prompts"], "prompts are not offered")
        XCTAssertEqual(result["serverInfo"]?["name"]?.stringValue, "herald-mcp")
        XCTAssertEqual(result["serverInfo"]?["version"]?.stringValue, MCPServer.serverVersion)
        XCTAssertFalse((result["instructions"]?.stringValue ?? "").isEmpty)
        XCTAssertEqual(server.negotiatedProtocolVersion, "2025-06-18")
        XCTAssertEqual(server.clientInfo?["name"]?.stringValue, "test")

        XCTAssertFalse(server.initializedByClient)
        let ack = await server.process(line: #"{"jsonrpc":"2.0","method":"notifications/initialized"}"#)
        XCTAssertNil(ack, "a notification gets no reply")
        XCTAssertTrue(server.initializedByClient)

        let ping = try await rpc("ping", id: 2)
        XCTAssertEqual(ping["result"], .object([:]))
        XCTAssertEqual(ping["id"]?.numberValue, 2)
    }

    func testProtocolVersionNegotiation() async throws {
        let old = try await rpc("initialize", .object(["protocolVersion": .string("2024-11-05")]))
        XCTAssertEqual(old["result"]?["protocolVersion"]?.stringValue, "2024-11-05", "a revision we speak is echoed")
        let future = try await rpc("initialize", .object(["protocolVersion": .string("2031-01-01")]))
        XCTAssertEqual(future["result"]?["protocolVersion"]?.stringValue, "2025-06-18", "an unknown one gets our latest")
        let missing = try await rpc("initialize", .object([:]))
        XCTAssertEqual(missing["error"]?["code"]?.numberValue, -32602)
    }

    func testUnknownMethodsAndBadCalls() async throws {
        try await assertRPCError("no/such/method", -32601)
        try await assertRPCError("prompts/list", -32601)
        try await assertRPCError("tools/call", .object(["name": .string("nope"), "arguments": .object([:])]), -32602)
        try await assertRPCError("tools/call", .object([:]), -32602)
        try await assertRPCError("tools/call", .object(["name": .string("herald_status"), "arguments": .string("x")]), -32602)
        try await assertRPCError("resources/read", .object([:]), -32602)
    }

    // MARK: tools/list

    static let expectedTools = [
        "herald_status", "list_manifests", "get_manifest", "put_manifest", "list_templates", "get_template", "put_template",
        "delete_template", "validate_template", "component_schema", "render_preview", "send_notification", "send_test",
        "list_shortcuts", "add_action_rule", "list_history", "dismiss", "speak", "get_quiet_hours", "set_quiet_hours",
    ]

    func testToolsListHasEveryDesignedTool() async throws {
        let listReply = try await rpc("tools/list")
        let tools = try XCTUnwrap(listReply["result"]?["tools"]?.arrayValue)
        XCTAssertEqual(tools.compactMap { $0["name"]?.stringValue }, Self.expectedTools)
        XCTAssertEqual(Set(Self.expectedTools).count, tools.count)

        for t in tools {
            let name = t["name"]?.stringValue ?? "?"
            XCTAssertGreaterThan((t["description"]?.stringValue ?? "").count, 40, "\(name) needs a real description")
            XCTAssertFalse((t["title"]?.stringValue ?? "").isEmpty, name)
            let schema = try XCTUnwrap(t["inputSchema"], name)
            XCTAssertEqual(schema["type"]?.stringValue, "object", name)
            let properties = Set(schema["properties"]?.objectValue?.keys.map { $0 } ?? [])
            for required in strings(schema["required"]) { XCTAssertTrue(properties.contains(required), "\(name): required '\(required)' is not a property") }
            for (key, p) in schema["properties"]?.objectValue ?? [:] {
                XCTAssertFalse((p["description"]?.stringValue ?? "").isEmpty, "\(name).\(key) needs a description")
            }
            XCTAssertNotNil(t["annotations"]?["readOnlyHint"]?.boolValue, name)
        }

        func tool(_ n: String) -> JSONValue { tools.first { $0["name"]?.stringValue == n }! }
        for n in ["herald_status", "list_manifests", "get_manifest", "list_templates", "get_template", "validate_template",
                  "component_schema", "render_preview", "list_shortcuts", "list_history"] {
            XCTAssertEqual(tool(n)["annotations"]?["readOnlyHint"]?.boolValue, true, "\(n) is read-only")
        }
        for n in ["put_manifest", "put_template", "delete_template", "send_notification", "send_test", "add_action_rule", "dismiss"] {
            XCTAssertEqual(tool(n)["annotations"]?["readOnlyHint"]?.boolValue, false, "\(n) changes things")
        }
        XCTAssertEqual(strings(tool("get_template")["inputSchema"]?["required"]), ["app", "name"])
        XCTAssertEqual(strings(tool("add_action_rule")["inputSchema"]?["required"]), ["app", "template", "rule"])
        XCTAssertEqual(tool("send_notification")["inputSchema"]?["additionalProperties"]?.boolValue, true,
                       "a notification carries the app's own fields as top-level keys")
        XCTAssertEqual(tool("get_template")["inputSchema"]?["additionalProperties"]?.boolValue, false)
        XCTAssertEqual(strings(tool("component_schema")["inputSchema"]?["properties"]?["component"]?["enum"]), HeraldComponent.typeNames)
    }

    // MARK: Status and read tools

    func testStatusReportsRunningHerald() async throws {
        let r = try payload(try await call("herald_status"))
        XCTAssertEqual(r["running"]?.boolValue, true)
        XCTAssertEqual(r["version"]?.stringValue, "1.1.0")
        XCTAssertEqual(r["pid"]?.numberValue, 4242)
        XCTAssertEqual(r["port"]?.numberValue, Double(fake.client.port))
        XCTAssertEqual(r["manifests"]?.numberValue, 1)
        XCTAssertEqual(r["templates"]?.numberValue, 1)
        XCTAssertEqual(r["shortcuts"]?.numberValue, 2)
        XCTAssertEqual(strings(r["apps"]), ["webwatcher.email"])
    }

    func testNotRunningIsAReadableToolError() async throws {
        let empty = FileManager.default.temporaryDirectory.appendingPathComponent("herald-mcp-none-\(UUID().uuidString)")
        // Port 1: nothing listens there, whatever else runs on this machine (a real Herald owns the default port).
        let offline = MCPServer(client: HeraldClient(supportDirectory: empty, port: 1), previewDirectory: previews)

        let status = try await call("herald_status", using: offline)
        XCTAssertFalse(isError(status), "status reports; it does not fail")
        let s = try payload(status)
        XCTAssertEqual(s["running"]?.boolValue, false)
        XCTAssertTrue((s["hint"]?.stringValue ?? "").contains("not running"))

        let get = try await call("get_manifest", .object(["app": .string("x")]), using: offline)
        XCTAssertTrue(isError(get))
        XCTAssertTrue(try text(get).contains("Herald is not running"))

        // The doc resource and component_schema still work offline.
        let schema = try await call("component_schema", using: offline)
        XCTAssertFalse(isError(schema))
        XCTAssertTrue(try text(schema).contains("\"components\""))
    }

    func testManifestAndTemplateReadTools() async throws {
        let list = try payload(try await call("list_manifests"))
        XCTAssertEqual(list["count"]?.numberValue, 1)
        let m0 = try XCTUnwrap(list["manifests"]?.arrayValue?.first)
        XCTAssertEqual(m0["app"]?.stringValue, "webwatcher.email")
        XCTAssertTrue(strings(m0["fields"]).contains("title:text!"), "required fields carry a !")
        XCTAssertTrue(strings(m0["fields"]).contains("count:number"))
        XCTAssertEqual(strings(m0["actions"]), ["markRead", "archive"])

        let get = try payload(try await call("get_manifest", .object(["app": .string("webwatcher.email")])))
        XCTAssertEqual(get["fields"]?.arrayValue?.count, 6)
        XCTAssertEqual(get["fields"]?.arrayValue?.first?["sample"]?.stringValue, "2 new from Acme Billing")

        let missing = try await call("get_manifest", .object(["app": .string("nobody")]))
        XCTAssertTrue(isError(missing))
        XCTAssertEqual(strings(try payload(missing)["registered"]), ["webwatcher.email"])

        let templates = try payload(try await call("list_templates"))
        let t0 = try XCTUnwrap(templates["templates"]?.arrayValue?.first)
        XCTAssertEqual(t0["name"]?.stringValue, "email-accumulated")
        XCTAssertEqual(t0["layoutVersion"]?.numberValue, 2)
        XCTAssertEqual(t0["cells"]?.numberValue, 6)
        XCTAssertEqual(t0["actionRules"]?.numberValue, 3)
        XCTAssertTrue(strings(t0["tokens"]).contains("sender"))
        XCTAssertEqual(strings(templates["builtins"]), ["builtin.imageLeft", "builtin.imageRight", "builtin.hero", "builtin.compact"])

        let get1 = try payload(try await call("get_template", .object(["app": .string("webwatcher.email"), "name": .string("email-accumulated")])))
        XCTAssertEqual(get1["cells"]?.arrayValue?.count, 6)

        // A built-in comes from code: no request for it is needed.
        let hero = try payload(try await call("get_template", .object(["app": .string("webwatcher.email"), "name": .string("builtin.hero")])))
        XCTAssertEqual(hero["layoutVersion"]?.numberValue, 2)
        XCTAssertEqual(hero["app"]?.stringValue, "webwatcher.email")

        let nope = try await call("get_template", .object(["app": .string("webwatcher.email"), "name": .string("nope")]))
        XCTAssertTrue(isError(nope))
        XCTAssertEqual(strings(try payload(nope)["saved"]), ["email-accumulated"])

        let shortcuts = try payload(try await call("list_shortcuts"))
        XCTAssertEqual(strings(shortcuts["shortcuts"]), ["Create follow-up", "Log to Notes"])
    }

    func testEveryRequestCarriesTheBearerToken() async throws {
        _ = try await call("get_manifest", .object(["app": .string("webwatcher.email")]))
        _ = try await call("list_shortcuts")
        let authed = fake.calls.filter { $0.path != "/v1/health" }
        XCTAssertFalse(authed.isEmpty)
        for c in authed { XCTAssertEqual(c.authorization, "Bearer test-token", c.path) }
    }

    func testWrongTokenIsExplained() async throws {
        let bad = MCPServer(client: HeraldClient(supportDirectory: fake.directory, token: "wrong"), previewDirectory: previews)
        let r = try await call("list_shortcuts", using: bad)
        XCTAssertTrue(isError(r))
        XCTAssertTrue(try text(r).contains("rejected the token"))
    }

    func testListHistorySummarisesAndAbbreviates() async throws {
        fake.history = [MCPFixtures.historyItem(id: "n1", title: "Two new", fields: ["count": .number(2), "sender": .text("Acme")])]
        let r = try payload(try await call("list_history", .object(["app": .string("webwatcher.email"), "limit": .number(5)])))
        let item = try XCTUnwrap(r["items"]?.arrayValue?.first)
        XCTAssertEqual(item["title"]?.stringValue, "Two new")
        XCTAssertEqual(item["fields"]?["count"]?.numberValue, 2)
        XCTAssertNotNil(item["deliveredAt"]?.stringValue)
        let q = try XCTUnwrap(fake.calls("GET", "/v1/history").last)
        XCTAssertEqual(q.query["app"], "webwatcher.email")
        XCTAssertEqual(q.query["limit"], "5")

        let full = try payload(try await call("list_history", .object(["full": .bool(true)])))
        XCTAssertNotNil(full["items"]?.arrayValue?.first?["notification"])
    }

    // MARK: component_schema

    func testComponentSchemaPrefersHeralds() async throws {
        fake.components = .object(["title": .string("from-herald"), "components": .object(["text": .object(["marker": .string("T")])]), "definitions": .object([:])])
        let all = try await call("component_schema")
        XCTAssertTrue(try text(all).contains("from-herald"))
        let one = try payload(try await call("component_schema", .object(["component": .string("text")])))
        XCTAssertEqual(one["schema"]?["marker"]?.stringValue, "T")
        XCTAssertEqual(one["source"]?.stringValue, "herald")
        XCTAssertEqual(fake.calls("GET", "/v1/components").count, 2)
    }

    func testComponentSchemaFallsBackToTheBuiltInDocument() async throws {
        fake.components = nil      // an older Herald answers 404
        let all = try await call("component_schema")
        XCTAssertFalse(isError(all))
        let doc = MCPFixtures.json(try text(all))
        XCTAssertEqual(doc["schemaVersion"]?.numberValue, Double(ComponentSchema.schemaVersion))
        for type in HeraldComponent.typeNames { XCTAssertNotNil(doc["components"]?[type], "component \(type)") }
        XCTAssertTrue(all["content"]?.arrayValue?.contains { $0["text"]?.stringValue?.hasPrefix("Source: herald-mcp") == true } == true)

        let one = try payload(try await call("component_schema", .object(["component": .string("rive")])))
        XCTAssertNotNil(one["schema"]?["properties"])
        XCTAssertNotNil(one["definitions"]?["emptyBehavior"], "the definitions the component refers to travel with it")
        XCTAssertNil(one["definitions"]?["grid"], "and only those")
        let section = try payload(try await call("component_schema", .object(["section": .string("actions")])))
        XCTAssertNotNil(section["value"]?["kinds"])

        let bad = try await call("component_schema", .object(["component": .string("hologram")]))
        XCTAssertTrue(isError(bad))
        XCTAssertEqual(strings(try payload(bad)["types"]), HeraldComponent.typeNames)
    }

    // MARK: put_template

    func testPutTemplateValidatesAndNamesTheCell() async throws {
        // 'b' overlaps 'a'; 'c' hangs outside the 2 x 2 grid; the colour is not a colour.
        let draft = MCPFixtures.template(name: "broken", cells: """
        {"id":"a","row":0,"col":0,"colSpan":2,"component":{"type":"text","binding":"{title}"}},
        {"id":"b","row":0,"col":1,"component":{"type":"text","binding":"{subject}"}},
        {"id":"c","row":1,"col":2,"component":{"type":"badge","binding":"{count}","color":"red-ish"}}
        """)
        let before = fake.calls("PUT", "/v1/templates").count
        let r = try await call("put_template", .object(["template": MCPFixtures.json(draft)]))
        XCTAssertTrue(isError(r))
        let report = try payload(r)
        XCTAssertEqual(report["saved"]?.boolValue, false)
        let errors = try XCTUnwrap(report["errors"]?.arrayValue)
        let cells = Set(errors.compactMap { $0["cellId"]?.stringValue })
        XCTAssertTrue(cells.contains("b"), "the overlap is reported on a cell: \(cells)")
        XCTAssertTrue(cells.contains("c"), "the cell outside the grid is named: \(cells)")
        for e in errors { XCTAssertFalse((e["path"]?.stringValue ?? "").isEmpty); XCTAssertFalse((e["message"]?.stringValue ?? "").isEmpty) }
        XCTAssertEqual(fake.calls("PUT", "/v1/templates").count, before, "an invalid template is never sent to Herald")
        XCTAssertNil(fake.templates["webwatcher.email"]?["broken"])
    }

    func testPutTemplateReportsDecodeErrorsWithThePathAndCell() async throws {
        let draft = MCPFixtures.template(name: "typed", cells: """
        {"id":"a","row":0,"col":0,"component":{"type":"text","binding":"{title}"}},
        {"id":"time","row":1,"col":0,"component":{"type":"hologram"}}
        """)
        let r = try await call("put_template", .object(["template": MCPFixtures.json(draft)]))
        XCTAssertTrue(isError(r))
        let report = try payload(r)
        XCTAssertEqual(report["cellId"]?.stringValue, "time")
        XCTAssertTrue((report["path"]?.stringValue ?? "").hasPrefix("cells[1]"), "\(report)")
        XCTAssertNil(fake.templates["webwatcher.email"]?["typed"])

        // The wrong type for a known property.
        let wrong = MCPFixtures.template(name: "typed", cells: """
        {"id":"a","row":"zero","col":0,"component":{"type":"text","binding":"{title}"}}
        """)
        let r2 = try await call("put_template", .object(["template": MCPFixtures.json(wrong)]))
        XCTAssertTrue(isError(r2))
        XCTAssertEqual(try payload(r2)["cellId"]?.stringValue, "a")

        let noName = try await call("put_template", .object(["template": .object(["app": .string("x")])]))
        XCTAssertTrue(isError(noName))
        XCTAssertEqual(try payload(noName)["path"]?.stringValue, "name")
    }

    func testPutTemplateSavesAValidOneAndWarnsAboutTypos() async throws {
        let draft = MCPFixtures.template(name: "inbox", cells: """
        {"id":"title","row":0,"col":0,"colspan":2,"component":{"type":"text","binding":"{title}","style":"title"}},
        {"id":"sub","row":1,"col":0,"colSpan":2,"component":{"type":"text","binding":"{subtitel} {sender}"}}
        """)
        let r = try await call("put_template", .object(["template": MCPFixtures.json(draft)]))
        XCTAssertFalse(isError(r), (try? text(r)) ?? "")
        let report = try payload(r)
        XCTAssertEqual(report["saved"]?.boolValue, true)
        XCTAssertEqual(report["cells"]?.numberValue, 2)
        let warnings = try XCTUnwrap(report["warnings"]?.arrayValue).compactMap { $0["message"]?.stringValue }
        XCTAssertTrue(warnings.contains { $0.contains("colspan") && $0.contains("colSpan") }, "a mistyped key gets a hint: \(warnings)")
        XCTAssertTrue(warnings.contains { $0.contains("subtitel") }, "a token the manifest does not declare is flagged: \(warnings)")

        let put = try XCTUnwrap(fake.calls("PUT", "/v1/templates").last)
        let saved = try HeraldJSON.decoder().decode(HeraldTemplate.self, from: put.body)
        XCTAssertEqual(saved.name, "inbox")
        XCTAssertEqual(saved.app, "webwatcher.email")
        XCTAssertEqual(saved.cells.count, 2)
        XCTAssertEqual(saved.layoutVersion, 2)
    }

    func testPutTemplateAcceptsTheSchemaExampleAndTakesAppFromTheArgument() async throws {
        var raw = try XCTUnwrap(MCPFixtures.json(MCPFixtures.template).objectValue)
        raw["name"] = .string("copy"); raw["app"] = nil
        let r = try await call("put_template", .object(["template": .object(raw), "app": .string("webwatcher.email"), "setAsDefault": .bool(true)]))
        XCTAssertFalse(isError(r), (try? text(r)) ?? "")
        let report = try payload(r)
        XCTAssertEqual(strings(report["warnings"]).count, 0, "\(report)")
        XCTAssertEqual(report["isDefault"]?.boolValue, true)
        XCTAssertEqual(fake.templates["webwatcher.email"]?["copy"]?["app"]?.stringValue, "webwatcher.email")
        XCTAssertEqual(fake.manifests["webwatcher.email"]?["defaultTemplate"]?.stringValue, "copy")
    }

    func testArgumentsAreForgiving() async throws {
        // A nested object passed as a JSON string, a number and a boolean passed as strings.
        let draft = MCPFixtures.template(name: "stringy", cells: """
        {"id":"a","row":0,"col":0,"component":{"type":"text","binding":"{title}"}}
        """)
        try await assertSucceeds("put_template", .object(["template": .string(draft), "setAsDefault": .string("true")]))
        XCTAssertEqual(fake.manifests["webwatcher.email"]?["defaultTemplate"]?.stringValue, "stringy")
        fake.history = [MCPFixtures.historyItem(id: "n1", title: "t", fields: ["title": .text("t")])]
        _ = try await call("list_history", .object(["limit": .string("3")]))
        XCTAssertEqual(fake.calls("GET", "/v1/history").last?.query["limit"], "3")
        try await assertFails("list_history", .object(["limit": .string("many")]))
        try await assertFails("list_history", .object(["limit": .number(2.5)]))
        try await assertFails("put_template", .object(["template": .string("not an object")]))

        // The app argument must agree with the template.
        var raw = try XCTUnwrap(MCPFixtures.json(draft).objectValue)
        raw["app"] = .string("other.app")
        try await assertFails("put_template", .object(["template": .object(raw), "app": .string("webwatcher.email")]), "app mismatch")
    }

    func testTheSchemasOwnExamplesRaiseNoUnknownKeyWarnings() throws {
        let doc = ComponentSchema.document()
        let examples = try XCTUnwrap(doc["examples"]?.arrayValue)
        XCTAssertFalse(examples.isEmpty)
        for example in examples {
            let template = try XCTUnwrap(example["template"]?.objectValue)
            XCTAssertEqual(TemplateKeyCheck.warnings(in: template).map(\.message), [], example["name"]?.stringValue ?? "example")
        }
        // Each component's own example, placed in a cell.
        for type in HeraldComponent.typeNames {
            let component = try XCTUnwrap(doc["components"]?[type]?["example"], type)
            let template = try XCTUnwrap(MCPFixtures.json(MCPFixtures.template(cells: """
            {"id":"c","row":0,"col":0,"component":\(component.text(pretty: false))}
            """)).objectValue)
            XCTAssertEqual(TemplateKeyCheck.warnings(in: template).map(\.message), [], "component example: \(type)")
        }
    }

    func testUnknownKeysGetAHint() {
        let raw = MCPFixtures.json(MCPFixtures.template(name: "t", cells: """
        {"id":"a","row":0,"col":0,"rowspan":2,"component":{"type":"text","binding":"{title}","maxline":2}}
        """, extra: #","collapseempty":false,"actionRules":[{"match":"x","hid":true}]"#)).objectValue!
        let messages = TemplateKeyCheck.warnings(in: raw).map(\.message)
        XCTAssertTrue(messages.contains { $0.contains("'rowspan'") && $0.contains("'rowSpan'") }, "\(messages)")
        XCTAssertTrue(messages.contains { $0.contains("'maxline'") && $0.contains("'maxLines'") }, "\(messages)")
        XCTAssertTrue(messages.contains { $0.contains("'collapseempty'") && $0.contains("'collapseEmpty'") }, "\(messages)")
        XCTAssertTrue(messages.contains { $0.contains("'hid'") && $0.contains("'hide'") }, "\(messages)")
        XCTAssertEqual(TemplateKeyCheck.editDistance("kitten", "sitting"), 3)
        XCTAssertNil(TemplateKeyCheck.closest(to: "zzzzzz", in: ["row", "col"]))
    }

    func testPutTemplateRefusesReservedNames() async throws {
        var raw = try XCTUnwrap(MCPFixtures.json(MCPFixtures.template).objectValue)
        raw["name"] = .string("builtin.mine")
        let r = try await call("put_template", .object(["template": .object(raw)]))
        XCTAssertTrue(isError(r))
        XCTAssertTrue(try text(r).contains("reserved"))
        XCTAssertTrue(fake.calls("PUT", "/v1/templates").isEmpty)
    }

    func testDeleteTemplate() async throws {
        let ok = try await call("delete_template", .object(["app": .string("webwatcher.email"), "name": .string("email-accumulated")]))
        XCTAssertFalse(isError(ok), (try? text(ok)) ?? "")
        XCTAssertNil(fake.templates["webwatcher.email"]?["email-accumulated"])
        let again = try await call("delete_template", .object(["app": .string("webwatcher.email"), "name": .string("email-accumulated")]))
        XCTAssertTrue(isError(again))
        let builtin = try await call("delete_template", .object(["app": .string("webwatcher.email"), "name": .string("builtin.hero")]))
        XCTAssertTrue(isError(builtin))
        XCTAssertEqual(fake.calls("DELETE", "/v1/templates").count, 2, "the built-in was refused locally")
    }

    // MARK: put_manifest

    func testPutManifestValidatesAndSaves() async throws {
        let ok = try await call("put_manifest", .object(["manifest": MCPFixtures.json("""
        {"app":"bidbot","appName":"BidBot","fields":[{"key":"title","type":"text","sample":"Bid won"},{"key":"amount","type":"number","sample":4200}],
         "actions":[{"id":"open","label":"Open","kind":"url","url":"https://example.com"}]}
        """)]))
        XCTAssertFalse(isError(ok), (try? text(ok)) ?? "")
        XCTAssertEqual(try payload(ok)["fields"]?.numberValue, 2)
        XCTAssertEqual(fake.manifests["bidbot"]?["appName"]?.stringValue, "BidBot")

        // A shortcut action belongs in a template, not a manifest: the error says where.
        let bad = try await call("put_manifest", .object(["manifest": MCPFixtures.json("""
        {"app":"bidbot","actions":[{"label":"Follow up","kind":"shortcut"}]}
        """)]))
        XCTAssertTrue(isError(bad))
        let report = try payload(bad)
        XCTAssertTrue((report["path"]?.stringValue ?? "").hasPrefix("actions[0]"), "\(report)")
        XCTAssertTrue((report["error"]?.stringValue ?? "").contains("authored in templates"))

        let noApp = try await call("put_manifest", .object(["manifest": MCPFixtures.json(#"{"appName":"x"}"#)]))
        XCTAssertTrue(isError(noApp))
        XCTAssertEqual(fake.calls("PUT", "/v1/manifest").count, 1)
    }

    // MARK: validate_template

    func testValidateTemplateReportsTheEffectWithSampleData() async throws {
        let r = try payload(try await call("validate_template", .object(["template": MCPFixtures.json(MCPFixtures.template)])))
        XCTAssertEqual(r["valid"]?.boolValue, true, "\(r)")
        XCTAssertEqual(r["manifestChecked"]?.boolValue, true)
        XCTAssertEqual(strings(r["errors"]).count, 0)
        let actions = try XCTUnwrap(r["withSampleData"]?["actions"]?.arrayValue)
        XCTAssertEqual(actions.compactMap { $0["id"]?.stringValue }, ["markRead", "shortcut-followup"],
                       "archive is hidden, markRead moved to the front, the shortcut added")
        XCTAssertEqual(actions.first?["label"]?.stringValue, "Mark as read")
        XCTAssertEqual(actions.last?["origin"]?.stringValue, "template")

        // A saved template by name.
        let byName = try payload(try await call("validate_template", .object(["app": .string("webwatcher.email"), "name": .string("email-accumulated")])))
        XCTAssertEqual(byName["valid"]?.boolValue, true)
        try await assertSucceeds("validate_template", .object(["app": .string("webwatcher.email"), "name": .string("builtin.compact")]))

        // Invalid is a result, not a failure.
        let broken = MCPFixtures.template(cells: """
        {"id":"a","row":0,"col":0,"component":{"type":"text","binding":"{title}"}},
        {"id":"a","row":1,"col":0,"component":{"type":"text","binding":"{title}"}}
        """)
        let res = try await call("validate_template", .object(["template": MCPFixtures.json(broken)]))
        XCTAssertFalse(isError(res))
        let rep = try payload(res)
        XCTAssertEqual(rep["valid"]?.boolValue, false)
        XCTAssertTrue(try XCTUnwrap(rep["errors"]?.arrayValue).contains { $0["cellId"]?.stringValue == "a" })

        let neither = try await call("validate_template")
        XCTAssertTrue(isError(neither))
    }

    func testValidateTemplateWorksWithoutHerald() async throws {
        let offline = MCPServer(client: HeraldClient(supportDirectory: fake.directory.appendingPathComponent("none")), previewDirectory: previews)
        let r = try payload(try await call("validate_template", .object(["template": MCPFixtures.json(MCPFixtures.template)]), using: offline))
        XCTAssertEqual(r["valid"]?.boolValue, true)
        XCTAssertEqual(r["manifestChecked"]?.boolValue, false)
        XCTAssertNotNil(r["note"])
    }

    func testCollapseAnalysisUsesTheManifestSamples() async throws {
        // The manifest declares no {body}, so the sample data has none: the cell that binds only it is empty and
        // collapses, and with it the row it alone occupies.
        let draft = MCPFixtures.template(cells: """
        {"id":"title","row":0,"col":0,"component":{"type":"text","binding":"{title}"}},
        {"id":"link","row":1,"col":0,"colSpan":2,"component":{"type":"text","binding":"{body}"}}
        """)
        let r = try payload(try await call("validate_template", .object(["template": MCPFixtures.json(draft)])))
        XCTAssertEqual(strings(r["withSampleData"]?["emptyCells"]), ["link"])
        XCTAssertEqual(r["withSampleData"]?["collapsedRows"]?.arrayValue?.first?.numberValue, 1)
    }

    // MARK: render_preview

    func testRenderPreviewReturnsAnImageAndAPath() async throws {
        let result = try await call("render_preview", .object([
            "app": .string("webwatcher.email"), "name": .string("email-accumulated"), "appearance": .string("dark"), "scale": .number(2),
        ]))
        XCTAssertFalse(isError(result), (try? text(result)) ?? "")
        let blocks = try XCTUnwrap(result["content"]?.arrayValue)
        let image = try XCTUnwrap(blocks.first { $0["type"]?.stringValue == "image" })
        XCTAssertEqual(image["mimeType"]?.stringValue, "image/png")
        XCTAssertEqual(Data(base64Encoded: image["data"]?.stringValue ?? ""), fake.previewPNG)

        let info = try payload(result)
        XCTAssertEqual(info["width"]?.numberValue, 760)
        XCTAssertEqual(info["height"]?.numberValue, 400)
        XCTAssertEqual(info["appearance"]?.stringValue, "dark")
        let path = try XCTUnwrap(info["path"]?.stringValue)
        XCTAssertTrue(path.hasPrefix(previews.path))
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: path)), fake.previewPNG, "the saved file is the picture")

        let sent = try XCTUnwrap(fake.calls("POST", "/v1/preview").last?.json)
        XCTAssertEqual(sent["template"]?.stringValue, "email-accumulated")
        XCTAssertEqual(sent["app"]?.stringValue, "webwatcher.email")
        XCTAssertEqual(sent["data"]?.stringValue, "sample")
        XCTAssertEqual(sent["appearance"]?.stringValue, "dark")
        XCTAssertEqual(sent["scale"]?.numberValue, 2)
    }

    func testRenderPreviewOfADraftWithDataOverrides() async throws {
        let draft = MCPFixtures.template(name: "draft", cells: """
        {"id":"title","row":0,"col":0,"colSpan":2,"component":{"type":"text","binding":"{title}"}}
        """)
        let result = try await call("render_preview", .object([
            "template": MCPFixtures.json(draft), "data": .object(["count": .number(12), "subject": .string("A very, very long subject line")]),
        ]))
        XCTAssertFalse(isError(result), (try? text(result)) ?? "")
        let sent = try XCTUnwrap(fake.calls("POST", "/v1/preview").last?.json)
        XCTAssertEqual(sent["template"]?["name"]?.stringValue, "draft", "an unsaved draft travels as an object")
        XCTAssertEqual(sent["template"]?["cells"]?.arrayValue?.count, 1)
        XCTAssertEqual(sent["app"]?.stringValue, "webwatcher.email", "the app comes from the draft")
        XCTAssertEqual(sent["data"]?["count"]?.numberValue, 12, "overrides win")
        XCTAssertEqual(sent["data"]?["sender"]?.stringValue, "Acme Billing", "the rest is the manifest's sample")
        XCTAssertEqual(sent["appearance"]?.stringValue, "light")
        XCTAssertEqual(sent["scale"]?.numberValue, 2)
        XCTAssertEqual(try payload(result)["data"]?.stringValue, "sample+overrides")
    }

    func testRenderPreviewRefusesAnInvalidDraftBeforeCallingHerald() async throws {
        let draft = MCPFixtures.template(cells: """
        {"id":"a","row":0,"col":0,"component":{"type":"text","binding":"{title}"}},
        {"id":"b","row":0,"col":0,"component":{"type":"text","binding":"{subject}"}}
        """)
        let r = try await call("render_preview", .object(["template": MCPFixtures.json(draft)]))
        XCTAssertTrue(isError(r))
        XCTAssertEqual(try payload(r)["errors"]?.arrayValue?.first?["cellId"]?.stringValue, "b")
        XCTAssertTrue(fake.calls("POST", "/v1/preview").isEmpty)
    }

    func testRenderPreviewWithTheLastRealNotification() async throws {
        fake.history = [MCPFixtures.historyItem(id: "n1", title: "Real title", fields: ["title": .text("Real title"), "count": .number(7)])]
        let r = try await call("render_preview", .object(["app": .string("webwatcher.email"), "name": .string("email-accumulated"), "source": .string("last")]))
        XCTAssertFalse(isError(r), (try? text(r)) ?? "")
        let sent = try XCTUnwrap(fake.calls("POST", "/v1/preview").last?.json)
        XCTAssertEqual(sent["data"]?["title"]?.stringValue, "Real title")
        XCTAssertEqual(sent["data"]?["count"]?.numberValue, 7)
        XCTAssertNil(sent["data"]?["sender"], "no sample values are mixed into the real data")

        fake.history = []
        let none = try await call("render_preview", .object(["app": .string("webwatcher.email"), "name": .string("x"), "source": .string("last")]))
        XCTAssertTrue(isError(none))
    }

    func testRenderPreviewOfTheAppsDefaultTemplate() async throws {
        try await assertSucceeds("render_preview", .object(["app": .string("webwatcher.email")]))
        let sent = try XCTUnwrap(fake.calls("POST", "/v1/preview").last?.json)
        XCTAssertEqual(sent["template"], .null, "no template: Herald picks the manifest's default")
        XCTAssertEqual(sent["app"]?.stringValue, "webwatcher.email")
    }

    func testRenderPreviewArgumentChecks() async throws {
        try await assertFails("render_preview", .object([:]), "needs an app")
        try await assertFails("render_preview", .object(["name": .string("x")]), "name needs app")
        try await assertFails("render_preview", .object(["app": .string("a"), "name": .string("x"), "appearance": .string("sepia")]))
        // A 400 from Herald (its own validation) comes back with its message.
        let bad = MCPServer(client: fake.client, previewDirectory: previews)
        fake.previewPNG = Data("not a png".utf8)
        let r = try await call("render_preview", .object(["app": .string("a"), "name": .string("x")]), using: bad)
        XCTAssertTrue(isError(r))
    }

    // MARK: send_notification / send_test

    func testSendNotificationPassesFieldsAtTheTopLevel() async throws {
        let r = try await call("send_notification", .object([
            "app": .string("webwatcher.email"), "title": .string("Hello"), "id": .string("n-1"),
            "template": .string("email-accumulated"),
            "fields": .object(["count": .number(3), "sender": .string("Acme"), "title": .string("ignored: explicit title wins")]),
            "subject": .string("Top-level field too"),
        ]))
        XCTAssertFalse(isError(r), (try? text(r)) ?? "")
        XCTAssertEqual(try payload(r)["id"]?.stringValue, "n-1")
        let sent = try XCTUnwrap(fake.calls("POST", "/v1/notify").last?.json)
        XCTAssertEqual(sent["title"]?.stringValue, "Hello")
        XCTAssertEqual(sent["count"]?.numberValue, 3)
        XCTAssertEqual(sent["sender"]?.stringValue, "Acme")
        XCTAssertEqual(sent["subject"]?.stringValue, "Top-level field too")
        XCTAssertNil(sent["fields"], "`fields` is a convenience, not a payload key")
        try await assertFails("send_notification", .object(["title": .string("no app")]))
    }

    func testSendTestUsesSampleDataAndIssuerActions() async throws {
        let r = try await call("send_test", .object(["app": .string("webwatcher.email"), "template": .string("email-accumulated")]))
        XCTAssertFalse(isError(r), (try? text(r)) ?? "")
        let sent = try XCTUnwrap(fake.calls("POST", "/v1/notify").last?.json)
        XCTAssertEqual(sent["app"]?.stringValue, "webwatcher.email")
        XCTAssertEqual(sent["template"]?.stringValue, "email-accumulated")
        XCTAssertEqual(sent["id"]?.stringValue, "mcp-test-email-accumulated")
        XCTAssertEqual(sent["title"]?.stringValue, "2 new from Acme Billing")
        XCTAssertEqual(sent["sender"]?.stringValue, "Acme Billing")
        XCTAssertEqual(sent["count"]?.numberValue, 2)
        XCTAssertEqual(sent["url"]?.stringValue, "https://example.com", "a declared field without a sample gets the designer's stand-in")
        XCTAssertNil(sent["body"], "an undeclared field is not invented")
        let buttons = try XCTUnwrap(sent["buttons"]?.arrayValue)
        XCTAssertEqual(buttons.compactMap { $0["label"]?.stringValue }, ["Mark as Read", "Archive"])
        XCTAssertEqual(strings(try payload(r)["issuerActions"]), ["markRead", "archive"])

        // Without the issuer's actions, with overrides and our own id.
        _ = try await call("send_test", .object([
            "app": .string("webwatcher.email"), "template": .string("email-accumulated"), "includeIssuerActions": .bool(false),
            "data": .object(["count": .number(99)]), "id": .string("t2"),
        ]))
        let second = try XCTUnwrap(fake.calls("POST", "/v1/notify").last?.json)
        XCTAssertNil(second["buttons"])
        XCTAssertEqual(second["count"]?.numberValue, 99)
        XCTAssertEqual(second["id"]?.stringValue, "t2")
    }

    func testSendTestNeedsASavedTemplate() async throws {
        let r = try await call("send_test", .object(["app": .string("webwatcher.email"), "template": .string("not-saved")]))
        XCTAssertTrue(isError(r))
        XCTAssertEqual(strings(try payload(r)["saved"]), ["email-accumulated"])
        XCTAssertTrue(fake.calls("POST", "/v1/notify").isEmpty)

        // No template named: the manifest's default is used, and without one it is an error.
        try await assertFails("send_test", .object(["app": .string("webwatcher.email")]))
        var m = try XCTUnwrap(fake.manifests["webwatcher.email"]?.objectValue)
        m["defaultTemplate"] = .string("email-accumulated")
        fake.manifests["webwatcher.email"] = .object(m)
        try await assertSucceeds("send_test", .object(["app": .string("webwatcher.email")]))
    }

    func testDismiss() async throws {
        _ = try await call("dismiss", .object(["app": .string("a"), "id": .string("n1")]))
        let one = try XCTUnwrap(fake.calls("POST", "/v1/dismiss").last?.json)
        XCTAssertEqual(one["app"]?.stringValue, "a")
        XCTAssertEqual(one["id"]?.stringValue, "n1")
        try await assertFails("dismiss", .object(["app": .string("a")]), "neither id nor all")
        XCTAssertTrue(fake.calls("POST", "/v1/dismissAll").isEmpty)
        _ = try await call("dismiss", .object(["app": .string("a"), "all": .bool(true)]))
        XCTAssertEqual(fake.calls("POST", "/v1/dismissAll").last?.json?["app"]?.stringValue, "a")
    }

    // MARK: add_action_rule

    func testAddActionRuleAddsAShortcutAndShowsTheResult() async throws {
        let rule: JSONValue = MCPFixtures.json("""
        {"add":{"id":"log","label":"Log it","kind":"shortcut","shortcut":"Log to Notes","input":"{title}\\n{url}"}}
        """)
        let r = try await call("add_action_rule", .object(["app": .string("webwatcher.email"), "template": .string("email-accumulated"), "rule": rule]))
        XCTAssertFalse(isError(r), (try? text(r)) ?? "")
        let report = try payload(r)
        XCTAssertEqual(report["ruleIndex"]?.numberValue, 3, "appended after the three existing rules")
        XCTAssertEqual(report["actionRules"]?.numberValue, 4)
        XCTAssertEqual(strings(report["warnings"]).count, 0)
        XCTAssertEqual(report["resultingActions"]?.arrayValue?.compactMap { $0["id"]?.stringValue }, ["markRead", "shortcut-followup", "log"])

        let saved = try HeraldJSON.decoder().decode(HeraldTemplate.self, from: try XCTUnwrap(fake.calls("PUT", "/v1/templates").last).body)
        XCTAssertEqual(saved.actionRules.count, 4)
        XCTAssertEqual(saved.actionRules.last?.add?.shortcut, "Log to Notes")
        XCTAssertEqual(saved.actionRules.last?.add?.input, "{title}\n{url}")
        XCTAssertEqual(saved.cells.count, 6, "the rest of the template is untouched")

        // The same id again replaces the rule instead of adding a second.
        let again = try payload(try await call("add_action_rule", .object([
            "app": .string("webwatcher.email"), "template": .string("email-accumulated"),
            "rule": MCPFixtures.json(#"{"add":{"id":"log","label":"Log it again","kind":"shortcut","shortcut":"Log to Notes"}}"#)])))
        XCTAssertEqual(again["replacedExistingRule"]?.boolValue, true)
        XCTAssertEqual(again["actionRules"]?.numberValue, 4)
    }

    func testAddActionRuleWarnsAboutMissingShortcutsAndUnmatchedRules() async throws {
        let r = try payload(try await call("add_action_rule", .object([
            "app": .string("webwatcher.email"), "template": .string("email-accumulated"),
            "rule": MCPFixtures.json(#"{"add":{"id":"x","label":"X","kind":"shortcut","shortcut":"log to notes"}}"#)])))
        let warnings = try XCTUnwrap(r["warnings"]?.arrayValue).compactMap { $0["message"]?.stringValue }
        XCTAssertTrue(warnings.contains { $0.contains("did you mean 'Log to Notes'") }, "\(warnings)")

        let r2 = try payload(try await call("add_action_rule", .object([
            "app": .string("webwatcher.email"), "template": .string("email-accumulated"),
            "rule": MCPFixtures.json(#"{"match":"snoooze","hide":true}"#)])))
        let w2 = try XCTUnwrap(r2["warnings"]?.arrayValue).compactMap { $0["message"]?.stringValue }
        XCTAssertTrue(w2.contains { $0.contains("snoooze") }, "\(w2)")
    }

    func testScriptActionsAreCheckedAgainstTheScriptsFolder() async throws {
        let scripts = fake.directory.appendingPathComponent("scripts")
        try FileManager.default.createDirectory(at: scripts.appendingPathComponent("sub"), withIntermediateDirectories: true)
        try "#!/bin/sh\ncat\n".write(to: scripts.appendingPathComponent("log.sh"), atomically: true, encoding: .utf8)
        try "x".write(to: scripts.appendingPathComponent("notes.txt"), atomically: true, encoding: .utf8)
        try "x".write(to: scripts.appendingPathComponent("sub/inner.py"), atomically: true, encoding: .utf8)
        try "x".write(to: scripts.appendingPathComponent(".hidden.sh"), atomically: true, encoding: .utf8)

        let status = try payload(try await call("herald_status"))
        XCTAssertEqual(status["scriptsDirectory"]?.stringValue, scripts.path)
        XCTAssertEqual(strings(status["scripts"]), ["log.sh", "notes.txt"], "hidden files and sub-folders are left out")

        func warnings(_ rule: String) async throws -> [String] {
            let r = try await call("add_action_rule", .object(["app": .string("webwatcher.email"), "template": .string("email-accumulated"),
                                                               "rule": MCPFixtures.json(rule)]))
            XCTAssertFalse(isError(r), (try? text(r)) ?? "")
            return try XCTUnwrap(try payload(r)["warnings"]?.arrayValue).compactMap { $0["message"]?.stringValue }
        }
        let ok = try await warnings(#"{"add":{"id":"s1","label":"Log","kind":"script","script":"log.sh"}}"#)
        XCTAssertEqual(ok, [])
        let missing = try await warnings(#"{"add":{"id":"s3","label":"Nope","kind":"script","script":"missing.sh"}}"#)
        XCTAssertTrue(missing.first?.contains("No file 'missing.sh'") == true, "\(missing)")
        let unrunnable = try await warnings(#"{"add":{"id":"s4","label":"Notes","kind":"script","script":"notes.txt"}}"#)
        XCTAssertTrue(unrunnable.first?.contains("not executable") == true, "\(unrunnable)")
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scripts.appendingPathComponent("notes.txt").path)
        let nowExecutable = try await warnings(#"{"add":{"id":"s5","label":"Notes","kind":"script","script":"notes.txt"}}"#)
        XCTAssertEqual(nowExecutable, [])
    }

    func testAddActionRuleRejections() async throws {
        func fails(_ rule: String, template: String = "email-accumulated", _ why: String) async throws {
            try await assertFails("add_action_rule", .object(["app": .string("webwatcher.email"), "template": .string(template),
                                                               "rule": MCPFixtures.json(rule)]), why)
        }
        let puts = fake.calls("PUT", "/v1/templates").count
        try await fails("{}", "a rule needs match or add")
        try await fails(#"{"match":"archive","style":"shiny"}"#, "style is validated")
        try await fails(#"{"add":{"id":"s","label":"S","kind":"shortcut"}}"#, "a shortcut action names its shortcut")
        try await fails(#"{"add":{"id":"c","label":"C","kind":"carrier-pigeon"}}"#, "unknown kind")
        try await fails(#"{"match":"archive","hide":true}"#, template: "builtin.hero", "built-ins are read-only")
        try await fails(#"{"match":"archive","hide":true}"#, template: "missing", "unknown template")
        XCTAssertEqual(fake.calls("PUT", "/v1/templates").count, puts, "nothing was saved")
    }

    // MARK: Resources

    func testResourcesListAndRead() async throws {
        let listReply = try await rpc("resources/list")
        let list = try XCTUnwrap(listReply["result"]?["resources"]?.arrayValue)
        let uris = list.compactMap { $0["uri"]?.stringValue }
        XCTAssertEqual(uris, ["herald://docs/components", "herald://manifests/webwatcher.email", "herald://templates/webwatcher.email/email-accumulated"])
        for r in list {
            XCTAssertFalse((r["name"]?.stringValue ?? "").isEmpty)
            XCTAssertNotNil(r["mimeType"]?.stringValue)
        }

        let docs = try await rpc("resources/read", .object(["uri": .string("herald://docs/components")]))
        let docsContent = try XCTUnwrap(docs["result"]?["contents"]?.arrayValue?.first)
        XCTAssertEqual(docsContent["uri"]?.stringValue, "herald://docs/components")
        XCTAssertEqual(docsContent["mimeType"]?.stringValue, "text/markdown")
        XCTAssertTrue((docsContent["text"]?.stringValue ?? "").contains("Herald templates"))

        let manifest = try await rpc("resources/read", .object(["uri": .string("herald://manifests/webwatcher.email")]))
        let m = MCPFixtures.json(try XCTUnwrap(manifest["result"]?["contents"]?.arrayValue?.first?["text"]?.stringValue))
        XCTAssertEqual(m["app"]?.stringValue, "webwatcher.email")
        XCTAssertEqual(manifest["result"]?["contents"]?.arrayValue?.first?["mimeType"]?.stringValue, "application/json")

        let template = try await rpc("resources/read", .object(["uri": .string("herald://templates/webwatcher.email/email-accumulated")]))
        let t = MCPFixtures.json(try XCTUnwrap(template["result"]?["contents"]?.arrayValue?.first?["text"]?.stringValue))
        XCTAssertEqual(t["name"]?.stringValue, "email-accumulated")

        let builtin = try await rpc("resources/read", .object(["uri": .string("herald://templates/webwatcher.email/builtin.compact")]))
        XCTAssertNotNil(builtin["result"])

        for bad in ["herald://manifests/nobody", "herald://templates/webwatcher.email/nope", "herald://nothing", "https://example.com", "herald://manifests/"] {
            let r = try await rpc("resources/read", .object(["uri": .string(bad)]))
            XCTAssertEqual(r["error"]?["code"]?.numberValue, -32002, bad)
        }

        let templatesReply = try await rpc("resources/templates/list")
        let templates = try XCTUnwrap(templatesReply["result"]?["resourceTemplates"]?.arrayValue)
        XCTAssertEqual(templates.compactMap { $0["uriTemplate"]?.stringValue },
                       ["herald://manifests/{app}", "herald://templates/{app}/{name}"])
    }

    func testResourceURIsAreEncoded() async throws {
        fake.templates["my app"] = ["Bid won": MCPFixtures.json(#"{"name":"Bid won","app":"my app","layoutVersion":1}"#)]
        let uri = MCPResources.uri(template: "Bid won", app: "my app")
        XCTAssertEqual(uri, "herald://templates/my%20app/Bid%20won")
        let listReply = try await rpc("resources/list")
        let list = try XCTUnwrap(listReply["result"]?["resources"]?.arrayValue)
        XCTAssertTrue(list.contains { $0["uri"]?.stringValue == uri })
        let read = try await rpc("resources/read", .object(["uri": .string(uri)]))
        XCTAssertEqual(MCPFixtures.json(try XCTUnwrap(read["result"]?["contents"]?.arrayValue?.first?["text"]?.stringValue))["name"]?.stringValue, "Bid won")
    }

    // MARK: Preview files

    func testPreviewFilesArePruned() async throws {
        let dir = fake.directory.appendingPathComponent("prune")
        let tools = MCPTools(client: fake.client, previewDirectory: dir)
        for _ in 0..<(MCPTools.keepPreviews + 5) {
            let r = try await tools.call("render_preview", arguments: .object(["app": .string("a"), "name": .string("builtin.hero")]))
            XCTAssertFalse(r.isError)
        }
        let files = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.hasSuffix(".png") }
        XCTAssertEqual(files.count, MCPTools.keepPreviews)
    }

    // MARK: Config

    func testConfigParsing() throws {
        let home = URL(fileURLWithPath: "/home/x/Herald")
        let tmp = URL(fileURLWithPath: "/tmp/t")
        var c = try MCPConfig.parse(arguments: [], environment: [:], defaultSupportDirectory: home, temporaryDirectory: tmp)
        XCTAssertEqual(c.supportDirectory, home)
        XCTAssertNil(c.port); XCTAssertNil(c.token)
        XCTAssertEqual(c.previewDirectory.path, "/tmp/t/herald-previews")
        XCTAssertEqual(c.mode, .run)

        c = try MCPConfig.parse(arguments: ["--port", "5000", "--debug"],
                                environment: ["HERALD_SUPPORT_DIR": "/srv/h", "HERALD_TOKEN": "tok", "HERALD_PREVIEW_DIR": "/srv/p"],
                                defaultSupportDirectory: home, temporaryDirectory: tmp)
        XCTAssertEqual(c.supportDirectory.path, "/srv/h")
        XCTAssertEqual(c.port, 5000)
        XCTAssertEqual(c.token, "tok")
        XCTAssertEqual(c.previewDirectory.path, "/srv/p")
        XCTAssertTrue(c.debug)

        c = try MCPConfig.parse(arguments: ["--support-dir", "/a", "--token", "t2"], environment: ["HERALD_SUPPORT_DIR": "/b", "HERALD_PORT": "4000"],
                                defaultSupportDirectory: home)
        XCTAssertEqual(c.supportDirectory.path, "/a", "a flag beats the environment")
        XCTAssertEqual(c.port, 4000)

        XCTAssertEqual(try MCPConfig.parse(arguments: ["--help"], environment: [:], defaultSupportDirectory: home).mode, .help)
        XCTAssertEqual(try MCPConfig.parse(arguments: ["--version"], environment: [:], defaultSupportDirectory: home).mode, .version)
        for bad in [["--port", "banana"], ["--port"], ["--nope"], ["--port", "70000"]] {
            XCTAssertThrowsError(try MCPConfig.parse(arguments: bad, environment: [:], defaultSupportDirectory: home), "\(bad)")
        }
        XCTAssertThrowsError(try MCPConfig.parse(arguments: [], environment: ["HERALD_PORT": "x"], defaultSupportDirectory: home))
    }

    func testClientOverridesPortAndToken() async throws {
        let ghost = FileManager.default.temporaryDirectory.appendingPathComponent("herald-ghost-\(UUID().uuidString)")
        let c = HeraldClient(supportDirectory: ghost, port: fake.client.port, token: FakeHerald.token)
        XCTAssertEqual(c.port, fake.client.port)
        let names = try await c.shortcuts()
        XCTAssertEqual(names, fake.shortcuts)
    }

    // MARK: Against the real router

    func testToolsAgainstTheRealRouter() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("herald-mcp-router-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let token = try TokenStore.loadOrCreate(in: dir)
        let backend = MCPRouterBackend()
        let router = Router(token: token, backend: backend, version: "1.1.0")
        let listener = HTTPLoopbackListener(port: 0) { await router.handle($0) }
        try listener.start(); defer { listener.stop() }
        try TokenStore.writePort(listener.port, in: dir)
        let s = MCPServer(client: HeraldClient(supportDirectory: dir), previewDirectory: dir.appendingPathComponent("previews"))

        // Manifest and template round-trip through the router's own decoding and validation.
        let put = try await call("put_manifest", .object(["manifest": MCPFixtures.json(MCPFixtures.manifest)]), using: s)
        XCTAssertFalse(isError(put), (try? text(put)) ?? "")
        XCTAssertEqual(backend.manifestsByApp["webwatcher.email"]?.fields.count, 6)
        let m = try payload(try await call("get_manifest", .object(["app": .string("webwatcher.email")]), using: s))
        XCTAssertEqual(m["actions"]?.arrayValue?.compactMap { $0["id"]?.stringValue }, ["markRead", "archive"])
        let rejected = try await call("put_manifest", .object(["manifest": MCPFixtures.json(#"{"app":"x","actions":[{"label":"A","kind":"shortcut"}]}"#)]), using: s)
        XCTAssertTrue(isError(rejected))

        let saved = try await call("put_template", .object(["template": MCPFixtures.json(MCPFixtures.template)]), using: s)
        XCTAssertFalse(isError(saved), (try? text(saved)) ?? "")
        XCTAssertEqual(backend.templatesByKey["webwatcher.email/email-accumulated"]?.cells.count, 6)
        let listed = try payload(try await call("list_templates", .object(["app": .string("webwatcher.email")]), using: s))
        XCTAssertEqual(listed["templates"]?.arrayValue?.first?["name"]?.stringValue, "email-accumulated")
        let back = try payload(try await call("get_template", .object(["app": .string("webwatcher.email"), "name": .string("email-accumulated")]), using: s))
        XCTAssertEqual(back["actionRules"]?.arrayValue?.count, 3)

        // The schema comes from the router (it is the same document, with no "built in" note).
        let schema = try await call("component_schema", using: s)
        XCTAssertEqual(schema["content"]?.arrayValue?.count, 1)
        XCTAssertEqual(MCPFixtures.json(try text(schema))["schemaVersion"]?.numberValue, Double(ComponentSchema.schemaVersion))
        let shortcuts = try payload(try await call("list_shortcuts", using: s))
        XCTAssertEqual(strings(shortcuts["shortcuts"]), backend.shortcutNames)

        // add_action_rule: the stored template gains the rule.
        let rule = try await call("add_action_rule", .object(["app": .string("webwatcher.email"), "template": .string("email-accumulated"),
            "rule": MCPFixtures.json(#"{"add":{"id":"log","label":"Log","kind":"shortcut","shortcut":"Log to Notes"}}"#)]), using: s)
        XCTAssertFalse(isError(rule), (try? text(rule)) ?? "")
        XCTAssertEqual(backend.templatesByKey["webwatcher.email/email-accumulated"]?.actionRules.last?.add?.shortcut, "Log to Notes")

        // render_preview: a saved template with data overrides, then an inline draft.
        let r1 = try await call("render_preview", .object(["app": .string("webwatcher.email"), "name": .string("email-accumulated"),
                                                           "appearance": .string("dark"), "data": .object(["count": .number(9)])]), using: s)
        XCTAssertFalse(isError(r1), (try? text(r1)) ?? "")
        XCTAssertNotNil(r1["content"]?.arrayValue?.first { $0["type"]?.stringValue == "image" })
        let spec1 = try XCTUnwrap(backend.previews.last)
        XCTAssertEqual(spec1.template, .named("email-accumulated"))
        XCTAssertEqual(spec1.appearance, .dark)
        XCTAssertEqual(spec1.scale, 2)
        XCTAssertEqual(spec1.data?.metadata?.objectValue?["count"], .number(9), "the router carries a field in metadata")
        XCTAssertEqual(spec1.data?.title, "2 new from Acme Billing", "and the manifest's sample title came along")

        let draft = MCPFixtures.template(name: "draft", cells: """
        {"id":"t","row":0,"col":0,"component":{"type":"text","binding":"{title}"}}
        """)
        let r2 = try await call("render_preview", .object(["template": MCPFixtures.json(draft)]), using: s)
        XCTAssertFalse(isError(r2), (try? text(r2)) ?? "")
        guard case .inline(let inline)? = backend.previews.last?.template else { return XCTFail("expected an inline template") }
        XCTAssertEqual(inline.name, "draft")
        let r3 = try await call("render_preview", .object(["app": .string("webwatcher.email")]), using: s)
        XCTAssertFalse(isError(r3), (try? text(r3)) ?? "")
        XCTAssertNil(backend.previews.last?.template, "no template: the app's default")

        // send_notification and send_test: manifest fields at the top level end up in the notification's metadata.
        let sent = try await call("send_notification", .object(["app": .string("webwatcher.email"), "title": .string("Hi"), "id": .string("n9"),
                                                                "fields": .object(["count": .number(3), "sender": .string("Acme")])]), using: s)
        XCTAssertFalse(isError(sent), (try? text(sent)) ?? "")
        let n = try XCTUnwrap(backend.notified.last)
        XCTAssertEqual(n.id, "n9")
        XCTAssertEqual(n.metadata?.objectValue?["sender"], .string("Acme"))
        XCTAssertEqual(n.metadata?.objectValue?["count"], .number(3))

        let test = try await call("send_test", .object(["app": .string("webwatcher.email"), "template": .string("email-accumulated")]), using: s)
        XCTAssertFalse(isError(test), (try? text(test)) ?? "")
        let t = try XCTUnwrap(backend.notified.last)
        XCTAssertEqual(t.template, "email-accumulated")
        XCTAssertEqual(t.id, "mcp-test-email-accumulated")
        XCTAssertEqual(t.buttons?.map(\.label), ["Mark as Read", "Archive"])
        XCTAssertEqual(t.metadata?.objectValue?["subject"], .string("Invoice #4021"))
    }

    // MARK: The real binary over stdio

    /// Pipes a scripted session into the built `herald-mcp` and checks what comes out: every stdout line is one
    /// JSON-RPC message, in order, and a tool call reaches the fake Herald over HTTP.
    func testBinaryOverStdio() async throws {
        let binary = Bundle(for: MCPProtocolTests.self).bundleURL.deletingLastPathComponent().appendingPathComponent("herald-mcp")
        guard FileManager.default.isExecutableFile(atPath: binary.path) else { throw XCTSkip("herald-mcp is not built next to the tests") }

        let script = [
            #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"stdio-test","version":"1"}}}"#,
            #"{"jsonrpc":"2.0","method":"notifications/initialized"}"#,
            #"{"jsonrpc":"2.0","id":2,"method":"tools/list"}"#,
            #"{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"list_shortcuts","arguments":{}}}"#,
            "this is not json",
            #"{"jsonrpc":"2.0","id":4,"method":"ping"}"#,
        ].joined(separator: "\n") + "\n"

        let process = Process()
        process.executableURL = binary
        process.environment = ["HERALD_SUPPORT_DIR": fake.directory.path, "HERALD_PREVIEW_DIR": previews.path]
        let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
        process.standardInput = stdin; process.standardOutput = stdout; process.standardError = stderr
        try process.run()
        stdin.fileHandleForWriting.write(Data(script.utf8))
        try stdin.fileHandleForWriting.close()
        let output = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)

        let lines = String(decoding: output, as: UTF8.self).split(separator: "\n").map(String.init)
        XCTAssertEqual(lines.count, 5, "initialize, tools/list, tools/call, the parse error, ping (the notification gets none)")
        let replies = lines.map(MCPFixtures.json)
        XCTAssertEqual(replies.map { $0["id"] }, [.number(1), .number(2), .number(3), .null, .number(4)])
        XCTAssertEqual(replies[0]["result"]?["serverInfo"]?["name"]?.stringValue, "herald-mcp")
        XCTAssertEqual(replies[1]["result"]?["tools"]?.arrayValue?.count, Self.expectedTools.count)
        let shortcuts = MCPFixtures.json(try XCTUnwrap(replies[2]["result"]?["content"]?.arrayValue?.first?["text"]?.stringValue))
        XCTAssertEqual(strings(shortcuts["shortcuts"]), fake.shortcuts)
        XCTAssertEqual(replies[3]["error"]?["code"]?.numberValue, -32700)
        XCTAssertEqual(fake.calls("GET", "/v1/shortcuts").count, 1)
        XCTAssertEqual(fake.calls("GET", "/v1/shortcuts").first?.authorization, "Bearer test-token")
        XCTAssertTrue(String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).contains("ready"), "logs go to stderr")
    }
}
