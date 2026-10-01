import Foundation

/// Pure argument parsing for the `herald` command line tool. No I/O except through
/// the injected `readInput` closure (used for `--json <file|->`).

public struct CLIParseError: Error, Equatable, CustomStringConvertible {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var description: String { message }
}

/// A fully described HTTP request for the Herald service.
public struct CLIRequest {
    public var method: String
    public var path: String
    public var query: [(name: String, value: String)]
    public var body: [String: Any]?
    public var needsAuth: Bool

    public init(method: String, path: String, query: [(name: String, value: String)] = [],
                body: [String: Any]? = nil, needsAuth: Bool = true) {
        self.method = method; self.path = path; self.query = query
        self.body = body; self.needsAuth = needsAuth
    }
}

public enum CLIAction {
    case help(String?)       // optional subcommand
    case version
    case request(CLIRequest)
}

public struct CLIInvocation {
    public var action: CLIAction
    public var port: Int?
    public var token: String?
}

public enum CLIArguments {
    public static let usage = """
    herald - send notifications to Herald.app

    USAGE
      herald <command> [options]

    COMMANDS
      notify        Send a notification (requires --app and --title, or --template, or --json)
      register      Register or update an app
      compose       Open the Composer window in Herald.app
      snooze        Snooze a banner (--app, --id, --minutes N)
      unsnooze      Bring a snoozed banner back now (--app, --id)
      dismiss       Dismiss one banner (--app, --id)
      dismiss-all   Dismiss all banners of an app (--app)
      history       Show an app's history (--app [--limit N] [--clear])
      apps          List registered apps
      health        Check that Herald is running

    GLOBAL OPTIONS
      --port N      Service port (default: Application Support/Herald/port, else 48617)
      --token T     Bearer token (default: Application Support/Herald/token)
      --json FILE   Raw JSON payload from FILE, or - for stdin (notify, register);
                    other flags are merged on top of it
      -h, --help    Show help (also: herald help <command>)
      --version     Show version

    notify OPTIONS
      --app ID  --title T  --subtitle T  --body T  --image PATH|URL|data:  --url URL
      --id ID               Replace an existing banner with this id
      --sound NAME|PATH|none
      --timeout SECONDS     0 = until dismissed
      --persistent | --no-persistent
      --snooze              Show the snooze menu
      --priority low|normal|high
      --button "Label=https://..."        Open URL (repeatable)
      --button "Label=cmd:shell command"  Run command (app needs allowCommands)
      --button "Label=cb:{\\"k\\":1}"       POST JSON payload to the app's callback URL
      --reminder "Title|2026-10-02T09:00" Add-to-Reminders action (title|ISO8601)
      --metadata JSON       Arbitrary JSON object stored with the notification
      --template NAME       Use a saved template (--title may then be omitted); {placeholders}
                            in the template are filled from --metadata
      --layout L            imageLeft | imageRight | hero | compact
      --accent #RRGGBB      Accent color for title, buttons and links
      --no-subtitle | --no-body | --no-time    Hide that part of the banner
      --max-body-lines N    Body line limit

    snooze OPTIONS
      --app ID  --id ID  --minutes N      (N may be fractional, 0 < N <= 43200)

    register OPTIONS
      --app ID  --name NAME  --icon PATH|data:  --bundle-id ID  --callback-url URL
      --allow-commands  --sound NAME  --persistent|--no-persistent  --timeout S  --corner C

    EXIT CODES
      0 ok   1 error (usage, HTTP error)   2 Herald is not running
    """

    public static let notRunningMessage = "Herald is not running. Launch Herald.app first."
    public static let defaultPort = 48617

    static let valueFlagsNotify: Set<String> = ["--app", "--id", "--title", "--subtitle", "--body", "--image", "--url",
        "--sound", "--timeout", "--priority", "--button", "--reminder", "--icon", "--callback-url", "--metadata", "--json",
        "--template", "--layout", "--accent", "--max-body-lines"]
    static let boolFlagsNotify: Set<String> = ["--persistent", "--no-persistent", "--snooze", "--no-snooze",
        "--no-subtitle", "--no-body", "--no-time"]

    public static func parse(_ args: [String],
                             readInput: (String) throws -> Data = { _ in Data() }) throws -> CLIInvocation {
        var rest = args
        var port: Int?
        var token: String?
        var wantHelp = false
        var wantVersion = false

        // Extract global options anywhere on the line; keep everything else in order.
        var remaining: [String] = []
        var i = 0
        while i < rest.count {
            let a = rest[i]
            switch a {
            case "-h", "--help": wantHelp = true
            case "--version": wantVersion = true
            case "--port":
                guard i + 1 < rest.count, let p = Int(rest[i + 1]), (1...65535).contains(p) else {
                    throw CLIParseError("--port needs a port number (1-65535)")
                }
                port = p; i += 1
            case "--token":
                guard i + 1 < rest.count else { throw CLIParseError("--token needs a value") }
                token = rest[i + 1]; i += 1
            default:
                if a.hasPrefix("--port=") {
                    guard let p = Int(a.dropFirst(7)), (1...65535).contains(p) else { throw CLIParseError("--port needs a port number (1-65535)") }
                    port = p
                } else if a.hasPrefix("--token=") {
                    token = String(a.dropFirst(8))
                } else { remaining.append(a) }
            }
            i += 1
        }
        rest = remaining

        func inv(_ action: CLIAction) -> CLIInvocation { CLIInvocation(action: action, port: port, token: token) }

        if wantVersion { return inv(.version) }
        guard var command = rest.first else { return inv(.help(nil)) }
        rest.removeFirst()
        if command == "help" { return inv(.help(rest.first)) }
        if wantHelp { return inv(.help(command)) }
        if command == "dismissAll" { command = "dismiss-all" }

        switch command {
        case "notify":
            return inv(.request(try parseNotify(rest, readInput: readInput)))
        case "register":
            return inv(.request(try parseRegister(rest, readInput: readInput)))
        case "compose":
            let o = try Options(rest, values: [], bools: [])
            try o.finish()
            return inv(.request(CLIRequest(method: "POST", path: "/v1/compose", body: [:])))
        case "snooze":
            let o = try Options(rest, values: ["--app", "--id", "--minutes"], bools: [])
            let app = try o.require("--app"); let id = try o.require("--id")
            let m = try o.require("--minutes")
            guard let minutes = Double(m), minutes > 0, minutes <= 43200 else {
                throw CLIParseError("--minutes needs a number greater than 0 and at most 43200")
            }
            try o.finish()
            return inv(.request(CLIRequest(method: "POST", path: "/v1/snooze", body: ["app": app, "id": id, "minutes": minutes])))
        case "unsnooze":
            let o = try Options(rest, values: ["--app", "--id"], bools: [])
            let app = try o.require("--app"); let id = try o.require("--id")
            try o.finish()
            return inv(.request(CLIRequest(method: "POST", path: "/v1/unsnooze", body: ["app": app, "id": id])))
        case "dismiss":
            let o = try Options(rest, values: ["--app", "--id"], bools: [])
            let app = try o.require("--app"); let id = try o.require("--id")
            try o.finish()
            return inv(.request(CLIRequest(method: "POST", path: "/v1/dismiss", body: ["app": app, "id": id])))
        case "dismiss-all":
            let o = try Options(rest, values: ["--app"], bools: [])
            let app = try o.require("--app")
            try o.finish()
            return inv(.request(CLIRequest(method: "POST", path: "/v1/dismissAll", body: ["app": app])))
        case "history":
            let o = try Options(rest, values: ["--app", "--limit"], bools: ["--clear"])
            let app = try o.require("--app")
            if o.flag("--clear") {
                try o.finish()
                return inv(.request(CLIRequest(method: "DELETE", path: "/v1/history", query: [("app", app)])))
            }
            var q = [("app", app)]
            if let l = o.value("--limit") {
                guard let n = Int(l), n > 0 else { throw CLIParseError("--limit needs a positive integer") }
                q.append(("limit", String(n)))
            }
            try o.finish()
            return inv(.request(CLIRequest(method: "GET", path: "/v1/history", query: q)))
        case "apps":
            let o = try Options(rest, values: [], bools: [])
            try o.finish()
            return inv(.request(CLIRequest(method: "GET", path: "/v1/apps")))
        case "health":
            let o = try Options(rest, values: [], bools: [])
            try o.finish()
            return inv(.request(CLIRequest(method: "GET", path: "/v1/health", needsAuth: false)))
        default:
            throw CLIParseError("unknown command '\(command)'")
        }
    }

    // MARK: notify / register

    static func parseNotify(_ rest: [String], readInput: (String) throws -> Data) throws -> CLIRequest {
        let o = try Options(rest, values: valueFlagsNotify, bools: boolFlagsNotify)
        var body = try loadJSON(o.value("--json"), readInput: readInput)
        if let v = o.value("--app") { body["app"] = v }
        if let v = o.value("--id") { body["id"] = v }
        if let v = o.value("--title") { body["title"] = v }
        if let v = o.value("--subtitle") { body["subtitle"] = v }
        if let v = o.value("--body") { body["body"] = v }
        if let v = o.value("--image") { body["image"] = v }
        if let v = o.value("--url") { body["url"] = v }
        if let v = o.value("--sound") { body["sound"] = v }
        if let v = o.value("--priority") {
            guard ["low", "normal", "high"].contains(v) else { throw CLIParseError("--priority must be low, normal or high") }
            body["priority"] = v
        }
        if let v = o.value("--timeout") { body["timeout"] = try number(v, "--timeout") }
        if o.flag("--persistent") { body["persistent"] = true }
        if o.flag("--no-persistent") { body["persistent"] = false }
        if o.flag("--snooze") { body["snooze"] = true }
        if o.flag("--no-snooze") { body["snooze"] = false }
        if let v = o.value("--template") { body["template"] = v }
        if let v = o.value("--layout") {
            guard HeraldLayout.allCases.map(\.rawValue).contains(v) else {
                throw CLIParseError("--layout must be one of \(HeraldLayout.allCases.map(\.rawValue).joined(separator: ", "))")
            }
            body["layout"] = v
        }
        if let v = o.value("--accent") { body["accentColor"] = v }
        if o.flag("--no-subtitle") { body["showSubtitle"] = false }
        if o.flag("--no-body") { body["showBody"] = false }
        if o.flag("--no-time") { body["showTimestamp"] = false }
        if let v = o.value("--max-body-lines") {
            guard let n = Int(v), n > 0 else { throw CLIParseError("--max-body-lines needs a positive integer") }
            body["maxBodyLines"] = n
        }
        if let v = o.value("--metadata") { body["metadata"] = try parseJSONValue(v, "--metadata") }
        if let v = o.value("--reminder") { body["reminder"] = try parseReminder(v) }
        let buttons = try o.values("--button").map(parseButton)
        if !buttons.isEmpty { body["buttons"] = (body["buttons"] as? [Any] ?? []) + buttons }
        try o.finish()
        guard let app = body["app"] as? String, !app.isEmpty else { throw CLIParseError("notify needs --app") }
        // A named template may supply the title, so --title is only required without one.
        let hasTemplate = (body["template"] as? String)?.isEmpty == false
        let title = body["title"] as? String ?? ""
        guard hasTemplate || !title.isEmpty else { throw CLIParseError("notify needs --title (or --template)") }
        _ = app
        return CLIRequest(method: "POST", path: "/v1/notify", body: body)
    }

    static func parseRegister(_ rest: [String], readInput: (String) throws -> Data) throws -> CLIRequest {
        let o = try Options(rest, values: ["--app", "--name", "--icon", "--bundle-id", "--callback-url", "--sound",
                                           "--timeout", "--corner", "--json"],
                            bools: ["--allow-commands", "--no-allow-commands", "--persistent", "--no-persistent"])
        var body = try loadJSON(o.value("--json"), readInput: readInput)
        if let v = o.value("--app") { body["app"] = v }
        if let v = o.value("--name") { body["appName"] = v }
        if let v = o.value("--icon") { body["icon"] = v }
        if let v = o.value("--bundle-id") { body["bundleId"] = v }
        if let v = o.value("--callback-url") { body["callbackURL"] = v }
        if o.flag("--allow-commands") { body["allowCommands"] = true }
        if o.flag("--no-allow-commands") { body["allowCommands"] = false }
        var defaults = body["defaults"] as? [String: Any] ?? [:]
        if let v = o.value("--sound") { defaults["sound"] = v }
        if let v = o.value("--timeout") { defaults["timeout"] = try number(v, "--timeout") }
        if let v = o.value("--corner") {
            guard ["topRight", "topLeft", "bottomRight", "bottomLeft"].contains(v) else {
                throw CLIParseError("--corner must be topRight, topLeft, bottomRight or bottomLeft")
            }
            defaults["corner"] = v
        }
        if o.flag("--persistent") { defaults["persistent"] = true }
        if o.flag("--no-persistent") { defaults["persistent"] = false }
        if !defaults.isEmpty { body["defaults"] = defaults }
        try o.finish()
        guard let app = body["app"] as? String, !app.isEmpty else { throw CLIParseError("register needs --app") }
        _ = app
        return CLIRequest(method: "POST", path: "/v1/register", body: body)
    }

    // MARK: helpers (internal for tests)

    /// "Label=https://x" | "Label=cmd:shell" | "Label=cb:{json}" (cb: alone = empty payload).
    public static func parseButton(_ spec: String) throws -> [String: Any] {
        guard let eq = spec.firstIndex(of: "=") else {
            throw CLIParseError("--button needs \"Label=target\", got '\(spec)'")
        }
        let label = String(spec[..<eq]).trimmingCharacters(in: .whitespaces)
        let target = String(spec[spec.index(after: eq)...])
        guard !label.isEmpty, !target.isEmpty else { throw CLIParseError("--button needs a label and a target, got '\(spec)'") }
        if target.hasPrefix("cmd:") {
            let c = String(target.dropFirst(4))
            guard !c.isEmpty else { throw CLIParseError("--button '\(label)' has an empty cmd:") }
            return ["label": label, "command": c]
        }
        if target.hasPrefix("cb:") {
            let p = String(target.dropFirst(3)).trimmingCharacters(in: .whitespaces)
            var cb: [String: Any] = [:]
            if !p.isEmpty { cb["payload"] = try parseJSONValue(p, "--button cb: payload") }
            return ["label": label, "callback": cb]
        }
        return ["label": label, "url": target]
    }

    /// "Title|ISO8601" (split on the last '|'); a bare string is just a title.
    public static func parseReminder(_ spec: String) throws -> [String: Any] {
        if let bar = spec.lastIndex(of: "|") {
            let title = String(spec[..<bar]).trimmingCharacters(in: .whitespaces)
            let due = String(spec[spec.index(after: bar)...]).trimmingCharacters(in: .whitespaces)
            guard !title.isEmpty else { throw CLIParseError("--reminder needs a title before '|'") }
            guard !due.isEmpty else { return ["title": title] }
            return ["title": title, "due": due]
        }
        guard !spec.isEmpty else { throw CLIParseError("--reminder needs \"Title|ISO8601\"") }
        return ["title": spec]
    }

    static func number(_ s: String, _ flag: String) throws -> Any {
        if let i = Int(s) { return i }
        if let d = Double(s) { return d }
        throw CLIParseError("\(flag) needs a number, got '\(s)'")
    }

    static func parseJSONValue(_ s: String, _ what: String) throws -> Any {
        do { return try JSONSerialization.jsonObject(with: Data(s.utf8), options: [.fragmentsAllowed]) }
        catch { throw CLIParseError("\(what) is not valid JSON: \(s)") }
    }

    static func loadJSON(_ source: String?, readInput: (String) throws -> Data) throws -> [String: Any] {
        guard let source else { return [:] }
        let data: Data
        do { data = try readInput(source) } catch { throw CLIParseError("cannot read --json \(source): \(error.localizedDescription)") }
        guard let obj = try? JSONSerialization.jsonObject(with: data), let dict = obj as? [String: Any] else {
            throw CLIParseError("--json \(source) must contain a JSON object")
        }
        return dict
    }

    /// Flag collector supporting `--flag value`, `--flag=value`, repeatable value flags.
    struct Options {
        private var vals: [String: [String]] = [:]
        private var bools: Set<String> = []

        init(_ args: [String], values: Set<String>, bools allowedBools: Set<String>) throws {
            var i = 0
            while i < args.count {
                var a = args[i]
                var inline: String?
                if a.hasPrefix("--"), let eq = a.firstIndex(of: "=") {
                    inline = String(a[a.index(after: eq)...]); a = String(a[..<eq])
                }
                if values.contains(a) {
                    if let inline { vals[a, default: []].append(inline) }
                    else {
                        guard i + 1 < args.count else { throw CLIParseError("\(a) needs a value") }
                        // "-" (stdin) is a legal value; other dash-prefixed flags are not.
                        let next = args[i + 1]
                        if next.hasPrefix("--") && values.union(allowedBools).contains(next) {
                            throw CLIParseError("\(a) needs a value")
                        }
                        vals[a, default: []].append(next); i += 1
                    }
                } else if allowedBools.contains(a) {
                    guard inline == nil else { throw CLIParseError("\(a) does not take a value") }
                    bools.insert(a)
                } else {
                    throw CLIParseError(a.hasPrefix("-") ? "unknown option '\(a)'" : "unexpected argument '\(a)'")
                }
                i += 1
            }
        }
        func value(_ f: String) -> String? { vals[f]?.last }
        func values(_ f: String) -> [String] { vals[f] ?? [] }
        func flag(_ f: String) -> Bool { bools.contains(f) }
        func require(_ f: String) throws -> String {
            guard let v = value(f), !v.isEmpty else { throw CLIParseError("missing required \(f)") }
            return v
        }
        func finish() throws {}
    }
}
