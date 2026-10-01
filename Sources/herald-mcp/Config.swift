import Foundation

/// Command line and environment of `herald-mcp`.
///
/// Normally there is nothing to configure: the token and port are read from `~/Library/Application
/// Support/Herald`, like the `herald` CLI does. The overrides are for a second Herald (a debug build on
/// another port) and for tests.
struct MCPConfig: Equatable {
    enum Mode: Equatable { case run, help, version }

    var mode: Mode = .run
    var supportDirectory: URL
    var port: Int?
    var token: String?
    var previewDirectory: URL
    /// Log every request to stderr.
    var debug = false

    struct ParseError: Error, Equatable { var message: String }

    static let usage = """
    herald-mcp \(MCPServer.serverVersion): MCP server for Herald (stdio, JSON-RPC 2.0, protocol \(MCPServer.latestProtocolVersion))

    Usage: herald-mcp [--support-dir DIR] [--port N] [--token T] [--preview-dir DIR] [--debug]

    Reads one JSON-RPC message per line from stdin and writes one per line to stdout; logs go to stderr.
    It talks to the running Herald.app over its loopback API, using the token and port files in the support
    directory (default ~/Library/Application Support/Herald).

    Environment: HERALD_SUPPORT_DIR, HERALD_PORT, HERALD_TOKEN, HERALD_PREVIEW_DIR, HERALD_MCP_DEBUG=1.
    Preview PNGs are saved under $TMPDIR/herald-previews unless --preview-dir says otherwise.

    Add it to Claude Code:  claude mcp add herald -- /usr/local/bin/herald-mcp
    """

    static func parse(arguments: [String], environment: [String: String],
                      defaultSupportDirectory: URL, temporaryDirectory: URL = FileManager.default.temporaryDirectory) throws -> MCPConfig {
        func expand(_ p: String) -> URL { URL(fileURLWithPath: (p as NSString).expandingTildeInPath) }
        func port(_ s: String, from: String) throws -> Int {
            guard let n = Int(s), (1...65535).contains(n) else { throw ParseError(message: "\(from) must be a port number (1-65535), got '\(s)'") }
            return n
        }

        var config = MCPConfig(
            supportDirectory: environment["HERALD_SUPPORT_DIR"].flatMap { $0.isEmpty ? nil : expand($0) } ?? defaultSupportDirectory,
            port: nil, token: environment["HERALD_TOKEN"].flatMap { $0.isEmpty ? nil : $0 },
            previewDirectory: environment["HERALD_PREVIEW_DIR"].flatMap { $0.isEmpty ? nil : expand($0) }
                ?? temporaryDirectory.appendingPathComponent("herald-previews", isDirectory: true))
        if let p = environment["HERALD_PORT"], !p.isEmpty { config.port = try port(p, from: "HERALD_PORT") }
        if let d = environment["HERALD_MCP_DEBUG"], !d.isEmpty, d != "0" { config.debug = true }

        var it = arguments.makeIterator()
        func value(_ flag: String) throws -> String {
            guard let v = it.next() else { throw ParseError(message: "\(flag) needs a value") }
            return v
        }
        while let arg = it.next() {
            switch arg {
            case "-h", "--help": config.mode = .help
            case "-v", "--version": config.mode = .version
            case "--debug": config.debug = true
            case "--support-dir": config.supportDirectory = expand(try value(arg))
            case "--preview-dir": config.previewDirectory = expand(try value(arg))
            case "--port": config.port = try port(try value(arg), from: "--port")
            case "--token": config.token = try value(arg)
            default: throw ParseError(message: "unknown argument '\(arg)'")
            }
        }
        return config
    }
}
