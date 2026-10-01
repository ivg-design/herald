import Foundation

public struct AppRecord: Codable, Equatable, Sendable {
    public var registration: HeraldAppRegistration
    /// The user confirmed in Settings that this app may run `command` buttons.
    public var commandsConfirmed: Bool = false
    /// The one non-loopback host the user agreed callbacks may be sent to (lower case, no port). Callbacks to
    /// a loopback address need no approval; to anything else they go only to this host.
    public var callbackHostApproved: String?

    public init(registration: HeraldAppRegistration, commandsConfirmed: Bool = false, callbackHostApproved: String? = nil) {
        self.registration = registration; self.commandsConfirmed = commandsConfirmed
        self.callbackHostApproved = callbackHostApproved
    }

    /// The host callbacks for this app would go to when no button names its own URL.
    public var registeredCallbackHost: String? {
        registration.callbackURL.flatMap { URL(string: $0) }.flatMap { CallbackDelivery.normalizedHost(of: $0) }
    }

    public var displayName: String { registration.appName ?? registration.app }
    public var commandsAllowed: Bool { (registration.allowCommands ?? false) && commandsConfirmed }
}

public struct EffectiveSettings: Equatable, Sendable {
    public var sound: String
    public var persistent: Bool
    /// nil = no auto-dismiss
    public var timeout: Double?
    public var corner: HeraldCorner

    public static let fallbackSound = "Glass"
    public static let defaultTransientTimeout = 8.0

    /// Resolves per-notification values over per-app defaults over built-ins.
    /// A timeout > 0 always auto-dismisses; `persistent: false` without a timeout uses 8 s.
    public static func resolve(_ n: HeraldNotification, _ record: AppRecord?) -> EffectiveSettings {
        let d = record?.registration.defaults
        let rawSound = n.sound ?? "default"
        let sound = rawSound == "default" ? (d?.sound ?? fallbackSound) : rawSound
        let persistent = n.persistent ?? d?.persistent ?? true
        let t = n.timeout ?? d?.timeout ?? 0
        let timeout: Double? = t > 0 ? t : (persistent ? nil : defaultTransientTimeout)
        return EffectiveSettings(sound: sound == "default" ? fallbackSound : sound,
                                 persistent: timeout == nil, timeout: timeout,
                                 corner: d?.corner ?? .topRight)
    }
}

public final class AppRegistry: @unchecked Sendable {
    /// Apps Herald keeps records for. Any caller with the token can name an app, so the number is bounded.
    public static let maxApps = 200

    private let file: URL
    private let lock = NSLock()
    private var records: [String: AppRecord]

    public init(file: URL) {
        self.file = file
        if let data = try? Data(contentsOf: file),
           let r = try? HeraldJSON.decoder().decode([String: AppRecord].self, from: data) { records = r } else { records = [:] }
    }

    public func record(for app: String) -> AppRecord? {
        lock.lock(); defer { lock.unlock() }
        return records[app]
    }

    public func all() -> [AppRecord] {
        lock.lock(); defer { lock.unlock() }
        return records.values.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    /// False when `app` is new and the registry is full.
    public func hasRoom(for app: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return records[app] != nil || records.count < Self.maxApps
    }

    /// Creates an implicit record for an unknown app id.
    @discardableResult
    public func ensure(_ app: String) -> AppRecord {
        lock.lock(); defer { lock.unlock() }
        if let r = records[app] { return r }
        let r = AppRecord(registration: HeraldAppRegistration(app: app))
        records[app] = r
        persist()
        return r
    }

    /// Merges a registration: non-nil fields overwrite, defaults merge field-wise.
    @discardableResult
    public func register(_ reg: HeraldAppRegistration) -> AppRecord {
        lock.lock(); defer { lock.unlock() }
        var rec = records[reg.app] ?? AppRecord(registration: HeraldAppRegistration(app: reg.app))
        var m = rec.registration
        if let v = reg.appName { m.appName = v }
        if let v = reg.icon { m.icon = v }
        if let v = reg.bundleId { m.bundleId = v }
        if let v = reg.callbackURL { m.callbackURL = v }
        if let v = reg.allowCommands { m.allowCommands = v }
        if let d = reg.defaults {
            var cur = m.defaults ?? HeraldAppDefaults()
            if let v = d.sound { cur.sound = v }
            if let v = d.persistent { cur.persistent = v }
            if let v = d.timeout { cur.timeout = v }
            if let v = d.corner { cur.corner = v }
            m.defaults = cur
        }
        rec.registration = m
        if m.allowCommands != true { rec.commandsConfirmed = false }
        records[reg.app] = rec
        persist()
        return rec
    }

    public func update(_ app: String, _ mutate: (inout AppRecord) -> Void) {
        lock.lock(); defer { lock.unlock() }
        var rec = records[app] ?? AppRecord(registration: HeraldAppRegistration(app: app))
        mutate(&rec)
        records[app] = rec
        persist()
    }

    private func persist() {
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? HeraldJSON.encoder().encode(records) { try? data.write(to: file, options: .atomic) }
    }
}
