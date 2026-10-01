import XCTest
@testable import HeraldCore

/// A backend that records the preview request it is handed and answers with a stand-in PNG.
final class PreviewBackend: HeraldBackend, @unchecked Sendable {
    static let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x01])
    var requests: [PreviewSpec] = []
    var failure: BackendError?
    func notify(_ n: HeraldNotification) async throws -> String { "x" }
    func register(_ r: HeraldAppRegistration) async throws {}
    func dismiss(app: String, id: String) async throws {}
    func dismissAll(app: String?) async throws {}
    func history(app: String?, limit: Int) async throws -> [HeraldHistoryItem] { [] }
    func clearHistory(app: String?) async throws {}
    func apps() async throws -> [HeraldAppRegistration] { [] }
    func preview(_ request: PreviewSpec) async throws -> Data {
        requests.append(request)
        if let failure { throw failure }
        return Self.png
    }
}

/// `POST|GET /v1/preview` (DESIGN 7.5). The route validates and decodes; the rendering itself (ImageRenderer
/// over the one GridBannerView) lives in the app target, which the package test host cannot link, so a PNG
/// signature check on a real render is done by the app-level run, not here.
final class PreviewRouteTests: XCTestCase {
    let token = "secret-token"
    var backend = PreviewBackend()
    var router: Router!

    override func setUp() {
        backend = PreviewBackend()
        router = Router(token: token, backend: backend, version: "1.1.0", pid: 1)
    }

    private func req(_ method: String, token: String? = "secret-token", body: String = "",
                     query: [String: String] = [:]) -> HTTPRequest {
        var h: [String: String] = [:]
        if let token { h["authorization"] = "Bearer \(token)" }
        return HTTPRequest(method: method, path: "/v1/preview", query: query, headers: h, body: Data(body.utf8))
    }

    private func post(_ json: String) async -> HTTPResponse { await router.handle(req("POST", body: json)) }

    private func message(_ r: HTTPResponse) -> String {
        ((try? JSONSerialization.jsonObject(with: r.body)) as? [String: String])?["error"] ?? ""
    }

    // MARK: Success

    func testNamedTemplateWithSampleDataReturnsPNG() async {
        let r = await post(#"{"template":"builtin.hero","app":"bidbot","data":"sample","appearance":"dark","scale":3}"#)
        XCTAssertEqual(r.status, 200)
        XCTAssertEqual(r.contentType, "image/png")
        XCTAssertEqual(r.body, PreviewBackend.png)
        XCTAssertEqual(Array(r.body.prefix(8)), [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        XCTAssertEqual(backend.requests.count, 1)
        let q = backend.requests[0]
        XCTAssertEqual(q.template, .named("builtin.hero"))
        XCTAssertEqual(q.app, "bidbot")
        XCTAssertNil(q.data)
        XCTAssertEqual(q.appearance, .dark)
        XCTAssertEqual(q.scale, 3)
    }

    func testResponseIsServedAsImagePNG() async {
        let r = await post(#"{"app":"a"}"#)
        let wire = String(decoding: r.serialize(), as: UTF8.self)
        XCTAssertTrue(wire.hasPrefix("HTTP/1.1 200 OK\r\n"))
        XCTAssertTrue(wire.contains("Content-Type: image/png\r\n"))
        XCTAssertFalse(wire.contains("application/json"))
        XCTAssertTrue(wire.contains("Content-Length: \(PreviewBackend.png.count)\r\n"))
    }

    func testErrorsStayJSON() async {
        let r = await post("{}")
        XCTAssertEqual(r.contentType, "application/json")
        XCTAssertTrue(String(decoding: r.serialize(), as: UTF8.self).contains("Content-Type: application/json\r\n"))
    }

    func testDefaultsAreDefaultTemplateSampleDataLightScaleTwo() async {
        let r = await post(#"{"app":"bidbot"}"#)
        XCTAssertEqual(r.status, 200)
        let q = backend.requests[0]
        XCTAssertNil(q.template)
        XCTAssertNil(q.data)
        XCTAssertEqual(q.appearance, .light)
        XCTAssertEqual(q.scale, 2)
    }

    func testInlineTemplateIsDecodedAndSuppliesTheApp() async throws {
        let t = BuiltinTemplates.template(layout: .compact, app: "from-template")
        let body = String(decoding: try HeraldJSON.encoder().encode(t), as: UTF8.self)
        let r = await post(#"{"template":"# + body + "}")
        XCTAssertEqual(r.status, 200, message(r))
        XCTAssertEqual(backend.requests[0].app, "from-template")
        guard case .inline(let got)? = backend.requests[0].template else { return XCTFail("not inline") }
        XCTAssertEqual(got.name, t.name)
        XCTAssertEqual(got.cells.count, t.cells.count)
    }

    func testInlineV1TemplateIsAccepted() async {
        let r = await post(#"{"template":{"name":"old","app":"a","layout":"hero"}}"#)
        XCTAssertEqual(r.status, 200, message(r))
        guard case .inline(let t)? = backend.requests[0].template else { return XCTFail("not inline") }
        XCTAssertFalse(t.usesGrid)
    }

    func testDataObjectBecomesANotification() async {
        let r = await post(#"{"app":"bidbot","template":"t","data":{"title":"Bid accepted","count":3,"customer":{"name":"Acme"},"buttons":[{"label":"Open","url":"https://example.com"}]}}"#)
        XCTAssertEqual(r.status, 200, message(r))
        guard let n = backend.requests[0].data else { return XCTFail("no data") }
        XCTAssertEqual(n.app, "bidbot")
        XCTAssertEqual(n.title, "Bid accepted")
        XCTAssertEqual(n.buttons?.first?.label, "Open")
        let fields = TemplateResolver.fields(for: n)
        XCTAssertEqual(fields["count"], .number(3))
        XCTAssertEqual(fields["customer.name"], .text("Acme"))
    }

    func testDataWithoutTitleIsAllowed() async {
        let r = await post(#"{"app":"a","data":{"subject":"Invoice"}}"#)
        XCTAssertEqual(r.status, 200, message(r))
        let n = backend.requests[0].data
        XCTAssertEqual(n?.title, "")
        XCTAssertEqual(TemplateResolver.fields(for: n!)["subject"], .text("Invoice"))
    }

    func testAppearanceIsCaseInsensitiveAndScaleMayBeFractional() async {
        let r = await post(#"{"app":"a","appearance":"DARK","scale":1.5}"#)
        XCTAssertEqual(r.status, 200, message(r))
        XCTAssertEqual(backend.requests[0].appearance, .dark)
        XCTAssertEqual(backend.requests[0].scale, 1.5)
    }

    // MARK: Validation

    func testRequiresAuth() async {
        for t in [nil, "wrong"] as [String?] {
            let r = await router.handle(req("POST", token: t, body: #"{"app":"a"}"#))
            XCTAssertEqual(r.status, 401)
            let g = await router.handle(req("GET", token: t, query: ["app": "a"]))
            XCTAssertEqual(g.status, 401)
        }
        XCTAssertTrue(backend.requests.isEmpty)
    }

    func testRejectsBadBodies() async {
        let cases: [(String, String)] = [
            ("", "a JSON body is required"),
            ("not json", "invalid JSON"),
            ("[]", "invalid JSON"),
            ("{}", "app is required"),
            (#"{"app":""}"#, "app is required"),
            (#"{"app":5}"#, "invalid field: app"),
            (#"{"app":"a","template":5}"#, "invalid field: template"),
            (#"{"app":"a","data":"live"}"#, "invalid field: data"),
            (#"{"app":"a","data":5}"#, "invalid field: data"),
            (#"{"app":"a","data":[1]}"#, "invalid field: data"),
            (#"{"app":"a","appearance":"sepia"}"#, "invalid field: appearance"),
            (#"{"app":"a","appearance":1}"#, "invalid field: appearance"),
        ]
        for (body, expected) in cases {
            let r = await post(body)
            XCTAssertEqual(r.status, 400, body)
            XCTAssertTrue(message(r).contains(expected), "\(body) -> \(message(r))")
        }
        XCTAssertTrue(backend.requests.isEmpty)
    }

    func testRejectsScaleOutsideOneToThree() async {
        for scale in ["0", "0.5", "3.5", "4", "-1", #""big""#, "true"] {
            let r = await post(#"{"app":"a","scale":"# + scale + "}")
            XCTAssertEqual(r.status, 400, scale)
            XCTAssertTrue(message(r).contains("scale"), message(r))
        }
        for scale in ["1", "2", "3"] {
            let r = await post(#"{"app":"a","scale":"# + scale + "}")
            XCTAssertEqual(r.status, 200, scale)
        }
        let nul = await post(#"{"app":"a","scale":null}"#)
        XCTAssertEqual(nul.status, 200)
        XCTAssertEqual(backend.requests.last?.scale, 2)
    }

    func testInvalidInlineTemplateNamesTheCell() async {
        let t = #"{"name":"bad","app":"a","grid":{"rows":1,"cols":2},"cells":[{"id":"c1","row":0,"col":0,"component":{"type":"text","binding":"{title}","style":"title"}},{"id":"c2","row":4,"col":0,"component":{"type":"text","binding":"{title}"}}]}"#
        let r = await post(#"{"template":"# + t + "}")
        XCTAssertEqual(r.status, 400)
        XCTAssertTrue(message(r).hasPrefix("invalid template: "), message(r))
        XCTAssertTrue(message(r).contains("c2"), message(r))
        XCTAssertTrue(backend.requests.isEmpty)
    }

    func testUndecodableInlineTemplateSaysWhere() async {
        let r = await post(#"{"template":{"name":"x","app":"a","grid":{"rows":1,"cols":1},"cells":[{"id":"c","row":0,"col":0,"component":{"type":"hologram"}}]}}"#)
        XCTAssertEqual(r.status, 400)
        XCTAssertTrue(message(r).hasPrefix("invalid template: "), message(r))
        XCTAssertTrue(message(r).contains("cells[0]"), message(r))
    }

    func testBackendErrorsPassThrough() async {
        backend.failure = BackendError(404, "template not found")
        let r = await post(#"{"app":"a","template":"nope"}"#)
        XCTAssertEqual(r.status, 404)
        XCTAssertEqual(message(r), "template not found")
        backend.failure = BackendError(500, "could not render the preview")
        let g = await router.handle(req("GET", query: ["app": "a"]))
        XCTAssertEqual(g.status, 500)
        XCTAssertEqual(g.contentType, "application/json")
    }

    func testBackendWithoutPreviewAnswers501() async {
        let r = Router(token: token, backend: MockBackend(), version: "1.1.0", pid: 1)
        let resp = await r.handle(req("POST", body: #"{"app":"a"}"#))
        XCTAssertEqual(resp.status, 501)
    }

    // MARK: GET

    func testGetQuickCheck() async {
        let r = await router.handle(req("GET", query: ["app": "bidbot", "template": "builtin.compact", "appearance": "dark"]))
        XCTAssertEqual(r.status, 200)
        XCTAssertEqual(r.contentType, "image/png")
        let q = backend.requests[0]
        XCTAssertEqual(q, PreviewSpec(template: .named("builtin.compact"), app: "bidbot", data: nil,
                                               appearance: .dark, scale: 2))
    }

    func testGetNeedsOnlyTheApp() async {
        let r = await router.handle(req("GET", query: ["app": "bidbot"]))
        XCTAssertEqual(r.status, 200)
        XCTAssertNil(backend.requests[0].template)
        XCTAssertEqual(backend.requests[0].appearance, .light)
    }

    func testGetValidation() async {
        let missing = await router.handle(req("GET"))
        XCTAssertEqual(missing.status, 400)
        XCTAssertEqual(message(missing), "app is required")
        let bad = await router.handle(req("GET", query: ["app": "a", "appearance": "blue"]))
        XCTAssertEqual(bad.status, 400)
        let scale = await router.handle(req("GET", query: ["app": "a", "scale": "9"]))
        XCTAssertEqual(scale.status, 400)
        let ok = await router.handle(req("GET", query: ["app": "a", "scale": "1"]))
        XCTAssertEqual(ok.status, 200)
        XCTAssertEqual(backend.requests.last?.scale, 1)
    }

    func testOtherMethodsAreNotAllowed() async {
        for m in ["PUT", "DELETE", "PATCH"] {
            let r = await router.handle(req(m, body: "{}"))
            XCTAssertEqual(r.status, 405, m)
        }
    }
}

/// What a preview draws: which template, which data (`PreviewPlan`).
final class PreviewPlanTests: XCTestCase {
    private let manifest = HeraldManifest(
        app: "mail", appName: "Mail",
        fields: [HeraldField(key: "title", type: .text, sample: .text("2 new from Acme")),
                 HeraldField(key: "sender", type: .text, sample: .text("Acme Billing")),
                 HeraldField(key: "count", type: .number, sample: .number(2)),
                 HeraldField(key: "tags", type: .list)],
        actions: [HeraldButton(label: "Mark as Read", callback: HeraldCallback(url: "http://127.0.0.1:1/x"))],
        defaultTemplate: "stored-default")

    private func plan(_ r: PreviewSpec, manifest: HeraldManifest? = nil,
                      stored: [String: HeraldTemplate] = [:]) throws -> PreviewPlan {
        try PreviewPlan.make(r, manifest: manifest, stored: { stored[$0] }, now: Date(timeIntervalSince1970: 1_800_000_000))
    }

    func testSampleDataComesFromTheManifest() throws {
        let p = try plan(PreviewSpec(app: "mail"), manifest: manifest)
        XCTAssertTrue(p.usedSamples)
        XCTAssertEqual(p.notification.title, "2 new from Acme")
        XCTAssertEqual(p.fields["sender"], .text("Acme Billing"))
        XCTAssertEqual(p.fields["count"], .number(2))
        XCTAssertEqual(p.fields["tags"], .list(["One", "Two", "Three"]))
        XCTAssertNotNil(p.fields["deliveredAt"])
        XCTAssertEqual(p.actions.map(\.action.label), ["Mark as Read"])
        XCTAssertEqual(p.actions.first?.origin, .issuer)
    }

    func testNoManifestUsesGenericSamplesAndAnOpenButton() throws {
        let p = try plan(PreviewSpec(app: "x"))
        XCTAssertEqual(p.notification.title, "Notification title")
        XCTAssertEqual(p.actions.map(\.action.label), ["Open"])
        XCTAssertEqual(p.template.name, "builtin.imageLeft")
    }

    func testNoTemplateUsesTheManifestDefaultThenTheBuiltin() throws {
        var stored = HeraldTemplate.blank(name: "stored-default", app: "mail")
        stored.accentColor = "#FF0000"
        let withDefault = try plan(PreviewSpec(app: "mail"), manifest: manifest, stored: ["stored-default": stored])
        XCTAssertEqual(withDefault.template.name, "stored-default")
        XCTAssertEqual(withDefault.notification.accentColor, "#FF0000")
        // The default names a template that no longer exists: fall back rather than fail.
        let missing = try plan(PreviewSpec(app: "mail"), manifest: manifest)
        XCTAssertEqual(missing.template.name, "builtin.imageLeft")
        XCTAssertEqual(missing.template.app, "mail")
    }

    func testNamedBuiltinStoredAndUnknown() throws {
        let hero = try plan(PreviewSpec(template: .named("builtin.hero"), app: "a"))
        XCTAssertEqual(hero.grid.layout, .hero)
        XCTAssertTrue(hero.grid.usesGrid)
        let mine = HeraldTemplate.blank(name: "mine", app: "a")
        XCTAssertEqual(try plan(PreviewSpec(template: .named("mine"), app: "a"), stored: ["mine": mine]).template.name, "mine")
        XCTAssertThrowsError(try plan(PreviewSpec(template: .named("nope"), app: "a"))) {
            XCTAssertEqual(($0 as? BackendError)?.status, 404)
        }
    }

    func testV1TemplateIsRenderedAsItsBuiltinGridAndFillsContentDefaults() throws {
        var v1 = HeraldTemplate(name: "old", app: "a", layout: .compact)
        v1.title = "{sender} wrote"
        let n = HeraldNotification(app: "a", title: "", metadata: .object(["sender": .string("Ann")]))
        let p = try plan(PreviewSpec(template: .inline(v1), app: "a", data: n))
        XCTAssertEqual(p.notification.title, "Ann wrote")
        XCTAssertTrue(p.grid.usesGrid)
        XCTAssertEqual(p.grid.layout, .compact)
        XCTAssertFalse(p.usedSamples)
    }

    func testRealDataIsNotMixedWithSamples() throws {
        // A field the data lacks stays absent, so the preview shows the collapse a real notification would get.
        let n = HeraldNotification(app: "mail", title: "Hi", metadata: .object(["count": .number(7)]))
        let p = try plan(PreviewSpec(app: "mail", data: n), manifest: manifest)
        XCTAssertEqual(p.fields["count"], .number(7))
        XCTAssertNil(p.fields["sender"])
        XCTAssertEqual(p.notification.title, "Hi")
        XCTAssertTrue(p.actions.isEmpty)
    }

    func testActionRulesApplyToIssuerActions() throws {
        var t = HeraldTemplate.blank(name: "t", app: "mail")
        t.actionRules = [HeraldActionRule(match: "Mark as Read", relabel: "Done"),
                         HeraldActionRule(add: HeraldAction(id: "fu", label: "Follow up", kind: .shortcut, shortcut: "Follow Up"))]
        let p = try plan(PreviewSpec(template: .inline(t), app: "mail"), manifest: manifest)
        XCTAssertEqual(p.actions.map(\.action.label), ["Done", "Follow up"])
        XCTAssertEqual(p.actions.map(\.origin), [.issuer, .template])
    }

    func testTemplateExtraIsABindableField() throws {
        var t = HeraldTemplate.blank(name: "t", app: "a")
        t.extra = ["queue": "inbox"]
        let p = try plan(PreviewSpec(template: .inline(t), app: "a"))
        XCTAssertEqual(p.fields["extra.queue"], .text("inbox"))
    }

    func testInlineTemplateErrorsAreReportedWithTheCell() throws {
        var t = HeraldTemplate.blank(name: "t", app: "a")
        t.cells = [HeraldCell(id: "far", row: 9, col: 0, component: .text(HeraldTextComponent(binding: "{title}")))]
        XCTAssertThrowsError(try plan(PreviewSpec(template: .inline(t), app: "a"))) {
            let e = $0 as? BackendError
            XCTAssertEqual(e?.status, 400)
            XCTAssertTrue(e?.message.contains("far") == true, e?.message ?? "")
        }
    }

    func testSamplePreviewGetsAPlaceholderForAnImageTheSamplesLack() throws {
        let tag = "data:image/png;base64,AAAA"
        let m = HeraldManifest(app: "mail", fields: [HeraldField(key: "title", sample: .text("Hi")),
                                                       HeraldField(key: "thumb", type: .image)])
        var t = HeraldTemplate.blank(name: "t", app: "mail")
        t.cells = [HeraldCell(id: "pic", row: 0, col: 0, component: .image(HeraldImageComponent(binding: "{thumb}")))]
        let spec = PreviewSpec(template: .inline(t), app: "mail")
        let p = try PreviewPlan.make(spec, manifest: m, stored: { _ in nil }, placeholderImage: tag)
        XCTAssertEqual(p.fields["thumb"], .text(tag))
        // Built-in templates bind {image}: the notification's own image is filled in too.
        let b = try PreviewPlan.make(PreviewSpec(template: .named("builtin.imageLeft"), app: "mail"),
                                     manifest: m, stored: { _ in nil }, placeholderImage: tag)
        XCTAssertEqual(b.notification.image, tag)
        XCTAssertEqual(b.fields["image"], .text(tag))
        // A sample the manifest does declare is kept; real data never gets a placeholder.
        let declared = HeraldManifest(app: "mail", fields: [HeraldField(key: "image", type: .image, sample: .text("/tmp/x.png"))])
        let k = try PreviewPlan.make(PreviewSpec(template: .named("builtin.imageLeft"), app: "mail"),
                                     manifest: declared, stored: { _ in nil }, placeholderImage: tag)
        XCTAssertEqual(k.fields["image"], .text("/tmp/x.png"))
        let real = try PreviewPlan.make(PreviewSpec(template: .named("builtin.imageLeft"), app: "mail",
                                                    data: HeraldNotification(app: "mail", title: "Hi")),
                                        manifest: m, stored: { _ in nil }, placeholderImage: tag)
        XCTAssertNil(real.fields["image"])
        XCTAssertNil(real.notification.image)
    }
}
