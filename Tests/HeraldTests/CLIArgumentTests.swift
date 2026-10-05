import XCTest
@testable import HeraldClient

final class CLIArgumentTests: XCTestCase {
    private func request(_ args: [String], input: [String: Data] = [:]) throws -> CLIRequest {
        let inv = try CLIArguments.parse(args) { src in
            guard let d = input[src] else { throw CocoaError(.fileNoSuchFile) }
            return d
        }
        guard case .request(let r) = inv.action else { XCTFail("not a request"); throw CLIParseError("x") }
        return r
    }

    func testNotifyFull() throws {
        let r = try request(["notify", "--app", "bidbot", "--title", "Bid accepted", "--body", "hi", "--image", "p.png",
                             "--url", "https://x", "--sound", "Glass", "--timeout", "0", "--snooze", "--priority", "high",
                             "--id", "bid-42", "--no-persistent", "--subtitle", "Acme"])
        XCTAssertEqual(r.method, "POST"); XCTAssertEqual(r.path, "/v1/notify"); XCTAssertTrue(r.needsAuth)
        let b = try XCTUnwrap(r.body)
        XCTAssertEqual(b["app"] as? String, "bidbot")
        XCTAssertEqual(b["title"] as? String, "Bid accepted")
        XCTAssertEqual(b["timeout"] as? Int, 0)
        XCTAssertEqual(b["snooze"] as? Bool, true)
        XCTAssertEqual(b["persistent"] as? Bool, false)
        XCTAssertEqual(b["priority"] as? String, "high")
        XCTAssertEqual(b["id"] as? String, "bid-42")
    }

    func testButtons() throws {
        let r = try request(["notify", "--app", "a", "--title", "t",
                             "--button", "Open=https://x.com/?a=b", "--button", "Archive=cmd:bidbot archive 42",
                             "--button", "Done=cb:{\"bid\":42}", "--button=Plain=cb:"])
        let btns = try XCTUnwrap(r.body?["buttons"] as? [[String: Any]])
        XCTAssertEqual(btns.count, 4)
        XCTAssertEqual(btns[0]["url"] as? String, "https://x.com/?a=b")
        XCTAssertEqual(btns[1]["command"] as? String, "bidbot archive 42")
        let cb = try XCTUnwrap(btns[2]["callback"] as? [String: Any])
        XCTAssertEqual((cb["payload"] as? [String: Any])?["bid"] as? Int, 42)
        XCTAssertNotNil(btns[3]["callback"] as? [String: Any])
        XCTAssertThrowsError(try CLIArguments.parseButton("nolabel"))
        XCTAssertThrowsError(try CLIArguments.parseButton("X=cb:{bad"))
    }

    func testReminder() throws {
        let r = try request(["notify", "--app", "a", "--title", "t", "--reminder", "Follow up|2026-10-02T09:00"])
        let rem = try XCTUnwrap(r.body?["reminder"] as? [String: Any])
        XCTAssertEqual(rem["title"] as? String, "Follow up")
        XCTAssertEqual(rem["due"] as? String, "2026-10-02T09:00")
        XCTAssertEqual(try CLIArguments.parseReminder("Just a title")["due"] as? String, nil)
    }

    func testJSONMergeAndStdin() throws {
        let json = Data(#"{"app":"x","title":"from file","body":"b"}"#.utf8)
        let r = try request(["notify", "--json", "-", "--title", "override"], input: ["-": json])
        XCTAssertEqual(r.body?["title"] as? String, "override")
        XCTAssertEqual(r.body?["body"] as? String, "b")
        XCTAssertThrowsError(try request(["notify", "--json", "missing.json"]))
        XCTAssertThrowsError(try request(["notify", "--json", "bad"], input: ["bad": Data("[1]".utf8)]))
    }

    func testNotifyValidation() {
        XCTAssertThrowsError(try request(["notify", "--title", "t"]))
        XCTAssertThrowsError(try request(["notify", "--app", "a"]))
        XCTAssertThrowsError(try request(["notify", "--app", "a", "--title", "t", "--bogus"]))
        XCTAssertThrowsError(try request(["notify", "--app", "a", "--title", "t", "--timeout", "soon"]))
        XCTAssertThrowsError(try request(["notify", "--app", "a", "--title"]))
        XCTAssertThrowsError(try request(["notify", "--app", "a", "--title", "t", "--priority", "bogus"]))
    }

    func testRegister() throws {
        let r = try request(["register", "--app", "bidbot", "--name", "BidBot", "--callback-url", "http://127.0.0.1:5/h",
                             "--allow-commands", "--sound", "Glass", "--corner", "topLeft", "--bundle-id", "com.x"])
        XCTAssertEqual(r.path, "/v1/register")
        XCTAssertEqual(r.body?["appName"] as? String, "BidBot")
        XCTAssertEqual(r.body?["callbackURL"] as? String, "http://127.0.0.1:5/h")
        XCTAssertEqual(r.body?["allowCommands"] as? Bool, true)
        XCTAssertEqual((r.body?["defaults"] as? [String: Any])?["corner"] as? String, "topLeft")
    }

    func testOtherCommands() throws {
        var r = try request(["dismiss", "--app", "a", "--id", "i"])
        XCTAssertEqual(r.path, "/v1/dismiss"); XCTAssertEqual(r.body?["id"] as? String, "i")
        r = try request(["dismiss-all", "--app", "a"])
        XCTAssertEqual(r.path, "/v1/dismissAll")
        r = try request(["history", "--app", "a", "--limit", "5"])
        XCTAssertEqual(r.method, "GET"); XCTAssertEqual(r.query.map { "\($0.name)=\($0.value)" }, ["app=a", "limit=5"])
        r = try request(["history", "--app", "a", "--clear"])
        XCTAssertEqual(r.method, "DELETE")
        r = try request(["apps"]); XCTAssertEqual(r.path, "/v1/apps")
        r = try request(["health"]); XCTAssertFalse(r.needsAuth)
        XCTAssertThrowsError(try request(["dismiss", "--app", "a"]))
        XCTAssertThrowsError(try request(["frobnicate"]))
    }

    func testStackCommandsAndGroup() throws {
        var r = try request(["dismiss-all", "--app", "a", "--group", "rive.app"])
        XCTAssertEqual(r.path, "/v1/dismissAll")
        XCTAssertEqual(r.body?["group"] as? String, "rive.app"); XCTAssertEqual(r.body?["app"] as? String, "a")
        r = try request(["dismiss-all", "--app", "a"])
        XCTAssertNil(r.body?["group"], "without --group it dismisses the whole app, as before")
        r = try request(["stacks"])
        XCTAssertEqual(r.method, "GET"); XCTAssertEqual(r.path, "/v1/stacks"); XCTAssertTrue(r.query.isEmpty)
        r = try request(["stacks", "--app", "a"])
        XCTAssertEqual(r.query.map { "\($0.name)=\($0.value)" }, ["app=a"])
        r = try request(["notify", "--app", "a", "--title", "t", "--group", "rive.app"])
        XCTAssertEqual(r.body?["group"] as? String, "rive.app")
    }

    func testGlobalOptionsAndHelp() throws {
        let inv = try CLIArguments.parse(["--port", "5000", "health", "--token=abc"])
        XCTAssertEqual(inv.port, 5000); XCTAssertEqual(inv.token, "abc")
        XCTAssertThrowsError(try CLIArguments.parse(["health", "--port", "99999"]))
        if case .help(let c) = try CLIArguments.parse(["notify", "--help"]).action { XCTAssertEqual(c, "notify") } else { XCTFail() }
        if case .help(nil) = try CLIArguments.parse([]).action {} else { XCTFail() }
        if case .version = try CLIArguments.parse(["--version"]).action {} else { XCTFail() }
    }

    func testHelpForOneCommandPrintsOnlyThatCommand() throws {
        if case .help(let c) = try CLIArguments.parse(["help", "snooze"]).action { XCTAssertEqual(c, "snooze") } else { XCTFail() }
        let snooze = try XCTUnwrap(CLIArguments.usage(for: "snooze"))
        XCTAssertTrue(snooze.contains("--minutes N"))
        XCTAssertFalse(snooze.contains("--reminder"), "notify options must not appear")
        let template = try XCTUnwrap(CLIArguments.usage(for: "template"))
        XCTAssertTrue(template.contains("template export") && template.contains("template rename"))
        XCTAssertNotNil(CLIArguments.usage(for: "notify"))
        XCTAssertNil(CLIArguments.usage(for: "bogus"))
        for name in CLIArguments.commandNames { XCTAssertNotNil(CLIArguments.usage(for: name), name) }
    }

    func testNotifyTemplateFlagsAndOptionalTitle() throws {
        // A named template may supply the title.
        let r = try request(["notify", "--app", "bidbot", "--template", "bid-won", "--metadata", "{\"amount\":\"$4,200\"}",
                             "--layout", "hero", "--accent", "#22C55E", "--no-subtitle", "--no-time", "--max-body-lines", "3"])
        let b = try XCTUnwrap(r.body)
        XCTAssertEqual(b["template"] as? String, "bid-won")
        XCTAssertNil(b["title"])
        XCTAssertEqual(b["layout"] as? String, "hero")
        XCTAssertEqual(b["accentColor"] as? String, "#22C55E")
        XCTAssertEqual(b["showSubtitle"] as? Bool, false)
        XCTAssertEqual(b["showTimestamp"] as? Bool, false)
        XCTAssertNil(b["showBody"])
        XCTAssertEqual(b["maxBodyLines"] as? Int, 3)
        // Without a template the title stays mandatory.
        XCTAssertThrowsError(try request(["notify", "--app", "a"]))
        XCTAssertThrowsError(try request(["notify", "--app", "a", "--layout", "diagonal", "--title", "t"]))
        XCTAssertThrowsError(try request(["notify", "--app", "a", "--title", "t", "--max-body-lines", "0"]))
    }

    func testSnoozeUnsnoozeCompose() throws {
        var r = try request(["snooze", "--app", "bidbot", "--id", "bid-42", "--minutes", "15"])
        XCTAssertEqual(r.method, "POST"); XCTAssertEqual(r.path, "/v1/snooze")
        XCTAssertEqual(r.body?["minutes"] as? Double, 15)
        XCTAssertEqual(r.body?["id"] as? String, "bid-42")
        XCTAssertThrowsError(try request(["snooze", "--app", "a", "--id", "x"]))
        XCTAssertThrowsError(try request(["snooze", "--app", "a", "--id", "x", "--minutes", "0"]))
        XCTAssertThrowsError(try request(["snooze", "--app", "a", "--id", "x", "--minutes", "99999"]))
        r = try request(["unsnooze", "--app", "bidbot", "--id", "bid-42"])
        XCTAssertEqual(r.path, "/v1/unsnooze")
        XCTAssertThrowsError(try request(["unsnooze", "--app", "a"]))
        r = try request(["compose"])
        XCTAssertEqual(r.method, "POST"); XCTAssertEqual(r.path, "/v1/compose")
        XCTAssertThrowsError(try request(["compose", "--app", "a"]))
    }
}
