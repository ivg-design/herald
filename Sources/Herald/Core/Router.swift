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
                let id = try await backend.notify(n)
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
                return .json(200, TemplatesReply(items: try await backend.templates(app: app)))
            case ("PUT", "/v1/templates"):
                let t = try decode(HeraldTemplate.self, req)
                guard !t.app.isEmpty else { throw BackendError(400, "app is required") }
                guard !t.name.isEmpty else { throw BackendError(400, "name is required") }
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
            case (_, "/v1/compose"), (_, "/v1/register"), (_, "/v1/notify"), (_, "/v1/dismiss"), (_, "/v1/dismissAll"),
                 (_, "/v1/history"), (_, "/v1/apps"), (_, "/v1/templates"),
                 (_, "/v1/manifests"), (_, "/v1/manifest"), (_, "/v1/components"), (_, "/v1/shortcuts"):
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
        let extras = obj.filter { !Self.notificationKeys.contains($0.key) }
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
            default: throw BackendError(400, "invalid JSON")
            }
        } catch { throw BackendError(400, "invalid JSON") }
    }
}
