import Foundation

/// Herald's own identity as a notification issuer: one app, `herald`, named "Herald", with the app icon. Everything Herald says on its
/// own behalf (connector approvals, the relay test) is a `herald` notification; `group` tells them apart ("connectors").
public enum HeraldIdentity {
    public static let app = "herald"
    public static let name = "Herald"
    /// Until 1.10 the connector approvals had an app of their own. They are `herald` notifications with this group now.
    public static let legacyConnectorsApp = "herald.connectors"
    public static let connectorsGroup = "connectors"
    /// The relay test sends through a throw-away key with this name prefix; its notification is shown as a `herald` one and removed again.
    public static let relayTestKeyPrefix = "herald-test-"
    public static let relayTestTitle = "Relay test"

    public static func isRelayTestKey(_ name: String) -> Bool { name.hasPrefix(relayTestKeyPrefix) }

    /// The history item a relay test left behind: a `herald` notification the relay delivered for this notification id.
    public static func isRelayTestItem(_ item: HeraldHistoryItem, notificationId: String) -> Bool {
        guard item.app == app, case .object(let m)? = item.notification.metadata,
              case .string(let nid)? = m["relayNotificationId"] else { return false }
        return nid == notificationId
    }

    /// Where the exported app icon lives, next to the agent icons.
    public static func iconFile(in support: URL) -> URL { AgentIssuer.iconsFolder(in: support).appendingPathComponent("herald.png") }

    /// Registers `herald` with its name and icon. `iconPNG` is written once (when there is none yet, or `refreshIcon`); a registration
    /// the user already named or iconned is left alone.
    @discardableResult
    public static func ensureRegistered(registry: AppRegistry, supportDirectory: URL, iconPNG: Data?, refreshIcon: Bool = false) -> AppRecord {
        let file = iconFile(in: supportDirectory)
        if let iconPNG, refreshIcon || !FileManager.default.fileExists(atPath: file.path) {
            try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? iconPNG.write(to: file, options: .atomic)
        }
        let existing = registry.record(for: app)?.registration
        var reg = HeraldAppRegistration(app: app)
        if existing?.appName == nil { reg.appName = name }
        if existing?.icon == nil, FileManager.default.fileExists(atPath: file.path) { reg.icon = file.path }
        return registry.register(reg)
    }
}
