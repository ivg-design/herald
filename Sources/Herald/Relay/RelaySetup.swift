import Foundation
import HeraldClient

// The relay setup surface: what Settings > Cloud does with the Cloudflare deploy, as plain types so the local HTTP API
// (`/v1/relay/*`) and the MCP tools reach exactly the same things as the screen. Nothing here reads the API token back.

public struct RelayTokenLink: Codable, Equatable, Sendable {
    public struct Permission: Codable, Equatable, Sendable { public var key: String; public var type: String; public var title: String; public var why: String }
    /// Cloudflare's token page, pre-filled with the permissions below and the name "Herald relay".
    public var url: String
    public var signUpURL: String
    public var permissions: [Permission]
    public var steps: [String]

    public static func make() -> RelayTokenLink {
        RelayTokenLink(
            url: CloudflareLinks.prefilledTokenURL().absoluteString, signUpURL: CloudflareLinks.signUp.absoluteString,
            permissions: CloudflareLinks.tokenPermissions.map { .init(key: $0.key, type: $0.type, title: $0.title, why: $0.why) },
            steps: [
                "Open the link (a free Cloudflare account is enough; sign up first if you have none).",
                "Cloudflare shows the token page with the three permissions already filled in and the name \"Herald relay\". Press Continue to summary, then Create Token.",
                "Copy the token it shows once, and give it to Herald (Settings > Cloud > Enable relay, or relay_set_cloudflare_token).",
            ])
    }
}

public struct RelayStepReport: Codable, Equatable, Sendable {
    public var step: String
    public var title: String
    public var phase: String   // started | done | failed
    public var detail: String
    public init(_ e: DeployEvent) { step = e.step.rawValue; title = e.step.title; phase = "\(e.phase)"; detail = e.detail }
}

public struct RelaySetupStatus: Codable, Equatable, Sendable {
    /// token-needed (no relay, no token), ready (no relay, token stored), deploying, connecting (paired, not connected yet),
    /// online, offline (paired, connection down), error (the last deploy or pairing failed; see `message`).
    public var state: String
    public var hasToken: Bool
    public var paired: Bool
    public var online: Bool
    public var relayURL: String
    public var mcpURL: String
    public var bundledVersion: String
    public var deployedVersion: String?
    public var updateAvailable: Bool
    public var message: String?
    public var steps: [RelayStepReport]
    public var usage: RelayUsage?
}

public struct RelaySettingsReply: Codable, Equatable, Sendable {
    public var settings: RelayCloudConfig
    public var pairingSecretSet: Bool
    public var errors: [String: String]
    public var redeployed: Bool
    public var steps: [RelayStepReport]
}

public struct RelayDeployReply: Codable, Equatable, Sendable {
    public var deployed: Bool
    public var upgraded: Bool
    public var relayURL: String
    public var paired: Bool
    public var online: Bool
    public var steps: [RelayStepReport]
}

public struct RelayDeleteReply: Codable, Equatable, Sendable {
    public var deleted: Bool
    public var note: String?
}

public struct RelayTestReply: Codable, Equatable, Sendable {
    public var healthy: Bool
    public var paired: Bool
    public var online: Bool
    public var roundTrip: Bool
    public var receipt: String?
    public var detail: String
}

public protocol RelaySetupBackend: Sendable {
    func setupStatus() async -> RelaySetupStatus
    func setCloudflareToken(_ token: String) async throws
    func deployRelay() async throws -> RelayDeployReply
    func relaySettings() async -> RelaySettingsReply
    func updateRelaySettings(_ patch: [String: JSONValue]) async throws -> RelaySettingsReply
    func deleteRelay() async throws -> RelayDeleteReply
    func testRelay() async throws -> RelayTestReply
    func relayInstructions(client: String) async throws -> String
}

extension RelayCloudConfig {
    /// Applies the Advanced fields named in `patch` (the field names of this struct). Unknown names and wrong types are errors.
    public func applying(_ patch: [String: JSONValue]) throws -> RelayCloudConfig {
        var c = self
        func str(_ v: JSONValue, _ k: String) throws -> String {
            guard case .string(let s) = v else { throw BackendError(400, "\(k) must be a string") }
            return s.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        func int(_ v: JSONValue, _ k: String) throws -> Int {
            guard case .number(let n) = v, n == n.rounded() else { throw BackendError(400, "\(k) must be a whole number") }
            return Int(n)
        }
        for (k, v) in patch {
            switch k {
            case "accountId": c.accountId = try str(v, k)
            case "workerName": c.workerName = try str(v, k)
            case "subdomain": c.subdomain = try str(v, k)
            case "bucket": c.bucket = try str(v, k)
            case "deviceName": c.deviceName = try str(v, k)
            case "audioRetentionDays": c.audioRetentionDays = try int(v, k)
            case "queueTTLHours": c.queueTTLHours = try int(v, k)
            case "notificationsPerDay": c.notificationsPerDay = try int(v, k)
            case "maxQueue": c.maxQueue = try int(v, k)
            case "bodyLimitBytes": c.bodyLimitBytes = try int(v, k)
            case "ratePerKey": c.ratePerKey = try int(v, k)
            case "maxDevices": c.maxDevices = try int(v, k)
            case "pingSeconds": c.pingSeconds = try int(v, k)
            default: throw BackendError(400, "unknown setting \(k)")
            }
        }
        return c
    }
}
