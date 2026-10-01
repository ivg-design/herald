import XCTest
@testable import HeraldCore

final class MCPInstallerTests: XCTestCase {
    private var dir: URL!
    override func setUp() {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("mcpinst-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    override func tearDown() { try? FileManager.default.removeItem(at: dir) }

    private func installer(claude: [String] = [], run: @escaping (String, [String]) -> (Int32, String) = { _, _ in (1, "") }) -> MCPInstaller {
        MCPInstaller(serverPath: "/App/Herald.app/Contents/Helpers/herald-mcp",
                     codexConfig: dir.appendingPathComponent(".codex/config.toml"),
                     desktopConfig: dir.appendingPathComponent("Claude/claude_desktop_config.json"),
                     claudeCandidates: claude, run: run)
    }

    func testCodexReplacesExistingTableOnly() {
        let old = """
        model = "x"

        [mcp_servers.other]
        command = "/bin/other"

        [mcp_servers.herald]
        command = "/old/herald-mcp"
        args = ["--x"]

        [profiles.a]
        k = 1

        """
        let out = MCPInstaller.codexMerge(old, command: "/new/herald-mcp")
        XCTAssertTrue(out.contains("command = \"/new/herald-mcp\""))
        XCTAssertFalse(out.contains("/old/herald-mcp"))
        XCTAssertFalse(out.contains("--x"))
        XCTAssertTrue(out.contains("[mcp_servers.other]\ncommand = \"/bin/other\""))
        XCTAssertTrue(out.contains("[profiles.a]\nk = 1"))
        XCTAssertTrue(out.contains("model = \"x\""))
        XCTAssertEqual(out.components(separatedBy: "[mcp_servers.herald]").count, 2)
    }

    func testCodexAppendsWhenAbsent() {
        let out = MCPInstaller.codexMerge("model = \"x\"", command: "/p/herald-mcp")
        XCTAssertEqual(out, "model = \"x\"\n\n[mcp_servers.herald]\ncommand = \"/p/herald-mcp\"\nargs = []\n")
        XCTAssertEqual(MCPInstaller.codexMerge("", command: "/p").hasPrefix("[mcp_servers.herald]"), true)
    }

    func testCodexEscapesQuotesAndLastTableReplaced() {
        let out = MCPInstaller.codexMerge("[mcp_servers.herald]\ncommand = \"/a\"\n", command: "/My \"Apps\"/mcp")
        XCTAssertTrue(out.contains("command = \"/My \\\"Apps\\\"/mcp\""))
        XCTAssertFalse(out.contains("\"/a\""))
    }

    func testCodexInstallWritesBackupAndStatus() throws {
        let inst = installer()
        try FileManager.default.createDirectory(at: inst.codexConfig.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "[mcp_servers.other]\ncommand = \"/o\"\n".write(to: inst.codexConfig, atomically: true, encoding: .utf8)
        XCTAssertEqual(inst.status(.codex), .notInstalled)
        let r = inst.installCodex()
        XCTAssertTrue(r.ok); XCTAssertEqual(r.touched, inst.codexConfig.path)
        let bak = try String(contentsOfFile: inst.codexConfig.path + ".bak", encoding: .utf8)
        XCTAssertEqual(bak, "[mcp_servers.other]\ncommand = \"/o\"\n")
        let now = try String(contentsOf: inst.codexConfig, encoding: .utf8)
        XCTAssertTrue(now.contains("[mcp_servers.other]") && now.contains("[mcp_servers.herald]"))
        XCTAssertEqual(inst.status(.codex), .installed)
    }

    func testCodexClientNotFound() {
        XCTAssertEqual(installer().status(.codex), .clientNotFound)
    }

    func testDesktopMergePreservesOtherServers() throws {
        let old = #"{"theme":"dark","mcpServers":{"fs":{"command":"/x","args":["a"]}}}"#
        let out = try MCPInstaller.desktopMerge(Data(old.utf8), command: "/h/herald-mcp")
        let o = try JSONSerialization.jsonObject(with: out) as! [String: Any]
        XCTAssertEqual(o["theme"] as? String, "dark")
        let s = o["mcpServers"] as! [String: Any]
        XCTAssertEqual((s["fs"] as! [String: Any])["command"] as? String, "/x")
        XCTAssertEqual((s["herald"] as! [String: Any])["command"] as? String, "/h/herald-mcp")
        XCTAssertFalse(String(decoding: out, as: UTF8.self).contains("\\/"))
    }

    func testDesktopMergeCreatesAndRejectsInvalid() throws {
        let o = try JSONSerialization.jsonObject(with: MCPInstaller.desktopMerge(nil, command: "/p")) as! [String: Any]
        XCTAssertNotNil((o["mcpServers"] as? [String: Any])?["herald"])
        XCTAssertThrowsError(try MCPInstaller.desktopMerge(Data("not json".utf8), command: "/p"))
    }

    func testDesktopInstallBackupAndInvalidLeftUntouched() throws {
        let inst = installer()
        let dir = inst.desktopConfig.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        XCTAssertEqual(inst.status(.claudeDesktop), .notInstalled)
        try Data(#"{"mcpServers":{"fs":{"command":"/x"}}}"#.utf8).write(to: inst.desktopConfig)
        XCTAssertTrue(inst.installClaudeDesktop().ok)
        XCTAssertTrue(FileManager.default.fileExists(atPath: inst.desktopConfig.path + ".bak"))
        XCTAssertEqual(inst.status(.claudeDesktop), .installed)
        try Data("garbage".utf8).write(to: inst.desktopConfig)
        XCTAssertFalse(inst.installClaudeDesktop().ok)
        XCTAssertEqual(try String(contentsOf: inst.desktopConfig, encoding: .utf8), "garbage")
    }

    func testClaudeCodeStatusAndAlreadyExists() {
        var calls: [[String]] = []
        let exe = "/bin/sh"
        var exists = false
        let inst = installer(claude: [exe]) { _, args in
            calls.append(args)
            if args.starts(with: ["mcp", "get"]) { return (exists ? 0 : 1, "") }
            if args.starts(with: ["mcp", "add"]) { return exists ? (1, "MCP server herald already exists in user config") : (0, "Added") }
            if args.starts(with: ["mcp", "remove"]) { exists = false; return (0, "") }
            return (1, "")
        }
        XCTAssertEqual(inst.status(.claudeCode), .notInstalled)
        exists = true
        XCTAssertEqual(inst.status(.claudeCode), .installed)
        let r = inst.installClaudeCode()
        XCTAssertFalse(r.ok); XCTAssertTrue(r.alreadyExists)
        let r2 = inst.installClaudeCode(reinstall: true)
        XCTAssertTrue(r2.ok)
        XCTAssertTrue(calls.contains(["mcp", "remove", "herald", "--scope", "user"]))
        XCTAssertEqual(r2.touched, "claude mcp add --scope user herald -- /App/Herald.app/Contents/Helpers/herald-mcp")
    }

    func testClaudeNotFound() {
        XCTAssertEqual(installer().status(.claudeCode), .clientNotFound)
    }

    func testGenericConfigAndToolsListParsing() throws {
        let g = installer().genericJSON
        let o = try JSONSerialization.jsonObject(with: Data(g.utf8)) as! [String: Any]
        let h = (o["mcpServers"] as! [String: Any])["herald"] as! [String: Any]
        XCTAssertEqual(h["command"] as? String, "/App/Herald.app/Contents/Helpers/herald-mcp")
        XCTAssertEqual((h["args"] as? [Any])?.count, 0)
        let out = #"{"jsonrpc":"2.0","id":1,"result":{}}"# + "\n" + #"{"jsonrpc":"2.0","id":2,"result":{"tools":[{},{},{}]}}"#
        XCTAssertEqual(try MCPInstaller.parseToolsList(out).get(), 3)
        XCTAssertThrowsError(try MCPInstaller.parseToolsList("").get())
    }
}
