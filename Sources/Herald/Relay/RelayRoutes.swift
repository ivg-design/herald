import Foundation
import HeraldClient

public struct RelayStatusReply: Codable, Equatable, Sendable {
    public var paired: Bool
    public var state: String
    public var online: Bool
    public var relayURL: String
    public var mcpURL: String
    public var deviceId: String?
    public var lastSeenAt: Date?
    public var keys: [RelayKeyInfo]
    public var log: [RelayLogEntry]
}

public struct RelayKeyCreated: Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var client: String
    public var scope: String
    /// Shown once: the relay keeps only a hash.
    public var key: String
    public var mcpURL: String
    public var connectorConfig: String
}

public protocol RelayBackend: Sendable {
    func relayStatus() async -> RelayStatusReply
    func relayPair() async throws -> (code: String, deviceId: String)
    func relayUnpair() async throws
    func relayCreateKey(name: String, client: String) async throws -> RelayKeyCreated
    func relayRevokeKey(id: String) async throws
    func relayUsage() async throws -> RelayUsage
}

/// `/v1/relay/*` on Herald's loopback API, answered ahead of the router like the snooze routes. Same bearer token as the rest.
///
///   GET  /v1/relay/status          pairing, connection, agent keys, the last 20 relay items with their receipt states
///   POST /v1/relay/pair            {} pairs this Mac with the relay (shows nothing; the code is in the reply)
///   POST /v1/relay/unpair          forgets the pairing and revokes every key
///   GET  /v1/relay/keys            the agent keys (never a secret)
///   POST /v1/relay/keys            {name, client?} mints a notify-only key; the reply holds the key once and a connector block
///   DELETE /v1/relay/keys/{id}     revokes a key
///   GET  /v1/relay/usage           what today has cost of the free plan
struct RevokedReply: Encodable { var revoked: Bool; var id: String }
struct KeysReply: Encodable { var keys: [RelayKeyInfo] }
struct PairReply: Encodable { var paired: Bool; var code: String; var deviceId: String }

public enum RelayRoutes {
    public static let prefix = "/v1/relay/"

    public static func handler(token: String, backend: RelayBackend,
                               fallback: @escaping HTTPLoopbackListener.Handler) -> HTTPLoopbackListener.Handler {
        return { req in
            if let r = await handle(req, token: token, backend: backend) { return r }
            return await fallback(req)
        }
    }

    public static func handle(_ req: HTTPRequest, token: String, backend: RelayBackend) async -> HTTPResponse? {
        guard req.path.hasPrefix(prefix) else { return nil }
        guard BearerAuth.isAuthorized(req, token: token) else { return HTTPResponse.error(401, "unauthorized") }
        let sub = String(req.path.dropFirst(prefix.count))
        do {
            switch (req.method, sub) {
            case ("GET", "status"): return HTTPResponse.json(200, await backend.relayStatus())
            case ("POST", "pair"):
                let r = try await backend.relayPair()
                return HTTPResponse.json(200, PairReply(paired: true, code: r.code, deviceId: r.deviceId))
            case ("POST", "unpair"):
                try await backend.relayUnpair()
                return HTTPResponse.json(200, ["unpaired": true])
            case ("GET", "keys"): return HTTPResponse.json(200, KeysReply(keys: await backend.relayStatus().keys))
            case ("POST", "keys"):
                struct Body: Decodable { var name: String?; var client: String? }
                let b = (try? HeraldJSON.decoder().decode(Body.self, from: req.body)) ?? Body()
                guard let name = b.name, !name.isEmpty else { throw BackendError(400, "name is required") }
                return HTTPResponse.json(201, try await backend.relayCreateKey(name: name, client: b.client ?? "other"))
            case ("GET", "usage"): return HTTPResponse.json(200, try await backend.relayUsage())
            default:
                if req.method == "DELETE", sub.hasPrefix("keys/") {
                    let id = String(sub.dropFirst("keys/".count))
                    guard id.range(of: "^[0-9a-f]{8}$", options: .regularExpression) != nil else { throw BackendError(400, "bad key id") }
                    try await backend.relayRevokeKey(id: id)
                    return HTTPResponse.json(200, RevokedReply(revoked: true, id: id))
                }
                return HTTPResponse.error(404, "no such relay route")
            }
        } catch let e as BackendError {
            return HTTPResponse.error(e.status, e.message)
        } catch let e as RelayError {
            switch e {
            case .limited(let m, _): return HTTPResponse.error(429, m)
            case .notPaired: return HTTPResponse.error(409, "not paired with a relay: pair first (POST /v1/relay/pair)")
            case .http(let c, let m): return HTTPResponse.error(c == 401 ? 502 : c, m)
            case .transport(let m): return HTTPResponse.error(502, "relay unreachable: \(m)")
            }
        } catch {
            return HTTPResponse.error(500, "\(error)")
        }
    }
}
