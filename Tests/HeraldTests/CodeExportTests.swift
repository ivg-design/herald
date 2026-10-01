import XCTest
@testable import HeraldCore

final class CodeExportTests: XCTestCase {
    /// A payload that exercises every field the exporters know about.
    private func fullNotification() -> HeraldNotification {
        var n = HeraldNotification(
            app: "bidbot", id: "bid-42", title: "Bid accepted", subtitle: "Acme RFP",
            body: "Won it. [Open](https://example.com/p?a=1&b=2)", image: "/tmp/p.png",
            url: "https://example.com/p", sound: "Glass", persistent: false, timeout: 12.5,
            priority: "high",
            buttons: [HeraldButton(label: "Open", url: "https://example.com/p"),
                      HeraldButton(label: "Mark done", callback: HeraldCallback(payload: .object(["bid": .number(42)]))),
                      HeraldButton(label: "Archive", command: "bidbot archive 42")],
            snooze: true,
            reminder: HeraldReminder(title: "Follow up", due: "2026-10-02T09:00:00-04:00"),
            metadata: .object(["amount": .string("4200")]))
        n.layout = .hero
        n.accentColor = "#34C759"
        n.maxBodyLines = 4
        return n
    }

    private func minimal(title: String = "Hello", app: String = "demo") -> HeraldNotification {
        HeraldNotification(app: app, title: title)
    }

    // MARK: Every format carries the app and the title

    func testEveryFormatContainsTitleAndApp() {
        for n in [minimal(), fullNotification()] {
            for f in CodeExportFormat.allCases {
                let out = CodeExport.export(n, as: f)
                XCTAssertTrue(out.contains(n.title), "\(f) lacks the title")
                XCTAssertTrue(out.contains(n.app), "\(f) lacks the app")
            }
        }
    }

    // MARK: Shell quoting

    func testShellQuote() {
        XCTAssertEqual(CodeExport.shellQuote("plain-word_1.txt"), "plain-word_1.txt")
        XCTAssertEqual(CodeExport.shellQuote(""), "''")
        XCTAssertEqual(CodeExport.shellQuote("two words"), "'two words'")
        XCTAssertEqual(CodeExport.shellQuote("it's"), "'it'\\''s'")
        XCTAssertEqual(CodeExport.shellQuote("$HOME `x` \"q\" \\ ;"), "'$HOME `x` \"q\" \\ ;'")
        XCTAssertEqual(CodeExport.shellQuote("a\nb"), "'a\nb'")
    }

    func testCurlQuotesAnApostropheInTheTitle() {
        let out = CodeExport.curl(minimal(title: "Bob's bid"))
        XCTAssertTrue(out.contains("Bob'\\''s bid"), out)
        XCTAssertTrue(out.hasPrefix("H=\"$HOME/Library/Application Support/Herald\""))
        XCTAssertTrue(out.contains("/v1/notify"))
        XCTAssertTrue(out.contains("Authorization: Bearer $(cat \"$H/token\")"))
        XCTAssertTrue(out.contains("Content-Type: application/json"))
    }

    // MARK: JSON escaping

    func testJSONLiteralEscaping() {
        let s = "say \"hi\"\\ now\nline2\ttab\u{1}ctl é 😀 </script>"
        let lit = CodeExport.Literal.string(s, .json)
        XCTAssertEqual(lit, "\"say \\\"hi\\\"\\\\ now\\nline2\\ttab\\u0001ctl é 😀 </script>\"")
        // It must be a valid JSON document that decodes back to the original text.
        let back = try? JSONDecoder().decode(String.self, from: Data(lit.utf8))
        XCTAssertEqual(back, s)
    }

    func testCurlPayloadIsValidJSONWithEscapes() throws {
        let n = HeraldNotification(app: "a", title: "Quote \" and \\ and\nnewline", body: "tab\there")
        let out = CodeExport.curl(n)
        // The text between the single quotes after -d is the JSON body.
        let start = try XCTUnwrap(out.range(of: "-d '"))
        let json = String(out[start.upperBound...].dropLast())
        XCTAssertFalse(json.contains("\n\n"))
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        XCTAssertEqual(obj["title"] as? String, "Quote \" and \\ and\nnewline")
        XCTAssertEqual(obj["body"] as? String, "tab\there")
        XCTAssertEqual(obj["app"] as? String, "a")
    }

    func testWireObjectRoundTripsTheFullPayload() throws {
        let n = fullNotification()
        let json = Literal.render(.object(CodeExport.wireObject(n)), .json, level: 0, expanded: true, ordered: true)
        let back = try HeraldJSON.decoder().decode(HeraldNotification.self, from: Data(json.utf8))
        XCTAssertEqual(back, n)
    }

    func testCurlOrdersKeysForReading() {
        let out = CodeExport.curl(fullNotification())
        let order = ["\"app\"", "\"id\"", "\"title\"", "\"subtitle\"", "\"buttons\"", "\"sound\"", "\"layout\"", "\"metadata\""]
        var last = out.startIndex
        for k in order {
            let r = out.range(of: k, range: last..<out.endIndex)
            XCTAssertNotNil(r, "\(k) missing or out of order")
            if let r { last = r.upperBound }
        }
    }

    // MARK: Swift

    func testSwiftEscapesAndAssignsNewFieldsAsProperties() {
        var n = HeraldNotification(app: "bid\"bot", title: "A \"quoted\" \\ title\nsecond", body: "x")
        n.layout = .compact
        n.showTimestamp = false
        n.template = "bid-won"
        let out = CodeExport.swift(n)
        XCTAssertTrue(out.contains("import HeraldClient"))
        XCTAssertTrue(out.contains("app: \"bid\\\"bot\""), out)
        XCTAssertTrue(out.contains("title: \"A \\\"quoted\\\" \\\\ title\\nsecond\""), out)
        XCTAssertTrue(out.contains("var notification = HeraldNotification("))
        XCTAssertTrue(out.contains("notification.layout = .compact"))
        XCTAssertTrue(out.contains("notification.showTimestamp = false"))
        XCTAssertTrue(out.contains("notification.template = \"bid-won\""))
        XCTAssertTrue(out.contains("HeraldClient.shared.notify(notification)"))
        XCTAssertFalse(out.contains("title: \"A \"quoted"))
    }

    func testSwiftRendersButtonsReminderAndMetadata() {
        let out = CodeExport.swift(fullNotification())
        XCTAssertTrue(out.contains("HeraldButton(label: \"Open\", url: \"https://example.com/p\")"), out)
        XCTAssertTrue(out.contains("HeraldButton(label: \"Mark done\", callback: HeraldCallback(payload: .object([\"bid\": .number(42)])))"), out)
        XCTAssertTrue(out.contains("HeraldButton(label: \"Archive\", command: \"bidbot archive 42\")"), out)
        XCTAssertTrue(out.contains("reminder: HeraldReminder(title: \"Follow up\", due: \"2026-10-02T09:00:00-04:00\")"), out)
        XCTAssertTrue(out.contains("metadata: .object([\"amount\": .string(\"4200\")])"), out)
        XCTAssertTrue(out.contains("timeout: 12.5"))
        XCTAssertTrue(out.contains("persistent: false"))
        XCTAssertTrue(out.contains("notification.maxBodyLines = 4"))
        XCTAssertTrue(out.contains("notification.accentColor = \"#34C759\""))
    }

    func testSwiftWithoutExtrasUsesLet() {
        let out = CodeExport.swift(minimal())
        XCTAssertTrue(out.contains("let notification = HeraldNotification("))
        XCTAssertFalse(out.contains("notification."))
    }

    // MARK: Python / Node

    func testPythonLiteralsAndEscapes() {
        var n = HeraldNotification(app: "demo", title: "He said \"hi\"\nbye", persistent: true, snooze: false,
                                   metadata: .object(["flag": .bool(true), "none": .null]))
        n.showBody = false
        let out = CodeExport.python(n)
        XCTAssertTrue(out.hasPrefix("from herald import Herald\n\nHerald().notify(\n"), out)
        XCTAssertTrue(out.contains("\"demo\","))
        XCTAssertTrue(out.contains("\"He said \\\"hi\\\"\\nbye\","), out)
        XCTAssertTrue(out.contains("persistent=True"))
        XCTAssertTrue(out.contains("snooze=False"))
        XCTAssertTrue(out.contains("showBody=False"))
        XCTAssertTrue(out.contains("\"flag\": True"))
        XCTAssertTrue(out.contains("\"none\": None"))
        XCTAssertTrue(out.hasSuffix("\n)"))
        // No trailing comma after the last keyword argument is required, but each kwarg is on its own line.
        XCTAssertFalse(out.contains("\n\n\n"))
    }

    func testPythonButtonsAreNestedLiterals() {
        let out = CodeExport.python(fullNotification())
        XCTAssertTrue(out.contains("buttons=["), out)
        XCTAssertTrue(out.contains("\"label\": \"Open\""))
        XCTAssertTrue(out.contains("\"payload\": {\"bid\": 42}"), out)
        XCTAssertTrue(out.contains("timeout=12.5"))
    }

    func testNodeLiteralsAndEscapes() {
        let n = HeraldNotification(app: "demo", title: "Path C:\\x \"q\"", subtitle: "s\u{2028}u", persistent: false)
        let out = CodeExport.node(n)
        XCTAssertTrue(out.hasPrefix("const { Herald } = require('./herald.js');"))
        XCTAssertTrue(out.contains("new Herald().notify(\"demo\", \"Path C:\\\\x \\\"q\\\"\""), out)
        XCTAssertTrue(out.contains("\"subtitle\": \"s\\u2028u\""), out)
        XCTAssertTrue(out.contains("\"persistent\": false"))
        XCTAssertTrue(out.hasSuffix("\n})();"), out)
    }

    func testNodeWithOnlyAppAndTitleHasNoFieldsObject() {
        XCTAssertTrue(CodeExport.node(minimal()).hasSuffix("notify(\"demo\", \"Hello\");\n})();"))
    }

    /// herald.js is CommonJS, which has no top-level await: the call must sit inside an async function.
    func testNodeAwaitIsInsideAnAsyncFunction() {
        let out = CodeExport.node(minimal())
        XCTAssertEqual(out, """
            const { Herald } = require('./herald.js');

            (async () => {
              await new Herald().notify("demo", "Hello");
            })();
            """)
        let full = CodeExport.node(fullNotification())
        let lines = full.components(separatedBy: "\n")
        let awaitLine = lines.firstIndex { $0.hasPrefix("  await new Herald()") }
        XCTAssertNotNil(awaitLine, full)
        XCTAssertFalse(lines.contains { $0.hasPrefix("await ") }, "no top-level await: \(full)")
        // Every line of the multi-line object literal is indented under the function.
        XCTAssertTrue(lines.dropFirst(3).dropLast().allSatisfy { $0.isEmpty || $0.hasPrefix("  ") }, full)
    }

    // MARK: CLI

    func testCLIUsesFlagsForSupportedFields() {
        var n = HeraldNotification(app: "bidbot", title: "Bid accepted", subtitle: "Acme RFP", url: "https://example.com/p",
                                   sound: "Glass", persistent: true, timeout: 30, priority: "high",
                                   buttons: [HeraldButton(label: "Open", url: "https://example.com/p"),
                                             HeraldButton(label: "Archive", command: "bidbot archive 42"),
                                             HeraldButton(label: "Done", callback: HeraldCallback(payload: .object(["bid": .number(42)])))],
                                   snooze: true, reminder: HeraldReminder(title: "Follow up", due: "2026-10-02T09:00"))
        n.metadata = .object(["k": .string("v w")])
        let out = CodeExport.cli(n)
        XCTAssertTrue(out.hasPrefix("herald notify \\\n  --app bidbot \\\n"), out)
        XCTAssertTrue(out.contains("--title 'Bid accepted'"))
        XCTAssertTrue(out.contains("--subtitle 'Acme RFP'"))
        XCTAssertTrue(out.contains("--sound Glass"))
        XCTAssertTrue(out.contains("--timeout 30"))
        XCTAssertTrue(out.contains("--persistent"))
        XCTAssertTrue(out.contains("--priority high"))
        XCTAssertTrue(out.contains("--snooze"))
        XCTAssertTrue(out.contains("--button 'Archive=cmd:bidbot archive 42'"))
        XCTAssertTrue(out.contains("--button Open=https://example.com/p"))
        XCTAssertTrue(out.contains("--button 'Done=cb:{\"bid\":42}'"), out)
        XCTAssertTrue(out.contains("--reminder 'Follow up|2026-10-02T09:00'"))
        XCTAssertTrue(out.contains("--metadata '{\"k\":\"v w\"}'"), out)
        XCTAssertFalse(out.contains("<<'JSON'"))
        XCTAssertFalse(out.hasSuffix("\\"))
    }

    func testCLIQuotesAnApostropheInTheTitle() {
        let out = CodeExport.cli(minimal(title: "It's \"done\""))
        XCTAssertTrue(out.contains("--title 'It'\\''s \"done\"'"), out)
    }

    func testCLISendsWhatItHasNoFlagForAsJSON() throws {
        var n = HeraldNotification(app: "bidbot", title: "T",
                                   buttons: [HeraldButton(label: "Del", style: "destructive", command: "rm x")])
        n.layout = .hero
        n.accentColor = "#FF0000"
        let out = CodeExport.cli(n)
        XCTAssertTrue(out.contains("--json - <<'JSON'\n"), out)
        XCTAssertTrue(out.hasSuffix("\nJSON"), out)
        let start = try XCTUnwrap(out.range(of: "<<'JSON'\n"))
        let body = String(out[start.upperBound...].dropLast(5))
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any])
        XCTAssertEqual(obj["layout"] as? String, "hero")
        XCTAssertEqual(obj["accentColor"] as? String, "#FF0000")
        // A styled button cannot be written as --button, so the whole list rides in the JSON.
        XCTAssertEqual((obj["buttons"] as? [[String: Any]])?.first?["style"] as? String, "destructive")
        XCTAssertFalse(out.contains("--button"))
        XCTAssertNil(obj["title"]); XCTAssertNil(obj["app"])
    }

    func testCLIOmitsAnEmptyTitleAndSendsTheTemplateAsJSON() {
        var n = HeraldNotification(app: "bidbot", title: "")
        n.template = "bid-won"
        n.metadata = .object(["amount": .string("4200")])
        let out = CodeExport.cli(n)
        XCTAssertFalse(out.contains("--title"), out)
        XCTAssertTrue(out.contains("\"template\": \"bid-won\""), out)
        XCTAssertTrue(out.contains("--metadata '{\"amount\":\"4200\"}'"), out)
    }

    // MARK: Literal helpers

    func testNumberFormatting() {
        XCTAssertEqual(CodeExport.Literal.number(8), "8")
        XCTAssertEqual(CodeExport.Literal.number(0), "0")
        XCTAssertEqual(CodeExport.Literal.number(1.5), "1.5")
        XCTAssertEqual(CodeExport.Literal.number(-3), "-3")
    }

    func testSwiftStringEscapes() {
        XCTAssertEqual(CodeExport.Literal.swiftString("a\"b\\c\n\t\r\u{1}"), "\"a\\\"b\\\\c\\n\\t\\r\\u{1}\"")
        XCTAssertEqual(CodeExport.Literal.swiftString("\\(x)"), "\"\\\\(x)\"")
    }
}

private typealias Literal = CodeExport.Literal
