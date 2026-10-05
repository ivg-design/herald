import Foundation

public struct BackendError: Error, Equatable {
    public var status: Int
    public var message: String
    public init(_ status: Int, _ message: String) { self.status = status; self.message = message }
}

/// What the router needs from the app. Implemented by the AppController.
public protocol HeraldBackend: AnyObject, Sendable {
    func notify(_ n: HeraldNotification) async throws -> String
    func register(_ r: HeraldAppRegistration) async throws
    func dismiss(app: String, id: String) async throws
    func dismissAll(app: String?) async throws
    func history(app: String?, limit: Int) async throws -> [HeraldHistoryItem]
    func clearHistory(app: String?) async throws
    func apps() async throws -> [HeraldAppRegistration]
    /// `DELETE /v1/apps/{id}`: the app's record, History, templates, manifest and icon files, together.
    func deleteApp(app: String) async throws
    func templates(app: String?) async throws -> [HeraldTemplate]
    func putTemplate(_ t: HeraldTemplate) async throws
    func deleteTemplate(app: String, name: String) async throws
    /// `herald compose`: open the Composer window.
    func compose() async throws
    // Herald 1.1 (DESIGN section 7)
    func manifests() async throws -> [HeraldManifest]
    func manifest(app: String) async throws -> HeraldManifest?
    func putManifest(_ m: HeraldManifest) async throws
    func deleteManifest(app: String) async throws
    /// Names of the installed Shortcuts.
    func shortcuts() async throws -> [String]
    /// `POST|GET /v1/preview`: the PNG of a template rendered offscreen (DESIGN section 7.5).
    func preview(_ request: PreviewSpec) async throws -> Data
    /// `GET/PUT /v1/settings/quiet-hours` (DESIGN section 7.9.1).
    func quietHours() async throws -> HeraldQuietReply
    func updateQuietHours(_ update: HeraldQuietUpdate) async throws -> HeraldQuietReply
    /// `POST /v1/dismissAll {app, group}`: every banner of `app` sent with this `group` (DESIGN section 9).
    func dismissGroup(app: String, group: String) async throws
    /// `POST /v1/designer/snapshot`: the Designer window's content drawn offscreen at `width` x `height` as PNG (test hook;
    /// no window is created or shown).
    func designerSnapshot(app: String?, template: String?, select: String?, width: Int, height: Int) async throws -> Data
    /// `POST /v1/rive/check`: loads a `rive` component in a window-less host view and reports what it found (test hook).
    func riveCheck(_ request: RiveCheckRequest) async throws -> RiveCheckReply
    /// `GET /v1/stacks?app=`: the stacks that are up (DESIGN section 9).
    func stacks(app: String?) async throws -> [HeraldStackInfo]
    /// `POST /v1/stacks/expand {app, group, expanded}`: open or close a stack in place.
    func expandStack(app: String, group: String, expanded: Bool) async throws
    /// `GET/PUT /v1/settings/stacking`: the global default stacking level (the bell menu's choice).
    func stackingLevel() async throws -> StackingLevel
    func setStackingLevel(_ level: StackingLevel) async throws -> StackingLevel
    /// The routes added for MCP/API parity with the editor and Settings (docs/reference/parity.md). nil: not supported.
    var parity: ParityService? { get }
}

/// Which template a preview draws: one stored for the app (or a `builtin.*` one) by name, or one sent inline.
/// `nil` in `PreviewSpec.template` means the app's default (its manifest's `defaultTemplate`, else
/// `builtin.imageLeft`).
public enum PreviewTemplateChoice: Sendable, Equatable {
    case named(String)
    case inline(HeraldTemplate)
}

public enum PreviewAppearance: String, Sendable, Equatable, CaseIterable {
    case light, dark
}

/// A decoded, validated `/v1/preview` request.
public struct PreviewSpec: Sendable, Equatable {
    public static let scaleRange: ClosedRange<Double> = 1...3
    public static let defaultScale: Double = 2

    public var template: PreviewTemplateChoice?
    public var app: String
    /// The data to draw: nil means the manifest's sample values; otherwise a notification whose top-level
    /// keys and `metadata` are the fields (as for `/v1/notify`).
    public var data: HeraldNotification?
    public var appearance: PreviewAppearance
    public var scale: Double
    /// An inline confirmation to draw on the banner, replacing its actions row (DESIGN 8), so a pending
    /// "Run this command?" can be checked without driving the UI. nil draws the banner as usual.
    public var confirmation: BannerConfirmation?
    /// Draws the inline reply field in place of the actions row (a `reply` action pressed), with `replySample` typed in it.
    public var replying: Bool
    public var replySample: String
    /// Draws the banner as the top card of a stack of this many notifications (DESIGN section 9): the stacked-card
    /// edges, the count badge and `{stack.count}`. 1 draws the banner as usual.
    public var stackCount: Int
    public static let stackCountRange: ClosedRange<Int> = 1...99
    /// With `stackCount` above 1: draw the stack open, as the list of its banners with Collapse and Dismiss all.
    public var stackExpanded: Bool

    public init(template: PreviewTemplateChoice? = nil, app: String, data: HeraldNotification? = nil,
                appearance: PreviewAppearance = .light, scale: Double = PreviewSpec.defaultScale,
                confirmation: BannerConfirmation? = nil, stackCount: Int = 1, stackExpanded: Bool = false,
                replying: Bool = false, replySample: String = "") {
        self.replying = replying; self.replySample = replySample
        self.template = template; self.app = app; self.data = data
        self.appearance = appearance; self.scale = scale; self.confirmation = confirmation
        self.stackCount = stackCount; self.stackExpanded = stackExpanded
    }
}

/// Template support is opt-in for a backend, so a conformer that predates it still compiles
/// (a test double, say) and answers 501 instead of pretending to store anything.
public extension HeraldBackend {
    var parity: ParityService? { nil }
    func deleteApp(app: String) async throws { throw BackendError(501, "removing apps is not supported") }
    func templates(app: String?) async throws -> [HeraldTemplate] { throw BackendError(501, "templates are not supported") }
    func putTemplate(_ t: HeraldTemplate) async throws { throw BackendError(501, "templates are not supported") }
    func deleteTemplate(app: String, name: String) async throws { throw BackendError(501, "templates are not supported") }
    func compose() async throws { throw BackendError(501, "compose is not supported") }
    func manifests() async throws -> [HeraldManifest] { throw BackendError(501, "manifests are not supported") }
    func manifest(app: String) async throws -> HeraldManifest? { throw BackendError(501, "manifests are not supported") }
    func putManifest(_ m: HeraldManifest) async throws { throw BackendError(501, "manifests are not supported") }
    func deleteManifest(app: String) async throws { throw BackendError(501, "manifests are not supported") }
    func shortcuts() async throws -> [String] { throw BackendError(501, "shortcuts are not supported") }
    func preview(_ request: PreviewSpec) async throws -> Data { throw BackendError(501, "previews are not supported") }
    func quietHours() async throws -> HeraldQuietReply { throw BackendError(501, "quiet hours are not supported") }
    func updateQuietHours(_ update: HeraldQuietUpdate) async throws -> HeraldQuietReply { throw BackendError(501, "quiet hours are not supported") }
    func dismissGroup(app: String, group: String) async throws { throw BackendError(501, "stacks are not supported") }
    func designerSnapshot(app: String?, template: String?, select: String?, width: Int, height: Int) async throws -> Data { throw BackendError(501, "designer snapshots are not supported") }
    func riveCheck(_ request: RiveCheckRequest) async throws -> RiveCheckReply { throw BackendError(501, "rive checks are not supported") }
    func stacks(app: String?) async throws -> [HeraldStackInfo] { throw BackendError(501, "stacks are not supported") }
    func expandStack(app: String, group: String, expanded: Bool) async throws { throw BackendError(501, "stacks are not supported") }
    func stackingLevel() async throws -> StackingLevel { throw BackendError(501, "stacking is not supported") }
    func setStackingLevel(_ level: StackingLevel) async throws -> StackingLevel { throw BackendError(501, "stacking is not supported") }
}

/// Routes the DESIGN section 2 endpoints. Only /v1/health is unauthenticated.
public final class Router: @unchecked Sendable {
    private let token: String
    private let backend: HeraldBackend
    private let version: String
    private let pid: Int

    public init(token: String, backend: HeraldBackend, version: String, pid: Int = Int(ProcessInfo.processInfo.processIdentifier)) {
        self.token = token; self.backend = backend; self.version = version; self.pid = pid
    }

    public func handle(_ req: HTTPRequest) async -> HTTPResponse {
        if req.path == "/v1/health" {
            guard req.method == "GET" else { return .error(405, "method not allowed") }
            return .json(200, HeraldHealth(ok: true, version: version, pid: pid))
        }
        guard authorized(req) else { return .error(401, "unauthorized") }
        do {
            switch (req.method, req.path) {
            case ("POST", "/v1/register"):
                let r = try decode(HeraldAppRegistration.self, req)
                guard !r.app.isEmpty else { throw BackendError(400, "app is required") }
                try await backend.register(r)
                return .json(200, ["ok": true])
            case ("POST", "/v1/notify"):
                let n = try decodeNotification(req)
                guard !n.app.isEmpty else { throw BackendError(400, "app is required") }
                // A template may supply the title; the backend re-checks once it has resolved it.
                guard !n.title.isEmpty || n.template?.isEmpty == false else { throw BackendError(400, "title is required") }
                if let speak = n.speak { try Self.validateSpeak(speak) }
                let id = try await backend.notify(n)
                return .json(200, NotifyReply(ok: true, id: id))
            case ("GET", "/v1/settings/quiet-hours"):
                return .json(200, try await backend.quietHours())
            case ("PUT", "/v1/settings/quiet-hours"):
                let u = try decode(HeraldQuietUpdate.self, req)
                return .json(200, try await backend.updateQuietHours(u))
            case ("POST", "/v1/speak"):
                let r = try decode(HeraldSpeakRequest.self, req)
                guard !r.app.isEmpty else { throw BackendError(400, "app is required") }
                guard !HeraldSpeak.clean(r.text).isEmpty else { throw BackendError(400, "text is required") }
                try Self.validateSpeak(HeraldSpeak(text: r.text, voice: r.voice, speed: r.speed, lang: r.lang))
                let id = try await backend.notify(r.notification())
                return .json(200, NotifyReply(ok: true, id: id))
            case ("POST", "/v1/dismiss"):
                let b = try decode(DismissBody.self, req)
                guard let app = b.app, !app.isEmpty else { throw BackendError(400, "app is required") }
                guard let id = b.id, !id.isEmpty else { throw BackendError(400, "id is required") }
                try await backend.dismiss(app: app, id: id)
                return .json(200, ["ok": true])
            case ("POST", "/v1/dismissAll"):
                let b = req.body.isEmpty ? DismissBody() : try decode(DismissBody.self, req)
                // With a group: the banners of that app sent with it (a stack), not the whole app.
                if let group = b.group, !group.isEmpty {
                    guard let app = b.app, !app.isEmpty else { throw BackendError(400, "app is required with group") }
                    try await backend.dismissGroup(app: app, group: group)
                } else {
                    try await backend.dismissAll(app: b.app)
                }
                return .json(200, ["ok": true])
            case ("GET", "/v1/stacks"):
                let app = req.query["app"].flatMap { $0.isEmpty ? nil : $0 }
                return .json(200, StacksReply(stacks: try await backend.stacks(app: app)))
            case ("GET", "/v1/settings/stacking"):
                return .json(200, StackingReply(level: try await backend.stackingLevel()))
            case ("PUT", "/v1/settings/stacking"):
                let b = try decode(StackingBody.self, req)
                guard let raw = b.level, let level = StackingLevel(rawValue: raw) else {
                    throw BackendError(400, "level must be one of " + StackingLevel.allCases.map(\.rawValue).joined(separator: ", "))
                }
                return .json(200, StackingReply(level: try await backend.setStackingLevel(level)))
            case ("POST", "/v1/stacks/expand"):
                let b = try decode(ExpandBody.self, req)
                guard let app = b.app, !app.isEmpty else { throw BackendError(400, "app is required") }
                // The group of a notification that sent none is its issuer id, so that is the default here too.
                try await backend.expandStack(app: app, group: b.group.flatMap { $0.isEmpty ? nil : $0 } ?? app, expanded: b.expanded ?? true)
                return .json(200, ["ok": true])
            case ("GET", "/v1/designer/snapshot"), ("POST", "/v1/designer/snapshot"):
                var q = req.query
                if req.method == "POST", !req.body.isEmpty,
                   let o = (try? JSONSerialization.jsonObject(with: req.body)) as? [String: Any] {
                    for (k, v) in o { q[k] = "\(v)" }
                }
                let w = q["width"].flatMap(Int.init) ?? 1100, h = q["height"].flatMap(Int.init) ?? 820
                guard (600...4000).contains(w), (400...3000).contains(h) else { throw BackendError(400, "width must be 600-4000 and height 400-3000") }
                return .png(try await backend.designerSnapshot(app: q["app"].flatMap { $0.isEmpty ? nil : $0 }, template: q["template"].flatMap { $0.isEmpty ? nil : $0 }, select: q["select"].flatMap { $0.isEmpty ? nil : $0 }, width: w, height: h))
            case ("POST", "/v1/rive/check"):
                let b = try decode(RiveCheckRequest.self, req)
                guard !b.app.isEmpty else { throw BackendError(400, "app is required") }
                return .json(200, try await backend.riveCheck(b))
            case ("GET", "/v1/history"):
                let limit = req.query["limit"].flatMap(Int.init) ?? 50
                guard limit >= 0 else { throw BackendError(400, "invalid limit") }
                let items = try await backend.history(app: req.query["app"], limit: limit)
                return .json(200, HistoryReply(items: items))
            case ("DELETE", "/v1/history"):
                try await backend.clearHistory(app: req.query["app"])
                return .json(200, ["ok": true])
            case ("GET", "/v1/apps"):
                return .json(200, AppsReply(apps: try await backend.apps()))
            case ("DELETE", _) where req.path.hasPrefix("/v1/apps/") && req.path != "/v1/apps/settings":
                guard let id = String(req.path.dropFirst("/v1/apps/".count)).removingPercentEncoding, !id.isEmpty, !id.contains("/") else {
                    throw BackendError(400, "app id is required: DELETE /v1/apps/{id}")
                }
                try await backend.deleteApp(app: id)
                return .json(200, DeletedAppReply(ok: true, deleted: id))
            case ("GET", "/v1/templates"):
                let app = req.query["app"].flatMap { $0.isEmpty ? nil : $0 }
                // Names that start with "_" are scratch templates (the Designer's "Send test" writes `_designer-test`):
                // they are used by name but never listed, so agents and clients do not mistake them for designs.
                let items = try await backend.templates(app: app).filter { !$0.name.hasPrefix("_") }
                return .json(200, TemplatesReply(items: items))
            case ("PUT", "/v1/templates"):
                let t = try decode(HeraldTemplate.self, req)
                guard !t.app.isEmpty else { throw BackendError(400, "app is required") }
                guard !t.name.isEmpty else { throw BackendError(400, "name is required") }
                // Existing stored names are never checked again; a name written now follows the one shared rule.
                if let problem = HeraldTemplateName.problem(t.name, allowScratch: true) {
                    let stored = try await backend.templates(app: t.app).contains { $0.name == t.name }
                    if !stored { throw BackendError(400, "invalid template name: \(problem)") }
                }
                // A saved template is read and laid out on every delivery for its app, so it is checked on the way in
                // (grid size, cell count, sizes), the same as the MCP server and the Designer do.
                let errors = t.validate().filter(\.isError)
                guard errors.isEmpty else {
                    throw BackendError(400, "invalid template: " + errors.map { issue in
                        (issue.cellId.map { "cell \($0): " } ?? "") + issue.path + ": " + issue.message
                    }.joined(separator: "; "))
                }
                try await backend.putTemplate(t.fittingGrid())
                return .json(200, ["ok": true])
            case ("DELETE", "/v1/templates"):
                guard let app = req.query["app"], !app.isEmpty else { throw BackendError(400, "app is required") }
                guard let name = req.query["name"], !name.isEmpty else { throw BackendError(400, "name is required") }
                try await backend.deleteTemplate(app: app, name: name)
                return .json(200, ["ok": true])
            case ("POST", "/v1/compose"):
                try await backend.compose()
                return .json(200, ["ok": true])
            case ("GET", "/v1/manifests"):
                return .json(200, ManifestsReply(items: try await backend.manifests()))
            case ("GET", "/v1/manifest"):
                guard let app = req.query["app"], !app.isEmpty else { throw BackendError(400, "app is required") }
                guard let m = try await backend.manifest(app: app) else { throw BackendError(404, "manifest not found") }
                return .json(200, m)
            case ("PUT", "/v1/manifest"):
                let m = try decodeManifest(req)
                let problems = m.validationErrors()
                guard problems.isEmpty else { throw BackendError(400, "invalid manifest: " + problems.joined(separator: "; ")) }
                try await backend.putManifest(m)
                return .json(200, ["ok": true])
            case ("DELETE", "/v1/manifest"):
                guard let app = req.query["app"], !app.isEmpty else { throw BackendError(400, "app is required") }
                try await backend.deleteManifest(app: app)
                return .json(200, ["ok": true])
            case ("GET", "/v1/components"):
                return componentsResponse()
            case ("GET", "/v1/shortcuts"):
                return .json(200, ShortcutsReply(items: try await backend.shortcuts()))
            case ("POST", "/v1/preview"):
                return .png(try await backend.preview(try await decodePreview(req)))
            case ("GET", "/v1/preview"):
                return .png(try await backend.preview(try previewRequest(query: req.query)))
            case (_, "/v1/compose"), (_, "/v1/register"), (_, "/v1/notify"), (_, "/v1/speak"), (_, "/v1/settings/quiet-hours"), (_, "/v1/dismiss"), (_, "/v1/dismissAll"), (_, "/v1/stacks"), (_, "/v1/stacks/expand"), (_, "/v1/rive/check"), (_, "/v1/designer/snapshot"), (_, "/v1/settings/stacking"),
                 (_, "/v1/history"), (_, "/v1/apps"), (_, "/v1/templates"),
                 (_, "/v1/manifests"), (_, "/v1/manifest"), (_, "/v1/components"), (_, "/v1/shortcuts"),
                 (_, "/v1/preview"):
                return .error(405, "method not allowed")
            default:
                // The parity routes (settings, per-app settings, assets, bundles, history search, symbols, voice, MCP
                // install, approvals): see ParityService. A backend without it answers 501 for those paths.
                if ParityService.owns(req.path) {
                    guard let parity = backend.parity else { throw BackendError(501, "this route is not supported by this Herald") }
                    return await parity.handle(req)
                }
                return .error(404, "not found")
            }
        } catch let e as BackendError {
            return .error(e.status, e.message)
        } catch {
            return .error(500, "\(error)")
        }
    }

    private struct NotifyReply: Encodable { var ok: Bool; var id: String }

    /// Voice, speed and language are checked here so a bad value is a 400 for the sender, not a silent failure later.
    static func validateSpeak(_ s: HeraldSpeak) throws {
        if let v = s.voice, !HeraldSpeak.isValidVoice(v) { throw BackendError(400, "invalid voice") }
        if let l = s.lang, !HeraldSpeak.isValidLang(l) { throw BackendError(400, "invalid lang") }
        if let sp = s.speed, !HeraldSpeak.speedRange.contains(sp) { throw BackendError(400, "speed must be between 0.5 and 2.0") }
    }
    private struct HistoryReply: Encodable { var items: [HeraldHistoryItem] }
    private struct AppsReply: Encodable { var apps: [HeraldAppRegistration] }
    private struct DeletedAppReply: Encodable { var ok: Bool; var deleted: String }
    private struct TemplatesReply: Encodable { var items: [HeraldTemplate] }
    private struct ManifestsReply: Encodable { var items: [HeraldManifest] }
    private struct ShortcutsReply: Encodable { var items: [String] }
    private struct DismissBody: Decodable { var app: String?; var id: String?; var group: String? }
    private struct StacksReply: Encodable { var stacks: [HeraldStackInfo] }
    private struct ExpandBody: Decodable { var app: String?; var group: String?; var expanded: Bool? }
    private struct StackingBody: Decodable { var level: String? }
    private struct StackingReply: Encodable {
        var level: String
        var levels: [String] = StackingLevel.allCases.map(\.rawValue)
        init(level: StackingLevel) { self.level = level.rawValue }
    }

    private func authorized(_ req: HTTPRequest) -> Bool { BearerAuth.isAuthorized(req, token: token) }

    /// `GET /v1/components`: the schema of the component types and their properties, for agents and the MCP
    /// server. It is static data produced by the client library, so no backend is involved.
    private func componentsResponse() -> HTTPResponse {
        .json(200, ComponentSchema.document())
    }

    /// The top-level keys of a notification payload that `HeraldNotification` itself models. Anything else a
    /// sender puts at the top level is a field of its manifest (DESIGN section 7.1: "fields values are read
    /// from the payload's top-level keys first, then `metadata`") and is carried in `metadata`, where
    /// `TemplateResolver.fields` reads it. Derived from the type, so a property added to it is known at once.
    private static let notificationKeys: Set<String> = Set(
        Mirror(reflecting: HeraldNotification(app: "", title: "")).children.compactMap { $0.label })

    /// `title` is a required String on the wire, but a payload that names a template may leave it
    /// out and let the template provide it. Only that case is patched, so a bare payload with no
    /// title still fails with the usual "missing field: title".
    ///
    /// Top-level keys that are not notification properties (a manifest field such as `subject` or `count`)
    /// are moved into `metadata`; where a key is in both, the top-level one wins. A payload with no such
    /// keys is decoded exactly as it was sent.
    private func decodeNotification(_ req: HTTPRequest) throws -> HeraldNotification {
        guard let obj = (try? JSONSerialization.jsonObject(with: req.body)) as? [String: Any] else {
            return try decode(HeraldNotification.self, req)
        }
        var patched = obj
        var changed = false
        if obj["template"] is String, obj["title"] == nil {
            patched["title"] = ""
            changed = true
        }
        if let flag = obj["speak"] as? Bool, !flag {   // `speak: false` means no speech
            patched["speak"] = nil
            changed = true
        }
        // `actions` is the documented name for the issuer's buttons (DESIGN 7.3); `buttons` still works and wins
        // when a payload sends both. Entries may use the manifest's wire form ({id, label, kind}). A list that is
        // not made of objects is a manifest field that happens to be called `actions` and stays where it is.
        if let list = obj["actions"] as? [[String: Any]] {
            patched["actions"] = nil
            if obj["buttons"] == nil { patched["buttons"] = list.map(Self.buttonObject) }
            changed = true
        }
        let extras = patched.filter { !Self.notificationKeys.contains($0.key) }
        if !extras.isEmpty, obj["metadata"] == nil || obj["metadata"] is [String: Any] || obj["metadata"] is NSNull {
            var metadata = (obj["metadata"] as? [String: Any]) ?? [:]
            for (k, v) in extras { metadata[k] = v }
            patched = patched.filter { Self.notificationKeys.contains($0.key) }
            patched["metadata"] = metadata
            changed = true
        }
        if changed, let data = try? JSONSerialization.data(withJSONObject: patched) {
            return try decode(HeraldNotification.self, body: data)
        }
        return try decode(HeraldNotification.self, req)
    }

    /// One entry of a payload's `actions` as a button object: the manifest's wire form `{id, label, kind: "callback"}`
    /// has no `callback` to read, so a callback action gets an empty one ("call the issuer back").
    private static func buttonObject(_ entry: [String: Any]) -> [String: Any] {
        var o = entry
        if (o["kind"] as? String) == "callback", o["callback"] == nil { o["callback"] = [String: Any]() }
        o["kind"] = nil
        o["id"] = nil
        return o
    }

    // MARK: Preview

    /// `GET /v1/preview?app=&template=&appearance=&scale=`: a quick check with the manifest's sample data.
    private func previewRequest(query: [String: String]) throws -> PreviewSpec {
        guard let app = query["app"], !app.isEmpty else { throw BackendError(400, "app is required") }
        var template: PreviewTemplateChoice?
        if let name = query["template"], !name.isEmpty { template = .named(name) }
        let appearance = try Self.previewAppearance(query["appearance"])
        let scale = try Self.previewScale(query["scale"].map { .string($0) })
        let stackCount = try Self.previewStackCount(query["stackCount"].map { .string($0) })
        let expanded = ["true", "1", "yes"].contains((query["stackExpanded"] ?? "").lowercased())
        return PreviewSpec(template: template, app: app, data: nil, appearance: appearance, scale: scale,
                           stackCount: stackCount, stackExpanded: expanded)
    }

    /// `stackCount` of a preview: a whole number from 1 to 99 (number or text), default 1.
    private static func previewStackCount(_ raw: ScaleInput?) throws -> Int {
        guard let raw else { return 1 }
        let value: Double?
        switch raw {
        case .number(let d): value = d
        case .string(let s): value = Double(s.trimmingCharacters(in: .whitespaces))
        case .invalid: value = nil
        }
        // Range-check as a Double first: `Int(v)` traps for any finite value outside the Int range (1e20).
        guard let v = value, v.isFinite, v == v.rounded(),
              v >= Double(PreviewSpec.stackCountRange.lowerBound), v <= Double(PreviewSpec.stackCountRange.upperBound) else {
            throw BackendError(400, "invalid field: stackCount (a whole number from 1 to 99)")
        }
        return Int(v)
    }

    /// `POST /v1/preview` `{template, app, data, appearance, scale, confirmation}`. `template` is a name or an inline template
    /// object (checked against the grid schema, so an agent gets the offending cell back); `data` is an object of
    /// field values or the string "sample" (the default); `appearance` is light (default) or dark; `scale` 1 to 3
    /// (default 2); `confirmation` (optional) draws a pending inline confirmation (`BannerConfirmation.fromPreview`);
    /// `stackCount` (optional, 1 to 99) draws the banner as the top card of a stack of that many (DESIGN section 9),
    /// `stackExpanded: true` as the open list of them.
    private func decodePreview(_ req: HTTPRequest) async throws -> PreviewSpec {
        guard let obj = (try? JSONSerialization.jsonObject(with: req.body)) as? [String: Any] else {
            throw BackendError(400, req.body.isEmpty ? "a JSON body is required" : "invalid JSON")
        }
        var template: PreviewTemplateChoice?
        switch obj["template"] {
        case nil, is NSNull: break
        case let name as String:
            if !name.isEmpty { template = .named(name) }
        case let dict as [String: Any]:
            guard let bytes = try? JSONSerialization.data(withJSONObject: dict) else { throw BackendError(400, "invalid template") }
            let t: HeraldTemplate
            do { t = try HeraldJSON.decoder().decode(HeraldTemplate.self, from: bytes) }
            catch let e as DecodingError { throw BackendError(400, "invalid template: " + Self.describe(e)) }
            catch { throw BackendError(400, "invalid template") }
            let errors = t.validate().filter(\.isError)
            guard errors.isEmpty else {
                throw BackendError(400, "invalid template: " + errors.map { issue in
                    (issue.cellId.map { "cell \($0): " } ?? "") + issue.path + ": " + issue.message
                }.joined(separator: "; "))
            }
            template = .inline(t)
        default:
            throw BackendError(400, "invalid field: template (a name or a template object)")
        }
        var app = ""
        switch obj["app"] {
        case nil, is NSNull: break
        case let s as String: app = s
        default: throw BackendError(400, "invalid field: app")
        }
        if app.isEmpty, case .inline(let t)? = template { app = t.app }
        guard !app.isEmpty else { throw BackendError(400, "app is required") }

        var data: HeraldNotification?
        switch obj["data"] {
        case nil, is NSNull: break
        case let s as String:
            switch s {
            case "sample": break
            case "last":
                // The Designer's "Last" preview: the most recent notification the app was sent.
                guard let item = try await backend.history(app: app, limit: 1).first else {
                    throw BackendError(400, "no notification has been delivered for \(app) yet; use \"sample\" or an object")
                }
                data = item.notification
            default: throw BackendError(400, "invalid field: data (an object, \"sample\" or \"last\")")
            }
        case let dict as [String: Any]:
            data = try previewNotification(app: app, data: dict)
        default:
            throw BackendError(400, "invalid field: data (an object, or \"sample\")")
        }
        let appearance = try Self.previewAppearance(obj["appearance"])
        let scale = try Self.previewScale(Self.previewScaleValue(obj["scale"]))
        var confirmation: BannerConfirmation?
        switch obj["confirmation"] {
        case nil, is NSNull: break
        case let raw?: confirmation = try BannerConfirmation.fromPreview(raw, defaultName: app)
        }
        let stackCount = try Self.previewStackCount(Self.previewScaleValue(obj["stackCount"]))
        var stackExpanded = false
        switch obj["stackExpanded"] {
        case nil, is NSNull: break
        case let b as Bool: stackExpanded = b
        default: throw BackendError(400, "invalid field: stackExpanded (true or false)")
        }
        var replying = false
        switch obj["replying"] {
        case nil, is NSNull: break
        case let b as Bool: replying = b
        default: throw BackendError(400, "invalid field: replying (true or false)")
        }
        return PreviewSpec(template: template, app: app, data: data, appearance: appearance, scale: scale,
                           confirmation: confirmation, stackCount: stackCount, stackExpanded: stackExpanded,
                           replying: replying, replySample: (obj["replySample"] as? String) ?? "")
    }

    /// The `data` object as a notification, by the same rules as `/v1/notify`: its notification keys are
    /// taken as they are, any other top-level key becomes a field in `metadata`. A missing title is allowed
    /// (the template supplies it or the preview shows none).
    private func previewNotification(app: String, data: [String: Any]) throws -> HeraldNotification {
        var patched = data
        patched["app"] = app
        if patched["title"] == nil { patched["title"] = "" }
        guard let bytes = try? JSONSerialization.data(withJSONObject: patched) else { throw BackendError(400, "invalid field: data") }
        do { return try decodeNotification(HTTPRequest(method: "POST", path: "/v1/notify", body: bytes)) }
        catch let e as BackendError { throw BackendError(e.status, e.message.replacingOccurrences(of: "field: ", with: "field: data.")) }
    }

    private enum ScaleInput { case string(String), number(Double), invalid }

    private static func previewScaleValue(_ raw: Any?) -> ScaleInput? {
        switch raw {
        case nil, is NSNull: return nil
        case let n as NSNumber where CFGetTypeID(n) != CFBooleanGetTypeID(): return .number(n.doubleValue)
        case let s as String: return .string(s)
        default: return .invalid
        }
    }

    private static func previewScale(_ raw: ScaleInput?) throws -> Double {
        guard let raw else { return PreviewSpec.defaultScale }
        let value: Double?
        switch raw {
        case .number(let d): value = d
        case .string(let s): value = Double(s.trimmingCharacters(in: .whitespaces))
        case .invalid: value = nil
        }
        guard let v = value, v.isFinite, PreviewSpec.scaleRange.contains(v) else {
            throw BackendError(400, "invalid field: scale (a number from 1 to 3)")
        }
        return v
    }

    private static func previewAppearance(_ value: Any?) throws -> PreviewAppearance {
        if value == nil || value is NSNull { return .light }
        guard let raw = value as? String else { throw BackendError(400, "invalid field: appearance (light or dark)") }
        if raw.isEmpty { return .light }
        guard let a = PreviewAppearance(rawValue: raw.lowercased()) else {
            throw BackendError(400, "invalid field: appearance (light or dark)")
        }
        return a
    }

    private static func describe(_ e: DecodingError) -> String {
        func path(_ keys: [CodingKey]) -> String {
            var out = ""
            for key in keys {
                if let i = key.intValue { out += "[\(i)]" } else { out += (out.isEmpty ? "" : ".") + key.stringValue }
            }
            return out
        }
        switch e {
        case .keyNotFound(let k, let c): return path(c.codingPath + [k]) + ": missing field"
        case .typeMismatch(_, let c), .valueNotFound(_, let c), .dataCorrupted(let c):
            let p = path(c.codingPath)
            return (p.isEmpty ? "" : p + ": ") + (c.debugDescription.isEmpty ? "wrong type" : c.debugDescription)
        @unknown default: return "invalid JSON"
        }
    }

    /// Like `decode`, but says what is wrong and where: an agent authoring a manifest needs "actions[1].kind:
    /// 'shortcut' actions are authored in templates", not "invalid JSON".
    private func decodeManifest(_ req: HTTPRequest) throws -> HeraldManifest {
        func path(_ keys: [CodingKey]) -> String {
            var out = ""
            for key in keys {
                if let i = key.intValue { out += "[\(i)]" } else { out += (out.isEmpty ? "" : ".") + key.stringValue }
            }
            return out
        }
        func fail(_ keys: [CodingKey], _ why: String) -> BackendError {
            BackendError(400, "invalid manifest: " + (keys.isEmpty ? "" : path(keys) + ": ") + why)
        }
        do { return try HeraldJSON.decoder().decode(HeraldManifest.self, from: req.body) }
        catch let e as DecodingError {
            switch e {
            case .keyNotFound(let k, let c): throw fail(c.codingPath + [k], "missing field")
            case .typeMismatch(_, let c), .valueNotFound(_, let c):
                throw fail(c.codingPath, c.debugDescription.isEmpty ? "wrong type" : c.debugDescription)
            case .dataCorrupted(let c): throw fail(c.codingPath, c.debugDescription)
            @unknown default: throw BackendError(400, "invalid manifest")
            }
        } catch { throw BackendError(400, "invalid JSON") }
    }

    private func decode<T: Decodable>(_ type: T.Type, _ req: HTTPRequest) throws -> T {
        try decode(type, body: req.body)
    }

    private func decode<T: Decodable>(_ type: T.Type, body: Data) throws -> T {
        do { return try HeraldJSON.decoder().decode(T.self, from: body) }
        catch let e as DecodingError {
            switch e {
            case .keyNotFound(let k, _): throw BackendError(400, "missing field: \(k.stringValue)")
            case .typeMismatch(_, let c), .valueNotFound(_, let c):
                throw BackendError(400, "invalid field: \(c.codingPath.map(\.stringValue).joined(separator: "."))")
            case .dataCorrupted(let c) where !c.codingPath.isEmpty:
                // A value the model refused (a grid with 40 million rows, a size that is not a size): say which.
                throw BackendError(400, "invalid field: " + Self.describe(e))
            default: throw BackendError(400, "invalid JSON")
            }
        } catch { throw BackendError(400, "invalid JSON") }
    }
}


/// `POST /v1/rive/check`: a headless way to see whether a `rive` component loads, which state machine and inputs it
/// found, and which input values the notification's fields would write. Nothing is shown or stored.
public struct RiveCheckRequest: Decodable, Sendable {
    public var app: String
    public var component: HeraldRiveComponent
    public var fields: [String: HeraldFieldValue]?
    /// Pointer steps to run in order: `hoverIn`, `hoverOut`, `pressDown`, `pressUp`.
    public var simulate: [String]?
}

public struct RiveCheckReply: Codable, Equatable, Sendable {
    public struct Input: Codable, Equatable, Sendable { public var name: String; public var kind: String
        public init(name: String, kind: String) { self.name = name; self.kind = kind } }
    public struct Machine: Codable, Equatable, Sendable { public var name: String; public var inputs: [Input]
        public init(name: String, inputs: [Input]) { self.name = name; self.inputs = inputs } }
    public struct Artboard: Codable, Equatable, Sendable {
        public var name: String; public var width: Double; public var height: Double
        public var defaultMachine: String?; public var machines: [Machine]; public var animations: [String]
        public init(name: String, width: Double, height: Double, defaultMachine: String?, machines: [Machine], animations: [String]) {
            self.name = name; self.width = width; self.height = height; self.defaultMachine = defaultMachine
            self.machines = machines; self.animations = animations
        }
    }
    /// True when the animation loaded and plays (no placeholder).
    public var loaded: Bool
    /// Why it did not, exactly as the banner's placeholder says.
    public var error: String?
    /// The state machine's inputs by name -> number | bool | trigger.
    public var inputs: [String: String]
    /// The values written to inputs from the fields, as text.
    public var applied: [String: String]
    public var artboards: [Artboard]
    /// Whether the view takes clicks (a click action or a `pressed` binding) or lets them through to the banner body.
    public var takesClicks: Bool
    /// What the simulated pointer steps wrote to inputs.
    public var pointerWrites: [String: String]
    /// The action ids that simulated clicks (a `pressDown` then `pressUp`) ran.
    public var clickedActions: [String]
    public init(loaded: Bool, error: String? = nil, inputs: [String: String] = [:], applied: [String: String] = [:], artboards: [Artboard] = [],
                takesClicks: Bool = false, pointerWrites: [String: String] = [:], clickedActions: [String] = []) {
        self.loaded = loaded; self.error = error; self.inputs = inputs; self.applied = applied; self.artboards = artboards
        self.takesClicks = takesClicks; self.pointerWrites = pointerWrites; self.clickedActions = clickedActions
    }
}
