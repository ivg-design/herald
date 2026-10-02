import Foundation

/// Everything the user can set about the relay Herald deploys to their own Cloudflare account (Settings > Cloud > Advanced).
/// The values that live in the Worker are sent as Worker vars on every deploy; the rest is Herald's own.
/// Secrets (API token, pairing secret, relay secret) are NOT here: they are in the Keychain (`CloudflareSecrets`).
public struct RelayCloudConfig: Codable, Equatable, Sendable {
    public var accountId: String = ""
    public var workerName: String = "herald-relay"
    /// The account's workers.dev subdomain (found or created at deploy time).
    public var subdomain: String = ""
    public var bucket: String = "herald-relay-audio"
    public var audioRetentionDays: Int = 7
    public var queueTTLHours: Int = 24
    public var notificationsPerDay: Int = 500
    public var maxQueue: Int = 100
    public var bodyLimitBytes: Int = 32 * 1024
    public var ratePerKey: Int = 60
    public var maxDevices: Int = 5
    /// How this Mac introduces itself when pairing; empty means the Mac's own name.
    public var deviceName: String = ""
    public var pingSeconds: Int = 300
    /// The bundle hash that was last deployed, and when.
    public var deployedHash: String = ""
    public var deployedAt: Date?

    public init() {}

    public var workerURL: String? {
        guard !subdomain.isEmpty else { return nil }
        return "https://\(workerName).\(subdomain).workers.dev"
    }

    /// Field name -> what is wrong. Empty means the form is valid.
    public func validate() -> [String: String] {
        var e: [String: String] = [:]
        func match(_ s: String, _ p: String) -> Bool { s.range(of: p, options: .regularExpression) != nil }
        if !accountId.isEmpty, !match(accountId, "^[0-9a-f]{32}$") { e["accountId"] = "An account id is 32 hexadecimal characters." }
        if !match(workerName, "^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$") { e["workerName"] = "Use 1 to 63 lowercase letters, digits or hyphens." }
        if !subdomain.isEmpty, !match(subdomain, "^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$") { e["subdomain"] = "Use lowercase letters, digits or hyphens." }
        if !match(bucket, "^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$") { e["bucket"] = "A bucket name is 3 to 63 lowercase letters, digits or hyphens." }
        if !(1...365).contains(audioRetentionDays) { e["audioRetentionDays"] = "Between 1 and 365 days." }
        if !(1...168).contains(queueTTLHours) { e["queueTTLHours"] = "Between 1 and 168 hours." }
        if !(1...100_000).contains(notificationsPerDay) { e["notificationsPerDay"] = "Between 1 and 100000 a day." }
        if !(1...1000).contains(maxQueue) { e["maxQueue"] = "Between 1 and 1000." }
        if !(1024...1_048_576).contains(bodyLimitBytes) { e["bodyLimitBytes"] = "Between 1024 and 1048576 bytes." }
        if !(1...10_000).contains(ratePerKey) { e["ratePerKey"] = "Between 1 and 10000 per 10 minutes." }
        if !(1...1000).contains(maxDevices) { e["maxDevices"] = "Between 1 and 1000." }
        if !(30...3600).contains(pingSeconds) { e["pingSeconds"] = "Between 30 and 3600 seconds." }
        if deviceName.count > 60 { e["deviceName"] = "At most 60 characters." }
        return e
    }

    /// The Worker vars for a deploy. `BUNDLE_HASH` is how a later run knows what is running.
    public func workerVars(bundleHash: String) -> [String: String] {
        [
            "MAX_DEVICES": String(maxDevices),
            "DEVICE_NOTIFICATIONS_PER_DAY": String(notificationsPerDay),
            "DEVICE_QUEUE_MAX": String(maxQueue),
            "QUEUE_TTL_HOURS": String(queueTTLHours),
            "MAX_BODY_BYTES": String(bodyLimitBytes),
            "RATE_LIMIT_PER_KEY": String(ratePerKey),
            "BUNDLE_HASH": bundleHash,
        ]
    }

    /// Changing one of these means the Worker has to be deployed again (the others are Herald's own or R2's).
    public func needsRedeploy(comparedTo old: RelayCloudConfig) -> Bool {
        workerVars(bundleHash: "") != old.workerVars(bundleHash: "") || workerName != old.workerName
            || bucket != old.bucket || audioRetentionDays != old.audioRetentionDays
    }
}

public final class RelayCloudConfigStore: @unchecked Sendable {
    private let lock = NSLock()
    private let file: URL?
    private var config: RelayCloudConfig

    public init(file: URL?) {
        self.file = file
        if let file, let d = try? Data(contentsOf: file), let c = try? HeraldJSONCoding.decoder.decode(RelayCloudConfig.self, from: d) { config = c }
        else { config = RelayCloudConfig() }
    }

    public var value: RelayCloudConfig { lock.lock(); defer { lock.unlock() }; return config }

    public func update(_ change: (inout RelayCloudConfig) -> Void) {
        lock.lock(); change(&config); let snapshot = config; lock.unlock()
        guard let file, let d = try? HeraldJSONCoding.encoder.encode(snapshot) else { return }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? d.write(to: file, options: .atomic)
    }
}
