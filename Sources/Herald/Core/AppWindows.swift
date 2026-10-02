import AppKit

// Window plumbing for the menu-bar app: the Cmd-Tab presence of the user-opened windows (issue #55), the one
// Settings window every Cmd-, goes to (issue #54), and the main menu that carries Cmd-,.

/// While at least one user-opened window (Designer, Quick send, History, Settings, a template editor) is open,
/// Herald is a regular app: it is in the Cmd-Tab switcher with its icon. At zero windows it goes back to an
/// accessory app. Banners never come here: they must not change the activation policy (DESIGN section 8).
/// Observers are keyed by `ObjectIdentifier` and removed by the window's own close, so a window that is shown
/// again never loses its token to a stale one.
@MainActor
final class WindowPresence {
    static let shared = WindowPresence()

    /// Applies a policy; replaced in tests.
    var apply: (NSApplication.ActivationPolicy) -> Void = { policy in
        NSApp.setActivationPolicy(policy)
        if policy == .regular, let icon = WindowPresence.appIcon() { NSApp.applicationIconImage = icon }
    }
    private var observers: [ObjectIdentifier: NSObjectProtocol] = [:]
    var openCount: Int { observers.count }

    static func appIcon() -> NSImage? {
        NSImage(named: "AppIcon") ?? NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)
    }

    /// Call each time the window is shown. Idempotent per window.
    func track(_ window: NSWindow) {
        let id = ObjectIdentifier(window)
        if let old = observers.removeValue(forKey: id) { NotificationCenter.default.removeObserver(old) }
        observers[id] = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.closed(id) }
        }
        apply(.regular)
    }

    private func closed(_ id: ObjectIdentifier) {
        if let token = observers.removeValue(forKey: id) { NotificationCenter.default.removeObserver(token) }
        if observers.isEmpty { apply(.accessory) }
    }
}

/// The one Settings window of the app. Cmd-, from any Herald window, the main menu and the bell menu all end here.
@MainActor
final class SettingsWindowController: NSObject {
    static let shared = SettingsWindowController()
    /// The Settings content, set by the app delegate at launch (the SwiftUI `SettingsView` lives in the app target).
    var makeContent: () -> NSView = { NSView() }
    private var settingsWindow: NSWindow?

    /// The window, created on first use; not shown.
    func window() -> NSWindow {
        if let settingsWindow { return settingsWindow }
        let w = NSWindow(contentRect: NSRect(origin: .zero, size: NSSize(width: 640, height: 460)),
                         styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        w.title = "Herald Settings"
        w.isReleasedWhenClosed = false
        w.tabbingMode = .disallowed
        w.contentView = makeContent()
        w.setFrameAutosaveName("HeraldSettings")
        w.center()
        settingsWindow = w
        return w
    }

    /// Brings Settings forward, or opens it.
    @objc func showSettings() {
        let w = window()
        WindowPresence.shared.track(w)
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }
}

/// The app's main menu: it is what answers Cmd-, in every window, plus the standard Edit and Window items the
/// SwiftUI App scene used to provide.
@MainActor
enum HeraldMainMenu {
    static func make() -> NSMenu {
        let main = NSMenu()
        func add(_ title: String, _ build: (NSMenu) -> Void) {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            let sub = NSMenu(title: title)
            build(sub)
            item.submenu = sub
            main.addItem(item)
        }
        add("Herald") { m in
            m.addItem(NSMenuItem(title: "About Herald", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: ""))
            m.addItem(.separator())
            let settings = NSMenuItem(title: "Settings\u{2026}", action: #selector(SettingsWindowController.showSettings), keyEquivalent: ",")
            settings.target = SettingsWindowController.shared
            m.addItem(settings)
            m.addItem(.separator())
            m.addItem(NSMenuItem(title: "Hide Herald", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h"))
            let others = NSMenuItem(title: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
            others.keyEquivalentModifierMask = [.command, .option]
            m.addItem(others)
            m.addItem(NSMenuItem(title: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: ""))
            m.addItem(.separator())
            m.addItem(NSMenuItem(title: "Quit Herald", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        }
        add("Edit") { m in
            m.addItem(NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z"))
            let redo = NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
            redo.keyEquivalentModifierMask = [.command, .shift]
            m.addItem(redo)
            m.addItem(.separator())
            m.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
            m.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
            m.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
            m.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        }
        add("Window") { m in
            m.addItem(NSMenuItem(title: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m"))
            m.addItem(NSMenuItem(title: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: ""))
            m.addItem(NSMenuItem(title: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        }
        return main
    }
}
