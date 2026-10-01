import Foundation
import HeraldClient

/// The tool implementations. Every call goes through Herald's HTTP API (`HeraldClient`); nothing here touches
/// the app's files. Failures the model can act on come back as results with `isError: true`.
final class MCPTools: @unchecked Sendable {
    let client: HeraldClient
    /// Where `render_preview` saves its PNGs.
    let previewDirectory: URL
    static let keepPreviews = 40

    init(client: HeraldClient, previewDirectory: URL) {
        self.client = client
        self.previewDirectory = previewDirectory
    }

    /// Runs a tool. An unknown tool name is a protocol error (`-32602`); everything else is a tool result.
    func call(_ name: String, arguments: JSONValue?) async throws -> MCPToolResult {
        guard MCPToolCatalog.byName[name] != nil else { throw RPCError.invalidParams("Unknown tool: \(name)") }
        do {
            let args = try MCPArgs(arguments)
            switch name {
            case "herald_status": return await status()
            case "list_manifests": return try await listManifests()
            case "get_manifest": return try await getManifest(args)
            case "put_manifest": return try await putManifest(args)
            case "list_templates": return try await listTemplates(args)
            case "get_template": return try await getTemplate(args)
            case "put_template": return try await putTemplate(args)
            case "delete_template": return try await deleteTemplate(args)
            case "validate_template": return try await validateTemplate(args)
            case "component_schema": return await componentSchema(args)
            case "render_preview": return try await renderPreview(args)
            case "send_notification": return try await sendNotification(args)
            case "send_test": return try await sendTest(args)
            case "list_shortcuts": return try await listShortcuts()
            case "add_action_rule": return try await addActionRule(args)
            case "list_history": return try await listHistory(args)
            case "dismiss": return try await dismiss(args)
            case "speak": return try await speak(args)
            case "get_quiet_hours": return try await getQuietHours()
            case "set_quiet_hours": return try await setQuietHours(args)
            default: throw RPCError.invalidParams("Unknown tool: \(name)")
            }
        } catch let failure as ToolFailure {
            return .failure(failure)
        } catch let rpc as RPCError {
            throw rpc
        } catch {
            return .failure(ToolFailure(describe(error)))
        }
    }

    // MARK: - Errors

    /// A sentence for a failed Herald call that says what to do about it.
    func describe(_ error: Error) -> String {
        guard let e = error as? HeraldError else { return "\(error)" }
        switch e {
        case .notRunning:
            return "Herald is not running or not reachable (looked for the token and port files in \(client.supportDirectory.path) and for an answer on 127.0.0.1:\(client.port)). Start Herald.app and try again."
        case .unauthorized:
            return "Herald rejected the token in \(client.supportDirectory.path)/token. Another Herald may own the port, or the token was regenerated; restart this MCP server."
        case .server(let status, let message):
            if status == 404 && message == "not found" {
                return "Herald answered 404 for this request: the running Herald predates Herald 1.1. Update and restart Herald."
            }
            if status == 501 { return "The running Herald does not support this (501 \(message))." }
            return "Herald returned \(status): \(message)"
        case .invalidResponse:
            return "Herald answered with something herald-mcp could not read (a version mismatch?)."
        }
    }

    private func objectOf(_ pairs: [String: JSONValue?]) -> JSONValue {
        .object(pairs.compactMapValues { $0 })
    }

    private func strings(_ items: [String]) -> JSONValue { .array(items.map { .string($0) }) }

    // MARK: - Status

    private func status() async -> MCPToolResult {
        var out: [String: JSONValue] = [
            "server": .string("herald-mcp \(MCPServer.serverVersion)"),
            "supportDirectory": .string(client.supportDirectory.path),
            "port": .number(Double(client.port)),
            "tokenFile": .bool(client.token != nil),
        ]
        do {
            let h = try await client.health()
            out["running"] = .bool(h.ok)
            out["version"] = .string(h.version)
            out["pid"] = .number(Double(h.pid))
        } catch {
            out["running"] = .bool(false)
            out["hint"] = .string(describe(error))
            return .json(.object(out))
        }
        if client.token == nil {
            out["authorized"] = .bool(false)
            out["hint"] = .string("Herald answers but no token file was found in \(client.supportDirectory.path); the other tools will fail.")
            return .json(.object(out))
        }
        do { out["apps"] = strings(try await client.apps().map(\.app)) }
        catch HeraldError.unauthorized { out["authorized"] = .bool(false); out["hint"] = .string(describe(HeraldError.unauthorized)); return .json(.object(out)) }
        catch {}
        do {
            out["manifests"] = .number(Double(try await client.manifests().count))
        } catch HeraldError.server(let status, _) where status == 404 || status == 501 {
            out["hint"] = .string("This Herald predates 1.1 (no manifests, grid templates or previews). Update Herald.")
        } catch {}
        if let n = try? await client.templates().count { out["templates"] = .number(Double(n)) }
        if let n = try? await client.shortcuts().count { out["shortcuts"] = .number(Double(n)) }
        out["scriptsDirectory"] = .string(scriptsDirectory.path)
        out["scripts"] = strings(scriptFiles())
        return .json(.object(out))
    }

    // MARK: - Scripts

    /// Where `script` actions find their files (`Application Support/Herald/scripts` of the Herald this server talks to).
    var scriptsDirectory: URL { client.supportDirectory.appendingPathComponent("scripts", isDirectory: true) }

    /// The files directly in the scripts folder (hidden files skipped), at most `limit`. A template's `script` is a
    /// plain file name, so files in sub-folders are of no use to it.
    func scriptFiles(limit: Int = 50) -> [String] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: scriptsDirectory, includingPropertiesForKeys: [.isRegularFileKey],
                                                                 options: [.skipsHiddenFiles])) ?? []
        let names = urls.filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }.map(\.lastPathComponent)
        return Array(names.sorted().prefix(limit))
    }

    /// Extensions Herald runs through an interpreter (see ActionRunner); other files must be executable.
    private static let scriptExtensions: Set<String> = ["sh", "zsh", "bash", "py", "rb", "pl", "applescript", "scpt"]

    /// Warnings for a `script` action: the file should exist in the scripts folder and be runnable.
    private func scriptWarnings(for action: HeraldAction, path: String) -> [HeraldTemplateIssue] {
        guard action.kind == .script, let name = action.script?.trimmingCharacters(in: .whitespaces), !name.isEmpty,
              !name.hasPrefix("/"), !name.hasPrefix("~"), !name.contains("..") else { return [] }
        let url = scriptsDirectory.appendingPathComponent(name)
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue else {
            return [.init(severity: .warning, path: "\(path).script",
                          message: "No file '\(name)' in \(scriptsDirectory.path). Create it there first (the script receives the notification JSON on stdin); the button fails until it exists.")]
        }
        if !Self.scriptExtensions.contains(url.pathExtension.lowercased()), !FileManager.default.isExecutableFile(atPath: url.path) {
            return [.init(severity: .warning, path: "\(path).script",
                          message: "'\(name)' is not executable and has no known extension (.sh .zsh .bash .py .rb .pl .scpt): chmod +x it, or rename it.")]
        }
        return []
    }

    // MARK: - Manifests

    private func listManifests() async throws -> MCPToolResult {
        let items = try await client.manifests().map { m -> JSONValue in
            objectOf([
                "app": .string(m.app), "appName": .string(m.appName), "version": .number(Double(m.version)),
                "fields": strings(m.fields.map { "\($0.key):\($0.type.rawValue)" + ($0.required == true ? "!" : "") }),
                "actions": strings(m.actions.indices.map { m.actionID(at: $0) }),
                "assets": strings(m.assets.map(\.id)),
                "defaultTemplate": m.defaultTemplate.map { .string($0) },
            ])
        }
        return .json(.object(["count": .number(Double(items.count)), "manifests": .array(items),
                              "note": .string("A trailing ! marks a required field. get_manifest shows sample values.")]), pretty: true)
    }

    private func getManifest(_ args: MCPArgs) async throws -> MCPToolResult {
        let app = try args.requiredString("app")
        guard let m = try await client.manifest(app: app) else {
            let known = ((try? await client.manifests()) ?? []).map(\.app)
            throw ToolFailure("No manifest is registered for app '\(app)'.",
                              details: ["registered": strings(known)])
        }
        return .json(try JSONValue(encoding: m).abbreviated())
    }

    private func putManifest(_ args: MCPArgs) async throws -> MCPToolResult {
        let raw = JSONValue.object(try args.requiredObject("manifest"))
        let m: HeraldManifest
        do { m = try raw.decoded(HeraldManifest.self) }
        catch { throw DecodeReport.failure(error, what: "manifest", raw: raw) }
        let problems = m.validationErrors()
        guard problems.isEmpty else {
            throw ToolFailure("Manifest not saved: \(problems.count) problem(s).", details: ["errors": strings(problems)])
        }
        try await client.putManifest(m)
        return .json(.object([
            "saved": .bool(true), "app": .string(m.app), "fields": .number(Double(m.fields.count)),
            "actions": .number(Double(m.actions.count)), "assets": .number(Double(m.assets.count)),
            "defaultTemplate": m.defaultTemplate.map { .string($0) } ?? .null,
        ]))
    }

    // MARK: - Templates

    private func templateSummary(_ t: HeraldTemplate, defaultName: String?) -> JSONValue {
        objectOf([
            "app": .string(t.app), "name": .string(t.name), "layoutVersion": .number(Double(t.layoutVersion)),
            "layout": t.usesGrid ? nil : .string(t.layout.rawValue),
            "cells": .number(Double(t.cells.count)), "tokens": strings(t.referencedTokens),
            "actionRules": .number(Double(t.actionRules.count)), "collapseEmpty": .bool(t.collapseEmpty),
            "isDefault": .bool(defaultName == t.name),
        ])
    }

    private func listTemplates(_ args: MCPArgs) async throws -> MCPToolResult {
        let app = try args.string("app").flatMap { $0.isEmpty ? nil : $0 }
        let templates = try await client.templates(app: app)
        let defaults = Dictionary(uniqueKeysWithValues:
            ((try? await client.manifests()) ?? []).compactMap { m in m.defaultTemplate.map { (m.app, $0) } })
        return .json(.object([
            "count": .number(Double(templates.count)),
            "templates": .array(templates.map { templateSummary($0, defaultName: defaults[$0.app]) }),
            "builtins": strings(BuiltinTemplates.names),
        ]))
    }

    private func getTemplate(_ args: MCPArgs) async throws -> MCPToolResult {
        let app = try args.requiredString("app"), name = try args.requiredString("name")
        guard let t = try await client.template(app: app, name: name) else { throw await templateNotFound(app: app, name: name) }
        return .json(try JSONValue(encoding: t))
    }

    private func templateNotFound(app: String, name: String) async -> ToolFailure {
        let saved = ((try? await client.templates(app: app)) ?? []).map(\.name)
        return ToolFailure("No template '\(name)' for app '\(app)'.",
                           details: ["saved": strings(saved), "builtins": strings(BuiltinTemplates.names)])
    }

    /// Decodes a template document and finds the keys the format does not know. Errors say where (and in which cell).
    private func parseTemplate(_ object: [String: JSONValue]) throws -> (HeraldTemplate, [HeraldTemplateIssue]) {
        let raw = JSONValue.object(object)
        for key in ["name", "app"] where (object[key]?.stringValue ?? "").trimmingCharacters(in: .whitespaces).isEmpty {
            throw ToolFailure("Invalid template at \(key): \(key) is required.", details: ["path": .string(key)])
        }
        do { return (try raw.decoded(HeraldTemplate.self), TemplateKeyCheck.warnings(in: object)) }
        catch { throw DecodeReport.failure(error, what: "template", raw: raw) }
    }

    private func issuesJSON(_ issues: [HeraldTemplateIssue]) throws -> JSONValue {
        .array(try issues.map { try JSONValue(encoding: $0) })
    }

    /// Errors fail the call (nothing is saved); warnings travel with the success.
    private func validated(_ t: HeraldTemplate, extra: [HeraldTemplateIssue], manifest: HeraldManifest?,
                           verb: String) throws -> [HeraldTemplateIssue] {
        let issues = t.validate(manifest: manifest) + extra
        let errors = issues.filter(\.isError)
        guard errors.isEmpty else {
            throw ToolFailure("Template not \(verb): \(errors.count) error(s). Fix them and call again.", details: [
                "saved": .bool(false),
                "errors": try issuesJSON(errors),
                "warnings": try issuesJSON(issues.filter { !$0.isError }),
            ])
        }
        return issues
    }

    private func putTemplate(_ args: MCPArgs) async throws -> MCPToolResult {
        var raw = try args.requiredObject("template")
        if let app = try args.string("app"), !app.isEmpty {
            if (raw["app"]?.stringValue ?? "").isEmpty { raw["app"] = .string(app) }
            else if raw["app"]?.stringValue != app {
                throw ToolFailure("Argument 'app' ('\(app)') does not match the template's own app ('\(raw["app"]?.stringValue ?? "")'). Drop one of them.",
                                  details: ["saved": .bool(false), "path": .string("app")])
            }
        }
        let (t, unknownKeys) = try parseTemplate(raw)
        if BuiltinTemplates.isBuiltin(t.name) || t.name.hasPrefix(BuiltinTemplates.prefix) {
            throw ToolFailure("Template names starting with '\(BuiltinTemplates.prefix)' are reserved for the built-in layouts. Pick another name.",
                              details: ["saved": .bool(false), "path": .string("name")])
        }
        let manifest = try? await client.manifest(app: t.app)
        let issues = try validated(t, extra: unknownKeys, manifest: manifest, verb: "saved")
        try await client.putTemplate(t)

        var notes: [String] = []
        if manifest == nil { notes.append("No manifest was available for '\(t.app)', so {tokens} were not checked against its fields.") }
        var isDefault = false
        if try args.bool("setAsDefault") == true {
            if var m = manifest {
                m.defaultTemplate = t.name
                try await client.putManifest(m)
                isDefault = true
            } else {
                notes.append("setAsDefault was ignored: '\(t.app)' has no manifest (put_manifest, then set defaultTemplate).")
            }
        }
        return .json(.object([
            "saved": .bool(true), "app": .string(t.app), "name": .string(t.name),
            "layoutVersion": .number(Double(t.layoutVersion)), "cells": .number(Double(t.cells.count)),
            "isDefault": .bool(isDefault),
            "warnings": try issuesJSON(issues.filter { !$0.isError }),
            "notes": strings(notes),
            "next": .string("render_preview to look at it; send_test to see the real banner."),
        ]))
    }

    private func deleteTemplate(_ args: MCPArgs) async throws -> MCPToolResult {
        let app = try args.requiredString("app"), name = try args.requiredString("name")
        if name.hasPrefix(BuiltinTemplates.prefix) {
            throw ToolFailure("'\(name)' is a built-in template and cannot be deleted.")
        }
        do { try await client.deleteTemplate(app: app, name: name) }
        catch HeraldError.server(let status, _) where status == 404 { throw await templateNotFound(app: app, name: name) }
        var notes: [String] = []
        if let m = (try? await client.manifest(app: app)) ?? nil, m.defaultTemplate == name {
            notes.append("'\(name)' is still the manifest's defaultTemplate; put_manifest to change it.")
        }
        return .json(.object(["deleted": .bool(true), "app": .string(app), "name": .string(name), "notes": strings(notes)]))
    }

    /// What the template does with the manifest's sample data: which cells are empty, which rows and columns
    /// collapse, and the action list after the rules.
    private func sampleAnalysis(_ t: HeraldTemplate, manifest: HeraldManifest?) -> JSONValue? {
        guard t.usesGrid else { return nil }
        var fields = TemplateResolver.sampleFields(manifest: manifest)
        for (k, v) in t.extra where !v.isEmpty { fields["extra.\(k)"] = .text(v) }
        let actions = ActionResolver.resolveDetailed(issuer: manifest?.actions ?? [], ids: manifest?.actionIDs, rules: t.actionRules)
        let empty = t.emptyCellIDs(fields: fields, actions: actions)
        let plan = t.plan(emptyCells: empty)
        return .object([
            "emptyCells": strings(empty.sorted()),
            "collapsedCells": strings(plan.collapsedCells.sorted()),
            "collapsedRows": .array(plan.collapsedRows.sorted().map { .number(Double($0)) }),
            "collapsedCols": .array(plan.collapsedCols.sorted().map { .number(Double($0)) }),
            "actions": actionList(actions),
        ])
    }

    private func actionList(_ actions: [HeraldResolvedAction]) -> JSONValue {
        .array(actions.map { r in
            objectOf(["id": .string(r.action.id), "label": .string(r.action.label), "kind": .string(r.action.kind.rawValue),
                      "style": r.action.style.map { .string($0) }, "origin": .string(r.origin.rawValue)])
        })
    }

    private func validateTemplate(_ args: MCPArgs) async throws -> MCPToolResult {
        let app = try args.string("app").flatMap { $0.isEmpty ? nil : $0 }
        var template: HeraldTemplate
        var extra: [HeraldTemplateIssue] = []
        if var raw = try args.object("template") {
            if (raw["app"]?.stringValue ?? "").isEmpty, let app { raw["app"] = .string(app) }
            (template, extra) = try parseTemplate(raw)
        } else if let name = try args.string("name") {
            guard let app else { throw ToolFailure("Give 'app' together with 'name'.") }
            guard let saved = try await client.template(app: app, name: name) else { throw await templateNotFound(app: app, name: name) }
            template = saved
        } else {
            throw ToolFailure("Give either 'template' (a draft object) or 'app' and 'name' (a saved template).")
        }
        let manifestApp = app ?? template.app
        var manifestChecked = false
        var manifest: HeraldManifest?
        do { manifest = try await client.manifest(app: manifestApp); manifestChecked = manifest != nil }
        catch { manifest = nil }
        let issues = template.validate(manifest: manifest) + extra
        var out: [String: JSONValue] = [
            "valid": .bool(!issues.contains { $0.isError }),
            "errors": try issuesJSON(issues.filter(\.isError)),
            "warnings": try issuesJSON(issues.filter { !$0.isError }),
            "manifestChecked": .bool(manifestChecked),
            "tokens": strings(template.referencedTokens),
        ]
        if let analysis = sampleAnalysis(template, manifest: manifest) { out["withSampleData"] = analysis }
        if !manifestChecked {
            out["note"] = .string("No manifest was available for '\(manifestApp)' (Herald not running, or none registered): {tokens} were not checked and the sample data is generic.")
        }
        return .json(.object(out))
    }

    // MARK: - Component schema

    private func componentSchema(_ args: MCPArgs) async -> MCPToolResult {
        do {
            let component = try args.string("component"), section = try args.string("section")
            // Prefer the running Herald's document (it matches what it will accept); fall back to the schema
            // compiled into this binary when Herald is down or predates /v1/components.
            var doc: JSONValue
            var source = "herald"
            do { doc = try await client.components() }
            catch { doc = ComponentSchema.document(); source = "herald-mcp (built in; Herald did not answer /v1/components)" }

            if let component {
                guard let c = doc["components"]?[component] else {
                    throw ToolFailure("Unknown component type '\(component)'.", details: ["types": strings(HeraldComponent.typeNames)])
                }
                return .json(.object(["component": .string(component), "schema": c,
                                      "definitions": Self.referencedDefinitions(of: c, in: doc), "source": .string(source)]))
            }
            if let section {
                guard let s = doc[section] else {
                    throw ToolFailure("Unknown section '\(section)'.", details: ["sections": strings(MCPToolCatalog.schemaSections)])
                }
                return .json(.object(["section": .string(section), "value": s, "source": .string(source)]))
            }
            var blocks: [MCPToolResult.Block] = [.text(doc.text())]
            if source != "herald" { blocks.append(.text("Source: \(source).")) }
            return MCPToolResult(blocks: blocks)
        } catch let f as ToolFailure {
            return .failure(f)
        } catch {
            return .failure(ToolFailure("\(error)"))
        }
    }

    /// The `definitions` a schema points at with `{"$ref": "#/definitions/<name>"}`, and those they point at.
    static func referencedDefinitions(of schema: JSONValue, in doc: JSONValue) -> JSONValue {
        guard let all = doc["definitions"]?.objectValue else { return .object([:]) }
        func refs(in v: JSONValue, into found: inout Set<String>) {
            switch v {
            case .object(let o):
                if case .string(let r)? = o["$ref"], r.hasPrefix("#/definitions/") { found.insert(String(r.dropFirst("#/definitions/".count))) }
                for child in o.values { refs(in: child, into: &found) }
            case .array(let a): for child in a { refs(in: child, into: &found) }
            default: break
            }
        }
        var needed = Set<String>()
        refs(in: schema, into: &needed)
        var queue = Array(needed)
        while let name = queue.popLast() {
            guard let d = all[name] else { continue }
            var inner = Set<String>()
            refs(in: d, into: &inner)
            for n in inner where needed.insert(n).inserted { queue.append(n) }
        }
        return .object(all.filter { needed.contains($0.key) })
    }

    // MARK: - Preview

    private func renderPreview(_ args: MCPArgs) async throws -> MCPToolResult {
        var warnings: [HeraldTemplateIssue] = []
        var templateRef: JSONValue
        var templateLabel: String
        var app = try args.string("app").flatMap { $0.isEmpty ? nil : $0 }

        if var raw = try args.object("template") {
            if (raw["app"]?.stringValue ?? "").isEmpty, let app { raw["app"] = .string(app) }
            if (raw["name"]?.stringValue ?? "").isEmpty { raw["name"] = .string("draft") }
            let (t, unknown) = try parseTemplate(raw)
            let manifest = try? await client.manifest(app: t.app)
            warnings = try validated(t, extra: unknown, manifest: manifest, verb: "rendered").filter { !$0.isError }
            app = app ?? t.app
            templateRef = try JSONValue(encoding: t)
            templateLabel = t.name
        } else if let name = try args.string("name") {
            guard app != nil else { throw ToolFailure("Give 'app' together with 'name'.") }
            templateRef = .string(name)
            templateLabel = name
        } else {
            guard app != nil else {
                throw ToolFailure("Give 'app', and 'name' (a saved template or builtin.*) or 'template' (a draft object). With neither name nor template the app's default template is rendered.")
            }
            templateRef = .null     // Herald draws the manifest's defaultTemplate, else a built-in
            templateLabel = "default"
        }
        let appID = app ?? ""

        let appearance = try args.string("appearance") ?? "light"
        guard ["light", "dark"].contains(appearance) else { throw ToolFailure("Argument 'appearance' must be light or dark.") }
        let scale = min(max(try args.number("scale") ?? 2, 1), 3)
        let source = try args.string("source") ?? "sample"
        guard ["sample", "last"].contains(source) else { throw ToolFailure("Argument 'source' must be sample or last.") }
        let overrides = try args.object("data") ?? [:]

        var data: JSONValue = .string("sample")
        if source == "last" || !overrides.isEmpty {
            var fields: [String: JSONValue]
            if source == "last" {
                guard let item = try await client.history(app: appID, limit: 1).first else {
                    throw ToolFailure("'\(appID)' has no notification in history yet; use source \"sample\".")
                }
                let resolved = item.fields ?? TemplateResolver.fields(for: item.notification, deliveredAt: item.deliveredAt)
                fields = resolved.mapValues(\.json)
            } else {
                let manifest = try? await client.manifest(app: appID)
                fields = TemplateResolver.sampleFields(manifest: manifest).mapValues(\.json)
                for k in ["app", "appName"] { fields[k] = nil }     // Herald fills these in
            }
            for (k, v) in overrides { fields[k] = v }
            data = .object(fields)
        }

        let request = HeraldPreviewRequest(template: templateRef, app: appID, data: data, appearance: appearance, scale: scale)
        let png = try await client.preview(request)
        let file = try savePreview(png, app: appID, template: templateLabel, appearance: appearance)

        var info: [String: JSONValue] = [
            "path": .string(file.path), "bytes": .number(Double(png.count)),
            "app": .string(appID), "template": .string(templateLabel),
            "appearance": .string(appearance), "scale": .number(scale),
            "data": .string(overrides.isEmpty ? source : "\(source)+overrides"),
        ]
        if let size = PNGInfo.size(of: png) { info["width"] = .number(Double(size.width)); info["height"] = .number(Double(size.height)) }
        if !warnings.isEmpty { info["warnings"] = try issuesJSON(warnings) }
        return MCPToolResult(blocks: [.image(data: png, mimeType: "image/png"), .text(JSONValue.object(info).text())])
    }

    /// Saves the PNG under `previewDirectory` and removes all but the newest `keepPreviews` files.
    private func savePreview(_ png: Data, app: String, template: String, appearance: String) throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(at: previewDirectory, withIntermediateDirectories: true)
        let stamp = DateFormatter()
        stamp.locale = Locale(identifier: "en_US_POSIX")
        stamp.dateFormat = "yyyyMMdd-HHmmss"
        let name = "preview-\(app.fileSlug)-\(template.fileSlug)-\(appearance)-\(stamp.string(from: Date()))-\(UUID().uuidString.prefix(4)).png"
        let url = previewDirectory.appendingPathComponent(name)
        do { try png.write(to: url, options: .atomic) }
        catch { throw ToolFailure("Could not save the preview PNG to \(url.path): \(error.localizedDescription)") }

        let files = ((try? fm.contentsOfDirectory(at: previewDirectory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? [])
            .filter { $0.lastPathComponent.hasPrefix("preview-") && $0.pathExtension == "png" }
        if files.count > Self.keepPreviews {
            let dated = files.map { ($0, (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) }
            for (old, _) in dated.sorted(by: { $0.1 > $1.1 }).dropFirst(Self.keepPreviews) { try? fm.removeItem(at: old) }
        }
        return url
    }

    // MARK: - Sending

    private func sendNotification(_ args: MCPArgs) async throws -> MCPToolResult {
        let app = try args.requiredString("app")
        var payload = args.values.filter { !$0.value.isNull }
        if let fields = try args.object("fields") {
            payload["fields"] = nil
            for (k, v) in fields where payload[k] == nil { payload[k] = v }
        }
        let id = try await client.notify(payload: .object(payload))
        return .json(.object(["sent": .bool(true), "id": .string(id), "app": .string(app)]))
    }

    private func sendTest(_ args: MCPArgs) async throws -> MCPToolResult {
        let app = try args.requiredString("app")
        let manifest = try await client.manifest(app: app)
        guard let templateName = try args.string("template").flatMap({ $0.isEmpty ? nil : $0 }) ?? manifest?.defaultTemplate else {
            throw ToolFailure("No template given and '\(app)' has no manifest defaultTemplate. Pass 'template' (a saved template's name).")
        }
        if !BuiltinTemplates.isBuiltin(templateName) {
            let saved = try await client.templates(app: app).map(\.name)
            guard saved.contains(templateName) else {
                throw ToolFailure("No saved template '\(templateName)' for app '\(app)'. Save it with put_template first.",
                                  details: ["saved": strings(saved), "builtins": strings(BuiltinTemplates.names)])
            }
        }

        var fields = TemplateResolver.sampleFields(manifest: manifest)
        for k in ["app", "appName", "id", "deliveredAt"] { fields[k] = nil }
        var payload = fields.mapValues(\.json)
        for (k, v) in try args.object("data") ?? [:] { payload[k] = v }
        payload["app"] = .string(app)
        payload["template"] = .string(templateName)
        payload["id"] = .string(try args.string("id").flatMap { $0.isEmpty ? nil : $0 } ?? "mcp-test-\(templateName)")
        if (payload["title"]?.stringValue ?? "").isEmpty { payload["title"] = .string("Test: \(templateName)") }

        var issuerActions: [String] = []
        if try args.bool("includeIssuerActions") ?? true, let m = manifest, !m.actions.isEmpty, payload["buttons"] == nil {
            payload["buttons"] = try JSONValue(encoding: m.actions)
            issuerActions = m.actions.indices.map { m.actionID(at: $0) }
        }
        let id = try await client.notify(payload: .object(payload))
        return .json(.object([
            "sent": .bool(true), "id": .string(id), "app": .string(app), "template": .string(templateName),
            "fields": strings(payload.keys.filter { !["app", "template", "id", "buttons"].contains($0) }.sorted()),
            "issuerActions": strings(issuerActions),
        ]))
    }

    private func dismiss(_ args: MCPArgs) async throws -> MCPToolResult {
        let app = try args.requiredString("app")
        if let id = try args.string("id"), !id.isEmpty {
            try await client.dismiss(app: app, id: id)
            return .json(.object(["dismissed": .string(id), "app": .string(app)]))
        }
        guard try args.bool("all") == true else { throw ToolFailure("Give the banner's 'id', or all: true to dismiss every banner of '\(app)'.") }
        try await client.dismissAll(app: app)
        return .json(.object(["dismissedAll": .bool(true), "app": .string(app)]))
    }

    private func speak(_ args: MCPArgs) async throws -> MCPToolResult {
        let app = try args.requiredString("app")
        let text = try args.requiredString("text")
        let request = HeraldSpeakRequest(app: app, text: text, id: try args.string("id").flatMap { $0.isEmpty ? nil : $0 },
                                         voice: try args.string("voice").flatMap { $0.isEmpty ? nil : $0 },
                                         speed: try args.number("speed"),
                                         lang: try args.string("lang").flatMap { $0.isEmpty ? nil : $0 })
        let id = try await client.speak(request)
        return .json(.object(["spoken": .bool(true), "id": .string(id), "app": .string(app)]))
    }

    private func getQuietHours() async throws -> MCPToolResult {
        .json(try JSONValue(encoding: try await client.quietHours()))
    }

    private func setQuietHours(_ args: MCPArgs) async throws -> MCPToolResult {
        var update = HeraldQuietUpdate()
        if let w = args.values["windows"], !w.isNull {
            do { update.windows = try JSONDecoder().decode([QuietWindow].self, from: try JSONEncoder().encode(w)) }
            catch { throw ToolFailure("windows must be [{days?, start: \"HH:MM\", end: \"HH:MM\", speech?, sounds?, banners?, speakSummary?}]: \(error)") }
        }
        if try args.bool("resume") == true { update.resume = true }
        let until = try args.string("until").flatMap { $0.isEmpty ? nil : $0 }
        let minutes = try args.number("minutes")
        if until != nil || minutes != nil {
            update.adHoc = .init(until: until, minutes: minutes, banners: try args.bool("banners"))
        }
        guard update.windows != nil || update.resume != nil || update.adHoc != nil else {
            throw ToolFailure("Nothing to change: give windows, until, minutes or resume: true.")
        }
        return .json(try JSONValue(encoding: try await client.setQuietHours(update)))
    }

    // MARK: - Shortcuts and action rules

    private func listShortcuts() async throws -> MCPToolResult {
        let names = try await client.shortcuts()
        return .json(.object(["count": .number(Double(names.count)), "shortcuts": strings(names),
                              "use": .string("add_action_rule with {\"add\": {\"id\": \"...\", \"label\": \"...\", \"kind\": \"shortcut\", \"shortcut\": \"<one of these names>\", \"input\": \"{title}\\n{url}\"}}")]))
    }

    private func addActionRule(_ args: MCPArgs) async throws -> MCPToolResult {
        let app = try args.requiredString("app"), name = try args.requiredString("template")
        if name.hasPrefix(BuiltinTemplates.prefix) {
            throw ToolFailure("'\(name)' is a built-in template and is read-only. get_template it, then put_template it under a new name (with the rule in actionRules).")
        }
        guard var t = try await client.template(app: app, name: name) else { throw await templateNotFound(app: app, name: name) }

        let rawRule = JSONValue.object(try args.requiredObject("rule"))
        let rule: HeraldActionRule
        do { rule = try rawRule.decoded(HeraldActionRule.self) }
        catch { throw DecodeReport.failure(error, what: "rule", raw: rawRule) }
        let hasMatch = !(rule.match ?? "").trimmingCharacters(in: .whitespaces).isEmpty
        guard hasMatch || rule.add != nil else {
            throw ToolFailure("A rule needs 'match' (an issuer action's id or label, or \"*\") or 'add' (an action of your own).")
        }

        var index = t.actionRules.count
        var replaced = false
        if let add = rule.add, !hasMatch,
           let i = t.actionRules.firstIndex(where: { ($0.match ?? "").isEmpty && $0.add?.id == add.id }) {
            index = i; replaced = true
            t.actionRules[i] = rule
        } else {
            t.actionRules.append(rule)
        }

        let manifest = (try? await client.manifest(app: app)) ?? nil
        var extra: [HeraldTemplateIssue] = []
        let rulePath = "actionRules[\(index)]"
        if hasMatch, let match = rule.match, match != "*" {
            var known = Set<String>()
            for (i, b) in (manifest?.actions ?? []).enumerated() { known.insert(manifest!.actionID(at: i).lowercased()); known.insert(b.label.lowercased()) }
            for r in t.actionRules { if let a = r.add { known.insert(a.id.lowercased()); known.insert(a.label.lowercased()) } }
            if manifest != nil, !known.contains(match.lowercased()) {
                extra.append(.init(severity: .warning, path: "\(rulePath).match",
                                   message: "'\(match)' is not an action the manifest declares (\(known.sorted().joined(separator: ", "))) nor one this template adds; the rule matches nothing unless the issuer sends it as a button."))
            }
        }
        if let add = rule.add, add.kind == .shortcut, let shortcut = add.shortcut,
           let installed = try? await client.shortcuts(), !installed.contains(shortcut) {
            let near = installed.first { $0.caseInsensitiveCompare(shortcut) == .orderedSame }
            extra.append(.init(severity: .warning, path: "\(rulePath).add.shortcut",
                               message: near.map { "No Shortcut named '\(shortcut)'; did you mean '\($0)'?" }
                                   ?? "No installed Shortcut is named '\(shortcut)' (list_shortcuts shows the installed ones). The button will fail until it exists."))
        }
        if let add = rule.add { extra += scriptWarnings(for: add, path: "\(rulePath).add") }
        let issues = try validated(t, extra: extra, manifest: manifest, verb: "saved")
        try await client.putTemplate(t)

        let resolved = ActionResolver.resolveDetailed(issuer: manifest?.actions ?? [], ids: manifest?.actionIDs, rules: t.actionRules)
        var out: [String: JSONValue] = [
            "saved": .bool(true), "app": .string(app), "template": .string(name),
            "ruleIndex": .number(Double(index)), "replacedExistingRule": .bool(replaced),
            "actionRules": .number(Double(t.actionRules.count)),
            "resultingActions": actionList(resolved),
            "warnings": try issuesJSON(issues.filter { !$0.isError }),
        ]
        if manifest == nil { out["note"] = .string("No manifest for '\(app)': resultingActions lists only the actions this template adds; the issuer's buttons are unknown.") }
        return .json(.object(out))
    }

    // MARK: - History

    private func listHistory(_ args: MCPArgs) async throws -> MCPToolResult {
        let app = try args.string("app").flatMap { $0.isEmpty ? nil : $0 }
        let limit = min(max(try args.int("limit") ?? 10, 1), 100)
        let full = try args.bool("full") ?? false
        let items = try await client.history(app: app, limit: limit)
        let rows: [JSONValue] = try items.map { item in
            if full { return try JSONValue(encoding: item).abbreviated() }
            return objectOf([
                "id": .string(item.id), "app": .string(item.app), "title": .string(item.notification.title),
                "subtitle": item.notification.subtitle.map { .string($0) },
                "template": item.notification.template.map { .string($0) },
                "deliveredAt": .string(ISODate.string(from: item.deliveredAt)),
                "dismissedAt": item.dismissedAt.map { .string(ISODate.string(from: $0)) },
                "actionUsed": item.actionUsed.map { .string($0) },
                "fields": item.fields.map { JSONValue.object($0.mapValues(\.json)).abbreviated(maxString: 300) },
            ])
        }
        return .json(.object(["count": .number(Double(rows.count)), "items": .array(rows)]))
    }
}
