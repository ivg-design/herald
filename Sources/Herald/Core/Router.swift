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

    public init(template: PreviewTemplateChoice? = nil, app: String, data: HeraldNotification? = nil,
                appearance: PreviewAppearance = .light, scale: Double = PreviewSpec.defaultScale) {
        self.template = template; self.app = app; self.data = data
        self.appearance = appearance; self.scale = scale
    }
}

/// Template support is opt-in for a backend, so a conformer that predates it still compiles
/// (a test double, say) and answers 501 instead of pretending to store anything.
public extension HeraldBackend {
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
                try await backend.dismissAll(app: b.app)
                return .json(200, ["ok": true])
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
                // A saved template is read and laid out on every delivery for its app, so it is checked on the way in
                // (grid size, cell count, sizes), the same as the MCP server and the Designer do.
                let errors = t.validate().filter(\.isError)
                guard errors.isEmpty else {
                    throw BackendError(400, "invalid template: " + errors.map { issue in
                        (issue.cellId.map { "cell \($0): " } ?? "") + issue.path + ": " + issue.message
                    }.joined(separator: "; "))
                }
                try await backend.putTemplate(t)
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
                return .png(try await backend.preview(try decodePreview(req)))
            case ("GET", "/v1/preview"):
                return .png(try await backend.preview(try previewRequest(query: req.query)))
            case (_, "/v1/compose"), (_, "/v1/register"), (_, "/v1/notify"), (_, "/v1/speak"), (_, "/v1/settings/quiet-hours"), (_, "/v1/dismiss"), (_, "/v1/dismissAll"),
                 (_, "/v1/history"), (_, "/v1/apps"), (_, "/v1/templates"),
                 (_, "/v1/manifests"), (_, "/v1/manifest"), (_, "/v1/components"), (_, "/v1/shortcuts"),
                 (_, "/v1/preview"):
                return .error(405, "method not allowed")
            default:
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
    private struct TemplatesReply: Encodable { var items: [HeraldTemplate] }
    private struct ManifestsReply: Encodable { var items: [HeraldManifest] }
    private struct ShortcutsReply: Encodable { var items: [String] }
    private struct DismissBody: Decodable { var app: String?; var id: String? }

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
        return PreviewSpec(template: template, app: app, data: nil, appearance: appearance, scale: scale)
    }

    /// `POST /v1/preview` `{template, app, data, appearance, scale}`. `template` is a name or an inline template
    /// object (checked against the grid schema, so an agent gets the offending cell back); `data` is an object of
    /// field values or the string "sample" (the default); `appearance` is light (default) or dark; `scale` 1 to 3
    /// (default 2).
    private func decodePreview(_ req: HTTPRequest) throws -> PreviewSpec {
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
            guard s == "sample" else { throw BackendError(400, "invalid field: data (an object, or \"sample\")") }
        case let dict as [String: Any]:
            data = try previewNotification(app: app, data: dict)
        default:
            throw BackendError(400, "invalid field: data (an object, or \"sample\")")
        }
        let appearance = try Self.previewAppearance(obj["appearance"])
        let scale = try Self.previewScale(Self.previewScaleValue(obj["scale"]))
        return PreviewSpec(template: template, app: app, data: data, appearance: appearance, scale: scale)
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
