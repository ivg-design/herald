import XCTest
@testable import HeraldCore
@testable import herald_mcp

/// Every parity tool is a thin wrapper over one Herald route (docs/reference/parity.md): the tool call becomes exactly
/// that request, the reply comes back as the tool's JSON, and nothing else happens in herald-mcp.
final class ParityToolTests: XCTestCase {
    final class Recorder: @unchecked Sendable {
        struct Call { var method: String; var path: String; var query: [String: String]; var body: JSONValue? }
        let directory: URL
        private let lock = NSLock()
        private var _calls: [Call] = []
        private var listener: HTTPLoopbackListener?
        var failNext: (Int, String)?
        var calls: [Call] { lock.lock(); defer { lock.unlock() }; return _calls }

        init() throws {
            directory = FileManager.default.temporaryDirectory.appendingPathComponent("herald-ptool-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try "tok".write(to: HeraldPaths.tokenURL(in: directory), atomically: true, encoding: .utf8)
            let l = HTTPLoopbackListener(port: 0) { [weak self] req in
                guard let self else { return .error(500, "gone") }
                guard req.headers["authorization"] == "Bearer tok" else { return .error(401, "unauthorized") }
                self.lock.lock()
                self._calls.append(Call(method: req.method, path: req.path, query: req.query,
                                        body: try? JSONDecoder().decode(JSONValue.self, from: req.body)))
                let fail = self.failNext; self.failNext = nil
                self.lock.unlock()
                if let (status, message) = fail { return .error(status, message) }
                if req.path == "/v1/designer/snapshot" { return .png(FakeHerald.png(width: 1100, height: 820)) }
                return .json(200, JSONValue.object(["ok": .bool(true), "path": .string(req.path)]))
            }
            try l.start()
            listener = l
            try "\(l.port)".write(to: HeraldPaths.portURL(in: directory), atomically: true, encoding: .utf8)
        }

        func stop() { listener?.stop(); try? FileManager.default.removeItem(at: directory) }
    }

    var rec: Recorder!
    var tools: MCPTools!

    override func setUpWithError() throws {
        rec = try Recorder()
        tools = MCPTools(client: HeraldClient(supportDirectory: rec.directory), previewDirectory: rec.directory.appendingPathComponent("previews"))
    }

    override func tearDown() { rec.stop() }

    private func run(_ name: String, _ args: [String: JSONValue]) async throws -> MCPToolResult {
        try await tools.call(name, arguments: .object(args))
    }

    private func s(_ v: String) -> JSONValue { .string(v) }

    // MARK: Table

    struct Case {
        var tool: String
        var args: [String: JSONValue]
        var method: String
        var path: String
        var query: [String: String] = [:]
        var body: [String: JSONValue]? = nil
    }

    func testEveryToolBecomesExactlyOneRequest() async throws {
        let cases: [Case] = [
            Case(tool: "get_settings", args: [:], method: "GET", path: "/v1/settings"),
            Case(tool: "set_settings", args: ["settings": .object(["muteAllSounds": .bool(true)])], method: "PUT", path: "/v1/settings", body: ["muteAllSounds": .bool(true)]),
            Case(tool: "list_apps", args: [:], method: "GET", path: "/v1/apps/settings"),
            Case(tool: "list_apps", args: ["app": s("demo")], method: "GET", path: "/v1/apps/settings", query: ["app": "demo"]),
            Case(tool: "update_app_settings", args: ["app": s("demo"), "settings": .object(["muteBanners": .bool(true)])], method: "PUT", path: "/v1/apps/settings", body: ["app": s("demo"), "muteBanners": .bool(true)]),
            Case(tool: "register_app", args: ["app": s("demo"), "appName": s("Demo"), "allowCommands": .bool(true)], method: "POST", path: "/v1/register", body: ["app": s("demo"), "appName": s("Demo"), "allowCommands": .bool(true)]),
            Case(tool: "voice_status", args: [:], method: "GET", path: "/v1/voice"),
            Case(tool: "install_voice", args: ["action": s("useExisting")], method: "POST", path: "/v1/voice/install", body: ["action": s("useExisting")]),
            Case(tool: "install_mcp", args: [:], method: "GET", path: "/v1/mcp"),
            Case(tool: "install_mcp", args: ["client": s("codex"), "reinstall": .bool(true)], method: "POST", path: "/v1/mcp/install", body: ["client": s("codex"), "reinstall": .bool(true)]),
            Case(tool: "get_replies", args: ["app": s("demo"), "since": s("2026-10-02T10:00:00Z"), "consume": .bool(true)], method: "GET", path: "/v1/replies", query: ["app": "demo", "since": "2026-10-02T10:00:00Z", "consume": "true"]),
            Case(tool: "wait_for_reply", args: ["notificationId": s("n1"), "app": s("demo"), "timeoutSeconds": .number(30)], method: "GET", path: "/v1/replies/wait", query: ["app": "demo", "id": "n1", "timeout": "30"]),
            Case(tool: "relay_status", args: [:], method: "GET", path: "/v1/relay/status"),
            Case(tool: "relay_usage", args: [:], method: "GET", path: "/v1/relay/usage"),
            Case(tool: "list_connectors", args: [:], method: "GET", path: "/v1/relay/connectors"),
            Case(tool: "create_agent_key", args: ["name": s("build-bot"), "client": s("claude")], method: "POST", path: "/v1/relay/keys", body: ["name": s("build-bot"), "client": s("claude")]),
            Case(tool: "revoke_agent_key", args: ["id": s("a1b2c3d4")], method: "DELETE", path: "/v1/relay/keys/a1b2c3d4"),
            Case(tool: "relay_token_url", args: [:], method: "GET", path: "/v1/relay/token-url"),
            Case(tool: "relay_set_cloudflare_token", args: ["token": s("cf-token-0123456789abcdef")], method: "POST", path: "/v1/relay/token", body: ["token": s("cf-token-0123456789abcdef")]),
            Case(tool: "relay_deploy", args: [:], method: "POST", path: "/v1/relay/deploy"),
            Case(tool: "relay_pair", args: [:], method: "POST", path: "/v1/relay/pair"),
            Case(tool: "relay_unpair", args: [:], method: "POST", path: "/v1/relay/unpair"),
            Case(tool: "relay_settings", args: [:], method: "GET", path: "/v1/relay/settings"),
            Case(tool: "relay_settings", args: ["settings": .object(["maxQueue": .number(50)])], method: "PUT", path: "/v1/relay/settings", body: ["maxQueue": .number(50)]),
            Case(tool: "relay_zones", args: [:], method: "GET", path: "/v1/relay/zones"),
            Case(tool: "relay_settings", args: ["settings": .object(["customDomain": .object(["zone": s("example.com"), "hostname": s("herald.example.com")])])], method: "PUT", path: "/v1/relay/settings",
                 body: ["customDomain": .object(["zone": s("example.com"), "hostname": s("herald.example.com")])]),
            Case(tool: "relay_delete", args: ["confirm": .bool(true)], method: "POST", path: "/v1/relay/delete", body: ["confirm": .bool(true)]),
            Case(tool: "relay_instructions", args: ["client": s("chatgpt")], method: "GET", path: "/v1/relay/instructions", query: ["client": "chatgpt"]),
            Case(tool: "relay_test", args: [:], method: "POST", path: "/v1/relay/test"),
            Case(tool: "list_approvals", args: [:], method: "GET", path: "/v1/actions/approvals"),
            Case(tool: "revoke_approval", args: ["app": s("demo"), "template": s("hero")], method: "DELETE", path: "/v1/actions/approvals", query: ["app": "demo", "template": "hero"]),
            Case(tool: "duplicate_template", args: ["app": s("demo"), "name": s("hero"), "newName": s("b")], method: "POST", path: "/v1/templates/duplicate", body: ["app": s("demo"), "name": s("hero"), "newName": s("b")]),
            Case(tool: "rename_template", args: ["app": s("demo"), "name": s("hero"), "newName": s("b")], method: "POST", path: "/v1/templates/rename", body: ["app": s("demo"), "name": s("hero"), "newName": s("b")]),
            Case(tool: "set_default_template", args: ["app": s("demo"), "name": s("hero")], method: "PUT", path: "/v1/templates/default", body: ["app": s("demo"), "name": s("hero")]),
            Case(tool: "set_default_template", args: ["app": s("demo")], method: "PUT", path: "/v1/templates/default", body: ["app": s("demo")]),
            Case(tool: "export_template_bundle", args: ["app": s("demo"), "name": s("hero"), "path": s("/tmp/h.heraldtemplate")], method: "GET", path: "/v1/templates/export", query: ["app": "demo", "name": "hero", "path": "/tmp/h.heraldtemplate"]),
            Case(tool: "import_template_bundle", args: ["path": s("/tmp/h.heraldtemplate"), "onConflict": s("replace")], method: "POST", path: "/v1/templates/import", body: ["path": s("/tmp/h.heraldtemplate"), "onConflict": s("replace")]),
            Case(tool: "delete_app", args: ["app": s("example.bidbot")], method: "DELETE", path: "/v1/apps/example.bidbot"),
            Case(tool: "delete_app", args: ["app": s("my app")], method: "DELETE", path: "/v1/apps/my%20app"),
            Case(tool: "delete_manifest", args: ["app": s("demo")], method: "DELETE", path: "/v1/manifest", query: ["app": "demo"]),
            Case(tool: "list_assets", args: ["app": s("demo")], method: "GET", path: "/v1/assets", query: ["app": "demo"]),
            Case(tool: "upload_asset", args: ["app": s("demo"), "name": s("a.png"), "base64": s("AAAA")], method: "POST", path: "/v1/assets", body: ["app": s("demo"), "name": s("a.png"), "base64": s("AAAA")]),
            Case(tool: "delete_asset", args: ["app": s("demo"), "file": s("a.png")], method: "DELETE", path: "/v1/assets", query: ["app": "demo", "file": "a.png"]),
            Case(tool: "list_symbols", args: ["q": s("bell"), "category": s("communication"), "limit": .number(20), "offset": .number(40)], method: "GET", path: "/v1/symbols", query: ["q": "bell", "category": "communication", "limit": "20", "offset": "40"]),
            Case(tool: "rive_check", args: ["app": s("demo"), "component": .object(["path": s("a.riv")]), "simulate": .array([s("hoverIn")])], method: "POST", path: "/v1/rive/check", body: ["app": s("demo"), "component": .object(["path": s("a.riv")]), "simulate": .array([s("hoverIn")])]),
            Case(tool: "history_search", args: ["q": s("invoice"), "app": s("demo"), "limit": .number(5)], method: "GET", path: "/v1/history/search", query: ["q": "invoice", "app": "demo", "limit": "5"]),
            Case(tool: "reshow_notification", args: ["app": s("demo"), "id": s("a")], method: "POST", path: "/v1/history/reshow", body: ["app": s("demo"), "id": s("a")]),
            Case(tool: "delete_history", args: ["app": s("demo"), "id": s("a")], method: "DELETE", path: "/v1/history/item", query: ["app": "demo", "id": "a"]),
            Case(tool: "delete_history", args: ["app": s("demo"), "all": .bool(true)], method: "DELETE", path: "/v1/history", query: ["app": "demo"]),
            Case(tool: "delete_history", args: ["all": .bool(true)], method: "DELETE", path: "/v1/history"),
            Case(tool: "export_history", args: ["app": s("demo"), "path": s("/tmp/h.json")], method: "GET", path: "/v1/history/export", query: ["app": "demo", "path": "/tmp/h.json"]),
            Case(tool: "snooze", args: ["app": s("demo"), "id": s("a"), "minutes": .number(15)], method: "POST", path: "/v1/snooze", body: ["app": s("demo"), "id": s("a"), "minutes": .number(15)]),
            Case(tool: "snooze", args: ["app": s("demo"), "id": s("a"), "cancel": .bool(true)], method: "POST", path: "/v1/unsnooze", body: ["app": s("demo"), "id": s("a")]),
            Case(tool: "expand_stack", args: ["app": s("demo"), "group": s("g"), "expanded": .bool(false)], method: "POST", path: "/v1/stacks/expand", body: ["app": s("demo"), "group": s("g"), "expanded": .bool(false)]),
        ]
        for c in cases {
            let before = rec.calls.count
            let r = try await run(c.tool, c.args)
            XCTAssertFalse(r.isError, "\(c.tool): \(r.blocks)")
            let made = Array(rec.calls.dropFirst(before))
            XCTAssertEqual(made.count, 1, "\(c.tool) makes one request")
            guard let call = made.first else { continue }
            XCTAssertEqual(call.method, c.method, c.tool)
            XCTAssertEqual(call.path, c.path, c.tool)
            XCTAssertEqual(call.query, c.query, c.tool)
            XCTAssertEqual(call.body, c.body.map { .object($0) }, c.tool)
            guard case .text(let t)? = r.blocks.first else { XCTFail("\(c.tool) returns text"); continue }
            XCTAssertTrue(t.contains(c.path), "\(c.tool) returns Herald's reply")
        }
        // The cases cover every JSON tool.
        let covered = Set(cases.map(\.tool))
        XCTAssertEqual(covered, Set(ParityTools.all.map(\.definition.name)), "a tool without a test")
    }

    func testDesignerSnapshotReturnsAnImageAndAsksForTheSnapshotRoute() async throws {
        let r = try await run("designer_snapshot", ["app": s("demo"), "template": s("hero"), "select": s("c1"), "width": .number(1200)])
        XCTAssertFalse(r.isError)
        guard case .image(_, let mime)? = r.blocks.first else { return XCTFail("an image") }
        XCTAssertEqual(mime, "image/png")
        let call = try XCTUnwrap(rec.calls.last)
        XCTAssertEqual(call.path, "/v1/designer/snapshot")
        XCTAssertEqual(call.query["select"], "c1"); XCTAssertEqual(call.query["width"], "1200")
    }

    // MARK: Failures

    func testMissingArgumentsAreToolErrorsNotRequests() async throws {
        for (tool, args) in [("set_settings", [String: JSONValue]()), ("update_app_settings", ["app": s("demo")]), ("delete_history", ["app": s("demo")]),
                             ("snooze", ["app": s("demo"), "id": s("a")]), ("revoke_approval", ["app": s("demo")]), ("duplicate_template", ["app": s("x")])] {
            let r = try await run(tool, args)
            XCTAssertTrue(r.isError, tool)
        }
        XCTAssertTrue(rec.calls.isEmpty, "bad arguments never reach Herald")
    }

    func testHeraldErrorsComeBackAsReadableToolErrors() async throws {
        rec.failNext = (403, "revokeCommands: only true is accepted")
        let r = try await run("update_app_settings", ["app": s("demo"), "settings": .object(["revokeCommands": .bool(false)])])
        XCTAssertTrue(r.isError)
        guard case .text(let t)? = r.blocks.first else { return XCTFail() }
        XCTAssertTrue(t.contains("403") && t.contains("only true"))
    }

    // MARK: Catalog

    func testCatalogHasEveryToolWithAnnotationsAndNoDuplicates() throws {
        let names = MCPToolCatalog.all.map(\.name)
        XCTAssertEqual(names.count, Set(names).count, "tool names are unique")
        let expected = ["get_settings", "set_settings", "list_apps", "update_app_settings", "register_app", "delete_app", "voice_status", "install_voice",
                        "install_mcp", "list_approvals", "revoke_approval", "duplicate_template", "rename_template", "set_default_template",
                        "export_template_bundle", "import_template_bundle", "delete_manifest", "list_assets", "upload_asset", "delete_asset",
                        "list_symbols", "rive_check", "history_search", "reshow_notification", "delete_history", "export_history", "snooze",
                        "expand_stack", "designer_snapshot"]
        for n in expected { XCTAssertTrue(names.contains(n), n) }
        for d in MCPToolCatalog.all {
            XCTAssertFalse(d.description.isEmpty, d.name)
            guard case .object(let schema) = d.inputSchema, schema["type"] == .string("object") else { XCTFail("\(d.name) schema"); continue }
        }
        // Destructive tools say so; read tools are read-only.
        for n in ["delete_history", "delete_app", "delete_asset", "delete_manifest", "revoke_approval", "rename_template", "import_template_bundle"] {
            XCTAssertTrue(MCPToolCatalog.byName[n]?.destructive == true, "\(n) is destructive")
        }
        for n in ["get_settings", "list_apps", "list_symbols", "history_search", "list_assets", "voice_status", "list_approvals", "designer_snapshot", "rive_check"] {
            XCTAssertTrue(MCPToolCatalog.byName[n]?.readOnly == true, "\(n) is read-only")
        }
        XCTAssertFalse(MCPToolCatalog.byName["install_voice"]?.idempotent ?? true)
    }

    func testNoToolCanGrantAnApproval() throws {
        // The one thing that must not be reachable: a way to approve command or callback execution.
        let text = MCPToolCatalog.all.map { $0.name + " " + $0.description }.joined(separator: "\n").lowercased()
        XCTAssertFalse(text.contains("approve_"), "no approve tool")
        for d in MCPToolCatalog.all { XCTAssertFalse(d.name.contains("grant") || d.name.hasPrefix("approve"), d.name) }
    }
}
