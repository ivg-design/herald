import XCTest
import AppKit
@testable import HeraldCore
@testable import HeraldClient

/// Connector names, automatic and custom icons, and the one place the lists read from (issues #85, #86).
final class AppIdentityTests: XCTestCase {
    private var root: URL!
    private var registry: AppRegistry!
    private var manifests: ManifestStore!
    private var templates: TemplateStore!
    private let fullName = "Herald Relay \u{2014} dot cloud computer"
    private let slugKey = "herald-relay-dot-cloud-c"
    private var noProducts: AgentIconSources.Roots { .init(applications: [root.appendingPathComponent("none")], npmRoots: [], claudeData: []) }

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("herald-identity-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        registry = AppRegistry(file: root.appendingPathComponent("apps.json"))
        manifests = ManifestStore(directory: root.appendingPathComponent("manifests"))
        templates = TemplateStore(directory: root.appendingPathComponent("templates"))
    }
    override func tearDown() { try? FileManager.default.removeItem(at: root) }

    private func key(_ name: String, kind: String?, display: String?, client: String = "other") -> RelayKeyInfo {
        RelayKeyInfo(id: "k-" + name, name: name, client: client, scope: "notify", kind: kind, displayName: display)
    }

    // MARK: Names (#85)

    func testAConnectorAppIsNamedWithTheClientsNameAndKeepsTheSlugInItsId() throws {
        let agent = try XCTUnwrap(AgentIdentity(cloudKeyName: slugKey, client: "other", clientName: fullName))
        XCTAssertEqual(agent.appID, "cloud." + slugKey)
        XCTAssertEqual(agent.name, fullName)
        try AgentIssuer.register(agent, iconPNG: nil, supportDirectory: root, registry: registry, manifests: manifests, templates: templates)
        XCTAssertEqual(registry.record(for: "cloud." + slugKey)?.registration.appName, fullName)
        XCTAssertEqual(registry.displayName(for: "cloud." + slugKey), fullName)
        XCTAssertEqual(manifests.get(app: "cloud." + slugKey)?.appName, fullName)
    }

    func testARegistrationWithTheTruncatedSlugNameIsOverwrittenByTheClientsName() throws {
        registry.register(HeraldAppRegistration(app: "cloud." + slugKey, appName: slugKey))
        let agent = try XCTUnwrap(AgentIdentity(cloudKeyName: slugKey, client: "other", clientName: fullName))
        try AgentIssuer.register(agent, iconPNG: nil, supportDirectory: root, registry: registry, manifests: manifests, templates: templates)
        XCTAssertEqual(registry.displayName(for: "cloud." + slugKey), fullName)
        // a static key (no client name) keeps a name it already has
        let staticKey = try XCTUnwrap(AgentIdentity(cloudKeyName: "build-bot", client: "other"))
        registry.register(HeraldAppRegistration(app: staticKey.appID, appName: "My renamed bot"))
        try AgentIssuer.register(staticKey, iconPNG: nil, supportDirectory: root, registry: registry, manifests: manifests, templates: templates)
        XCTAssertEqual(registry.displayName(for: staticKey.appID), "My renamed bot")
    }

    func testStartupRenamesExistingConnectorAppsFromTheRelaysDisplayName() throws {
        registry.register(HeraldAppRegistration(app: "cloud." + slugKey, appName: slugKey))
        registry.register(HeraldAppRegistration(app: "cloud.build-bot", appName: "build-bot"))
        registry.register(HeraldAppRegistration(app: "cloud.never-sent", appName: nil))
        let keys = [key(slugKey, kind: "oauth", display: fullName), key("build-bot", kind: "static", display: nil),
                    key("not-yet", kind: "oauth", display: "Later")]
        let renamed = CloudApps.reconcile(keys: keys, registry: registry, manifests: manifests, supportDirectory: root, roots: noProducts)
        XCTAssertEqual(renamed, ["cloud." + slugKey])
        XCTAssertEqual(registry.displayName(for: "cloud." + slugKey), fullName)
        XCTAssertEqual(registry.displayName(for: "cloud.build-bot"), "build-bot")
        XCTAssertNil(registry.record(for: "cloud.not-yet"))
        XCTAssertTrue(CloudApps.reconcile(keys: keys, registry: registry, supportDirectory: root, roots: noProducts).isEmpty, "idempotent")
    }

    func testTheAppsListSortsByDisplayNameIgnoringCase() {
        for (id, name) in [("a1", "zeta"), ("a2", "Alpha"), ("a3", "beta"), ("a4", "Beta")] {
            registry.register(HeraldAppRegistration(app: id, appName: name))
        }
        XCTAssertEqual(registry.all().map(\.displayName), ["Alpha", "beta", "Beta", "zeta"])
    }

    // MARK: Icons (#86)

    func testClientsAreRecognisedByTheirNames() {
        XCTAssertEqual(AutoIcon.flavor(["ChatGPT", nil]), .chatgpt)
        XCTAssertEqual(AutoIcon.flavor(["My app", "openai-mcp-client"]), .chatgpt)
        XCTAssertEqual(AutoIcon.flavor(["Claude Desktop"]), .claude)
        XCTAssertEqual(AutoIcon.flavor([nil, "claude"]), .claude)
        XCTAssertEqual(AutoIcon.flavor(["OpenAI Codex CLI"]), .codex)
        XCTAssertEqual(AutoIcon.flavor([fullName, slugKey, "other"]), .other)
    }

    func testTheOpenAIIconIsUsedOnlyWhenChatGPTIsInstalled() throws {
        let apps = root.appendingPathComponent("Applications")
        let marker = Data("chatgpt-icon".utf8)
        let roots = AgentIconSources.Roots(applications: [apps], npmRoots: [], claudeData: [])
        XCTAssertNil(AutoIcon.productPNG(.chatgpt, roots: roots, finder: { _ in marker }))
        try FileManager.default.createDirectory(at: apps.appendingPathComponent("ChatGPT.app"), withIntermediateDirectories: true)
        XCTAssertEqual(AutoIcon.productPNG(.chatgpt, roots: roots, finder: { _ in marker }), marker)
        XCTAssertNil(AutoIcon.productPNG(.other, roots: roots, finder: { _ in marker }))
    }

    func testIconlessCloudAndAgentAppsGetATileNeverALetter() throws {
        registry.register(HeraldAppRegistration(app: "cloud." + slugKey, appName: fullName))
        registry.register(HeraldAppRegistration(app: "cloud.build-bot", appName: "build-bot"))
        registry.register(HeraldAppRegistration(app: "agent.my-bot", appName: "My Bot"))
        registry.register(HeraldAppRegistration(app: "plain", appName: "Plain"))
        let own = root.appendingPathComponent("own.png"); try IconArt.symbolTilePNG(symbol: "star")!.write(to: own)
        registry.register(HeraldAppRegistration(app: "cloud.has-icon", icon: own.path))
        let keys = [key(slugKey, kind: "oauth", display: fullName), key("build-bot", kind: "static", display: nil)]
        let changed = AutoIcon.applyToIconless(registry: registry, supportDirectory: root, keys: keys, roots: noProducts)
        XCTAssertEqual(Set(changed), ["cloud." + slugKey, "cloud.build-bot", "agent.my-bot"])
        func png(_ app: String) throws -> Data { try Data(contentsOf: URL(fileURLWithPath: XCTUnwrap(registry.record(for: app)?.registration.icon))) }
        for app in changed { XCTAssertTrue(IconArt.isUsableAppIcon(try png(app)), app) }
        XCTAssertEqual(try png("cloud." + slugKey), IconArt.symbolTilePNG(symbol: "cloud"))
        XCTAssertEqual(try png("cloud.build-bot"), IconArt.symbolTilePNG(symbol: "key"))
        XCTAssertEqual(try png("agent.my-bot"), IconArt.symbolTilePNG(symbol: "terminal"))
        XCTAssertNil(registry.record(for: "plain")?.registration.icon)
        XCTAssertEqual(registry.record(for: "cloud.has-icon")?.registration.icon, own.path)
        XCTAssertTrue(AutoIcon.applyToIconless(registry: registry, supportDirectory: root, keys: keys, roots: noProducts).isEmpty, "idempotent")
    }

    func testAUserIconWinsAndRemoveGoesBackToTheAutomaticOne() throws {
        registry.register(HeraldAppRegistration(app: "cloud.x", appName: "X"))
        AutoIcon.applyToIconless(registry: registry, supportDirectory: root, roots: noProducts)
        let automatic = try XCTUnwrap(registry.iconSource(for: "cloud.x"))
        let picked = root.appendingPathComponent("picked.png"); try IconArt.symbolTilePNG(symbol: "star")!.write(to: picked)
        let stored = try CustomIcon.set(app: "cloud.x", from: picked, supportDirectory: root, registry: registry)
        XCTAssertTrue(stored.path.hasPrefix(root.path + "/app-icons/"))
        XCTAssertEqual(registry.iconSource(for: "cloud.x"), stored.path)
        try FileManager.default.removeItem(at: picked)                     // the source may go: the copy stays
        XCTAssertTrue(FileManager.default.fileExists(atPath: stored.path))
        // a re-registration or the startup pass keeps the user's choice
        AutoIcon.applyToIconless(registry: registry, supportDirectory: root, roots: noProducts)
        XCTAssertEqual(registry.iconSource(for: "cloud.x"), stored.path)
        CustomIcon.remove(app: "cloud.x", supportDirectory: root, registry: registry)
        XCTAssertEqual(registry.iconSource(for: "cloud.x"), automatic)
        XCTAssertFalse(FileManager.default.fileExists(atPath: stored.path))
        let bad = root.appendingPathComponent("bad.png"); try Data("nope".utf8).write(to: bad)
        XCTAssertThrowsError(try CustomIcon.set(app: "cloud.x", from: bad, supportDirectory: root, registry: registry))
        XCTAssertThrowsError(try CustomIcon.set(app: "missing", from: bad, supportDirectory: root, registry: registry))
    }

    func testRemovingAnAppRemovesItsAutomaticAndCustomIcons() throws {
        registry.register(HeraldAppRegistration(app: "cloud.y", appName: "Y"))
        AutoIcon.applyToIconless(registry: registry, supportDirectory: root, roots: noProducts)
        let picked = root.appendingPathComponent("p.png"); try IconArt.symbolTilePNG(symbol: "star")!.write(to: picked)
        let custom = try CustomIcon.set(app: "cloud.y", from: picked, supportDirectory: root, registry: registry)
        let auto = AutoIcon.file(for: "cloud.y", in: root)
        XCTAssertTrue(FileManager.default.fileExists(atPath: auto.path))
        let record = registry.record(for: "cloud.y")
        XCTAssertEqual(AppLifecycle.removeIcons(of: "cloud.y", record: record, supportDirectory: root, registry: registry) >= 2, true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: custom.path)); XCTAssertFalse(FileManager.default.fileExists(atPath: auto.path))
    }

    func testRecordsWithoutACustomIconStillDecode() throws {
        let old = #"{"registration":{"app":"a"}}"#.data(using: .utf8)!
        let r = try HeraldJSON.decoder().decode(AppRecord.self, from: old)
        XCTAssertNil(r.customIcon)
    }
}
