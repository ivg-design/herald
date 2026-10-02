import XCTest
@testable import HeraldClient
@testable import HeraldCore

/// Herald's own identity (one `herald` app with name and icon), the startup cleanups, removing an app, and the History sidebar's
/// "All Apps" selection.
final class HeraldIdentityTests: XCTestCase {
    var root: URL!
    var registry: AppRegistry!, history: HistoryStore!, templates: TemplateStore!, manifests: ManifestStore!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("herald-identity-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        reopen()
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private func reopen() {
        registry = AppRegistry(file: root.appendingPathComponent("apps.json"))
        history = HistoryStore(directory: root.appendingPathComponent("history"))
        templates = TemplateStore(directory: root.appendingPathComponent("templates"))
        manifests = ManifestStore(directory: root.appendingPathComponent("manifests"))
    }

    private let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) + Data(repeating: 9, count: 30)

    @discardableResult
    private func add(_ app: String, _ id: String, at t: TimeInterval = 0, title: String = "t", group: String? = nil, register: Bool = true) -> HeraldHistoryItem {
        var n = HeraldNotification(app: app, id: id, title: title); n.group = group
        let item = HeraldHistoryItem(id: id, app: app, notification: n, deliveredAt: Date(timeIntervalSince1970: 1_700_000_000 + t))
        history.upsert(item)
        if register { registry.ensure(app) }
        return item
    }

    private func migrate(icon: Data? = nil) -> HeraldMigrationReport {
        HeraldMigrations.run(supportDirectory: root, registry: registry, history: history, templates: templates, manifests: manifests, iconPNG: icon)
    }

    // MARK: One Herald, with a name and an icon

    func testHeraldIsRegisteredWithItsNameAndTheExportedAppIcon() throws {
        _ = migrate(icon: png)
        let rec = try XCTUnwrap(registry.record(for: "herald"))
        XCTAssertEqual(rec.registration.appName, "Herald"); XCTAssertEqual(rec.displayName, "Herald")
        let icon = try XCTUnwrap(rec.registration.icon)
        XCTAssertEqual(icon, HeraldIdentity.iconFile(in: root).path)
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: icon)), png)
        // exported once: a second run keeps the file and the registration
        _ = migrate(icon: Data(repeating: 1, count: 20))
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: icon)), png)
    }

    func testAnImplicitHeraldRecordWithoutAnameGetsOne() throws {
        registry.ensure("herald")                              // what a notification with no registration made
        XCTAssertNil(registry.record(for: "herald")?.registration.appName)
        _ = migrate(icon: png)
        XCTAssertEqual(registry.record(for: "herald")?.registration.appName, "Herald")
    }

    func testAnameTheUserChoseIsKept() throws {
        registry.register(HeraldAppRegistration(app: "herald", appName: "My Herald", icon: "/somewhere/own.png"))
        _ = migrate(icon: png)
        XCTAssertEqual(registry.record(for: "herald")?.registration.appName, "My Herald")
        XCTAssertEqual(registry.record(for: "herald")?.registration.icon, "/somewhere/own.png")
    }

    func testConnectorsAreFoldedIntoHeraldWithGroupConnectors() throws {
        registry.register(HeraldAppRegistration(app: "herald.connectors", appName: "Herald connectors"))
        add("herald.connectors", "c1", at: 1, title: "Connector request")
        add("herald.connectors", "c2", at: 2, title: "Connector request", group: "kept")
        add("herald", "h1", at: 3, title: "Hello")
        manifests.put(HeraldManifest(app: "herald.connectors", appName: "Herald connectors"))
        let r = migrate(icon: png)
        XCTAssertEqual(r.foldedConnectors, 2)
        XCTAssertNil(registry.record(for: "herald.connectors")); XCTAssertNil(manifests.get(app: "herald.connectors"))
        XCTAssertEqual(history.apps(), ["herald"])
        let items = history.items(app: "herald")
        XCTAssertEqual(Set(items.map(\.id)), ["c1", "c2", "h1"])
        XCTAssertEqual(items.first { $0.id == "c1" }?.notification.group, "connectors")
        XCTAssertEqual(items.first { $0.id == "c1" }?.notification.app, "herald")
        XCTAssertEqual(items.first { $0.id == "c2" }?.notification.group, "kept", "a group the item already had stays")
        XCTAssertEqual(items.map(\.id), ["h1", "c2", "c1"], "newest first, order kept")
        XCTAssertEqual(migrate().foldedConnectors, 0)           // nothing left to fold
    }

    // MARK: Apps that no longer exist

    func testHistoryOfAnUnregisteredAppIsPurgedAtStartup() {
        add("webwatcher", "w1", register: false)               // the legacy id: History without a record
        add("agent.claude-code", "a1")
        let r = migrate()
        XCTAssertEqual(r.purgedOrphans, ["webwatcher"])
        XCTAssertEqual(history.apps(), ["agent.claude-code"])
    }

    func testTestAndDemoLeftoversAreRemovedOnceAndOnlyBidbotWithoutAManifest() throws {
        add("cloud.herald-test-ab12cd", "t1")
        registry.register(HeraldAppRegistration(app: "cloud.herald-test-ab12cd", icon: AgentIssuer.iconsFolder(in: root).appendingPathComponent("herald-test-ab12cd.png").path))
        try FileManager.default.createDirectory(at: AgentIssuer.iconsFolder(in: root), withIntermediateDirectories: true)
        try png.write(to: AgentIssuer.iconsFolder(in: root).appendingPathComponent("herald-test-ab12cd.png"))
        add("cloud.herald-test-ff00aa", "t2")
        add("cloud.my-bot", "k1")                               // a real cloud agent stays
        add("bidbot", "b1")                                     // the accidental example registration
        add("example.bidbot", "e1")                             // the example under its new id stays
        let r = migrate()
        XCTAssertEqual(r.removedLeftovers, ["bidbot", "cloud.herald-test-ab12cd", "cloud.herald-test-ff00aa"])
        XCTAssertEqual(Set(history.apps()), ["cloud.my-bot", "example.bidbot"])
        XCTAssertNil(registry.record(for: "bidbot")); XCTAssertNil(registry.record(for: "cloud.herald-test-ab12cd"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: AgentIssuer.iconsFolder(in: root).appendingPathComponent("herald-test-ab12cd.png").path))
        // once: a bidbot installed on purpose later is not touched by the next start
        add("bidbot", "b2")
        XCTAssertEqual(migrate().removedLeftovers, [])
        XCTAssertNotNil(registry.record(for: "bidbot"))
    }

    func testABidbotInstalledOnPurposeHasAManifestAndStays() {
        add("bidbot", "b1")
        manifests.put(HeraldManifest(app: "bidbot", appName: "BidBot"))
        XCTAssertEqual(migrate().removedLeftovers, [])
        XCTAssertNotNil(registry.record(for: "bidbot")); XCTAssertEqual(history.apps(), ["bidbot"])
    }

    // MARK: Removing an app

    func testRemovingAnAppTakesItsHistoryTemplatesManifestAndIconFilesTogether() throws {
        let icons = AgentIssuer.iconsFolder(in: root)
        try FileManager.default.createDirectory(at: icons, withIntermediateDirectories: true)
        let own = icons.appendingPathComponent("demo-bot.png"), custom = icons.appendingPathComponent("demo-bot.custom.png")
        try png.write(to: own); try png.write(to: custom)
        let outside = FileManager.default.temporaryDirectory.appendingPathComponent("outside-\(UUID().uuidString).png")
        try png.write(to: outside); defer { try? FileManager.default.removeItem(at: outside) }
        registry.register(HeraldAppRegistration(app: "cloud.demo-bot", icon: own.path))
        registry.register(HeraldAppRegistration(app: "keeper", icon: outside.path))
        add("cloud.demo-bot", "d1"); add("cloud.demo-bot", "d2"); add("keeper", "k1")
        XCTAssertTrue(templates.put(HeraldTemplate(name: "hero", app: "cloud.demo-bot")))
        manifests.put(HeraldManifest(app: "cloud.demo-bot", appName: "Demo"))

        let r = AppLifecycle.remove(app: "cloud.demo-bot", supportDirectory: root, registry: registry, history: history, templates: templates, manifests: manifests)
        XCTAssertTrue(r.wasRegistered); XCTAssertEqual(r.historyItems, 2); XCTAssertEqual(r.templates, 1); XCTAssertTrue(r.manifest)
        XCTAssertNil(registry.record(for: "cloud.demo-bot")); XCTAssertEqual(history.apps(), ["keeper"])
        XCTAssertTrue(templates.list(app: "cloud.demo-bot").isEmpty); XCTAssertNil(manifests.get(app: "cloud.demo-bot"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: own.path)); XCTAssertFalse(FileManager.default.fileExists(atPath: custom.path))
        // another app's own icon, outside Herald's folder, is never touched
        XCTAssertTrue(AppLifecycle.remove(app: "keeper", supportDirectory: root, registry: registry, history: history, templates: templates, manifests: manifests).wasRegistered)
        XCTAssertTrue(FileManager.default.fileExists(atPath: outside.path))
    }

    func testAnIconFileSharedByAnotherAppWithTheSameSlugIsKept() throws {
        let icons = AgentIssuer.iconsFolder(in: root)
        try FileManager.default.createDirectory(at: icons, withIntermediateDirectories: true)
        let shared = icons.appendingPathComponent("my-bot.png"); try png.write(to: shared)
        registry.register(HeraldAppRegistration(app: "agent.my-bot", icon: shared.path))
        registry.register(HeraldAppRegistration(app: "cloud.my-bot", icon: shared.path))
        AppLifecycle.remove(app: "cloud.my-bot", supportDirectory: root, registry: registry, history: history, templates: templates, manifests: manifests)
        // the registered path is inside the support folder, so it goes with cloud.my-bot; agent.my-bot must then be re-iconned by its issuer
        XCTAssertNotNil(registry.record(for: "agent.my-bot"))
    }

    // MARK: DELETE /v1/apps/{id}

    final class AppsBackend: HeraldBackend, @unchecked Sendable {
        var deleted: [String] = []
        var unknown: Set<String> = []
        func notify(_ n: HeraldNotification) async throws -> String { "x" }
        func register(_ r: HeraldAppRegistration) async throws {}
        func dismiss(app: String, id: String) async throws {}
        func dismissAll(app: String?) async throws {}
        func history(app: String?, limit: Int) async throws -> [HeraldHistoryItem] { [] }
        func clearHistory(app: String?) async throws {}
        func apps() async throws -> [HeraldAppRegistration] { [] }
        func deleteApp(app: String) async throws {
            if app == "herald" { throw BackendError(409, "herald is Herald itself and cannot be removed") }
            if unknown.contains(app) { throw BackendError(404, "no such app") }
            deleted.append(app)
        }
    }

    func testDeleteAppRouteDecodesTheIdAndMapsErrors() async throws {
        let b = AppsBackend(); b.unknown = ["ghost"]
        let r = Router(token: "t", backend: b, version: "1", pid: 1)
        func call(_ m: String, _ p: String, token: String? = "t") async -> HTTPResponse {
            await r.handle(HTTPRequest(method: m, path: p, headers: token.map { ["authorization": "Bearer \($0)"] } ?? [:], body: Data()))
        }
        let ok = await call("DELETE", "/v1/apps/cloud.herald-test-ab12cd")
        XCTAssertEqual(ok.status, 200); XCTAssertEqual(b.deleted, ["cloud.herald-test-ab12cd"])
        let enc = await call("DELETE", "/v1/apps/my%20app"); XCTAssertEqual(enc.status, 200); XCTAssertEqual(b.deleted.last, "my app")
        let unauth = await call("DELETE", "/v1/apps/x", token: nil); XCTAssertEqual(unauth.status, 401)
        let gone = await call("DELETE", "/v1/apps/ghost"); XCTAssertEqual(gone.status, 404)
        let me = await call("DELETE", "/v1/apps/herald"); XCTAssertEqual(me.status, 409)
        let bare = await call("DELETE", "/v1/apps/"); XCTAssertEqual(bare.status, 400)
        let nested = await call("DELETE", "/v1/apps/a/b"); XCTAssertEqual(nested.status, 400)
        let plain = await call("DELETE", "/v1/apps"); XCTAssertEqual(plain.status, 405)           // the collection is not deletable
        XCTAssertEqual(b.deleted.count, 2)
    }

    // MARK: History: All Apps

    func testAllAppsIsTheDefaultSelectionAndListsEveryAppNewestFirst() {
        add("alpha", "a1", at: 1, title: "first"); add("beta", "b1", at: 3, title: "third"); add("alpha", "a2", at: 2, title: "second")
        let browser = HistoryBrowser()
        XCTAssertEqual(browser.selection, .all)
        XCTAssertEqual(HistorySelection(id: nil), .all)
        XCTAssertEqual(HistorySelection(id: HistorySelection.allID), .all)
        let all = browser.items(history: history) { $0.capitalized }
        XCTAssertEqual(all.map(\.id), ["b1", "a2", "a1"], "every app, newest first")
        XCTAssertEqual(Set(all.map(\.app)), ["alpha", "beta"])
        // the sidebar: All Apps first with the total, then each app
        let rows = browser.rows(history: history) { $0.capitalized }
        XCTAssertEqual(rows.map(\.title), ["All Apps", "Alpha", "Beta"]); XCTAssertEqual(rows.first?.total, 3)
        XCTAssertEqual(rows.first?.selection, .all); XCTAssertEqual(rows.first?.id, HistorySelection.allID)
        // selecting an app narrows; selecting All again widens
        var b = browser
        b.selection = .app("alpha"); XCTAssertEqual(b.items(history: history) { $0 }.map(\.id), ["a2", "a1"])
        b.selection = HistorySelection(id: HistorySelection.allID); XCTAssertEqual(b.items(history: history) { $0 }.count, 3)
    }

    func testSearchSpansEveryAppAndMatchesTheAppName() {
        add("alpha", "a1", title: "invoice paid"); add("beta", "b1", title: "invoice due"); add("beta", "b2", title: "deploy")
        var b = HistoryBrowser(search: "invoice")
        XCTAssertEqual(Set(b.items(history: history) { $0 }.map(\.id)), ["a1", "b1"])
        b.search = "Fancy"
        XCTAssertEqual(b.items(history: history) { $0 == "beta" ? "Fancy Beta" : $0 }.map(\.app), ["beta", "beta"], "the display name is searched")
    }

    func testMultiSelectDeleteWorksAcrossApps() {
        let x = add("alpha", "a1"), y = add("beta", "b1"), z = add("beta", "b2")
        HistoryBrowser.delete([x, y], from: history)
        XCTAssertEqual(history.items(app: "alpha").count, 0); XCTAssertEqual(history.items(app: "beta").map(\.id), [z.id])
        XCTAssertEqual(history.apps(), ["beta"])
    }

    func testASelectedAppThatIsGoneFallsBackToAllApps() {
        add("alpha", "a1")
        var b = HistoryBrowser(selection: .app("alpha"))
        history.clear(app: "alpha")
        b.reconcile(history: history)
        XCTAssertEqual(b.selection, .all)
    }
}
