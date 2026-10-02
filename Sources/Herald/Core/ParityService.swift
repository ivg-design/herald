import Foundation

// MCP/API parity with the editor and Settings (docs/reference/parity.md, issue #56).
//
// The routes here close the gaps between what a person can do in Herald's windows and what the loopback API offers:
// the settings table, per-app settings, assets, template duplicate/rename/default/export/import, History search,
// re-show, delete and export, SF Symbol names, the voice and MCP installs, and the approvals list.
//
// All of it is pure file and store work (testable without a window). What needs the running app (UserDefaults, the
// login item, displays, the Kokoro and MCP installers, showing a banner) goes through `ParityHost`.
//
// Security: the routes sit behind the same Bearer token as every other. Approvals that gate code execution
// (command buttons, callback hosts, template commands) can be READ and REVOKED here, never granted: the token
// holder is the program that approval protects against.

/// What the service needs from the running app. Every requirement answers 501 by default so a test supplies only
/// what it exercises.
public protocol ParityHost: AnyObject, Sendable {
    /// The current value of a general setting (a key of `SettingsSchema.general`).
    func settingValue(_ key: String) async -> JSONValue?
    /// Applies a value that already passed `SettingsSchema.validate`.
    func applySetting(_ key: String, _ value: JSONValue) async throws
    /// The choices behind the settings: sounds, displays, voices, corners, engines.
    func options() async -> [String: JSONValue]
    /// The per-app voice preferences: `speak`, `voice`, `urgentBreaksQuiet`.
    func appVoice(_ app: String) async -> [String: JSONValue]
    func applyAppVoice(app: String, key: String, value: JSONValue) async throws
    /// Kokoro: installed or not, what is missing, install progress, available voices.
    func voiceState() async throws -> JSONValue
    /// `install`, `cancel` or `useExisting`.
    func voiceInstall(action: String) async throws -> JSONValue
    /// Per client (Claude Code, Codex, Claude Desktop, CLI): installed or not, and the server path.
    func mcpStatus() async throws -> JSONValue
    /// `name` is the generic client's name (its app becomes `agent.<slug>`); `icon` a file to use as its icon. Installing also
    /// registers the agent as an issuer (app, manifest, default template, icon): see `AgentIssuer`.
    func mcpInstall(client: String, reinstall: Bool, name: String?, icon: String?) async throws -> JSONValue
    /// Shows a stored notification again as a new banner. Returns its id.
    func reshow(_ n: HeraldNotification) async throws -> String
    /// Closes the banner of a notification that is being deleted from History.
    func closeBanner(app: String, id: String) async
    /// Tells the windows to refresh.
    func changed() async
}

public extension ParityHost {
    func settingValue(_ key: String) async -> JSONValue? { nil }
    func applySetting(_ key: String, _ value: JSONValue) async throws { throw BackendError(501, "settings are not supported") }
    func options() async -> [String: JSONValue] { [:] }
    func appVoice(_ app: String) async -> [String: JSONValue] { [:] }
    func applyAppVoice(app: String, key: String, value: JSONValue) async throws { throw BackendError(501, "voice settings are not supported") }
    func voiceState() async throws -> JSONValue { throw BackendError(501, "voice is not supported") }
    func voiceInstall(action: String) async throws -> JSONValue { throw BackendError(501, "voice is not supported") }
    func mcpStatus() async throws -> JSONValue { throw BackendError(501, "MCP install is not supported") }
    func mcpInstall(client: String, reinstall: Bool, name: String?, icon: String?) async throws -> JSONValue { throw BackendError(501, "MCP install is not supported") }
    func reshow(_ n: HeraldNotification) async throws -> String { throw BackendError(501, "re-show is not supported") }
    func closeBanner(app: String, id: String) async {}
    func changed() async {}
}

public final class ParityService: @unchecked Sendable {
    let templates: TemplateStore
    let manifests: ManifestStore
    let history: HistoryStore
    let registry: AppRegistry
    let assets: AssetStore
    let bundles: TemplateBundleService
    let approvals: TemplateCommandApprovals
    let host: ParityHost
    /// Saves go through the app (it refreshes open windows); a service in a test passes the stores' own.
    let saveTemplate: (HeraldTemplate) throws -> Void
    let removeTemplate: (_ app: String, _ name: String) throws -> Void
    let saveManifest: (HeraldManifest) throws -> Void
    let symbols: () -> SymbolListing?

    public init(templates: TemplateStore, manifests: ManifestStore, history: HistoryStore, registry: AppRegistry,
                assets: AssetStore, approvals: TemplateCommandApprovals, host: ParityHost,
                saveTemplate: ((HeraldTemplate) throws -> Void)? = nil,
                removeTemplate: ((String, String) throws -> Void)? = nil,
                saveManifest: ((HeraldManifest) throws -> Void)? = nil,
                symbols: @escaping () -> SymbolListing? = { ParityService.systemSymbols }) {
        self.templates = templates; self.manifests = manifests; self.history = history; self.registry = registry
        self.assets = assets; self.approvals = approvals; self.host = host
        self.bundles = TemplateBundleService(templates: templates, assets: assets, manifest: { manifests.get(app: $0) })
        self.saveTemplate = saveTemplate ?? { t in
            guard templates.put(t) else { throw BackendError(500, "could not save template \(t.name)") }
        }
        self.removeTemplate = removeTemplate ?? { app, name in
            guard templates.delete(app: app, name: name) else { throw BackendError(404, "template not found") }
        }
        self.saveManifest = saveManifest ?? { m in
            guard manifests.put(m) else { throw BackendError(500, "could not save manifest \(m.app)") }
        }
        self.symbols = symbols
    }

    /// Loaded once: reading the CoreGlyphs plists takes a moment.
    public static let systemSymbols: SymbolListing? = SymbolListing.load()

    // MARK: Routing

    static let methods: [String: [String]] = [
        "/v1/settings": ["GET", "PUT"],
        "/v1/apps/settings": ["GET", "PUT"],
        "/v1/assets": ["GET", "POST", "DELETE"],
        "/v1/templates/duplicate": ["POST"],
        "/v1/templates/rename": ["POST"],
        "/v1/templates/default": ["PUT"],
        "/v1/templates/export": ["GET"],
        "/v1/templates/import": ["POST"],
        "/v1/history/search": ["GET"],
        "/v1/history/export": ["GET"],
        "/v1/history/reshow": ["POST"],
        "/v1/history/item": ["DELETE"],
        "/v1/symbols": ["GET"],
        "/v1/voice": ["GET"],
        "/v1/voice/install": ["POST"],
        "/v1/mcp": ["GET"],
        "/v1/mcp/install": ["POST"],
        "/v1/actions/approvals": ["GET", "DELETE"],
    ]

    public static func owns(_ path: String) -> Bool { methods[path] != nil }

    public func handle(_ req: HTTPRequest) async -> HTTPResponse {
        guard let allowed = Self.methods[req.path] else { return .error(404, "not found") }
        guard allowed.contains(req.method) else { return .error(405, "method not allowed") }
        do {
            let response = try await route(req)
            // Whatever changed on disk, the open windows pick it up.
            if req.method != "GET" && response.status < 300 { await host.changed() }
            return response
        } catch let e as BackendError {
            return .error(e.status, e.message)
        } catch {
            return .error(500, "\(error)")
        }
    }

    private func route(_ req: HTTPRequest) async throws -> HTTPResponse {
        do {
            switch (req.method, req.path) {
            case ("GET", "/v1/settings"): return try await getSettings()
            case ("PUT", "/v1/settings"): return try await putSettings(req)
            case ("GET", "/v1/apps/settings"): return try await getAppSettings(req)
            case ("PUT", "/v1/apps/settings"): return try await putAppSettings(req)
            case ("GET", "/v1/assets"): return try listAssets(req)
            case ("POST", "/v1/assets"): return try uploadAsset(req)
            case ("DELETE", "/v1/assets"): return try deleteAsset(req)
            case ("POST", "/v1/templates/duplicate"): return try duplicateTemplate(req)
            case ("POST", "/v1/templates/rename"): return try renameTemplate(req)
            case ("PUT", "/v1/templates/default"): return try setDefaultTemplate(req)
            case ("GET", "/v1/templates/export"): return try exportBundle(req)
            case ("POST", "/v1/templates/import"): return try importBundle(req)
            case ("GET", "/v1/history/search"): return try searchHistory(req)
            case ("GET", "/v1/history/export"): return try exportHistory(req)
            case ("POST", "/v1/history/reshow"): return try await reshow(req)
            case ("DELETE", "/v1/history/item"): return try await deleteHistoryItem(req)
            case ("GET", "/v1/symbols"): return try listSymbols(req)
            case ("GET", "/v1/voice"): return Self.reply(try await host.voiceState())
            case ("POST", "/v1/voice/install"): return try await voiceInstall(req)
            case ("GET", "/v1/mcp"): return Self.reply(try await host.mcpStatus())
            case ("POST", "/v1/mcp/install"): return try await mcpInstall(req)
            case ("GET", "/v1/actions/approvals"): return listApprovals()
            case ("DELETE", "/v1/actions/approvals"): return try await revokeApproval(req)
            default: return .error(404, "not found")
            }
        } catch let e as BackendError {
            return .error(e.status, e.message)
        } catch {
            return .error(500, "\(error)")
        }
    }

    // MARK: Helpers

    static func reply(_ value: JSONValue, status: Int = 200) -> HTTPResponse { .json(status, value) }

    static func reply(_ object: [String: Any], status: Int = 200) -> HTTPResponse {
        let data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data("{}".utf8)
        return HTTPResponse(status: status, body: data)
    }

    func body(_ req: HTTPRequest) throws -> [String: Any] {
        if req.body.isEmpty { return [:] }
        guard let o = (try? JSONSerialization.jsonObject(with: req.body)) as? [String: Any] else { throw BackendError(400, "invalid JSON: the body must be an object") }
        return o
    }

    func requiredString(_ o: [String: Any], _ key: String) throws -> String {
        guard let v = o[key] else { throw BackendError(400, "missing field: \(key)") }
        guard let s = v as? String, !s.trimmingCharacters(in: .whitespaces).isEmpty else { throw BackendError(400, "invalid field: \(key) (a non-empty string)") }
        return s
    }

    func optionalString(_ o: [String: Any], _ key: String) throws -> String? {
        guard let v = o[key], !(v is NSNull) else { return nil }
        guard let s = v as? String else { throw BackendError(400, "invalid field: \(key) (a string)") }
        return s.isEmpty ? nil : s
    }

    func query(_ req: HTTPRequest, _ key: String) -> String? { req.query[key].flatMap { $0.isEmpty ? nil : $0 } }

    func requiredQuery(_ req: HTTPRequest, _ key: String) throws -> String {
        guard let v = query(req, key) else { throw BackendError(400, "\(key) is required") }
        return v
    }

    static func any(_ value: JSONValue) -> Any {
        switch value {
        case .null: return NSNull()
        case .bool(let b): return b
        case .number(let n): return n == n.rounded() && abs(n) < 1e15 ? Int(n) : n
        case .string(let s): return s
        case .array(let a): return a.map(any)
        case .object(let o): return o.mapValues(any)
        }
    }

    static func jsonObject<T: Encodable>(_ value: T) -> Any {
        guard let data = try? HeraldJSON.encoder().encode(value),
              let o = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else { return NSNull() }
        return o
    }

    // MARK: Settings

    func settingsReply() async -> [String: Any] {
        var values: [String: Any] = [:]
        for d in SettingsSchema.general {
            if let v = await host.settingValue(d.key) { values[d.key] = Self.any(v) }
        }
        return ["settings": values, "schema": SettingsSchema.general.map(\.json),
                "options": Self.any(.object(await host.options()))]
    }

    func getSettings() async throws -> HTTPResponse { Self.reply(await settingsReply()) }

    func putSettings(_ req: HTTPRequest) async throws -> HTTPResponse {
        let valid = try SettingsSchema.validate(try body(req), against: SettingsSchema.general)
        for s in valid { try await host.applySetting(s.key, s.value) }
        await host.changed()
        var out = await settingsReply()
        out["applied"] = valid.map(\.key)
        if valid.contains(where: { $0.key == "port" }) { out["note"] = "The server restarts on the new port a moment after this reply; the port file has the new number." }
        return Self.reply(out)
    }

    // MARK: Per-app settings

    func appJSON(_ rec: AppRecord) async -> [String: Any] {
        let d = rec.registration.defaults
        var settings: [String: Any] = [
            "sound": d?.sound ?? EffectiveSettings.fallbackSound,
            "persistent": d?.persistent ?? true,
            "timeout": d?.timeout ?? 0,
            "display": rec.screen ?? BannerDisplay.main,
            "muteBanners": rec.mutedBanners,
            "effectiveCorner": (rec.corner ?? d?.corner ?? .topRight).rawValue,
        ]
        settings["corner"] = rec.corner?.rawValue ?? NSNull()
        settings["stacking"] = rec.stacking?.rawValue ?? NSNull()
        let voice = await host.appVoice(rec.registration.app)
        var approvals: [String: Any] = [
            "commandsRequested": rec.registration.allowCommands ?? false,
            "commandsConfirmed": rec.commandsConfirmed,
            "commandsAllowed": rec.commandsAllowed,
        ]
        approvals["callbackHostRegistered"] = rec.registeredCallbackHost ?? NSNull()
        approvals["callbackHostApproved"] = rec.callbackHostApproved ?? NSNull()
        var o: [String: Any] = ["app": rec.registration.app, "appName": rec.displayName, "settings": settings,
                                "voice": Self.any(.object(voice)), "approvals": approvals]
        if let b = rec.registration.bundleId { o["bundleId"] = b }
        if let c = rec.registration.callbackURL { o["callbackURL"] = c }
        return o
    }

    func getAppSettings(_ req: HTTPRequest) async throws -> HTTPResponse {
        if let app = query(req, "app") {
            guard let rec = registry.record(for: app) else { throw BackendError(404, "unknown app: \(app)") }
            return Self.reply(["apps": [await appJSON(rec)], "schema": SettingsSchema.app.map(\.json)])
        }
        var apps: [[String: Any]] = []
        for r in registry.all() { apps.append(await appJSON(r)) }
        return Self.reply(["apps": apps, "schema": SettingsSchema.app.map(\.json),
                           "options": Self.any(.object(await host.options()))])
    }

    func putAppSettings(_ req: HTTPRequest) async throws -> HTTPResponse {
        var o = try body(req)
        let app = try requiredString(o, "app")
        o["app"] = nil
        guard registry.record(for: app) != nil else { throw BackendError(404, "unknown app: \(app)") }
        let valid = try SettingsSchema.validate(o, against: SettingsSchema.app, nullable: SettingsSchema.nullableApp)
        // Approvals: withdrawing is allowed, granting is not.
        for s in valid where s.key == "revokeCommands" || s.key == "revokeCallbackHost" {
            guard s.value == .bool(true) else {
                throw BackendError(403, "\(s.key): only true is accepted; approvals are given by the user in Settings > Apps, never through the API")
            }
        }
        for s in valid {
            switch s.key {
            case "sound": registry.update(app) { $0.registration.defaults = Self.edited($0.registration.defaults) { $0.sound = s.value.parityString } }
            case "persistent": registry.update(app) { $0.registration.defaults = Self.edited($0.registration.defaults) { $0.persistent = s.value.parityBool } }
            case "timeout": registry.update(app) { $0.registration.defaults = Self.edited($0.registration.defaults) { $0.timeout = s.value.parityNumber } }
            case "corner": registry.update(app) { $0.corner = s.value.parityString.flatMap(HeraldCorner.init(rawValue:)) }
            case "display": registry.update(app) { $0.screen = s.value.parityString == BannerDisplay.main ? nil : s.value.parityString }
            case "muteBanners": registry.update(app) { $0.mutedBanners = s.value.parityBool ?? false }
            case "stacking": registry.update(app) { $0.stacking = s.value.parityString.flatMap(StackingLevel.init(rawValue:)) }
            case "speak", "voice", "urgentBreaksQuiet": try await host.applyAppVoice(app: app, key: s.key, value: s.value)
            case "revokeCommands": registry.update(app) { $0.commandsConfirmed = false }
            case "revokeCallbackHost": registry.update(app) { $0.callbackHostApproved = nil }
            default: break
            }
        }
        await host.changed()
        guard let rec = registry.record(for: app) else { throw BackendError(404, "unknown app: \(app)") }
        return Self.reply(["ok": true, "applied": valid.map(\.key), "app": await appJSON(rec)])
    }

    static func edited(_ d: HeraldAppDefaults?, _ change: (inout HeraldAppDefaults) -> Void) -> HeraldAppDefaults {
        var x = d ?? HeraldAppDefaults()
        change(&x)
        return x
    }

    // MARK: Approvals

    func listApprovals() -> HTTPResponse {
        Self.reply(["items": Self.jsonObject(approvals.all()),
                    "note": "Approvals are granted by the user when a banner asks; here they can only be listed and revoked."])
    }

    func revokeApproval(_ req: HTTPRequest) async throws -> HTTPResponse {
        let app = try requiredQuery(req, "app"), template = try requiredQuery(req, "template")
        guard approvals.all().contains(where: { $0.app == app && $0.template == template }) else {
            throw BackendError(404, "no approval for \(app) / \(template)")
        }
        approvals.revoke(app: app, template: template)
        await host.changed()
        return Self.reply(["ok": true])
    }

    // MARK: Voice and MCP

    func voiceInstall(_ req: HTTPRequest) async throws -> HTTPResponse {
        let action = try requiredString(try body(req), "action")
        guard ["install", "cancel", "useExisting"].contains(action) else {
            throw BackendError(400, "action must be install, cancel or useExisting")
        }
        return Self.reply(try await host.voiceInstall(action: action))
    }

    static let mcpClients = ["claudeCode", "codex", "claudeDesktop", "generic", "cli"]

    func mcpInstall(_ req: HTTPRequest) async throws -> HTTPResponse {
        let o = try body(req)
        let client = try requiredString(o, "client")
        guard Self.mcpClients.contains(client) else { throw BackendError(400, "client must be one of \(Self.mcpClients.joined(separator: ", "))") }
        let reinstall = (o["reinstall"] as? Bool) ?? false
        let name = try optionalString(o, "name"), icon = try optionalString(o, "icon")
        if client == "generic", name == nil { throw BackendError(400, "name is required for the generic client (its app becomes agent.<slug>)") }
        if let icon, !FileManager.default.fileExists(atPath: (icon as NSString).expandingTildeInPath) { throw BackendError(400, "no such icon file: \(icon)") }
        return Self.reply(try await host.mcpInstall(client: client, reinstall: reinstall, name: name,
                                                    icon: icon.map { ($0 as NSString).expandingTildeInPath }))
    }
}

extension JSONValue {
    var parityString: String? { if case .string(let s) = self { return s } else { return nil } }
    var parityBool: Bool? { if case .bool(let b) = self { return b } else { return nil } }
    var parityNumber: Double? { if case .number(let n) = self { return n } else { return nil } }
}
