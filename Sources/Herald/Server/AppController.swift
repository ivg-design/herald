import AppKit
import Foundation

/// Adapter that lets the (nonisolated) router call into the main-actor controller.
final class BackendAdapter: HeraldBackend, @unchecked Sendable {
    private let controller: AppController
    init(_ c: AppController) { controller = c }
    func notify(_ n: HeraldNotification) async throws -> String { try await controller.notify(n) }
    func register(_ r: HeraldAppRegistration) async throws { try await controller.register(r) }
    func dismiss(app: String, id: String) async throws { await controller.dismissItem(app: app, id: id, action: nil) }
    func dismissAll(app: String?) async throws { await controller.dismissAll(app: app) }
    func history(app: String?, limit: Int) async throws -> [HeraldHistoryItem] { await controller.historyItems(app: app, limit: limit) }
    func clearHistory(app: String?) async throws { await controller.clearHistory(app: app) }
    func apps() async throws -> [HeraldAppRegistration] { await controller.registeredApps() }
    func templates(app: String?) async throws -> [HeraldTemplate] { await controller.templateList(app: app) }
    func putTemplate(_ t: HeraldTemplate) async throws { try await controller.putTemplate(t) }
    func deleteTemplate(app: String, name: String) async throws { try await controller.deleteTemplate(app: app, name: name) }
    func compose() async throws { await controller.requestCompose() }
    func manifests() async throws -> [HeraldManifest] { await controller.manifestList() }
    func manifest(app: String) async throws -> HeraldManifest? { await controller.manifest(app: app) }
    func putManifest(_ m: HeraldManifest) async throws { try await controller.putManifest(m) }
    func deleteManifest(app: String) async throws { try await controller.deleteManifest(app: app) }
    func shortcuts() async throws -> [String] { try await controller.shortcutNames() }
}

@MainActor
final class AppController {
    static let shared = AppController()
    /// Set by the app delegate: opens the Composer window (`POST /v1/compose`, i.e. `herald compose`).
    var openComposer: (() -> Void)?
    func requestCompose() { openComposer?() }
    /// Set by the app delegate: opens the History window (the "+N more" pill uses it).
    var openHistory: (() -> Void)?

    static var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0" }

    let supportDirectory = HeraldPaths.defaultSupportDirectory
    let history: HistoryStore
    let templates: TemplateStore
    let manifests: ManifestStore
    let registry: AppRegistry
    let settings = AppSettings.shared
    let sounds = SoundPlayer()
    let reminders = ReminderService()
    private(set) var banners: BannerCenter!
    private var listener: HTTPLoopbackListener?
    private var token = ""
    private(set) var serverStatus = "Not started"
    private(set) var serverRunning = false

    private init() {
        history = HistoryStore(directory: supportDirectory.appendingPathComponent("history", isDirectory: true))
        templates = TemplateStore(directory: supportDirectory.appendingPathComponent("templates", isDirectory: true))
        manifests = ManifestStore(directory: supportDirectory.appendingPathComponent("manifests", isDirectory: true))
        registry = AppRegistry(file: supportDirectory.appendingPathComponent("apps.json"))
        banners = BannerCenter(controller: self)
    }

    var muted: Bool {
        get { settings.muted }
        set { settings.muted = newValue; changed() }
    }

    func start() {
        do { token = try TokenStore.loadOrCreate(in: supportDirectory) }
        catch { serverStatus = "Cannot create token: \(error.localizedDescription)"; return }
        startServer()
        restoreBanners()
        changed()
    }

    func startServer() {
        listener?.stop(); listener = nil; serverRunning = false
        let router = Router(token: token, backend: BackendAdapter(self), version: Self.version)
        // /v1/snooze and /v1/unsnooze are answered ahead of the router (see SnoozeRoutes); everything else falls through to it.
        let handler = SnoozeRoutes.handler(token: token, backend: BackendAdapter(self)) { await router.handle($0) }
        // The token is checked on the request head too, so an unauthenticated caller is turned away before
        // any of its body is buffered (the router still checks it again).
        let l = HTTPLoopbackListener(port: settings.effectivePort, headCheck: BearerAuth.headCheck(token: token), handler: handler)
        do {
            try l.start()
            listener = l
            try TokenStore.writePort(l.port, in: supportDirectory)
            serverRunning = true
            serverStatus = "Listening on 127.0.0.1:\(l.port)"
        } catch {
            serverStatus = "Server failed on port \(settings.effectivePort): \(error.localizedDescription)"
        }
        changed()
    }

    func stop() {
        listener?.stop()
        try? FileManager.default.removeItem(at: HeraldPaths.portURL(in: supportDirectory))
    }

    func changed() { NotificationCenter.default.post(name: .heraldChanged, object: nil) }

    var unreadCount: Int { history.unreadCount() }

    // MARK: Backend operations

    func notify(_ n: HeraldNotification) async throws -> String {
        // Resolve the named template before anything else (DESIGN section 6), so history, banner and
        // sound all see the final payload. An unknown template name is not fatal while the payload
        // has its own title: dropping a notification is worse than losing its styling.
        // The issuer's manifest (DESIGN section 7.1) can name a default template for payloads that name none.
        let manifest = manifests.get(app: n.app)
        var named = n
        if named.template?.isEmpty != false, let fallback = manifest?.defaultTemplate, !fallback.isEmpty,
           templates.get(app: n.app, name: fallback) != nil {
            named.template = fallback
        }
        let template = templates.template(for: named)
        if template == nil, let name = named.template, !name.isEmpty { log("template \(name) not found for \(n.app)") }
        let n = TemplateResolver.resolve(named, with: template)
        guard !n.app.isEmpty else { throw BackendError(400, "app is required") }
        guard !n.title.isEmpty else {
            throw BackendError(400, n.template == nil ? "title is required" : "title is required (template \(n.template ?? "") has none or does not exist)")
        }
        // Size limits come before anything is stored: a record, a cached image or a history entry.
        try PayloadLimits.validate(n)
        guard registry.hasRoom(for: n.app) else { throw BackendError(429, "too many apps (at most \(AppRegistry.maxApps))") }
        var note = n
        let id = (n.id?.isEmpty == false) ? n.id! : UUID().uuidString
        note.id = id
        // Caching the image suspends this call. A newer notify or a dismiss for the same id that runs meanwhile
        // supersedes it, and the stale one is dropped when it resumes instead of overwriting or resurrecting.
        let key = BannerCenter.key(n.app, id)
        let ticket = pendingNotifies.begin(key)
        defer { pendingNotifies.finish(key, ticket) }
        let record = registry.ensure(n.app)
        var imagePath: String?
        if let spec = n.image, !spec.isEmpty { imagePath = await history.cacheImage(spec) }
        guard pendingNotifies.isCurrent(key, ticket) else { return id }
        // What a grid template binds to: payload fields, then metadata (the manifest's samples are for the designer only).
        let fields = TemplateResolver.fields(for: note, manifest: manifest)
        let item = HeraldHistoryItem(id: id, app: n.app, notification: note, deliveredAt: Date(), imagePath: imagePath, fields: fields)
        history.upsert(item)
        let eff = EffectiveSettings.resolve(note, record)
        banners.show(item, settings: eff, record: record)
        playSound(eff, record: record)
        changed()
        return id
    }

    func register(_ r: HeraldAppRegistration) throws {
        try PayloadLimits.validate(r)
        guard registry.hasRoom(for: r.app) else { throw BackendError(429, "too many apps (at most \(AppRegistry.maxApps))") }
        registry.register(r)
        AppIcons.invalidate()
        changed()
    }

    /// `supersedePending: false` is for the auto-dismiss timeout, which must not cancel an update of the same
    /// notification that is still being prepared (it restarts the banner's timeout anyway).
    func dismissItem(app: String, id: String, action: String?, notify: Bool = true, supersedePending: Bool = true) {
        if supersedePending { pendingNotifies.invalidate(BannerCenter.key(app, id)) }
        cancelFlash(BannerCenter.key(app, id))
        history.update(app: app, id: id) { item in
            // The first way an item was dismissed is the one History records; a late click or a repeated
            // dismiss must not rewrite it.
            if item.dismissedAt == nil {
                item.dismissedAt = Date()
                if let action { item.actionUsed = action }
            }
            item.snoozedUntil = nil
        }
        banners.close(app: app, id: id)
        if notify { changed() }
    }

    /// One `changed()` for the whole sweep: each one refreshes the menu bar and re-reads history.
    func dismissAll(app: String?) {
        pendingNotifies.invalidateAll(prefix: app.map { $0 + "\u{1}" })
        for item in history.undismissed() where app == nil || item.app == app {
            dismissItem(app: item.app, id: item.id, action: nil, notify: false)
        }
        changed()
    }

    func historyItems(app: String?, limit: Int) -> [HeraldHistoryItem] {
        if let app { return history.items(app: app, limit: limit) }
        return history.allItems(limit: limit)
    }

    func clearHistory(app: String?) {
        pendingNotifies.invalidateAll(prefix: app.map { $0 + "\u{1}" })
        for a in app.map({ [$0] }) ?? history.apps() {
            for item in history.items(app: a) { banners.close(app: a, id: item.id) }
            history.clear(app: a)
        }
        changed()
    }

    func registeredApps() -> [HeraldAppRegistration] { registry.all().map(\.registration) }

    // MARK: Templates

    func templateList(app: String?) -> [HeraldTemplate] { templates.list(app: app) }

    func putTemplate(_ t: HeraldTemplate) throws {
        guard templates.put(t) else { throw BackendError(500, "could not save template \(t.name)") }
        changed()
    }

    func deleteTemplate(app: String, name: String) throws {
        guard templates.delete(app: app, name: name) else { throw BackendError(404, "template not found") }
        changed()
    }

    // MARK: Manifests and Shortcuts

    func manifestList() -> [HeraldManifest] { manifests.list() }

    func manifest(app: String) -> HeraldManifest? { manifests.get(app: app) }

    /// Stores the issuer's manifest. The app also gets the manifest's name and icon, unless it registered
    /// its own (`POST /v1/register` always wins), so an issuer that only sends a manifest still shows up
    /// under its real name in Settings, History and on banners.
    func putManifest(_ m: HeraldManifest) throws {
        guard manifests.hasRoom(for: m.app) else { throw BackendError(429, "too many manifests (at most \(ManifestStore.maxManifests))") }
        guard registry.hasRoom(for: m.app) else { throw BackendError(429, "too many apps (at most \(AppRegistry.maxApps))") }
        guard manifests.put(m) else { throw BackendError(500, "could not save manifest \(m.app)") }
        let own = registry.record(for: m.app)?.registration
        let name = own?.appName == nil && m.appName != m.app ? m.appName : nil
        let icon = own?.icon == nil ? m.icon : nil
        if own == nil || name != nil || icon != nil {
            registry.register(HeraldAppRegistration(app: m.app, appName: name, icon: icon))
            AppIcons.invalidate()
        }
        changed()
    }

    func deleteManifest(app: String) throws {
        guard manifests.delete(app: app) else { throw BackendError(404, "manifest not found") }
        changed()
    }

    /// Installed Shortcuts, by name (`GET /v1/shortcuts`). A slow or missing `shortcuts` tool is a gateway
    /// problem, not a bad request.
    func shortcutNames() async throws -> [String] {
        do { return try await ShortcutsCatalog.shared.names() }
        catch let e as ShortcutsError {
            if case .timedOut = e { throw BackendError(504, e.localizedDescription) }
            throw BackendError(502, e.localizedDescription)
        }
    }

    // MARK: User actions (from banners)

    /// Banners whose callback POST or shell command is still running. A second click on the same banner is
    /// ignored until the first one finishes, so an impatient double click cannot fire an action twice.
    private var busyActions: Set<String> = []
    /// notify calls that are suspended preparing their image, keyed by `BannerCenter.key`.
    private var pendingNotifies = SupersedeTracker()
    private var reminderInFlight: Set<String> = []
    /// Pending "put the banner back after the failure line" tasks, keyed by `BannerCenter.key`.
    private var failureFlashes: [String: Task<Void, Never>] = [:]
    private var systemObservers: [NSObjectProtocol] = []
    private let callbacks = CallbackDelivery()
    private let commandRunner = CommandRunner()

    static let failureLineDuration: TimeInterval = 4

    /// Never pass interpolated text as NSLog's format string: a button label containing "%@" would be read as one.
    private func log(_ message: String) { NSLog("Herald: %@", message) }
    static let openRemindersLabel = "Open Reminders"

    func userClosed(app: String, id: String) { dismissItem(app: app, id: id, action: nil) }

    enum LinkOutcome { case opened, blocked, failed }

    /// The one way Herald hands a sender-supplied URL to the system. Only web and mail links open (see
    /// `LinkPolicy`); the Reminders app, which Herald itself offers after "Add to Reminders", is the one
    /// exception, and only that exact URL.
    static func openLink(_ url: URL) -> LinkOutcome {
        guard LinkPolicy.isOpenable(url) || url.absoluteString == ReminderService.remindersAppURL.absoluteString else { return .blocked }
        return NSWorkspace.shared.open(url) ? .opened : .failed
    }

    static func openSafely(_ url: URL) -> Bool { openLink(url) == .opened }

    private static func failureReason(_ outcome: LinkOutcome) -> String {
        outcome == .blocked ? "this link type is not allowed" : "nothing can open this link"
    }

    func userOpened(app: String, id: String) {
        guard let item = history.item(app: app, id: id) else { return }
        if let u = item.notification.url, let url = URL(string: u) {
            let outcome = Self.openLink(url)
            guard outcome == .opened else {
                log("link of \(app)/\(id) not opened (\(outcome)): \(u)")
                flashFailure(app: app, id: id, reason: Self.failureReason(outcome))
                return
            }
        } else if let bid = registry.record(for: app)?.registration.bundleId,
                  let running = NSRunningApplication.runningApplications(withBundleIdentifier: bid).first {
            running.activate()
        }
        dismissItem(app: app, id: id, action: "open")
    }

    /// A button was pressed. Link buttons open and dismiss. Callback and command buttons dismiss only once the
    /// action succeeded: when it fails the banner stays, shows a brief "Action failed" line and can be tried again.
    func userPressed(app: String, id: String, button: HeraldButton) {
        guard let item = history.item(app: app, id: id) else { return }
        guard !busyActions.contains(BannerCenter.key(app, id)) else { return }
        if let u = button.url {
            guard let url = URL(string: u) else { flashFailure(app: app, id: id, reason: "invalid link"); return }
            let outcome = Self.openLink(url)
            guard outcome == .opened else {
                log("link button \(button.label) of \(app) not opened (\(outcome)): \(u)")
                flashFailure(app: app, id: id, reason: Self.failureReason(outcome))
                return
            }
            dismissItem(app: app, id: id, action: button.label)
        } else if let cmd = button.command {
            runCommandButton(item: item, button: button, command: cmd)
        } else if let cb = button.callback {
            runCallbackButton(item: item, button: button, callback: cb)
        } else {
            dismissItem(app: app, id: id, action: button.label)
        }
    }

    // MARK: Callback buttons

    private func runCallbackButton(item: HeraldHistoryItem, button: HeraldButton, callback: HeraldCallback) {
        let target = callback.url ?? registry.record(for: item.app)?.registration.callbackURL
        guard let target, let url = URL(string: target) else {
            log("callback button \(button.label) of \(item.app) has no callback URL")
            flashFailure(app: item.app, id: item.id, reason: "no callback URL")
            return
        }
        // A callback goes to a loopback address freely; any other host only after the user agreed to it, because
        // the event carries the payload the sender attached to the button.
        var approvedHosts: Set<String> = []
        if CallbackDelivery.needsApproval(url) {
            guard let host = CallbackDelivery.normalizedHost(of: url) else {
                flashFailure(app: item.app, id: item.id, reason: "invalid callback URL")
                return
            }
            if registry.record(for: item.app)?.callbackHostApproved != host {
                switch confirmCallbackHost(app: item.app, host: host, url: url) {
                case .once: break
                case .always: registry.update(item.app) { $0.callbackHostApproved = host }; changed()
                case .cancel: return
                }
            }
            approvedHosts = [host]
        }
        let event = HeraldCallbackEvent(notificationId: item.id, app: item.app, action: button.label, payload: callback.payload)
        let key = BannerCenter.key(item.app, item.id)
        busyActions.insert(key)
        Task { @MainActor in
            let outcome = await callbacks.deliver(event, to: url, approvedHosts: approvedHosts)
            busyActions.remove(key)
            switch outcome {
            case .delivered:
                dismissItem(app: item.app, id: item.id, action: button.label)
            case .failed(_, let reason):
                flashFailure(app: item.app, id: item.id, reason: reason)
            }
        }
    }

    private enum HostChoice { case once, always, cancel }

    /// "Send Once" is the default: the lasting approval is one click further away than the safe choice.
    private func confirmCallbackHost(app: String, host: String, url: URL) -> HostChoice {
        let name = registry.record(for: app)?.displayName ?? app
        let a = NSAlert()
        a.alertStyle = .warning
        a.messageText = "Send \(name)'s button action to \(host)?"
        a.informativeText = "\(name) wants Herald to POST this button's action and payload to \(url.absoluteString). That address is not on this Mac."
        a.addButton(withTitle: "Send Once")
        a.addButton(withTitle: "Always Allow \(host)")
        a.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        switch a.runModal() {
        case .alertFirstButtonReturn: return .once
        case .alertSecondButtonReturn: return .always
        default: return .cancel
        }
    }

    // MARK: Command buttons

    /// Commands run only when the app registered with `allowCommands` AND the user agreed. The agreement is
    /// asked for the first time such a button is pressed, with the exact command in front of the user.
    private func runCommandButton(item: HeraldHistoryItem, button: HeraldButton, command: String) {
        let record = registry.record(for: item.app)
        let name = record?.displayName ?? item.app
        switch CommandPermission.evaluate(record) {
        case .denied(let why):
            log("command button \(button.label) ignored for \(item.app): \(why)")
            flashFailure(app: item.app, id: item.id, reason: "commands are not allowed for \(name)")
            return
        case .needsConfirmation:
            guard confirmCommand(app: item.app, displayName: name, command: command) else { return }
        case .allowed:
            break
        }
        let key = BannerCenter.key(item.app, item.id)
        busyActions.insert(key)
        let context = CommandContext(app: item.app, notificationId: item.id, action: button.label)
        Task { @MainActor in
            let result = await commandRunner.run(command, context: context)
            busyActions.remove(key)
            if result.succeeded {
                dismissItem(app: item.app, id: item.id, action: button.label)
            } else {
                log("command for \(item.app)/\(item.id) failed: \(result.summary) (see \(commandRunner.log.url.path))")
                flashFailure(app: item.app, id: item.id, reason: result.summary)
            }
        }
    }

    /// "Run Once" is the default button on purpose: the lasting permission is one click further away than
    /// the safe choice, so pressing Return by habit cannot grant it.
    private func confirmCommand(app: String, displayName: String, command: String) -> Bool {
        let a = NSAlert()
        a.alertStyle = .warning
        a.messageText = "Run this command for \(displayName)?"
        a.informativeText = "\(displayName) wants Herald to run the command below with your user permissions (/bin/zsh -lc)."
        a.accessoryView = Self.commandView(command)
        a.addButton(withTitle: "Run Once")
        a.addButton(withTitle: "Always Allow \(displayName)")
        a.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        switch a.runModal() {
        case .alertFirstButtonReturn:
            return true
        case .alertSecondButtonReturn:
            registry.update(app) { $0.commandsConfirmed = true }
            changed()
            return true
        default:
            return false
        }
    }

    /// The command verbatim, selectable and scrollable, so a long one is neither truncated nor reflowed.
    private static func commandView(_ command: String) -> NSView {
        let scroll = NSTextView.scrollableTextView()
        scroll.frame = NSRect(x: 0, y: 0, width: 420, height: 90)
        scroll.borderType = .bezelBorder
        if let text = scroll.documentView as? NSTextView {
            text.isEditable = false
            text.isSelectable = true
            text.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
            text.textContainerInset = NSSize(width: 4, height: 4)
            text.string = command
        }
        return scroll
    }

    // MARK: Failure line

    /// A failed button action leaves the banner up and shows "Action failed" in its subtitle line for a few
    /// seconds. It goes through `BannerCenter.show` (which replaces a banner in place) with a copy of the
    /// notification, so it works in every layout without the banner views knowing about failures. History is
    /// never touched: the original payload comes back when the line expires.
    private func flashFailure(app: String, id: String, reason: String) {
        if !settings.muted { NSSound.beep() }
        guard let item = history.item(app: app, id: id), item.dismissedAt == nil, item.snoozedUntil == nil else { return }
        let key = BannerCenter.key(app, id)
        var shown = item
        let detail = reason.count > 60 ? String(reason.prefix(57)) + "..." : reason
        shown.notification.subtitle = "Action failed" + (detail.isEmpty ? "" : " \u{00B7} \(detail)")
        showInPlace(shown)
        failureFlashes[key]?.cancel()
        failureFlashes[key] = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.failureLineDuration * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            self.failureFlashes[key] = nil
            self.restoreBanner(app: app, id: id)
        }
    }

    private func cancelFlash(_ key: String) {
        failureFlashes.removeValue(forKey: key)?.cancel()
    }

    private func showInPlace(_ item: HeraldHistoryItem) {
        let record = registry.ensure(item.app)
        banners.show(item, settings: EffectiveSettings.resolve(item.notification, record), record: record)
    }

    /// Shows the banner exactly as History has it. Does nothing if it was dismissed or snoozed in the meantime.
    private func restoreBanner(app: String, id: String) {
        guard let item = history.item(app: app, id: id), item.dismissedAt == nil, item.snoozedUntil == nil else { return }
        showInPlace(item)
    }

    // MARK: Sound

    /// Plays the notification's sound unless Herald is muted. A sound that does not exist falls back to the
    /// app's default sound and then to the built-in one (see `SoundPlayer.play`).
    private func playSound(_ eff: EffectiveSettings, record: AppRecord?) {
        guard !settings.muted else { return }
        let fallback = [record?.registration.defaults?.sound, EffectiveSettings.fallbackSound].compactMap { $0 }
        sounds.play(eff.sound, fallback: fallback)
    }

    // MARK: Snooze

    func userSnoozed(app: String, id: String, option: SnoozeOption) {
        snooze(app: app, id: id, until: option.fireDate(from: Date()))
    }

    /// `POST /v1/snooze`: the same as the banner's menu, for an arbitrary number of minutes.
    func snoozeItem(app: String, id: String, minutes: Double) throws -> Date {
        guard Snooze.isValid(minutes: minutes) else { throw BackendError(400, "minutes must be greater than 0 and at most \(Int(Snooze.maxMinutes))") }
        guard let item = history.item(app: app, id: id) else { throw BackendError(404, "notification not found") }
        guard item.dismissedAt == nil else { throw BackendError(400, "notification is already dismissed") }
        let until = Snooze.fireDate(afterMinutes: minutes, from: Date())
        snooze(app: app, id: id, until: until)
        return until
    }

    /// `POST /v1/unsnooze`: brings a snoozed banner back now, silently (it is not a new alert). Not snoozed: no-op.
    func unsnoozeItem(app: String, id: String) throws {
        guard let item = history.item(app: app, id: id) else { throw BackendError(404, "notification not found") }
        guard item.dismissedAt == nil else { throw BackendError(400, "notification is already dismissed") }
        fireSnooze(app: app, id: id, playSound: false)
    }

    /// The snooze is persisted (`snoozedUntil`) before the timer is armed, so a quit or crash in between
    /// still brings the banner back at the right time.
    private func snooze(app: String, id: String, until: Date) {
        guard let item = history.item(app: app, id: id), item.dismissedAt == nil else { return }
        cancelFlash(BannerCenter.key(app, id))
        history.update(app: app, id: id) { $0.snoozedUntil = until }
        banners.close(app: app, id: id)   // also cancels the timer of an earlier snooze
        banners.scheduleSnooze(app: app, id: id, at: until)
        changed()
    }

    func snoozeFired(app: String, id: String) { fireSnooze(app: app, id: id, playSound: true) }

    /// Shows a snoozed notification again. `show` replaces a banner with the same id in place, so a
    /// notification re-sent under that id while it was snoozed never ends up on screen twice.
    private func fireSnooze(app: String, id: String, playSound: Bool) {
        guard let current = history.item(app: app, id: id), current.dismissedAt == nil, current.snoozedUntil != nil,
              let item = history.update(app: app, id: id, { $0.snoozedUntil = nil }) else { return }
        let record = registry.ensure(app)
        let eff = EffectiveSettings.resolve(item.notification, record)
        banners.show(item, settings: eff, record: record)
        if playSound { self.playSound(eff, record: record) }
        changed()
    }

    /// Arms a timer for every pending snooze and fires the ones that are already due. Runs at launch and
    /// again after sleep or a clock change, when a timer set for a wall-clock time may have been missed.
    private func rearmSnoozes() {
        let now = Date()
        for item in history.undismissed() {
            guard let until = item.snoozedUntil else { continue }
            if until <= now { fireSnooze(app: item.app, id: item.id, playSound: true) }
            else { banners.scheduleSnooze(app: item.app, id: item.id, at: until) }
        }
    }

    func bannerExpired(app: String, id: String) { dismissItem(app: app, id: id, action: "timeout", supersedePending: false) }

    // MARK: Reminders

    func userAddedReminder(app: String, id: String) {
        guard let item = history.item(app: app, id: id), let rem = item.notification.reminder else { return }
        let key = BannerCenter.key(app, id)
        guard reminderInFlight.insert(key).inserted else { return }
        banners.setReminderState(app: app, id: id, .working)
        let draft = ReminderDraft(notification: item.notification, reminder: rem)
        Task { @MainActor in
            defer { reminderInFlight.remove(key) }
            do {
                try await reminders.add(draft)
                offerOpenReminders(app: app, id: id)
                banners.setReminderState(app: app, id: id, .added)
            } catch {
                banners.setReminderState(app: app, id: id, .failed(error.localizedDescription))
                presentReminderError(error)
            }
        }
    }

    /// After a successful add the banner gains an "Open Reminders" button. It is an ordinary link button on
    /// the displayed copy (History keeps the original payload), so it needs nothing from the banner views.
    private func offerOpenReminders(app: String, id: String) {
        guard var item = history.item(app: app, id: id), item.dismissedAt == nil, item.snoozedUntil == nil else { return }
        var buttons = item.notification.buttons ?? []
        guard !buttons.contains(where: { $0.label == Self.openRemindersLabel }) else { return }
        buttons.append(HeraldButton(label: Self.openRemindersLabel, url: ReminderService.remindersAppURL.absoluteString))
        item.notification.buttons = buttons
        showInPlace(item)   // resets the reminder state to idle; the caller sets .added right after
    }

    private func presentReminderError(_ error: Error) {
        let a = NSAlert()
        a.alertStyle = .warning
        a.messageText = "Couldn't add to Reminders"
        a.informativeText = error.localizedDescription
        a.addButton(withTitle: "OK")
        var offerSettings = false
        if case ReminderError.denied = error { offerSettings = true }
        if offerSettings { a.addButton(withTitle: "Open Privacy Settings") }
        NSApp.activate(ignoringOtherApps: true)
        if a.runModal() == .alertSecondButtonReturn { ReminderService.openPrivacySettings() }
    }

    // MARK: Relaunch

    /// Banners put back on screen at launch. A long-running chatty sender can leave hundreds of undismissed
    /// items; one panel and one full-resolution image per item would stall the launch and bury the screen, so
    /// only the newest ones get a panel. The rest stay undismissed in History and are counted by the "+N more" pill.
    static let restoreLimit = 6

    private func restoreBanners() {
        let now = Date()
        var chimed = false   // one sound for any number of snoozes that ran out while Herald was not running
        var toShow: [(item: HeraldHistoryItem, eff: EffectiveSettings, record: AppRecord)] = []
        for item in history.undismissed() {
            let record = registry.ensure(item.app)
            let eff = EffectiveSettings.resolve(item.notification, record)
            switch Snooze.restoreAction(snoozedUntil: item.snoozedUntil, persistent: eff.persistent, now: now) {
            case .expire:
                history.update(app: item.app, id: item.id) { $0.dismissedAt = now; $0.actionUsed = "timeout" }
            case .schedule(let until):
                banners.scheduleSnooze(app: item.app, id: item.id, at: until)
            case .fireNow:
                fireSnooze(app: item.app, id: item.id, playSound: !chimed)
                chimed = true
            case .showNow:
                toShow.append((item, eff, record))
            }
        }
        // `undismissed()` is oldest first, so the newest are at the end and are shown last (on top).
        let deferred = toShow.dropLast(Self.restoreLimit)
        banners.deferBanners(keys: deferred.map { BannerCenter.key($0.item.app, $0.item.id) }, corner: toShow.last?.eff.corner ?? .topRight)
        for r in toShow.suffix(Self.restoreLimit) { banners.show(r.item, settings: r.eff, record: r.record) }
        observeSystemEvents()
    }

    private func observeSystemEvents() {
        guard systemObservers.isEmpty else { return }
        let rearm: @Sendable (Notification) -> Void = { [weak self] _ in MainActor.assumeIsolated { self?.rearmSnoozes() } }
        systemObservers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main, using: rearm))
        systemObservers.append(NotificationCenter.default.addObserver(
            forName: .NSSystemClockDidChange, object: nil, queue: .main, using: rearm))
    }
}

/// `POST /v1/snooze` and `POST /v1/unsnooze` (served by `SnoozeRoutes`, see `startServer`).
extension BackendAdapter: HeraldSnoozeBackend {
    func snooze(app: String, id: String, minutes: Double) async throws -> Date {
        try await controller.snoozeItem(app: app, id: id, minutes: minutes)
    }
    func unsnooze(app: String, id: String) async throws {
        try await controller.unsnoozeItem(app: app, id: id)
    }
}
