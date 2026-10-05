import AppKit
import SwiftUI

final class BannerPanel: NSPanel {
    /// Banners must never take keyboard focus from the app the user is working in: the
    /// panel is non-activating AND refuses key/main status, so a click on a button or
    /// link is handled without the user's typing target changing. Nothing in a banner
    /// needs key status, except the inline reply field (`BannerCenter.setReply`): while that row is up the panel may become
    /// key, and only because the user clicked the field (`becomesKeyOnlyIfNeeded`); it never activates Herald.
    var allowsKey = false
    override var canBecomeKey: Bool { allowsKey }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class BannerEntry {
    let key: String
    let panel: BannerPanel
    let host: BannerHostingView<StackRootView>
    let model: BannerModel
    /// Arrival order (larger is newer): the order of the stack on screen, kept by `StackBook`. A banner that is
    /// delivered again inside a stack moves to the top of it, so it can change.
    var seq: Int
    /// The stack this banner is in (DESIGN section 9); nil when its issuer does not stack. `StackCenter` owns the plan.
    var stackKey: String?
    /// What the panel draws about its stack: the count, whether this card is the top, the open list.
    let stack: StackModel
    /// Under a newer card of its stack (the card on top stands for it).
    var folded = false
    /// Not on screen because the card on top of its stack is.
    var hidden = false
    /// The key of the card on top of this banner's stack (its own when it is alone).
    var topKey: String?
    var corner: HeraldCorner
    /// The display the app chose: `BannerDisplay.main` or a display id. Resolved against the connected displays
    /// whenever the stack is laid out, so a monitor that comes or goes moves its banners.
    var screen: String
    var height: CGFloat = 80
    /// The banner's width: a v2 template sets its own (`BannerModel.bannerWidth`), so it is per banner.
    var width: CGFloat = BannerView.width
    var remaining: Double?
    /// The full timeout, so the countdown starts over once an inline question has been answered.
    var timeout: Double?
    var shown = false
    var measured = false
    /// Hidden because the banners above it already fill the screen (see `BannerStackPlan`).
    var overflowed = false
    init(key: String, panel: BannerPanel, host: BannerHostingView<StackRootView>, model: BannerModel, stack: StackModel, seq: Int,
         corner: HeraldCorner, screen: String = BannerDisplay.main) {
        self.key = key; self.panel = panel; self.host = host; self.model = model; self.stack = stack; self.seq = seq
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
    /// Which banners fold together, who is on top, what is open (DESIGN section 9).
    let stacks: StackCenter
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
        // The level is the issuer's own override, else the global default; the family is its manifest's.
        stacks = StackCenter(
            level: { [unowned controller] app in
                StackKeying.level(override: controller.registry.record(for: app)?.stacking, default: controller.settings.stacking)
            },
            family: { [unowned controller] app in controller.manifests.get(app: app)?.family })
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
        stacks.installEscapeMonitor { [weak self] in self?.collapseAllStacks() }
        ticker = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(ticker!, forMode: .common)
    }

    static func key(_ app: String, _ id: String) -> String { BannerKey.make(app, id) }
    var visibleCount: Int { entries.count }

    // MARK: Show / update

    /// `promoted` puts the banner at the bottom of its stack (lazy promotion of a deferred banner: it is older
    /// than the ones on screen) instead of the top. `keepPlace` is for a banner that is only redrawn (a failure
    /// line, an "Open Reminders" button): inside a group stack it does not move to the top as a new delivery would.
    func show(_ item: HeraldHistoryItem, settings: EffectiveSettings, record: AppRecord?,
              template: HeraldTemplate? = nil, manifest: HeraldManifest? = nil, promoted: Bool = false,
              keepPlace: Bool = false) {
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
        // The stack it joins (DESIGN section 9): a banner for a key that is already up folds into that stack as its
        // top card; the same id again is replaced in place and never counts twice.
        let stackKey = stacks.stackKey(for: item)

        if let e = entries[key] {
            stacks.deliver(key, stackKey: stackKey, keepPlace: keepPlace)
            e.seq = stacks.order(of: key) ?? e.seq
            e.stackKey = stackKey
            // Template and manifest first, so the item change below redraws once with everything in place.
            e.model.template = template
            e.model.manifest = manifest
            e.model.item = item
            e.model.image = image
            e.model.icon = icon
            e.model.appName = name
            e.model.reminderState = .idle
            e.model.failureLine = nil
            // The question was about the content that is being replaced: it is cancelled, not carried over.
            controller.confirmations.drop(app: item.app, id: item.id)
            controller.dropReply(app: item.app, id: item.id)
            e.remaining = settings.timeout
            e.timeout = settings.timeout
            e.corner = settings.corner
            e.screen = settings.screen
            e.width = e.model.bannerWidth
            applyStacks()
            relayout(animated: true)
            controller.bannerShown(app: item.app, id: item.id)
            return
        }

        let model = BannerModel(item: item, appName: name, icon: icon, image: image, template: template, manifest: manifest)
        // On a closed stack's top card the close button, the snooze menu and a body click act on the whole group;
        // on a lone banner and on a row of the open list, on that notification alone.
        model.onClose = { [weak self] in self?.closePressed(app: item.app, id: item.id) }
        model.onOpen = { [weak self] in self?.openPressed(app: item.app, id: item.id) }
        #if DEBUG
        // Verification without touching the screen: a Debug build started with HERALD_DEBUG_TAP_AFTER=<seconds> clicks each
        // banner's body once, that long after it is made, so its height before and after can be read from /v1/stacks.
        if let s = ProcessInfo.processInfo.environment["HERALD_DEBUG_TAP_AFTER"], let d = Double(s) {
            DispatchQueue.main.asyncAfter(deadline: .now() + d) { [weak model] in model?.bodyClicked() }
        }
        #endif
        model.onAction = { [weak self] action, origin in self?.route(action, origin: origin, app: item.app, id: item.id) }
        model.onSnooze = { [weak self] o in self?.snoozePressed(app: item.app, id: item.id, option: o) }
        model.onExpandStack = { [weak self] in self?.setStackOpen(key: key, true) }
        model.onReminder = { [weak self] in self?.controller.userAddedReminder(app: item.app, id: item.id) }
        model.onConfirmationAnswer = { [weak self] confirmation, choice in
            self?.controller.confirmations.answer(app: item.app, id: item.id, confirmation: confirmation, choice)
        }
        model.onReplySend = { [weak self] prompt, text in self?.controller.sendReply(app: item.app, id: item.id, prompt: prompt, text: text) }
        model.onReplyCancel = { [weak self] prompt in self?.controller.cancelReply(app: item.app, id: item.id, prompt: prompt) }
        model.onRecordStop = { [weak self] p in self?.controller.stopRecording(app: item.app, id: item.id, prompt: p) }
        model.onRecordSend = { [weak self] p in self?.controller.sendRecording(app: item.app, id: item.id, prompt: p) }
        model.onRecordCancel = { [weak self] p in self?.controller.cancelRecording(app: item.app, id: item.id, prompt: p) }

        let stackModel = StackModel()
        stackModel.onExpand = { [weak self] in self?.setStackOpen(key: key, true) }
        stackModel.onCollapse = { [weak self] in self?.setStackOpen(key: key, false) }
        stackModel.onDismissAll = { [weak self] in self?.dismissStack(of: key) }
        let host = BannerHostingView(rootView: StackRootView(model: model, stack: stackModel))
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
        stacks.deliver(key, stackKey: stackKey, promoted: promoted)
        let e = BannerEntry(key: key, panel: panel, host: host, model: model, stack: stackModel,
                            seq: stacks.order(of: key) ?? 0, corner: settings.corner, screen: settings.screen)
        e.stackKey = stackKey
        e.remaining = settings.timeout
        e.timeout = settings.timeout
        // Templates differ a lot in height (a one-line banner ~44 pt, a hero ~260 pt); start from an estimate and
        // let the SwiftUI measurement below replace it. The view is the single source of truth for height.
        e.width = model.bannerWidth
        e.height = BannerView.estimatedHeight(for: model)
        entries[key] = e
        // Before the first measurement, so the card is measured with its stack's edges and counter.
        applyStacks()
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
        // The banner is up: a follow-up's timer starts now (not while quiet hours or mute held it back).
        controller.bannerShown(app: item.app, id: item.id)
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

    /// `keepBottomInside` (an open stack's list panel, whose Collapse and Dismiss all sit at its bottom edge): on a top
    /// corner the bottom edge never falls below the visible frame, even if the panel is taller than it.
    private func targetOrigin(slot: BannerSlot, offset: CGFloat, width: CGFloat, height: CGFloat,
                              keepBottomInside: Bool = false) -> NSPoint {
        let vf = BannerDisplays.visibleFrame(of: slot.screen)
        let right = slot.corner == .topRight || slot.corner == .bottomRight
        let top = slot.corner == .topRight || slot.corner == .topLeft
        let x = right ? vf.maxX - Self.margin - width : vf.minX + Self.margin
        var y = top ? vf.maxY - Self.margin - offset - height : vf.minY + Self.margin + offset
        if keepBottomInside { y = max(y, vf.minY + Self.margin) }
        #if DEBUG
        // Documentation screenshots: banners are laid out as usual but far outside every display (Debug/ScreenshotMode.swift).
        if let o = ScreenshotMode.bannerOffset { return NSPoint(x: x + o.x, y: y + o.y) }
        // A development instance checked end to end (HERALD_DEBUG_OFFSCREEN_BANNERS=1): the same layout, far outside every
        // display, so nothing appears on the screen of the person using the Mac.
        if ProcessInfo.processInfo.environment["HERALD_DEBUG_OFFSCREEN_BANNERS"] == "1" {
            return NSPoint(x: x + ShotKit.far.x, y: y + ShotKit.far.y)
        }
        #endif
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
        // The stacking level (the bell menu, Settings > Apps) or an issuer's family may have changed: re-key the
        // banners that are up, so they fold or unfold under the new rule.
        var dirty = regroupStacks()
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
        // Who is on top of which stack, and which cards another one stands for (hidden ones take no room).
        applyStacks()
        var slots = Set(entries.values.filter { !$0.hidden }.map { slot(of: $0, connected: connected) })
        slots.formUnion(deferred.slots)
        slots.formUnion(stubs.keys)
        slots.formUnion(freed.keys)
        for slotKey in slots {
            let vf = BannerDisplays.visibleFrame(of: slotKey.screen)
            let available = max(0, vf.height - 2 * Self.margin)
            let onStack = entries.values.filter { !$0.hidden && slot(of: $0, connected: connected) == slotKey }
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
                let origin = targetOrigin(slot: slotKey, offset: plan.offsets[index], width: e.width, height: e.height,
                                          keepBottomInside: e.stack.expanded)
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
        // A question open on a banner that goes away is cancelled (nothing runs, nothing is remembered). Last, so
        // the entry is already gone and clearing the row does not lay the stack out a second time.
        defer { controller.confirmations.drop(app: app, id: id); controller.dropReply(app: app, id: id) }
        cancelSnooze(key)
        let wasDeferred = deferred.remove(key)
        guard let e = entries.removeValue(forKey: key) else {
            if wasDeferred { requestRelayout() }
            return
        }
        // The stack it was in loses a member; the card under it comes up if it was the top.
        let removal = stacks.remove(key)
        // A banner that was on screen leaves a place on its stack; the oldest deferred banner of that stack takes it
        // (unless banners that did not fit are still waiting: they are older and come first). A card whose stack
        // still has other members leaves no place: the next one takes its spot.
        let connected = BannerDisplays.connectedIDs
        let freedSlot = slot(of: e, connected: connected)
        if e.shown, !e.overflowed, (removal?.remaining ?? 0) == 0, deferred.count(in: freedSlot) > 0,
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
        applyStacks()
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

    /// Redraws a banner that is up with the item as History now holds it (a follow-up's line). False when none is up.
    @discardableResult
    func updateItem(_ item: HeraldHistoryItem) -> Bool {
        guard let e = entries[Self.key(item.app, item.id)] else { return false }
        e.model.item = item
        relayout(animated: true)
        return true
    }

    /// Shows (or clears, with nil) the "Action failed" strip on a banner. False when no such banner is up.
    @discardableResult
    func setFailureLine(app: String, id: String, _ text: String?) -> Bool {
        guard let e = entries[Self.key(app, id)] else { return false }
        e.model.failureLine = text
        relayout(animated: true)
        return true
    }

    // MARK: Inline confirmations

    /// Puts a question on a banner (or takes it off with nil) and lays the stack out again: the row replaces the
    /// actions row and is usually taller. False when no such banner is up. Never touches the panel's key state.
    @discardableResult
    func setConfirmation(app: String, id: String, _ confirmation: BannerConfirmation?) -> Bool {
        guard let e = entries[Self.key(app, id)] else { return false }
        let wasAsking = e.model.confirmation != nil
        e.model.confirmation = confirmation
        // A banner that is asking does not count down (see `tick`); the countdown starts over once it is answered.
        if wasAsking && confirmation == nil { e.remaining = e.timeout }
        relayout(animated: true)
        return true
    }

    // MARK: Inline reply

    /// Puts the reply field on a banner (or takes it off with nil) in place of the actions row. For as long as it is up the
    /// panel may become key, so a click in the field can take typing; it still never activates Herald and never becomes key
    /// by itself. When the row goes the panel gives key status up again. False when no such banner is up.
    @discardableResult
    func setReply(app: String, id: String, _ prompt: BannerReplyPrompt?) -> Bool {
        guard let e = entries[Self.key(app, id)] else { return false }
        let wasReplying = e.model.reply != nil
        e.model.reply = prompt
        e.panel.allowsKey = prompt != nil
        if prompt == nil {
            if e.panel.isKeyWindow { e.panel.makeFirstResponder(nil); e.panel.resignKey() }
            // A banner that was being answered counts down again from the start.
            if wasReplying { e.remaining = e.timeout }
        }
        relayout(animated: true)
        return true
    }

    // MARK: Inline record strip

    /// Puts the record strip on a banner (or takes it off with nil) in place of the actions row. It needs no key status: its
    /// buttons are clickable on the non-activating panel. A banner that was being answered counts down again from the start.
    @discardableResult
    func setRecord(app: String, id: String, _ prompt: BannerRecordPrompt?) -> Bool {
        guard let e = entries[Self.key(app, id)] else { return false }
        let wasRecording = e.model.record != nil
        let heightMayChange = e.model.record?.phase != prompt?.phase
        e.model.record = prompt
        if prompt == nil, wasRecording { e.remaining = e.timeout }
        if heightMayChange { relayout(animated: true) }   // the elapsed counter ticks without a layout
        return true
    }

    // MARK: Stacks (DESIGN section 9)

    /// Pushes the stack plan onto the banners: which card is on top, how many it stands for, what is open and which
    /// cards are hidden under another. Cheap; it runs whenever a banner comes or goes, a stack opens or closes, and at
    /// the start of every layout. A banner only changes what it publishes when the value changed, so a view is not
    /// redrawn for nothing.
    private func applyStacks() {
        let plan = stacks.book.plan()
        let connected = BannerDisplays.connectedIDs
        // The tallest an open list may be on each display: what its slot leaves under the margins, the footer and the gap.
        var listCaps: [String: CGFloat] = [:]
        for e in entries.values {
            let stack = plan.stack(containing: e.key)
            let count = stack?.count ?? 1
            let top = stack?.top ?? e.key
            let isTop = top == e.key
            let open = isTop && count > 1 && stacks.isExpanded(stackKey: e.stackKey)
            e.topKey = top
            e.folded = count > 1 && !isTop
            // A card under another waits for the one on top to be measured, so it can slide in, before it leaves the
            // screen: a stack never blinks off.
            e.hidden = e.folded && (entries[top]?.measured ?? true)
            if e.hidden {
                if e.shown || e.panel.isVisible { e.panel.orderOut(nil) }
                e.shown = false
            }
            // A card that is only a row of the open list, or under another card, is a plain banner.
            let cardCount = (isTop && !open) ? count : 1
            if e.model.stackCount != cardCount { e.model.stackCount = cardCount }
            if e.stack.count != count { e.stack.count = count }
            if e.stack.isTop != isTop { e.stack.isTop = isTop }
            if e.stack.expanded != open { e.stack.expanded = open }
            let right = e.corner == .topRight || e.corner == .bottomRight
            if e.stack.trailing != right { e.stack.trailing = right }
            let screen = slot(of: e, connected: connected).screen
            let cap = listCaps[screen] ?? StackListLayout.cap(
                available: max(0, BannerDisplays.visibleFrame(of: screen).height - 2 * Self.margin))
            listCaps[screen] = cap
            if e.stack.maxListHeight != cap { e.stack.maxListHeight = cap }
            var members: [StackListMember] = []
            if isTop, count > 1, let stack {
                members = stack.members.compactMap { k in entries[k].map { StackListMember(id: k, model: $0.model) } }
            }
            if !Self.same(e.stack.members, members) { e.stack.members = members }
            if open {
                let width = members.map(\.model.bannerWidth).max() ?? e.model.bannerWidth
                if e.stack.width != width { e.stack.width = width }
                e.width = width
            } else {
                e.width = e.model.bannerWidth
            }
        }
    }

    private static func same(_ a: [StackListMember], _ b: [StackListMember]) -> Bool {
        a.count == b.count && zip(a, b).allSatisfy { $0.id == $1.id && $0.model === $1.model }
    }

    /// A stack's countdown is held while its card is hovered or its list is open (hidden members follow the card).
    private func stackHeld(_ e: BannerEntry, mouse: NSPoint) -> Bool {
        if stacks.isExpanded(stackKey: e.stackKey) { return true }
        guard e.hidden, let top = e.topKey, let t = entries[top] else { return false }
        return t.shown && t.panel.frame.contains(mouse)
    }

    /// Re-keys the banners that are up under the level and family that apply now. True when any changed stack.
    private func regroupStacks() -> Bool {
        let moved = stacks.regroup { [unowned self] key in self.entries[key].flatMap { self.stacks.stackKey(for: $0.model.item) } }
        if moved { for e in entries.values { e.stackKey = stacks.book.stackKey(of: e.key) } }
        return moved
    }

    /// Opens or closes the stack `key` is in, in place: the top card's panel grows into the list or shrinks back.
    /// Nothing here activates Herald or makes a panel key (DESIGN section 8).
    func setStackOpen(key: String, _ open: Bool) {
        guard let stackKey = entries[key]?.stackKey else { return }
        stacks.setExpanded(stackKey: stackKey, open)
        applyStacks()
        relayout(animated: true)
    }

    /// Esc, while a Herald window has the key: every open stack closes.
    func collapseAllStacks() {
        let open = stacks.book.expandedStacks
        guard !open.isEmpty else { return }
        for k in open { stacks.setExpanded(stackKey: k, false) }
        applyStacks()
        relayout(animated: true)
    }

    /// "Dismiss all" of an open stack: every member of the stack `key` is in.
    private func dismissStack(of key: String) {
        guard let stackKey = entries[key]?.stackKey else { return }
        controller.dismissMembers(stacks.book.members(ofStack: stackKey).compactMap(BannerKey.split))
    }

    /// The card's close button. On a closed stack's top card it dismisses the whole group (each member goes to
    /// History as dismissed); anywhere else, the one notification.
    private func closePressed(app: String, id: String) {
        if let group = stacks.closedGroup(topKey: Self.key(app, id)) {
            controller.dismissMembers(group.compactMap(BannerKey.split))
        } else {
            controller.userClosed(app: app, id: id)
        }
    }

    /// A click on a banner's body. A closed stack's top card that has no link of its own opens the stack instead of
    /// going nowhere; everything else opens the notification's url.
    private func openPressed(app: String, id: String) {
        let key = Self.key(app, id)
        if stacks.closedGroup(topKey: key) != nil, controller.history.item(app: app, id: id)?.notification.url?.isEmpty != false {
            setStackOpen(key: key, true)
            return
        }
        controller.userOpened(app: app, id: id)
    }

    /// The snooze menu. On a closed stack's top card it snoozes the group, which comes back as the same stack.
    private func snoozePressed(app: String, id: String, option: SnoozeOption) {
        let key = Self.key(app, id)
        if stacks.closedGroup(topKey: key) != nil {
            controller.userSnoozedGroup(members: stacks.restoreOrder(of: key).compactMap(BannerKey.split), option: option)
        } else {
            controller.userSnoozed(app: app, id: id, option: option)
        }
    }

    /// The live stacks, for `GET /v1/stacks`: every group of banners that is up, newest member first.
    func stackInfos(app: String?) -> [HeraldStackInfo] {
        stacks.infos(app: app, item: { [weak self] key in self?.entries[key]?.model.item }, frame: { [weak self] key in
            guard let e = self?.entries[key], e.shown else { return nil }
            let f = e.panel.frame
            return HeraldStackInfo.Frame(x: f.minX, y: f.minY, width: f.width, height: f.height)
        })
    }

    /// `POST /v1/stacks/expand`: opens or closes the stack that holds a notification of `app` sent with `group`, the
    /// same as the badge and the Collapse button do (no UI to drive for a test or an agent). False when no such
    /// stack with two or more notifications is up.
    func setStackOpen(app: String, group: String, _ open: Bool) -> Bool {
        for stack in stacks.book.plan().stacks where stack.count > 1 {
            let match = stack.members.contains { key in
                guard let item = entries[key]?.model.item else { return false }
                return item.app == app && StackKeying.effectiveGroup(app: item.app, group: item.notification.group) == group
            }
            if match { setStackOpen(key: stack.top, open); return true }
        }
        return false
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
            // A stack counts down as one: hovering its card or having it open holds every member, hidden ones too.
            guard let rem = e.remaining, !hovered, !stackHeld(e, mouse: mouse), e.model.confirmation == nil, e.model.reply == nil, e.model.record == nil else { continue }
            e.remaining = rem - 0.25
            if e.remaining! <= 0, let pair = split(e.key) { expired.append(pair) }
        }
        for (app, id) in expired { controller.bannerExpired(app: app, id: id) }
    }
}

extension BannerCenter: ConfirmationSurface {
    func presentConfirmation(_ confirmation: BannerConfirmation, app: String, id: String) -> Bool {
        setConfirmation(app: app, id: id, confirmation)
    }

    func clearConfirmation(app: String, id: String) {
        setConfirmation(app: app, id: id, nil)
    }
}

#if DEBUG
extension BannerCenter {
    /// For the HERALD_SCREENSHOTS launch mode (Debug/ScreenshotMode.swift).
    func debugPanel(app: String, id: String) -> NSWindow? { entries[Self.key(app, id)]?.panel }
    func debugModel(app: String, id: String) -> BannerModel? { entries[Self.key(app, id)]?.model }
}
#endif
