#if DEBUG
import SwiftUI
import AppKit
import HeraldClient

/// Hidden launch mode for the documentation screenshots (Debug builds only). Run it with `scripts/docs-screenshots.sh`, or by hand:
///
///     HERALD_SCREENSHOTS=<rawDir> [HERALD_SCREENSHOTS_ONLY=designer-,history] <Debug Herald binary>
///
/// Environment switches
///   HERALD_SCREENSHOTS=<dir>        turns the mode on; raw captures (transparent corners, no shadow, 2x) and `shots-meta.json` go here.
///                                   `web/scripts/frame-shots.mjs --docs` then composites them on gradients into web/public/shots/docs.
///   HERALD_SCREENSHOTS_ONLY=a,b     re-take only shots whose name starts with one of these (`banner-`, `settings-cloud`, `history-filtered`).
///
/// It runs on sample data only. `prepare()` points the app at a throwaway support folder and a free port, so the installed Herald's
/// data is never read or written. UserDefaults cannot be redirected (one bundle id), so the keys the run touches are put back at the end.
/// NO window is ever shown on a display and nothing is activated: every window is placed far outside all displays (`ShotKit.place`) and
/// captured by window id (`ShotKit`: screencapture, CGWindowListCreateImage or in-process cacheDisplay, first that works), banners are laid
/// out far off screen (`ScreenshotMode.bannerOffset`), the Dock icon and the status item are suppressed. Light appearance for every shot; shots
/// marked dual are taken again in dark as `<name>-dark`.
@MainActor
enum ScreenshotMode {
    static var outputDirectory: URL? {
        guard let p = ProcessInfo.processInfo.environment["HERALD_SCREENSHOTS"], !p.isEmpty else { return nil }
        return URL(fileURLWithPath: (p as NSString).expandingTildeInPath, isDirectory: true)
    }
    static var isActive: Bool { outputDirectory != nil }
    /// Added to every banner's position so banners live far outside the displays.
    static var bannerOffset: CGPoint? { isActive ? CGPoint(x: ShotKit.far.x, y: ShotKit.far.y) : nil }

    static var statusMenu: NSMenu?
    static var statusItem: NSStatusItem?

    /// Window creation hook for the app's own code paths: orders in offscreen instead of activating.
    static func present(_ w: NSWindow) { ShotKit.place(w) }

    private static var defaultsBefore: [String: Any] = [:]
    private static var voiceSuiteExisted = true
    private static let domain = Bundle.main.bundleIdentifier ?? "com.ivg.herald"

    /// First thing in `main()`, before `AppController` exists.
    nonisolated static func prepare() {
        guard ProcessInfo.processInfo.environment["HERALD_SCREENSHOTS"].map({ !$0.isEmpty }) == true else { return }
        let dir = NSTemporaryDirectory() + "herald-screenshots-\(getpid())"
        try? FileManager.default.removeItem(atPath: dir)
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        setenv("HERALD_SUPPORT_DIR", dir, 1)
        // Overlay scrollers that stay hidden while nothing scrolls, whatever the Mac's own setting (legacy scrollers draw as thick bars).
        UserDefaults.standard.setVolatileDomain(["AppleShowScrollBars": "WhenScrolling"], forName: UserDefaults.argumentDomain)   // extended in start()
        setenv("HERALD_PORT", String(49_000 + Int(getpid()) % 900), 1)
    }

    /// From `applicationDidFinishLaunching`, after `controller.start()`.
    static func start(controller: AppController) {
        guard let out = outputDirectory else { return }
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        WindowPresence.shared.apply = { _ in }          // no Dock icon, no activation policy change
        defaultsBefore = UserDefaults.standard.persistentDomain(forName: domain) ?? [:]
        voiceSuiteExisted = UserDefaults.standard.persistentDomain(forName: "com.ivg.herald.voice-dev") != nil
        NSApp.appearance = NSAppearance(named: .aqua)
        // The owner's saved Designer layout, zoom and symbol favourites must neither shape the shots nor be touched: the argument domain
        // overrides them for this process only and is never written back.
        UserDefaults.standard.setVolatileDomain(
            ["AppleShowScrollBars": "WhenScrolling", "designer.left": 226.0, "designer.right": 340.0, "designer.editorZoom": 1.0, "designer.previewZoom": 1.0,
             "designerPreviewFraction": 0.5, "designerSymbolFavorites": [String](), "designerSymbolRecents": [String]()],
            forName: UserDefaults.argumentDomain)
        Task { @MainActor in
            let runner = Runner(controller: controller, out: out)
            await runner.run()
            controller.relay.debugRemoveSample()
            restoreDefaults()
            ShotKit.log("done")
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
}

/// The application object in screenshot mode: reports active (so switches and default buttons draw in colour) without being activated.
final class ShotApplication: NSApplication {
    override var isActive: Bool { true }
}

/// A window of the mode's own making: never key, never main, never moved back on screen.
final class ShotWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    // Reports active so controls draw in the accent colour; the window is never really key and nothing is activated.
    override var isKeyWindow: Bool { true }
    override var isMainWindow: Bool { true }
    // AppKit's private "draw as active" queries (title bar, tab strip, controls).
    @objc(_hasKeyAppearance) func shotHasKeyAppearance() -> Bool { true }
    @objc(_hasMainAppearance) func shotHasMainAppearance() -> Bool { true }
    @objc(_hasActiveControls) func shotHasActiveControls() -> Bool { true }
    @objc(_hasActiveAppearance) func shotHasActiveAppearance() -> Bool { true }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

@MainActor
final class Runner {
    let c: AppController
    let out: URL
    let only: [String]
    var metas: [[String: Any]] = []
    var skipped: [String] = []
    init(controller: AppController, out: URL) {
        c = controller; self.out = out
        only = (ProcessInfo.processInfo.environment["HERALD_SCREENSHOTS_ONLY"] ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    func pause(_ s: Double) async { try? await Task.sleep(nanoseconds: UInt64(s * 1_000_000_000)) }

    /// A shot is taken when no filter is set or its name starts with one of the filters (or a filter starts with its name).
    func wants(_ name: String) -> Bool { only.isEmpty || only.contains { name.hasPrefix($0) || $0.hasPrefix(name) } }
    func wantsAny(_ prefix: String) -> Bool { only.isEmpty || only.contains { $0.hasPrefix(prefix) || prefix.hasPrefix($0) } }

    /// Safety net: any visible window of this process that AppKit has pulled onto a display is thrown back out at once.
    func startWatchdog() {
        Task { @MainActor in
            while !Task.isCancelled {
                for w in NSApp.windows where w.isVisible && w.alphaValue > 0 && !String(describing: type(of: w)).contains("StatusBar") && !ShotKit.isOffscreen(w) {
                    ShotKit.log("WATCHDOG: moved \(w.title.isEmpty ? String(describing: type(of: w)) : w.title) off the display (was \(NSStringFromRect(w.frame)))")
                    w.alphaValue = 0; w.setFrameOrigin(ShotKit.far); w.alphaValue = 1
                }
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
        }
    }

    func run() async {
        startWatchdog()
        ScreenshotMode.seed(c)
        await pause(1.0)
        if wantsAny("designer-") { await designer() } else if wantsAny("banner-actions") { await styleHeadless() }
        if wantsAny("settings-") { await settings() }
        if wantsAny("menu") { await menu() }
        await extras()
        // Banners before History: an open History window holds banners back (the notifications are already in front of the user).
        if wantsAny("banner-") { await banners() }
        if wantsAny("history") { await history() }
        writeMeta()
    }

    // MARK: Capture

    struct Opts {
        var title: String, shows: String, section: String
        var dual = false
        var crop: CGRect?
        var trim = false
        var round: CGFloat?
        var settle = 0.9
        var darkOnly = false
    }

    func setDark(_ dark: Bool) {
        NSApp.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        DesignerWindow.debugModel?.appearance = dark ? .dark : .light
    }

    /// Takes `name` (and `name-dark` when `dual`). `prepare` runs before each capture.
    func shot(_ name: String, _ w: NSWindow, _ o: Opts, prepare: ((Bool) async -> Void)? = nil) async {
        guard wants(name) || (o.dual && wants(name + "-dark")) else { return }
        for dark in o.dual ? [false, true] : [false] {
            let file = dark ? name + "-dark" : name
            guard wants(file) || wants(name) else { continue }
            setDark(dark)
            await prepare?(dark)
            await pause(o.settle)
            w.contentView?.layoutSubtreeIfNeeded(); w.displayIfNeeded()
            await pause(0.15)
            ShotKit.keepOffscreen(w)
            guard ShotKit.isOffscreen(w) else { ShotKit.log("\(file): window is not offscreen, skipped"); skipped.append(file); continue }
            await save(file, await ShotKit.grab(w, name: file), o, dark: dark)
        }
        setDark(false)
    }

    func save(_ file: String, _ g: ShotKit.Grab?, _ o: Opts, dark: Bool, windowShot: Bool = true) async {
        guard var img = g?.image, let method = g?.method else { ShotKit.log("\(file): FAILED, no capture method worked"); skipped.append(file); return }
        if let r = o.crop, let cropped = ShotKit.crop(img, points: r) { img = cropped }
        if o.trim { img = ShotKit.trimBottom(img) }
        if let r = o.round, let rounded = ShotKit.rounded(img, radius: r) { img = rounded }
        else if windowShot, let px = ShotKit.rgba(img), px[3] > 200, let rounded = ShotKit.rounded(img, radius: 16) { img = rounded }
        guard let data = ShotKit.png(img) else { skipped.append(file); return }
        try? data.write(to: out.appendingPathComponent(file + ".png"), options: .atomic)
        ShotKit.log("\(file): \(img.width)x\(img.height) px via \(method.rawValue)")
        metas.removeAll { ($0["name"] as? String) == file }
        metas.append(["name": file, "title": o.title + (dark ? " (dark)" : ""), "shows": o.shows, "section": o.section,
                      "appearance": dark ? "dark" : "light", "width": img.width, "height": img.height])
    }

    func writeMeta() {
        let f = out.appendingPathComponent("shots-meta.json")
        var all: [[String: Any]] = []
        if let d = try? Data(contentsOf: f), let old = try? JSONSerialization.jsonObject(with: d) as? [[String: Any]] { all = old }
        for m in metas { all.removeAll { ($0["name"] as? String) == (m["name"] as? String) }; all.append(m) }
        if let d = try? JSONSerialization.data(withJSONObject: all, options: [.prettyPrinted, .sortedKeys]) { try? d.write(to: f) }
        if !skipped.isEmpty { ShotKit.log("SKIPPED: " + skipped.joined(separator: ", ")) }
    }

    // MARK: Designer

    /// Applies the Actions-tab styling to the "ci" template without taking any designer shot (the banner shots need it).
    func styleHeadless() async {
        DesignerWindow.show(controller: c, app: ScreenshotMode.ciApp, template: ScreenshotMode.ciTemplate)
        guard let w = DesignerWindow.debugWindow, let m = DesignerWindow.debugModel, ShotKit.place(w, size: NSSize(width: 1280, height: 800)) else { return }
        await pause(1.0)
        ScreenshotMode.styleCiTemplate(m)
        w.close()
        await pause(0.4)
    }

    func designer() async {
        DesignerWindow.show(controller: c, app: ScreenshotMode.ciApp, template: ScreenshotMode.ciTemplate)
        guard let w = DesignerWindow.debugWindow, let m = DesignerWindow.debugModel else { ShotKit.log("designer: no window"); return }
        guard ShotKit.place(w, size: NSSize(width: 1280, height: 800)) else { return }
        await pause(1.2)
        ScreenshotMode.styleCiTemplate(m)
        await pause(0.8)
        let titleBar = w.frame.height - w.contentLayoutRect.height
        let top = titleBar + 34                                   // below the Design | Quick send bar
        let left = CGFloat(DesignerPanes.defaultLeft), right = CGFloat(DesignerPanes.defaultRight)
        let contentH = w.contentLayoutRect.height - 34
        let previewH = CGFloat(DesignerSplit.make(width: 0, fraction: DesignerSplit.defaultPreviewFraction).previewLength(total: Double(contentH)))
        let centerX = left + 8, centerW = w.frame.width - left - right - 16

        await shot("designer-overview", w, Opts(title: "Designer", shows: "The Design Template window: the palette of components, assets and fields on the left, the live preview above the grid editor in the middle, and the inspector (Cell, Template, Actions tabs) on the right, with the body text cell selected.", section: "designer", dual: true)) { _ in
            m.tab = .cell; m.select(cell: "body")
        }
        await shot("designer-cell-selected", w, Opts(title: "A text cell selected", shows: "The Cell tab of the inspector for the selected title text cell: its position and span, alignment, the text binding with the token picker, style, lines and colour, and what the cell does when its field is empty.", section: "designer")) { _ in
            m.tab = .cell; m.select(cell: "title")
        }
        await shot("designer-inspector-template", w, Opts(title: "Template inspector", shows: "The Template tab of the inspector: template name, accent colour, whether empty fields collapse or leave their place, the grid's width, gap and padding, and the column and row track lists.", section: "designer")) { _ in
            m.clearSelection(); m.tab = .template
        }
        await shot("designer-inspector-actions", w, Opts(title: "Actions inspector", shows: "The Actions tab of the inspector: the issuer's three actions (Open log with icon and text, Deploy icon-only, Dismiss) each with its Shows menu, Button style menu and icon button, a user-added Shortcut action with edit and delete, and the Extra data table.", section: "designer", dual: true)) { _ in
            m.clearSelection(); m.tab = .actions
        }
        // The action form is a sheet in the app; an attached sheet makes AppKit pull its parent window back onto a display, so the
        // same view is drawn in a window of its own instead.
        if wants("designer-action-form") {
            var req = m.newActionRequest(kind: .shortcut)
            req.action.label = "Notify the team"
            req.action.shortcut = "Post build status"
            req.action.symbol = HeraldSymbol(name: "paperplane")
            let host = NSHostingView(rootView: ActionFormView(model: m, request: req).background(Color(nsColor: .windowBackgroundColor)))
            let fw = ShotWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 560), styleMask: [.borderless], backing: .buffered, defer: false)
            fw.isReleasedWhenClosed = false
            fw.contentView = host
            if ShotKit.place(fw, size: NSSize(width: 480, height: 560)) {
                await shot("designer-action-form", fw, Opts(title: "Add action form", shows: "The Add action form: Label, Does this (Run a Shortcut with its name and input), Shows, Button style and the Symbol panel for the button's icon.", section: "designer", round: 14))
            }
            fw.close()
        }
        if wants("designer-action-icon-popover") {
            // The popover itself is vibrancy over nothing when nothing is behind it, so its content is drawn in a window of its own.
            var sym: HeraldSymbol? = HeraldSymbol(name: "link")
            let panel = SymbolPanel(model: m, symbol: Binding(get: { sym }, set: { sym = $0 }))
            let host = NSHostingView(rootView: ScrollView { panel.padding(12) }.frame(width: 320, height: 420).background(Color(nsColor: .windowBackgroundColor)))
            let pw = ShotWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 420), styleMask: [.borderless], backing: .buffered, defer: false)
            pw.isReleasedWhenClosed = false
            pw.contentView = host
            if ShotKit.place(pw, size: NSSize(width: 320, height: 420)) {
                await shot("designer-action-icon-popover", pw, Opts(title: "Per-action icon panel", shows: "The Symbol panel that opens from an action's icon button: the symbol name with its picker, weight, scale, placement (Before, After, Only), rendering mode, colour, variable value and effect.", section: "designer", trim: true, round: 12))
            }
            pw.close()
        }
        await shot("designer-palette", w, Opts(title: "Palette", shows: "The left pane of the designer: the Components list (text, image, icon, actions, buttons and more), the Assets section for animations, and the Fields list with issuer, standard and seen tokens that can be dragged onto the grid.", section: "designer", crop: CGRect(x: 0, y: top, width: left, height: contentH), round: 12)) { _ in
            m.clearSelection(); m.tab = .cell
        }
        await shot("designer-live-preview", w, Opts(title: "Live preview", shows: "The live preview pane: the banner as it will appear, the Sample and Last real source switch, the light and dark preview toggle, zoom, the Fields (absent) button, Send test and Save.", section: "designer", crop: CGRect(x: centerX, y: top, width: centerW, height: previewH), round: 12)) { _ in
            m.previewSource = .sample
        }
        await shot("designer-grid-editing", w, Opts(title: "Editing the grid", shows: "The grid editor with the body cell selected: its resize handles, the column and row track rulers with their sizes, and the empty slots around the cells.", section: "designer", crop: CGRect(x: centerX, y: top + previewH + 8, width: centerW, height: contentH - previewH - 8), round: 12)) { _ in
            m.tab = .cell; m.select(cell: "body")
        }
        await shot("designer-empty-field-collapse", w, Opts(title: "Empty fields collapse", shows: "The preview with the subtitle and body fields marked absent (the Fields button reads 2 absent) so their rows collapse, next to the Template tab where \"Collapse empty fields\" or leaving their place is chosen.", section: "designer")) { _ in
            m.clearSelection(); m.tab = .template; m.absentTokens = ["subtitle", "body"]
        }
        m.absentTokens = []
        if wants("designer-symbol-browser") {
            m.tab = .cell
            SymbolBrowserPanel.show(parent: w) {
                SymbolBrowserHost(designer: m, current: { HeraldSymbol(name: "bell.badge") }, apply: { _ in })
            }
            await pause(1.5)
            if let p = w.childWindows?.first(where: { $0.title == "SF Symbols" }) {
                await shot("designer-symbol-browser", p, Opts(title: "SF Symbol browser", shows: "The SF Symbols browser: the category list with counts on the left (All symbols, Recents, Favourites, then categories such as Communication and Weather), a search field with a size slider, and the grid of symbols with their names; the right pane waits for a symbol to be selected.", section: "designer"))
            } else { ShotKit.log("designer-symbol-browser: panel not found"); skipped.append("designer-symbol-browser") }
            SymbolBrowserPanel.close()
            await pause(0.5)
        }
        await shot("designer-quick-send", w, Opts(title: "Quick send", shows: "Quick send mode of the designer window: the form for sending a one-off notification (issuer, title, subtitle, body, buttons, sound) with its live preview.", section: "designer")) { _ in
            m.showQuickSend(app: ScreenshotMode.ciApp)
        }
        m.showDesign()
        w.close()
        await pause(0.4)
    }

    // MARK: Settings

    func settingsTab(_ i: Int) { NotificationCenter.default.post(name: Notification.Name("herald.debug.settingsTab"), object: i) }

    /// One window per Settings tab (switching tabs in an offscreen window crashes AppKit's tab layout), as tall as the tab's content.
    func settingsShot(_ name: String, tab: Int, _ o: Opts, tall: CGFloat = 1500, fit: Bool = true, extra: ((NSWindow) async -> Void)? = nil) async {
        guard wants(name) else { return }
        let w = ShotWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: tall), styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        w.title = "Herald Settings"
        w.isReleasedWhenClosed = false
        w.contentView = NSHostingView(rootView: SettingsView(controller: c, initialTab: tab))
        guard ShotKit.place(w, size: NSSize(width: 760, height: tall)) else { return }
        await pause(1.2)
        await extra?(w)
        // Two passes: measure how much of the tall window the tab fills, then take the shot in a window of exactly that height,
        // so the window keeps its own rounded bottom corners.
        if fit, let g = await ShotKit.grab(w, name: name + " (measure)") {
            let frameH = CGFloat(ShotKit.trimBottom(g.image, pad: 18).height) / 2
            let titleBar = w.frame.height - w.contentLayoutRect.height
            w.setContentSize(NSSize(width: 760, height: max(300, frameH - titleBar)))
            ShotKit.keepOffscreen(w)
            await pause(1.0)
        }
        await shot(name, w, o)
        w.close()
        await pause(0.3)
    }

    func settings() async {
        await settingsShot("settings-general", tab: 0, Opts(title: "General settings", shows: "The General tab: the local API port with Apply and Reset, the token file button, Launch at login, Mute all sounds, the tooltip level, and the History size limit.", section: "settings"))
        await settingsShot("settings-apps", tab: 1, Opts(title: "Apps settings", shows: "The Apps tab with GitHub Actions selected in the list: its icon, banner, sound and display settings, and the Remove button at the bottom.", section: "settings"), tall: 1150, fit: false) { _ in
            NotificationCenter.default.post(name: Notification.Name("herald.debug.appsSelect"), object: ScreenshotMode.ciApp)
            await self.pause(0.8)
        }
        await settingsShot("settings-actions", tab: 2, Opts(title: "Actions settings", shows: "The Actions tab: the scripts folder with two sample scripts and the Reveal in Finder button, and the templates that carry commands of their own with their confirmation status.", section: "settings"))
        await settingsShot("settings-voice", tab: 3, Opts(title: "Voice settings", shows: "The Voice tab: the speech voice, speed and language choices, the on-device voice install, and the Quiet hours section.", section: "settings"))
        await settingsShot("settings-cloud-off", tab: 4, Opts(title: "Cloud settings, relay off", shows: "The Cloud tab before a relay is set up: the explanation, the Enable relay switch (off), and the collapsed Advanced section.", section: "settings"))
        await settingsShot("settings-mcp", tab: 5, Opts(title: "MCP settings", shows: "The MCP tab: the herald-mcp server path and its Test button, one-click install rows for Claude Code, Codex and Claude Desktop, and the generic client config.", section: "settings"))
        if wants("settings-cloud-paired") || wants("settings-cloud-advanced") {
            ScreenshotMode.sampleRelay(c)
            await pause(0.8)
            await settingsShot("settings-cloud-paired", tab: 4, Opts(title: "Cloud settings, paired", shows: "The whole Cloud tab for a paired, online relay: relay state and Connector URL, Connect an agent, Connector approvals with one pending request and its code and Approve and Deny buttons, Reply subscriptions with one subscription and an End button, Agent keys with Design and Revoke, Usage today, and Last relay items.", section: "settings"), tall: 3400)
            await settingsShot("settings-cloud-advanced", tab: 4, Opts(title: "Cloud settings, Advanced", shows: "The Cloud tab with Advanced expanded: the custom domain, the Macs paired with the relay, the relay URL and every relay limit as an editable field.", section: "settings"), tall: 4400) { _ in
                NotificationCenter.default.post(name: Notification.Name("herald.debug.cloudAdvanced"), object: true)
                await self.pause(1.0)
            }
        }

        if wants("settings-cloud-deploy") {
            let host = NSHostingView(rootView: DeployRelaySheet(controller: c, isPresented: .constant(true)).frame(width: 520))
            let size = host.fittingSize
            let d = ShotWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
            d.isReleasedWhenClosed = false
            d.contentView = host
            if ShotKit.place(d, size: size) {
                await shot("settings-cloud-deploy", d, Opts(title: "Create your relay on Cloudflare", shows: "The deploy sheet opened by Enable relay: the explanation, step 1 Create a token with the Open Cloudflare button, step 2 the token field, and the Deploy button.", section: "settings", round: 14))
            }
            d.close()
        }
        if wants("settings-quiet-hours") {
            let q = ShotWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 900), styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
            q.title = "Herald Settings"
            q.isReleasedWhenClosed = false
            q.contentView = NSHostingView(rootView: Form { QuietHoursSettingsView() }.formStyle(.grouped).padding(16))
            if ShotKit.place(q, size: NSSize(width: 760, height: 900)) {
                await pause(1.0)
                if let g = await ShotKit.grab(q, name: "quiet (measure)") {
                    let frameH = CGFloat(ShotKit.trimBottom(g.image, pad: 4).height) / 2
                    q.setContentSize(NSSize(width: 760, height: frameH - (q.frame.height - q.contentLayoutRect.height)))
                    ShotKit.keepOffscreen(q)
                    await pause(0.8)
                }
                await shot("settings-quiet-hours", q, Opts(title: "Quiet hours", shows: "The Quiet hours section of the Voice tab: one window with the weekday chips, from 22:30 until 07:30, the Speech, Sounds and Banners switches, the option to speak queued messages when it ends, Add Window and Quiet for 1 Hour.", section: "settings"))
            }
            q.close()
        }
    }

    // MARK: History

    func history() async {
        ScreenshotMode.seedHistory(c)
        for (name, app, search, o) in [
            ("history", HistorySelection.allID, "", Opts(title: "History", shows: "The History window with All Apps selected: the apps sidebar with counts, the search field, and the newest-first list of past notifications as banner-style rows.", section: "history", settle: 1.0)),
            ("history-group-folded", "vercel", "", Opts(title: "History with a folded group", shows: "The History window with Vercel selected: three notifications sent with the same group are folded into one row, herald-web, with an arrow to open it and a line saying 3 notifications and how many were not dismissed.", section: "history", settle: 1.0)),
            ("history-filtered", ScreenshotMode.ciApp, "build", Opts(title: "History filtered", shows: "The History window with GitHub Actions selected in the sidebar and the text \"build\" in the search field, so only matching rows are listed.", section: "history", settle: 1.0))] {
            guard wants(name) else { continue }
            let w = ShotWindow(contentRect: NSRect(x: 0, y: 0, width: 980, height: 640), styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
            w.title = "Herald History"
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: HistoryView(controller: c, initialSelection: app, initialSearch: search))
            guard ShotKit.place(w, size: NSSize(width: 980, height: 640)) else { continue }
            await pause(1.2)
            await shot(name, w, o)
            w.close()
            await pause(0.3)
        }
    }

    // MARK: Menu

    func menu() async {
        guard wants("menu"), let menu = ScreenshotMode.statusMenu else { return }
        menu.delegate?.menuNeedsUpdate?(menu)
        let host = NSHostingView(rootView: ShotMenuView(menu: menu).padding(2))
        let size = host.fittingSize
        let w = ShotWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        w.isOpaque = false; w.backgroundColor = .clear; w.hasShadow = false; w.isReleasedWhenClosed = false
        w.contentView = host
        guard ShotKit.place(w, size: size) else { return }
        await shot("menu", w, Opts(title: "Menu bar menu", shows: "The Herald menu-bar menu: the unread count, Compose, Design Template, History, Mute Sounds, Quiet for 1 Hour, Stack Notifications, Dismiss All, Settings and Quit, with their shortcuts. Drawn from the real menu's items, since a live menu cannot be captured without opening it.", section: "menu", round: 12))
        w.close()
    }

    // MARK: Banners

    func bannerPanels() -> [NSWindow] { NSApp.windows.filter { $0 is BannerPanel && $0.isVisible && $0.alphaValue > 0.5 } }

    /// Captures every visible banner panel as one picture (a stack that is open has more than one).
    func grabBanners(_ name: String) async -> ShotKit.Grab? {
        let panels = bannerPanels()
        guard !panels.isEmpty else {
            ShotKit.log("\(name): no banner panel")
            return nil
        }
        for p in panels where !ShotKit.isOffscreen(p) { ShotKit.log("\(name): a banner panel is on screen, skipped"); return nil }
        if panels.count == 1 { return await ShotKit.grab(panels[0], name: name) }
        let union = panels.map(\.frame).reduce(panels[0].frame) { $0.union($1) }
        guard let ctx = CGContext(data: nil, width: Int(union.width * 2), height: Int(union.height * 2), bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        var method = ShotKit.Method.cacheDisplay
        for p in panels {
            guard let g = await ShotKit.grab(p, name: name) else { return nil }
            method = g.method
            ctx.draw(g.image, in: CGRect(x: (p.frame.minX - union.minX) * 2, y: (p.frame.minY - union.minY) * 2, width: p.frame.width * 2, height: p.frame.height * 2))
        }
        return ctx.makeImage().map { ShotKit.Grab(image: $0, method: method) }
    }

    func banner(_ name: String, _ o: Opts, _ n: HeraldNotification, settle: Double = 1.0, prepare: (@MainActor (String, String) async -> Void)? = nil,
                keep: Bool = false) async -> (String, String)? {
        guard wants(name) else { return nil }
        guard let id = try? await c.notify(n) else { ShotKit.log("\(name): notify failed"); skipped.append(name); return nil }
        await pause(1.2)
        await prepare?(n.app, id)
        await pause(settle)
        await save(name, await grabBanners(name), o, dark: false, windowShot: false)
        if !keep { c.banners.close(app: n.app, id: id); await pause(0.7) }
        return (n.app, id)
    }

    func banners() async {
        ShotKit.log("banner offset \(String(describing: ScreenshotMode.bannerOffset))")
        let long = "The nightly build finished with 3 warnings and 1 failing test. The failing test is in the relay reconnect path: it expects the second attempt to wait two seconds, but the backoff now starts at one. The fix is a one-line change in the test; the other warnings are about unused imports in the new Cloud settings files."
        _ = await banner("banner-plain", Opts(title: "Banner", shows: "A plain notification banner: the issuer icon and name, a title, a subtitle, two lines of body text, the time and the close button.", section: "banners"),
            HeraldNotification(app: "vercel", id: UUID().uuidString, title: "Deploy finished", subtitle: "herald-web \u{00B7} production",
                               body: "Built in 42 s with no warnings. The new landing page is live.", sound: "none", persistent: true))
        let longN = { HeraldNotification(app: "vercel", id: UUID().uuidString, title: "Nightly build finished", subtitle: "herald-relay \u{00B7} main", body: long, sound: "none", persistent: true, maxBodyLines: 3) }
        if let k = await banner("banner-long-collapsed", Opts(title: "Long banner, collapsed", shows: "A notification with a long body, cut short after a few lines until the banner is clicked.", section: "banners"), longN(), keep: true) {
            if wants("banner-long-expanded") {
                c.banners.debugModel(app: k.0, id: k.1)?.bodyClicked()
                await pause(1.5)
                await save("banner-long-expanded", await grabBanners("banner-long-expanded"), Opts(title: "Long banner, expanded", shows: "The same notification after a click on its body: every line shows in full and the banner has grown to fit.", section: "banners"), dark: false, windowShot: false)
            }
            c.banners.close(app: k.0, id: k.1); await pause(0.7)
        }
        _ = await banner("banner-actions", Opts(title: "Banner with buttons", shows: "A banner with three buttons from the issuer's manifest: Open log with an icon and text, an icon-only Deploy button, and a Dismiss button; the template's own Post to Slack Shortcut button follows.", section: "banners"),
            HeraldNotification(app: ScreenshotMode.ciApp, id: UUID().uuidString, title: "Build failed", subtitle: "herald-relay \u{00B7} main",
                               body: "Step 'lint' exited with code 1.", url: "https://ci.example.com/runs/4821", sound: "none", persistent: true, template: ScreenshotMode.ciTemplate, actionIds: ["open-log", "deploy", "dismiss"]))
        _ = await banner("banner-confirm", Opts(title: "Destructive confirmation", shows: "The inline confirmation that replaces the buttons after pressing a destructive action: the question, what will run, and the Deploy and Cancel answers.", section: "banners"),
            HeraldNotification(app: "vercel", id: UUID().uuidString, title: "Preview looks good", subtitle: "herald-web \u{00B7} gmail-section",
                               body: "Promote this build to production?", sound: "none", persistent: true,
                               buttons: [HeraldButton(label: "Deploy", style: "destructive", url: "https://example.com"), HeraldButton(label: "Not now", style: "cancel")]),
            prepare: { app, id in _ = self.c.banners.presentConfirmation(.destructiveAction(label: "Deploy", name: "Vercel"), app: app, id: id) })
        _ = await banner("banner-reply", Opts(title: "Inline reply", shows: "The inline reply field that replaces the buttons when a Reply button is pressed, with its placeholder and the Send and Cancel controls.", section: "banners"),
            HeraldNotification(app: "cloud.build-bot", id: UUID().uuidString, title: "Migration finished",
                               body: "All 14 tables migrated with no data loss. Should I open the pull request, or run the seed script first?", sound: "none", persistent: true),
            prepare: { app, id in _ = self.c.banners.setReply(app: app, id: id, BannerReplyPrompt(placeholder: "Reply to Claude (build-bot)\u{2026}")) })
        _ = await banner("banner-record", Opts(title: "Voice record strip", shows: "The inline record strip of a voice reply: the recording state with its elapsed time and the controls to stop or cancel.", section: "banners"),
            HeraldNotification(app: "cloud.build-bot", id: UUID().uuidString, title: "Migration finished", body: "Should I open the pull request?", sound: "none", persistent: true),
            prepare: { app, id in _ = self.c.banners.setRecord(app: app, id: id, BannerRecordPrompt(phase: .recording, elapsed: 7.4)) })
        _ = await banner("banner-connector-consent", Opts(title: "Connector request", shows: "The question a connector's request raises: which connector asks, the host it returns to, the match code, and the Approve and Deny answers.", section: "banners"),
            HeraldNotification(app: HeraldIdentity.app, id: UUID().uuidString, title: "Connector request", body: "Claude Desktop is asking to connect to Herald.", sound: "none", persistent: true),
            prepare: { app, id in
                HeraldIdentity.ensureRegistered(registry: self.c.registry, supportDirectory: self.c.supportDirectory, iconPNG: nil)
                _ = self.c.banners.presentConfirmation(.connectorConsent(name: "Claude Desktop", host: "claude.ai"), app: app, id: id)
            })
        // A spoken notification shows a replay control once its speech exists; the speech record is attached without playing anything.
        _ = await banner("banner-speech", Opts(title: "Spoken notification", shows: "A notification that was spoken: the small speaker control beside the time replays the message.", section: "banners"),
            HeraldNotification(app: "agent.claude-code", id: UUID().uuidString, title: "Tests pass", subtitle: "herald", body: "All 412 tests passed after the banner refactor.", sound: "none", persistent: true),
            prepare: { app, id in
                _ = self.c.history.update(app: app, id: id) { $0.speech = HeraldSpeech(text: "Tests pass. All 412 tests passed after the banner refactor.", voice: "af_heart", audioPath: nil, durationSeconds: 3.4) }
                if let m = self.c.banners.debugModel(app: app, id: id), let fresh = self.c.history.item(app: app, id: id) { m.item = fresh }
            })
        // Stacks: three notifications of one group.
        if wants("banner-stack") {
            var ids: [String] = []
            for (i, t) in ["Preview ready", "Deploy finished", "Build passed"].enumerated() {
                let n = HeraldNotification(app: "vercel", id: UUID().uuidString, title: t, subtitle: "herald-web \u{00B7} \(["gmail-section", "production", "main"][i])",
                                           body: ["https://example.com/preview", "Built in 42 s.", "Finished in 3 min 12 s."][i], sound: "none", persistent: true, group: "herald-web")
                if let id = try? await c.notify(n) { ids.append(id) }
                await pause(0.8)
            }
            await pause(1.2)
            ShotKit.log("stack: \(bannerPanels().count) panels visible")
            await save("banner-stack-closed", await grabBanners("banner-stack-closed"), Opts(title: "Closed stack", shows: "Three notifications of one group folded into one stacked banner: the top card with the count badge and the edges of the cards under it.", section: "banners"), dark: false, windowShot: false)
            _ = c.banners.setStackOpen(app: "vercel", group: "herald-web", true)
            await pause(1.5)
            ShotKit.log("stack open: \(bannerPanels().count) panels visible")
            await save("banner-stack-open", await grabBanners("banner-stack-open"), Opts(title: "Open stack", shows: "The same stack opened: the three notifications listed one under the other with the Collapse and Dismiss all controls at the bottom.", section: "banners"), dark: false, windowShot: false)
            c.banners.closeAll()
            await pause(0.8)
        }
    }
}
#endif
