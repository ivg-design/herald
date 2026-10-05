import XCTest
@testable import HeraldClient
@testable import HeraldCore

/// `PUT /v1/templates/follow-up` (set_follow_up) and the follow-up rows of the approvals list, over real stores in a
/// temporary folder. The route reports approval state and never grants it.
final class SetFollowUpTests: XCTestCase {
    final class Host: ParityHost, @unchecked Sendable {}

    var root: URL!
    var service: ParityService!
    var registry: AppRegistry!
    var templates: TemplateStore!
    var manifests: ManifestStore!
    var approvals: TemplateCommandApprovals!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("herald-followup-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        registry = AppRegistry(file: root.appendingPathComponent("apps.json"))
        templates = TemplateStore(directory: root.appendingPathComponent("templates"))
        manifests = ManifestStore(directory: root.appendingPathComponent("manifests"))
        approvals = TemplateCommandApprovals(file: root.appendingPathComponent("approvals.json"))
        service = ParityService(templates: templates, manifests: manifests, history: HistoryStore(directory: root.appendingPathComponent("history")),
                                registry: registry, assets: AssetStore(directory: root.appendingPathComponent("assets")),
                                approvals: approvals, host: Host(),
                                actionRunner: ActionRunner(scriptsDirectory: root.appendingPathComponent("scripts")))
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    // MARK: Helpers

    private func put(_ body: [String: Any]) async -> HTTPResponse {
        let data = (try? JSONSerialization.data(withJSONObject: body)) ?? Data()
        return await service.handle(HTTPRequest(method: "PUT", path: "/v1/templates/follow-up", query: [:], headers: [:], body: data))
    }

    private func assertStatus(_ body: [String: Any], _ code: Int, _ message: String = "", line: UInt = #line) async {
        let r = await put(body)
        XCTAssertEqual(r.status, code, message + " " + text(r), line: line)
    }

    private func json(_ r: HTTPResponse) throws -> [String: Any] {
        try XCTUnwrap(try JSONSerialization.jsonObject(with: r.body) as? [String: Any], String(decoding: r.body, as: UTF8.self))
    }

    private func text(_ r: HTTPResponse) -> String { String(decoding: r.body, as: UTF8.self) }

    private func manifest(_ app: String, default d: String? = nil) throws -> HeraldManifest {
        let json = """
        {"app":"\(app)","appName":"Demo","fields":[{"key":"title","type":"text","sample":"Hi"}],
         "actions":[{"id":"run","label":"Run","kind":"command","command":"echo hi"},{"id":"cb","label":"Ping","kind":"callback"},
                    {"id":"link","label":"Open","kind":"url","url":"https://example.com"}]\(d.map { ",\"defaultTemplate\":\"\($0)\"" } ?? "")}
        """
        return try HeraldJSON.decoder().decode(HeraldManifest.self, from: Data(json.utf8))
    }

    private func seedApp(_ app: String, commands: Bool = false) {
        registry.register(HeraldAppRegistration(app: app, appName: "Demo", allowCommands: commands ? true : nil))
    }

    private func seedStoredDefault(_ app: String, name: String = "hero") throws {
        var t = BuiltinTemplates.template(layout: .hero, app: app)
        t.name = name
        XCTAssertTrue(templates.put(t))
        var m = try manifest(app, default: name)
        m.defaultTemplate = name
        XCTAssertTrue(manifests.put(m))
    }

    private func assertNothingGranted(_ before: (Int, [Bool]), file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(approvals.all().count, before.0, "no approval granted", file: file, line: line)
        XCTAssertEqual(registry.all().map(\.commandsConfirmed), before.1, "commandsConfirmed untouched", file: file, line: line)
    }

    private var snapshot: (Int, [Bool]) { (approvals.all().count, registry.all().map(\.commandsConfirmed)) }

    // MARK: With a stored default template

    func testEditsTheStoredDefaultTemplateAndReportsApprovalWithoutGrantingIt() async throws {
        seedApp("demo"); try seedStoredDefault("demo")
        let before = snapshot
        let r = await put(["app": "demo", "after": "10m", "shortcut": "Forward to phone", "input": "{title}"])
        XCTAssertEqual(r.status, 200, text(r))
        let o = try json(r)
        XCTAssertEqual(o["saved"] as? Bool, true)
        XCTAssertEqual(o["template"] as? String, "hero")
        XCTAssertEqual(o["createdTemplate"] as? Bool, false)
        XCTAssertEqual(o["origin"] as? String, "template")
        XCTAssertEqual(o["approval"] as? String, "needs-approval")
        XCTAssertEqual(o["needsApproval"] as? Bool, true)
        XCTAssertTrue((o["note"] as? String ?? "").contains("list_shortcuts"))
        XCTAssertEqual((o["followUp"] as? [String: Any])?["after"] as? Int, 600)
        let action = try XCTUnwrap(o["action"] as? [String: Any])
        XCTAssertEqual(action["kind"] as? String, "shortcut"); XCTAssertEqual(action["label"] as? String, "Forward to phone")
        XCTAssertEqual(action["input"] as? String, "{title}")
        let saved = try XCTUnwrap(templates.get(app: "demo", name: "hero")?.followUp)
        XCTAssertEqual(saved.after, 600); XCTAssertEqual(saved.action?.shortcut, "Forward to phone")
        XCTAssertEqual(templates.list(app: "demo").count, 1, "no copy made")
        assertNothingGranted(before)
    }

    func testAnApprovedTemplateActionReportsApproved() async throws {
        seedApp("demo"); try seedStoredDefault("demo")
        let runner = ActionRunner(scriptsDirectory: root.appendingPathComponent("scripts"))
        let action = HeraldAction(id: "follow-up", label: "Forward", kind: .shortcut, shortcut: "Forward", input: nil)
        approvals.approve(app: "demo", template: "hero", commands: [try XCTUnwrap(runner.approvalKey(for: action))])
        let o = try json(await put(["app": "demo", "after": 60, "shortcut": "Forward", "label": "Forward"]))
        XCTAssertEqual(o["approval"] as? String, "approved")
        XCTAssertEqual(o["needsApproval"] as? Bool, false)
    }

    func testNamedTemplateAndTheBuiltInAndMissingCases() async throws {
        seedApp("demo"); try seedStoredDefault("demo")
        var other = BuiltinTemplates.template(layout: .compact, app: "demo"); other.name = "other"
        XCTAssertTrue(templates.put(other))
        let ok = try json(await put(["app": "demo", "template": "other", "after": 30, "command": "echo hi"]))
        XCTAssertEqual(ok["template"] as? String, "other")
        XCTAssertNotNil(templates.get(app: "demo", name: "other")?.followUp)
        XCTAssertNil(templates.get(app: "demo", name: "hero")?.followUp)
        let builtin = await put(["app": "demo", "template": "builtin.hero", "after": 30, "command": "echo hi"])
        XCTAssertEqual(builtin.status, 400); XCTAssertTrue(text(builtin).contains("duplicate"))
        await assertStatus(["app": "demo", "template": "nope", "after": 30, "command": "echo"], 404)
    }

    func testAnIssuerActionRefRunsUnderTheAppPermission() async throws {
        seedApp("demo", commands: false); try seedStoredDefault("demo")
        let before = snapshot
        let denied = try json(await put(["app": "demo", "after": "5m", "actionRef": "run"]))
        XCTAssertEqual(denied["origin"] as? String, "issuer")
        XCTAssertEqual(denied["approval"] as? String, "app-not-allowed")
        registry.register(HeraldAppRegistration(app: "demo", appName: "Demo", allowCommands: true))
        let ask = try json(await put(["app": "demo", "after": "5m", "actionRef": "run"]))
        XCTAssertEqual(ask["approval"] as? String, "app-permission-needed")
        XCTAssertEqual(ask["needsApproval"] as? Bool, true)
        let cb = try json(await put(["app": "demo", "after": "5m", "actionRef": "cb"]))
        XCTAssertEqual(cb["approval"] as? String, "none", "a callback runs no code")
        assertNothingGranted(before)
    }

    // MARK: Without a template

    func testCreatesADefaultTemplateAndMakesItTheManifestDefault() async throws {
        seedApp("demo")
        XCTAssertTrue(manifests.put(try manifest("demo")))
        let before = snapshot
        let o = try json(await put(["app": "demo", "after": "2h", "script": "log.sh"]))
        XCTAssertEqual(o["createdTemplate"] as? Bool, true)
        XCTAssertEqual(o["template"] as? String, "default")
        XCTAssertEqual(manifests.get(app: "demo")?.defaultTemplate, "default")
        XCTAssertEqual(manifests.get(app: "demo")?.actions.count, 3, "the manifest keeps its actions")
        let t = try XCTUnwrap(templates.get(app: "demo", name: "default"))
        XCTAssertEqual(t.followUp?.after, 7200); XCTAssertEqual(t.followUp?.action?.script, "log.sh")
        XCTAssertFalse(t.cells.isEmpty, "a copy of the layout")
        XCTAssertEqual(o["approval"] as? String, "needs-approval")
        assertNothingGranted(before)
    }

    func testTheCopyFollowsABuiltInDefaultLayoutAndAvoidsTakenNames() async throws {
        seedApp("demo")
        var other = BuiltinTemplates.template(layout: .imageLeft, app: "demo"); other.name = "default"
        XCTAssertTrue(templates.put(other))
        XCTAssertTrue(manifests.put(try manifest("demo", default: "builtin.compact")))
        let o = try json(await put(["app": "demo", "after": 90, "shortcut": "S"]))
        XCTAssertEqual(o["template"] as? String, "default-2")
        XCTAssertEqual(manifests.get(app: "demo")?.defaultTemplate, "default-2")
        let copy = try XCTUnwrap(templates.get(app: "demo", name: "default-2"))
        XCTAssertEqual(copy.grid, BuiltinTemplates.named("builtin.compact", app: "demo")?.grid)
        XCTAssertNil(templates.get(app: "demo", name: "default")?.followUp, "the existing template is untouched")
    }

    func testACloudConnectorAppWithNoManifestGetsOne() async throws {
        let before = snapshot
        let o = try json(await put(["app": "cloud.chatgpt", "after": "10m", "shortcut": "Forward"]))
        XCTAssertEqual(o["createdTemplate"] as? Bool, true)
        XCTAssertEqual(o["manifestCreated"] as? Bool, true)
        XCTAssertEqual(manifests.get(app: "cloud.chatgpt")?.defaultTemplate, "default")
        XCTAssertEqual(templates.get(app: "cloud.chatgpt", name: "default")?.followUp?.action?.shortcut, "Forward")
        XCTAssertEqual(o["approval"] as? String, "needs-approval")
        assertNothingGranted(before)
    }

    // MARK: Off and refusals

    func testEnabledFalseSwitchesTheTemplateFollowUpOff() async throws {
        seedApp("demo"); try seedStoredDefault("demo")
        let o = try json(await put(["app": "demo", "enabled": false]))
        XCTAssertEqual((o["followUp"] as? [String: Any])?["enabled"] as? Bool, false)
        XCTAssertEqual(o["approval"] as? String, "none")
        XCTAssertEqual(templates.get(app: "demo", name: "hero")?.followUp, HeraldFollowUp(enabled: false))
        await assertStatus(["app": "demo", "enabled": false, "after": 60, "command": "x"], 400)
    }

    func testAUrlActionRefIsRefused() async throws {
        seedApp("demo"); try seedStoredDefault("demo")
        let r = await put(["app": "demo", "after": 60, "actionRef": "link"])
        XCTAssertEqual(r.status, 400)
        XCTAssertTrue(text(r).contains("url"), text(r))
        XCTAssertNil(templates.get(app: "demo", name: "hero")?.followUp)
        await assertStatus(["app": "demo", "after": 60, "actionRef": "nothing"], 400)
    }

    func testAfterOutOfRangeAndMissingArgumentsAreRefused() async throws {
        seedApp("demo"); try seedStoredDefault("demo")
        for after: Any in [1, 4, 604_801, "8d", "soon", "1s"] {
            let r = await put(["app": "demo", "after": after, "shortcut": "S"])
            XCTAssertEqual(r.status, 400, "after \(after): \(text(r))")
        }
        await assertStatus(["app": "demo", "shortcut": "S"], 400, "after is required")
        await assertStatus(["app": "demo", "after": 60], 400, "an action is required")
        await assertStatus(["app": "demo", "after": 60, "shortcut": "S", "command": "x"], 400, "one action only")
        await assertStatus(["app": "demo", "after": 60, "script": "../x.sh"], 400, "a plain script name")
        await assertStatus(["after": 60, "shortcut": "S"], 400, "app is required")
        XCTAssertNil(templates.get(app: "demo", name: "hero")?.followUp)
        XCTAssertEqual(templates.list(app: "demo").count, 1)
    }

    // MARK: Approvals list

    func testListApprovalsGainsFollowUpRows() async throws {
        seedApp("demo"); try seedStoredDefault("demo")
        _ = await put(["app": "demo", "after": "10m", "shortcut": "Forward"])
        var m = try XCTUnwrap(manifests.get(app: "demo"))
        m.followUp = HeraldFollowUp(after: 300, actionRef: "cb")
        XCTAssertTrue(manifests.put(m))
        seedApp("other", commands: true)
        var om = try manifest("other"); om.followUp = HeraldFollowUp(after: 300, actionRef: "run")
        XCTAssertTrue(manifests.put(om))
        let r = await service.handle(HTTPRequest(method: "GET", path: "/v1/actions/approvals", query: [:], headers: [:], body: Data()))
        let rows = try XCTUnwrap(try json(r)["followUps"] as? [[String: Any]])
        let t = try XCTUnwrap(rows.first { $0["source"] as? String == "template" })
        XCTAssertEqual(t["app"] as? String, "demo"); XCTAssertEqual(t["template"] as? String, "hero")
        XCTAssertEqual(t["kind"] as? String, "shortcut"); XCTAssertEqual(t["origin"] as? String, "template")
        XCTAssertEqual(t["approval"] as? String, "needs-approval"); XCTAssertEqual(t["action"] as? String, "Forward")
        let demoManifest = try XCTUnwrap(rows.first { $0["source"] as? String == "manifest" && $0["app"] as? String == "demo" })
        XCTAssertEqual(demoManifest["kind"] as? String, "callback"); XCTAssertEqual(demoManifest["approval"] as? String, "none")
        XCTAssertNil(demoManifest["template"])
        let other = try XCTUnwrap(rows.first { $0["app"] as? String == "other" })
        XCTAssertEqual(other["origin"] as? String, "issuer"); XCTAssertEqual(other["approval"] as? String, "app-permission-needed")
        XCTAssertEqual(rows.count, 3)
    }

    func testListApprovalsFollowUpsIsEmptyWithoutAny() async throws {
        let r = await service.handle(HTTPRequest(method: "GET", path: "/v1/actions/approvals", query: [:], headers: [:], body: Data()))
        XCTAssertEqual((try json(r)["followUps"] as? [Any])?.count, 0)
    }

    func testTheRouteAcceptsOnlyPut() async throws {
        let r = await service.handle(HTTPRequest(method: "GET", path: "/v1/templates/follow-up", query: [:], headers: [:], body: Data()))
        XCTAssertEqual(r.status, 405)
    }
}
