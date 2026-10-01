import AppKit
import SwiftUI

final class BannerPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class BannerEntry {
    let key: String
    let panel: BannerPanel
    let host: NSHostingView<BannerView>
    let model: BannerModel
    let seq: Int
    var corner: HeraldCorner
    var height: CGFloat = 80
    /// The banner's width: a v2 template sets its own (`BannerModel.bannerWidth`), so it is per banner.
    var width: CGFloat = BannerView.width
    var remaining: Double?
    var shown = false
    var measured = false
    /// Hidden because the banners above it already fill the screen (see `BannerStackPlan`).
    var overflowed = false
    init(key: String, panel: BannerPanel, host: NSHostingView<BannerView>, model: BannerModel, seq: Int, corner: HeraldCorner) {
        self.key = key; self.panel = panel; self.host = host; self.model = model; self.seq = seq; self.corner = corner
    }
}

/// Owns the on-screen banner panels: stacking, animation, hover-paused timeouts.
@MainActor
final class BannerCenter {
    static let margin: CGFloat = 12
    static let gap: CGFloat = 8
    /// Height of the "+N more" pill.
    static let stubHeight: CGFloat = 26

    private unowned let controller: AppController
    private var entries: [String: BannerEntry] = [:]
    private var snoozeTimers: [String: Timer] = [:]
    private var seqCounter = 0
    private var ticker: Timer?
    private var screenObserver: NSObjectProtocol?
    private var relayoutScheduled = false
    private var stubs: [HeraldCorner: OverflowStub] = [:]
    /// Banners that exist only in History (not restored to a panel at launch) and are counted by the pill.
    private var deferredKeys: Set<String> = []
    private var deferredCorner: HeraldCorner = .topRight

    /// Handles a pressed action other than dismiss, the snooze menu and Add to Reminders: url, callback,
    /// command, script and shortcut actions, whether the issuer sent them or the template added them (`origin`
    /// says which). Arguments are the banner's app and id. While nil, url, callback and command actions run as
    /// v1 buttons did and the rest are ignored.
    var actionHandler: ((_ app: String, _ id: String, _ action: HeraldAction, _ origin: HeraldActionOrigin) -> Void)?

    init(controller: AppController) {
        self.controller = controller
        // A monitor that comes or goes changes the visible frame; banners would otherwise stay where the old
        // frame put them, possibly off the screen.
        let reflow: @Sendable (Notification) -> Void = { [weak self] _ in MainActor.assumeIsolated { self?.relayout(animated: false) } }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main, using: reflow)
        ticker = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(ticker!, forMode: .common)
    }

    static func key(_ app: String, _ id: String) -> String { app + "\u{1}" + id }
    var visibleCount: Int { entries.count }

    // MARK: Show / update

    func show(_ item: HeraldHistoryItem, settings: EffectiveSettings, record: AppRecord?,
              template: HeraldTemplate? = nil, manifest: HeraldManifest? = nil) {
        let key = Self.key(item.app, item.id)
        // What a banner draws besides its notification is looked up where the controller keeps it, so every show
        // (a new notification, a snooze coming back, a restore at launch, a failure line) draws the same banner.
        let template = template ?? storedTemplate(for: item)
        let manifest = manifest ?? controller.manifests.get(app: item.app)
        cancelSnooze(key)
        deferredKeys.remove(key)
        let image = item.imagePath.flatMap { NSImage(contentsOfFile: $0) }
        let icon = AppIcons.icon(for: record, app: item.app)
        let name = record?.displayName ?? item.app

        if let e = entries[key] {
            // Template and manifest first, so the item change below redraws once with everything in place.
            e.model.template = template
            e.model.manifest = manifest
            e.model.item = item
            e.model.image = image
            e.model.icon = icon
            e.model.appName = name
            e.model.reminderState = .idle
            e.model.failureLine = nil
            e.remaining = settings.timeout
            e.corner = settings.corner
            e.width = e.model.bannerWidth
            relayout(animated: true)
            return
        }

        let model = BannerModel(item: item, appName: name, icon: icon, image: image, template: template, manifest: manifest)
        model.onClose = { [weak self] in self?.controller.userClosed(app: item.app, id: item.id) }
        model.onOpen = { [weak self] in self?.controller.userOpened(app: item.app, id: item.id) }
        model.onAction = { [weak self] action, origin in self?.route(action, origin: origin, app: item.app, id: item.id) }
        model.onSnooze = { [weak self] o in self?.controller.userSnoozed(app: item.app, id: item.id, option: o) }
        model.onReminder = { [weak self] in self?.controller.userAddedReminder(app: item.app, id: item.id) }

        let host = NSHostingView(rootView: BannerView(model: model))
        let panel = BannerPanel(contentRect: NSRect(x: 0, y: 0, width: model.bannerWidth, height: 80),
                                styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.contentView = host

        seqCounter += 1
        let e = BannerEntry(key: key, panel: panel, host: host, model: model, seq: seqCounter, corner: settings.corner)
        e.remaining = settings.timeout
        // Templates differ a lot in height (a one-line banner ~44 pt, a hero ~260 pt); start from an estimate and
        // let the SwiftUI measurement below replace it. The view is the single source of truth for height.
        e.width = model.bannerWidth
        e.height = BannerView.estimatedHeight(for: model)
        entries[key] = e
        model.onHeight = { [weak self, weak e] h in
            MainActor.assumeIsolated {
                guard let self, let e, h > 1 else { return }
                if abs(e.height - h) > 0.5 || !e.measured {
                    e.height = ceil(h)
                    e.measured = true
                    self.requestRelayout()
                }
            }
        }
        // Park the panel off-screen and invisible so SwiftUI renders and reports its height.
        // The alpha must be 0 BEFORE the first setFrame/orderFront: SwiftUI can report its height synchronously from
        // inside those calls, and relayout() then starts the slide/fade-in. Resetting alpha afterwards (as this code
        // once did) cancelled that fade and left the banner invisible until another notification re-ran relayout.
        let vf = screenFrame
        panel.alphaValue = 0
        panel.setFrame(NSRect(x: vf.maxX + 40, y: vf.maxY - 200, width: e.width, height: e.height), display: false)
        panel.orderFrontRegardless()
    }

    /// The template the notification names: one saved for its app, else a built-in (`builtin.hero` ...).
    private func storedTemplate(for item: HeraldHistoryItem) -> HeraldTemplate? {
        if let t = controller.templates.template(for: item.notification) { return t }
        guard let name = item.notification.template else { return nil }
        return BuiltinTemplates.named(name, app: item.app)
    }

    /// A pressed action goes to the installed handler. Without one, what a v1 button could express (open a
    /// link, call back, run a command) runs as it always did.
    private func route(_ action: HeraldAction, origin: HeraldActionOrigin, app: String, id: String) {
        if let handler = actionHandler { handler(app, id, action, origin); return }
        if let button = action.legacyButton { controller.userPressed(app: app, id: id, button: button) }
    }

    // MARK: Layout

    private var screenFrame: NSRect {
        (NSScreen.screens.first ?? NSScreen.main)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
    }

    private func targetOrigin(corner: HeraldCorner, offset: CGFloat, width: CGFloat, height: CGFloat) -> NSPoint {
        let vf = screenFrame
        let right = corner == .topRight || corner == .bottomRight
        let top = corner == .topRight || corner == .topLeft
        let x = right ? vf.maxX - Self.margin - width : vf.minX + Self.margin
        let y = top ? vf.maxY - Self.margin - offset - height : vf.minY + Self.margin + offset
        return NSPoint(x: x, y: y)
    }

    /// Many banners measuring themselves at once (a restore, a burst of notifications) ask for one layout pass,
    /// not one each: every pass touches every banner.
    func requestRelayout() {
        guard !relayoutScheduled else { return }
        relayoutScheduled = true
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.relayoutScheduled = false
                self.relayout(animated: true)
            }
        }
    }

    func relayout(animated: Bool) {
        let available = max(0, screenFrame.height - 2 * Self.margin)
        for corner in HeraldCorner.allCases {
            let group = entries.values.filter { $0.corner == corner && $0.measured }.sorted { $0.seq > $1.seq }
            let deferredHere = corner == deferredCorner ? deferredKeys.count : 0
            let plan = BannerStackPlan.make(heights: group.map(\.height), available: available, gap: Self.gap,
                                            stubHeight: Self.stubHeight,
                                            // While this corner's banners are still being measured there is nothing to attach the pill to.
                                            forceStub: deferredHere > 0 && (!group.isEmpty || !entries.values.contains { $0.corner == corner }))
            for (index, e) in group.enumerated() {
                guard index < plan.visibleCount else {
                    // No room: the panel stays hidden until a banner above it goes away.
                    e.overflowed = true
                    if e.shown || e.panel.isVisible { e.panel.orderOut(nil) }
                    e.shown = false
                    continue
                }
                e.overflowed = false
                let origin = targetOrigin(corner: corner, offset: plan.offsets[index], width: e.width, height: e.height)
                let frame = NSRect(origin: origin, size: NSSize(width: e.width, height: e.height))
                if !e.shown {
                    e.shown = true
                    let right = corner == .topRight || corner == .bottomRight
                    var start = frame
                    start.origin.x += (right ? 1 : -1) * (e.width + Self.margin)
                    e.panel.setFrame(start, display: false)
                    e.panel.alphaValue = 0
                    e.panel.orderFrontRegardless()
                }
                if animated {
                    NSAnimationContext.runAnimationGroup({ ctx in
                        ctx.duration = 0.28
                        ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                        e.panel.animator().setFrame(frame, display: true)
                        e.panel.animator().alphaValue = 1
                    }, completionHandler: { [weak self, weak e] in
                        // A newer group can supersede this one mid-flight; whatever happens, a banner that is still
                        // on screen must end up fully opaque.
                        MainActor.assumeIsolated {
                            guard let self, let e, self.entries[e.key] === e, !e.overflowed else { return }
                            if e.panel.alphaValue < 1 { e.panel.alphaValue = 1 }
                        }
                    })
                } else {
                    e.panel.setFrame(frame, display: true)
                    e.panel.alphaValue = 1
                }
            }
            updateStub(corner: corner, offset: plan.stubOffset, count: plan.overflow + deferredHere)
        }
    }

    private func updateStub(corner: HeraldCorner, offset: CGFloat?, count: Int) {
        guard let offset, count > 0 else {
            if let stub = stubs[corner], stub.panel.isVisible { stub.panel.orderOut(nil) }
            return
        }
        let stub: OverflowStub
        if let existing = stubs[corner] { stub = existing } else {
            stub = OverflowStub()
            stub.model.onHistory = { [weak self] in self?.controller.openHistory?() }
            stub.model.onDismissAll = { [weak self] in self?.controller.dismissAll(app: nil) }
            stubs[corner] = stub
        }
        let width = stub.update(count: count)
        let right = corner == .topRight || corner == .bottomRight
        let vf = screenFrame
        let top = corner == .topRight || corner == .topLeft
        let x = right ? vf.maxX - Self.margin - width : vf.minX + Self.margin
        let y = top ? vf.maxY - Self.margin - offset - Self.stubHeight : vf.minY + Self.margin + offset
        stub.panel.setFrame(NSRect(x: x, y: y, width: width, height: Self.stubHeight), display: true)
        stub.panel.alphaValue = 1
        stub.panel.orderFrontRegardless()
    }

    /// Banners that were left without a panel (see `AppController.restoreBanners`). They stay undismissed in
    /// History; the pill counts them until they are dismissed.
    func deferBanners(keys: [String], corner: HeraldCorner = .topRight) {
        deferredKeys = Set(keys)
        deferredCorner = corner
        requestRelayout()
    }

    /// A banner held back by quiet hours: no panel, but History keeps it unread and the "+N more" pill counts it
    /// until it is dismissed (like banners left without a panel at launch).
    func deferBanner(key: String, corner: HeraldCorner) {
        deferredKeys.insert(key)
        deferredCorner = corner
        requestRelayout()
    }

    // MARK: Removal

    /// Removes the banner (animated) and cancels any pending snooze. Does not touch history.
    func close(app: String, id: String) {
        let key = Self.key(app, id)
        cancelSnooze(key)
        if deferredKeys.remove(key) != nil { requestRelayout() }
        guard let e = entries.removeValue(forKey: key) else { return }
        let right = e.corner == .topRight || e.corner == .bottomRight
        var out = e.panel.frame
        out.origin.x += (right ? 1 : -1) * 60
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            e.panel.animator().setFrame(out, display: true)
            e.panel.animator().alphaValue = 0
        }, completionHandler: {
            MainActor.assumeIsolated { e.panel.orderOut(nil) }
        })
        requestRelayout()
    }

    func closeAll() {
        for e in Array(entries.values) {
            guard let (app, id) = split(e.key) else { continue }
            close(app: app, id: id)
        }
    }

    private func split(_ key: String) -> (String, String)? {
        let p = key.components(separatedBy: "\u{1}")
        return p.count == 2 ? (p[0], p[1]) : nil
    }

    func setReminderState(app: String, id: String, _ s: ReminderState) {
        entries[Self.key(app, id)]?.model.reminderState = s
    }

    /// Shows (or clears, with nil) the "Action failed" strip on a banner. False when no such banner is up.
    @discardableResult
    func setFailureLine(app: String, id: String, _ text: String?) -> Bool {
        guard let e = entries[Self.key(app, id)] else { return false }
        e.model.failureLine = text
        relayout(animated: true)
        return true
    }

    // MARK: Snooze

    func scheduleSnooze(app: String, id: String, at date: Date) {
        let key = Self.key(app, id)
        snoozeTimers[key]?.invalidate()
        let t = Timer(fire: date, interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.snoozeTimers[key] = nil
                self?.controller.snoozeFired(app: app, id: id)
            }
        }
        RunLoop.main.add(t, forMode: .common)
        snoozeTimers[key] = t
    }

    private func cancelSnooze(_ key: String) {
        snoozeTimers.removeValue(forKey: key)?.invalidate()
    }

    // MARK: Timeouts (hover pauses)

    private func tick() {
        let mouse = NSEvent.mouseLocation
        var expired: [(String, String)] = []
        for e in entries.values {
            let hovered = e.shown && e.panel.frame.contains(mouse)
            if e.model.hovering != hovered { e.model.hovering = hovered }
            guard let rem = e.remaining, !hovered else { continue }
            e.remaining = rem - 0.25
            if e.remaining! <= 0, let pair = split(e.key) { expired.append(pair) }
        }
        for (app, id) in expired { controller.bannerExpired(app: app, id: id) }
    }
}
