import Foundation
import HeraldClient

// herald-mcp: an MCP server (stdio) that lets an agent author Herald notification templates.
// stdin: one JSON-RPC message per line. stdout: one JSON-RPC message per line, nothing else. stderr: logs.

func logLine(_ text: String) {
    try? FileHandle.standardError.write(contentsOf: Data(("herald-mcp: " + text + "\n").utf8))
}

signal(SIGPIPE, SIG_IGN)

let config: MCPConfig
do {
    config = try MCPConfig.parse(arguments: Array(CommandLine.arguments.dropFirst()),
                                 environment: ProcessInfo.processInfo.environment,
                                 defaultSupportDirectory: HeraldPaths.defaultSupportDirectory)
} catch let error as MCPConfig.ParseError {
    logLine("\(error.message)\n\(MCPConfig.usage)")
    exit(2)
}

switch config.mode {
case .help:
    print(MCPConfig.usage)
    exit(0)
case .version:
    print("herald-mcp \(MCPServer.serverVersion)")
    exit(0)
case .run:
    break
}

let client = HeraldClient(supportDirectory: config.supportDirectory, port: config.port, token: config.token)
let server = MCPServer(client: client, previewDirectory: config.previewDirectory, defaultApp: config.agentApp,
                       log: config.debug ? { logLine($0) } : { _ in })
logLine("\(MCPServer.serverVersion) ready (Herald at 127.0.0.1:\(client.port), support directory \(config.supportDirectory.path)" + (config.agentApp.map { ", sending as \($0)" } ?? "") + ")")

while let line = readLine(strippingNewline: true) {
    if line.allSatisfy(\.isWhitespace) { continue }
    if let reply = await server.process(line: line) {
        try? FileHandle.standardOutput.write(contentsOf: Data((reply + "\n").utf8))
    }
}
logLine("stdin closed, exiting")
