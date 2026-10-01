import Foundation
#if canImport(HeraldClient)
import HeraldClient
#endif

/// Target languages of the composer's "Copy as..." menu.
public enum CodeExportFormat: String, CaseIterable, Identifiable, Sendable {
    case curl, swift, python, node, cli

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .curl: return "curl"
        case .swift: return "Swift (HeraldClient)"
        case .python: return "Python (herald.py)"
        case .node: return "Node (herald.js)"
        case .cli: return "herald CLI"
        }
    }
}

/// Turns a notification into code that reproduces it, so a payload designed in the composer can be
/// pasted straight into a script, an app or a shell. Pure functions over `HeraldNotification` (no
/// AppKit, no I/O) so the quoting and escaping rules can be unit tested.
///
/// Why everything goes through the *wire object*: the exporters must emit exactly what the HTTP API
/// would receive. Encoding the notification once with the shared `HeraldJSON` encoder and walking the
/// resulting JSON keeps the exporters correct for fields added to `HeraldNotification` later (layout,
/// accent colour, ...) without each language needing a new case.
public enum CodeExport {

    public static func export(_ n: HeraldNotification, as format: CodeExportFormat) -> String {
        switch format {
        case .curl: return curl(n)
        case .swift: return swift(n)
        case .python: return python(n)
        case .node: return node(n)
        case .cli: return cli(n)
        }
    }

    // MARK: curl

    /// `curl` call that reads the port and token from Herald's Application Support files, exactly as
    /// the bundled clients do, so the snippet keeps working when the port is overridden in Settings.
    public static func curl(_ n: HeraldNotification) -> String {
        let json = Literal.render(.object(wireObject(n)), .json, level: 0, expanded: true, ordered: true)
        return """
        H="$HOME/Library/Application Support/Herald"
        curl -sS -X POST "http://127.0.0.1:$(cat "$H/port")/v1/notify" \\
          -H "Authorization: Bearer $(cat "$H/token")" \\
          -H 'Content-Type: application/json' \\
          -d \(shellQuote(json))
        """
    }

    // MARK: Swift

    /// Swift source using the `HeraldClient` package. Fields the initializer knows are passed as
    /// arguments; newer fields (template, layout, accent colour, ...) are assigned as properties so the
    /// snippet compiles regardless of which of them the initializer exposes.
    public static func swift(_ n: HeraldNotification) -> String {
        let wire = wireObject(n)
        var args: [String] = ["app: \(Literal.swiftString(n.app))"]
        if let v = n.id { args.append("id: \(Literal.swiftString(v))") }
        args.append("title: \(Literal.swiftString(n.title))")
        if let v = n.subtitle { args.append("subtitle: \(Literal.swiftString(v))") }
        if let v = n.body { args.append("body: \(Literal.swiftString(v))") }
        if let v = n.image { args.append("image: \(Literal.swiftString(v))") }
        if let v = n.url { args.append("url: \(Literal.swiftString(v))") }
        if let v = n.sound { args.append("sound: \(Literal.swiftString(v))") }
        if let v = n.persistent { args.append("persistent: \(v)") }
        if let v = n.timeout { args.append("timeout: \(Literal.number(v))") }
        if let v = n.priority { args.append("priority: \(Literal.swiftString(v))") }
        if let bs = n.buttons, !bs.isEmpty {
            let rows = bs.map { "        " + swiftButton($0) }.joined(separator: ",\n")
            args.append("buttons: [\n\(rows)\n    ]")
        }
        if let v = n.snooze { args.append("snooze: \(v)") }
        if let r = n.reminder { args.append("reminder: \(swiftReminder(r))") }
        if let m = n.metadata { args.append("metadata: \(Literal.render(m, .swift, level: 1))") }

        let extras = orderedKeys(wire).filter { !swiftInitKeys.contains($0) }
        var out = "import HeraldClient\n\n"
        out += "\(extras.isEmpty ? "let" : "var") notification = HeraldNotification(\n"
        out += args.map { "    " + $0 }.joined(separator: ",\n")
        out += "\n)\n"
        for k in extras { out += "notification.\(k) = \(swiftPropertyValue(key: k, wire[k] ?? .null))\n" }
        out += """

        do {
            let id = try await HeraldClient.shared.notify(notification)
            print("Sent notification \\(id)")
        } catch {
            print("Herald: \\(error)")
        }
        """
        return out
    }

    private static let swiftInitKeys: Set<String> = ["app", "id", "title", "subtitle", "body", "image", "url", "sound",
        "persistent", "timeout", "priority", "buttons", "snooze", "reminder", "metadata"]

    private static func swiftButton(_ b: HeraldButton) -> String {
        var a = ["label: \(Literal.swiftString(b.label))"]
        if let v = b.style { a.append("style: \(Literal.swiftString(v))") }
        if let v = b.url { a.append("url: \(Literal.swiftString(v))") }
        if let v = b.command { a.append("command: \(Literal.swiftString(v))") }
        if let c = b.callback {
            var ca: [String] = []
            if let u = c.url { ca.append("url: \(Literal.swiftString(u))") }
            if let p = c.payload { ca.append("payload: \(Literal.render(p, .swift, level: 2))") }
            a.append("callback: HeraldCallback(\(ca.joined(separator: ", ")))")
        }
        return "HeraldButton(\(a.joined(separator: ", ")))"
    }

    private static func swiftReminder(_ r: HeraldReminder) -> String {
        var a: [String] = []
        if let t = r.title { a.append("title: \(Literal.swiftString(t))") }
        if let d = r.due { a.append("due: \(Literal.swiftString(d))") }
        return "HeraldReminder(\(a.joined(separator: ", ")))"
    }

    /// Right-hand side for `notification.<key> = ...`. The layout enum is the one non-literal case.
    private static func swiftPropertyValue(key: String, _ v: JSONValue) -> String {
        if key == "layout", case .string(let s) = v { return ".\(s)" }
        switch v {
        case .string(let s): return Literal.swiftString(s)
        case .bool(let b): return b ? "true" : "false"
        case .number(let d): return Literal.number(d)
        case .null: return "nil"
        default: return Literal.render(v, .swift, level: 0)
        }
    }

    // MARK: Python

    /// Call of `Herald().notify(...)` from `clients/python/herald.py` (stdlib only).
    public static func python(_ n: HeraldNotification) -> String {
        let wire = wireObject(n)
        var lines = ["from herald import Herald", "", "Herald().notify("]
        lines.append("    \(Literal.string(n.app, .python)),")
        lines.append("    \(Literal.string(n.title, .python)),")
        let rest = orderedKeys(wire).filter { $0 != "app" && $0 != "title" }
        for (i, k) in rest.enumerated() {
            let v = Literal.render(wire[k] ?? .null, .python, level: 1)
            lines.append("    \(k)=\(v)\(i == rest.count - 1 ? "" : ",")")
        }
        lines.append(")")
        return lines.joined(separator: "\n")
    }

    // MARK: Node

    /// Call of `new Herald().notify(...)` from `clients/node/herald.js` (CommonJS, Node 18+). CommonJS has no
    /// top-level `await`, so the call sits in an async function that runs at once.
    public static func node(_ n: HeraldNotification) -> String {
        let wire = wireObject(n)
        var fields = wire
        fields["app"] = nil; fields["title"] = nil
        var call = "await new Herald().notify(\(Literal.string(n.app, .javascript)), \(Literal.string(n.title, .javascript))"
        if !fields.isEmpty {
            call += ", \(Literal.render(.object(fields), .javascript, level: 0, expanded: true, ordered: true))"
        }
        call += ");"
        let body = call.components(separatedBy: "\n").map { $0.isEmpty ? $0 : "  " + $0 }.joined(separator: "\n")
        return "const { Herald } = require('./herald.js');\n\n(async () => {\n\(body)\n})();"
    }

    // MARK: CLI

    /// `herald notify ...` command. Everything the CLI has a flag for is passed as a flag; whatever it
    /// cannot express (layout fields, styled buttons, callback URLs, ...) rides along as a small
    /// `--json -` heredoc, which the CLI merges beneath the flags.
    public static func cli(_ n: HeraldNotification) -> String {
        var rest = wireObject(n)
        var flags: [String] = []
        func take(_ key: String) { rest[key] = nil }

        flags.append("--app \(shellQuote(n.app))"); take("app")
        if let v = n.id { flags.append("--id \(shellQuote(v))"); take("id") }
        // An empty title means "the template supplies it": there is nothing to pass, and the CLI would
        // read `--title ''` as a missing title.
        if !n.title.isEmpty { flags.append("--title \(shellQuote(n.title))") }
        take("title")
        if let v = n.subtitle { flags.append("--subtitle \(shellQuote(v))"); take("subtitle") }
        if let v = n.body { flags.append("--body \(shellQuote(v))"); take("body") }
        if let v = n.image { flags.append("--image \(shellQuote(v))"); take("image") }
        if let v = n.url { flags.append("--url \(shellQuote(v))"); take("url") }
        if let v = n.sound { flags.append("--sound \(shellQuote(v))"); take("sound") }
        if let v = n.timeout { flags.append("--timeout \(Literal.number(v))"); take("timeout") }
        if let v = n.persistent { flags.append(v ? "--persistent" : "--no-persistent"); take("persistent") }
        if let v = n.snooze { flags.append(v ? "--snooze" : "--no-snooze"); take("snooze") }
        if let v = n.priority, ["low", "normal", "high"].contains(v) { flags.append("--priority \(v)"); take("priority") }
        if let bs = n.buttons, !bs.isEmpty {
            let specs = bs.map(cliButtonSpec)
            if specs.allSatisfy({ $0 != nil }) {
                for s in specs { flags.append("--button \(shellQuote(s!))") }
                take("buttons")
            }
        }
        if let r = n.reminder, let spec = cliReminderSpec(r) { flags.append("--reminder \(shellQuote(spec))"); take("reminder") }
        if let m = n.metadata {
            flags.append("--metadata \(shellQuote(Literal.render(m, .json, level: 0, compact: true)))")
            take("metadata")
        }

        var out = "herald notify"
        let heredoc = !rest.isEmpty
        for f in flags {
            out += " \\\n  \(f)"
        }
        if heredoc {
            out += " \\\n  --json - <<'JSON'\n"
            out += Literal.render(.object(rest), .json, level: 0, expanded: true, ordered: true)
            out += "\nJSON"
        }
        return out
    }

    /// `Label=target` for the CLI's `--button`; nil when the CLI syntax cannot carry the button
    /// (it has no way to set a style or a callback URL).
    private static func cliButtonSpec(_ b: HeraldButton) -> String? {
        if let s = b.style, s != "default" { return nil }
        if b.label.contains("=") || b.label != b.label.trimmingCharacters(in: .whitespaces) { return nil }
        if let cb = b.callback {
            if cb.url != nil || b.url != nil || b.command != nil { return nil }
            guard let p = cb.payload else { return "\(b.label)=cb:" }
            return "\(b.label)=cb:\(Literal.render(p, .json, level: 0, compact: true))"
        }
        if let c = b.command, b.url == nil, !c.isEmpty { return "\(b.label)=cmd:\(c)" }
        if let u = b.url, b.command == nil, !u.isEmpty, !u.hasPrefix("cmd:"), !u.hasPrefix("cb:") { return "\(b.label)=\(u)" }
        return nil
    }

    private static func cliReminderSpec(_ r: HeraldReminder) -> String? {
        guard let t = r.title, !t.isEmpty else { return nil }
        guard let d = r.due, !d.isEmpty else { return t.contains("|") ? nil : t }
        return "\(t)|\(d)"
    }

    // MARK: Shared helpers

    /// POSIX single-quote quoting: safe words stay bare, everything else is wrapped in `'...'` with
    /// embedded quotes written as `'\''`. Newlines survive inside single quotes.
    public static func shellQuote(_ s: String) -> String {
        if s.isEmpty { return "''" }
        let safe = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_@%+=:,./-")
        if s.allSatisfy({ safe.contains($0) }) { return s }
        return "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// The notification as the JSON object that would travel over HTTP (nil fields omitted).
    public static func wireObject(_ n: HeraldNotification) -> [String: JSONValue] {
        if let data = try? HeraldJSON.encoder().encode(n),
           let v = try? JSONDecoder().decode(JSONValue.self, from: data), case .object(let o) = v { return o }
        return ["app": .string(n.app), "title": .string(n.title)]
    }

    /// Reading order of the generated snippets: identity, content, actions, behaviour, look, data.
    static let fieldOrder = ["app", "id", "template", "title", "subtitle", "body", "image", "url", "buttons",
                             "sound", "persistent", "timeout", "snooze", "reminder", "priority",
                             "layout", "accentColor", "showSubtitle", "showBody", "showTimestamp", "maxBodyLines",
                             "metadata"]

    static func orderedKeys(_ o: [String: JSONValue]) -> [String] {
        let known = fieldOrder.filter { o[$0] != nil }
        let other = o.keys.filter { !fieldOrder.contains($0) }.sorted()
        return known + other
    }

    /// Keys of a nested object (a button, a reminder, metadata): the well-known ones first, in the order
    /// a person would write them, then everything else alphabetically for a stable output.
    static func nestedKeys(_ o: [String: JSONValue]) -> [String] {
        let first = ["label", "title", "url", "command", "callback", "style", "due", "payload"]
        return first.filter { o[$0] != nil } + o.keys.filter { !first.contains($0) }.sorted()
    }

    // MARK: Literal rendering

    enum Dialect { case json, python, javascript, swift }

    /// Renders `JSONValue`s as source text in a target language. Short containers stay on one line,
    /// long ones break with a four-space (Swift/Python) or two-space (JSON/JS) indent.
    enum Literal {
        static let inlineLimit = 64

        static func indentUnit(_ d: Dialect) -> String { (d == .json || d == .javascript) ? "  " : "    " }

        /// `ordered` puts a payload object's keys in reading order (see `fieldOrder`) instead of
        /// alphabetical; it applies to that object only, never to nested metadata or payloads.
        static func render(_ v: JSONValue, _ d: Dialect, level: Int, expanded: Bool = false,
                           compact: Bool = false, ordered: Bool = false) -> String {
            switch v {
            case .null: return d == .python ? "None" : (d == .swift ? ".null" : "null")
            case .bool(let b):
                if d == .python { return b ? "True" : "False" }
                return d == .swift ? ".bool(\(b))" : (b ? "true" : "false")
            case .number(let n): return d == .swift ? ".number(\(number(n)))" : number(n)
            case .string(let s): return d == .swift ? ".string(\(swiftString(s)))" : string(s, d)
            case .array(let items):
                let parts = items.map { render($0, d, level: level + 1, compact: compact) }
                let open = d == .swift ? ".array([" : "[", close = d == .swift ? "])" : "]"
                return container(parts, open: open, close: close, d, level: level, expanded: expanded, compact: compact)
            case .object(let o):
                let kv = (d == .json && compact) ? ":" : ": "
                let parts = (ordered ? orderedKeys(o) : nestedKeys(o)).map { k -> String in
                    let key = d == .swift ? swiftString(k) : string(k, d)
                    return "\(key)\(kv)\(render(o[k]!, d, level: level + 1, compact: compact))"
                }
                if d == .swift && parts.isEmpty { return ".object([:])" }
                let open = d == .swift ? ".object([" : "{", close = d == .swift ? "])" : "}"
                return container(parts, open: open, close: close, d, level: level, expanded: expanded, compact: compact)
            }
        }

        private static func container(_ parts: [String], open: String, close: String, _ d: Dialect, level: Int,
                                      expanded: Bool, compact: Bool) -> String {
            if parts.isEmpty { return open + close }
            let sep = (d == .json && compact) ? "," : ", "
            let inline = open + parts.joined(separator: sep) + close
            if compact || (!expanded && inline.count <= inlineLimit && !inline.contains("\n")) { return inline }
            let unit = indentUnit(d)
            let pad = String(repeating: unit, count: level + 1)
            let end = String(repeating: unit, count: level)
            return open + "\n" + parts.map { pad + $0 }.joined(separator: ",\n") + "\n" + end + close
        }

        /// JSON string literal. Valid as-is in JSON, JavaScript and Python source.
        static func string(_ s: String, _ d: Dialect) -> String {
            if d == .swift { return swiftString(s) }
            var out = "\""
            for u in s.unicodeScalars {
                switch u {
                case "\"": out += "\\\""
                case "\\": out += "\\\\"
                case "\n": out += "\\n"
                case "\r": out += "\\r"
                case "\t": out += "\\t"
                case "\u{8}": out += "\\b"
                case "\u{C}": out += "\\f"
                default:
                    if u.value < 0x20 || u.value == 0x2028 || u.value == 0x2029 {
                        out += String(format: "\\u%04x", u.value)
                    } else { out.unicodeScalars.append(u) }
                }
            }
            return out + "\""
        }

        static func swiftString(_ s: String) -> String {
            var out = "\""
            for u in s.unicodeScalars {
                switch u {
                case "\"": out += "\\\""
                case "\\": out += "\\\\"
                case "\n": out += "\\n"
                case "\r": out += "\\r"
                case "\t": out += "\\t"
                case "\0": out += "\\0"
                default:
                    if u.value < 0x20 || u.value == 0x7F { out += "\\u{\(String(u.value, radix: 16, uppercase: true))}" }
                    else { out.unicodeScalars.append(u) }
                }
            }
            return out + "\""
        }

        static func number(_ d: Double) -> String {
            if d == d.rounded(), abs(d) < 1e15 { return String(Int64(d)) }
            return "\(d)"
        }
    }
}
