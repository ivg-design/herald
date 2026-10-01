import Foundation

/// One-click installation of the bundled `herald-mcp` server into agent clients (DESIGN 7.6, docs/MCP.md).
/// Foundation only, so it is unit tested through HeraldCore. Every path is injectable; tests never touch the
/// user's real configs.
public enum MCPClient: String, CaseIterable, Identifiable {
    case claudeCode = "Claude Code", codex = "Codex", claudeDesktop = "Claude Desktop", generic = "Generic"
    public var id: String { rawValue }
}

public enum MCPClientStatus: Equatable {
    case installed, notInstalled, clientNotFound
    public var label: String {
        switch self {
        case .installed: return "Installed"
        case .notInstalled: return "Not installed"
        case .clientNotFound: return "Client not found"
        }
    }
}

public struct MCPInstallResult: Equatable {
    public var ok: Bool
    public var message: String
    /// The file or command that was touched.
    public var touched: String
    /// Claude Code only: `herald` is already registered, so offer Reinstall.
    public var alreadyExists = false
}

public struct MCPInstaller {
    public var serverPath: String
    public var codexConfig: URL
    public var desktopConfig: URL
    public var claudeCandidates: [String]
    /// Runs an executable with arguments; returns (exit status, combined output).
    public var run: (_ exe: String, _ args: [String]) -> (Int32, String)

    public static func bundledServerPath(bundle: Bundle = .main) -> String {
        let p = bundle.bundleURL.appendingPathComponent("Contents/Helpers/herald-mcp").path
        return FileManager.default.isExecutableFile(atPath: p) ? p : "/usr/local/bin/herald-mcp"
    }
    public static func bundledCLIPath(bundle: Bundle = .main) -> String {
        bundle.bundleURL.appendingPathComponent("Contents/Helpers/herald").path
    }

    public init(serverPath: String = MCPInstaller.bundledServerPath(),
                codexConfig: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/config.toml"),
                desktopConfig: URL = FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent("Library/Application Support/Claude/claude_desktop_config.json"),
                claudeCandidates: [String]? = nil,
                run: @escaping (String, [String]) -> (Int32, String) = MCPInstaller.runProcess) {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        self.serverPath = serverPath
        self.codexConfig = codexConfig
        self.desktopConfig = desktopConfig
        self.claudeCandidates = claudeCandidates ?? [
            "\(home)/.local/bin/claude", "/opt/homebrew/bin/claude", "/usr/local/bin/claude",
            "\(home)/.claude/local/claude", "\(home)/.npm-global/bin/claude", "\(home)/.bun/bin/claude"]
        self.run = run
    }

    // MARK: Process

    public static func runProcess(_ exe: String, _ args: [String]) -> (Int32, String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = args
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = (env["PATH"] ?? "") + ":/opt/homebrew/bin:/usr/local/bin:\(NSHomeDirectory())/.local/bin"
        p.environment = env
        let pipe = Pipe()
        p.standardOutput = pipe; p.standardError = pipe; p.standardInput = FileHandle.nullDevice
        do { try p.run() } catch { return (127, "\(error.localizedDescription)") }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
    }

    public func claudeBinary() -> String? {
        let fm = FileManager.default
        for c in claudeCandidates where fm.isExecutableFile(atPath: c) { return c }
        let (st, out) = run("/bin/zsh", ["-lc", "command -v claude"])
        let line = out.split(separator: "\n").last.map(String.init) ?? ""
        return st == 0 && fm.isExecutableFile(atPath: line) ? line : nil
    }

    // MARK: Pure config logic

    static func tomlQuote(_ s: String) -> String {
        "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    static func isHeraldHeader(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard t.hasPrefix("[") && !t.hasPrefix("[[") else { return false }
        let compact = t.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)[0]
            .trimmingCharacters(in: .whitespaces).replacingOccurrences(of: " ", with: "")
        return compact == "[mcp_servers.herald]" || compact == "[mcp_servers.\"herald\"]" || compact == "[mcp_servers.'herald']"
    }

    static func isHeader(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces).hasPrefix("[")
    }

    public static func codexHasHerald(_ text: String) -> Bool {
        text.components(separatedBy: "\n").contains(where: isHeraldHeader)
    }

    /// Replaces an existing `[mcp_servers.herald]` table (up to the next header) or appends one.
    public static func codexMerge(_ text: String, command: String) -> String {
        let table = ["[mcp_servers.herald]", "command = \(tomlQuote(command))", "args = []"]
        var lines = text.components(separatedBy: "\n")
        if let start = lines.firstIndex(where: isHeraldHeader) {
            var end = start + 1
            while end < lines.count && !isHeader(lines[end]) { end += 1 }
            // Keep blank separation before the next header.
            lines.replaceSubrange(start..<end, with: table + (end < lines.count ? [""] : []))
            return lines.joined(separator: "\n")
        }
        var out = text
        if !out.isEmpty && !out.hasSuffix("\n") { out += "\n" }
        if !out.isEmpty { out += "\n" }
        return out + table.joined(separator: "\n") + "\n"
    }

    enum JSONError: Error, LocalizedError {
        case invalid
        var errorDescription: String? { "the existing file is not a valid JSON object; left untouched" }
    }

    static func parseObject(_ data: Data) throws -> [String: Any] {
        if data.allSatisfy({ $0 == 0x20 || $0 == 0x0A || $0 == 0x0D || $0 == 0x09 }) { return [:] }
        guard let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw JSONError.invalid }
        return o
    }

    public static func desktopHasHerald(_ data: Data) -> Bool {
        guard let o = try? parseObject(data), let s = o["mcpServers"] as? [String: Any] else { return false }
        return s["herald"] != nil
    }

    /// Merges the herald server into a Claude Desktop config, keeping every other key and server.
    public static func desktopMerge(_ data: Data?, command: String) throws -> Data {
        var root = try parseObject(data ?? Data())
        var servers = root["mcpServers"] as? [String: Any] ?? [:]
        servers["herald"] = ["command": command]
        root["mcpServers"] = servers
        return try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    }

    public var genericJSON: String {
        let o: [String: Any] = ["mcpServers": ["herald": ["command": serverPath, "args": [String]()]]]
        let d = (try? JSONSerialization.data(withJSONObject: o, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])) ?? Data()
        return String(decoding: d, as: UTF8.self)
    }
    public var genericCommandLine: String { "claude mcp add --scope user herald -- \(serverPath)" }
    public var genericClipboardText: String {
        "\(genericJSON)\n\nstdio command: \(serverPath)\n\(genericCommandLine)\n"
    }

    // MARK: Status

    public func status(_ client: MCPClient) -> MCPClientStatus {
        let fm = FileManager.default
        switch client {
        case .generic: return .notInstalled
        case .claudeCode:
            guard let claude = claudeBinary() else { return .clientNotFound }
            return run(claude, ["mcp", "get", "herald"]).0 == 0 ? .installed : .notInstalled
        case .codex:
            let dir = codexConfig.deletingLastPathComponent().path
            guard fm.fileExists(atPath: codexConfig.path) || fm.fileExists(atPath: dir) else { return .clientNotFound }
            guard let t = try? String(contentsOf: codexConfig, encoding: .utf8) else { return .notInstalled }
            return Self.codexHasHerald(t) ? .installed : .notInstalled
        case .claudeDesktop:
            guard fm.fileExists(atPath: desktopConfig.deletingLastPathComponent().path) else { return .clientNotFound }
            guard let d = try? Data(contentsOf: desktopConfig) else { return .notInstalled }
            return Self.desktopHasHerald(d) ? .installed : .notInstalled
        }
    }

    // MARK: Install

    private func backup(_ url: URL) throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return }
        let bak = URL(fileURLWithPath: url.path + ".bak")
        try? fm.removeItem(at: bak)
        try fm.copyItem(at: url, to: bak)
    }

    public func installClaudeCode(reinstall: Bool = false) -> MCPInstallResult {
        guard let claude = claudeBinary() else {
            return .init(ok: false, message: "The claude command was not found.", touched: "claude mcp add")
        }
        let addCmd = "claude mcp add --scope user herald -- \(serverPath)"
        if reinstall { _ = run(claude, ["mcp", "remove", "herald", "--scope", "user"]) }
        let (st, out) = run(claude, ["mcp", "add", "--scope", "user", "herald", "--", serverPath])
        if st == 0 { return .init(ok: true, message: "Registered with Claude Code (user scope).", touched: addCmd) }
        if out.lowercased().contains("already exists") {
            return .init(ok: false, message: "herald is already registered in Claude Code. Use Reinstall to replace it.",
                         touched: addCmd, alreadyExists: true)
        }
        return .init(ok: false, message: out.isEmpty ? "claude exited with status \(st)." : out, touched: addCmd)
    }

    public func installCodex() -> MCPInstallResult {
        do {
            let fm = FileManager.default
            let old = (try? String(contentsOf: codexConfig, encoding: .utf8)) ?? ""
            try fm.createDirectory(at: codexConfig.deletingLastPathComponent(), withIntermediateDirectories: true)
            try backup(codexConfig)
            try Self.codexMerge(old, command: serverPath).write(to: codexConfig, atomically: true, encoding: .utf8)
            return .init(ok: true, message: "Added [mcp_servers.herald]. Restart Codex to pick it up. Backup: config.toml.bak.",
                         touched: codexConfig.path)
        } catch {
            return .init(ok: false, message: error.localizedDescription, touched: codexConfig.path)
        }
    }

    public func installClaudeDesktop() -> MCPInstallResult {
        do {
            let fm = FileManager.default
            let old = try? Data(contentsOf: desktopConfig)
            let merged = try Self.desktopMerge(old, command: serverPath)
            try fm.createDirectory(at: desktopConfig.deletingLastPathComponent(), withIntermediateDirectories: true)
            try backup(desktopConfig)
            try merged.write(to: desktopConfig, options: .atomic)
            return .init(ok: true, message: "Added herald to mcpServers. Restart Claude Desktop. Backup: .bak next to the file.",
                         touched: desktopConfig.path)
        } catch {
            return .init(ok: false, message: error.localizedDescription, touched: desktopConfig.path)
        }
    }

    // MARK: CLI

    public func installCLI(source: String = MCPInstaller.bundledCLIPath(),
                           destDir: String = "/usr/local/bin") -> MCPInstallResult {
        let fm = FileManager.default
        let dest = destDir + "/herald"
        guard fm.isExecutableFile(atPath: source) else {
            return .init(ok: false, message: "The bundled herald tool was not found (run from the built Herald.app).", touched: source)
        }
        if fm.isWritableFile(atPath: destDir) {
            do {
                try? fm.removeItem(atPath: dest)
                try fm.copyItem(atPath: source, toPath: dest)
                return .init(ok: true, message: "Installed the herald command line tool.", touched: dest)
            } catch { return .init(ok: false, message: error.localizedDescription, touched: dest) }
        }
        func sh(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }
        let script = "mkdir -p \(sh(destDir)) && cp -f \(sh(source)) \(sh(dest)) && chmod 755 \(sh(dest))"
        let esc = script.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let (st, out) = run("/usr/bin/osascript", ["-e", "do shell script \"\(esc)\" with administrator privileges"])
        return st == 0 ? .init(ok: true, message: "Installed the herald command line tool (administrator).", touched: dest)
                       : .init(ok: false, message: out.isEmpty ? "Cancelled or failed (status \(st))." : out, touched: dest)
    }

    // MARK: Test connection

    /// Runs the server with a scripted initialize + tools/list over stdio. Returns the tool count or an error.
    public func testConnection(timeout: TimeInterval = 15) -> Result<Int, MCPTestError> {
        guard FileManager.default.isExecutableFile(atPath: serverPath) else {
            return .failure(MCPTestError(message: "Server not found at \(serverPath)"))
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: serverPath)
        let inp = Pipe(), outp = Pipe()
        p.standardInput = inp; p.standardOutput = outp; p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return .failure(MCPTestError(message: error.localizedDescription)) }
        let script = """
        {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"herald-settings","version":"1"}}}
        {"jsonrpc":"2.0","method":"notifications/initialized"}
        {"jsonrpc":"2.0","id":2,"method":"tools/list"}

        """
        inp.fileHandleForWriting.write(Data(script.utf8))
        try? inp.fileHandleForWriting.close()
        let killer = DispatchWorkItem { if p.isRunning { p.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: killer)
        let data = outp.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        killer.cancel()
        return Self.parseToolsList(String(decoding: data, as: UTF8.self))
    }

    public static func parseToolsList(_ output: String) -> Result<Int, MCPTestError> {
        var sawInit = false
        for line in output.split(separator: "\n") {
            guard let d = line.data(using: .utf8), let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { continue }
            if let e = o["error"] as? [String: Any] { return .failure(MCPTestError(message: (e["message"] as? String) ?? "server error")) }
            if (o["id"] as? Int) == 1 { sawInit = true }
            if (o["id"] as? Int) == 2, let r = o["result"] as? [String: Any], let tools = r["tools"] as? [Any] { return .success(tools.count) }
        }
        return .failure(MCPTestError(message: sawInit ? "initialize worked but tools/list returned nothing." : "No response from the server."))
    }
}

public struct MCPTestError: Error, Equatable { public var message: String }
