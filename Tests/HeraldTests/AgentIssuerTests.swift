import XCTest
import ImageIO
import CoreGraphics
import UniformTypeIdentifiers
@testable import HeraldClient
@testable import HeraldCore
@testable import herald_mcp

/// MCP agents as issuers (issue #62): the identity, manifest and template of an installed client, registering them
/// without disturbing what the user changed, the server configuration that carries `--agent`, the icon lookup, and
/// `herald-mcp` defaulting its app from the flag.
final class AgentIssuerTests: XCTestCase {
    var root: URL!
    var registry: AppRegistry!
    var manifests: ManifestStore!
    var templates: TemplateStore!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("herald-agent-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        registry = AppRegistry(file: root.appendingPathComponent("apps.json"))
        manifests = ManifestStore(directory: root.appendingPathComponent("manifests"))
        templates = TemplateStore(directory: root.appendingPathComponent("templates"))
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private func register(_ agent: AgentIdentity, png: Data? = nil) throws -> AgentIssuer.Report {
        try AgentIssuer.register(agent, iconPNG: png, supportDirectory: root, registry: registry, manifests: manifests, templates: templates)
    }

    private var tinyPNG: Data { Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) + Data(repeating: 7, count: 40) }

    // MARK: Identity

    func testAppIdsAndSlugs() throws {
        XCTAssertEqual(AgentIdentity(kind: .claudeCode)?.appID, "agent.claude-code")
        XCTAssertEqual(AgentIdentity(kind: .codex)?.appID, "agent.codex")
        XCTAssertEqual(AgentIdentity(kind: .claudeDesktop)?.appID, "agent.claude-desktop")
        XCTAssertEqual(AgentIdentity(kind: .generic, genericName: "My Bot v2!")?.appID, "agent.my-bot-v2")
        XCTAssertNil(AgentIdentity(kind: .generic, genericName: "  !! "), "a generic client needs a usable name")
        XCTAssertNil(AgentIdentity(kind: .generic))
        XCTAssertEqual(AgentIdentity.client("claudeCode")?.symbol, "terminal")
        XCTAssertEqual(AgentIdentity.client("codex")?.symbol, "sparkles")
        XCTAssertEqual(AgentIdentity.client("claudeDesktop")?.symbol, "message.circle")
        XCTAssertNil(AgentIdentity.client("vim"))
        XCTAssertEqual(HeraldAgent.appID(from: "claude-code"), "agent.claude-code")
        XCTAssertEqual(HeraldAgent.appID(from: "agent.claude-code"), "agent.claude-code")
        XCTAssertEqual(HeraldAgent.appID(from: "  Agent.My Bot "), "agent.my-bot")
        XCTAssertNil(HeraldAgent.appID(from: "!!!"))
        XCTAssertEqual(AgentIdentity(kind: .codex)?.serverArguments, ["--agent", "codex"])
    }

    func testManifestDeclaresWhatAnAgentSaysAndOffers() throws {
        for kind in AgentIdentity.Kind.allCases {
            let agent = try XCTUnwrap(AgentIdentity(kind: kind, genericName: "Some Client"))
            let m = agent.manifest(icon: "/x.png")
            XCTAssertEqual(m.validationErrors(), [], agent.appID)
            XCTAssertEqual(m.app, agent.appID); XCTAssertEqual(m.appName, agent.name); XCTAssertEqual(m.defaultTemplate, "agent")
            XCTAssertEqual(Set(m.fields.map(\.key)), ["title", "body", "status", "project", "session", "task", "tool", "duration", "link", "needsInput"])
            XCTAssertTrue(m.fields.allSatisfy { $0.sample != nil }, "every field has a sample for previews")
            XCTAssertEqual(m.field("needsInput")?.type, .bool); XCTAssertEqual(m.field("link")?.type, .url)
            XCTAssertEqual(m.field("title")?.required, true)
            XCTAssertEqual((0..<m.actions.count).map { m.actionID(at: $0) }, ["open", "reply", "dismiss"])
            XCTAssertNotNil(m.actions[0].url); XCTAssertNotNil(m.actions[1].callback)
        }
    }

    func testDefaultTemplateIsValidAndBuiltFromCompact() throws {
        for kind in AgentIdentity.Kind.allCases {
            let agent = try XCTUnwrap(AgentIdentity(kind: kind, genericName: "Some Client"))
            let t = agent.template()
            XCTAssertEqual(t.name, "agent"); XCTAssertEqual(t.app, agent.appID); XCTAssertTrue(t.usesGrid)
            let issues = t.validate(manifest: agent.manifest()).filter(\.isError)
            XCTAssertTrue(issues.isEmpty, "\(agent.appID): \(issues.map(\.message))")
            let tokens = Set(t.referencedTokens)
            XCTAssertTrue(tokens.isSubset(of: Set(agent.manifest().fields.map(\.key)).union(["timestamp", "appName", "app", "id"])), "\(tokens)")
            // The compact skeleton is still there, with the status badge carrying the agent's symbol.
            XCTAssertTrue(["icon", "title", "time", "close", "actions"].allSatisfy { id in t.cells.contains { $0.id == id } })
            let badge = try XCTUnwrap(t.cells.first { $0.id == "status" })
            guard case .badge(let b) = badge.component else { return XCTFail("a badge") }
            XCTAssertEqual(b.symbol?.name, agent.symbol); XCTAssertEqual(b.binding, "{status}")
            // No cell overlaps another.
            XCTAssertTrue(t.validate().filter(\.isError).isEmpty)
        }
    }

    // MARK: Registering

    func testInstallRegistersAppManifestTemplateAndIcon() throws {
        let agent = try XCTUnwrap(AgentIdentity(kind: .claudeCode))
        let report = try register(agent, png: tinyPNG)
        XCTAssertTrue(report.manifestWritten); XCTAssertTrue(report.templateCreated); XCTAssertFalse(report.iconMissing)

        let rec = try XCTUnwrap(registry.record(for: "agent.claude-code"))
        XCTAssertEqual(rec.registration.appName, "Claude Code"); XCTAssertEqual(rec.registration.defaults?.sound, "Glass")
        let m = try XCTUnwrap(manifests.get(app: "agent.claude-code"))
        XCTAssertEqual(m.defaultTemplate, "agent"); XCTAssertEqual(m.fields.count, 10)
        XCTAssertNotNil(templates.get(app: "agent.claude-code", name: "agent"))

        // The icon is a copy inside Herald's own folder; nothing points at /Applications.
        let icon = try XCTUnwrap(m.icon)
        XCTAssertTrue(icon.hasPrefix(root.path + "/agent-icons/"), icon)
        XCTAssertEqual(rec.registration.icon, icon)
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: icon)), tinyPNG)
    }

    func testNoIconIsReportedNotHidden() throws {
        let report = try register(try XCTUnwrap(AgentIdentity(kind: .codex)), png: nil)
        XCTAssertTrue(report.iconMissing); XCTAssertNil(report.iconPath)
        XCTAssertNil(registry.record(for: "agent.codex")?.registration.icon, "no generated glyph is put in its place")
        XCTAssertNil(manifests.get(app: "agent.codex")?.icon)
        // A later install that finds one fills it in.
        let again = try register(try XCTUnwrap(AgentIdentity(kind: .codex)), png: tinyPNG)
        XCTAssertFalse(again.iconMissing)
        XCTAssertEqual(manifests.get(app: "agent.codex")?.icon, again.iconPath)
    }

    func testReinstallIsIdempotentAndKeepsTheUsersEdits() throws {
        let agent = try XCTUnwrap(AgentIdentity(kind: .claudeCode))
        _ = try register(agent, png: tinyPNG)

        // The user designs their own banner, changes the sound and name, and picks another default template.
        var mine = try XCTUnwrap(templates.get(app: agent.appID, name: "agent"))
        mine.cells.removeAll { $0.id == "project" }
        mine.accentColor = "#FF8800"
        XCTAssertTrue(templates.put(mine))
        registry.update(agent.appID) { $0.registration.defaults?.sound = "Funk"; $0.registration.appName = "My Claude" }
        var m = try XCTUnwrap(manifests.get(app: agent.appID))
        m.defaultTemplate = "my-look"
        XCTAssertTrue(manifests.put(m))

        let report = try register(agent, png: tinyPNG)
        XCTAssertFalse(report.templateCreated, "an existing template is never overwritten")
        XCTAssertEqual(templates.get(app: agent.appID, name: "agent"), mine)
        let rec = try XCTUnwrap(registry.record(for: agent.appID))
        XCTAssertEqual(rec.registration.defaults?.sound, "Funk"); XCTAssertEqual(rec.registration.appName, "My Claude")
        XCTAssertEqual(manifests.get(app: agent.appID)?.defaultTemplate, "my-look")
        XCTAssertEqual(manifests.get(app: agent.appID)?.fields.count, 10, "the manifest is the current one")

        // Nothing changed on a second identical run, and a manifest that lost a field gets it back.
        XCTAssertFalse(try register(agent, png: tinyPNG).manifestWritten, "a rerun writes nothing new")
        m = try XCTUnwrap(manifests.get(app: agent.appID))
        m.fields.removeAll { $0.key == "tool" }
        XCTAssertTrue(manifests.put(m))
        XCTAssertTrue(try register(agent, png: tinyPNG).manifestWritten)
        XCTAssertNotNil(manifests.get(app: agent.appID)?.field("tool"))
        XCTAssertEqual(manifests.get(app: agent.appID)?.defaultTemplate, "my-look")
    }

    func testAUsersOwnIconSurvivesReinstall() throws {
        let agent = try XCTUnwrap(AgentIdentity(kind: .generic, genericName: "Bot"))
        _ = try register(agent, png: nil)
        let mine = root.appendingPathComponent("mine.png")
        try tinyPNG.write(to: mine)
        registry.update(agent.appID) { $0.registration.icon = mine.path }
        let report = try register(agent, png: Data(repeating: 1, count: 20))
        XCTAssertEqual(report.iconPath, mine.path)
        XCTAssertEqual(registry.record(for: agent.appID)?.registration.icon, mine.path)
    }

    // MARK: Server configuration

    func testInstallWritesTheAgentIntoEachClientsConfiguration() throws {
        var calls: [[String]] = []
        let inst = MCPInstaller(serverPath: "/App/herald-mcp", codexConfig: root.appendingPathComponent(".codex/config.toml"),
                                desktopConfig: root.appendingPathComponent("Claude/claude_desktop_config.json"), claudeCandidates: ["/bin/sh"],
                                run: { _, args in calls.append(args); return (0, "") })
        XCTAssertTrue(inst.installClaudeCode(agent: "claude-code").ok)
        XCTAssertEqual(calls.last, ["mcp", "add", "--scope", "user", "herald", "--", "/App/herald-mcp", "--agent", "claude-code"])
        XCTAssertTrue(inst.installCodex(agent: "codex").ok)
        let toml = try String(contentsOf: root.appendingPathComponent(".codex/config.toml"))
        XCTAssertTrue(toml.contains("args = [\"--agent\", \"codex\"]"), toml)
        XCTAssertTrue(inst.installClaudeDesktop(agent: "claude-desktop").ok)
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("Claude/claude_desktop_config.json"))) as! [String: Any]
        let herald = (json["mcpServers"] as! [String: Any])["herald"] as! [String: Any]
        XCTAssertEqual(herald["args"] as? [String], ["--agent", "claude-desktop"])
        XCTAssertTrue(inst.genericJSON(agent: "my-bot").contains("\"--agent\""))
        XCTAssertTrue(inst.genericCommandLine(agent: "my-bot").hasSuffix("/App/herald-mcp --agent my-bot"))
        // Without an agent nothing changes.
        XCTAssertEqual(inst.genericCommandLine, "claude mcp add --scope user herald -- /App/herald-mcp")
        XCTAssertTrue(MCPInstaller.codexMerge("", command: "/p").contains("args = []"))
    }

    func testReinstallingTheConfigurationDoesNotDuplicateIt() throws {
        let inst = MCPInstaller(serverPath: "/App/herald-mcp", codexConfig: root.appendingPathComponent("c.toml"),
                                desktopConfig: root.appendingPathComponent("d.json"), claudeCandidates: [], run: { _, _ in (0, "") })
        XCTAssertTrue(inst.installCodex(agent: "codex").ok)
        XCTAssertTrue(inst.installCodex(agent: "codex").ok)
        let toml = try String(contentsOf: root.appendingPathComponent("c.toml"))
        XCTAssertEqual(toml.components(separatedBy: "[mcp_servers.herald]").count, 2)
    }

    // MARK: Icons

    /// A real `.icns` made with sips from a generated PNG, inside a fixture application bundle.
    private func fixtureApp(named name: String, in folder: URL, iconFile: String = "app.icns") throws -> URL {
        let fm = FileManager.default
        let app = folder.appendingPathComponent(name)
        let res = app.appendingPathComponent("Contents/Resources")
        try fm.createDirectory(at: res, withIntermediateDirectories: true)
        let png = folder.appendingPathComponent("src-\(UUID().uuidString).png")
        try makePNG(side: 128).write(to: png)
        let icns = res.appendingPathComponent(iconFile)
        XCTAssertEqual(IconExtractor.runProcess("/usr/bin/sips", ["-s", "format", "icns", png.path, "--out", icns.path]), 0, "sips builds the fixture")
        let info: [String: Any] = ["CFBundleIconFile": (iconFile as NSString).deletingPathExtension, "CFBundleName": name]
        try (info as NSDictionary).write(to: app.appendingPathComponent("Contents/Info.plist"))
        try? fm.removeItem(at: png)
        return app
    }

    private func makePNG(side: Int) throws -> Data {
        let ctx = try XCTUnwrap(CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                                          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.setFillColor(CGColor(red: 0.8, green: 0.3, blue: 0.2, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: side, height: side))
        let image = try XCTUnwrap(ctx.makeImage())
        let data = NSMutableData()
        let dest = try XCTUnwrap(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(dest, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(dest))
        return data as Data
    }

    private func pixelSize(_ png: Data) -> (Int, Int)? {
        guard let src = CGImageSourceCreateWithData(png as CFData, nil), let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
        return (img.width, img.height)
    }

    func testExtractorConvertsAnIcnsFromABundleToPNG() throws {
        let apps = root.appendingPathComponent("Applications")
        let app = try fixtureApp(named: "Claude.app", in: apps)
        XCTAssertEqual(IconExtractor.icnsURL(inBundle: app)?.lastPathComponent, "app.icns", "Info.plist names the file")
        let png = try XCTUnwrap(IconExtractor.png(fromBundle: app))
        XCTAssertEqual(png.prefix(4), Data([0x89, 0x50, 0x4E, 0x47]))
        let size = try XCTUnwrap(pixelSize(png))
        XCTAssertLessThanOrEqual(max(size.0, size.1), 512)
        XCTAssertGreaterThan(size.0, 0)
        XCTAssertNil(IconExtractor.png(fromBundle: root.appendingPathComponent("Nothing.app")))
        // Without CFBundleIconFile the largest .icns in Resources is used.
        let bare = try fixtureApp(named: "Bare.app", in: apps, iconFile: "whatever.icns")
        try FileManager.default.removeItem(at: bare.appendingPathComponent("Contents/Info.plist"))
        XCTAssertEqual(IconExtractor.icnsURL(inBundle: bare)?.lastPathComponent, "whatever.icns")
    }

    func testIconSourcesFindTheProductThenThePackage() throws {
        let apps = root.appendingPathComponent("Applications")
        _ = try fixtureApp(named: "Claude.app", in: apps)
        let roots = AgentIconSources.Roots(applications: [apps], npmRoots: [root.appendingPathComponent("npm")], claudeData: [])
        let claude = try XCTUnwrap(AgentIconSources.png(for: .claudeCode, roots: roots))
        XCTAssertEqual(claude.source.lastPathComponent, "Claude.app")
        XCTAssertNotNil(AgentIconSources.png(for: .claudeDesktop, roots: roots), "Claude Desktop shares Claude.app's icon")
        XCTAssertNil(AgentIconSources.png(for: .codex, roots: roots), "Codex has neither an app nor a package here")
        XCTAssertNil(AgentIconSources.png(for: .generic, roots: roots))

        // The package fallback: an icon file inside @openai/codex.
        let pkg = root.appendingPathComponent("npm/@openai/codex/assets")
        try FileManager.default.createDirectory(at: pkg, withIntermediateDirectories: true)
        try makePNG(side: 64).write(to: pkg.appendingPathComponent("codex-icon.png"))
        try Data(repeating: 0, count: 10).write(to: pkg.appendingPathComponent("readme.txt"))
        let codex = try XCTUnwrap(AgentIconSources.png(for: .codex, roots: roots))
        XCTAssertEqual(codex.source.lastPathComponent, "codex-icon.png")
    }

    func testTheManifestIconPointsIntoTheSupportFolder() throws {
        let apps = root.appendingPathComponent("Applications")
        _ = try fixtureApp(named: "Claude.app", in: apps)
        let found = try XCTUnwrap(AgentIconSources.png(for: .claudeCode, roots: .init(applications: [apps], npmRoots: [], claudeData: [])))
        let agent = try XCTUnwrap(AgentIdentity(kind: .claudeCode))
        let report = try register(agent, png: found.data)
        let icon = try XCTUnwrap(manifests.get(app: agent.appID)?.icon)
        XCTAssertTrue(icon.hasPrefix(AgentIssuer.iconsFolder(in: root).path))
        XCTAssertFalse(icon.contains("Applications"), "the copy is Herald's, not a link into the app")
        XCTAssertEqual(icon, report.iconPath)
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: icon)).prefix(4), Data([0x89, 0x50, 0x4E, 0x47]))
    }

    // MARK: herald-mcp

    func testConfigTakesTheAgentFromTheFlagOrTheEnvironment() throws {
        let home = root!
        var c = try MCPConfig.parse(arguments: ["--agent", "claude-code"], environment: [:], defaultSupportDirectory: home)
        XCTAssertEqual(c.agentApp, "agent.claude-code")
        c = try MCPConfig.parse(arguments: [], environment: ["HERALD_AGENT": "Codex"], defaultSupportDirectory: home)
        XCTAssertEqual(c.agentApp, "agent.codex")
        c = try MCPConfig.parse(arguments: ["--agent", "agent.my-bot"], environment: ["HERALD_AGENT": "codex"], defaultSupportDirectory: home)
        XCTAssertEqual(c.agentApp, "agent.my-bot", "the flag wins")
        XCTAssertNil(try MCPConfig.parse(arguments: [], environment: [:], defaultSupportDirectory: home).agentApp)
        XCTAssertThrowsError(try MCPConfig.parse(arguments: ["--agent", "!!"], environment: [:], defaultSupportDirectory: home))
        XCTAssertThrowsError(try MCPConfig.parse(arguments: ["--agent"], environment: [:], defaultSupportDirectory: home))
    }

    func testToolsDefaultTheAppAndAnExplicitAppStillWins() async throws {
        let rec = try ParityToolTests.Recorder()
        defer { rec.stop() }
        let tools = MCPTools(client: HeraldClient(supportDirectory: rec.directory), previewDirectory: rec.directory, defaultApp: "agent.claude-code")

        _ = try await tools.call("send_notification", arguments: .object(["title": .string("Done"), "status": .string("done")]))
        let sent = try XCTUnwrap(rec.calls.last)
        XCTAssertEqual(sent.path, "/v1/notify")
        XCTAssertEqual(sent.body?["app"]?.stringValue, "agent.claude-code")
        XCTAssertEqual(sent.body?["status"]?.stringValue, "done", "agent fields go through untouched")

        _ = try await tools.call("send_notification", arguments: .object(["app": .string("other"), "title": .string("x")]))
        XCTAssertEqual(rec.calls.last?.body?["app"]?.stringValue, "other")

        _ = try await tools.call("dismiss", arguments: .object(["all": .bool(true)]))
        XCTAssertEqual(rec.calls.last?.body?["app"]?.stringValue, "agent.claude-code")
        _ = try await tools.call("list_stacks", arguments: .object([:]))
        XCTAssertEqual(rec.calls.last?.query["app"], "agent.claude-code")
        _ = try await tools.call("list_history", arguments: nil)
        XCTAssertEqual(rec.calls.last?.query["app"], "agent.claude-code")
        _ = try await tools.call("speak", arguments: .object(["text": .string("hello")]))
        XCTAssertEqual(rec.calls.last?.body?["app"]?.stringValue, "agent.claude-code")

        // A tool outside the list keeps its own meaning: no app means all apps.
        let before = rec.calls.count
        _ = try await tools.call("list_apps", arguments: .object([:]))
        XCTAssertNil(rec.calls[before].query["app"])
    }

    func testWithoutAnAgentAppStaysRequired() async throws {
        let rec = try ParityToolTests.Recorder()
        defer { rec.stop() }
        let tools = MCPTools(client: HeraldClient(supportDirectory: rec.directory), previewDirectory: rec.directory)
        let r = try await tools.call("send_notification", arguments: .object(["title": .string("x")]))
        XCTAssertTrue(r.isError)
        XCTAssertTrue(rec.calls.isEmpty)
        let plain = MCPToolCatalog.byName["send_notification"]!
        XCTAssertTrue(plain.inputSchema["required"]?.arrayValue?.contains(.string("app")) ?? false)
    }

    func testToolsListMakesAppOptionalForAnAgent() throws {
        let d = MCPTools.withDefaultApp(try XCTUnwrap(MCPToolCatalog.byName["send_notification"]), "agent.codex")
        XCTAssertFalse(d.inputSchema["required"]?.arrayValue?.contains(.string("app")) ?? true)
        XCTAssertTrue(d.description.contains("agent.codex"))
        XCTAssertNotNil(d.inputSchema["properties"]?["app"], "app is still accepted")
        let untouched = MCPTools.withDefaultApp(try XCTUnwrap(MCPToolCatalog.byName["get_manifest"]), "agent.codex")
        XCTAssertEqual(untouched.description, MCPToolCatalog.byName["get_manifest"]?.description)
        for name in MCPTools.appDefaulting { XCTAssertNotNil(MCPToolCatalog.byName[name], name) }
    }
}
