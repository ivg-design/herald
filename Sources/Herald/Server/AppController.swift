import SwiftUI
import AppKit
import Foundation

/// Adapter that lets the (nonisolated) router call into the main-actor controller.
final class BackendAdapter: HeraldBackend, @unchecked Sendable {
    private let controller: AppController
    let parity: ParityService?
    init(_ c: AppController, parity: ParityService? = nil) { controller = c; self.parity = parity }
    func notify(_ n: HeraldNotification) async throws -> String { try await controller.notify(n) }
    func register(_ r: HeraldAppRegistration) async throws { try await controller.register(r) }
    func dismiss(app: String, id: String) async throws { await controller.dismissItem(app: app, id: id, action: nil) }
    func dismissAll(app: String?) async throws { await controller.dismissAll(app: app) }
    func dismissGroup(app: String, group: String) async throws { await controller.dismissGroup(app: app, group: group) }
    func stacks(app: String?) async throws -> [HeraldStackInfo] { await controller.stackInfos(app: app) }
    func expandStack(app: String, group: String, expanded: Bool) async throws {
        try await controller.setStackExpanded(app: app, group: group, expanded: expanded)
    }
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
    func preview(_ request: PreviewSpec) async throws -> Data { try await controller.previewPNG(request) }
    func riveCheck(_ request: RiveCheckRequest) async throws -> RiveCheckReply { await controller.riveCheck(request) }
    func designerSnapshot(app: String?, template: String?, select: String?, width: Int, height: Int) async throws -> Data {
        try await controller.designerSnapshot(app: app, template: template, select: select, width: width, height: height)
    }
    func quietHours() async throws -> HeraldQuietReply { await MainActor.run { QuietHoursCoordinator.shared.reply() } }
    func updateQuietHours(_ update: HeraldQuietUpdate) async throws -> HeraldQuietReply {
        try await MainActor.run { try QuietHoursCoordinator.shared.apply(update) }
    }
    func stackingLevel() async throws -> StackingLevel { await controller.settings.stacking }
    func setStackingLevel(_ level: StackingLevel) async throws -> StackingLevel {
        await MainActor.run { controller.settings.stacking = level; return controller.settings.stacking }
    }
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
    /// What users typed into banners' inline Reply, waiting for an agent to read it (`GET /v1/replies`).
    let replyQueue: ReplyQueue
    let settings = AppSettings.shared
    let sounds = SoundPlayer()
    let reminders = ReminderService()
    private(set) var banners: BannerCenter!
    /// The inline confirmations (DESIGN 8): questions asked inside a banner, never in a modal alert.
    private(set) var confirmations: ConfirmationFlow!
    /// The MCP/API parity routes (settings, assets, bundles, History search, symbols...); see ParityService.
    private(set) var parityService: ParityService!
    /// The cloud relay: the outbound socket, agent keys and receipts (docs/CLOUD.md).
    private(set) var relay: RelayController!
    private var listener: HTTPLoopbackListener?
    private var token = ""
    private(set) var serverStatus = "Not started"
    private(set) var serverRunning = false

    private init() {
        history = HistoryStore(directory: supportDirectory.appendingPathComponent("history", isDirectory: true), cap: HistoryCapSetting.value)
        templates = TemplateStore(directory: supportDirectory.appendingPathComponent("templates", isDirectory: true))
        manifests = ManifestStore(directory: supportDirectory.appendingPathComponent("manifests", isDirectory: true))
        registry = AppRegistry(file: supportDirectory.appendingPathComponent("apps.json"))
        replyQueue = ReplyQueue(file: supportDirectory.appendingPathComponent("replies.json"))
        banners = BannerCenter(controller: self)
        confirmations = ConfirmationFlow(registry: registry, approvals: commandApprovals) { [unowned self] in changed() }
        confirmations.surface = banners
        parityService = ParityService(templates: templates, manifests: manifests, history: history, registry: registry,
                                      assets: AssetStore.shared, approvals: commandApprovals, host: AppParityHost(controller: self),
                                      replies: replyQueue)
        // Every action a grid banner offers (button, action row, icon button, Rive click) runs through the
        // controller, which works out the origin itself and applies the permission each kind needs.
        banners.actionHandler = { [unowned self] app, id, action, _ in userPerformed(app: app, id: id, action: action) }
        relay = RelayController(controller: self)
    }

    var muted: Bool {
        get { settings.muted }
        set { settings.muted = newValue; changed() }
    }

    func start() {
        do { token = try TokenStore.loadOrCreate(in: supportDirectory) }
        catch { serverStatus = "Cannot create token: \(error.localizedDescription)"; return }
        let voice = VoiceCoordinator.shared
        voice.history = history
        voice.showBanner = { [unowned self] item in
            let record = registry.ensure(item.app)
            banners.show(item, settings: EffectiveSettings.resolve(item.notification, record), record: record)
            changed()
        }
        voice.onSpoken = { [unowned self] app, id in relay.speechFinished(app: app, id: id) }
        voice.start()
        // Installed agents (agent.claude-code, ...) get the current default manifest and template; the user's own edits stay.
        AgentIssuer.refreshInstalled(supportDirectory: supportDirectory, registry: registry, manifests: manifests, templates: templates,
                                     detectedHost: HeraldHostApp.detectCurrent())
        startServer()
        restoreBanners()
        relay.start()
        changed()
    }

    func startServer() {
        listener?.stop(); listener = nil; serverRunning = false
        let router = Router(token: token, backend: BackendAdapter(self, parity: parityService), version: Self.version)
        // /v1/snooze and /v1/unsnooze are answered ahead of the router (see SnoozeRoutes); everything else falls through to it.
        let snoozing = SnoozeRoutes.handler(token: token, backend: BackendAdapter(self, parity: parityService)) { await router.handle($0) }
        let handler = RelayRoutes.handler(token: token, backend: relay, setup: relay, fallback: snoozing)
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
        // `actionIds` become the manifest's buttons now, so history and every later press see what was offered.
        named = ActionResolver.materializingActionIDs(named, manifest: manifest)
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
        // What a grid template binds to: payload fields, then metadata, plus the template's own `extra` values
        // and the delivery time (the manifest's samples are for the designer only).
        let delivered = Date()
        let fields = TemplateResolver.fields(for: note, manifest: manifest, extra: template?.extra ?? [:], deliveredAt: delivered)
        let item = HeraldHistoryItem(id: id, app: n.app, notification: note, deliveredAt: delivered, imagePath: imagePath, fields: fields)
        history.upsert(item)
        let eff = EffectiveSettings.resolve(note, record)
        // Voice (DESIGN section 7.9): speech is queued here; a voice-only notification gets no banner and no chime.
        // Quiet hours (DESIGN section 7.9.1) may silence speech, the chime and the banner; `priority: urgent` can
        // break through when the app allows it.
        let quiet = QuietHoursCoordinator.shared.state(for: note)
        let voiceOnly = VoiceCoordinator.shared.handle(notification: note, historyItem: item, quiet: quiet)
        if !voiceOnly {
            if quiet.active && quiet.banners { banners.deferBanner(key: key, corner: eff.corner) }
            else { banners.show(item, settings: eff, record: record) }
            if !(quiet.active && quiet.sounds) { playSound(eff, record: record) }
        }
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
        VoiceCoordinator.shared.cancel(app: app, id: id)
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
        if app == nil { VoiceCoordinator.shared.stopAll() }
        for item in history.undismissed() where app == nil || item.app == app {
            dismissItem(app: item.app, id: item.id, action: nil, notify: false)
        }
        changed()
    }

    // MARK: Stacks (DESIGN section 9)

    /// `POST /v1/dismissAll {app, group}`: every banner of `app` that was sent with this `group`, which is a stack
    /// when stacking is by sender. The group of a notification that sent none is its issuer id.
    func dismissGroup(app: String, group: String) {
        for item in history.undismissed()
        where item.app == app && StackKeying.effectiveGroup(app: item.app, group: item.notification.group) == group {
            dismissItem(app: item.app, id: item.id, action: nil, notify: false)
        }
        changed()
    }

    /// A stack's banners dismissed at once: its card's close button and "Dismiss all". Each member goes to History as
    /// dismissed, with one refresh for the lot.
    func dismissMembers(_ members: [(app: String, id: String)]) {
        for m in members { dismissItem(app: m.app, id: m.id, action: nil, notify: false) }
        changed()
    }

    /// `GET /v1/stacks`: the stacks that are up.
    func stackInfos(app: String?) -> [HeraldStackInfo] { banners.stackInfos(app: app) }

    /// `POST /v1/stacks/expand`: opens or closes a stack in place (never activates Herald).
    func setStackExpanded(app: String, group: String, expanded: Bool) throws {
        guard banners.setStackOpen(app: app, group: group, expanded) else {
            throw BackendError(404, "no stack of two or more notifications for that app and group")
        }
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
        // Copy the issuer's Rive files in now, so a banner can still draw them if the originals move later.
        // A bad asset is reported when a banner tries to draw it, so it never blocks the manifest.
        for r in AssetStore.shared.installAll(m) where !r.ok { log("manifest \(m.app): asset \(r.id): \(r.error?.localizedDescription ?? "not installed")") }
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
        let old = manifests.get(app: app)
        guard manifests.delete(app: app) else { throw BackendError(404, "manifest not found") }
        if let old { AssetStore.shared.remove(manifest: old) }
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

    // MARK: Preview

    /// `POST|GET /v1/preview`: the template drawn offscreen with the one banner view, as PNG. Nothing is stored,
    /// shown, played or added to history; a sample preview needs no notification at all. An image the data
    /// names is loaded without touching the history's image cache.
    func previewPNG(_ request: PreviewSpec) async throws -> Data {
        let plan = try PreviewPlan.make(request, manifest: manifests.get(app: request.app),
                                        stored: { [templates] in templates.get(app: request.app, name: $0) },
                                        placeholderImage: PreviewRenderer.placeholderImageSpec)
        let record = registry.record(for: request.app)
        let appName = record?.displayName ?? plan.manifest?.appName ?? request.app
        // The banner shows the notification's own image from this (remote ones would not load offscreen otherwise).
        let image = await PreviewRenderer.loadImage(plan.notification.image)
        do {
            return try PreviewRenderer.png(plan: plan, appName: appName, icon: AppIcons.icon(for: record, app: request.app),
                                           image: image, appearance: request.appearance, scale: request.scale,
                                           confirmation: request.confirmation, stackCount: request.stackCount,
                                           stackExpanded: request.stackExpanded,
                                           reply: request.replying ? BannerReplyPrompt(placeholder: plan.replyPlaceholder, sample: request.replySample) : nil)
        } catch {
            throw BackendError(500, error.localizedDescription)
        }
    }

    // MARK: Designer snapshot

    /// `POST /v1/designer/snapshot`: the Designer's content in a window-less hosting view, drawn to a bitmap. Nothing
    /// is shown, activated or saved; the model reads the app's templates and manifest but is never saved.
    func designerSnapshot(app: String?, template: String?, select: String?, width: Int, height: Int) throws -> Data {
        let m = DesignerModel(backend: .live(self), app: app, template: template)
        if let select { m.select(cell: select) }
        let view = DesignerView(model: m, controller: self,
                                iconFor: { [registry] in AppIcons.icon(for: registry.record(for: $0), app: $0) })
            .environment(\.colorScheme, .light)
        let host = NSHostingView(rootView: view)
        host.appearance = NSAppearance(named: .aqua)
        host.frame = NSRect(x: 0, y: 0, width: width, height: height)
        host.layoutSubtreeIfNeeded()
        // One more pass: GeometryReader-driven panes settle after the first layout.
        RunLoop.current.run(until: Date().addingTimeInterval(0.15))
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { throw BackendError(500, "could not allocate a bitmap") }
        host.cacheDisplay(in: host.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { throw BackendError(500, "could not encode the PNG") }
        return png
    }

    // MARK: Rive check

    /// `POST /v1/rive/check`: the live `RiveHostView` (the one a banner uses) created without a window, so what a
    /// banner would do with this component is observable through the API and no UI is involved.
    func riveCheck(_ request: RiveCheckRequest) -> RiveCheckReply {
        let manifest = manifests.get(app: request.app)
        let host = RiveHostView(frame: NSRect(x: 0, y: 0, width: 320, height: 160))
        var clicked: [String] = []
        host.onAction = { clicked.append($0) }
        host.apply(.init(component: request.component, app: request.app, manifest: manifest,
                         fields: request.fields ?? [:], assets: .shared))
        defer { host.tearDown() }
        for step in request.simulate ?? [] { host.simulate(step) }
        func text(_ v: HeraldFieldValue) -> String {
            switch v {
            case .text(let s): return s
            case .number(let n): return String(n)
            case .bool(let b): return String(b)
            case .list(let l): return l.joined(separator: ",")
            }
        }
        var artboards: [RiveCheckReply.Artboard] = []
        if let url = try? AssetStore.shared.resolve(request.component, app: request.app, manifest: manifest),
           let info = RiveFileInspector.read(url) {
            artboards = info.artboards.map { a in
                .init(name: a.name, width: a.width, height: a.height, defaultMachine: a.defaultMachine,
                      machines: a.machines.map { m in .init(name: m.name, inputs: m.inputs.map { .init(name: $0.name, kind: $0.kind.rawValue) }) },
                      animations: a.animations)
            }
        }
        return RiveCheckReply(loaded: host.loadError == nil && host.viewModel != nil, error: host.loadError,
                              inputs: host.inputKinds.mapValues(\.rawValue), applied: host.applied.mapValues(text),
                              artboards: artboards, takesClicks: host.takesClicks, pointerWrites: host.pointerWrites,
                              clickedActions: clicked)
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
    /// Runs script, command and shortcut actions (DESIGN 7.3); their output goes to ~/Library/Logs/Herald/actions.log.
    let actionRunner = ActionRunner()
    /// The templates whose commands the user confirmed (template-authored commands ask once per template).
    let commandApprovals = TemplateCommandApprovals(
        file: HeraldPaths.defaultSupportDirectory.appendingPathComponent("template-approvals.json"))

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
        // A template can make the banner's click bring the issuing application forward instead of opening a link.
        let template = templates.template(for: item.notification)
        if template?.onClick == .openApp {
            perform(HeraldAction(id: "open-app", label: "Open app", kind: .openApp), origin: .template, item: item,
                    template: template, manifest: manifests.get(app: app))
            return
        }
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

    /// A v1 button was pressed (the classic banner layouts). It is the issuer's own button and runs under the
    /// issuer rules, with v1's precedence (url, command, callback, else dismiss).
    func userPressed(app: String, id: String, button: HeraldButton) {
        userPerformed(app: app, id: id, action: ActionRunner.legacyAction(button))
    }

    /// The actions a banner for `item` can offer, with their origins: the issuer's buttons after the template's
    /// rules, then the template's own inline component actions.
    func resolvedActions(for item: HeraldHistoryItem) -> [HeraldResolvedAction] {
        ActionRunner.resolvedActions(notification: item.notification, manifest: manifests.get(app: item.app),
                                     template: templates.template(for: item.notification))
    }

    /// An action was pressed on a banner: a grid button, the action row, an icon button or a Rive click. The
    /// controller works out where the action came from itself, so a view cannot claim a template origin for an
    /// issuer's command. Link, dismiss and snooze actions run at once; callbacks, commands, scripts and
    /// shortcuts dismiss the banner only once they succeed. When one fails the banner stays, shows a brief
    /// "Action failed" line and can be tried again.
    func userPerformed(app: String, id: String, action pressed: HeraldAction) {
        guard let item = history.item(app: app, id: id) else { return }
        guard !busyActions.contains(BannerCenter.key(app, id)) else { return }
        let template = templates.template(for: item.notification)
        let manifest = manifests.get(app: app)
        let offered = ActionRunner.resolvedActions(notification: item.notification, manifest: manifest, template: template)
        let found = ActionRunner.match(pressed, in: offered)
        // The pressed copy carries the style the button was drawn with (a button's own `style` overrides its action's).
        var action = found?.action ?? pressed
        if let style = pressed.style { action.style = style }
        // An action the notification does not offer is treated as the issuer's: the strictest rule.
        perform(action, origin: found?.origin ?? .issuer, item: item, template: template, manifest: manifest)
    }

    private func perform(_ action: HeraldAction, origin: HeraldActionOrigin, item: HeraldHistoryItem,
                         template: HeraldTemplate?, manifest: HeraldManifest?) {
        let app = item.app, id = item.id
        let extra = template?.extra ?? [:]
        let invocation = ActionInvocation(
            notification: item.notification,
            fields: TemplateResolver.fields(for: item.notification, manifest: manifest, extra: extra, deliveredAt: item.deliveredAt),
            extra: extra, template: item.notification.template, imagePath: item.imagePath)
        let plan: ActionPlan
        switch actionRunner.plan(action, origin: origin, invocation: invocation) {
        case .failure(let e):
            log("\(action.kind.rawValue) action \(action.label) of \(app) cannot run: \(e.reason)")
            flashFailure(app: app, id: id, reason: e.reason)
            return
        case .success(let p):
            plan = p
        }
        // The gate may have to ask the user first. The question is drawn inside the banner (never an alert), so the
        // rest of the action runs from its answer: `proceed` is called at once when nothing needs asking.
        let go = { [self] in
            authorize(action, origin: origin, item: item, template: template, manifest: manifest) { [self] in
                execute(plan, action: action, origin: origin, item: item, manifest: manifest)
            }
        }
        // A destructive button is asked about first (inline, never an alert); its own gate follows.
        if ActionRunner.confirmsBeforeRunning(action) {
            let name = registry.record(for: app)?.displayName ?? app
            confirmations.askDestructive(app: app, id: id, label: ctxLabel(action, item: item), name: name, run: go)
        } else {
            go()
        }
    }

    /// The button's text as the banner draws it (`{tokens}` filled).
    private func ctxLabel(_ action: HeraldAction, item: HeraldHistoryItem) -> String {
        let template = templates.template(for: item.notification)
        let fields = TemplateResolver.fields(for: item.notification, manifest: manifests.get(app: item.app),
                                             extra: template?.extra ?? [:], deliveredAt: item.deliveredAt)
        let s = TemplateResolver.fill(action.label, fields: fields).trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? action.id : s
    }

    /// What an authorized action does.
    private func execute(_ plan: ActionPlan, action: HeraldAction, origin: HeraldActionOrigin, item: HeraldHistoryItem,
                         manifest: HeraldManifest?) {
        let app = item.app, id = item.id
        guard !busyActions.contains(BannerCenter.key(app, id)) else { return }
        switch plan {
        case .openURL(let url):
            let outcome = Self.openLink(url)
            guard outcome == .opened else {
                log("link action \(action.label) of \(app) not opened (\(outcome)): \(url.absoluteString)")
                flashFailure(app: app, id: id, reason: Self.failureReason(outcome))
                return
            }
            dismissItem(app: app, id: id, action: action.label)
        case .callback(let callback):
            // The issuer is told which of ITS buttons was pressed: its own label, even when a template rule
            // relabelled the action on the banner.
            let label = origin == .issuer
                ? (ActionRunner.issuerLabel(id: action.id, notification: item.notification, manifest: manifest) ?? action.label)
                : action.label
            runCallbackButton(item: item, label: label, callback: callback)
        case .process(let spec):
            runProcess(spec, action: action, origin: origin, item: item)
        case .openApp(let bundleId, let path):
            openApplication(bundleId: bundleId, path: path, action: action, item: item, manifest: manifest)
        case .reply(let reply):
            if reply.voice == true { beginRecording(item: item) }
            else { beginReply(reply, action: action, origin: origin, item: item, manifest: manifest) }
        case .dismiss:
            dismissItem(app: app, id: id, action: action.label)
        case .snooze(let minutes):
            do { _ = try snoozeItem(app: app, id: id, minutes: minutes) }
            catch { flashFailure(app: app, id: id, reason: "could not snooze") }
        }
    }

    // MARK: Inline reply

    /// A reply being typed: what the banner's field belongs to and where the answer goes.
    private struct PendingReply {
        let prompt: UUID
        let reply: HeraldReply
        let label: String
        let origin: HeraldActionOrigin
    }
    private var pendingReplies: [String: PendingReply] = [:]

    /// Reply was pressed: the buttons give way to a text field inside the banner (never a window, never an activation).
    private func beginReply(_ reply: HeraldReply, action: HeraldAction, origin: HeraldActionOrigin, item: HeraldHistoryItem,
                            manifest: HeraldManifest?) {
        let key = BannerCenter.key(item.app, item.id)
        let label = origin == .issuer
            ? (ActionRunner.issuerLabel(id: action.id, notification: item.notification, manifest: manifest) ?? action.label)
            : action.label
        let prompt = BannerReplyPrompt(placeholder: reply.placeholder)
        confirmations.drop(app: item.app, id: item.id)
        guard banners.setReply(app: item.app, id: item.id, prompt) else {
            flashFailure(app: item.app, id: item.id, reason: "the banner is not on screen to reply on")
            return
        }
        pendingReplies[key] = PendingReply(prompt: prompt.id, reply: reply, label: label, origin: origin)
    }

    /// Send on the reply field. The text goes onto the notification's History record (`reply`, `repliedAt`) and into the app's
    /// reply queue; with a callback (the action's own, or the app's registered URL) it is also POSTed there. The banner is
    /// then dismissed (after the callback has gone, when there is one). An empty reply, or one for a prompt that was
    /// replaced, is ignored.
    func sendReply(app: String, id: String, prompt: UUID, text: String) {
        let key = BannerCenter.key(app, id)
        guard let pending = pendingReplies[key], pending.prompt == prompt,
              let stored = ReplyRecorder.record(app: app, id: id, text: text, history: history, queue: replyQueue),
              let item = history.item(app: app, id: id) else { return }
        let clean = stored.text
        relay.replySent(app: app, id: id, text: clean)
        pendingReplies[key] = nil
        banners.setReply(app: app, id: id, nil)
        changed()
        guard var callback = pending.reply.callback else {
            dismissItem(app: app, id: id, action: "reply")
            return
        }
        var payload: [String: JSONValue] = [:]
        if case .object(let o)? = callback.payload { payload = o }
        payload["reply"] = .string(clean)
        callback.payload = .object(payload)
        runCallbackButton(item: history.item(app: app, id: id) ?? item, label: pending.label, callback: callback)
    }

    func cancelReply(app: String, id: String, prompt: UUID) {
        let key = BannerCenter.key(app, id)
        guard pendingReplies[key]?.prompt == prompt else { return }
        pendingReplies[key] = nil
        banners.setReply(app: app, id: id, nil)
    }

    /// The banner went away or was replaced while its reply field was up: nothing is stored.
    func dropReply(app: String, id: String) {
        let key = BannerCenter.key(app, id)
        guard pendingReplies.removeValue(forKey: key) != nil else { return }
        banners.setReply(app: app, id: id, nil)
    }

    // MARK: Voice reply (the Record button of a cloud notification)

    private struct Recording { let session: VoiceReplySession; let ticker: Task<Void, Never> }
    private var recordings: [String: Recording] = [:]

    /// Record was pressed: the buttons give way to the record strip, the microphone is asked for on first use, and recording
    /// starts. Nothing here starts by itself; this runs only from the button.
    private func beginRecording(item: HeraldHistoryItem) {
        let key = BannerCenter.key(item.app, item.id)
        guard recordings[key] == nil else { return }
        confirmations.drop(app: item.app, id: item.id)
        dropReply(app: item.app, id: item.id)
        let file = supportDirectory.appendingPathComponent("history/audio/replies/\(item.id).m4a")
        let session = VoiceReplySession(recorder: MicRecorder(), transcriber: OnDeviceTranscriber(),
                                        permission: { await MicRecorder.requestPermission() }, file: file)
        session.onChange = { [weak self] prompt in self?.banners.setRecord(app: item.app, id: item.id, prompt) }
        guard banners.setRecord(app: item.app, id: item.id, session.prompt) else {
            flashFailure(app: item.app, id: item.id, reason: "the banner is not on screen to record on")
            return
        }
        let ticker = Task { @MainActor [weak session] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 100_000_000)
                session?.tick(0.1)
            }
        }
        recordings[key] = Recording(session: session, ticker: ticker)
        Task { await session.start() }
    }

    func stopRecording(app: String, id: String, prompt: UUID) {
        guard let r = recordings[BannerCenter.key(app, id)], r.session.prompt.id == prompt else { return }
        r.session.stop()
    }

    func cancelRecording(app: String, id: String, prompt: UUID) {
        let key = BannerCenter.key(app, id)
        guard let r = recordings[key], r.session.prompt.id == prompt else { return }
        r.session.cancel()
        endRecording(key: key, app: app, id: id)
    }

    /// Send: transcribe on this Mac, upload the m4a and the transcript to the relay, keep a copy in History.
    func sendRecording(app: String, id: String, prompt: UUID) {
        let key = BannerCenter.key(app, id)
        guard let r = recordings[key], r.session.prompt.id == prompt else { return }
        r.ticker.cancel()
        Task {
            let result = await r.session.send { [relay] res in
                try await relay!.client.reportVoiceReply(id: id, m4a: res.m4a, transcript: res.transcript, seconds: res.seconds)
            }
            guard let result else { return }   // the strip shows why; Cancel closes it
            history.update(app: app, id: id) {
                $0.reply = result.transcript ?? "(voice reply)"
                $0.repliedAt = Date()
                $0.replyAudioPath = result.file.path
                $0.replyTranscript = result.transcript
            }
            endRecording(key: key, app: app, id: id)
            dismissItem(app: app, id: id, action: "reply")
        }
    }

    private func endRecording(key: String, app: String, id: String) {
        recordings.removeValue(forKey: key)?.ticker.cancel()
        banners.setRecord(app: app, id: id, nil)
    }

    // MARK: Open app

    /// Brings an application to the front: the action's own bundle id or path, else the issuing application
    /// (manifest `appBundleId` / `appPath`, the bundle id it registered with, the app named `appName`).
    /// This is a user's click on a button, so activating the application it opens is the point; Herald itself
    /// stays in the background (DESIGN 8). An application that cannot be found is not an error that stops
    /// anything: the banner stays, shows the failure line and History keeps a note.
    private func openApplication(bundleId: String?, path: String?, action: HeraldAction, item: HeraldHistoryItem,
                                 manifest: HeraldManifest?) {
        let app = item.app, id = item.id
        let record = registry.record(for: app)
        let candidates = HeraldOpenAppResolver.candidates(
            bundleId: bundleId, path: path, manifest: manifest, registeredBundleId: record?.registration.bundleId,
            appName: manifest?.appName ?? record?.displayName)
        guard let found = HeraldOpenAppResolver.resolve(candidates) else {
            log("open-app action \(action.label) of \(app): no installed application found (tried \(candidates))")
            history.update(app: app, id: id) { $0.actionNote = HeraldOpenAppResolver.notFoundNote(label: action.label) }
            changed()
            flashFailure(app: app, id: id, reason: "no installed application found")
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        let name = found.url.deletingPathExtension().lastPathComponent
        NSWorkspace.shared.openApplication(at: found.url, configuration: configuration) { [weak self] _, error in
            DispatchQueue.main.async {
                guard let self else { return }
                if let error {
                    self.log("open-app action \(action.label) of \(app): \(name) did not open: \(error.localizedDescription)")
                    self.history.update(app: app, id: id) { $0.actionNote = "\(action.label): could not open \(name)" }
                    self.changed()
                    self.flashFailure(app: app, id: id, reason: "could not open \(name)")
                } else {
                    self.dismissItem(app: app, id: id, action: action.label)
                }
            }
        }
    }

    // MARK: Callback buttons

    private func runCallbackButton(item: HeraldHistoryItem, label: String, callback: HeraldCallback) {
        let target = callback.url ?? registry.record(for: item.app)?.registration.callbackURL
        guard let target, let url = URL(string: target) else {
            log("callback action \(label) of \(item.app) has no callback URL")
            flashFailure(app: item.app, id: item.id, reason: "no callback URL")
            return
        }
        // A callback goes to a loopback address freely; any other host only after the user agreed to it, because
        // the event carries the payload the sender attached to the button. The question is asked inside the banner
        // (DESIGN 8) and the delivery runs from its answer; once or always sends, cancel does nothing.
        guard CallbackDelivery.needsApproval(url) else {
            deliverCallback(item: item, label: label, callback: callback, url: url, approvedHosts: [])
            return
        }
        guard let host = CallbackDelivery.normalizedHost(of: url) else {
            flashFailure(app: item.app, id: item.id, reason: "invalid callback URL")
            return
        }
        let send = { [self] in deliverCallback(item: item, label: label, callback: callback, url: url, approvedHosts: [host]) }
        if registry.record(for: item.app)?.callbackHostApproved == host {
            send()
        } else {
            let name = registry.record(for: item.app)?.displayName ?? item.app
            confirmations.askCallbackHost(app: item.app, id: item.id, name: name, host: host, url: url.absoluteString,
                                          send: send)
        }
    }

    private func deliverCallback(item: HeraldHistoryItem, label: String, callback: HeraldCallback, url: URL,
                                 approvedHosts: Set<String>) {
        let event = HeraldCallbackEvent(notificationId: item.id, app: item.app, action: label, payload: callback.payload)
        let key = BannerCenter.key(item.app, item.id)
        busyActions.insert(key)
        Task { @MainActor in
            let outcome = await callbacks.deliver(event, to: url, approvedHosts: approvedHosts)
            busyActions.remove(key)
            switch outcome {
            case .delivered:
                dismissItem(app: item.app, id: item.id, action: label)
            case .failed(_, let reason):
                flashFailure(app: item.app, id: item.id, reason: reason)
            }
        }
    }

    // MARK: Code-running actions

    /// The rules for actions that run code. An issuer's command (or script, or shortcut) needs the app's
    /// `allowCommands` AND the user's agreement, asked for the first time such a button is pressed with the
    /// exact command in front of the user. A command, script or Shortcut from the template is confirmed once
    /// per template and again whenever one of them changes (the script's SHA-256 included). The question is an
    /// inline row in the banner (DESIGN 8), never an alert: `proceed` runs at once when nothing needs asking and
    /// otherwise from the answer (Run once or Always allow). It never runs when the user cancels, when a failure
    /// line was shown, or when the banner goes away first.
    private func authorize(_ action: HeraldAction, origin: HeraldActionOrigin, item: HeraldHistoryItem,
                           template: HeraldTemplate?, manifest: HeraldManifest?, proceed: @escaping () -> Void) {
        switch ActionRunner.gate(for: action, origin: origin) {
        case .open:
            proceed()
        case .appPermission:
            let record = registry.record(for: item.app)
            let name = record?.displayName ?? item.app
            switch CommandPermission.evaluate(record) {
            case .denied(let why):
                log("\(action.kind.rawValue) action \(action.label) ignored for \(item.app): \(why)")
                flashFailure(app: item.app, id: item.id, reason: "commands are not allowed for \(name)")
            case .needsConfirmation:
                confirmations.askCommand(app: item.app, id: item.id, name: name, kind: action.kind,
                                         text: ActionRunner.describe(action), run: proceed)
            case .allowed:
                proceed()
            }
        case .templateConfirmation:
            // The approval key binds to the command text, the script file's hash or the Shortcut's name and input.
            guard let key = actionRunner.approvalKey(for: action) else { proceed(); return }
            let templateName = template?.name ?? item.notification.template ?? ""
            if commandApprovals.isApproved(app: item.app, template: templateName, command: key) { proceed(); return }
            let all = template.map { actionRunner.templateApprovalKeys(of: $0) } ?? [key]
            let replaced = ActionRunner.replacedIssuerLabel(for: action, notification: item.notification,
                                                            manifest: manifest, template: template)
            let name = registry.record(for: item.app)?.displayName ?? item.app
            confirmations.askTemplateCommand(app: item.app, id: item.id, template: templateName, name: name,
                                             kind: action.kind, pressedText: actionRunner.confirmationText(for: action),
                                             approvalKey: key, all: all, replacedIssuerLabel: replaced, run: proceed)
        }
    }

    private func runProcess(_ spec: ActionProcessSpec, action: HeraldAction, origin: HeraldActionOrigin, item: HeraldHistoryItem) {
        let key = BannerCenter.key(item.app, item.id)
        busyActions.insert(key)
        let context = CommandContext(app: item.app, notificationId: item.id, action: action.label)
        Task { @MainActor in
            let result = await actionRunner.run(spec, context: context, origin: origin)
            busyActions.remove(key)
            if result.succeeded {
                dismissItem(app: item.app, id: item.id, action: action.label)
            } else {
                log("\(spec.kind.rawValue) action for \(item.app)/\(item.id) failed: \(result.summary) (see \(actionRunner.log.url.path))")
                flashFailure(app: item.app, id: item.id, reason: actionRunner.failureReason(result))
            }
        }
    }

    // MARK: Failure line

    /// A failed action leaves the banner up and shows an "Action failed" strip under its grid for a few seconds
    /// (`BannerModel.failureLine`), whatever the template draws. History is never touched.
    private func flashFailure(app: String, id: String, reason: String) {
        if !settings.muted { NSSound.beep() }
        guard let item = history.item(app: app, id: id), item.dismissedAt == nil, item.snoozedUntil == nil else { return }
        let key = BannerCenter.key(app, id)
        let detail = reason.count > 100 ? String(reason.prefix(97)) + "..." : reason
        let line = "Action failed" + (detail.isEmpty ? "" : " \u{00B7} \(detail)")
        if !banners.setFailureLine(app: app, id: id, line) {
            showInPlace(item)
            banners.setFailureLine(app: app, id: id, line)
        }
        failureFlashes[key]?.cancel()
        failureFlashes[key] = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.failureLineDuration * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            self.failureFlashes[key] = nil
            self.banners.setFailureLine(app: app, id: id, nil)
        }
    }

    private func cancelFlash(_ key: String) {
        failureFlashes.removeValue(forKey: key)?.cancel()
    }

    private func showInPlace(_ item: HeraldHistoryItem) {
        let record = registry.ensure(item.app)
        banners.show(item, settings: EffectiveSettings.resolve(item.notification, record), record: record, keepPlace: true)
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

    /// The snooze menu of a stack's card: the whole group goes away and comes back together as the same stack.
    /// `members` are oldest first, and each wakes a few milliseconds after the one before, so they fold back in the
    /// order they arrived (the newest ends up on top).
    func userSnoozedGroup(members: [(app: String, id: String)], option: SnoozeOption) {
        let until = option.fireDate(from: Date())
        for (i, m) in members.enumerated() { snooze(app: m.app, id: m.id, until: until.addingTimeInterval(Double(i) * 0.05)) }
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
        // A snoozed stack wakes as several banners at once; one chime is enough.
        if playSound, Date().timeIntervalSince(lastSnoozeChime) > 1 {
            lastSnoozeChime = Date()
            self.playSound(eff, record: record)
        }
        changed()
    }
    private var lastSnoozeChime = Date.distantPast

    /// Arms a timer for every pending snooze and fires the ones that are already due. Runs at launch and
    /// again after sleep or a clock change, when a timer set for a wall-clock time may have been missed.
    private func rearmSnoozes() {
        let pending = history.undismissed().compactMap { item in
            item.snoozedUntil.map { PendingSnooze(app: item.app, id: item.id, until: $0) }
        }
        let plan = Snooze.rearmPlan(pending, now: Date())
        for (i, p) in plan.fireNow.enumerated() { fireSnooze(app: p.app, id: p.id, playSound: i == 0) }
        for p in plan.schedule { banners.scheduleSnooze(app: p.app, id: p.id, at: p.until) }
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
                presentReminderError(error, app: app, id: id)
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

    /// "Couldn't add to Reminders" is asked as an inline row on the banner (OK, and Open Privacy Settings when the
    /// permission was denied), not as a modal alert (DESIGN 8).
    private func presentReminderError(_ error: Error, app: String, id: String) {
        var denied = false
        if case ReminderError.denied = error { denied = true }
        confirmations.showReminderError(app: app, id: id, message: error.localizedDescription, canOpenSettings: denied) {
            ReminderService.openPrivacySettings()
        }
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
