import XCTest
@testable import HeraldClient
@testable import HeraldCore

final class SymbolEditingTests: XCTestCase {
    func testNameBlankRemovesTheSymbolAndKeepsStyling() {
        XCTAssertNil(SymbolEditing.setName(HeraldSymbol(name: "a", weight: .bold), "  "))
        let s = SymbolEditing.setName(HeraldSymbol(name: "a", weight: .bold), "bell")
        XCTAssertEqual(s?.name, "bell"); XCTAssertEqual(s?.weight, .bold)
    }

    func testModeAdjustsColours() {
        var s = SymbolEditing.setMode(HeraldSymbol(name: "a"), .palette)
        XCTAssertEqual(s.colors, ["accent", "secondary"])
        s = SymbolEditing.setColor(s, at: 0, "#FF3B30")
        s = SymbolEditing.addColor(s)
        XCTAssertEqual(s.colors?.count, 3)
        XCTAssertEqual(SymbolEditing.addColor(s).colors?.count, 3, "at most three")
        XCTAssertEqual(SymbolEditing.setMode(s, .hierarchical).colors, ["#FF3B30"])
        XCTAssertNil(SymbolEditing.setMode(s, .multicolor).colors)
        XCTAssertNil(SymbolEditing.setMode(s, .monochrome).renderingMode)
        XCTAssertEqual(SymbolEditing.removeColor(s, at: 0).colors?.first, "secondary")
        XCTAssertEqual(SymbolEditing.setColor(s, at: 1, "{tint}").colors?[1], "{tint}")
        XCTAssertEqual(SymbolEditing.setColor(s, at: 1, " ").colors?[1], "accent")
    }

    func testVariableValueNumbersAreClampedAndTokensKept() {
        let s = HeraldSymbol(name: "wifi")
        XCTAssertEqual(SymbolEditing.setVariableValue(s, "0.5").variableValue, "0.5")
        XCTAssertEqual(SymbolEditing.setVariableValue(s, "7").variableValue, "1")
        XCTAssertEqual(SymbolEditing.setVariableValue(s, "-2").variableValue, "0")
        XCTAssertEqual(SymbolEditing.setVariableValue(s, "{progress}").variableValue, "{progress}")
        XCTAssertNil(SymbolEditing.setVariableValue(SymbolEditing.setVariableValue(s, "1"), "").variableValue)
    }

    func testEffectKindsTriggersAndSpeed() {
        var s = SymbolEditing.setEffect(HeraldSymbol(name: "a"), .variableColor)
        s.effect?.cumulative = true
        s = SymbolEditing.setTrigger(s, .repeating)
        s = SymbolEditing.setSpeed(s, 2)
        XCTAssertEqual(s.effect, HeraldSymbolEffect(kind: .variableColor, trigger: .repeating, speed: 2, cumulative: true))
        s = SymbolEditing.setEffect(s, .bounce)
        XCTAssertNil(s.effect?.cumulative, "variableColor options are dropped")
        XCTAssertEqual(SymbolEditing.setEffect(s, .replace).effect?.trigger, .onChange)
        XCTAssertNil(SymbolEditing.setTrigger(s, .onAppear).effect?.trigger, "the default is not written")
        XCTAssertNil(SymbolEditing.setSpeed(s, 1).effect?.speed)
        XCTAssertEqual(SymbolEditing.setSpeed(s, 99).effect?.speed, 4)
        XCTAssertNil(SymbolEditing.setEffect(s, nil).effect)
    }

    func testNormalizedDropsDefaultsSoPlainNamesStayStrings() throws {
        let s = HeraldSymbol(name: "a", weight: .regular, scale: .medium, placement: .leading, renderingMode: .monochrome, colors: [])
        let n = try XCTUnwrap(SymbolEditing.normalized(s))
        XCTAssertTrue(n.isPlainName)
        XCTAssertNil(SymbolEditing.normalized(HeraldSymbol(name: " ")))
        XCTAssertNil(SymbolEditing.normalized(nil))
    }
}
