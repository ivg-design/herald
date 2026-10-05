import Foundation
import HeraldClient

// MARK: - JSONValue conveniences

extension JSONValue {
    var objectValue: [String: JSONValue]? { if case .object(let o) = self { return o } else { return nil } }
    var arrayValue: [JSONValue]? { if case .array(let a) = self { return a } else { return nil } }
    var stringValue: String? { if case .string(let s) = self { return s } else { return nil } }
    var boolValue: Bool? { if case .bool(let b) = self { return b } else { return nil } }
    var numberValue: Double? { if case .number(let n) = self { return n } else { return nil } }
    var isNull: Bool { if case .null = self { return true } else { return false } }

    subscript(key: String) -> JSONValue? { objectValue?[key] }

    /// The JSON form of any Encodable (a template, a manifest, a history item).
    init(encoding value: some Encodable) throws {
        let data = try HeraldJSON.encoder().encode(value)
        self = try JSONDecoder().decode(JSONValue.self, from: data)
    }

    func decoded<T: Decodable>(_ type: T.Type) throws -> T {
        let data = try JSONEncoder().encode(self)
        return try HeraldJSON.decoder().decode(T.self, from: data)
    }

    /// JSON text with sorted keys. Pretty by default: two-space indentation, `"key": value`, empty collections as
    /// `[]` / `{}`, and anything that fits on one line (<= 72 characters compact) kept on one line, which is
    /// easier to read and cheaper for a model than one token per line.
    func text(pretty: Bool = true) -> String {
        guard pretty else { return compactText() }
        var out = ""
        write(indent: 0, into: &out)
        return out
    }

    private func compactText() -> String {
        let encoder = HeraldJSON.encoder()
        guard let data = try? encoder.encode(self), let s = String(data: data, encoding: .utf8) else { return "null" }
        return s
    }

    private func write(indent: Int, into out: inout String) {
        switch self {
        case .object(let o) where !o.isEmpty:
            let flat = compactText()
            if flat.count <= 72 { out += flat; return }
            let pad = String(repeating: " ", count: indent + 2)
            out += "{\n"
            let keys = o.keys.sorted()
            for (i, key) in keys.enumerated() {
                out += pad + JSONValue.string(key).compactText() + ": "
                o[key]!.write(indent: indent + 2, into: &out)
                out += i < keys.count - 1 ? ",\n" : "\n"
            }
            out += String(repeating: " ", count: indent) + "}"
        case .array(let a) where !a.isEmpty:
            let flat = compactText()
            if flat.count <= 72 { out += flat; return }
            let pad = String(repeating: " ", count: indent + 2)
            out += "[\n"
            for (i, item) in a.enumerated() {
                out += pad
                item.write(indent: indent + 2, into: &out)
                out += i < a.count - 1 ? ",\n" : "\n"
            }
            out += String(repeating: " ", count: indent) + "]"
        case .object: out += "{}"
        case .array: out += "[]"
        default: out += compactText()
        }
    }

    /// The same value with every very long string (a base64 `data:` image, a pasted document) replaced by a
    /// short marker, so a manifest with an embedded icon does not cost an agent thousands of tokens.
    func abbreviated(maxString: Int = 1200) -> JSONValue {
        switch self {
        case .string(let s) where s.count > maxString:
            if s.hasPrefix("data:") { return .string("<\(s.prefix(40))... \(s.count) characters omitted>") }
            return .string(String(s.prefix(400)) + "... <\(s.count) characters in all>")
        case .array(let a): return .array(a.map { $0.abbreviated(maxString: maxString) })
        case .object(let o): return .object(o.mapValues { $0.abbreviated(maxString: maxString) })
        default: return self
        }
    }
}

extension JSONValue {
    /// Does `s` look like what `abbreviated()` writes in place of a long string?
    static func isAbbreviationMarker(_ s: String) -> Bool {
        (s.hasPrefix("<data:") && s.hasSuffix(" characters omitted>")) || (s.hasSuffix(" characters in all>") && s.contains("... <"))
    }

    /// Every abbreviation marker anywhere in the value.
    var abbreviationMarkers: [String] {
        switch self {
        case .string(let s): return Self.isAbbreviationMarker(s) ? [s] : []
        case .array(let a): return a.flatMap(\.abbreviationMarkers)
        case .object(let o): return o.values.flatMap(\.abbreviationMarkers)
        default: return []
        }
    }

    /// Marker -> the original strings it stands for, for every long string in the value.
    func abbreviationTable(maxString: Int = 1200) -> [String: [String]] {
        var table: [String: [String]] = [:]
        func walk(_ v: JSONValue) {
            switch v {
            case .string(let s) where s.count > maxString:
                if case .string(let marker) = v.abbreviated(maxString: maxString), !(table[marker]?.contains(s) ?? false) {
                    table[marker, default: []].append(s)
                }
            case .array(let a): a.forEach(walk)
            case .object(let o): o.values.forEach(walk)
            default: break
            }
        }
        walk(self)
        return table
    }

    /// The value with each marker replaced by the stored string it was made from. A marker that matches no
    /// stored string, or more than one, is left alone and reported in `unresolved`.
    func restoringAbbreviated(_ table: [String: [String]], unresolved: inout [String]) -> JSONValue {
        switch self {
        case .string(let s) where Self.isAbbreviationMarker(s):
            if let originals = table[s], originals.count == 1 { return .string(originals[0]) }
            unresolved.append(s)
            return self
        case .array(let a): return .array(a.map { $0.restoringAbbreviated(table, unresolved: &unresolved) })
        case .object(let o): return .object(o.mapValues { $0.restoringAbbreviated(table, unresolved: &unresolved) })
        default: return self
        }
    }

    /// Does any button in `list` (an array of objects) run code: a shell `command`, a `script` or a `shortcut`? Returns their labels.
    static func commandButtonLabels(in list: JSONValue?) -> [String] {
        guard case .array(let items)? = list else { return [] }
        return items.compactMap { item in
            guard case .object(let o) = item, Self.runsCode(o) else { return nil }
            if case .string(let label)? = o["label"] { return label }
            return "(unlabelled)"
        }
    }

    /// Does this action or button object carry a non-empty command, script or shortcut?
    static func runsCode(_ o: [String: JSONValue]) -> Bool {
        ["command", "script", "shortcut"].contains { key in
            guard let c = o[key], !c.isNull else { return false }
            if case .string(let s) = c, s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return false }
            return true
        }
    }

    /// The label of the inline action of a `followUp` object that runs code, if it has one.
    static func followUpCodeLabel(in value: JSONValue?) -> String? {
        guard case .object(let f)? = value, case .object(let a)? = f["action"], runsCode(a) else { return nil }
        if case .string(let label)? = a["label"] { return label }
        return "(unlabelled)"
    }
}

extension HeraldFieldValue {
    var json: JSONValue { ActionResolver.json(self) }
}

// MARK: - Tool arguments and results

/// A tool failed in a way the model should read and react to (it becomes a result with `isError: true`).
struct ToolFailure: Error {
    var message: String
    /// Extra structured detail merged into the failure's JSON (`errors`, `path`, `cellId`...).
    var details: [String: JSONValue]
    init(_ message: String, details: [String: JSONValue] = [:]) { self.message = message; self.details = details }
}

/// The arguments object of a `tools/call`, with typed accessors that fail with a readable message.
struct MCPArgs {
    let values: [String: JSONValue]

    init(_ raw: JSONValue?) throws {
        switch raw {
        case nil, .null?: values = [:]
        case .object(let o)?: values = o
        default: throw ToolFailure("The tool arguments must be a JSON object.")
        }
    }

    func value(_ key: String) -> JSONValue? {
        guard let v = values[key], !v.isNull else { return nil }
        return v
    }

    func string(_ key: String) throws -> String? {
        guard let v = value(key) else { return nil }
        guard case .string(let s) = v else { throw ToolFailure("Argument '\(key)' must be a string.") }
        return s
    }

    /// A non-blank string.
    func requiredString(_ key: String) throws -> String {
        guard let s = try string(key), !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ToolFailure("Missing required argument '\(key)'.")
        }
        return s
    }

    /// Models and some MCP clients hand over numbers and booleans as strings ("5", "true"); both are accepted.
    func bool(_ key: String) throws -> Bool? {
        guard let v = value(key) else { return nil }
        switch v {
        case .bool(let b): return b
        case .string(let s) where ["true", "false"].contains(s.lowercased()): return s.lowercased() == "true"
        default: throw ToolFailure("Argument '\(key)' must be true or false.")
        }
    }

    func number(_ key: String) throws -> Double? {
        guard let v = value(key) else { return nil }
        switch v {
        case .number(let n) where n.isFinite: return n
        case .string(let s):
            if let n = Double(s.trimmingCharacters(in: .whitespaces)), n.isFinite { return n }
        default: break
        }
        throw ToolFailure("Argument '\(key)' must be a number.")
    }

    func int(_ key: String) throws -> Int? {
        guard let n = try number(key) else { return nil }
        guard n == n.rounded(), abs(n) < 1e9 else { throw ToolFailure("Argument '\(key)' must be an integer.") }
        return Int(n)
    }

    /// An object argument. A string holding a JSON object is accepted too: clients that cannot send nested
    /// objects pass them serialized.
    func object(_ key: String) throws -> [String: JSONValue]? {
        guard let v = value(key) else { return nil }
        if case .object(let o) = v { return o }
        if case .string(let s) = v, s.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{"),
           let parsed = try? JSONDecoder().decode(JSONValue.self, from: Data(s.utf8)), case .object(let o) = parsed { return o }
        throw ToolFailure("Argument '\(key)' must be a JSON object.")
    }

    func requiredObject(_ key: String) throws -> [String: JSONValue] {
        guard let o = try object(key) else { throw ToolFailure("Missing required argument '\(key)' (a JSON object).") }
        return o
    }
}

/// What a tool hands back: content blocks and whether it failed.
struct MCPToolResult: Equatable {
    enum Block: Equatable {
        case text(String)
        case image(data: Data, mimeType: String)
    }
    var blocks: [Block]
    var isError: Bool

    init(blocks: [Block], isError: Bool = false) { self.blocks = blocks; self.isError = isError }

    static func text(_ s: String) -> MCPToolResult { .init(blocks: [.text(s)]) }

    static func json(_ v: JSONValue, pretty: Bool = true) -> MCPToolResult { .text(v.text(pretty: pretty)) }

    static func failure(_ failure: ToolFailure) -> MCPToolResult {
        var o: [String: JSONValue] = ["ok": .bool(false), "error": .string(failure.message)]
        for (k, v) in failure.details { o[k] = v }
        return .init(blocks: [.text(JSONValue.object(o).text())], isError: true)
    }

    /// The MCP `CallToolResult`.
    var jsonValue: JSONValue {
        let content: [JSONValue] = blocks.map {
            switch $0 {
            case .text(let t): return .object(["type": .string("text"), "text": .string(t)])
            case .image(let data, let mime):
                return .object(["type": .string("image"), "data": .string(data.base64EncodedString()), "mimeType": .string(mime)])
            }
        }
        return .object(["content": .array(content), "isError": .bool(isError)])
    }

    /// The text of the first text block (for tests and logs).
    var firstText: String? {
        for b in blocks { if case .text(let t) = b { return t } }
        return nil
    }
}

// MARK: - Decoding errors with a path

enum DecodeReport {
    /// "cells[2].component.binding".
    static func path(_ keys: [CodingKey]) -> String {
        var out = ""
        for k in keys {
            if let i = k.intValue { out += "[\(i)]" } else { out += (out.isEmpty ? "" : ".") + k.stringValue }
        }
        return out
    }

    /// A failure for a document that did not decode: what is wrong and where, and (for a template) the id of the
    /// cell the path runs through, so the agent can fix exactly that cell.
    static func failure(_ error: Error, what: String, raw: JSONValue?) -> ToolFailure {
        var keys: [CodingKey] = []
        var reason = "\(error)"
        if let e = error as? DecodingError {
            switch e {
            case .keyNotFound(let k, let c):
                keys = c.codingPath + [k]; reason = "missing field '\(k.stringValue)'"
            case .typeMismatch(_, let c), .valueNotFound(_, let c), .dataCorrupted(let c):
                keys = c.codingPath
                reason = c.debugDescription.isEmpty ? "wrong type" : c.debugDescription
            @unknown default: break
            }
        } else if let localized = (error as? LocalizedError)?.errorDescription {
            reason = localized
        }
        let path = Self.path(keys)
        var details: [String: JSONValue] = [:]
        var message = "Invalid \(what)"
        if !path.isEmpty { message += " at \(path)"; details["path"] = .string(path) }
        if keys.count >= 2, keys[0].stringValue == "cells", let i = keys[1].intValue,
           case .string(let id)? = raw?["cells"]?.arrayValue.flatMap({ $0.indices.contains(i) ? $0[i] : nil })?["id"] {
            message += " (cell '\(id)')"
            details["cellId"] = .string(id)
        }
        return ToolFailure(message + ": " + reason, details: details)
    }
}

// MARK: - Schema builders for tool input schemas

enum Schema {
    static func string(_ description: String, values: [String]? = nil) -> JSONValue {
        var o: [String: JSONValue] = ["type": .string("string"), "description": .string(description)]
        if let values { o["enum"] = .array(values.map { .string($0) }) }
        return .object(o)
    }
    static func integer(_ description: String, min: Int? = nil, max: Int? = nil) -> JSONValue {
        var o: [String: JSONValue] = ["type": .string("integer"), "description": .string(description)]
        if let min { o["minimum"] = .number(Double(min)) }
        if let max { o["maximum"] = .number(Double(max)) }
        return .object(o)
    }
    static func number(_ description: String, min: Double? = nil, max: Double? = nil) -> JSONValue {
        var o: [String: JSONValue] = ["type": .string("number"), "description": .string(description)]
        if let min { o["minimum"] = .number(min) }
        if let max { o["maximum"] = .number(max) }
        return .object(o)
    }
    static func boolean(_ description: String) -> JSONValue {
        .object(["type": .string("boolean"), "description": .string(description)])
    }
    static func object(_ description: String, properties: [String: JSONValue] = [:]) -> JSONValue {
        var o: [String: JSONValue] = ["type": .string("object"), "description": .string(description)]
        if !properties.isEmpty { o["properties"] = .object(properties) }
        return .object(o)
    }
    /// The `inputSchema` of a tool.
    static func input(_ properties: [String: JSONValue] = [:], required: [String] = [], extra: Bool = false) -> JSONValue {
        var o: [String: JSONValue] = ["type": .string("object"), "properties": .object(properties),
                                      "additionalProperties": .bool(extra)]
        if !required.isEmpty { o["required"] = .array(required.map { .string($0) }) }
        return .object(o)
    }
}

// MARK: - Misc

enum PNGInfo {
    /// Width and height from the IHDR chunk, nil when `data` is not a PNG.
    static func size(of data: Data) -> (width: Int, height: Int)? {
        let bytes = [UInt8](data.prefix(24))
        guard bytes.count == 24, bytes[0] == 0x89, bytes[1] == 0x50, bytes[2] == 0x4E, bytes[3] == 0x47 else { return nil }
        func be(_ i: Int) -> Int { Int(bytes[i]) << 24 | Int(bytes[i + 1]) << 16 | Int(bytes[i + 2]) << 8 | Int(bytes[i + 3]) }
        return (be(16), be(20))
    }
}

extension String {
    /// A file-name-safe fragment: letters, digits, '.', '-' and '_' only.
    var fileSlug: String {
        let s = String(map { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "-" || $0 == "_") ? $0 : "-" })
        return s.isEmpty ? "x" : String(s.prefix(60))
    }
}
