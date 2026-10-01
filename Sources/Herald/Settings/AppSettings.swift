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

    var effectivePort: Int { portOverride > 0 ? portOverride : HeraldPaths.defaultPort }

    private init() {
        portOverride = UserDefaults.standard.integer(forKey: "portOverride")
        muted = UserDefaults.standard.bool(forKey: "muted")
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
