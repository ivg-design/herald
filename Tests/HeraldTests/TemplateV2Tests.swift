import XCTest
@testable import HeraldCore

/// Herald 1.1 template model: components, grid, sizes, actions and rules, bindings, collapsing,
/// built-in grid templates, validation and the agent schema.
final class TemplateV2Tests: XCTestCase {
    private let dec = HeraldJSON.decoder()
    private let enc = HeraldJSON.encoder()

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try dec.decode(type, from: Data(json.utf8))
    }

    private func jsonObject<T: Encodable>(_ value: T) throws -> [String: Any] {
        let data = try enc.encode(value)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private let emailManifestJSON = """
    {"app":"webwatcher.email","appName":"WebWatcher Email","version":1,
     "fields":[{"key":"title","type":"text","required":true,"sample":"2 new from Acme Billing"},
               {"key":"sender","type":"text","sample":"Acme Billing"},{"key":"count","type":"number","sample":2},
               {"key":"receivedAt","type":"date","sample":"2026-10-01T14:14:00Z"},{"key":"url","type":"url"},
               {"key":"image","type":"image"},{"key":"flagged","type":"bool"},{"key":"labels","type":"list"},
               {"key":"subject"}],
     "actions":[{"id":"markRead","label":"Mark as Read","kind":"callback"},
                {"id":"archive","label":"Archive","kind":"callback","style":"destructive"}],
     "assets":[{"id":"bell","type":"rive","path":"/x/bell.riv","stateMachine":"Main","inputs":["count","hover"]}]}
    """

    private func manifest() throws -> HeraldManifest { try decode(HeraldManifest.self, emailManifestJSON) }

    // MARK: Components

    private func allComponents() -> [HeraldComponent] {
        let dismiss = HeraldAction(id: "dismiss", label: "Dismiss", kind: .dismiss, style: "cancel")
        return [
            .text(HeraldTextComponent(binding: "{title} - {count}", style: .title, maxLines: 2, color: "#34C759",
                                      fontSize: 14, weight: .bold, alignment: .center, markdown: true,
                                      emptyBehavior: .keep)),
            .image(HeraldImageComponent(binding: "{image}", fit: .fit, cornerRadius: 10, aspectRatio: 1.5, height: 80,
                                        emptyBehavior: .collapse)),
            .issuerIcon(HeraldIssuerIconComponent(size: 30, cornerRadius: 6, shape: .circle, emptyBehavior: .keep)),
            .timestamp(HeraldTimestampComponent(binding: "{receivedAt}", relative: true, style: .mono, color: "accent",
                                                fontSize: 10, emptyBehavior: .collapse)),
            .button(HeraldButtonComponent(action: HeraldAction(id: "go", label: "Go", kind: .url, url: "https://x"),
                                          style: "destructive")),
            .button(HeraldButtonComponent(actionRef: "markRead", emptyBehavior: .keep)),
            .actions(HeraldActionsComponent(source: .template, layout: .stack, maxVisible: 3, emptyBehavior: .keep)),
            .iconButton(HeraldIconButtonComponent(symbol: "xmark", action: dismiss, size: 20, color: "#888",
                                                  tooltip: "Close", emptyBehavior: .keep)),
            .iconButton(HeraldIconButtonComponent(symbol: "alarm", actionRef: "snooze")),
            .badge(HeraldBadgeComponent(binding: "{count}", color: "#FF3B30", textColor: "primary", emptyBehavior: .keep)),
            .progress(HeraldProgressComponent(binding: "{percent}", color: "accent", height: 6, emptyBehavior: .collapse)),
            .rive(HeraldRiveComponent(asset: "bell", path: "/x.riv", stateMachine: "Main", artboard: "A",
                                      inputBindings: ["count": "{count}", "hover": "hover"],
                                      action: HeraldAction(id: "open", label: "Open", kind: .url, url: "https://x"),
                                      loop: false, aspectRatio: 1, height: 40, emptyBehavior: .keep)),
            .rive(HeraldRiveComponent(path: "/y.riv", actionRef: "markRead")),
            .spacer,
        ]
    }

    func testEveryComponentRoundTripsWithTypeDiscriminator() throws {
        for c in allComponents() {
            let obj = try jsonObject(c)
            XCTAssertEqual(obj["type"] as? String, c.typeName, "\(c)")
            let data = try enc.encode(c)
            XCTAssertEqual(try dec.decode(HeraldComponent.self, from: data), c, "\(c)")
        }
        // Every type name is covered by the samples above.
        XCTAssertEqual(Set(allComponents().map(\.typeName)), Set(HeraldComponent.typeNames))
    }

    func testSpacerEncodesOnlyItsType() throws {
        XCTAssertEqual(String(data: try enc.encode(HeraldComponent.spacer), encoding: .utf8), "{\"type\":\"spacer\"}")
        XCTAssertEqual(try decode(HeraldComponent.self, "{\"type\":\"spacer\",\"ignored\":1}"), .spacer)
    }

    func testMinimalComponentsDecodeWithDocumentedDefaults() throws {
        guard case .text(let t) = try decode(HeraldComponent.self, "{\"type\":\"text\",\"binding\":\"{a}\"}") else { return XCTFail() }
        XCTAssertEqual(t.style, .body); XCTAssertNil(t.maxLines); XCTAssertNil(t.color); XCTAssertNil(t.emptyBehavior)
        XCTAssertTrue(t.rendersMarkdown)   // body markdown by default
        var caption = t; caption.style = .caption
        XCTAssertFalse(caption.rendersMarkdown)
        caption.markdown = true
        XCTAssertTrue(caption.rendersMarkdown)

        guard case .image(let i) = try decode(HeraldComponent.self, "{\"type\":\"image\"}") else { return XCTFail() }
        XCTAssertEqual(i.binding, "{image}"); XCTAssertEqual(i.fit, .cover); XCTAssertEqual(i.cornerRadius, 0)
        guard case .issuerIcon(let icon) = try decode(HeraldComponent.self, "{\"type\":\"issuerIcon\"}") else { return XCTFail() }
        XCTAssertEqual(icon.size, 22); XCTAssertEqual(icon.shape, .rounded)
        guard case .actions(let a) = try decode(HeraldComponent.self, "{\"type\":\"actions\"}") else { return XCTFail() }
        XCTAssertEqual(a.source, .merged); XCTAssertEqual(a.layout, .wrap); XCTAssertNil(a.maxVisible)
        guard case .timestamp(let ts) = try decode(HeraldComponent.self, "{\"type\":\"timestamp\"}") else { return XCTFail() }
        XCTAssertNil(ts.binding); XCTAssertFalse(ts.relative)
        guard case .rive(let r) = try decode(HeraldComponent.self, "{\"type\":\"rive\",\"asset\":\"b\"}") else { return XCTFail() }
        XCTAssertEqual(r.inputBindings, [:]); XCTAssertNil(r.loop)
    }

    func testBadComponentsAreRejected() {
        XCTAssertThrowsError(try decode(HeraldComponent.self, "{\"type\":\"carousel\"}")) { e in
            XCTAssertTrue("\(e)".contains("carousel"))
        }
        XCTAssertThrowsError(try decode(HeraldComponent.self, "{\"binding\":\"{a}\"}"))
        XCTAssertThrowsError(try decode(HeraldComponent.self, "{\"type\":\"text\"}"))
        XCTAssertThrowsError(try decode(HeraldComponent.self, "{\"type\":\"badge\"}"))
        XCTAssertThrowsError(try decode(HeraldComponent.self, "{\"type\":\"iconButton\"}"))
        XCTAssertThrowsError(try decode(HeraldComponent.self, "{\"type\":\"text\",\"binding\":\"x\",\"style\":\"huge\"}"))
    }

    func testButtonActionCanBeInlineOrAReference() throws {
        guard case .button(let ref) = try decode(HeraldComponent.self, "{\"type\":\"button\",\"action\":\"markRead\"}") else { return XCTFail() }
        XCTAssertEqual(ref.actionRef, "markRead"); XCTAssertNil(ref.action)
        guard case .button(let ref2) = try decode(HeraldComponent.self, "{\"type\":\"button\",\"actionRef\":\"archive\"}") else { return XCTFail() }
        XCTAssertEqual(ref2.actionRef, "archive")
        guard case .button(let inline) = try decode(
            HeraldComponent.self, "{\"type\":\"button\",\"action\":{\"label\":\"Follow up\",\"shortcut\":\"Make task\"}}") else { return XCTFail() }
        XCTAssertNil(inline.actionRef)
        XCTAssertEqual(inline.action?.kind, .shortcut); XCTAssertEqual(inline.action?.id, "follow-up")
    }

    func testComponentHelpers() {
        let text = HeraldComponent.text(HeraldTextComponent(binding: "{a} {b.c} {a}"))
        XCTAssertEqual(text.referencedTokens, ["a", "b.c"])
        XCTAssertEqual(text.bindingStrings, ["{a} {b.c} {a}"])
        let rive = HeraldComponent.rive(HeraldRiveComponent(asset: "x", inputBindings: ["count": "{n}", "hover": "hover", "p": "pressed"]))
        XCTAssertEqual(rive.referencedTokens, ["n"])
        let btn = HeraldComponent.button(HeraldButtonComponent(
            action: HeraldAction(id: "s", label: "Do {title}", kind: .shortcut, shortcut: "X", input: "{url}")))
        XCTAssertEqual(btn.referencedTokens, ["title", "url"])
        XCTAssertEqual(btn.inlineActions.count, 1)
        XCTAssertNil(HeraldComponent.spacer.emptyBehavior)
        XCTAssertEqual(HeraldComponent.spacer.typeName, "spacer")
    }

    // MARK: Sizes and grid

    func testSizeEncoding() throws {
        let sizes: [HeraldSize] = [.auto, .fill, .points(72), .points(12.5)]
        XCTAssertEqual(String(data: try enc.encode(sizes), encoding: .utf8), "[\"auto\",\"fill\",72,12.5]")
        XCTAssertEqual(try dec.decode([HeraldSize].self, from: enc.encode(sizes)), sizes)
        // The DESIGN example writes points as strings; those and a pt suffix decode too.
        XCTAssertEqual(try decode([HeraldSize].self, "[\"72\",\"fill\",56,\"10pt\",\" AUTO \"]"),
                       [.points(72), .fill, .points(56), .points(10), .auto])
        XCTAssertThrowsError(try decode([HeraldSize].self, "[\"wide\"]"))
        XCTAssertThrowsError(try decode([HeraldSize].self, "[true]"))
    }

    func testGridDefaultsAndAccessors() throws {
        let g = try decode(HeraldGrid.self, "{}")
        XCTAssertEqual(g.rows, 3); XCTAssertEqual(g.cols, 4)
        XCTAssertEqual(g.rowSizes, [.auto, .auto, .auto]); XCTAssertEqual(g.colSizes, Array(repeating: .fill, count: 4))
        XCTAssertEqual(g.gap, 8); XCTAssertEqual(g.padding, 14); XCTAssertEqual(g.width, 400)
        let fromSizes = try decode(HeraldGrid.self, "{\"colSizes\":[\"72\",\"fill\"],\"rowSizes\":[\"auto\"]}")
        XCTAssertEqual(fromSizes.cols, 2); XCTAssertEqual(fromSizes.rows, 1)
        XCTAssertEqual(g.rowSize(at: 99), .auto); XCTAssertEqual(g.colSize(at: -1), .fill)
        XCTAssertEqual(HeraldGrid.standard.colSizes, [.points(72), .fill, .fill, .points(56)])
        XCTAssertEqual(try dec.decode(HeraldGrid.self, from: enc.encode(HeraldGrid.standard)), .standard)
    }

    func testCellDecodesWithDefaultsAndRanges() throws {
        let c = try decode(HeraldCell.self, "{\"row\":1,\"col\":2,\"component\":{\"type\":\"spacer\"}}")
        XCTAssertEqual(c.id, "r1c2"); XCTAssertEqual(c.rowSpan, 1); XCTAssertEqual(c.colSpan, 1)
        XCTAssertEqual(c.align, .topLeading); XCTAssertEqual(c.padding, 0)
        XCTAssertThrowsError(try decode(HeraldCell.self, "{\"row\":1,\"col\":2}"))
        XCTAssertThrowsError(try decode(HeraldCell.self, "{\"row\":1,\"col\":2,\"align\":\"middle\",\"component\":{\"type\":\"spacer\"}}"))
        let wide = HeraldCell(id: "w", row: 1, col: 2, rowSpan: 5, colSpan: 5, component: .spacer)
        XCTAssertEqual(wide.rowRange(in: 3), 1..<3); XCTAssertEqual(wide.colRange(in: 4), 2..<4)
    }

    func testAlignHasEveryNinePointsWithAxes() {
        XCTAssertEqual(HeraldAlign.allCases.count, 9)
        XCTAssertEqual(HeraldAlign.topLeading.horizontal, .leading); XCTAssertEqual(HeraldAlign.topLeading.vertical, .top)
        XCTAssertEqual(HeraldAlign.center.horizontal, .center); XCTAssertEqual(HeraldAlign.center.vertical, .center)
        XCTAssertEqual(HeraldAlign.bottomTrailing.horizontal, .trailing); XCTAssertEqual(HeraldAlign.bottomTrailing.vertical, .bottom)
        XCTAssertEqual(HeraldAlign.bottom.horizontal, .center); XCTAssertEqual(HeraldAlign.trailing.vertical, .center)
    }

    // MARK: Template

    func testV1JSONStillDecodesAsLayoutVersion1() throws {
        let v1 = """
        {"name":"bid-won","app":"bidbot","layout":"hero","accentColor":"#34C759","showBody":false,"maxBodyLines":3,
         "title":"Won {amount}","buttons":[{"label":"Open","url":"https://x"}],"timeout":5,"snooze":true}
        """
        let t = try decode(HeraldTemplate.self, v1)
        XCTAssertEqual(t.layoutVersion, 1); XCTAssertNil(t.grid); XCTAssertEqual(t.cells, [])
        XCTAssertTrue(t.collapseEmpty); XCTAssertEqual(t.actionRules.count, 0); XCTAssertEqual(t.extra, [:])
        XCTAssertFalse(t.usesGrid)
        XCTAssertEqual(t.layout, .hero); XCTAssertEqual(t.buttons.first?.label, "Open")
        let minimal = try decode(HeraldTemplate.self, "{\"name\":\"n\",\"app\":\"a\"}")
        XCTAssertEqual(minimal, HeraldTemplate(name: "n", app: "a"))
        XCTAssertEqual(minimal.layoutVersion, 1)
        // A v1 template writes no grid, cells, rules or extra.
        let obj = try jsonObject(t)
        XCTAssertNil(obj["grid"]); XCTAssertNil(obj["cells"]); XCTAssertNil(obj["actionRules"]); XCTAssertNil(obj["extra"])
        XCTAssertEqual(obj["layoutVersion"] as? Int, 1)
        XCTAssertEqual(try dec.decode(HeraldTemplate.self, from: enc.encode(t)), t)
    }

    func testV2TemplateRoundTrips() throws {
        let t = try decode(HeraldTemplate.self, ComponentSchema.emailExample)
        XCTAssertEqual(t.layoutVersion, 2); XCTAssertTrue(t.usesGrid)
        XCTAssertEqual(t.grid?.colSizes, [.points(40), .fill, .fill, .auto])
        XCTAssertEqual(t.cells.count, 6); XCTAssertEqual(t.actionRules.count, 3)
        XCTAssertEqual(t.extra, ["queue": "inbox"])
        XCTAssertEqual(t.cell(withID: "count")?.align, .topTrailing)
        XCTAssertEqual(t.cell(withID: "icon")?.rowSpan, 2)
        let again = try dec.decode(HeraldTemplate.self, from: enc.encode(t))
        XCTAssertEqual(again, t)
        XCTAssertEqual(t.referencedTokens, ["title", "count", "sender", "subject", "receivedAt"])
    }

    func testGridWithoutLayoutVersionMeansV2() throws {
        let t = try decode(HeraldTemplate.self, "{\"name\":\"n\",\"app\":\"a\",\"grid\":{\"rows\":1,\"cols\":1},\"cells\":[]}")
        XCTAssertEqual(t.layoutVersion, 2)
        let blank = HeraldTemplate.blank(name: "b", app: "a")
        XCTAssertEqual(blank.layoutVersion, 2); XCTAssertEqual(blank.grid, .standard); XCTAssertTrue(blank.cells.isEmpty)
        XCTAssertEqual(try dec.decode(HeraldTemplate.self, from: enc.encode(blank)), blank)
    }

    func testV2TemplateStillResolvesV1Defaults() {
        var t = HeraldTemplate.blank(name: "t", app: "bidbot")
        t.title = "Won {amount}"; t.sound = "Ping"; t.buttons = [HeraldButton(label: "Open", url: "https://x")]
        let n = HeraldNotification(app: "bidbot", id: "1", title: "", metadata: .object(["amount": .number(42)]))
        let r = TemplateResolver.resolve(n, with: t)
        XCTAssertEqual(r.title, "Won 42"); XCTAssertEqual(r.sound, "Ping"); XCTAssertEqual(r.buttons?.count, 1)
    }

    // MARK: Actions

    private let issuer = [
        HeraldButton(label: "Mark as Read", callback: HeraldCallback()),
        HeraldButton(label: "Archive", style: "destructive", callback: HeraldCallback(payload: .object(["a": .number(1)]))),
        HeraldButton(label: "Open", url: "https://x"),
        HeraldButton(label: "Run", command: "echo hi"),
        HeraldButton(label: "Close"),
    ]

    func testIssuerButtonsMapToActions() {
        let list = ActionResolver.resolve(issuer: issuer, rules: [])
        XCTAssertEqual(list.map(\.id), ["mark-as-read", "archive", "open", "run", "close"])
        XCTAssertEqual(list.map(\.kind), [.callback, .callback, .url, .command, .dismiss])
        XCTAssertEqual(list[1].style, "destructive"); XCTAssertEqual(list[2].url, "https://x"); XCTAssertEqual(list[3].command, "echo hi")
        XCTAssertEqual(list[1].callback?.payload, .object(["a": .number(1)]))
        XCTAssertEqual(ActionResolver.resolve(issuer: [], rules: []), [])
        // Duplicate labels get distinct ids.
        let dup = ActionResolver.resolve(issuer: [HeraldButton(label: "Go"), HeraldButton(label: "Go")], rules: [])
        XCTAssertEqual(dup.map(\.id), ["go", "go-2"])
        // And a legacy button comes back for the kinds a v1 button can express.
        XCTAssertEqual(list[2].legacyButton, HeraldButton(label: "Open", url: "https://x"))
        XCTAssertEqual(list[3].legacyButton, HeraldButton(label: "Run", command: "echo hi"))
        XCTAssertNotNil(list[0].legacyButton?.callback)
        XCTAssertNil(HeraldAction(id: "s", label: "S", kind: .shortcut, shortcut: "X").legacyButton)
    }

    func testRuleHidesByIdOrLabelCaseInsensitive() {
        let r = ActionResolver.resolve(issuer: issuer, rules: [
            HeraldActionRule(match: "ARCHIVE", hide: true), HeraldActionRule(match: "mark-as-read", hide: true)])
        XCTAssertEqual(r.map(\.id), ["open", "run", "close"])
        // hide: false and an unknown match change nothing.
        XCTAssertEqual(ActionResolver.resolve(issuer: issuer, rules: [
            HeraldActionRule(match: "archive", hide: false), HeraldActionRule(match: "nope", hide: true)]).count, 5)
        XCTAssertEqual(ActionResolver.resolve(issuer: issuer, rules: [HeraldActionRule(match: "*", hide: true)]), [])
    }

    func testRuleRelabelsRestylesAndRepositions() {
        let r = ActionResolver.resolve(issuer: issuer, rules: [
            HeraldActionRule(match: "Archive", relabel: "Archive it", style: "cancel", position: 0)])
        XCTAssertEqual(r.map(\.label), ["Archive it", "Mark as Read", "Open", "Run", "Close"])
        XCTAssertEqual(r[0].style, "cancel"); XCTAssertEqual(r[0].id, "archive"); XCTAssertEqual(r[0].kind, .callback)
        // Position is clamped; relabel to empty is ignored; a restyle to "" clears the style.
        let r2 = ActionResolver.resolve(issuer: issuer, rules: [
            HeraldActionRule(match: "mark-as-read", position: 99), HeraldActionRule(match: "archive", relabel: "", style: "")])
        XCTAssertEqual(r2.map(\.id), ["archive", "open", "run", "close", "mark-as-read"])
        XCTAssertEqual(r2[0].label, "Archive"); XCTAssertNil(r2[0].style)
        // A wildcard restyles everything.
        XCTAssertTrue(ActionResolver.resolve(issuer: issuer, rules: [HeraldActionRule(match: "*", style: "cancel")]).allSatisfy { $0.style == "cancel" })
    }

    func testRuleAddsTemplateActionsAndReplacesSameId() {
        let follow = HeraldAction(id: "shortcut-followup", label: "Follow up", kind: .shortcut,
                                  shortcut: "Create follow-up", input: "{title}\n{url}")
        let detailed = ActionResolver.resolveDetailed(issuer: issuer, rules: [HeraldActionRule(add: follow)])
        XCTAssertEqual(detailed.count, 6)
        XCTAssertEqual(detailed.last?.action, follow); XCTAssertEqual(detailed.last?.origin, .template)
        XCTAssertTrue(detailed.dropLast().allSatisfy { $0.origin == .issuer })

        // Insert at a position; the id defaults to a slug of the label.
        let r = ActionResolver.resolve(issuer: issuer, rules: [
            HeraldActionRule(position: 1, add: HeraldAction(id: "", label: "Say Hi", kind: .command, command: "say hi"))])
        XCTAssertEqual(r.map(\.id), ["mark-as-read", "say-hi", "archive", "open", "run", "close"])

        // Adding an id that exists replaces that action in place and makes it the template's.
        let replace = ActionResolver.resolveDetailed(issuer: issuer, rules: [
            HeraldActionRule(add: HeraldAction(id: "open", label: "Open mine", kind: .script, script: "open.sh"))])
        XCTAssertEqual(replace.count, 5)
        XCTAssertEqual(replace[2].action.label, "Open mine"); XCTAssertEqual(replace[2].origin, .template)

        // With a match, `position` moves the match; the added action is appended.
        let both = ActionResolver.resolve(issuer: issuer, rules: [
            HeraldActionRule(match: "close", position: 0, add: HeraldAction(id: "z", label: "Z", kind: .dismiss))])
        XCTAssertEqual(both.map(\.id), ["close", "mark-as-read", "archive", "open", "run", "z"])
    }

    func testRulesRunInOrder() {
        let r = ActionResolver.resolve(issuer: issuer, rules: [
            HeraldActionRule(add: HeraldAction(id: "x", label: "X", kind: .dismiss)),
            HeraldActionRule(match: "*", hide: true),
            HeraldActionRule(add: HeraldAction(id: "y", label: "Y", kind: .snooze, snoozeMinutes: 30)),
            HeraldActionRule(match: "y", relabel: "Why")])
        XCTAssertEqual(r.map(\.id), ["y"]); XCTAssertEqual(r.first?.label, "Why"); XCTAssertEqual(r.first?.snoozeMinutes, 30)
    }

    func testDeclaredIssuerIdsDriveRuleMatching() throws {
        let m = try manifest()
        let buttons = [HeraldButton(label: "mark as read", callback: HeraldCallback()),   // payload label, different case
                       HeraldButton(label: "Archive", callback: HeraldCallback()),
                       HeraldButton(label: "Extra", url: "https://x")]
        let ids = ActionResolver.issuerIDs(for: buttons, manifest: m)
        XCTAssertEqual(ids, ["markRead", "archive", ""])
        let r = ActionResolver.resolve(issuer: buttons, ids: ids, rules: [
            HeraldActionRule(match: "markRead", relabel: "Read"), HeraldActionRule(match: "archive", hide: true)])
        XCTAssertEqual(r.map(\.id), ["markRead", "extra"]); XCTAssertEqual(r.first?.label, "Read")
        // The manifest's own actions resolve with the manifest's ids.
        XCTAssertEqual(ActionResolver.resolve(issuer: m.actions, ids: m.actionIDs, rules: []).map(\.id), ["markRead", "archive"])
        XCTAssertEqual(ActionResolver.issuerIDs(for: buttons, manifest: nil), ["", "", ""])
        // Already-built actions can be resolved directly.
        let direct = ActionResolver.resolveDetailed(
            issuerActions: [HeraldAction(id: "a", label: "A", kind: .url, url: "https://x")], rules: [HeraldActionRule(match: "a", relabel: "B")])
        XCTAssertEqual(direct.first?.action.label, "B"); XCTAssertEqual(direct.first?.origin, .issuer)
    }

    func testActionDecodingIsLenientButStrictAboutKind() throws {
        let a = try decode(HeraldAction.self, "{\"label\":\"Open\",\"url\":\"https://x\"}")
        XCTAssertEqual(a.kind, .url); XCTAssertEqual(a.id, "open")
        XCTAssertEqual(try decode(HeraldAction.self, "{\"id\":\"s\",\"shortcut\":\"X\"}").label, "s")
        XCTAssertEqual(try decode(HeraldAction.self, "{\"label\":\"c\",\"callback\":{}}").kind, .callback)
        XCTAssertEqual(try decode(HeraldAction.self, "{\"label\":\"c\",\"kind\":\"snooze\",\"snoozeMinutes\":5}").snoozeMinutes, 5)
        XCTAssertThrowsError(try decode(HeraldAction.self, "{\"label\":\"nothing\"}"))
        XCTAssertThrowsError(try decode(HeraldAction.self, "{\"kind\":\"dismiss\"}"))
        XCTAssertThrowsError(try decode(HeraldAction.self, "{\"label\":\"x\",\"kind\":\"teleport\"}"))
        for kind in HeraldActionKind.allCases {   // every kind round-trips
            let action = HeraldAction(id: "i", label: "L", kind: kind, style: "default", url: "https://x",
                                      callback: HeraldCallback(url: "http://127.0.0.1:1", payload: .string("p")),
                                      command: "c", script: "s.sh", shortcut: "S", input: "{title}", snoozeMinutes: 7)
            XCTAssertEqual(try dec.decode(HeraldAction.self, from: enc.encode(action)), action)
        }
        let rule = HeraldActionRule(match: "m", hide: true, relabel: "r", style: "cancel", position: 2,
                                    add: HeraldAction(id: "i", label: "L", kind: .dismiss))
        XCTAssertEqual(try dec.decode(HeraldActionRule.self, from: enc.encode(rule)), rule)
        XCTAssertEqual(try decode(HeraldActionRule.self, "{}"), HeraldActionRule())
    }

    func testShortcutInputAndMergedPayload() throws {
        let fields: [String: HeraldFieldValue] = ["title": .text("Hello"), "url": .text("https://x"), "count": .number(2)]
        let withInput = HeraldAction(id: "f", label: "F", kind: .shortcut, shortcut: "S", input: "{title}\n{url}\n{missing}|")
        XCTAssertEqual(ActionResolver.inputText(for: withInput, fields: fields), "Hello\nhttps://x\n|")
        XCTAssertNil(ActionResolver.inputText(for: HeraldAction(id: "f", label: "F", kind: .shortcut, shortcut: "S"), fields: fields))
        XCTAssertNil(ActionResolver.inputText(for: HeraldAction(id: "f", label: "F", kind: .shortcut, shortcut: "S", input: ""), fields: fields))

        let n = HeraldNotification(app: "a", id: "n1", title: "Hello", metadata: .object(["k": .string("v")]))
        let payload = ActionResolver.mergedPayload(notification: n, fields: fields, extra: ["queue": "inbox"], action: withInput)
        guard case .object(let o) = payload else { return XCTFail() }
        XCTAssertEqual(o["app"], .string("a")); XCTAssertEqual(o["id"], .string("n1"))
        XCTAssertEqual(o["action"], .object(["id": .string("f"), "label": .string("F"), "kind": .string("shortcut")]))
        guard case .object(let f)? = o["fields"] else { return XCTFail() }
        XCTAssertEqual(f["count"], .number(2)); XCTAssertEqual(f["title"], .string("Hello"))
        XCTAssertEqual(o["extra"], .object(["queue": .string("inbox")]))
        guard case .object(let note)? = o["notification"] else { return XCTFail() }
        XCTAssertEqual(note["title"], .string("Hello"))
        XCTAssertEqual(note["metadata"], .object(["k": .string("v")]))
    }

    // MARK: Bindings

    func testBindReturnsNilWhenEveryTokenIsAbsent() {
        let f: [String: HeraldFieldValue] = ["title": .text("Hi"), "count": .number(2), "blank": .text("  "),
                                             "none": .list([]), "on": .bool(true), "tags": .list(["a", "b"])]
        XCTAssertNil(TemplateResolver.bind("{nope}", fields: f))
        XCTAssertNil(TemplateResolver.bind("{nope} - {alsoNope}", fields: f))
        XCTAssertNil(TemplateResolver.bind("{blank}", fields: f))         // blank counts as absent
        XCTAssertNil(TemplateResolver.bind("{none}", fields: f))          // empty list too
        XCTAssertEqual(TemplateResolver.bind("{title}", fields: f), "Hi")
        XCTAssertEqual(TemplateResolver.bind("{title} - {count}", fields: f), "Hi - 2")
        // One present token is enough; absent ones become empty and the ends are trimmed.
        XCTAssertEqual(TemplateResolver.bind("{title} {nope}", fields: f), "Hi")
        XCTAssertEqual(TemplateResolver.bind("{nope} {title}", fields: f), "Hi")
        XCTAssertEqual(TemplateResolver.bind("{on}/{tags}", fields: f), "true/a, b")
        // A binding without tokens is a literal.
        XCTAssertEqual(TemplateResolver.bind("Hello", fields: [:]), "Hello")
        XCTAssertNil(TemplateResolver.bind("", fields: f)); XCTAssertNil(TemplateResolver.bind("   ", fields: f))
        // Braces that are not tokens stay.
        XCTAssertEqual(TemplateResolver.bind("{\"a\": 1} {title}", fields: f), "{\"a\": 1} Hi")
        XCTAssertEqual(TemplateResolver.bind("{count}", fields: ["count": .number(2.5)]), "2.5")
        XCTAssertEqual(TemplateResolver.bind("{n}", fields: ["n": .number(0)]), "0")   // zero is present
        XCTAssertEqual(TemplateResolver.fill("a{x}b{title}", fields: f), "ab" + "Hi")
    }

    func testFieldsPutTopLevelBeforeMetadata() throws {
        let n = HeraldNotification(
            app: "webwatcher.email", id: "n1", title: "Top title", subtitle: "Sub", body: "", image: "/p.png", url: "https://x",
            priority: "high",
            metadata: .object(["title": .string("meta title"), "sender": .string("Acme"), "count": .number(3),
                               "flagged": .bool(true), "labels": .array([.string("a"), .number(2), .null, .object([:])]),
                               "customer": .object(["name": .string("Bo"), "tier": .object(["n": .number(1)])]),
                               "empty": .string(""), "nothing": .null, "flat": .string("  ")]))
        let f = TemplateResolver.fields(for: n, manifest: nil)
        XCTAssertEqual(f["title"], .text("Top title"))           // top-level wins over metadata
        XCTAssertEqual(f["subtitle"], .text("Sub")); XCTAssertEqual(f["image"], .text("/p.png"))
        XCTAssertEqual(f["url"], .text("https://x")); XCTAssertEqual(f["priority"], .text("high"))
        XCTAssertEqual(f["app"], .text("webwatcher.email")); XCTAssertEqual(f["id"], .text("n1"))
        XCTAssertNil(f["body"])                                   // blank is absent
        XCTAssertEqual(f["sender"], .text("Acme")); XCTAssertEqual(f["count"], .number(3)); XCTAssertEqual(f["flagged"], .bool(true))
        XCTAssertEqual(f["labels"], .list(["a", "2"]))
        XCTAssertEqual(f["customer.name"], .text("Bo")); XCTAssertEqual(f["customer.tier.n"], .number(1))
        XCTAssertNil(f["empty"]); XCTAssertNil(f["nothing"]); XCTAssertNil(f["flat"]); XCTAssertNil(f["appName"])
        XCTAssertEqual(TemplateResolver.bind("{customer.name} ({count})", fields: f), "Bo (3)")
    }

    func testFieldsUseManifestForNamesAndCoercionButNotSamples() throws {
        let m = try manifest()
        let n = HeraldNotification(app: "webwatcher.email", title: "T", metadata: .object([
            "count": .string("4"), "flagged": .string("yes"), "labels": .string("x"), "sender": .string("S")]))
        let f = TemplateResolver.fields(for: n, manifest: m)
        XCTAssertEqual(f["appName"], .text("WebWatcher Email"))
        XCTAssertEqual(f["count"], .number(4)); XCTAssertEqual(f["flagged"], .bool(true))
        XCTAssertEqual(f["labels"], .text("x"))                 // list fields are not split
        XCTAssertNil(f["receivedAt"])                            // the manifest's sample is NOT applied
        XCTAssertNil(f["image"])
        // Extra values and the delivery time are opt-in.
        let date = Date(timeIntervalSince1970: 1_790_000_000)
        let g = TemplateResolver.fields(for: n, manifest: nil, extra: ["queue": "inbox", "": "x", "blank": " "], deliveredAt: date)
        XCTAssertEqual(g["extra.queue"], .text("inbox")); XCTAssertNil(g["extra.blank"])
        XCTAssertEqual(g["deliveredAt"], .text(ISODate.string(from: date)))
        XCTAssertEqual(TemplateResolver.date(from: try XCTUnwrap(TemplateResolver.bind("{deliveredAt}", fields: g)))?.timeIntervalSince1970 ?? 0,
                       1_790_000_000, accuracy: 0.01)
    }

    func testSampleFieldsComeFromTheManifest() throws {
        let m = try manifest()
        let s = TemplateResolver.sampleFields(manifest: m)
        XCTAssertEqual(s["title"], .text("2 new from Acme Billing")); XCTAssertEqual(s["count"], .number(2))
        XCTAssertEqual(s["receivedAt"], .text("2026-10-01T14:14:00Z"))
        XCTAssertEqual(s["app"], .text("webwatcher.email")); XCTAssertEqual(s["appName"], .text("WebWatcher Email"))
        // Declared without a sample: a stand-in by type; an image gets none.
        XCTAssertEqual(s["url"], .text("https://example.com")); XCTAssertEqual(s["flagged"], .bool(true))
        XCTAssertEqual(s["labels"], .list(["One", "Two", "Three"])); XCTAssertEqual(s["subject"], .text("Subject"))
        XCTAssertNil(s["image"])
        XCTAssertNil(s["subtitle"])                              // undeclared: absent
        let generic = TemplateResolver.sampleFields(manifest: nil)
        XCTAssertNotNil(generic["title"]); XCTAssertNotNil(generic["subtitle"]); XCTAssertNotNil(generic["body"])
        XCTAssertEqual(TemplateResolver.date(from: "1790000000")?.timeIntervalSince1970, 1_790_000_000)
        XCTAssertEqual(TemplateResolver.date(from: "1790000000000")?.timeIntervalSince1970, 1_790_000_000)
        XCTAssertNil(TemplateResolver.date(from: "soon"))
    }

    // MARK: hasContent and collapsing

    private func acts(_ ids: [(String, HeraldActionOrigin)]) -> [HeraldResolvedAction] {
        ids.map { HeraldResolvedAction(action: HeraldAction(id: $0.0, label: $0.0, kind: .dismiss), origin: $0.1) }
    }

    func testHasContentPerComponent() {
        let f: [String: HeraldFieldValue] = ["title": .text("T"), "count": .number(2)]
        let none: [HeraldResolvedAction] = []
        XCTAssertTrue(HeraldComponent.text(HeraldTextComponent(binding: "{title}")).hasContent(fields: f, actions: none))
        XCTAssertFalse(HeraldComponent.text(HeraldTextComponent(binding: "{subtitle}")).hasContent(fields: f, actions: none))
        XCTAssertFalse(HeraldComponent.image(HeraldImageComponent()).hasContent(fields: f, actions: none))
        XCTAssertTrue(HeraldComponent.image(HeraldImageComponent()).hasContent(fields: ["image": .text("/p.png")], actions: none))
        XCTAssertTrue(HeraldComponent.badge(HeraldBadgeComponent(binding: "{count}")).hasContent(fields: f, actions: none))
        XCTAssertFalse(HeraldComponent.progress(HeraldProgressComponent(binding: "{percent}")).hasContent(fields: f, actions: none))
        XCTAssertTrue(HeraldComponent.issuerIcon(HeraldIssuerIconComponent()).hasContent(fields: [:], actions: none))
        XCTAssertTrue(HeraldComponent.spacer.hasContent(fields: [:], actions: none))
        // A timestamp with no binding always has the delivery time; with a binding it needs the token.
        XCTAssertTrue(HeraldComponent.timestamp(HeraldTimestampComponent()).hasContent(fields: [:], actions: none))
        XCTAssertTrue(HeraldComponent.timestamp(HeraldTimestampComponent(binding: " ")).hasContent(fields: [:], actions: none))
        XCTAssertFalse(HeraldComponent.timestamp(HeraldTimestampComponent(binding: "{receivedAt}")).hasContent(fields: f, actions: none))
        // Buttons: inline always; a reference needs the action in the list.
        let inline = HeraldComponent.button(HeraldButtonComponent(action: HeraldAction(id: "x", label: "X", kind: .dismiss)))
        XCTAssertTrue(inline.hasContent(fields: f, actions: none))
        let ref = HeraldComponent.button(HeraldButtonComponent(actionRef: "markRead"))
        XCTAssertFalse(ref.hasContent(fields: f, actions: none))
        XCTAssertFalse(ref.hasContent(fields: f, actions: acts([("archive", .issuer)])))
        XCTAssertTrue(ref.hasContent(fields: f, actions: acts([("markRead", .issuer)])))
        XCTAssertFalse(HeraldComponent.iconButton(HeraldIconButtonComponent(symbol: "x")).hasContent(fields: f, actions: none))
        // `actions` looks at its source.
        let merged = HeraldComponent.actions(HeraldActionsComponent(source: .merged))
        let issuerOnly = HeraldComponent.actions(HeraldActionsComponent(source: .issuer))
        let templateOnly = HeraldComponent.actions(HeraldActionsComponent(source: .template))
        let mixed = acts([("a", .issuer)])
        XCTAssertFalse(merged.hasContent(fields: f, actions: none))
        XCTAssertTrue(merged.hasContent(fields: f, actions: mixed)); XCTAssertTrue(issuerOnly.hasContent(fields: f, actions: mixed))
        XCTAssertFalse(templateOnly.hasContent(fields: f, actions: mixed))
        XCTAssertTrue(templateOnly.hasContent(fields: f, actions: acts([("t", .template)])))
        XCTAssertFalse(HeraldComponent.rive(HeraldRiveComponent()).hasContent(fields: f, actions: none))
        XCTAssertTrue(HeraldComponent.rive(HeraldRiveComponent(asset: "bell")).hasContent(fields: f, actions: none))
    }

    /// 3 x 2: title | subtitle / body (both columns) / actions (both columns).
    private func smallTemplate(collapseEmpty: Bool = true, bodyBehavior: HeraldEmptyBehavior? = nil) -> HeraldTemplate {
        var t = HeraldTemplate(
            name: "t", app: "a", grid: HeraldGrid(rows: 3, cols: 2),
            cells: [
                HeraldCell(id: "title", row: 0, col: 0, component: .text(HeraldTextComponent(binding: "{title}"))),
                HeraldCell(id: "sub", row: 0, col: 1, component: .text(HeraldTextComponent(binding: "{subtitle}"))),
                HeraldCell(id: "body", row: 1, col: 0, colSpan: 2,
                           component: .text(HeraldTextComponent(binding: "{body}", emptyBehavior: bodyBehavior))),
                HeraldCell(id: "actions", row: 2, col: 0, colSpan: 2, component: .actions(HeraldActionsComponent())),
            ])
        t.collapseEmpty = collapseEmpty
        return t
    }

    func testEmptyComponentsCollapseTheirRowsAndColumns() {
        let t = smallTemplate()
        let plan = t.plan(fields: ["title": .text("T")], actions: [])
        XCTAssertEqual(plan.collapsedCells, ["sub", "body", "actions"])
        XCTAssertEqual(plan.collapsedRows, [1, 2])
        XCTAssertEqual(plan.collapsedCols, [1])           // nothing live is left in column 1
        XCTAssertTrue(plan.isCollapsed(cell: "sub")); XCTAssertFalse(plan.isCollapsed(cell: "title"))

        // With the body and an action present, only the empty subtitle goes.
        let full = t.plan(fields: ["title": .text("T"), "body": .text("B")], actions: acts([("go", .issuer)]))
        XCTAssertEqual(full.collapsedCells, ["sub"]); XCTAssertEqual(full.collapsedRows, []); XCTAssertEqual(full.collapsedCols, [])
        // A live cell spanning both columns keeps column 1 alive even when the subtitle is gone.
        XCTAssertEqual(t.plan(fields: ["title": .text("T"), "body": .text("B")], actions: []).collapsedCols, [])
    }

    func testKeepLeavesEmptyComponentsInPlace() {
        let t = smallTemplate(collapseEmpty: false)
        let plan = t.plan(fields: ["title": .text("T")], actions: [])
        XCTAssertEqual(plan, HeraldGridPlan())            // nothing collapses at all
        // A component can still opt in to collapsing; its row goes with it.
        let mixed = smallTemplate(collapseEmpty: false, bodyBehavior: .collapse)
        let p2 = mixed.plan(fields: ["title": .text("T")], actions: [])
        XCTAssertEqual(p2.collapsedCells, ["body"]); XCTAssertEqual(p2.collapsedRows, [1]); XCTAssertEqual(p2.collapsedCols, [])
        // And the other way round: collapse by default, one component keeps its space.
        let keepBody = smallTemplate(collapseEmpty: true, bodyBehavior: .keep)
        let p3 = keepBody.plan(fields: ["title": .text("T")], actions: [])
        XCTAssertEqual(p3.collapsedCells, ["sub", "actions"]); XCTAssertEqual(p3.collapsedRows, [2]); XCTAssertEqual(p3.collapsedCols, [])
    }

    func testRowsWithNoCellsCollapseOnlyWhenCollapseEmptyIsOn() {
        func make(_ collapse: Bool) -> HeraldTemplate {
            var t = HeraldTemplate(name: "t", app: "a", grid: HeraldGrid(rows: 3, cols: 1), cells: [
                HeraldCell(id: "a", row: 0, col: 0, component: .text(HeraldTextComponent(binding: "{title}"))),
                HeraldCell(id: "c", row: 2, col: 0, component: .text(HeraldTextComponent(binding: "{title}")))])
            t.collapseEmpty = collapse
            return t
        }
        let f: [String: HeraldFieldValue] = ["title": .text("T")]
        XCTAssertEqual(make(true).plan(fields: f, actions: []).collapsedRows, [1])
        XCTAssertEqual(make(false).plan(fields: f, actions: []).collapsedRows, [])
    }

    func testASpanningCellKeepsEveryTrackItCoversAlive() {
        let t = HeraldTemplate(name: "t", app: "a", grid: HeraldGrid(rows: 3, cols: 2), cells: [
            HeraldCell(id: "image", row: 0, col: 0, rowSpan: 3, component: .image(HeraldImageComponent())),
            HeraldCell(id: "title", row: 0, col: 1, component: .text(HeraldTextComponent(binding: "{title}"))),
            HeraldCell(id: "body", row: 1, col: 1, component: .text(HeraldTextComponent(binding: "{body}"))),
            HeraldCell(id: "meta", row: 2, col: 1, component: .text(HeraldTextComponent(binding: "{meta}")))])
        // The image covers all three rows, so none of them collapses while it is there.
        let p = t.plan(fields: ["image": .text("/p.png"), "title": .text("T")], actions: [])
        XCTAssertEqual(p.collapsedRows, []); XCTAssertEqual(p.collapsedCols, [])
        // Only the image: the text column has nothing left and goes; the rows stay for the image.
        let p2 = t.plan(fields: ["image": .text("/p.png")], actions: [])
        XCTAssertEqual(p2.collapsedRows, []); XCTAssertEqual(p2.collapsedCols, [1])
        // No image: its column goes, and so do the rows with nothing in them.
        let p3 = t.plan(fields: ["title": .text("T")], actions: [])
        XCTAssertEqual(p3.collapsedCols, [0]); XCTAssertEqual(p3.collapsedRows, [1, 2])
        // A wide cell keeps the column it spans alive even though its own first column has other content.
        let wide = HeraldTemplate(name: "t", app: "a", grid: HeraldGrid(rows: 2, cols: 2), cells: [
            HeraldCell(id: "a", row: 0, col: 0, component: .text(HeraldTextComponent(binding: "{a}"))),
            HeraldCell(id: "b", row: 1, col: 0, colSpan: 2, component: .text(HeraldTextComponent(binding: "{b}")))])
        XCTAssertEqual(wide.plan(fields: ["a": .text("1"), "b": .text("2")], actions: []).collapsedCols, [])
        XCTAssertEqual(wide.plan(fields: ["a": .text("1")], actions: []).collapsedCols, [1])
        // A v1 template has no grid to collapse.
        XCTAssertEqual(HeraldTemplate(name: "n", app: "a").plan(emptyCells: ["x"]), HeraldGridPlan())
    }

    // MARK: Built-in templates

    func testFourBuiltinsExistAndAreValidGridTemplates() {
        XCTAssertEqual(BuiltinTemplates.names, ["builtin.imageLeft", "builtin.imageRight", "builtin.hero", "builtin.compact"])
        let all = BuiltinTemplates.all(app: "bidbot")
        XCTAssertEqual(all.map(\.name), BuiltinTemplates.names)
        for t in all {
            XCTAssertEqual(t.app, "bidbot"); XCTAssertTrue(t.usesGrid); XCTAssertEqual(t.layoutVersion, 2)
            XCTAssertTrue(t.collapseEmpty)
            let issues = t.validate()
            XCTAssertEqual(issues, [], "\(t.name): \(issues)")
            XCTAssertEqual(t.grid?.width, 380)
            XCTAssertEqual(try? dec.decode(HeraldTemplate.self, from: enc.encode(t)), t, t.name)
            XCTAssertEqual(BuiltinTemplates.named(t.name, app: "bidbot"), t)
        }
        XCTAssertNil(BuiltinTemplates.named("builtin.sideways")); XCTAssertNil(BuiltinTemplates.named("imageLeft"))
        XCTAssertTrue(BuiltinTemplates.isBuiltin("builtin.hero")); XCTAssertFalse(BuiltinTemplates.isBuiltin("hero"))
        XCTAssertEqual(BuiltinTemplates.layout(forName: "builtin.compact"), .compact)
        XCTAssertEqual(BuiltinTemplates.named("builtin.hero")?.layout, .hero)
    }

    func testBuiltinLooksMatchTheV1Structure() throws {
        let left = BuiltinTemplates.template(layout: .imageLeft)
        XCTAssertEqual(left.grid?.colSizes.first, .points(72))
        XCTAssertEqual(left.cell(withID: "image")?.col, 0); XCTAssertEqual(left.cell(withID: "image")?.rowSpan, 3)
        let right = BuiltinTemplates.template(layout: .imageRight)
        // Right: text | image | time | close and icon (the time sits beside the close button, so it is not between
        // the text and the image).
        XCTAssertEqual(right.cell(withID: "image")?.col, 1); XCTAssertEqual(right.cell(withID: "title")?.col, 0)
        XCTAssertEqual(right.grid?.colSizes[1], .points(72))
        let hero = BuiltinTemplates.template(layout: .hero)
        guard case .image(let hi)? = hero.cell(withID: "image")?.component else { return XCTFail() }
        XCTAssertEqual(hi.aspectRatio ?? 0, 16.0 / 9.0, accuracy: 0.0001)
        XCTAssertEqual(hero.cell(withID: "image")?.colSpan, 4); XCTAssertEqual(hero.grid?.rows, 5)
        let compact = BuiltinTemplates.template(layout: .compact)
        XCTAssertNil(compact.cell(withID: "image")); XCTAssertNil(compact.cell(withID: "body")); XCTAssertNil(compact.cell(withID: "subtitle"))
        guard case .text(let title)? = compact.cell(withID: "title")?.component else { return XCTFail() }
        XCTAssertEqual(title.maxLines, 1)
        // Every layout has a title, a dismiss button, an action row and the v1 timestamp.
        for t in BuiltinTemplates.all() {
            for id in ["title", "close", "actions", "time"] { XCTAssertNotNil(t.cell(withID: id), "\(t.name) \(id)") }
            guard case .iconButton(let b)? = t.cell(withID: "close")?.component else { return XCTFail() }
            XCTAssertEqual(b.action?.kind, .dismiss)
        }
    }

    func testBuiltinFlagsMatchTheV1Flags() {
        let t = BuiltinTemplates.template(layout: .imageLeft, accentColor: "#34C759", showSubtitle: false,
                                          showBody: true, showTimestamp: false, maxBodyLines: 3)
        XCTAssertNil(t.cell(withID: "subtitle")); XCTAssertNil(t.cell(withID: "time")); XCTAssertNotNil(t.cell(withID: "body"))
        guard case .text(let body)? = t.cell(withID: "body")?.component else { return XCTFail() }
        XCTAssertEqual(body.maxLines, 3); XCTAssertTrue(body.rendersMarkdown)
        guard case .text(let title)? = t.cell(withID: "title")?.component else { return XCTFail() }
        XCTAssertEqual(title.color, "#34C759")
        XCTAssertEqual(t.accentColor, "#34C759"); XCTAssertEqual(t.maxBodyLines, 3)
        XCTAssertTrue(BuiltinTemplates.template(layout: .imageLeft, app: "a", accentColor: "#34C759", showSubtitle: false,
                                                showBody: true, showTimestamp: false, maxBodyLines: 3).validate().isEmpty)
        // Without an accent the title has no colour (primary, as in v1); a bad accent is ignored.
        guard case .text(let plain)? = BuiltinTemplates.template(layout: .imageLeft, accentColor: "green").cell(withID: "title")?.component else { return XCTFail() }
        XCTAssertNil(plain.color)
        XCTAssertNil(BuiltinTemplates.template(layout: .imageLeft, showBody: false).cell(withID: "body"))
    }

    func testBuiltinCollapsesLikeV1() {
        // A title-only notification: no image column, no subtitle/body rows, no action row.
        let t = BuiltinTemplates.template(layout: .imageLeft)
        let f = TemplateResolver.fields(for: HeraldNotification(app: "a", title: "T"))
        let plan = t.plan(fields: f, actions: [])
        XCTAssertEqual(plan.collapsedCells, ["image", "subtitle", "body", "actions"])
        XCTAssertEqual(plan.collapsedRows, [3]); XCTAssertEqual(plan.collapsedCols, [0])
        // With an image, subtitle, body and two buttons everything shows.
        let n = HeraldNotification(app: "a", title: "T", subtitle: "S", body: "B", image: "/p.png")
        let list = ActionResolver.resolveDetailed(issuer: [HeraldButton(label: "Open", url: "https://x")], rules: [])
        let full = t.plan(fields: TemplateResolver.fields(for: n), actions: list)
        XCTAssertEqual(full.collapsedCells, []); XCTAssertEqual(full.collapsedRows, []); XCTAssertEqual(full.collapsedCols, [])
        // Turning collapse off keeps the title-only banner's blank rows and columns.
        var keep = t; keep.collapseEmpty = false
        XCTAssertEqual(keep.plan(fields: f, actions: []), HeraldGridPlan())
    }

    func testV1TemplateAndNotificationMapToBuiltinGrids() {
        var v1 = HeraldTemplate(name: "bid-won", app: "bidbot", layout: .hero)
        v1.accentColor = "#112233"; v1.showBody = false; v1.sound = "Ping"; v1.buttons = [HeraldButton(label: "Open", url: "https://x")]
        let g = BuiltinTemplates.gridTemplate(for: v1)
        XCTAssertTrue(g.usesGrid); XCTAssertEqual(g.name, "bid-won"); XCTAssertEqual(g.app, "bidbot")
        XCTAssertEqual(g.sound, "Ping"); XCTAssertEqual(g.buttons.count, 1); XCTAssertEqual(g.grid?.rows, 5)
        XCTAssertNil(g.cell(withID: "body")); XCTAssertNotNil(g.cell(withID: "image"))
        XCTAssertEqual(g.cell(withID: "title")?.component.typeName, "text")
        // A grid template is returned unchanged.
        let own = HeraldTemplate.blank(name: "mine", app: "a")
        XCTAssertEqual(BuiltinTemplates.gridTemplate(for: own), own)

        let n = HeraldNotification(app: "a", title: "T", layout: .compact, accentColor: "#FF0000", showTimestamp: false, maxBodyLines: 99)
        let fromN = BuiltinTemplates.gridTemplate(for: n)
        XCTAssertEqual(fromN.name, "builtin.compact"); XCTAssertNil(fromN.cell(withID: "time"))
        let plainN = BuiltinTemplates.gridTemplate(for: HeraldNotification(app: "a", title: "T", maxBodyLines: 99))
        XCTAssertEqual(plainN.name, "builtin.imageLeft")
        guard case .text(let body)? = plainN.cell(withID: "body")?.component else { return XCTFail() }
        XCTAssertEqual(body.maxLines, 30)   // clamped like v1
    }

    // MARK: Validation

    private func errors(_ t: HeraldTemplate, manifest: HeraldManifest? = nil) -> [HeraldTemplateIssue] {
        t.validate(manifest: manifest).filter(\.isError)
    }

    func testValidationFindsStructuralErrorsAndNamesCells() {
        var t = HeraldTemplate(name: "t", app: "a", grid: HeraldGrid(rows: 2, cols: 2), cells: [
            HeraldCell(id: "a", row: 0, col: 0, colSpan: 2, component: .text(HeraldTextComponent(binding: "{x}"))),
            HeraldCell(id: "b", row: 0, col: 1, component: .text(HeraldTextComponent(binding: "{x}"))),     // overlaps a
            HeraldCell(id: "a", row: 1, col: 0, component: .spacer),                                          // duplicate id
            HeraldCell(id: "out", row: 1, col: 1, colSpan: 2, component: .spacer),                            // off the grid
            HeraldCell(id: "neg", row: -1, col: 0, component: .spacer),
            HeraldCell(id: "zero", row: 0, col: 0, rowSpan: 0, component: .spacer),
            HeraldCell(id: "", row: 1, col: 1, component: .spacer),
        ])
        let errs = errors(t)
        func has(_ id: String?, _ text: String) -> Bool { errs.contains { $0.cellId == id && $0.message.contains(text) } }
        XCTAssertTrue(has("b", "overlaps cell 'a'"), "\(errs)")
        XCTAssertTrue(has("a", "used twice"))
        XCTAssertTrue(has("out", "does not fit"))
        XCTAssertTrue(has("neg", "start at 0"))
        XCTAssertTrue(has("zero", "at least 1"))
        XCTAssertTrue(errs.contains { $0.path == "cells[6].id" })
        XCTAssertFalse(t.isValid())

        t = HeraldTemplate(name: "", app: "", grid: HeraldGrid(rows: 2, cols: 2, rowSizes: [.auto], colSizes: [.fill, .points(-4)],
                                                               gap: -1, padding: 100, width: 50))
        let g = errors(t).map(\.path)
        for p in ["name", "app", "grid.rowSizes", "grid.colSizes[1]", "grid.gap", "grid.padding", "grid.width"] {
            XCTAssertTrue(g.contains(p), "\(p) in \(g)")
        }
        XCTAssertTrue(errors(HeraldTemplate(name: "t", app: "a", grid: HeraldGrid(rows: 0, cols: 99))).contains { $0.path == "grid.rows" })
        var v3 = HeraldTemplate.blank(name: "t", app: "a"); v3.layoutVersion = 3
        XCTAssertTrue(errors(v3).contains { $0.path == "layoutVersion" })
        var nogrid = HeraldTemplate(name: "t", app: "a"); nogrid.layoutVersion = 2
        XCTAssertTrue(errors(nogrid).contains { $0.path == "grid" })
        var v1WithGrid = HeraldTemplate(name: "t", app: "a"); v1WithGrid.grid = .standard
        XCTAssertTrue(v1WithGrid.validate().contains { $0.severity == .warning && $0.path == "layoutVersion" })
        XCTAssertTrue(HeraldTemplate(name: "t", app: "a").isValid())
    }

    func testValidationChecksComponentsAndActions() {
        func one(_ c: HeraldComponent, rules: [HeraldActionRule] = []) -> [HeraldTemplateIssue] {
            errors(HeraldTemplate(name: "t", app: "a", grid: HeraldGrid(rows: 1, cols: 1),
                                  cells: [HeraldCell(id: "c", row: 0, col: 0, component: c)], actionRules: rules))
        }
        XCTAssertEqual(one(.text(HeraldTextComponent(binding: "{a}"))), [])
        XCTAssertFalse(one(.text(HeraldTextComponent(binding: " "))).isEmpty)
        XCTAssertTrue(one(.text(HeraldTextComponent(binding: "{a}", maxLines: 0, color: "red", fontSize: 2))).count == 3)
        XCTAssertTrue(one(.image(HeraldImageComponent(aspectRatio: 0))).contains { $0.path.hasSuffix("aspectRatio") })
        XCTAssertTrue(one(.issuerIcon(HeraldIssuerIconComponent(size: 2))).contains { $0.path.hasSuffix("size") })
        XCTAssertFalse(one(.button(HeraldButtonComponent())).isEmpty)
        XCTAssertTrue(one(.button(HeraldButtonComponent(actionRef: "x"))).isEmpty)
        XCTAssertFalse(one(.iconButton(HeraldIconButtonComponent(symbol: ""))).isEmpty)
        XCTAssertTrue(one(.actions(HeraldActionsComponent(maxVisible: 0))).contains { $0.path.hasSuffix("maxVisible") })
        XCTAssertFalse(one(.rive(HeraldRiveComponent())).isEmpty)
        XCTAssertTrue(one(.badge(HeraldBadgeComponent(binding: "{n}", color: "#12"))).contains { $0.path.hasSuffix("color") })
        XCTAssertTrue(one(.spacer).isEmpty)

        // Actions need what their kind needs.
        func action(_ a: HeraldAction) -> [HeraldTemplateIssue] { one(.button(HeraldButtonComponent(action: a))) }
        XCTAssertFalse(action(HeraldAction(id: "u", label: "U", kind: .url)).isEmpty)
        XCTAssertFalse(action(HeraldAction(id: "u", label: "U", kind: .url, url: "file:///etc/passwd")).isEmpty)
        XCTAssertTrue(action(HeraldAction(id: "u", label: "U", kind: .url, url: "https://x/{id}")).isEmpty)
        XCTAssertTrue(action(HeraldAction(id: "u", label: "U", kind: .url, url: "{url}")).isEmpty)
        XCTAssertFalse(action(HeraldAction(id: "c", label: "C", kind: .command)).isEmpty)
        XCTAssertFalse(action(HeraldAction(id: "s", label: "S", kind: .script, script: "../x.sh")).isEmpty)
        XCTAssertTrue(action(HeraldAction(id: "s", label: "S", kind: .script, script: "x.sh")).isEmpty)
        XCTAssertFalse(action(HeraldAction(id: "s", label: "S", kind: .shortcut)).isEmpty)
        XCTAssertFalse(action(HeraldAction(id: "z", label: "Z", kind: .snooze, snoozeMinutes: 0)).isEmpty)
        XCTAssertTrue(action(HeraldAction(id: "z", label: "Z", kind: .snooze)).isEmpty)
        XCTAssertFalse(action(HeraldAction(id: "z", label: "", kind: .dismiss)).isEmpty)
        XCTAssertFalse(action(HeraldAction(id: "z", label: "Z", kind: .dismiss, style: "loud")).isEmpty)

        // Rules.
        XCTAssertFalse(one(.spacer, rules: [HeraldActionRule()]).isEmpty)                          // neither match nor add
        XCTAssertTrue(one(.spacer, rules: [HeraldActionRule(match: "x", hide: true)]).isEmpty)
        XCTAssertTrue(one(.spacer, rules: [HeraldActionRule(match: "x", position: -1)]).contains { $0.path.hasSuffix("position") })
        XCTAssertTrue(one(.spacer, rules: [HeraldActionRule(add: HeraldAction(id: "s", label: "S", kind: .shortcut))])
            .contains { $0.path == "actionRules[0].add.shortcut" })
    }

    func testValidationWarnsAboutTokensTheManifestDoesNotKnow() throws {
        let m = try manifest()
        var t = HeraldTemplate(name: "t", app: "webwatcher.email", grid: HeraldGrid(rows: 1, cols: 3), cells: [
            HeraldCell(id: "ok", row: 0, col: 0, component: .text(HeraldTextComponent(binding: "{sender} {title} {extra.queue}"))),
            HeraldCell(id: "typo", row: 0, col: 1, component: .text(HeraldTextComponent(binding: "{sendr}"))),
            HeraldCell(id: "bell", row: 0, col: 2, component: .rive(HeraldRiveComponent(
                asset: "bell", inputBindings: ["count": "{count}", "nope": "hover"]))),
        ], extra: ["queue": "inbox"])
        let w = t.validate(manifest: m)
        XCTAssertTrue(w.filter(\.isError).isEmpty, "\(w)")
        XCTAssertTrue(w.contains { $0.severity == .warning && $0.cellId == "typo" && $0.message.contains("{sendr}") })
        XCTAssertFalse(w.contains { $0.cellId == "ok" })
        XCTAssertTrue(w.contains { $0.cellId == "bell" && $0.path.hasSuffix("inputBindings.nope") })
        t.cells[2].component = .rive(HeraldRiveComponent(asset: "ghost"))
        XCTAssertTrue(t.validate(manifest: m).contains { $0.path.hasSuffix("asset") && $0.severity == .warning })
        // Without a manifest there is nothing to compare tokens with.
        XCTAssertTrue(t.validate().filter { $0.severity == .warning && $0.cellId == "typo" }.isEmpty)
        // actionRef is checked against the manifest and the template's own additions.
        var refs = HeraldTemplate(name: "t", app: "webwatcher.email", grid: HeraldGrid(rows: 1, cols: 3), cells: [
            HeraldCell(id: "r1", row: 0, col: 0, component: .button(HeraldButtonComponent(actionRef: "markRead"))),
            HeraldCell(id: "r2", row: 0, col: 1, component: .button(HeraldButtonComponent(actionRef: "mine"))),
            HeraldCell(id: "r3", row: 0, col: 2, component: .button(HeraldButtonComponent(actionRef: "ghost")))],
            actionRules: [HeraldActionRule(add: HeraldAction(id: "mine", label: "Mine", kind: .dismiss))])
        let rw = refs.validate(manifest: m).filter { $0.path.hasSuffix("actionRef") }
        XCTAssertEqual(rw.map(\.cellId), ["r3"])
        refs.extra = ["bad key!": "x"]
        XCTAssertTrue(refs.validate().contains { $0.path == "extra.bad key!" })
    }

    // MARK: Agent schema

    func testSchemaCoversEveryComponentAndEnum() throws {
        let doc = ComponentSchema.document()
        guard case .object(let root) = doc, case .object(let components)? = root["components"],
              case .object(let defs)? = root["definitions"] else { return XCTFail("schema shape") }
        XCTAssertEqual(Set(components.keys), Set(HeraldComponent.typeNames))
        XCTAssertEqual(root["schemaVersion"], .number(2))
        // No literal in the schema failed to parse.
        XCTAssertFalse(ComponentSchema.jsonString().contains("schema literal failed to parse"))
        XCTAssertFalse(ComponentSchema.jsonString().contains("\"error\""))

        func enumValues(_ v: JSONValue?) -> Set<String> {
            guard case .object(let o)? = v, case .array(let a)? = o["enum"] else { return [] }
            return Set(a.compactMap { if case .string(let s) = $0 { return s } else { return nil } })
        }
        func props(_ type: String) -> [String: JSONValue] {
            guard case .object(let c)? = components[type], case .object(let p)? = c["properties"] else { return [:] }
            return p
        }
        XCTAssertEqual(enumValues(defs["align"]), Set(HeraldAlign.allCases.map(\.rawValue)))
        XCTAssertEqual(enumValues(defs["emptyBehavior"]), Set(HeraldEmptyBehavior.allCases.map(\.rawValue)))
        XCTAssertEqual(enumValues(props("text")["style"]), Set(HeraldTextStyle.allCases.map(\.rawValue)))
        XCTAssertEqual(enumValues(props("text")["weight"]), Set(HeraldFontWeight.allCases.map(\.rawValue)))
        XCTAssertEqual(enumValues(props("text")["alignment"]), Set(HeraldTextAlignment.allCases.map(\.rawValue)))
        XCTAssertEqual(enumValues(props("image")["fit"]), Set(HeraldImageFit.allCases.map(\.rawValue)))
        XCTAssertEqual(enumValues(props("issuerIcon")["shape"]), Set(HeraldIconShape.allCases.map(\.rawValue)))
        XCTAssertEqual(enumValues(props("actions")["source"]), Set(HeraldActionSource.allCases.map(\.rawValue)))
        XCTAssertEqual(enumValues(props("actions")["layout"]), Set(HeraldActionsLayout.allCases.map(\.rawValue)))
        guard case .object(let actionDef)? = defs["action"], case .object(let ap)? = actionDef["properties"] else { return XCTFail() }
        XCTAssertEqual(enumValues(ap["kind"]), Set(HeraldActionKind.allCases.map(\.rawValue)))
        for key in ["id", "label", "kind", "style", "url", "callback", "command", "script", "shortcut", "input", "snoozeMinutes"] {
            XCTAssertNotNil(ap[key], key)
        }

        // Every property the Swift types encode is described: encode a fully populated component and compare keys.
        for c in allComponents() {
            let encoded = try jsonObject(c)
            let described = Set(props(c.typeName).keys)
            for key in encoded.keys where key != "action" || c.typeName != "button" || true {
                XCTAssertTrue(described.contains(key), "\(c.typeName).\(key) is not in the schema")
            }
        }
        // The grid and cell properties likewise.
        guard case .object(let gridDef)? = defs["grid"], case .object(let gp)? = gridDef["properties"],
              case .object(let cellDef)? = defs["cell"], case .object(let cp)? = cellDef["properties"] else { return XCTFail() }
        XCTAssertEqual(Set(gp.keys), Set(try jsonObject(HeraldGrid.standard).keys))
        XCTAssertEqual(Set(cp.keys), Set(try jsonObject(HeraldCell(id: "i", row: 0, col: 0, component: .spacer)).keys))
        guard case .object(let tp)? = root["properties"] else { return XCTFail() }
        for key in try jsonObject(HeraldTemplate.blank(name: "n", app: "a")).keys where key != "layout" && key != "showSubtitle"
            && key != "showBody" && key != "showTimestamp" && key != "maxBodyLines" {
            XCTAssertNotNil(tp[key], "template.\(key)")
        }
    }

    func testSchemaExamplesDecodeAndValidate() throws {
        guard case .object(let root) = ComponentSchema.document(), case .array(let examples)? = root["examples"],
              case .object(let comps)? = root["components"] else { return XCTFail() }
        XCTAssertGreaterThanOrEqual(examples.count, 2)
        for ex in examples {
            guard case .object(let o) = ex, let tpl = o["template"] else { return XCTFail() }
            let t = try dec.decode(HeraldTemplate.self, from: enc.encode(tpl))
            XCTAssertEqual(t.layoutVersion, 2)
            XCTAssertEqual(t.validate().filter(\.isError), [], t.name)
        }
        // Every component's own example decodes to that component type.
        for (type, v) in comps {
            guard case .object(let c) = v, let example = c["example"] else { return XCTFail(type) }
            let comp = try dec.decode(HeraldComponent.self, from: enc.encode(example))
            XCTAssertEqual(comp.typeName, type)
        }
        // Examples reference the manifest-style ids and the template keeps its authored extras.
        let email = try decode(HeraldTemplate.self, ComponentSchema.emailExample)
        let list = ActionResolver.resolveDetailed(issuer: try manifest().actions, ids: try manifest().actionIDs, rules: email.actionRules)
        XCTAssertEqual(list.map(\.id), ["markRead", "shortcut-followup"])
        XCTAssertEqual(list.first?.action.label, "Mark as read"); XCTAssertEqual(list.last?.origin, .template)
    }

    func testSchemaServesAsJSONTextAndGuide() throws {
        let data = ComponentSchema.jsonData()
        let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertNotNil(parsed?["components"]); XCTAssertNotNil(parsed?["definitions"])
        XCTAssertEqual(parsed?["schemaVersion"] as? Int, 2)
        let guide = ComponentSchema.guide()
        for t in HeraldComponent.typeNames { XCTAssertTrue(guide.contains("`\(t)`"), t) }
        for k in HeraldActionKind.allCases { XCTAssertTrue(guide.contains("`\(k.rawValue)`"), k.rawValue) }
        XCTAssertTrue(guide.contains("collapseEmpty"))
    }
}
