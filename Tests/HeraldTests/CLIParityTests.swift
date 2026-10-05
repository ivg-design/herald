import XCTest
@testable import HeraldClient

/// `herald` commands for the parity routes: each is exactly one request.
final class CLIParityTests: XCTestCase {
    private func request(_ args: [String], input: [String: Data] = [:]) throws -> CLIRequest {
        let inv = try CLIArguments.parse(args) { src in
            guard let d = input[src] else { throw CocoaError(.fileNoSuchFile) }
            return d
        }
        guard case .request(let r) = inv.action else { XCTFail("not a request: \(args)"); throw CLIParseError("x") }
        return r
    }

    private func query(_ r: CLIRequest) -> [String: String] { Dictionary(uniqueKeysWithValues: r.query.map { ($0.name, $0.value) }) }

    func testSettings() throws {
        var r = try request(["settings"])
        XCTAssertEqual(r.method, "GET"); XCTAssertEqual(r.path, "/v1/settings")
        r = try request(["settings", "get"])
        XCTAssertEqual(r.path, "/v1/settings")
        r = try request(["settings", "set", "muteAllSounds=true", "voiceSpeed=1.2", "stacking=bySender", "voiceSystem=null", "port=48701"])
        XCTAssertEqual(r.method, "PUT"); XCTAssertEqual(r.path, "/v1/settings")
        let b = try XCTUnwrap(r.body)
        XCTAssertEqual(b["muteAllSounds"] as? Bool, true)
        XCTAssertEqual(b["voiceSpeed"] as? Double, 1.2)
        XCTAssertEqual(b["stacking"] as? String, "bySender", "plain words stay strings")
        XCTAssertTrue(b["voiceSystem"] is NSNull)
        XCTAssertEqual(b["port"] as? Int, 48701)
        XCTAssertThrowsError(try request(["settings", "set"]))
        XCTAssertThrowsError(try request(["settings", "set", "novalue"]))
        XCTAssertThrowsError(try request(["settings", "reset"]))
    }

    func testAppsSettings() throws {
        var r = try request(["apps"])
        XCTAssertEqual(r.path, "/v1/apps")
        r = try request(["apps", "settings"])
        XCTAssertEqual(r.path, "/v1/apps/settings"); XCTAssertTrue(r.query.isEmpty)
        r = try request(["apps", "settings", "--app", "demo"])
        XCTAssertEqual(query(r), ["app": "demo"])
        r = try request(["apps", "set", "--app", "demo", "muteBanners=true", "corner=bottomLeft", "timeout=8", "stacking=null"])
        XCTAssertEqual(r.method, "PUT"); XCTAssertEqual(r.path, "/v1/apps/settings")
        let b = try XCTUnwrap(r.body)
        XCTAssertEqual(b["app"] as? String, "demo"); XCTAssertEqual(b["muteBanners"] as? Bool, true)
        XCTAssertEqual(b["corner"] as? String, "bottomLeft"); XCTAssertEqual(b["timeout"] as? Int, 8); XCTAssertTrue(b["stacking"] is NSNull)
        r = try request(["apps", "set", "sound=Ping", "--app=demo"])
        XCTAssertEqual(r.body?["app"] as? String, "demo")
        XCTAssertThrowsError(try request(["apps", "set", "muteBanners=true"]), "needs --app")
        XCTAssertThrowsError(try request(["apps", "set", "--app", "demo"]), "needs a pair")
    }

    func testAssets() throws {
        var r = try request(["assets", "list", "--app", "demo"])
        XCTAssertEqual(r.path, "/v1/assets"); XCTAssertEqual(query(r), ["app": "demo"])
        r = try request(["assets", "add", "--app", "demo", "--file", "/tmp/x.riv", "--name", "bell.riv"])
        XCTAssertEqual(r.method, "POST")
        XCTAssertEqual(r.body?["path"] as? String, "/tmp/x.riv"); XCTAssertEqual(r.body?["name"] as? String, "bell.riv")
        r = try request(["assets", "add", "--app", "demo", "--file", "rel/x.png"])
        XCTAssertTrue((r.body?["path"] as? String)?.hasPrefix("/") == true, "paths are made absolute: Herald runs elsewhere")
        r = try request(["assets", "rm", "--app", "demo", "--file", "x.riv"])
        XCTAssertEqual(r.method, "DELETE"); XCTAssertEqual(query(r), ["app": "demo", "file": "x.riv"])
        XCTAssertThrowsError(try request(["assets"]))
        XCTAssertThrowsError(try request(["assets", "add", "--app", "demo"]))
    }

    func testSymbolsAndHistory() throws {
        var r = try request(["symbols", "arrow", "up", "--category", "arrows", "--limit", "10"])
        XCTAssertEqual(r.path, "/v1/symbols"); XCTAssertEqual(query(r), ["q": "arrow up", "category": "arrows", "limit": "10"])
        r = try request(["symbols"])
        XCTAssertTrue(r.query.isEmpty)

        r = try request(["history", "search", "invoice", "paid", "--app", "demo", "--limit", "5"])
        XCTAssertEqual(r.path, "/v1/history/search"); XCTAssertEqual(query(r), ["q": "invoice paid", "app": "demo", "limit": "5"])
        r = try request(["history", "reshow", "--app", "demo", "--id", "a"])
        XCTAssertEqual(r.method, "POST"); XCTAssertEqual(r.path, "/v1/history/reshow"); XCTAssertEqual(r.body?["id"] as? String, "a")
        r = try request(["history", "delete", "--app", "demo", "--id", "a"])
        XCTAssertEqual(r.method, "DELETE"); XCTAssertEqual(r.path, "/v1/history/item")
        r = try request(["history", "export", "--app", "demo", "--out", "/tmp/h.json"])
        XCTAssertEqual(r.path, "/v1/history/export"); XCTAssertEqual(query(r), ["app": "demo", "path": "/tmp/h.json"])
        XCTAssertThrowsError(try request(["history", "search"]))
        // The old forms still work.
        r = try request(["history", "--app", "demo", "--limit", "3"])
        XCTAssertEqual(r.path, "/v1/history")
        r = try request(["history", "--app", "demo", "--clear"])
        XCTAssertEqual(r.method, "DELETE"); XCTAssertEqual(r.path, "/v1/history")
    }

    func testTemplates() throws {
        var r = try request(["template", "list", "--app", "demo"])
        XCTAssertEqual(r.path, "/v1/templates"); XCTAssertEqual(query(r), ["app": "demo"])
        r = try request(["template", "put", "t.json"], input: ["t.json": Data(#"{"name":"a","app":"demo"}"#.utf8)])
        XCTAssertEqual(r.method, "PUT"); XCTAssertEqual(r.body?["name"] as? String, "a")
        XCTAssertThrowsError(try request(["template", "put"]))
        XCTAssertThrowsError(try request(["template", "put", "missing.json"]))
        r = try request(["template", "delete", "--app", "demo", "--name", "a"])
        XCTAssertEqual(r.method, "DELETE"); XCTAssertEqual(query(r), ["app": "demo", "name": "a"])
        r = try request(["template", "duplicate", "--app", "demo", "--name", "a", "--new-name", "b", "--to-app", "x"])
        XCTAssertEqual(r.path, "/v1/templates/duplicate"); XCTAssertEqual(r.body?["newName"] as? String, "b"); XCTAssertEqual(r.body?["toApp"] as? String, "x")
        r = try request(["template", "rename", "--app", "demo", "--name", "a", "--new-name", "b"])
        XCTAssertEqual(r.path, "/v1/templates/rename")
        XCTAssertThrowsError(try request(["template", "rename", "--app", "demo", "--name", "a"]))
        r = try request(["template", "default", "--app", "demo", "--name", "a"])
        XCTAssertEqual(r.method, "PUT"); XCTAssertEqual(r.body?["name"] as? String, "a")
        r = try request(["template", "default", "--app", "demo", "--clear"])
        XCTAssertNil(r.body?["name"])
        XCTAssertThrowsError(try request(["template", "default", "--app", "demo"]))
        // follow-up
        r = try request(["template", "follow-up", "--app", "demo", "--name", "hero", "--after", "10m", "--shortcut", "Forward", "--input", "{title}", "--label", "Fwd"])
        XCTAssertEqual(r.method, "PUT"); XCTAssertEqual(r.path, "/v1/templates/follow-up")
        XCTAssertEqual(r.body?["app"] as? String, "demo"); XCTAssertEqual(r.body?["template"] as? String, "hero")
        XCTAssertEqual(r.body?["after"] as? Int, 600); XCTAssertEqual(r.body?["shortcut"] as? String, "Forward")
        XCTAssertEqual(r.body?["input"] as? String, "{title}"); XCTAssertEqual(r.body?["label"] as? String, "Fwd")
        r = try request(["template", "follow-up", "--app", "demo", "--after", "90", "--action-ref", "cb"])
        XCTAssertEqual(r.body?["actionRef"] as? String, "cb"); XCTAssertEqual(r.body?["after"] as? Int, 90)
        XCTAssertNil(r.body?["template"])
        r = try request(["template", "follow-up", "--app", "demo", "--after", "2h", "--script", "log.sh"])
        XCTAssertEqual(r.body?["script"] as? String, "log.sh"); XCTAssertEqual(r.body?["after"] as? Int, 7200)
        r = try request(["template", "follow-up", "--app", "demo", "--after", "5m", "--command", "echo hi"])
        XCTAssertEqual(r.body?["command"] as? String, "echo hi")
        r = try request(["template", "follow-up", "--app", "demo", "--off"])
        XCTAssertEqual(r.body?["enabled"] as? Bool, false); XCTAssertNil(r.body?["after"])
        XCTAssertThrowsError(try request(["template", "follow-up", "--app", "demo"]), "needs an action")
        XCTAssertThrowsError(try request(["template", "follow-up", "--app", "demo", "--shortcut", "S"]), "needs --after")
        XCTAssertThrowsError(try request(["template", "follow-up", "--app", "demo", "--after", "soon", "--shortcut", "S"]))
        XCTAssertThrowsError(try request(["template", "follow-up", "--app", "demo", "--after", "1", "--shortcut", "S"]), "below 5 seconds")
        XCTAssertThrowsError(try request(["template", "follow-up", "--app", "demo", "--after", "5m", "--shortcut", "S", "--script", "x.sh"]))
        XCTAssertThrowsError(try request(["template", "follow-up", "--app", "demo", "--off", "--after", "5m"]))
        XCTAssertThrowsError(try request(["template", "follow-up", "--after", "5m", "--shortcut", "S"]), "needs --app")
        // export and import are unchanged.
        let inv = try CLIArguments.parse(["template", "export", "--app", "demo", "--name", "a"])
        guard case .templateExport = inv.action else { return XCTFail() }
    }

    func testVoiceMcpApprovalsManifest() throws {
        XCTAssertEqual(try request(["voice"]).path, "/v1/voice")
        XCTAssertEqual(try request(["voice", "status"]).path, "/v1/voice")
        XCTAssertEqual(try request(["voice", "use-existing"]).body?["action"] as? String, "useExisting")
        XCTAssertEqual(try request(["voice", "install"]).body?["action"] as? String, "install")
        XCTAssertThrowsError(try request(["voice", "format"]))
        XCTAssertEqual(try request(["mcp"]).path, "/v1/mcp")
        let r = try request(["mcp", "install", "codex", "--reinstall"])
        XCTAssertEqual(r.path, "/v1/mcp/install"); XCTAssertEqual(r.body?["client"] as? String, "codex"); XCTAssertEqual(r.body?["reinstall"] as? Bool, true)
        let g = try request(["mcp", "install", "generic", "--name", "My Bot", "--icon", "/tmp/bot.png"])
        XCTAssertEqual(g.body?["name"] as? String, "My Bot"); XCTAssertEqual(g.body?["icon"] as? String, "/tmp/bot.png")
        XCTAssertThrowsError(try request(["mcp", "install"]))
        XCTAssertEqual(try request(["approvals"]).path, "/v1/actions/approvals")
        let rv = try request(["approvals", "revoke", "--app", "a", "--template", "t"])
        XCTAssertEqual(rv.method, "DELETE"); XCTAssertEqual(query(rv), ["app": "a", "template": "t"])
        XCTAssertThrowsError(try request(["approvals", "grant", "--app", "a"]), "there is no grant command")
        let m = try request(["manifest", "delete", "--app", "a"])
        XCTAssertEqual(m.method, "DELETE"); XCTAssertEqual(m.path, "/v1/manifest")
    }
}
