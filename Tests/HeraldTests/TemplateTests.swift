import XCTest
@testable import HeraldCore

/// A backend wired to a real TemplateStore, mirroring what AppController.notify does with templates
/// (lookup, resolve, title check) so the router tests exercise the same sequence end to end.
final class TemplateBackend: HeraldBackend, @unchecked Sendable {
    let store: TemplateStore
    var delivered: [HeraldNotification] = []
    init(store: TemplateStore) { self.store = store }

    func notify(_ n: HeraldNotification) async throws -> String {
        let r = TemplateResolver.resolve(n, with: store.template(for: n))
        guard !r.title.isEmpty else { throw BackendError(400, "title is required") }
        delivered.append(r)
        return r.id ?? "gen"
    }
    func register(_ r: HeraldAppRegistration) async throws {}
    func dismiss(app: String, id: String) async throws {}
    func dismissAll(app: String?) async throws {}
    func history(app: String?, limit: Int) async throws -> [HeraldHistoryItem] { [] }
    func clearHistory(app: String?) async throws {}
    func apps() async throws -> [HeraldAppRegistration] { [] }
    func templates(app: String?) async throws -> [HeraldTemplate] { store.list(app: app) }
    func putTemplate(_ t: HeraldTemplate) async throws {
        guard store.put(t) else { throw BackendError(500, "could not save") }
    }
    func deleteTemplate(app: String, name: String) async throws {
        guard store.delete(app: app, name: name) else { throw BackendError(404, "template not found") }
    }
}

final class TemplateTests: XCTestCase {
    private func note(_ title: String = "T", metadata: [String: JSONValue]? = nil) -> HeraldNotification {
        HeraldNotification(app: "bidbot", id: "n1", title: title, metadata: metadata.map(JSONValue.object))
    }

    // MARK: Decoding

    func testPartialJSONDecodesWithDefaults() throws {
        let t = try HeraldJSON.decoder().decode(HeraldTemplate.self, from: Data("{\"name\":\"bid-won\",\"app\":\"bidbot\"}".utf8))
        XCTAssertEqual(t.id, "bidbot/bid-won")
        XCTAssertEqual(t.layout, .imageLeft)
        XCTAssertTrue(t.showSubtitle); XCTAssertTrue(t.showBody); XCTAssertTrue(t.showTimestamp)
        XCTAssertEqual(t.maxBodyLines, HeraldTemplate.defaultMaxBodyLines)
        XCTAssertEqual(t.buttons, [])
        XCTAssertNil(t.title); XCTAssertNil(t.accentColor); XCTAssertNil(t.persistent); XCTAssertNil(t.reminder)
        XCTAssertEqual(t, HeraldTemplate(name: "bid-won", app: "bidbot"))
    }

    func testSomeFieldsSetOthersDefault() throws {
        let json = """
        {"name":"n","app":"a","layout":"hero","accentColor":"#34C759","showBody":false,"maxBodyLines":3,
         "title":"Won {amount}","buttons":[{"label":"Open","url":"https://x"}],"timeout":5,"snooze":true,
         "reminder":{"title":"Follow up"}}
        """
        let t = try HeraldJSON.decoder().decode(HeraldTemplate.self, from: Data(json.utf8))
        XCTAssertEqual(t.layout, .hero); XCTAssertEqual(t.accentColor, "#34C759")
        XCTAssertFalse(t.showBody); XCTAssertTrue(t.showSubtitle)
        XCTAssertEqual(t.maxBodyLines, 3); XCTAssertEqual(t.buttons.first?.label, "Open")
        XCTAssertEqual(t.timeout, 5); XCTAssertEqual(t.snooze, true); XCTAssertEqual(t.reminder?.title, "Follow up")
    }

    func testNameAndAppAreRequiredAndBadLayoutRejected() {
        XCTAssertThrowsError(try HeraldJSON.decoder().decode(HeraldTemplate.self, from: Data("{\"app\":\"a\"}".utf8)))
        XCTAssertThrowsError(try HeraldJSON.decoder().decode(HeraldTemplate.self, from: Data("{\"name\":\"n\"}".utf8)))
        XCTAssertThrowsError(try HeraldJSON.decoder().decode(
            HeraldTemplate.self, from: Data("{\"name\":\"n\",\"app\":\"a\",\"layout\":\"sideways\"}".utf8)))
    }

    func testTemplateRoundTripsAndOmitsNilFields() throws {
        var t = HeraldTemplate(name: "n", app: "a", layout: .compact)
        t.accentColor = "#FF0000"; t.title = "Hi {x}"; t.buttons = [HeraldButton(label: "Go", url: "https://x")]
        t.reminder = HeraldReminder(title: "R", due: "2026-10-02T09:00")
        let data = try HeraldJSON.encoder().encode(t)
        XCTAssertEqual(try HeraldJSON.decoder().decode(HeraldTemplate.self, from: data), t)
        let text = String(data: data, encoding: .utf8)!
        XCTAssertFalse(text.contains("\"subtitle\"")); XCTAssertFalse(text.contains("\"id\""))
    }

    func testNotificationNewFieldsDecodeAndStayOptional() throws {
        let json = """
        {"app":"a","title":"t","template":"bid-won","layout":"imageRight","accentColor":"#123456",
         "showSubtitle":false,"showBody":true,"showTimestamp":false,"maxBodyLines":4}
        """
        let n = try HeraldJSON.decoder().decode(HeraldNotification.self, from: Data(json.utf8))
        XCTAssertEqual(n.template, "bid-won"); XCTAssertEqual(n.layout, .imageRight)
        XCTAssertEqual(n.accentColor, "#123456"); XCTAssertEqual(n.showSubtitle, false)
        XCTAssertEqual(n.showBody, true); XCTAssertEqual(n.showTimestamp, false); XCTAssertEqual(n.maxBodyLines, 4)
        let plain = try HeraldJSON.decoder().decode(HeraldNotification.self, from: Data("{\"app\":\"a\",\"title\":\"t\"}".utf8))
        XCTAssertNil(plain.template); XCTAssertNil(plain.layout); XCTAssertNil(plain.maxBodyLines)
        XCTAssertEqual(try HeraldJSON.decoder().decode(HeraldNotification.self, from: HeraldJSON.encoder().encode(n)), n)
    }

    // MARK: Resolution

    func testNoTemplateLeavesNotificationUntouched() {
        let n = HeraldNotification(app: "a", title: "{keep}", body: "{me}")
        XCTAssertEqual(TemplateResolver.resolve(n, with: nil), n)
    }

    func testTemplateFillsWhatPayloadLeftOut() {
        var t = HeraldTemplate(name: "t", app: "bidbot", layout: .hero)
        t.accentColor = "#34C759"; t.showSubtitle = false; t.showTimestamp = false; t.maxBodyLines = 2
        t.subtitle = "Sub"; t.body = "Body"; t.image = "/p.png"; t.url = "https://x"
        t.buttons = [HeraldButton(label: "Open", url: "https://x")]
        t.sound = "Ping"; t.persistent = false; t.timeout = 9; t.snooze = true; t.priority = "high"
        t.reminder = HeraldReminder(title: "R")
        let r = TemplateResolver.resolve(note(), with: t)
        XCTAssertEqual(r.title, "T")
        XCTAssertEqual(r.subtitle, "Sub"); XCTAssertEqual(r.body, "Body"); XCTAssertEqual(r.image, "/p.png")
        XCTAssertEqual(r.url, "https://x"); XCTAssertEqual(r.buttons?.count, 1)
        XCTAssertEqual(r.sound, "Ping"); XCTAssertEqual(r.persistent, false); XCTAssertEqual(r.timeout, 9)
        XCTAssertEqual(r.snooze, true); XCTAssertEqual(r.priority, "high"); XCTAssertEqual(r.reminder?.title, "R")
        XCTAssertEqual(r.layout, .hero); XCTAssertEqual(r.accentColor, "#34C759")
        XCTAssertEqual(r.showSubtitle, false); XCTAssertEqual(r.showBody, true); XCTAssertEqual(r.showTimestamp, false)
        XCTAssertEqual(r.maxBodyLines, 2)
        XCTAssertEqual(r.app, "bidbot"); XCTAssertEqual(r.id, "n1")
    }

    func testPayloadOverridesTemplate() {
        var t = HeraldTemplate(name: "t", app: "bidbot", layout: .hero)
        t.accentColor = "#111111"; t.showSubtitle = false; t.showBody = false; t.maxBodyLines = 2
        t.title = "Template title"; t.subtitle = "Tsub"; t.body = "Tbody"; t.image = "/t.png"; t.url = "https://t"
        t.buttons = [HeraldButton(label: "T", url: "https://t")]
        t.sound = "Ping"; t.persistent = false; t.timeout = 9; t.snooze = true; t.priority = "low"
        t.reminder = HeraldReminder(title: "TR")
        let payload = HeraldNotification(
            app: "bidbot", id: "n1", title: "Payload title", subtitle: "Psub", body: "Pbody", image: "/p.png",
            url: "https://p", sound: "none", persistent: true, timeout: 0, priority: "high",
            buttons: [HeraldButton(label: "P")], snooze: false, reminder: HeraldReminder(title: "PR"),
            template: "t", layout: .compact, accentColor: "#222222", showSubtitle: true, showBody: true,
            showTimestamp: true, maxBodyLines: 5)
        let r = TemplateResolver.resolve(payload, with: t)
        XCTAssertEqual(r, payload)           // every payload field survives
        XCTAssertEqual(r.template, "t")      // and the reference to the template is kept
    }

    func testEmptyTitleTakesTemplateTitleButExplicitEmptyButtonsWin() {
        var t = HeraldTemplate(name: "t", app: "bidbot")
        t.title = "From template"; t.buttons = [HeraldButton(label: "T")]
        XCTAssertEqual(TemplateResolver.resolve(note(""), with: t).title, "From template")
        XCTAssertEqual(TemplateResolver.resolve(note("Mine"), with: t).title, "Mine")
        var n = note(); n.buttons = []
        XCTAssertEqual(TemplateResolver.resolve(n, with: t).buttons, [])
        XCTAssertEqual(TemplateResolver.resolve(note(), with: t).buttons?.map(\.label), ["T"])
        // No template buttons and none in the payload leaves the field nil rather than [].
        XCTAssertNil(TemplateResolver.resolve(note(), with: HeraldTemplate(name: "e", app: "bidbot")).buttons)
    }

    // MARK: Placeholders

    func testPlaceholdersFromMetadataThenOwnFields() {
        var t = HeraldTemplate(name: "t", app: "bidbot")
        t.title = "Won {amount} on {project}"
        t.subtitle = "{subtitle} / {app} / {id}"
        t.body = "{title}: {amount}"
        t.url = "https://x/{bid}"
        let n = HeraldNotification(app: "bidbot", id: "n1", title: "", subtitle: "Acme", body: nil, url: nil,
                                   metadata: .object(["amount": .string("$4,200"), "project": .string("RFP"), "bid": .number(42)]))
        // Own fields come from the payload as sent: its title is empty, so {title} is empty here.
        let r = TemplateResolver.resolve(n, with: t)
        XCTAssertEqual(r.title, "Won $4,200 on RFP")
        XCTAssertEqual(r.subtitle, "Acme") // payload subtitle wins; the template's is not used
        XCTAssertEqual(r.body, ": $4,200")
        XCTAssertEqual(r.url, "https://x/42")

        var t2 = HeraldTemplate(name: "t2", app: "bidbot")
        t2.subtitle = "{subtitle} / {app} / {id}"; t2.body = "{title}: {amount}"
        let n2 = HeraldNotification(app: "bidbot", id: "n1", title: "Bid", subtitle: nil, metadata: .object(["amount": .string("9")]))
        let r2 = TemplateResolver.resolve(n2, with: t2)
        XCTAssertEqual(r2.subtitle, " / bidbot / n1")    // payload has no subtitle: {subtitle} is empty
        XCTAssertEqual(r2.body, "Bid: 9")
    }

    func testUnknownPlaceholdersBecomeEmpty() {
        var t = HeraldTemplate(name: "t", app: "bidbot")
        t.title = "A{nope}B"; t.body = "{missing} and {also_missing}!"
        let r = TemplateResolver.resolve(note(""), with: t)
        XCTAssertEqual(r.title, "AB")
        XCTAssertEqual(r.body, " and !")
    }

    func testMetadataBeatsOwnFields() {
        var t = HeraldTemplate(name: "t", app: "bidbot")
        t.body = "{title}|{app}"
        let n = HeraldNotification(app: "bidbot", title: "Real", metadata: .object(["title": .string("Meta"), "app": .string("MetaApp")]))
        XCTAssertEqual(TemplateResolver.resolve(n, with: t).body, "Meta|MetaApp")
    }

    func testPlaceholderTypesNestingAndLiteralBraces() {
        var t = HeraldTemplate(name: "t", app: "bidbot")
        t.body = "{n} {frac} {ok} {nul} {arr} {customer.name} {customer.x.y} {} { spaced } {\"j\":1} {{wrapped}}"
        let meta: [String: JSONValue] = [
            "n": .number(4200), "frac": .number(2.5), "ok": .bool(true), "nul": .null, "arr": .array([.string("x")]),
            "customer": .object(["name": .string("Acme")]),
        ]
        let r = TemplateResolver.resolve(note(metadata: meta), with: t)
        XCTAssertEqual(r.body, "4200 2.5 true   Acme  {} { spaced } {\"j\":1} {}")
        // {{wrapped}}: the inner token is unknown (empty), the outer braces are literal.
    }

    func testSubstitutedValuesAreNotRescannedAndPayloadTextIsLiteral() {
        var t = HeraldTemplate(name: "t", app: "bidbot")
        t.body = "{a}"
        let r = TemplateResolver.resolve(note(metadata: ["a": .string("{b}"), "b": .string("no")]), with: t)
        XCTAssertEqual(r.body, "{b}")
        var n = note("Keep {this}"); n.body = "and {that}"
        let r2 = TemplateResolver.resolve(n, with: t)
        XCTAssertEqual(r2.title, "Keep {this}"); XCTAssertEqual(r2.body, "and {that}")
    }

    func testURLPlaceholderValuesAreEscapedButSchemeIsNot() {
        var t = HeraldTemplate(name: "t", app: "bidbot")
        t.url = "{base}/search?q={q}"
        let r = TemplateResolver.resolve(note(metadata: ["base": .string("https://x.test"), "q": .string("Acme Corp")]), with: t)
        XCTAssertEqual(r.url, "https://x.test/search?q=Acme%20Corp")
        XCTAssertNotNil(URL(string: r.url ?? ""))
    }

    /// A whole link in metadata must reach the click target as it was: existing %XX escapes are not
    /// escaped a second time and the fragment is not turned into %23.
    func testURLPlaceholderKeepsExistingEscapesAndFragment() {
        var t = HeraldTemplate(name: "t", app: "bidbot")
        t.url = "{link}"
        let r = TemplateResolver.resolve(note(metadata: ["link": .string("https://x.com/a%20b?q=1#top")]), with: t)
        XCTAssertEqual(r.url, "https://x.com/a%20b?q=1#top")
        XCTAssertNotNil(URL(string: r.url ?? ""))
    }

    func testURLPlaceholderStillEscapesABarePercentAndSpaces() {
        var t = HeraldTemplate(name: "t", app: "bidbot")
        t.url = "https://x.test/s?q={q}"
        let r = TemplateResolver.resolve(note(metadata: ["q": .string("50% off, 100%")]), with: t)
        XCTAssertEqual(r.url, "https://x.test/s?q=50%25%20off,%20100%25")
        XCTAssertNotNil(URL(string: r.url ?? ""))
    }

    func testPlaceholderListing() {
        XCTAssertEqual(TemplateResolver.placeholders(in: "{b} {a} {b} {} x"), ["b", "a"])
        XCTAssertEqual(TemplateResolver.placeholders(in: "none"), [])
    }

    // MARK: Store

    private func tempStore() -> (TemplateStore, URL) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("herald-tpl-\(UUID().uuidString)")
        return (TemplateStore(directory: dir), dir)
    }

    func testStoreRoundTrip() throws {
        let (store, dir) = tempStore(); defer { try? FileManager.default.removeItem(at: dir) }
        XCTAssertEqual(store.list(), [])
        XCTAssertNil(store.get(app: "bidbot", name: "bid-won"))

        var a = HeraldTemplate(name: "bid-won", app: "bidbot", layout: .hero)
        a.title = "Won {amount}"; a.accentColor = "#34C759"
        let b = HeraldTemplate(name: "bid-lost", app: "bidbot")
        let c = HeraldTemplate(name: "alert", app: "other")
        XCTAssertTrue(store.put(a)); XCTAssertTrue(store.put(b)); XCTAssertTrue(store.put(c))

        XCTAssertEqual(store.get(app: "bidbot", name: "bid-won"), a)
        XCTAssertEqual(store.list(app: "bidbot").map(\.name), ["bid-lost", "bid-won"])
        XCTAssertEqual(store.list(app: nil).map(\.id), ["bidbot/bid-lost", "bidbot/bid-won", "other/alert"])
        XCTAssertEqual(store.list(app: "").count, 3)
        XCTAssertEqual(store.list(app: "ghost"), [])
        // The documented on-disk location.
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("bidbot/bid-won.json").path))

        a.layout = .compact
        XCTAssertTrue(store.put(a))   // replace
        XCTAssertEqual(store.get(app: "bidbot", name: "bid-won")?.layout, .compact)
        XCTAssertEqual(store.list(app: "bidbot").count, 2)

        // A fresh store over the same folder sees the same data (persistence, not a cache).
        XCTAssertEqual(TemplateStore(directory: dir).get(app: "bidbot", name: "bid-won"), a)

        XCTAssertTrue(store.delete(app: "bidbot", name: "bid-won"))
        XCTAssertFalse(store.delete(app: "bidbot", name: "bid-won"))
        XCTAssertNil(store.get(app: "bidbot", name: "bid-won"))
        XCTAssertTrue(store.delete(app: "bidbot", name: "bid-lost"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent("bidbot").path), "empty app folder is removed")
        XCTAssertEqual(store.list().map(\.id), ["other/alert"])
    }

    func testStoreRejectsEmptyIdentityAndNeutralisesPaths() throws {
        let (store, dir) = tempStore(); defer { try? FileManager.default.removeItem(at: dir) }
        XCTAssertFalse(store.put(HeraldTemplate(name: "", app: "a")))
        XCTAssertFalse(store.put(HeraldTemplate(name: "n", app: "")))
        let evil = HeraldTemplate(name: "../../escape", app: "..")
        XCTAssertTrue(store.put(evil))
        XCTAssertEqual(store.get(app: "..", name: "../../escape"), evil)
        // Nothing was written outside the templates folder.
        let parent = dir.deletingLastPathComponent()
        XCTAssertFalse(FileManager.default.fileExists(atPath: parent.appendingPathComponent("escape.json").path))
        // (Resolve symlinks: the temp dir is /var/... but the enumerator reports /private/var/...)
        let root = dir.resolvingSymlinksInPath().path + "/"
        let written = ((FileManager.default.enumerator(at: dir, includingPropertiesForKeys: nil)?.allObjects as? [URL]) ?? [])
            .filter { $0.pathExtension == "json" }
        XCTAssertEqual(written.count, 1)
        XCTAssertTrue(written.allSatisfy { $0.resolvingSymlinksInPath().path.hasPrefix(root) })
        // Distinct awkward names do not collide.
        XCTAssertTrue(store.put(HeraldTemplate(name: "a/b", app: "x"))); XCTAssertTrue(store.put(HeraldTemplate(name: "a_b", app: "x")))
        XCTAssertEqual(store.list(app: "x").count, 2)
    }

    func testStoreFindsHandRenamedFileAndSkipsCorruptOnes() throws {
        let (store, dir) = tempStore(); defer { try? FileManager.default.removeItem(at: dir) }
        XCTAssertTrue(store.put(HeraldTemplate(name: "real", app: "a")))
        let folder = dir.appendingPathComponent("a")
        try FileManager.default.moveItem(at: folder.appendingPathComponent("real.json"), to: folder.appendingPathComponent("renamed.json"))
        try "not json".write(to: folder.appendingPathComponent("junk.json"), atomically: true, encoding: .utf8)
        XCTAssertEqual(store.get(app: "a", name: "real")?.name, "real")
        XCTAssertEqual(store.list(app: "a").map(\.name), ["real"])
        XCTAssertTrue(store.delete(app: "a", name: "real"))
        XCTAssertNil(store.get(app: "a", name: "real"))
    }

    func testTemplateLookupForNotification() {
        let (store, dir) = tempStore(); defer { try? FileManager.default.removeItem(at: dir) }
        store.put(HeraldTemplate(name: "bid-won", app: "bidbot"))
        XCTAssertNotNil(store.template(for: HeraldNotification(app: "bidbot", title: "t", template: "bid-won")))
        XCTAssertNil(store.template(for: HeraldNotification(app: "other", title: "t", template: "bid-won")))
        XCTAssertNil(store.template(for: HeraldNotification(app: "bidbot", title: "t", template: "nope")))
        XCTAssertNil(store.template(for: HeraldNotification(app: "bidbot", title: "t")))
    }

    // MARK: Router

    private func routerAndBackend() -> (Router, TemplateBackend, URL) {
        let (store, dir) = tempStore()
        let backend = TemplateBackend(store: store)
        return (Router(token: "secret-token", backend: backend, version: "1.0.0", pid: 1), backend, dir)
    }

    private func req(_ method: String, _ path: String, token: String? = "secret-token", body: String = "",
                     query: [String: String] = [:]) -> HTTPRequest {
        var h: [String: String] = [:]
        if let token { h["authorization"] = "Bearer \(token)" }
        return HTTPRequest(method: method, path: path, query: query, headers: h, body: Data(body.utf8))
    }

    private func text(_ r: HTTPResponse) -> String { String(data: r.body, encoding: .utf8) ?? "" }

    func testTemplateRoutesNeedAuth() async {
        let (router, _, dir) = routerAndBackend(); defer { try? FileManager.default.removeItem(at: dir) }
        let calls: [(String, [String: String], String)] = [
            ("GET", [:], ""), ("PUT", [:], "{\"name\":\"n\",\"app\":\"a\"}"), ("DELETE", ["app": "a", "name": "n"], ""),
        ]
        for (method, query, body) in calls {
            for t in [nil, "wrong"] as [String?] {
                let r = await router.handle(req(method, "/v1/templates", token: t, body: body, query: query))
                XCTAssertEqual(r.status, 401, "\(method) with token \(t ?? "nil")")
                XCTAssertEqual(text(r), "{\"error\":\"unauthorized\"}")
            }
        }
    }

    func testScratchTemplatesAreNotListed() async throws {
        let (router, backend, dir) = routerAndBackend(); defer { try? FileManager.default.removeItem(at: dir) }
        for name in ["_designer-test", "bid-won"] {
            let put = await router.handle(req("PUT", "/v1/templates", body: "{\"name\":\"\(name)\",\"app\":\"bidbot\"}"))
            XCTAssertEqual(put.status, 200)
        }
        let r = await router.handle(req("GET", "/v1/templates"))
        let items = try HeraldJSON.decoder().decode([String: [HeraldTemplate]].self, from: r.body)["items"] ?? []
        XCTAssertEqual(items.map(\.name), ["bid-won"])
        XCTAssertNotNil(backend.store.template(for: HeraldNotification(app: "bidbot", title: "t", template: "_designer-test")),
                        "a scratch template still resolves by name")
    }

    func testTemplateCRUDOverHTTP() async throws {
        let (router, backend, dir) = routerAndBackend(); defer { try? FileManager.default.removeItem(at: dir) }
        var r = await router.handle(req("GET", "/v1/templates"))
        XCTAssertEqual(r.status, 200); XCTAssertEqual(text(r), "{\"items\":[]}")

        r = await router.handle(req("PUT", "/v1/templates", body: "{\"name\":\"bid-won\",\"app\":\"bidbot\",\"layout\":\"hero\",\"title\":\"Won {amount}\"}"))
        XCTAssertEqual(r.status, 200); XCTAssertEqual(text(r), "{\"ok\":true}")
        r = await router.handle(req("PUT", "/v1/templates", body: "{\"name\":\"alert\",\"app\":\"other\"}"))
        XCTAssertEqual(r.status, 200)

        struct Reply: Decodable { var items: [HeraldTemplate] }
        r = await router.handle(req("GET", "/v1/templates", query: ["app": "bidbot"]))
        var items = try HeraldJSON.decoder().decode(Reply.self, from: r.body).items
        XCTAssertEqual(items.count, 1); XCTAssertEqual(items[0].layout, .hero); XCTAssertEqual(items[0].title, "Won {amount}")
        r = await router.handle(req("GET", "/v1/templates"))
        items = try HeraldJSON.decoder().decode(Reply.self, from: r.body).items
        XCTAssertEqual(items.map(\.id), ["bidbot/bid-won", "other/alert"])

        r = await router.handle(req("DELETE", "/v1/templates", query: ["app": "bidbot", "name": "bid-won"]))
        XCTAssertEqual(r.status, 200); XCTAssertEqual(text(r), "{\"ok\":true}")
        XCTAssertNil(backend.store.get(app: "bidbot", name: "bid-won"))
        r = await router.handle(req("DELETE", "/v1/templates", query: ["app": "bidbot", "name": "bid-won"]))
        XCTAssertEqual(r.status, 404)
    }

    func testOversizedGridIsRefusedBeforeItAllocatesAnything() async throws {
        // Decoding stops at the track count, before one size per track is allocated.
        for json in [#"{"rows":40000000,"cols":3}"#, #"{"rows":3,"cols":13}"#, #"{"rows":0,"cols":3}"#, #"{"rows":-5,"cols":3}"#,
                     #"{"rows":2,"cols":2,"rowSizes":["auto","auto","auto","auto","auto","auto","auto","auto","auto","auto","auto","auto","auto"]}"#] {
            XCTAssertThrowsError(try HeraldJSON.decoder().decode(HeraldGrid.self, from: Data(json.utf8)), json)
        }
        let ok = try HeraldJSON.decoder().decode(HeraldGrid.self, from: Data(#"{"rows":12,"cols":12}"#.utf8))
        XCTAssertEqual(ok.rowSizes.count, 12)

        // PUT /v1/templates says why, and nothing is stored.
        let (router, backend, dir) = routerAndBackend(); defer { try? FileManager.default.removeItem(at: dir) }
        var r = await router.handle(req("PUT", "/v1/templates", body: #"{"name":"x","app":"bidbot","grid":{"rows":40000000,"cols":3}}"#))
        XCTAssertEqual(r.status, 400)
        XCTAssertTrue(text(r).contains("grid.rows"), text(r))
        // A grid that decodes but fails validation (a 5000 pt track) is refused too, where it used to be saved.
        r = await router.handle(req("PUT", "/v1/templates", body: #"{"name":"x","app":"bidbot","layoutVersion":2,"grid":{"rows":1,"cols":1,"rowSizes":[5000],"colSizes":["fill"]}}"#))
        XCTAssertEqual(r.status, 400)
        XCTAssertTrue(text(r).contains("invalid template"), text(r))
        XCTAssertNil(backend.store.get(app: "bidbot", name: "x"))
    }

    func testOversizedTemplateFileIsIgnoredOnRead() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("herald-big-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = TemplateStore(directory: dir)
        XCTAssertTrue(store.put(HeraldTemplate(name: "small", app: "bidbot")))
        XCTAssertNotNil(store.get(app: "bidbot", name: "small"))
        let file = dir.appendingPathComponent("bidbot/small.json")
        let pad = String(repeating: " ", count: TemplateStore.maxFileBytes + 1)
        let json = try String(contentsOf: file, encoding: .utf8) + pad
        try json.write(to: file, atomically: true, encoding: .utf8)
        XCTAssertNil(store.get(app: "bidbot", name: "small"))
    }

    func testTemplateRouteValidationAndMethods() async {
        let (router, _, dir) = routerAndBackend(); defer { try? FileManager.default.removeItem(at: dir) }
        var r = await router.handle(req("PUT", "/v1/templates", body: "{\"app\":\"a\"}"))
        XCTAssertEqual(r.status, 400); XCTAssertTrue(text(r).contains("name"))
        r = await router.handle(req("PUT", "/v1/templates", body: "{\"name\":\"n\",\"app\":\"\"}"))
        XCTAssertEqual(r.status, 400); XCTAssertTrue(text(r).contains("app"))
        r = await router.handle(req("PUT", "/v1/templates", body: "nope"))
        XCTAssertEqual(r.status, 400)
        r = await router.handle(req("DELETE", "/v1/templates", query: ["app": "a"]))
        XCTAssertEqual(r.status, 400)
        r = await router.handle(req("DELETE", "/v1/templates", query: ["name": "n"]))
        XCTAssertEqual(r.status, 400)
        r = await router.handle(req("POST", "/v1/templates"))
        XCTAssertEqual(r.status, 405)
    }

    func testBackendWithoutTemplateSupportAnswers501() async {
        let router = Router(token: "secret-token", backend: MockBackend(), version: "1.0.0", pid: 1)
        let r = await router.handle(req("GET", "/v1/templates"))
        XCTAssertEqual(r.status, 501)
    }

    func testNotifyResolvesTemplateThroughRouter() async {
        let (router, backend, dir) = routerAndBackend(); defer { try? FileManager.default.removeItem(at: dir) }
        _ = await router.handle(req("PUT", "/v1/templates", body: """
            {"name":"bid-won","app":"bidbot","layout":"hero","accentColor":"#34C759","title":"Won {amount}",
             "body":"{client} accepted","buttons":[{"label":"Open","url":"https://x"}],"showTimestamp":false}
            """))

        // Title-less payload: the template supplies it, placeholders come from metadata.
        var r = await router.handle(req("POST", "/v1/notify", body: """
            {"app":"bidbot","id":"b1","template":"bid-won","metadata":{"amount":"$4,200","client":"Acme"}}
            """))
        XCTAssertEqual(r.status, 200, text(r))
        let d = backend.delivered.last
        XCTAssertEqual(d?.title, "Won $4,200"); XCTAssertEqual(d?.body, "Acme accepted")
        XCTAssertEqual(d?.layout, .hero); XCTAssertEqual(d?.accentColor, "#34C759")
        XCTAssertEqual(d?.showTimestamp, false); XCTAssertEqual(d?.buttons?.first?.label, "Open")

        // Payload fields override the template.
        r = await router.handle(req("POST", "/v1/notify", body: """
            {"app":"bidbot","id":"b2","title":"Mine","template":"bid-won","layout":"compact","buttons":[]}
            """))
        XCTAssertEqual(r.status, 200)
        XCTAssertEqual(backend.delivered.last?.title, "Mine"); XCTAssertEqual(backend.delivered.last?.layout, .compact)
        XCTAssertEqual(backend.delivered.last?.buttons, [])

        // Unknown template with a title still delivers, unstyled; without a title it is a 400.
        r = await router.handle(req("POST", "/v1/notify", body: "{\"app\":\"bidbot\",\"title\":\"Plain\",\"template\":\"ghost\"}"))
        XCTAssertEqual(r.status, 200)
        XCTAssertNil(backend.delivered.last?.layout)
        r = await router.handle(req("POST", "/v1/notify", body: "{\"app\":\"bidbot\",\"template\":\"ghost\"}"))
        XCTAssertEqual(r.status, 400)

        // No template and no title keeps the original error.
        r = await router.handle(req("POST", "/v1/notify", body: "{\"app\":\"bidbot\"}"))
        XCTAssertEqual(r.status, 400); XCTAssertTrue(text(r).contains("title"))
    }
}
