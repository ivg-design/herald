#if DEBUG
import SwiftUI
import AppKit
import HeraldClient

/// Hidden launch mode for the website's screenshots: `HERALD_SCREENSHOTS=<dir> Herald.app/Contents/MacOS/Herald` (Debug builds only).
///
/// It runs on sample data only. Before anything else `prepare()` points the app at a throwaway support folder (history, templates,
/// manifests, apps, token, Keychain item) and a free port, so the installed Herald's data is never read or written. UserDefaults
/// cannot be redirected (one bundle id), so the keys the run touches (window frames, designer panes) are put back when it ends.
/// Each window is opened in turn, captured with `screencapture -l <windowNumber> -o -x` (no shadow, native 2x), closed, and the app quits.
@MainActor
enum ScreenshotMode {
    static var outputDirectory: URL? {
        guard let p = ProcessInfo.processInfo.environment["HERALD_SCREENSHOTS"], !p.isEmpty else { return nil }
        return URL(fileURLWithPath: (p as NSString).expandingTildeInPath, isDirectory: true)
    }
    static var isActive: Bool { outputDirectory != nil }

    private static var defaultsBefore: [String: Any] = [:]
    private static var voiceSuiteExisted = true
    private static let domain = Bundle.main.bundleIdentifier ?? "com.ivg.herald"

    /// First thing in `main()`, before `AppController` exists.
    nonisolated static func prepare() {
        guard ProcessInfo.processInfo.environment["HERALD_SCREENSHOTS"].map({ !$0.isEmpty }) == true else { return }
        let dir = NSTemporaryDirectory() + "herald-screenshots-\(getpid())"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        setenv("HERALD_SUPPORT_DIR", dir, 1)
        setenv("HERALD_PORT", String(49_000 + Int(getpid()) % 900), 1)
    }

    /// From `applicationDidFinishLaunching`, after `controller.start()`.
    static func start(controller: AppController) {
        guard let out = outputDirectory else { return }
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        defaultsBefore = UserDefaults.standard.persistentDomain(forName: domain) ?? [:]
        voiceSuiteExisted = UserDefaults.standard.persistentDomain(forName: "com.ivg.herald.voice-dev") != nil
        NSApp.appearance = NSAppearance(named: .aqua)
        Task { @MainActor in
            await Runner(controller: controller, out: out).run()
            restoreDefaults()
            FileHandle.standardError.write(Data("screenshots: done\n".utf8))
            NSApp.terminate(nil)
        }
    }

    private static func restoreDefaults() {
        let d = UserDefaults.standard
        let now = d.persistentDomain(forName: domain) ?? [:]
        for key in Set(now.keys).union(defaultsBefore.keys) {
            let a = defaultsBefore[key], b = now[key]
            if let a { if b == nil || !(a as AnyObject).isEqual(b) { d.set(a, forKey: key) } } else { d.removeObject(forKey: key) }
        }
        d.synchronize()
        if !voiceSuiteExisted { d.removePersistentDomain(forName: "com.ivg.herald.voice-dev") }
    }

    private static func log(_ s: String) { FileHandle.standardError.write(Data(("screenshots: " + s + "\n").utf8)) }

    @MainActor
    private final class Runner {
        let c: AppController
        let out: URL
        init(controller: AppController, out: URL) { c = controller; self.out = out }

        func pause(_ s: Double) async { try? await Task.sleep(nanoseconds: UInt64(s * 1_000_000_000)) }

        func run() async {
            seed()
            await pause(1.0)
            await designer()
            await settings()
            await history()
            await banners()
        }

        // MARK: Capture

        func capture(_ w: NSWindow, _ name: String, settle: Double = 0.6) async {
            w.orderFrontRegardless()
            await pause(settle)
            let file = out.appendingPathComponent(name + ".png")
            try? FileManager.default.removeItem(at: file)
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            p.arguments = ["-l", String(w.windowNumber), "-o", "-x", file.path]
            await withCheckedContinuation { (k: CheckedContinuation<Void, Never>) in
                p.terminationHandler = { _ in k.resume() }
                do { try p.run() } catch { ScreenshotMode.log("\(name): cannot run screencapture: \(error)"); k.resume() }
            }
            let size = (try? Data(contentsOf: file)).flatMap { NSBitmapImageRep(data: $0) }.map { "\($0.pixelsWide)x\($0.pixelsHigh)" } ?? "MISSING"
            ScreenshotMode.log("\(name): window \(Int(w.frame.width))x\(Int(w.frame.height)) pt -> \(size) px")
        }

        func place(_ w: NSWindow, content: NSSize) {
            w.setContentSize(content)
            w.center()
        }

        // MARK: Sample data

        func seed() {
            _ = try? AgentIssuer.register(AgentIdentity(kind: .claudeCode)!, iconPNG: nil, supportDirectory: c.supportDirectory,
                                          registry: c.registry, manifests: c.manifests, templates: c.templates)
            _ = try? AgentIssuer.register(AgentIdentity(kind: .codex)!, iconPNG: nil, supportDirectory: c.supportDirectory,
                                          registry: c.registry, manifests: c.manifests, templates: c.templates)
            _ = try? AgentIssuer.register(AgentIdentity(cloudKeyName: "dev-box", client: "claude", clientName: "Claude (dev-box)")!, iconPNG: nil,
                                          supportDirectory: c.supportDirectory, registry: c.registry, manifests: c.manifests, templates: c.templates)
            for (app, name) in [("vercel", "Vercel"), ("calendar", "Calendar"), ("web-watcher", "Web Watcher"), ("ci", "GitHub Actions")] {
                c.registry.register(HeraldAppRegistration(app: app, appName: name))
            }
            _ = AutoIcon.applyToIconless(registry: c.registry, supportDirectory: c.supportDirectory)
            AppIcons.invalidate()

            let now = Date()
            func item(_ app: String, _ title: String, _ sub: String?, _ body: String?, _ minutesAgo: Double, buttons: [HeraldButton]? = nil) -> HeraldHistoryItem {
                let id = UUID().uuidString
                let n = HeraldNotification(app: app, id: id, title: title, subtitle: sub, body: body, buttons: buttons)
                return HeraldHistoryItem(id: id, app: app, notification: n, deliveredAt: now.addingTimeInterval(-minutesAgo * 60))
            }
            c.history.upsert(contentsOf: [
                item("vercel", "Deploy finished", "herald-web \u{00B7} production", "Built in 42 s, no warnings.", 3),
                item("agent.claude-code", "Tests pass", "herald", "All 412 tests passed after the banner refactor. Ready for review.", 9),
                item("web-watcher", "Price dropped", "Studio monitor", "Now $289, was $329.", 21),
                item("calendar", "Design review in 10 minutes", "Room 4B", nil, 34),
                item("ci", "Build failed", "herald-relay \u{00B7} main", "Step 'lint' exited with code 1.", 58),
                item("agent.codex", "Refactor done", "relay", "Moved the socket handling into its own module. 3 files changed.", 95),
                item("cloud.dev-box", "Migration finished", nil, "All 14 tables migrated. Want me to open the pull request?", 130),
                item("vercel", "Preview ready", "herald-web \u{00B7} gmail-section", "https://herald-web-git-gmail.vercel.app", 190),
                item("web-watcher", "Page changed", "Release notes", "A new section was added: 'Known issues'.", 260),
                item("ci", "Build passed", "herald \u{00B7} main", "Finished in 3 min 12 s.", 400),
                item("calendar", "Standup", "Starts at 9:30", nil, 1_300),
                item("agent.claude-code", "Needs your input", "herald", "Should the relay keep receipts for 7 or 30 days?", 1_500),
            ])
            c.changed()
            // A sample quiet-hours window for the Settings capture.
            AppSettings.shared.quiet.windows = [QuietWindow(days: ["mon", "tue", "wed", "thu", "fri"], start: "22:30", end: "07:30",
                                                            speech: true, sounds: true, banners: false, speakSummary: true)]
        }

        // MARK: Windows

        func designer() async {
            DesignerWindow.show(controller: c, app: "agent.claude-code", template: AgentIdentity.templateName)
            guard let w = DesignerWindow.debugWindow else { ScreenshotMode.log("designer: no window"); return }
            place(w, content: NSSize(width: 1280, height: 800))
            for (name, appearance) in [("designer-light", NSAppearance.Name.aqua), ("designer-dark", .darkAqua)] {
                NSApp.appearance = NSAppearance(named: appearance)
                await capture(w, name, settle: 1.0)
            }
            NSApp.appearance = NSAppearance(named: .aqua)
            DesignerWindow.debugModel?.showQuickSend(app: "agent.claude-code")
            await capture(w, "quick-send", settle: 1.0)
            DesignerWindow.debugModel?.showDesign()
            await pause(0.4)
            if let m = DesignerWindow.debugModel {
                SymbolBrowserPanel.show(parent: w) {
                    SymbolBrowserHost(designer: m, current: { HeraldSymbol(name: "bell.badge") }, apply: { _ in })
                }
                await pause(1.2)
                if let p = w.childWindows?.first(where: { $0.title == "SF Symbols" }) { await capture(p, "symbol-browser", settle: 0.8) }
                else { ScreenshotMode.log("symbol-browser: panel not found") }
                SymbolBrowserPanel.close()
            }
            w.close()
            await pause(0.4)
        }

        func settings() async {
            let ctl = SettingsWindowController.shared
            let w = ctl.window()
            place(w, content: NSSize(width: 760, height: 600))
            ctl.showSettings()
            await pause(0.8)
            let tabs: [(String, Int)] = [("settings-general", 0), ("settings-apps", 1), ("settings-voice", 3), ("settings-cloud", 4), ("settings-mcp", 5)]
            for (name, index) in tabs {
                if !selectTab(index, in: w.contentView) { ScreenshotMode.log("\(name): no NSTabView to switch"); continue }
                await capture(w, name, settle: 0.9)
            }
            w.close()
            await pause(0.4)
            // Quiet hours lives at the middle of the Voice tab: a window of its own shows it whole.
            let q = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 380), styleMask: [.titled, .closable],
                             backing: .buffered, defer: false)
            q.title = "Herald Settings"
            q.isReleasedWhenClosed = false
            q.contentView = NSHostingView(rootView: Form { QuietHoursSettingsView() }.formStyle(.grouped).padding(16))
            q.center()
            await capture(q, "settings-quiet-hours", settle: 0.9)
            q.close()
            await pause(0.3)
        }

        func selectTab(_ index: Int, in view: NSView?) -> Bool {
            guard let view else { return false }
            if let t = view as? NSTabView, index < t.numberOfTabViewItems { t.selectTabViewItem(at: index); return true }
            return view.subviews.contains { selectTab(index, in: $0) }
        }

        func history() async {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 980, height: 640),
                             styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
            w.title = "Herald History"
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: HistoryView(controller: c))
            w.center()
            NSApp.activate(ignoringOtherApps: true)
            w.makeKeyAndOrderFront(nil)
            await capture(w, "history", settle: 1.2)
            w.close()
            await pause(0.3)
        }

        // MARK: Banners

        func banner(_ name: String, _ n: HeraldNotification, prepare: (String, String) -> Void = { _, _ in }) async {
            guard let id = try? await c.notify(n) else { ScreenshotMode.log("\(name): notify failed"); return }
            await pause(0.8)
            prepare(n.app, id)
            await pause(0.9)
            if let w = c.banners.debugPanel(app: n.app, id: id) { await capture(w, name, settle: 0.3) }
            else { ScreenshotMode.log("\(name): banner panel not found") }
            c.banners.close(app: n.app, id: id)
            await pause(0.6)
        }

        func banners() async {
            await banner("banner-plain", HeraldNotification(
                app: "vercel", id: UUID().uuidString, title: "Deploy finished", subtitle: "herald-web \u{00B7} production",
                body: "Built in 42 s with no warnings. The new landing page is live.", sound: "none", persistent: true,
                buttons: [HeraldButton(label: "Open site", url: "https://example.com")]))
            await banner("banner-confirm", HeraldNotification(
                app: "vercel", id: UUID().uuidString, title: "Preview looks good", subtitle: "herald-web \u{00B7} gmail-section",
                body: "Promote this build to production?", sound: "none", persistent: true,
                buttons: [HeraldButton(label: "Deploy", style: "destructive", url: "https://example.com"), HeraldButton(label: "Not now", style: "cancel")]),
                prepare: { app, id in
                    _ = self.c.banners.presentConfirmation(.destructiveAction(label: "Deploy", name: "Vercel"), app: app, id: id)
                })
            await banner("banner-reply", HeraldNotification(
                app: "cloud.dev-box", id: UUID().uuidString, title: "Migration finished",
                body: "All 14 tables migrated with no data loss. Should I open the pull request, or run the seed script first?",
                sound: "none", persistent: true),
                prepare: { app, id in
                    _ = self.c.banners.setReply(app: app, id: id, BannerReplyPrompt(placeholder: "Reply to Claude (dev-box)\u{2026}"))
                })
        }
    }
}

#endif
