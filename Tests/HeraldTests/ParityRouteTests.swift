import XCTest
@testable import HeraldClient
@testable import HeraldCore

/// The routes that give the MCP server (and any client) everything the Designer, History and Settings can do
/// (docs/reference/parity.md, issue #56), over real stores in a temporary folder and a recording host.
final class ParityRouteTests: XCTestCase {
    final class Host: ParityHost, @unchecked Sendable {
        var values: [String: JSONValue] = ["port": .number(48617), "muteAllSounds": .bool(false), "stacking": .string("bySender")]
        var applied: [(String, JSONValue)] = []
        var appVoiceCalls: [(String, String, JSONValue)] = []
        var reshown: [HeraldNotification] = []
        var closed: [(String, String)] = []
        var changes = 0
        var installs: [(String, Bool, String?, String?)] = []
        var installOpens: [(String?, String?)] = []
        var voiceActions: [String] = []
        func settingValue(_ key: String) async -> JSONValue? { values[key] }
        func applySetting(_ key: String, _ value: JSONValue) async throws { applied.append((key, value)); values[key] = value }
        func options() async -> [String: JSONValue] { ["sounds": .array([.string("none"), .string("Glass")])] }
        func appVoice(_ app: String) async -> [String: JSONValue] { ["speak": .bool(true), "voice": .null, "urgentBreaksQuiet": .bool(false)] }
        func applyAppVoice(app: String, key: String, value: JSONValue) async throws { appVoiceCalls.append((app, key, value)) }
        func voiceState() async throws -> JSONValue { .object(["engine": .string("system")]) }
        func voiceInstall(action: String) async throws -> JSONValue { voiceActions.append(action); return .object(["ok": .bool(true)]) }
        func mcpStatus() async throws -> JSONValue { .object(["server": .string("/x/herald-mcp")]) }
        func mcpInstall(client: String, reinstall: Bool, name: String?, icon: String?, opens: String?, detectedHost: String?) async throws -> JSONValue { installs.append((client, reinstall, name, icon)); installOpens.append((opens, detectedHost)); return .object(["ok": .bool(true)]) }
        func reshow(_ n: HeraldNotification) async throws -> String { reshown.append(n); return "again" }
        func closeBanner(app: String, id: String) async { closed.append((app, id)) }
        func changed() async { changes += 1 }
    }

    var root: URL!
    var host: Host!
    var service: ParityService!
    var registry: AppRegistry!
    var history: HistoryStore!
    var templates: TemplateStore!
    var manifests: ManifestStore!
    var approvals: TemplateCommandApprovals!
    var assets: AssetStore!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("herald-parity-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        host = Host()
        registry = AppRegistry(file: root.appendingPathComponent("apps.json"))
        history = HistoryStore(directory: root.appendingPathComponent("history"))
        templates = TemplateStore(directory: root.appendingPathComponent("templates"))
        manifests = ManifestStore(directory: root.appendingPathComponent("manifests"))
        approvals = TemplateCommandApprovals(file: root.appendingPathComponent("approvals.json"))
        assets = AssetStore(directory: root.appendingPathComponent("assets"))
        let catalog = SymbolCatalog(names: ["bell", "bell.fill", "arrow.up", "cloud.sun"],
                                    terms: ["bell": ["ring", "alarm"], "cloud.sun": ["weather"]],
                                    categories: [SymbolCategory(key: "communication", title: "Communication", icon: "bubble"),
                                                 SymbolCategory(key: "weather", title: "Weather", icon: "sun.max")],
                                    categoryKeys: ["bell": ["communication"], "bell.fill": ["communication"], "cloud.sun": ["weather"]])
        let listing = SymbolListing(catalog: catalog)
        service = ParityService(templates: templates, manifests: manifests, history: history, registry: registry, assets: assets,
                                approvals: approvals, host: host, symbols: { listing })
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    // MARK: Helpers

    @discardableResult
    private func call(_ method: String, _ path: String, _ body: Any? = nil, query: [String: String] = [:]) async -> HTTPResponse {
        let data = body.map { (try? JSONSerialization.data(withJSONObject: $0)) ?? Data() } ?? Data()
        return await service.handle(HTTPRequest(method: method, path: path, query: query, headers: [:], body: data))
    }

    private func json(_ r: HTTPResponse) throws -> [String: Any] {
        try XCTUnwrap(try JSONSerialization.jsonObject(with: r.body) as? [String: Any], String(decoding: r.body, as: UTF8.self))
    }

    private func text(_ r: HTTPResponse) -> String { String(decoding: r.body, as: UTF8.self) }

    private func seedApp(_ app: String = "demo", commands: Bool = false) {
        registry.register(HeraldAppRegistration(app: app, appName: "Demo", callbackURL: "https://hooks.example.com/x",
                                                allowCommands: commands ? true : nil))
        if commands { registry.update(app) { $0.commandsConfirmed = true; $0.callbackHostApproved = "hooks.example.com" } }
    }

    private func seedTemplate(_ name: String = "hero", app: String = "demo") -> HeraldTemplate {
        var t = HeraldTemplate.blank(name: name, app: app)
        t.grid = HeraldGrid(rows: 2, cols: 2)
        t.cells = [HeraldCell(id: "c", row: 0, col: 0, component: .text(HeraldTextComponent(binding: "{title}")))]
        XCTAssertTrue(templates.put(t))
        return t
    }

    private func notification(_ app: String, _ id: String, _ title: String, body: String? = nil) -> HeraldHistoryItem {
        HeraldHistoryItem(id: id, app: app, notification: HeraldNotification(app: app, id: id, title: title, body: body), deliveredAt: Date())
    }

    // MARK: Routing

    func testOwnsOnlyItsPathsAndAnswersMethods() async {
        XCTAssertTrue(ParityService.owns("/v1/settings"))
        XCTAssertFalse(ParityService.owns("/v1/settings/stacking"))
        let r = await call("DELETE", "/v1/settings")
        XCTAssertEqual(r.status, 405)
    }

    func testRouterRoutesToTheServiceAndAnswers501WithoutOne() async throws {
        final class WithParity: HeraldBackend, @unchecked Sendable {
            let parity: ParityService?
            init(_ p: ParityService?) { parity = p }
            func notify(_ n: HeraldNotification) async throws -> String { "x" }
            func register(_ r: HeraldAppRegistration) async throws {}
            func dismiss(app: String, id: String) async throws {}
            func dismissAll(app: String?) async throws {}
            func history(app: String?, limit: Int) async throws -> [HeraldHistoryItem] { [] }
            func clearHistory(app: String?) async throws {}
            func apps() async throws -> [HeraldAppRegistration] { [] }
        }
        func send(_ router: Router, token: String?) async -> HTTPResponse {
            var h: [String: String] = [:]
            if let token { h["authorization"] = "Bearer \(token)" }
            return await router.handle(HTTPRequest(method: "GET", path: "/v1/settings", query: [:], headers: h, body: Data()))
        }
        let with = Router(token: "t", backend: WithParity(service), version: "1", pid: 1)
        let r = await send(with, token: "t")
        XCTAssertEqual(r.status, 200)
        let no = await send(with, token: nil)
        XCTAssertEqual(no.status, 401, "the same Bearer token guards the new routes")
        let without = Router(token: "t", backend: WithParity(nil), version: "1", pid: 1)
        let r501 = await send(without, token: "t")
        XCTAssertEqual(r501.status, 501)
    }

    // MARK: Settings

    func testGetSettingsHasValuesSchemaAndOptions() async throws {
        let o = try json(await call("GET", "/v1/settings"))
        let settings = try XCTUnwrap(o["settings"] as? [String: Any])
        XCTAssertEqual(settings["muteAllSounds"] as? Bool, false)
        XCTAssertEqual(settings["stacking"] as? String, "bySender")
        let schema = try XCTUnwrap(o["schema"] as? [[String: Any]])
        XCTAssertTrue(schema.contains { $0["key"] as? String == "voiceSpeed" && $0["type"] as? String == "number" })
        XCTAssertNotNil((o["options"] as? [String: Any])?["sounds"])
    }

    func testPutSettingsValidatesEverythingBeforeApplyingAnything() async throws {
        var r = await call("PUT", "/v1/settings", ["muteAllSounds": true, "stacking": "never", "voiceSpeed": 1.25])
        XCTAssertEqual(r.status, 200, text(r))
        XCTAssertEqual(Set(host.applied.map(\.0)), ["muteAllSounds", "stacking", "voiceSpeed"])
        XCTAssertGreaterThan(host.changes, 0)

        host.applied = []
        let bad: [[String: Any]] = [
            ["bogus": 1], ["muteAllSounds": "yes"], ["muteAllSounds": 1], ["stacking": "sideways"], ["port": 80], ["port": 50000.5],
            ["voiceSpeed": 5], ["voiceDefault": ""], ["voiceDefault": "../etc"], ["voiceLang": "x y"], ["voiceEngine": "robot"],
            ["historyCapPerApp": 0], ["voiceDefault": NSNull()], [:],
            ["muteAllSounds": false, "port": 70000],
        ]
        for b in bad {
            r = await call("PUT", "/v1/settings", b)
            XCTAssertEqual(r.status, 400, "\(b) -> \(text(r))")
        }
        XCTAssertTrue(host.applied.isEmpty, "a rejected request changes nothing")
        r = await call("PUT", "/v1/settings", ["voiceSystem": NSNull()])
        XCTAssertEqual(r.status, 200, "nullable settings accept null")
        r = await call("PUT", "/v1/settings", ["port": 48701])
        XCTAssertEqual(r.status, 200)
        XCTAssertNotNil(try json(r)["note"], "the port change says the server restarts")
    }

    func testEverySettingInTheTableIsReadableAndWritable() async throws {
        for d in SettingsSchema.general {
            let sample: Any
            switch d.kind {
            case .bool: sample = true
            case .integer(let r): sample = r.lowerBound
            case .number(let r): sample = r.lowerBound
            case .choice(let v): sample = v[0]
            case .text: sample = d.key == "voiceLang" ? "en-gb" : (d.key == "voiceDefault" ? "bf_emma" : "x")
            }
            let r = await call("PUT", "/v1/settings", [d.key: sample])
            XCTAssertEqual(r.status, 200, "\(d.key): \(text(r))")
        }
    }

    // MARK: Per-app settings

    func testAppSettingsListAndUpdate() async throws {
        seedApp(commands: true)
        var o = try json(await call("GET", "/v1/apps/settings"))
        var app = try XCTUnwrap((o["apps"] as? [[String: Any]])?.first)
        XCTAssertEqual((app["approvals"] as? [String: Any])?["commandsConfirmed"] as? Bool, true)
        XCTAssertEqual((app["approvals"] as? [String: Any])?["callbackHostApproved"] as? String, "hooks.example.com")

        let r = await call("PUT", "/v1/apps/settings", ["app": "demo", "sound": "Ping", "persistent": false, "timeout": 12,
                                                         "corner": "bottomLeft", "display": "main", "muteBanners": true,
                                                         "stacking": "never", "speak": false, "voice": "af_bella", "urgentBreaksQuiet": true])
        XCTAssertEqual(r.status, 200, text(r))
        let rec = try XCTUnwrap(registry.record(for: "demo"))
        XCTAssertEqual(rec.registration.defaults?.sound, "Ping")
        XCTAssertEqual(rec.registration.defaults?.persistent, false)
        XCTAssertEqual(rec.registration.defaults?.timeout, 12)
        XCTAssertEqual(rec.corner, .bottomLeft)
        XCTAssertNil(rec.screen, "main is stored as no override")
        XCTAssertTrue(rec.mutedBanners)
        XCTAssertEqual(rec.stacking, StackingLevel.never)
        XCTAssertEqual(Set(host.appVoiceCalls.map(\.1)), ["speak", "voice", "urgentBreaksQuiet"])

        // null clears an override.
        _ = await call("PUT", "/v1/apps/settings", ["app": "demo", "corner": NSNull(), "stacking": NSNull(), "display": "4251"])
        let again = try XCTUnwrap(registry.record(for: "demo"))
        XCTAssertNil(again.corner); XCTAssertNil(again.stacking); XCTAssertEqual(again.screen, "4251")

        o = try json(await call("GET", "/v1/apps/settings", query: ["app": "demo"]))
        app = try XCTUnwrap((o["apps"] as? [[String: Any]])?.first)
        XCTAssertEqual((app["settings"] as? [String: Any])?["display"] as? String, "4251")

        for bad: [String: Any] in [["app": "demo", "corner": "middle"], ["app": "demo", "timeout": -1], ["app": "demo", "display": "left"],
                                    ["app": "demo", "nope": true], ["app": "demo"], ["sound": "x"]] {
            let b = await call("PUT", "/v1/apps/settings", bad)
            XCTAssertEqual(b.status, 400, "\(bad)")
        }
        let missing = await call("PUT", "/v1/apps/settings", ["app": "ghost", "muteBanners": true])
        XCTAssertEqual(missing.status, 404)
        let none = await call("GET", "/v1/apps/settings", query: ["app": "ghost"])
        XCTAssertEqual(none.status, 404)
    }

    func testApprovalsCanBeRevokedButNeverGranted() async throws {
        seedApp(commands: true)
        for grant: [String: Any] in [["app": "demo", "revokeCommands": false], ["app": "demo", "revokeCallbackHost": false]] {
            let r = await call("PUT", "/v1/apps/settings", grant)
            XCTAssertEqual(r.status, 403, text(r))
        }
        XCTAssertTrue(try XCTUnwrap(registry.record(for: "demo")).commandsConfirmed, "refused: nothing changed")
        // Unknown keys cannot grant either.
        let g = await call("PUT", "/v1/apps/settings", ["app": "demo", "commandsConfirmed": true])
        XCTAssertEqual(g.status, 400)
        let r = await call("PUT", "/v1/apps/settings", ["app": "demo", "revokeCommands": true, "revokeCallbackHost": true])
        XCTAssertEqual(r.status, 200, text(r))
        let rec = try XCTUnwrap(registry.record(for: "demo"))
        XCTAssertFalse(rec.commandsConfirmed); XCTAssertNil(rec.callbackHostApproved)
    }

    func testTemplateApprovalsListAndRevoke() async throws {
        approvals.approve(app: "demo", template: "hero", commands: ["say hi"])
        var o = try json(await call("GET", "/v1/actions/approvals"))
        XCTAssertEqual((o["items"] as? [[String: Any]])?.first?["template"] as? String, "hero")
        var r = await call("DELETE", "/v1/actions/approvals", query: ["app": "demo", "template": "hero"])
        XCTAssertEqual(r.status, 200)
        XCTAssertFalse(approvals.isApproved(app: "demo", template: "hero", command: "say hi"))
        r = await call("DELETE", "/v1/actions/approvals", query: ["app": "demo", "template": "hero"])
        XCTAssertEqual(r.status, 404)
        r = await call("DELETE", "/v1/actions/approvals", query: ["app": "demo"])
        XCTAssertEqual(r.status, 400)
        o = try json(await call("GET", "/v1/actions/approvals"))
        XCTAssertEqual((o["items"] as? [Any])?.count, 0)
        r = await call("POST", "/v1/actions/approvals")
        XCTAssertEqual(r.status, 405, "there is no way to POST an approval")
    }

    // MARK: Voice and MCP

    func testVoiceAndMcpRoutesPassThroughToTheHost() async throws {
        var r = await call("GET", "/v1/voice")
        XCTAssertEqual(r.status, 200)
        r = await call("POST", "/v1/voice/install", ["action": "install"])
        XCTAssertEqual(r.status, 200)
        r = await call("POST", "/v1/voice/install", ["action": "format"])
        XCTAssertEqual(r.status, 400)
        XCTAssertEqual(host.voiceActions, ["install"])
        r = await call("GET", "/v1/mcp")
        XCTAssertEqual(r.status, 200)
        r = await call("POST", "/v1/mcp/install", ["client": "codex", "reinstall": true])
        XCTAssertEqual(r.status, 200)
        XCTAssertEqual(host.installs.first?.0, "codex"); XCTAssertEqual(host.installs.first?.1, true)
        r = await call("POST", "/v1/mcp/install", ["client": "generic", "name": "My Bot"])
        XCTAssertEqual(r.status, 200)
        XCTAssertEqual(host.installs.last?.2, "My Bot")
        r = await call("POST", "/v1/mcp/install", ["client": "generic"])
        XCTAssertEqual(r.status, 400, "a generic client needs a name")
        r = await call("POST", "/v1/mcp/install", ["client": "codex", "icon": "/no/such/icon.png"])
        XCTAssertEqual(r.status, 400)
        r = await call("POST", "/v1/mcp/install", ["client": "vim"])
        XCTAssertEqual(r.status, 400)
        r = await call("POST", "/v1/mcp/install", [:])
        XCTAssertEqual(r.status, 400)
    }

    // MARK: Assets

    private let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 13] + Array("IHDR".utf8) + [UInt8](repeating: 0, count: 20))

    func testUploadListAndDeleteAnImageAndARiveFile() async throws {
        var r = await call("POST", "/v1/assets", ["app": "demo", "name": "logo.png", "base64": png.base64EncodedString()])
        XCTAssertEqual(r.status, 200, text(r))
        let image = try json(r)
        XCTAssertEqual(image["kind"] as? String, "image"); XCTAssertEqual(image["format"] as? String, "png")
        XCTAssertTrue(FileManager.default.fileExists(atPath: try XCTUnwrap(image["path"] as? String)))

        let riv = Data((0..<300).map { UInt8($0 % 251) })
        r = await call("POST", "/v1/assets", ["app": "demo", "name": "confetti.riv", "base64": riv.base64EncodedString()])
        XCTAssertEqual(r.status, 200, text(r))
        XCTAssertEqual(((try json(r))["component"] as? [String: Any])?["path"] as? String, "confetti.riv")

        _ = seedTemplate()
        var t = try XCTUnwrap(templates.get(app: "demo", name: "hero"))
        t.cells.append(HeraldCell(id: "r", row: 1, col: 0, component: .rive(HeraldRiveComponent(path: "confetti.riv"))))
        XCTAssertTrue(templates.put(t))

        let list = try json(await call("GET", "/v1/assets", query: ["app": "demo"]))
        let items = try XCTUnwrap(list["assets"] as? [[String: Any]])
        XCTAssertEqual(items.map { $0["file"] as? String }.sorted { ($0 ?? "") < ($1 ?? "") }, ["confetti.riv", "logo.png"])
        XCTAssertEqual(items.first { $0["kind"] as? String == "rive" }?["usedBy"] as? [String], ["hero"])

        r = await call("DELETE", "/v1/assets", query: ["app": "demo", "file": "confetti.riv"])
        XCTAssertEqual(r.status, 200)
        XCTAssertEqual(try json(r)["stillReferencedBy"] as? [String], ["hero"], "the reply names the templates left with a placeholder")
        r = await call("DELETE", "/v1/assets", query: ["app": "demo", "file": "logo.png"])
        XCTAssertEqual(r.status, 200)
        r = await call("DELETE", "/v1/assets", query: ["app": "demo", "file": "logo.png"])
        XCTAssertEqual(r.status, 404)
    }

    func testUploadFromAPathAndRejections() async throws {
        let src = root.appendingPathComponent("big.png")
        try png.write(to: src)
        var r = await call("POST", "/v1/assets", ["app": "demo", "path": src.path])
        XCTAssertEqual(r.status, 200, text(r))

        r = await call("POST", "/v1/assets", ["app": "demo", "name": "x.png", "base64": Data("not an image at all".utf8).base64EncodedString()])
        XCTAssertEqual(r.status, 400, "bytes are checked, not the name")
        r = await call("POST", "/v1/assets", ["app": "demo", "name": "../evil.png", "base64": png.base64EncodedString()])
        XCTAssertEqual(r.status, 400, "no path traversal")
        r = await call("POST", "/v1/assets", ["app": "demo", "name": "a.png", "base64": png.base64EncodedString(), "path": src.path])
        XCTAssertEqual(r.status, 400, "base64 and path together")
        r = await call("POST", "/v1/assets", ["app": "demo", "base64": png.base64EncodedString()])
        XCTAssertEqual(r.status, 400, "base64 needs a name")
        r = await call("POST", "/v1/assets", ["app": "demo", "path": root.appendingPathComponent("missing.png").path])
        XCTAssertEqual(r.status, 400)
        r = await call("POST", "/v1/assets", ["app": "demo", "name": "notes.txt", "base64": png.base64EncodedString()])
        XCTAssertEqual(r.status, 400, "the kind cannot be told")
        r = await call("POST", "/v1/assets", ["app": "demo", "name": "a.riv", "base64": Data().base64EncodedString()])
        XCTAssertEqual(r.status, 400)
        r = await call("GET", "/v1/assets")
        XCTAssertEqual(r.status, 400, "app is required")
    }

    // MARK: Templates

    func testDuplicateRenameAndDefault() async throws {
        _ = seedTemplate()
        manifests.put(HeraldManifest(app: "demo", appName: "Demo", defaultTemplate: "hero"))

        var o = try json(await call("POST", "/v1/templates/duplicate", ["app": "demo", "name": "hero"]))
        XCTAssertEqual(o["name"] as? String, "hero copy")
        o = try json(await call("POST", "/v1/templates/duplicate", ["app": "demo", "name": "hero"]))
        XCTAssertEqual(o["name"] as? String, "hero copy 2", "a taken name is numbered")
        o = try json(await call("POST", "/v1/templates/duplicate", ["app": "demo", "name": "hero", "newName": "wide", "toApp": "other"]))
        XCTAssertEqual(o["app"] as? String, "other")
        XCTAssertNotNil(templates.get(app: "other", name: "wide"))
        o = try json(await call("POST", "/v1/templates/duplicate", ["app": "demo", "name": "builtin.hero", "newName": "from-builtin"]))
        XCTAssertNotNil(templates.get(app: "demo", name: "from-builtin"), "built-in layouts can be copied")
        var r = await call("POST", "/v1/templates/duplicate", ["app": "demo", "name": "hero", "newName": "wide", "toApp": "other"])
        XCTAssertEqual(r.status, 409)
        r = await call("POST", "/v1/templates/duplicate", ["app": "demo", "name": "hero", "newName": "builtin.x"])
        XCTAssertEqual(r.status, 400)
        r = await call("POST", "/v1/templates/duplicate", ["app": "demo", "name": "ghost"])
        XCTAssertEqual(r.status, 404)

        // Rename moves the default with it.
        r = await call("POST", "/v1/templates/rename", ["app": "demo", "name": "hero", "newName": "banner"])
        XCTAssertEqual(r.status, 200, text(r))
        XCTAssertNil(templates.get(app: "demo", name: "hero")); XCTAssertNotNil(templates.get(app: "demo", name: "banner"))
        XCTAssertEqual(manifests.get(app: "demo")?.defaultTemplate, "banner")
        XCTAssertEqual(try json(r)["isDefault"] as? Bool, true)
        for bad in [["app": "demo", "name": "banner", "newName": "hero copy"], ["app": "demo", "name": "banner", "newName": "a/b"],
                    ["app": "demo", "name": "builtin.hero", "newName": "x"], ["app": "demo", "name": "banner", "newName": "_x"]] {
            r = await call("POST", "/v1/templates/rename", bad)
            XCTAssertTrue([400, 409].contains(r.status), "\(bad) -> \(r.status)")
        }
        r = await call("POST", "/v1/templates/rename", ["app": "demo", "name": "ghost", "newName": "x"])
        XCTAssertEqual(r.status, 404)
        // A stored template that already carries a reserved name (older data) can be renamed away from it.
        XCTAssertTrue(templates.put(HeraldTemplate.blank(name: "builtin.old", app: "demo")))
        r = await call("POST", "/v1/templates/rename", ["app": "demo", "name": "builtin.old", "newName": "old"])
        XCTAssertEqual(r.status, 200, text(r))

        r = await call("PUT", "/v1/templates/default", ["app": "demo", "name": "hero copy"])
        XCTAssertEqual(r.status, 200); XCTAssertEqual(manifests.get(app: "demo")?.defaultTemplate, "hero copy")
        r = await call("PUT", "/v1/templates/default", ["app": "demo", "name": "builtin.compact"])
        XCTAssertEqual(r.status, 200)
        r = await call("PUT", "/v1/templates/default", ["app": "demo"])
        XCTAssertEqual(r.status, 200); XCTAssertNil(manifests.get(app: "demo")?.defaultTemplate, "no name clears it")
        r = await call("PUT", "/v1/templates/default", ["app": "demo", "name": "ghost"])
        XCTAssertEqual(r.status, 404)
        r = await call("PUT", "/v1/templates/default", ["app": "nomanifest", "name": "x"])
        XCTAssertEqual(r.status, 400)
    }

    func testExportAndImportABundleKeepsTheAnimation() async throws {
        var t = seedTemplate("anim")
        let riv = Data((0..<400).map { UInt8(($0 * 3) % 251) })
        let r0 = await call("POST", "/v1/assets", ["app": "demo", "name": "bell.riv", "base64": riv.base64EncodedString()])
        XCTAssertEqual(r0.status, 200)
        t.cells.append(HeraldCell(id: "r", row: 1, col: 0, component: .rive(HeraldRiveComponent(path: "bell.riv"))))
        XCTAssertTrue(templates.put(t))

        var o = try json(await call("GET", "/v1/templates/export", query: ["app": "demo", "name": "anim"]))
        XCTAssertEqual(o["assets"] as? [String], ["bell.riv"])
        let b64 = try XCTUnwrap(o["base64"] as? String)

        // Into another app, twice: the second is kept beside the first.
        o = try json(await call("POST", "/v1/templates/import", ["base64": b64, "app": "copy-app"]))
        XCTAssertEqual(o["name"] as? String, "anim"); XCTAssertEqual(o["installedAssets"] as? [String], ["bell.riv"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: assets.folder(for: "copy-app").appendingPathComponent("bell.riv").path))
        o = try json(await call("POST", "/v1/templates/import", ["base64": b64, "app": "copy-app"]))
        XCTAssertEqual(o["name"] as? String, "anim 2"); XCTAssertEqual(o["renamedFrom"] as? String, "anim")
        var r = await call("POST", "/v1/templates/import", ["base64": b64, "app": "copy-app", "onConflict": "fail"])
        XCTAssertEqual(r.status, 409)
        r = await call("POST", "/v1/templates/import", ["base64": b64, "app": "copy-app", "onConflict": "replace"])
        XCTAssertEqual(try json(r)["replaced"] as? Bool, true)
        r = await call("POST", "/v1/templates/import", ["base64": b64, "onConflict": "sideways"])
        XCTAssertEqual(r.status, 400)

        // Through files.
        let file = root.appendingPathComponent("anim.heraldtemplate")
        r = await call("GET", "/v1/templates/export", query: ["app": "demo", "name": "anim", "path": file.path])
        XCTAssertEqual(r.status, 200, text(r))
        XCTAssertNil(try json(r)["base64"]); XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        r = await call("POST", "/v1/templates/import", ["path": file.path, "app": "third"])
        XCTAssertEqual(r.status, 200, text(r))
        r = await call("POST", "/v1/templates/import", ["path": root.appendingPathComponent("x.zip").path])
        XCTAssertEqual(r.status, 400)
        r = await call("POST", "/v1/templates/import", ["base64": Data("junk".utf8).base64EncodedString()])
        XCTAssertEqual(r.status, 400)
        r = await call("POST", "/v1/templates/import", [:])
        XCTAssertEqual(r.status, 400)
        r = await call("GET", "/v1/templates/export", query: ["app": "demo", "name": "ghost"])
        XCTAssertEqual(r.status, 404)
    }

    // MARK: History

    func testSearchReshowDeleteAndExport() async throws {
        seedApp()
        history.upsert(notification("demo", "a", "Invoice paid", body: "Acme sent $40"))
        history.upsert(notification("demo", "b", "Build failed", body: "main is red"))
        history.upsert(notification("other", "c", "Invoice overdue"))

        var o = try json(await call("GET", "/v1/history/search", query: ["q": "invoice"]))
        XCTAssertEqual(o["count"] as? Int, 2)
        o = try json(await call("GET", "/v1/history/search", query: ["q": "invoice", "app": "demo"]))
        XCTAssertEqual((o["items"] as? [[String: Any]])?.first?["id"] as? String, "a")
        o = try json(await call("GET", "/v1/history/search", query: ["q": "acme paid"]))
        XCTAssertEqual(o["count"] as? Int, 1, "every word must match")
        o = try json(await call("GET", "/v1/history/search", query: ["q": "demo"]))
        XCTAssertEqual(o["count"] as? Int, 2, "the app name matches too")
        var r = await call("GET", "/v1/history/search", query: ["q": "x", "limit": "-1"])
        XCTAssertEqual(r.status, 400)

        r = await call("POST", "/v1/history/reshow", ["app": "demo", "id": "a"])
        XCTAssertEqual(r.status, 200); XCTAssertEqual(host.reshown.first?.title, "Invoice paid")
        XCTAssertEqual(try json(r)["id"] as? String, "again")
        r = await call("POST", "/v1/history/reshow", ["app": "demo", "id": "zzz"])
        XCTAssertEqual(r.status, 404)

        o = try json(await call("GET", "/v1/history/export", query: ["app": "demo"]))
        XCTAssertEqual(o["count"] as? Int, 2)
        let file = root.appendingPathComponent("out.json")
        r = await call("GET", "/v1/history/export", query: ["path": file.path])
        XCTAssertEqual(try json(r)["count"] as? Int, 3)
        XCTAssertNotNil(try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [Any])
        r = await call("GET", "/v1/history/export", query: ["path": root.appendingPathComponent("o.txt").path])
        XCTAssertEqual(r.status, 400)

        r = await call("DELETE", "/v1/history/item", query: ["app": "demo", "id": "a"])
        XCTAssertEqual(r.status, 200)
        XCTAssertNil(history.item(app: "demo", id: "a")); XCTAssertNotNil(history.item(app: "demo", id: "b"))
        XCTAssertEqual(host.closed.first?.1, "a", "its banner is closed")
        r = await call("DELETE", "/v1/history/item", query: ["app": "demo", "id": "a"])
        XCTAssertEqual(r.status, 404)
        r = await call("DELETE", "/v1/history/item", query: ["app": "demo"])
        XCTAssertEqual(r.status, 400)
    }

    // MARK: Symbols

    func testSymbolsSearchByNameTermAndCategory() async throws {
        var o = try json(await call("GET", "/v1/symbols", query: ["q": "bell"]))
        XCTAssertEqual((o["symbols"] as? [[String: Any]])?.map { $0["name"] as? String }, ["bell", "bell.fill"])
        XCTAssertEqual(((o["symbols"] as? [[String: Any]])?.first?["categories"] as? [String]), ["communication"])
        o = try json(await call("GET", "/v1/symbols", query: ["q": "alarm"]))
        XCTAssertEqual(o["total"] as? Int, 1, "search terms count")
        o = try json(await call("GET", "/v1/symbols", query: ["category": "weather"]))
        XCTAssertEqual((o["symbols"] as? [[String: Any]])?.map { $0["name"] as? String }, ["cloud.sun"])
        o = try json(await call("GET", "/v1/symbols", query: ["limit": "2", "offset": "1"]))
        XCTAssertEqual((o["symbols"] as? [Any])?.count, 2); XCTAssertEqual(o["total"] as? Int, 4)
        XCTAssertEqual((o["categories"] as? [[String: Any]])?.first { $0["key"] as? String == "communication" }?["count"] as? Int, 2)
        let r = await call("GET", "/v1/symbols", query: ["category": "nope"])
        XCTAssertEqual(r.status, 400)
    }

    func testRealSymbolListingLoadsWhenThisMacHasOne() throws {
        guard let listing = SymbolListing.load() else { throw XCTSkip("no CoreGlyphs on this machine") }
        XCTAssertTrue(listing.catalog.contains("bell"))
        XCTAssertEqual(listing.categories.first?.key, "all")
        XCTAssertGreaterThan(listing.categories.count, 5)
        XCTAssertFalse(listing.categories(of: "bell").isEmpty)
    }
}
