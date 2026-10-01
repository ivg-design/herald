import Foundation

public enum HeraldError: Error, LocalizedError, Equatable {
    case notRunning
    case unauthorized
    case server(status: Int, message: String)
    case invalidResponse

    public var errorDescription: String? {
        switch self {
        case .notRunning: return "Herald is not running (no token/port file or no answer on the port)."
        case .unauthorized: return "Herald rejected the token."
        case .server(let s, let m): return "Herald returned \(s): \(m)"
        case .invalidResponse: return "Unexpected response from Herald."
        }
    }
}

public struct HeraldHealth: Codable, Equatable, Sendable {
    public var ok: Bool
    public var version: String
    public var pid: Int
    public init(ok: Bool, version: String, pid: Int) { self.ok = ok; self.version = version; self.pid = pid }
}

/// Client for the Herald loopback API. Reads the token and port from Application Support.
public final class HeraldClient: @unchecked Sendable {
    public static let shared = HeraldClient()

    public let supportDirectory: URL
    private let session: URLSession

    public init(supportDirectory: URL = HeraldPaths.defaultSupportDirectory) {
        self.supportDirectory = supportDirectory
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 5
        cfg.waitsForConnectivity = false
        self.session = URLSession(configuration: cfg)
    }

    public var token: String? { HeraldPaths.readToken(in: supportDirectory) }
    public var port: Int { HeraldPaths.readPort(in: supportDirectory) ?? HeraldPaths.defaultPort }

    /// True when token and port files exist and /v1/health answers (blocking, <= 1 s).
    public var isAvailable: Bool {
        guard token != nil, let url = URL(string: "http://127.0.0.1:\(port)/v1/health") else { return false }
        var req = URLRequest(url: url)
        req.timeoutInterval = 1
        let sem = DispatchSemaphore(value: 0)
        let ok = Flag()
        session.dataTask(with: req) { data, resp, _ in
            if let http = resp as? HTTPURLResponse, http.statusCode == 200,
               let data, (try? HeraldJSON.decoder().decode(HeraldHealth.self, from: data)) != nil { ok.value = true }
            sem.signal()
        }.resume()
        _ = sem.wait(timeout: .now() + 1.5)
        return ok.value
    }
    private final class Flag: @unchecked Sendable { var value = false }

    public func health() async throws -> HeraldHealth {
        try await send("GET", "/v1/health", auth: false)
    }

    /// Returns the notification id.
    @discardableResult
    public func notify(_ n: HeraldNotification) async throws -> String {
        struct R: Decodable { var id: String }
        let r: R = try await send("POST", "/v1/notify", body: n)
        return r.id
    }

    public func register(_ r: HeraldAppRegistration) async throws {
        let _: Ack = try await send("POST", "/v1/register", body: r)
    }

    public func dismiss(app: String, id: String) async throws {
        let _: Ack = try await send("POST", "/v1/dismiss", body: ["app": app, "id": id])
    }

    public func dismissAll(app: String) async throws {
        let _: Ack = try await send("POST", "/v1/dismissAll", body: ["app": app])
    }

    public func history(app: String? = nil, limit: Int = 50) async throws -> [HeraldHistoryItem] {
        struct R: Decodable { var items: [HeraldHistoryItem] }
        var q = [URLQueryItem(name: "limit", value: String(limit))]
        if let app { q.append(URLQueryItem(name: "app", value: app)) }
        let r: R = try await send("GET", "/v1/history", query: q)
        return r.items
    }

    private struct Ack: Decodable { var ok: Bool }
    private struct Empty: Encodable {}

    private func send<T: Decodable, B: Encodable>(_ method: String, _ path: String, query: [URLQueryItem] = [],
                                                  body: B?, auth: Bool = true) async throws -> T {
        var comps = URLComponents()
        comps.scheme = "http"; comps.host = "127.0.0.1"; comps.port = port; comps.path = path
        if !query.isEmpty { comps.queryItems = query }
        guard let url = comps.url else { throw HeraldError.invalidResponse }
        var req = URLRequest(url: url)
        req.httpMethod = method
        if auth {
            guard let token else { throw HeraldError.notRunning }
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            req.httpBody = try HeraldJSON.encoder().encode(body)
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let data: Data, resp: URLResponse
        do { (data, resp) = try await session.data(for: req) } catch { throw HeraldError.notRunning }
        guard let http = resp as? HTTPURLResponse else { throw HeraldError.invalidResponse }
        if http.statusCode == 401 { throw HeraldError.unauthorized }
        guard (200..<300).contains(http.statusCode) else {
            let msg = (try? JSONDecoder().decode([String: String].self, from: data))?["error"] ?? "error"
            throw HeraldError.server(status: http.statusCode, message: msg)
        }
        do { return try HeraldJSON.decoder().decode(T.self, from: data) } catch { throw HeraldError.invalidResponse }
    }

    private func send<T: Decodable>(_ method: String, _ path: String, query: [URLQueryItem] = [],
                                    auth: Bool = true) async throws -> T {
        try await send(method, path, query: query, body: Optional<Empty>.none, auth: auth)
    }
}
