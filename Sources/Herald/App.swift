import SwiftUI
import AppKit

@main
struct HeraldApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    var body: some Scene {
        Settings { EmptyView() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var historyWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private let controller = AppController.shared

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.imagePosition = .imageLeading
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        refreshStatusItem()
        NotificationCenter.default.addObserver(forName: .heraldChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshStatusItem() }
        }

        controller.openComposer = { [weak self] in self?.openComposer() }
        controller.openHistory = { [weak self] in self?.openHistory() }
        controller.start()
        askLaunchAtLoginIfNeeded()
    }

    func applicationWillTerminate(_ notification: Notification) { controller.stop() }

    private func refreshStatusItem() {
        guard let button = statusItem.button else { return }
        let name = controller.muted ? "bell.slash" : "bell"
        let img = NSImage(systemSymbolName: name, accessibilityDescription: "Herald")
        img?.isTemplate = true
        button.image = img
        let n = controller.unreadCount
        button.title = n > 0 ? " \(n)" : ""
    }

    private func askLaunchAtLoginIfNeeded() {
        let s = AppSettings.shared
        guard !s.didAskLaunchAtLogin, Bundle.main.bundleURL.path.hasPrefix("/Applications/") else { return }
        s.didAskLaunchAtLogin = true
        let alert = NSAlert()
        alert.messageText = "Launch Herald at login?"
        alert.informativeText = "Herald needs to be running to show notifications from your other apps."
        alert.addButton(withTitle: "Launch at Login")
        alert.addButton(withTitle: "Not Now")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn { s.launchAtLogin = true }
    }

    // MARK: Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let n = controller.unreadCount
        let header = NSMenuItem(title: n > 0 ? "\(n) unread" : "No unread notifications", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())
        menu.addItem(item("Compose\u{2026}", #selector(openComposer), "n"))
        menu.addItem(item("Design Template\u{2026}", #selector(openDesigner), "d"))
        menu.addItem(item("History\u{2026}", #selector(openHistory), "h"))
        let mute = item("Mute Sounds", #selector(toggleMute), "m")
        mute.state = controller.muted ? .on : .off
        menu.addItem(mute)
        // Quiet hours (DESIGN section 7.9.1)
        let quiet = QuietHoursCoordinator.shared.status()
        if quiet.active, let until = quiet.until {
            let t = until.formatted(date: .omitted, time: .shortened)
            let label = menu.addItem(withTitle: "Quiet until \(t)", action: nil, keyEquivalent: "")
            label.isEnabled = false
            menu.addItem(item("Resume Now", #selector(resumeQuiet), ""))
        } else {
            menu.addItem(item("Quiet for 1 Hour", #selector(quietOneHour), ""))
        }
        menu.addItem(stackingItem())
        menu.addItem(item("Dismiss All", #selector(dismissAll), ""))
        menu.addItem(.separator())
        menu.addItem(item("Settings\u{2026}", #selector(openSettings), ","))
        menu.addItem(item("Quit Herald", #selector(quit), "q"))
    }

    private func item(_ title: String, _ action: Selector, _ key: String) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
        i.target = self
        return i
    }

    /// "Stack Notifications": the quick switch for how banners fold together (DESIGN section 9). It sets the global
    /// default; an issuer's own choice in Settings > Apps still wins.
    private func stackingItem() -> NSMenuItem {
        let parent = NSMenuItem(title: "Stack Notifications", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        for level in StackingLevel.allCases {
            let i = NSMenuItem(title: level.title, action: #selector(setStacking(_:)), keyEquivalent: "")
            i.target = self
            i.representedObject = level.rawValue
            i.state = controller.settings.stacking == level ? .on : .off
            i.toolTip = level.detail
            sub.addItem(i)
        }
        parent.submenu = sub
        return parent
    }

    @objc private func setStacking(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let level = StackingLevel(rawValue: raw) { controller.settings.stacking = level }
    }

    @objc private func toggleMute() { controller.muted.toggle() }
    @objc private func quietOneHour() { QuietHoursCoordinator.shared.quietFor(minutes: 60) }
    @objc private func resumeQuiet() { QuietHoursCoordinator.shared.resumeNow() }
    @objc private func dismissAll() { controller.dismissAll(app: nil) }
    @objc private func quit() { NSApp.terminate(nil) }

    /// "Compose..." (and `herald compose`): the Designer in quick-send mode (issue #31).
    @objc func openComposer() {
        DesignerWindow.show(controller: controller, quickSend: true)
    }

    @objc func openDesigner() {
        DesignerWindow.show(controller: controller)
    }

    @objc func openHistory() {
        historyWindow = present(historyWindow, title: "Herald History", size: NSSize(width: 820, height: 560),
                                content: HistoryView(controller: controller))
    }

    @objc func openSettings() {
        settingsWindow = present(settingsWindow, title: "Herald Settings", size: NSSize(width: 640, height: 460),
                                 content: SettingsView(controller: controller))
    }

    private func present<V: View>(_ existing: NSWindow?, title: String, size: NSSize, content: V) -> NSWindow {
        let w: NSWindow
        if let existing { w = existing } else {
            w = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                         styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
            w.title = title
            w.isReleasedWhenClosed = false
            w.tabbingMode = .disallowed   // with "prefer tabs: always" macOS would merge History/Composer/Settings into one tabbed window
            w.contentView = NSHostingView(rootView: content)
            w.center()
        }
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
        return w
    }
}
