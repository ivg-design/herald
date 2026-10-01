import AppKit
import SwiftUI

final class BannerPanel: NSPanel {
    /// Banners must never take keyboard focus from the app the user is working in: the
    /// panel is non-activating AND refuses key/main status, so a click on a button or
    /// link is handled without the user's typing target changing. Nothing in a banner
    /// needs key status (there are no text fields).
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class BannerEntry {
    let key: String
    let panel: BannerPanel
    let host: BannerHostingView<BannerView>
    let model: BannerModel
    let seq: Int
    var corner: HeraldCorner
    /// The display the app chose: `BannerDisplay.main` or a display id. Resolved against the connected displays
    /// whenever the stack is laid out, so a monitor that comes or goes moves its banners.
    var screen: String
    var height: CGFloat = 80
    /// The banner's width: a v2 template sets its own (`BannerModel.bannerWidth`), so it is per banner.
    var width: CGFloat = BannerView.width
    var remaining: Double?
    var shown = false
    var measured = false
    /// Hidden because the banners above it already fill the screen (see `BannerStackPlan`).
    var overflowed = false
    init(key: String, panel: BannerPanel, host: BannerHostingView<BannerView>, model: BannerModel, seq: Int,
         corner: HeraldCorner, screen: String = BannerDisplay.main) {
        self.key = key; self.panel = panel; self.host = host; self.model = model; self.seq = seq
        self.corner = corner; self.screen = screen
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
    private var stubs: [BannerSlot: OverflowStub] = [:]
    /// Banners that exist only in History (not restored to a panel at launch, or held back by quiet hours) and
    /// are counted by the pill. The oldest of a stack comes back when a banner of that stack is dismissed.
    private var deferred = DeferredBanners()
    /// Places freed on a stack by dismissals that no promotion has used yet (lazy promotion, issue #25).
    private var freed: [BannerSlot: Int] = [:]
    private var settingsObserver: NSObjectProtocol?

    /// Handles a pressed action other than dismiss, the snooze menu and Add to Reminders: url, callback,
    /// command, script and shortcut actions, whether the issuer sent them or the template added them (`origin`
    /// says which). Arguments are the banner's app and id. While nil, url, callback and command actions run as
    /// v1 buttons did and the rest are ignored.
    var actionHandler: ((_ app: String, _ id: String, _ action: HeraldAction, _ origin: HeraldActionOrigin) -> Void)?

    init(controller: AppController) {
        self.controller = controller
        // A monitor that comes or goes changes the visible frame; banners would otherwise stay where the old
        // frame put them, possibly off the screen.
        let reflow: @Sendable (Notification) -> Void = { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshPlacement(animated: false) }
        }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main, using: reflow)
        // The per-app display, corner and mute settings (Settings > Apps) post this when they change.
        settingsObserver = NotificationCenter.default.addObserver(
            forName: .heraldChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshPlacement(animated: true) }
        }
        ticker = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(ticker!, forMode: .common)
    }

    static func key(_ app: String, _ id: String) -> String { app + "\u{1}" + id }
    var visibleCount: Int { entries.count }

    // MARK: Show / update

    /// `promoted` puts the banner at the bottom of its stack (lazy promotion of a deferred banner: it is older
    /// than the ones on screen) instead of the top.
    func show(_ item: HeraldHistoryItem, settings: EffectiveSettings, record: AppRecord?,
              template: HeraldTemplate? = nil, manifest: HeraldManifest? = nil, promoted: Bool = false) {
        let key = Self.key(item.app, item.id)
        // The user turned this app's banners off (issue #28): no panel. The notification is already in History,
        // unread; a banner of the same id that is up (it was muted while showing) goes away without being dismissed.
        if settings.mutedBanners || record?.mutedBanners == true {
            cancelSnooze(key)
            if deferred.remove(key) { requestRelayout() }
            if entries[key] != nil { close(app: item.app, id: item.id) }
            return
        }
        // What a banner draws besides its notification is looked up where the controller keeps it, so every show
        // (a new notification, a snooze coming back, a restore at launch, a failure line) draws the same banner.
        let template = template ?? storedTemplate(for: item)
        let manifest = manifest ?? controller.manifests.get(app: item.app)
        cancelSnooze(key)
        deferred.remove(key)
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
            e.screen = settings.screen
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

        let host = BannerHostingView(rootView: BannerView(model: model))
        let panel = BannerPanel(contentRect: NSRect(x: 0, y: 0, width: model.bannerWidth, height: 80),
                                styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true   // belt and braces with canBecomeKey == false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.contentView = host

        // New banners go on top of their stack; a promoted one is older than everything on screen, so it goes below.
        let seq: Int
        if promoted { seq = (entries.values.map(\.seq).min() ?? 1) - 1 } else { seqCounter += 1; seq = seqCounter }
        let e = BannerEntry(key: key, panel: panel, host: host, model: model, seq: seq, corner: settings.corner,
                            screen: settings.screen)
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
        let vf = BannerDisplays.visibleFrame(of: nil)
        panel.alphaValue = 0
        panel.setFrame(NSRect(x: BannerDisplays.parkingX, y: vf.maxY - 200, width: e.width, height: e.height), display: false)
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

    /// The stack a banner is on: its app's display (the primary one when that is not connected) and corner.
    private func slot(of e: BannerEntry, connected: [String]) -> BannerSlot {
        BannerSlot(screen: BannerDisplay.resolve(e.screen, connected: connected), corner: e.corner)
    }

    /// Where a banner that has no panel (a deferred one) would go: its app's own settings, else `fallback`.
    private func slot(forKey key: String, fallback: HeraldCorner, connected: [String]) -> BannerSlot {
        let rec = split(key).flatMap { controller.registry.record(for: $0.0) }
        return BannerSlot.resolve(screen: rec?.screen, corner: rec?.corner ?? rec?.registration.defaults?.corner ?? fallback,
                                  connected: connected)
    }

    private func isMuted(key: String) -> Bool {
        split(key).flatMap { controller.registry.record(for: $0.0) }?.mutedBanners == true
    }

    private func targetOrigin(slot: BannerSlot, offset: CGFloat, width: CGFloat, height: CGFloat) -> NSPoint {
        let vf = BannerDisplays.visibleFrame(of: slot.screen)
        let right = slot.corner == .topRight || slot.corner == .bottomRight
        let top = slot.corner == .topRight || slot.corner == .topLeft
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

    /// Re-reads where every app wants its banners (display, corner, muted: Settings > Apps) and which displays
    /// are connected, moves what moved and lays out again. Cheap when nothing changed.
    func refreshPlacement(animated: Bool) {
        let connected = BannerDisplays.connectedIDs
        var dirty = false
        for e in Array(entries.values) {
            guard let (app, id) = split(e.key) else { continue }
            let rec = controller.registry.record(for: app)
            if rec?.mutedBanners == true { close(app: app, id: id); dirty = true; continue }
            let corner = rec?.corner ?? rec?.registration.defaults?.corner ?? .topRight
            let screen = rec?.screen ?? BannerDisplay.main
            if corner != e.corner || screen != e.screen { e.corner = corner; e.screen = screen; dirty = true }
        }
        for key in deferred.keys where isMuted(key: key) { deferred.remove(key); dirty = true }
        if deferred.reslot({ slot(forKey: $0, fallback: .topRight, connected: connected) }) { dirty = true }
        // `animated: false` is a display that came or went: the slots changed even though no setting did.
        if dirty || !animated { relayout(animated: animated) }
    }

    func relayout(animated: Bool) {
        let connected = BannerDisplays.connectedIDs
        var slots = Set(entries.values.map { slot(of: $0, connected: connected) })
        slots.formUnion(deferred.slots)
        slots.formUnion(stubs.keys)
        slots.formUnion(freed.keys)
        for slotKey in slots {
            let vf = BannerDisplays.visibleFrame(of: slotKey.screen)
            let available = max(0, vf.height - 2 * Self.margin)
            let onStack = entries.values.filter { slot(of: $0, connected: connected) == slotKey }
            let group = onStack.filter(\.measured).sorted { $0.seq > $1.seq }
            var deferredHere = deferred.count(in: slotKey)
            let plan = BannerStackPlan.make(heights: group.map(\.height), available: available, gap: Self.gap,
                                            stubHeight: Self.stubHeight,
                                            // While this stack's banners are still being measured there is nothing to attach the pill to.
                                            forceStub: deferredHere > 0 && (!group.isEmpty || onStack.isEmpty))
            for (index, e) in group.enumerated() {
                guard index < plan.visibleCount else {
                    // No room: the panel stays hidden until a banner above it goes away.
                    e.overflowed = true
                    if e.shown || e.panel.isVisible { e.panel.orderOut(nil) }
                    e.shown = false
                    continue
                }
                e.overflowed = false
                let origin = targetOrigin(slot: slotKey, offset: plan.offsets[index], width: e.width, height: e.height)
                let frame = NSRect(origin: origin, size: NSSize(width: e.width, height: e.height))
                if !e.shown {
                    e.shown = true
                    let right = slotKey.corner == .topRight || slotKey.corner == .bottomRight
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
            // Lazy promotion (issue #25): a dismissal freed a place on this stack, so the oldest banner that was
            // left in History takes it, once the stack is measured and really has room.
            if let n = freed[slotKey], n > 0 {
                switch BannerPromotion.decide(freed: n, deferred: deferredHere, unmeasured: onStack.count - group.count,
                                              overflow: plan.overflow) {
                case .promote:
                    freed[slotKey] = n - 1
                    promoteOldest(in: slotKey)
                    deferredHere = deferred.count(in: slotKey)
                case .wait:
                    break
                case .stop:
                    freed[slotKey] = nil
                }
            } else if freed[slotKey] != nil {
                freed[slotKey] = nil
            }
            updateStub(slot: slotKey, offset: plan.stubOffset, count: plan.overflow + deferredHere)
        }
    }

    /// Shows the oldest deferred banner of `slot` below the ones on screen. A banner that has meanwhile been
    /// dismissed, snoozed or muted, or that quiet hours still hold back, is not shown (the first three are dropped
    /// from the deferred list; quiet hours end the promotion and keep it).
    private func promoteOldest(in slot: BannerSlot) {
        while let next = deferred.oldest(in: slot) {
            guard let (app, id) = split(next.key) else { deferred.remove(next.key); continue }
            guard let item = controller.history.item(app: app, id: id), item.dismissedAt == nil, item.snoozedUntil == nil,
                  !isMuted(key: next.key) else { deferred.remove(next.key); continue }
            let quiet = QuietHoursCoordinator.shared.state(for: item.notification)
            if quiet.active && quiet.banners { freed[slot] = nil; return }
            let record = controller.registry.record(for: app)
            show(item, settings: EffectiveSettings.resolve(item.notification, record), record: record, promoted: true)
            return
        }
    }

    private func updateStub(slot: BannerSlot, offset: CGFloat?, count: Int) {
        guard let offset, count > 0 else {
            if let stub = stubs[slot], stub.panel.isVisible { stub.panel.orderOut(nil) }
            return
        }
        let stub: OverflowStub
        if let existing = stubs[slot] { stub = existing } else {
            stub = OverflowStub()
            stub.model.onHistory = { [weak self] in self?.controller.openHistory?() }
            stub.model.onDismissAll = { [weak self] in self?.controller.dismissAll(app: nil) }
            stubs[slot] = stub
        }
        let width = stub.update(count: count)
        let right = slot.corner == .topRight || slot.corner == .bottomRight
        let vf = BannerDisplays.visibleFrame(of: slot.screen)
        let top = slot.corner == .topRight || slot.corner == .topLeft
        let x = right ? vf.maxX - Self.margin - width : vf.minX + Self.margin
        let y = top ? vf.maxY - Self.margin - offset - Self.stubHeight : vf.minY + Self.margin + offset
        stub.panel.setFrame(NSRect(x: x, y: y, width: width, height: Self.stubHeight), display: true)
        stub.panel.alphaValue = 1
        stub.panel.orderFrontRegardless()
    }

    /// Banners that were left without a panel (see `AppController.restoreBanners`). They stay undismissed in
    /// History; the pill counts them until they are dismissed, and the oldest of a stack comes back when one of
    /// that stack's banners is dismissed. `keys` are oldest first. A muted app's banners are not counted.
    func deferBanners(keys: [String], corner: HeraldCorner = .topRight) {
        let connected = BannerDisplays.connectedIDs
        deferred = DeferredBanners()
        for k in keys where !isMuted(key: k) { deferred.add(k, slot: slot(forKey: k, fallback: corner, connected: connected)) }
        requestRelayout()
    }

    /// A banner held back by quiet hours: no panel, but History keeps it unread and the "+N more" pill counts it
    /// until it is dismissed (like banners left without a panel at launch). A muted app's banner is not counted.
    func deferBanner(key: String, corner: HeraldCorner) {
        guard !isMuted(key: key) else { return }
        deferred.add(key, slot: slot(forKey: key, fallback: corner, connected: BannerDisplays.connectedIDs))
        requestRelayout()
    }

    // MARK: Removal

    /// Removes the banner (animated) and cancels any pending snooze. Does not touch history.
    func close(app: String, id: String) {
        let key = Self.key(app, id)
        cancelSnooze(key)
        let wasDeferred = deferred.remove(key)
        guard let e = entries.removeValue(forKey: key) else {
            if wasDeferred { requestRelayout() }
            return
        }
        // A banner that was on screen leaves a place on its stack; the oldest deferred banner of that stack takes it
        // (unless banners that did not fit are still waiting: they are older and come first).
        let connected = BannerDisplays.connectedIDs
        let freedSlot = slot(of: e, connected: connected)
        if e.shown, !e.overflowed, deferred.count(in: freedSlot) > 0,
           !entries.values.contains(where: { slot(of: $0, connected: connected) == freedSlot && $0.overflowed }) {
            freed[freedSlot, default: 0] += 1
        }
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
