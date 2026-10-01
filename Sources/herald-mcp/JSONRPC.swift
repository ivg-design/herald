import Foundation
import HeraldClient

/// JSON-RPC 2.0 framing for MCP over stdio: one JSON message per line (newline-delimited, UTF-8, no embedded
/// raw newlines). This file knows nothing about MCP methods; `MCPServer` does.

struct RPCError: Error, Equatable {
    var code: Int
    var message: String
    var data: JSONValue?

    init(code: Int, message: String, data: JSONValue? = nil) { self.code = code; self.message = message; self.data = data }

    static func parse(_ message: String) -> RPCError { .init(code: -32700, message: message) }
    static func invalidRequest(_ message: String) -> RPCError { .init(code: -32600, message: message) }
    static func methodNotFound(_ method: String) -> RPCError { .init(code: -32601, message: "Method not found: \(method)") }
    static func invalidParams(_ message: String) -> RPCError { .init(code: -32602, message: message) }
    static func internalError(_ message: String) -> RPCError { .init(code: -32603, message: message) }
    /// MCP: a resource that does not exist.
    static func resourceNotFound(_ uri: String) -> RPCError {
        .init(code: -32002, message: "Resource not found", data: .object(["uri": .string(uri)]))
    }
}

/// One decoded JSON-RPC message.
enum RPCMessage: Equatable {
    /// Has an `id`: the server must answer it.
    case request(id: JSONValue, method: String, params: JSONValue?)
    /// No `id`: no answer.
    case notification(method: String, params: JSONValue?)
    /// A reply to a request the server sent (it sends none), ignored.
    case response
    /// Not a valid message. `id` is the request's id when it could be read, else null.
    case invalid(id: JSONValue, error: RPCError)
}

/// What one line of input held.
enum RPCFrame: Equatable {
    case single(RPCMessage)
    /// A JSON array of messages (JSON-RPC batching; MCP 2025-06-18 dropped it, older clients may still send it).
    case batch([RPCMessage])
}

enum RPC {
    static let version = "2.0"

    /// Decodes one line.
    static func parse(line: String) -> RPCFrame {
        let value: JSONValue
        do { value = try JSONDecoder().decode(JSONValue.self, from: Data(line.utf8)) }
        catch { return .single(.invalid(id: .null, error: .parse("Parse error: the line is not valid JSON"))) }

        if case .array(let items) = value {
            if items.isEmpty { return .single(.invalid(id: .null, error: .invalidRequest("Invalid Request: empty batch"))) }
            return .batch(items.map(message(from:)))
        }
        return .single(message(from: value))
    }

    static func message(from value: JSONValue) -> RPCMessage {
        guard case .object(let o) = value else {
            return .invalid(id: .null, error: .invalidRequest("Invalid Request: a message must be a JSON object"))
        }
        // The id, when it is usable, is echoed in the error so the client can match it.
        var id: JSONValue = .null
        var hasID = false
        if let raw = o["id"] {
            switch raw {
            case .string, .number: id = raw; hasID = true
            case .null: return .invalid(id: .null, error: .invalidRequest("Invalid Request: id must not be null"))
            default: return .invalid(id: .null, error: .invalidRequest("Invalid Request: id must be a string or a number"))
            }
        }
        guard case .string(let v)? = o["jsonrpc"], v == version else {
            return .invalid(id: id, error: .invalidRequest("Invalid Request: \"jsonrpc\" must be \"2.0\""))
        }
        if let m = o["method"] {
            guard case .string(let method) = m, !method.isEmpty else {
                return .invalid(id: id, error: .invalidRequest("Invalid Request: method must be a string"))
            }
            let params = o["params"].flatMap { $0 == .null ? nil : $0 }
            if let params {
                switch params {
                case .object, .array: break
                default: return .invalid(id: id, error: .invalidRequest("Invalid Request: params must be an object or an array"))
                }
            }
            return hasID ? .request(id: id, method: method, params: params) : .notification(method: method, params: params)
        }
        if hasID, o["result"] != nil || o["error"] != nil { return .response }
        return .invalid(id: id, error: .invalidRequest("Invalid Request: no method"))
    }

    static func result(id: JSONValue, _ result: JSONValue) -> JSONValue {
        .object(["jsonrpc": .string(version), "id": id, "result": result])
    }

    static func failure(id: JSONValue, _ error: RPCError) -> JSONValue {
        var e: [String: JSONValue] = ["code": .number(Double(error.code)), "message": .string(error.message)]
        if let data = error.data { e["data"] = data }
        return .object(["jsonrpc": .string(version), "id": id, "error": .object(e)])
    }

    /// The compact JSON text of a message: it never contains a raw newline (the encoder escapes them in strings),
    /// so it is one frame.
    static func encode(_ value: JSONValue) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(value), let text = String(data: data, encoding: .utf8) else {
            return "{\"jsonrpc\":\"2.0\",\"id\":null,\"error\":{\"code\":-32603,\"message\":\"could not encode response\"}}"
        }
        return text
    }
}
