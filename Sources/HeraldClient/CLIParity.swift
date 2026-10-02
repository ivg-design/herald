import Foundation

// `herald` commands for the parity routes (docs/reference/parity.md): settings, per-app settings, assets, symbols,
// History search / re-show / delete / export, template list / put / delete / duplicate / rename / default, manifest
// delete, voice, mcp and approvals. Each command is one request; the work is Herald's.

extension CLIArguments {
    /// `true`, `false`, `null`, numbers and JSON strings/arrays/objects keep their type; anything else is a string.
    static func scalar(_ s: String) -> Any {
        if let v = try? JSONSerialization.jsonObject(with: Data(s.utf8), options: [.fragmentsAllowed]) { return v }
        return s
    }

    /// `KEY=VALUE` words into an object.
    static func pairs(_ words: [String], what: String) throws -> [String: Any] {
        guard !words.isEmpty else { throw CLIParseError("\(what) needs KEY=VALUE pairs, for example muteAllSounds=true") }
        var out: [String: Any] = [:]
        for w in words {
            guard let eq = w.firstIndex(of: "="), eq != w.startIndex else { throw CLIParseError("'\(w)' is not KEY=VALUE") }
            out[String(w[..<eq])] = scalar(String(w[w.index(after: eq)...]))
        }
        return out
    }

    static func absolute(_ path: String) -> String {
        let p = (path as NSString).expandingTildeInPath
        return p.hasPrefix("/") ? p : (FileManager.default.currentDirectoryPath as NSString).appendingPathComponent(p)
    }

    /// Splits leading words (no dash) from the flags that follow.
    static func words(_ args: [String]) -> (words: [String], flags: [String]) {
        let n = args.firstIndex { $0.hasPrefix("--") } ?? args.count
        return (Array(args[..<n]), Array(args[n...]))
    }

    static func get(_ path: String, _ q: [(name: String, value: String)] = []) -> CLIAction {
        .request(CLIRequest(method: "GET", path: path, query: q))
    }

    /// nil when `command` is not one of these.
    static func parseParity(_ command: String, _ rest: [String], readInput: (String) throws -> Data) throws -> CLIAction? {
        switch command {
        case "settings":
            guard let sub = rest.first else { return get("/v1/settings") }
            switch sub {
            case "get": guard rest.count == 1 else { throw CLIParseError("settings get takes no arguments") }; return get("/v1/settings")
            case "set": return .request(CLIRequest(method: "PUT", path: "/v1/settings", body: try pairs(Array(rest.dropFirst()), what: "settings set")))
            default: throw CLIParseError("unknown settings command '\(sub)' (use get or set KEY=VALUE ...)")
            }
        case "assets":
            guard let sub = rest.first else { throw CLIParseError("assets needs list, add or rm") }
            let args = Array(rest.dropFirst())
            switch sub {
            case "list":
                let o = try Options(args, values: ["--app"], bools: [])
                return get("/v1/assets", [("app", try o.require("--app"))])
            case "add":
                let o = try Options(args, values: ["--app", "--file", "--name", "--kind"], bools: [])
                var body: [String: Any] = ["app": try o.require("--app"), "path": absolute(try o.require("--file"))]
                if let n = o.value("--name") { body["name"] = n }
                if let k = o.value("--kind") { body["kind"] = k }
                return .request(CLIRequest(method: "POST", path: "/v1/assets", body: body))
            case "rm":
                let o = try Options(args, values: ["--app", "--file"], bools: [])
                return .request(CLIRequest(method: "DELETE", path: "/v1/assets", query: [("app", try o.require("--app")), ("file", try o.require("--file"))]))
            default: throw CLIParseError("unknown assets command '\(sub)' (use list, add or rm)")
            }
        case "symbols":
            let (w, flags) = words(rest)
            let o = try Options(flags, values: ["--category", "--limit", "--offset"], bools: [])
            var q: [(String, String)] = []
            if !w.isEmpty { q.append(("q", w.joined(separator: " "))) }
            for (flag, name) in [("--category", "category"), ("--limit", "limit"), ("--offset", "offset")] {
                if let v = o.value(flag) { q.append((name, v)) }
            }
            return get("/v1/symbols", q)
        case "voice":
            guard let sub = rest.first, sub != "status" else { return get("/v1/voice") }
            let action = ["install": "install", "cancel": "cancel", "use-existing": "useExisting"][sub]
            guard let action, rest.count == 1 else { throw CLIParseError("voice needs status, install, cancel or use-existing") }
            return .request(CLIRequest(method: "POST", path: "/v1/voice/install", body: ["action": action]))
        case "mcp":
            guard let sub = rest.first, sub != "status" else { return get("/v1/mcp") }
            guard sub == "install" else { throw CLIParseError("mcp needs status or install CLIENT") }
            let (w, flags) = words(Array(rest.dropFirst()))
            guard w.count == 1 else { throw CLIParseError("mcp install needs one client: \(["claudeCode", "codex", "claudeDesktop", "cli", "generic"].joined(separator: ", "))") }
            let o = try Options(flags, values: ["--name", "--icon"], bools: ["--reinstall"])
            var body: [String: Any] = ["client": w[0], "reinstall": o.flag("--reinstall")]
            if let n = o.value("--name") { body["name"] = n }
            if let i = o.value("--icon") { body["icon"] = absolute(i) }
            return .request(CLIRequest(method: "POST", path: "/v1/mcp/install", body: body))
        case "approvals":
            guard let sub = rest.first else { return get("/v1/actions/approvals") }
            guard sub == "revoke" else { throw CLIParseError("approvals needs revoke --app ID --template NAME (or nothing, to list)") }
            let o = try Options(Array(rest.dropFirst()), values: ["--app", "--template"], bools: [])
            return .request(CLIRequest(method: "DELETE", path: "/v1/actions/approvals", query: [("app", try o.require("--app")), ("template", try o.require("--template"))]))
        case "manifest":
            guard rest.first == "delete" else { throw CLIParseError("manifest needs delete --app ID") }
            let o = try Options(Array(rest.dropFirst()), values: ["--app"], bools: [])
            return .request(CLIRequest(method: "DELETE", path: "/v1/manifest", query: [("app", try o.require("--app"))]))
        default:
            return nil
        }
    }

    /// `apps settings [--app ID]` and `apps set --app ID KEY=VALUE ...`; nil for the plain `apps`.
    static func parseAppsParity(_ rest: [String]) throws -> CLIAction? {
        guard let sub = rest.first, !sub.hasPrefix("-") else { return nil }
        let args = Array(rest.dropFirst())
        switch sub {
        case "settings":
            let o = try Options(args, values: ["--app"], bools: [])
            return get("/v1/apps/settings", o.value("--app").map { [("app", $0)] } ?? [])
        case "set":
            // KEY=VALUE words may come before or after --app.
            var words: [String] = [], flags: [String] = []
            var i = 0
            while i < args.count {
                if args[i] == "--app", i + 1 < args.count { flags += [args[i], args[i + 1]]; i += 2 }
                else if args[i].hasPrefix("--app=") { flags.append(args[i]); i += 1 }
                else { words.append(args[i]); i += 1 }
            }
            let o = try Options(flags, values: ["--app"], bools: [])
            var body = try pairs(words, what: "apps set")
            body["app"] = try o.require("--app")
            return .request(CLIRequest(method: "PUT", path: "/v1/apps/settings", body: body))
        default:
            throw CLIParseError("unknown apps command '\(sub)' (use settings or set)")
        }
    }

    /// History subcommands; nil when the first word is not one (the old `history --app ID` form).
    static func parseHistoryParity(_ rest: [String]) throws -> CLIAction? {
        guard let sub = rest.first, ["search", "reshow", "delete", "export"].contains(sub) else { return nil }
        let args = Array(rest.dropFirst())
        switch sub {
        case "search":
            let (w, flags) = words(args)
            guard !w.isEmpty else { throw CLIParseError("history search needs the words to find") }
            let o = try Options(flags, values: ["--app", "--limit"], bools: [])
            var q: [(String, String)] = [("q", w.joined(separator: " "))]
            if let a = o.value("--app") { q.append(("app", a)) }
            if let l = o.value("--limit") { q.append(("limit", l)) }
            return get("/v1/history/search", q)
        case "reshow":
            let o = try Options(args, values: ["--app", "--id"], bools: [])
            return .request(CLIRequest(method: "POST", path: "/v1/history/reshow", body: ["app": try o.require("--app"), "id": try o.require("--id")]))
        case "delete":
            let o = try Options(args, values: ["--app", "--id"], bools: [])
            return .request(CLIRequest(method: "DELETE", path: "/v1/history/item", query: [("app", try o.require("--app")), ("id", try o.require("--id"))]))
        default:
            let o = try Options(args, values: ["--app", "--out", "-o"], bools: [])
            var q: [(String, String)] = []
            if let a = o.value("--app") { q.append(("app", a)) }
            if let out = o.value("--out") ?? o.value("-o") { q.append(("path", absolute(out))) }
            return get("/v1/history/export", q)
        }
    }

    /// Template subcommands beyond export and import; nil when `sub` is not one.
    static func parseTemplateParity(_ sub: String, _ args: [String], readInput: (String) throws -> Data) throws -> CLIAction? {
        switch sub {
        case "list":
            let o = try Options(args, values: ["--app"], bools: [])
            return get("/v1/templates", o.value("--app").map { [("app", $0)] } ?? [])
        case "put":
            guard let source = args.first, !source.hasPrefix("--") || source == "-" else { throw CLIParseError("template put needs a JSON file (or - for stdin)") }
            guard args.count == 1 else { throw CLIParseError("template put takes one file") }
            let body = try loadJSON(source, readInput: readInput)
            return .request(CLIRequest(method: "PUT", path: "/v1/templates", body: body))
        case "delete":
            let o = try Options(args, values: ["--app", "--name"], bools: [])
            return .request(CLIRequest(method: "DELETE", path: "/v1/templates", query: [("app", try o.require("--app")), ("name", try o.require("--name"))]))
        case "duplicate":
            let o = try Options(args, values: ["--app", "--name", "--new-name", "--to-app"], bools: [])
            var body: [String: Any] = ["app": try o.require("--app"), "name": try o.require("--name")]
            if let n = o.value("--new-name") { body["newName"] = n }
            if let t = o.value("--to-app") { body["toApp"] = t }
            return .request(CLIRequest(method: "POST", path: "/v1/templates/duplicate", body: body))
        case "rename":
            let o = try Options(args, values: ["--app", "--name", "--new-name"], bools: [])
            return .request(CLIRequest(method: "POST", path: "/v1/templates/rename",
                                       body: ["app": try o.require("--app"), "name": try o.require("--name"), "newName": try o.require("--new-name")]))
        case "default":
            let o = try Options(args, values: ["--app", "--name"], bools: ["--clear"])
            var body: [String: Any] = ["app": try o.require("--app")]
            if !o.flag("--clear") { body["name"] = try o.require("--name") }
            else if o.value("--name") != nil { throw CLIParseError("use --name or --clear, not both") }
            return .request(CLIRequest(method: "PUT", path: "/v1/templates/default", body: body))
        default:
            return nil
        }
    }
}
