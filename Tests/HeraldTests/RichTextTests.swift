import XCTest
@testable import HeraldClient
@testable import herald_mcp

// Issue #64: rich text for the `text` component. The offscreen render of the same model is in
// BannerSnapshotTests (`testRichTextTwoLinesSnapshot`).
final class RichTextTests: XCTestCase {
    private func run(_ t: String, _ b: (inout HeraldTextRun) -> Void = { _ in }) -> HeraldTextRun {
        var r = HeraldTextRun(text: t); b(&r); return r
    }

    // MARK: markup <-> lines

    func testMarkupParsesToRuns() {
        let (lines, issues) = HeraldRichText.parse("**Project:**\n{{align=trailing}}*`{project}`*")
        XCTAssertTrue(issues.isEmpty, "\(issues)")
        XCTAssertEqual(lines.count, 2)
        XCTAssertEqual(lines[0].runs, [HeraldTextRun(text: "Project:", weight: .bold)])
        XCTAssertEqual(lines[1].align, .trailing)
        XCTAssertEqual(lines[1].runs, [HeraldTextRun(token: "{project}", italic: true, font: .mono)])
    }

    func testRoundTripIsLossless() {
        let lines: [HeraldTextLine] = [
            .init(runs: [run("Project: ") { $0.weight = .bold; $0.underline = true },
                         HeraldTextRun(token: "{project}", weight: .medium, italic: true, font: .serif, size: 14, color: "#FF3B30")]),
            .init(align: .center, runs: [run("a \\* b \\_ c \\~ d \\` e \\{ f \\\\ g") ,
                                         run(" struck") { $0.strike = true; $0.font = .mono; $0.size = 9.5 }]),
            .init(align: .trailing, runs: [HeraldTextRun(token: "{extra.build}", color: "accent")]),
            .init(runs: []),
        ].map { HeraldRichText.normalized($0) }
        let markup = HeraldRichText.markup(for: lines)
        let back = HeraldRichText.parse(markup)
        XCTAssertTrue(back.issues.isEmpty, "\(back.issues)\n\(markup)")
        XCTAssertEqual(back.lines, lines, markup)
    }

    func testEveryMarkRoundTrips() {
        for text in ["**b**", "*i*", "`m`", "__u__", "~~s~~", "***bi***", "plain {t} text", "{{size=18}}big{{/}}", "{{color=#0A84FF}}**x**{{/}} y"] {
            let a = HeraldRichText.parse(text).lines
            XCTAssertEqual(HeraldRichText.parse(HeraldRichText.markup(for: a)).lines, a, text)
        }
    }

    func testEscapesAndMalformed() {
        XCTAssertEqual(HeraldRichText.plainText(HeraldRichText.parse(#"5 \* 3 \*\* 2"#).lines), "5 * 3 ** 2")
        let bad = HeraldRichText.parse("**never closed\n{{size=99}}x{{/}} {{color=nope}}y{{/}}\nz {{align=center}}")
        XCTAssertGreaterThanOrEqual(bad.issues.count, 4, "\(bad.issues)")
        XCTAssertEqual(HeraldRichText.parse("**never closed").lines[0].runs, [HeraldTextRun(text: "\\*\\*never closed")])
    }

    func testHasStyling() {
        XCTAssertFalse(HeraldRichText.hasStyling(HeraldRichText.parse("Project: {project}\nsecond").lines))
        XCTAssertTrue(HeraldRichText.hasStyling(HeraldRichText.parse("**P**").lines))
        XCTAssertTrue(HeraldRichText.hasStyling(HeraldRichText.parse("{{align=center}}P").lines))
    }

    func testRunTextMarkupAndTokenCompile() {
        let c = HeraldComponent.text(HeraldTextComponent(binding: "", lines: [
            .init(runs: [HeraldTextRun(text: "Hi **there** ", token: "{name}", color: "#112233")])]))
        let r = c.hasContent(fields: ["name": .text("Bo")], actions: [])
        XCTAssertTrue(r)
        guard case .text(let t) = c, let l = t.resolvedLines(fields: ["name": .text("Bo")]) else { return XCTFail() }
        XCTAssertEqual(l[0].runs.map(\.text), ["Hi ", "there", " ", "Bo"].filter { _ in true }.map { $0 }.enumerated().map { $0.element })
        XCTAssertEqual(l[0].runs[1].weight, .bold)
        XCTAssertEqual(l[0].runs[0].color, "#112233")   // the run's own style is the base
    }

    // MARK: resolving, collapse

    func testAllEmptyLineCollapses() {
        let t = HeraldTextComponent(binding: "**Title**\n{sender}\n{{align=trailing}}{subject}")
        let f: [String: HeraldFieldValue] = ["subject": .text("Invoice")]
        let l = t.resolvedLines(fields: f)!
        XCTAssertEqual(l.map(\.text), ["Title", "Invoice"])          // {sender} line collapsed
        XCTAssertEqual(l[1].align, .trailing)
        let kept = t.resolvedLines(fields: f, keepEmptyLines: true)!
        XCTAssertEqual(kept.map(\.text), ["Title", "", "Invoice"])   // keep: blank line holds its height
        XCTAssertNil(HeraldTextComponent(binding: "{a}\n{b}").resolvedLines(fields: [:]))   // all lines empty
    }

    func testLiteralLineStaysEvenIfNeighbourEmpty() {
        let t = HeraldTextComponent(binding: "Project:\n{project}")
        XCTAssertEqual(t.resolvedLines(fields: [:])?.map(\.text), ["Project:"])
        XCTAssertEqual(t.resolvedLines(fields: ["project": .text("Herald")])?.map(\.text), ["Project:", "Herald"])
    }

    func testPlainBindingBehaviourUnchanged() {
        let t = HeraldTextComponent(binding: "{sender}: {subject}")
        XCTAssertEqual(t.resolvedLines(fields: ["subject": .text("Invoice")])?.map(\.text), [": Invoice"])
        XCTAssertNil(HeraldTextComponent(binding: "{count} new").resolvedLines(fields: [:]))
        XCTAssertEqual(HeraldTextComponent(binding: "Hello").resolvedLines(fields: [:])?.map(\.text), ["Hello"])
        XCTAssertNil(HeraldTextComponent(binding: "  ").resolvedLines(fields: [:]))
        // values are never read as markup
        XCTAssertEqual(HeraldTextComponent(binding: "{x}").resolvedLines(fields: ["x": .text("**a**")])?.first?.runs.first?.weight, nil)
    }

    func testCodableLinesPrecedence() throws {
        let json = #"{"type":"text","lines":[{"align":"center","runs":[{"text":"A","weight":"bold"},{"token":"{p}","italic":true}]}]}"#
        let c = try JSONDecoder().decode(HeraldComponent.self, from: Data(json.utf8))
        guard case .text(let t) = c else { return XCTFail() }
        XCTAssertEqual(t.binding, ""); XCTAssertEqual(t.lines?.first?.align, .center)
        XCTAssertEqual(c.referencedTokens, ["p"])
        let again = try JSONDecoder().decode(HeraldComponent.self, from: try JSONEncoder().encode(c))
        XCTAssertEqual(again, c)
        XCTAssertFalse(String(data: try JSONEncoder().encode(c), encoding: .utf8)!.contains("\"binding\""))
    }

    // MARK: validation and schema

    private func template(_ comp: HeraldComponent) -> HeraldTemplate {
        HeraldTemplate(name: "t", app: "demo", grid: HeraldGrid(rows: 1, cols: 1, rowSizes: [.auto], colSizes: [.fill]),
                       cells: [HeraldCell(id: "c", row: 0, col: 0, component: comp)])
    }

    func testValidationWarnsOnMalformedMarkupAndUnknownTokens() {
        let manifest = try! JSONDecoder().decode(HeraldManifest.self, from: Data(#"{"app":"demo","appName":"Demo","fields":[{"key":"project","type":"text"}]}"#.utf8))
        let bad = HeraldComponent.text(HeraldTextComponent(binding: "**oops\n{{size=3}}x{{/}} {typo}"))
        let issues = template(bad).validate(manifest: manifest)
        XCTAssertFalse(issues.contains { $0.isError }, "\(issues)")
        XCTAssertTrue(issues.contains { $0.message.contains("rich text") && $0.message.contains("never closed") }, "\(issues)")
        XCTAssertTrue(issues.contains { $0.message.contains("size") && $0.message.contains("6 to 72") }, "\(issues)")
        XCTAssertTrue(issues.contains { $0.message.contains("{typo}") }, "\(issues)")

        let runs = HeraldComponent.text(HeraldTextComponent(binding: "", lines: [
            .init(runs: [HeraldTextRun(token: "{project}", weight: .bold), HeraldTextRun(token: "{nope}"), HeraldTextRun(size: 2)])]))
        let ri = template(runs).validate(manifest: manifest)
        XCTAssertTrue(ri.contains { $0.message.contains("{nope}") }, "\(ri)")
        XCTAssertTrue(ri.contains { $0.message.contains("neither text nor token") }, "\(ri)")
        XCTAssertFalse(ri.contains { $0.isError && $0.path.hasSuffix("binding") }, "lines replaces binding: \(ri)")
        XCTAssertTrue(template(.text(HeraldTextComponent(binding: "**ok** {project}\n{{align=center}}x"))).validate(manifest: manifest).isEmpty)
    }

    func testSchemaDocumentsRichText() {
        let doc = ComponentSchema.document()
        let props = doc["components"]?["text"]?["properties"]
        XCTAssertNotNil(props?["lines"]); XCTAssertNotNil(props?["lineSpacing"])
        XCTAssertNotNil(props?["lines"]?["items"]?["properties"]?["runs"]?["items"]?["properties"]?["italic"])
        XCTAssertTrue(props?["binding"]?["description"]?.stringValue?.contains("{{align=center}}") ?? false)
    }

    // MARK: formatting bar edits

    func testToggleWrapUnwrapAndCaret() {
        let t = "Project: x"
        let bold = HeraldRichText.toggle(.bold, in: t, selection: NSRange(location: 0, length: 8))
        XCTAssertEqual(bold.text, "**Project:** x")
        XCTAssertEqual(HeraldRichText.toggle(.bold, in: bold.text, selection: bold.selection).text, t)         // selection inside
        XCTAssertEqual(HeraldRichText.toggle(.bold, in: bold.text, selection: NSRange(location: 2, length: 8)).text, t)   // outside
        let it = HeraldRichText.toggle(.italic, in: bold.text, selection: NSRange(location: 0, length: 12))
        XCTAssertEqual(it.text, "***Project:***" + " x".replacingOccurrences(of: "***", with: ""))
        XCTAssertEqual(HeraldRichText.toggle(.mono, in: "ab", selection: NSRange(location: 1, length: 0)).text, "a``b")
        let multi = HeraldRichText.toggle(.strike, in: "a\nb", selection: NSRange(location: 0, length: 3))
        XCTAssertEqual(multi.text, "~~a~~\n~~b~~")
        XCTAssertEqual(HeraldRichText.toggle(.strike, in: multi.text, selection: NSRange(location: 0, length: 11)).text, "a\nb")
        // bold is not italic
        XCTAssertEqual(HeraldRichText.toggle(.italic, in: "**x**", selection: NSRange(location: 0, length: 5)).text, "***x***")
    }

    func testSizeColorAndAlign() {
        var e = HeraldRichText.stepSize(by: 2, base: 12, in: "hello", selection: NSRange(location: 0, length: 5))
        XCTAssertEqual(e.text, "{{size=14}}hello{{/}}")
        e = HeraldRichText.stepSize(by: 2, base: 12, in: e.text, selection: e.selection)
        XCTAssertEqual(e.text, "{{size=16}}hello{{/}}")
        e = HeraldRichText.setSpan("color", to: "#FF0000", in: e.text, selection: e.selection)
        XCTAssertEqual(e.text, "{{size=16 color=#FF0000}}hello{{/}}")
        e = HeraldRichText.setSpan("size", to: nil, in: e.text, selection: e.selection)
        e = HeraldRichText.setSpan("color", to: nil, in: e.text, selection: e.selection)
        XCTAssertEqual(e.text, "hello")
        XCTAssertEqual(HeraldRichText.stepSize(by: -100, base: 12, in: "x", selection: NSRange(location: 0, length: 1)).text, "{{size=6}}x{{/}}")

        let t = "one\ntwo"
        let a = HeraldRichText.setAlign(.center, in: t, caret: 5)
        XCTAssertEqual(a.text, "one\n{{align=center}}two")
        XCTAssertEqual(HeraldRichText.align(in: a.text, caret: 6), .center)
        XCTAssertNil(HeraldRichText.align(in: a.text, caret: 1))
        XCTAssertEqual(HeraldRichText.setAlign(.trailing, in: a.text, caret: 10).text, "one\n{{align=trailing}}two")
        XCTAssertEqual(HeraldRichText.setAlign(nil, in: a.text, caret: 10).text, t)
        XCTAssertEqual(HeraldRichText.insertToken("project", in: "ab", selection: NSRange(location: 1, length: 0)).text, "a{project}b")
    }
}
