import XCTest
import AppKit
@testable import HeraldCore

/// One Settings window for the whole app (issue #54) and Herald in the Cmd-Tab switcher while a window is open
/// (issue #55). Windows here are never shown or ordered front.
@MainActor
final class AppWindowTests: XCTestCase {
    private func menuItems(_ menu: NSMenu) -> [NSMenuItem] {
        menu.items.flatMap { [$0] + ($0.submenu.map(menuItems) ?? []) }
    }
    private func srcRoot() -> URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Sources/Herald")
    }

    // MARK: Settings (issue #54)

    func testCommandCommaResolvesToTheSharedSettingsController() {
        let commas = menuItems(HeraldMainMenu.make()).filter { $0.keyEquivalent == "," }
        XCTAssertEqual(commas.count, 1, "exactly one Cmd-, item")
        XCTAssertTrue(commas[0].target === SettingsWindowController.shared)
        XCTAssertEqual(commas[0].action, #selector(SettingsWindowController.showSettings))
        XCTAssertEqual(commas[0].keyEquivalentModifierMask, [.command])
    }

    func testThereIsExactlyOneSettingsWindow() {
        let c = SettingsWindowController.shared
        c.makeContent = { NSView() }
        XCTAssertTrue(c.window() === c.window())
        XCTAssertEqual(c.window().title, "Herald Settings")
    }

    func testNoSwiftUISettingsSceneRemains() throws {
        let src = try String(contentsOf: srcRoot().appendingPathComponent("App.swift"), encoding: .utf8)
        XCTAssertFalse(src.contains("Settings {"), "the SwiftUI Settings scene opened a blank window")
        XCTAssertFalse(src.contains(": App {"))
        XCTAssertFalse(src.contains("WindowGroup"))
    }

    // MARK: Cmd-Tab presence (issue #55)

    private func newWindow() -> NSWindow {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100), styleMask: [.titled, .closable], backing: .buffered, defer: true)
        w.isReleasedWhenClosed = false
        return w
    }
    private func close(_ w: NSWindow) { NotificationCenter.default.post(name: NSWindow.willCloseNotification, object: w) }

    func testPolicyFlipsWithTheWindowCount() {
        let p = WindowPresence()
        var policies: [NSApplication.ActivationPolicy] = []
        p.apply = { policies.append($0) }
        let a = newWindow(), b = newWindow()
        p.track(a)
        XCTAssertEqual(policies.last, .regular)
        p.track(b)
        XCTAssertEqual(p.openCount, 2)
        close(a)
        XCTAssertEqual(p.openCount, 1)
        XCTAssertEqual(policies.last, .regular, "one window is still open")
        close(b)
        XCTAssertEqual(p.openCount, 0)
        XCTAssertEqual(policies.last, .accessory)
    }

    func testAReopenedWindowKeepsItsOwnTokenAndLeavesCleanly() {
        let p = WindowPresence()
        var policies: [NSApplication.ActivationPolicy] = []
        p.apply = { policies.append($0) }
        let a = newWindow()
        p.track(a); close(a)
        XCTAssertEqual(policies.last, .accessory)
        p.track(a)   // shown again
        p.track(a)   // and brought forward again: still one window
        XCTAssertEqual(p.openCount, 1)
        close(a)
        XCTAssertEqual(p.openCount, 0)
        XCTAssertEqual(policies.last, .accessory)
        close(a)     // a stray second close changes nothing
        XCTAssertEqual(policies.filter { $0 == .accessory }.count, 2)
    }

    func testNothingTrackedMeansNoPolicyChange() {
        let p = WindowPresence()
        var calls = 0
        p.apply = { _ in calls += 1 }
        XCTAssertEqual(p.openCount, 0)
        XCTAssertEqual(calls, 0)
    }

    /// Banners must never change the policy or activate the app (DESIGN section 8). The banner code is AppKit in
    /// the app target, so this guards it at the source: nothing in Banners/ touches the policy, presence or activation.
    func testBannerCodeNeverTouchesActivationPolicyOrActivates() throws {
        let dir = srcRoot().appendingPathComponent("Banners")
        let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil).filter { $0.pathExtension == "swift" }
        XCTAssertFalse(files.isEmpty)
        for f in files {
            let text = try String(contentsOf: f, encoding: .utf8)
            for line in text.split(separator: "\n") where !line.trimmingCharacters(in: .whitespaces).hasPrefix("//") {
                for bad in ["setActivationPolicy", "WindowPresence", "NSApp.activate(", "applicationIconImage"] {
                    XCTAssertFalse(line.contains(bad), "\(f.lastPathComponent) uses \(bad)")
                }
            }
        }
    }
}
