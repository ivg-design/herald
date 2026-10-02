import XCTest
@testable import HeraldClient
@testable import HeraldCore

final class SymbolSchemaTests: XCTestCase {
    private let full = HeraldSymbol(name: "wifi", weight: .semibold, scale: .large, placement: .trailing,
                                    renderingMode: .palette, colors: ["#FF3B30", "accent", "{tint}"], variableValue: "{signal}",
                                    effect: HeraldSymbolEffect(kind: .variableColor, trigger: .repeating, speed: 1.5, cumulative: true, reversing: true))

    private func roundTrip<T: Codable & Equatable>(_ v: T, file: StaticString = #filePath, line: UInt = #line) throws {
        let data = try HeraldJSON.encoder().encode(v)
        XCTAssertEqual(try HeraldJSON.decoder().decode(T.self, from: data), v, file: file, line: line)
    }

    func testEveryFieldRoundTrips() throws {
        try roundTrip(full)
        for k in HeraldSymbolWeight.allCases { try roundTrip(HeraldSymbol(name: "a", weight: k)) }
        for k in HeraldSymbolScale.allCases { try roundTrip(HeraldSymbol(name: "a", scale: k)) }
        for k in HeraldSymbolPlacement.allCases { try roundTrip(HeraldSymbol(name: "a", placement: k)) }
        for k in HeraldSymbolRenderingMode.allCases { try roundTrip(HeraldSymbol(name: "a", renderingMode: k)) }
        for k in HeraldSymbolEffectKind.allCases { for t in HeraldSymbolTrigger.allCases {
            try roundTrip(HeraldSymbol(name: "a", effect: HeraldSymbolEffect(kind: k, trigger: t, speed: 2)))
        } }
        try roundTrip(HeraldSymbol(name: "a", variableValue: "0.25"))
    }

    func testPlainNameIsAStringAndNumbersStayNumbers() throws {
        let enc = HeraldJSON.encoder()
        XCTAssertEqual(String(data: try enc.encode(HeraldSymbol(name: "bell")), encoding: .utf8), "\"bell\"")
        let s = try HeraldJSON.decoder().decode(HeraldSymbol.self, from: Data(#"{"name":"wifi","variableValue":0.5}"#.utf8))
        XCTAssertEqual(s.variableValue, "0.5")
        let out = String(data: try enc.encode(s), encoding: .utf8) ?? ""
        XCTAssertTrue(out.contains("\"variableValue\":0.5"), out)
        XCTAssertEqual(try HeraldJSON.decoder().decode(HeraldSymbol.self, from: Data("\"bell\"".utf8)), HeraldSymbol(name: "bell"))
    }

    func testComponentsAndActionsCarryTheSymbol() throws {
        let comps: [HeraldComponent] = [
            .button(HeraldButtonComponent(action: HeraldAction(id: "a", label: "A", kind: .dismiss), symbol: full)),
            .actions(HeraldActionsComponent(symbol: full)),
            .issuerIcon(HeraldIssuerIconComponent(symbol: full)),
            .badge(HeraldBadgeComponent(binding: "{n}", symbol: full)),
            .iconButton(HeraldIconButtonComponent(symbol: "wifi", action: HeraldAction(id: "a", label: "A", kind: .dismiss), symbolStyle: full)),
        ]
        for c in comps { try roundTrip(c); XCTAssertEqual(c.symbols.first?.name, "wifi") }
        try roundTrip(HeraldAction(id: "a", label: "A", kind: .dismiss, symbol: full))
        try roundTrip(HeraldActionRule(match: "a", symbol: full))
        // iconButton stays wire compatible: a plain name is a string, the name is `symbol`.
        let icon = try HeraldJSON.decoder().decode(HeraldComponent.self, from: Data(#"{"type":"iconButton","symbol":"xmark","action":{"id":"d","label":"D","kind":"dismiss"}}"#.utf8))
        guard case .iconButton(let b) = icon else { return XCTFail() }
        XCTAssertEqual(b.symbol, "xmark"); XCTAssertNil(b.symbolStyle)
    }

    func testARuleGivesMatchedActionsASymbol() {
        let rules = [HeraldActionRule(match: "*", symbol: HeraldSymbol(name: "checkmark", weight: .bold))]
        let list = ActionResolver.resolve(issuer: [HeraldButton(label: "Open", url: "https://x")], rules: rules)
        XCTAssertEqual(list.first?.symbol?.name, "checkmark")
    }

    func testTokensInColorsAndVariableValueAreReferenced() {
        let c = HeraldComponent.badge(HeraldBadgeComponent(binding: "{n}", symbol: full))
        XCTAssertEqual(Set(c.referencedTokens), ["n", "tint", "signal"])
    }

    // MARK: Validation

    private func issues(_ sym: HeraldSymbol) -> [HeraldTemplateIssue] {
        var t = HeraldTemplate(name: "t", app: "a", grid: HeraldGrid(rows: 1, cols: 1), cells: [])
        t.cells = [HeraldCell(id: "b", row: 0, col: 0, component: .badge(HeraldBadgeComponent(binding: "{title}", symbol: sym)))]
        return t.validate()
    }

    func testValidSymbolHasNoSymbolIssues() {
        XCTAssertTrue(issues(full).filter { $0.path.contains("symbol") }.isEmpty, "\(issues(full))")
    }

    func testUnknownNameIsAWarningNotAnError() {
        let i = issues(HeraldSymbol(name: "definitely.not.a.symbol"))
        let hit = i.filter { $0.path.hasSuffix("symbol.name") }
        XCTAssertEqual(hit.count, 1)
        XCTAssertEqual(hit.first?.severity, .warning)
    }

    func testOutOfRangeAndInconsistentSettingsWarn() {
        func warns(_ s: HeraldSymbol, _ key: String) -> Bool {
            issues(s).contains { $0.path.hasSuffix(key) && $0.severity == .warning }
        }
        XCTAssertTrue(warns(HeraldSymbol(name: "wifi", variableValue: "1.5"), "variableValue"))
        XCTAssertTrue(warns(HeraldSymbol(name: "wifi", variableValue: "lots"), "variableValue"))
        XCTAssertTrue(warns(HeraldSymbol(name: "wifi", colors: ["red"]), "colors[0]"))
        XCTAssertTrue(warns(HeraldSymbol(name: "wifi", colors: ["#111", "#222", "#333", "#444"]), "colors"))
        XCTAssertTrue(warns(HeraldSymbol(name: "wifi", renderingMode: .palette), "colors"))
        XCTAssertTrue(warns(HeraldSymbol(name: "wifi", renderingMode: .multicolor, colors: ["#111"]), "colors"))
        XCTAssertTrue(warns(HeraldSymbol(name: "wifi", effect: HeraldSymbolEffect(kind: .pulse, speed: 9)), "effect.speed"))
        XCTAssertTrue(warns(HeraldSymbol(name: "wifi", effect: HeraldSymbolEffect(kind: .bounce, cumulative: true)), "effect"))
        XCTAssertTrue(warns(HeraldSymbol(name: "wifi", effect: HeraldSymbolEffect(kind: .replace, trigger: .onAppear)), "effect.trigger"))
        XCTAssertFalse(issues(HeraldSymbol(name: "wifi", variableValue: "0.5")).contains { $0.path.hasSuffix("variableValue") })
    }

    func testBlankNameIsAnError() {
        XCTAssertTrue(issues(HeraldSymbol(name: " ")).contains { $0.path.hasSuffix("symbol.name") && $0.isError })
    }

    func testTheComponentSchemaDocumentsTheSymbolOnEveryComponent() {
        func at(_ path: String...) -> JSONValue? {
            var v: JSONValue? = ComponentSchema.document()
            for k in path { if case .object(let o)? = v { v = o[k] } else { v = nil } }
            return v
        }
        XCTAssertNotNil(at("definitions", "symbol", "properties", "effect"))
        for type in ["button", "actions", "issuerIcon", "badge", "iconButton"] {
            XCTAssertNotNil(at("components", type, "properties", "symbol"), type)
        }
        XCTAssertNotNil(at("definitions", "action", "properties", "symbol"))
        XCTAssertNotNil(at("definitions", "actionRule", "properties", "symbol"))
        for k in ["name", "weight", "scale", "placement", "renderingMode", "colors", "variableValue", "effect"] {
            XCTAssertNotNil(at("definitions", "symbol", "properties", k), k)
        }
    }
}
