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
    /// The setup state machine (token-needed ... online), present when Herald serves the setup routes.
    public var setup: RelaySetupStatus?
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

/// Connectors approved through OAuth (they are `oauth` agent keys) and requests still waiting for a decision. The 6-digit
/// codes are never returned here: they are for the person at the Mac.
public struct RelayConnectorsReply: Codable, Equatable, Sendable {
    public struct Pending: Codable, Equatable, Sendable {
        public var id: String
        public var clientName: String
        public var redirectHost: String?
        public var expiresAt: String?
        /// The device flow's code the agent printed (not the approval code), so a local agent can tell the user which request is which.
        public var userCode: String?
        public init(id: String, clientName: String, redirectHost: String? = nil, expiresAt: String? = nil, userCode: String? = nil) {
            self.id = id; self.clientName = clientName; self.redirectHost = redirectHost; self.expiresAt = expiresAt; self.userCode = userCode
        }
    }
    public var connectors: [RelayKeyInfo]
    public var pending: [Pending]

    public init(connectors: [RelayKeyInfo] = [], pending: [Pending] = []) { self.connectors = connectors; self.pending = pending }
}

public protocol RelayBackend: Sendable {
    func relayConnectors() async -> RelayConnectorsReply
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
///   GET  /v1/relay/connectors      connectors approved through OAuth (kind oauth) and requests waiting for approval (no codes)
struct RevokedReply: Encodable { var revoked: Bool; var id: String }
struct KeysReply: Encodable { var keys: [RelayKeyInfo] }
struct PairReply: Encodable { var paired: Bool; var code: String; var deviceId: String }

///   GET  /v1/relay/setup           the setup state machine: token-needed / ready / deploying / connecting / online / offline / error
///   GET  /v1/relay/token-url       the pre-filled Cloudflare token page and the permissions to give it
///   POST /v1/relay/token           {token} stores the API token in the Keychain (never read back)
///   POST /v1/relay/deploy          deploys or upgrades the Worker in the user's Cloudflare account, pairs; returns the step log
///   GET|PUT /v1/relay/settings     every Advanced field; a change to a Worker value redeploys
///   GET  /v1/relay/zones           the Cloudflare zones the token can see (for the custom domain; needs Zone: Read)
///   POST /v1/relay/delete          {confirm: true} deletes the Worker (and every mailbox) from Cloudflare
///   POST /v1/relay/test            health, then a notification through the relay and its receipt
///   GET  /v1/relay/instructions?client=chatgpt|claude|codex   the exact text to give that agent
public enum RelayRoutes {
    public static let prefix = "/v1/relay/"

    public static func handler(token: String, backend: RelayBackend, setup: RelaySetupBackend? = nil,
                               fallback: @escaping HTTPLoopbackListener.Handler) -> HTTPLoopbackListener.Handler {
        return { req in
            if let r = await handle(req, token: token, backend: backend, setup: setup) { return r }
            return await fallback(req)
        }
    }

    public static func handle(_ req: HTTPRequest, token: String, backend: RelayBackend, setup: RelaySetupBackend? = nil) async -> HTTPResponse? {
        guard req.path.hasPrefix(prefix) else { return nil }
        guard BearerAuth.isAuthorized(req, token: token) else { return HTTPResponse.error(401, "unauthorized") }
        let sub = String(req.path.dropFirst(prefix.count))
        do {
            if let setup, let r = try await handleSetup(req, sub: sub, setup: setup) { return r }
            switch (req.method, sub) {
            case ("GET", "status"):
                var st = await backend.relayStatus()
                st.setup = await setup?.setupStatus()
                return HTTPResponse.json(200, st)
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
            case ("GET", "connectors"): return HTTPResponse.json(200, await backend.relayConnectors())
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

extension RelayRoutes {
    static func handleSetup(_ req: HTTPRequest, sub: String, setup: RelaySetupBackend) async throws -> HTTPResponse? {
        switch (req.method, sub) {
        case ("GET", "setup"): return HTTPResponse.json(200, await setup.setupStatus())
        case ("GET", "token-url"): return HTTPResponse.json(200, RelayTokenLink.make())
        case ("POST", "token"):
            struct Body: Decodable { var token: String? }
            let b = (try? HeraldJSON.decoder().decode(Body.self, from: req.body)) ?? Body()
            guard let t = b.token?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { throw BackendError(400, "token is required") }
            try await setup.setCloudflareToken(t)
            return HTTPResponse.json(200, ["stored": true])
        case ("POST", "deploy"): return HTTPResponse.json(200, try await setup.deployRelay())
        case ("GET", "settings"): return HTTPResponse.json(200, await setup.relaySettings())
        case ("PUT", "settings"):
            guard case .object(let o)? = try? HeraldJSON.decoder().decode(JSONValue.self, from: req.body) else { throw BackendError(400, "body must be a JSON object of settings") }
            return HTTPResponse.json(200, try await setup.updateRelaySettings(o))
        case ("GET", "zones"): return HTTPResponse.json(200, try await setup.relayZones())
        case ("POST", "delete"):
            struct Body: Decodable { var confirm: Bool? }
            guard ((try? HeraldJSON.decoder().decode(Body.self, from: req.body)) ?? Body()).confirm == true else {
                throw BackendError(400, "this deletes the relay and every mailbox from Cloudflare: send {\"confirm\": true}")
            }
            return HTTPResponse.json(200, try await setup.deleteRelay())
        case ("POST", "test"): return HTTPResponse.json(200, try await setup.testRelay())
        case ("GET", "instructions"):
            let client = req.query["client"] ?? ""
            return HTTPResponse.json(200, ["client": client, "text": try await setup.relayInstructions(client: client)])
        default: return nil
        }
    }
}
