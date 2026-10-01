import Foundation
import HeraldClient

/// The MCP server: decodes lines, answers `initialize`, `ping`, `tools/*` and `resources/*`, and ignores
/// notifications. It does no I/O of its own; `main.swift` feeds it lines and writes what it returns.
final class MCPServer: @unchecked Sendable {
    static let serverName = "herald-mcp"
    static let serverVersion = "1.1.0"
    /// The protocol revision this server implements.
    static let latestProtocolVersion = "2025-06-18"
    /// Revisions it also accepts: the tool and resource shapes it uses are the same in these.
    static let supportedProtocolVersions = ["2025-06-18", "2025-03-26", "2024-11-05"]

    static let instructions = """
    Herald shows persistent, interactive banners on the user's Mac. These tools design how one app's notifications look \
    and what their buttons do. Workflow: herald_status (is it running?); get_manifest (the fields the app sends: their keys \
    are the {tokens} a template binds, and the actions it offers); component_schema (what a template may contain); \
    put_template (validated; errors name the cell); render_preview (look at the picture, light and dark, with long and \
    missing values via `data`); add_action_rule and list_shortcuts (hide or relabel the issuer's buttons, add your own: \
    Apple Shortcut, shell command, script, URL); send_test (shows the real banner). This server never presses a banner \
    button and never runs an action itself.
    """

    private(set) var clientInfo: JSONValue?
    private(set) var negotiatedProtocolVersion: String?
    private(set) var initializedByClient = false
    var log: (String) -> Void

    let tools: MCPTools
    let resources: MCPResources

    init(client: HeraldClient, previewDirectory: URL, log: @escaping (String) -> Void = { _ in }) {
        let tools = MCPTools(client: client, previewDirectory: previewDirectory)
        self.tools = tools
        self.resources = MCPResources(client: client, describe: { tools.describe($0) })
        self.log = log
    }

    // MARK: - Lines in, lines out

    /// Handles one input line and returns the line to write, or nil when nothing is to be sent (a notification).
    func process(line: String) async -> String? {
        switch RPC.parse(line: line) {
        case .single(let message):
            return await handle(message).map(RPC.encode)
        case .batch(let messages):
            var replies: [JSONValue] = []
            for m in messages { if let r = await handle(m) { replies.append(r) } }
            return replies.isEmpty ? nil : RPC.encode(.array(replies))
        }
    }

    func handle(_ message: RPCMessage) async -> JSONValue? {
        switch message {
        case .invalid(let id, let error):
            log("invalid message: \(error.message)")
            return RPC.failure(id: id, error)
        case .response:
            return nil
        case .notification(let method, let params):
            handleNotification(method, params)
            return nil
        case .request(let id, let method, let params):
            do { return RPC.result(id: id, try await handleRequest(method, params)) }
            catch let error as RPCError { return RPC.failure(id: id, error) }
            catch { return RPC.failure(id: id, .internalError("\(error)")) }
        }
    }

    private func handleNotification(_ method: String, _ params: JSONValue?) {
        switch method {
        case "notifications/initialized": initializedByClient = true
        case "notifications/cancelled": break       // requests run to completion one at a time
        default: log("ignored notification \(method)")
        }
    }

    // MARK: - Requests

    private func handleRequest(_ method: String, _ params: JSONValue?) async throws -> JSONValue {
        switch method {
        case "initialize": return try initialize(params)
        case "ping": return .object([:])
        case "tools/list":
            return .object(["tools": .array(MCPToolCatalog.all.map(\.jsonValue))])
        case "tools/call":
            guard case .string(let name)? = params?["name"] else { throw RPCError.invalidParams("tools/call needs a tool 'name'") }
            let arguments = params?["arguments"]
            if let a = arguments, !a.isNull, a.objectValue == nil { throw RPCError.invalidParams("'arguments' must be an object") }
            log("tools/call \(name)")
            return try await tools.call(name, arguments: arguments).jsonValue
        case "resources/list":
            return .object(["resources": .array(await resources.list())])
        case "resources/templates/list":
            return .object(["resourceTemplates": .array(MCPResources.uriTemplates)])
        case "resources/read":
            guard case .string(let uri)? = params?["uri"] else { throw RPCError.invalidParams("resources/read needs a 'uri'") }
            log("resources/read \(uri)")
            return try await resources.read(uri: uri)
        default:
            throw RPCError.methodNotFound(method)
        }
    }

    /// Version negotiation: a revision we support is echoed; anything else is answered with our latest and the
    /// client decides whether it can live with it (MCP lifecycle).
    private func initialize(_ params: JSONValue?) throws -> JSONValue {
        guard case .string(let requested)? = params?["protocolVersion"] else {
            throw RPCError.invalidParams("initialize needs a 'protocolVersion'")
        }
        let version = Self.supportedProtocolVersions.contains(requested) ? requested : Self.latestProtocolVersion
        negotiatedProtocolVersion = version
        clientInfo = params?["clientInfo"]
        if case .string(let name)? = clientInfo?["name"] { log("client \(name) \(clientInfo?["version"]?.stringValue ?? ""), protocol \(version)") }
        return .object([
            "protocolVersion": .string(version),
            "capabilities": .object([
                "tools": .object(["listChanged": .bool(false)]),
                "resources": .object(["subscribe": .bool(false), "listChanged": .bool(false)]),
            ]),
            "serverInfo": .object(["name": .string(Self.serverName), "title": .string("Herald"),
                                   "version": .string(Self.serverVersion)]),
            "instructions": .string(Self.instructions),
        ])
    }
}
