import Foundation
import ServiceManagement

/// App-wide preferences (UserDefaults) plus launch-at-login.
final class AppSettings: ObservableObject {
    static let shared = AppSettings()
    private let d = UserDefaults.standard

    /// 0 = use the default port (48617).
    @Published var portOverride: Int { didSet { d.set(portOverride, forKey: "portOverride") } }

    /// Global mute for notification sounds. Persisted, so it survives relaunch and login. Changing it posts
    /// `.heraldChanged` from here (not from whoever flipped it) because it has two doors, the menu and the
    /// Settings toggle, and the menu bar icon (bell / bell.slash) has to follow both.
    @Published var muted: Bool {
        didSet {
            guard muted != oldValue else { return }
            d.set(muted, forKey: "muted")
            NotificationCenter.default.post(name: .heraldChanged, object: nil)
        }
    }

    /// Quiet hours (DESIGN section 7.9.1): the schedule, an ad-hoc silence and "Resume now". Stored as JSON; a
    /// development instance (HERALD_SUPPORT_DIR) keeps it in its own suite, away from the installed Herald's.
    @Published var quiet: HeraldQuietHours {
        didSet {
            guard quiet != oldValue else { return }
            if let data = try? HeraldJSON.encoder().encode(quiet) { Self.quietDefaults.set(data, forKey: "quietHours") }
            NotificationCenter.default.post(name: .heraldChanged, object: nil)
        }
    }
    var quietHours: [QuietWindow] {
        get { quiet.windows }
        set { quiet.windows = newValue }
    }
    private static var quietDefaults: UserDefaults {
        if ProcessInfo.processInfo.environment["HERALD_SUPPORT_DIR"]?.isEmpty == false,
           let suite = UserDefaults(suiteName: "com.ivg.herald.voice-dev") { return suite }
        return .standard
    }

    /// HERALD_PORT (a development build running beside the installed Herald) beats the stored override.
    var effectivePort: Int {
        if let p = ProcessInfo.processInfo.environment["HERALD_PORT"].flatMap(Int.init), (1024...65535).contains(p) { return p }
        return portOverride > 0 ? portOverride : HeraldPaths.defaultPort
    }

    private init() {
        portOverride = UserDefaults.standard.integer(forKey: "portOverride")
        muted = UserDefaults.standard.bool(forKey: "muted")
        quiet = Self.quietDefaults.data(forKey: "quietHours")
            .flatMap { try? HeraldJSON.decoder().decode(HeraldQuietHours.self, from: $0) } ?? HeraldQuietHours()
    }

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            objectWillChange.send()
            do {
                if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch { NSLog("Herald: launch at login failed: \(error)") }
        }
    }

    var didAskLaunchAtLogin: Bool {
        get { d.bool(forKey: "didAskLaunchAtLogin") }
        set { d.set(newValue, forKey: "didAskLaunchAtLogin") }
    }
}
