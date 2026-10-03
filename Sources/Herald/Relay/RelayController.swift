import AppKit
import Network
import Foundation
import HeraldClient

/// The app's side of the cloud relay: owns the `RelayClient`, answers Settings > Cloud and `/v1/relay/*`, registers an issuer
/// (`cloud.<key name>`) per agent key, and wires speech, replies and voice replies to the relay's receipts.
@MainActor
final class RelayController: RelayHost, RelayBackend {
    unowned let controller: AppController
    let store: RelayStateStore
    let dedupe: RelayDedupe
    let tokens: RelayTokenStore
    private(set) var client: RelayClient!
    private(set) var keys: [RelayKeyInfo] = []
    private(set) var usage: RelayUsage?
    private(set) var pairingCode: String?
    private(set) var lastError: String?
    /// Connector requests the relay has pushed (the OAuth flow): pending ones show a banner and a code in Settings > Cloud.
    private(set) var consentBook = ConsentBook()
    private var consentExpiry: Task<Void, Never>?
    static let consentApp = HeraldIdentity.app
    // Relay setup (Cloudflare deploy): see RelayController+Setup.swift.
    let cloudConfig: RelayCloudConfigStore
    let cloudSecrets: CloudflareSecrets
    var relaySwitch: RelaySwitch!
    var deployRunning = false
    var deployLog = DeployLog()
    var deployFailure: String?
    var healthBundle: String?
    private var issuerKeys = Set<String>()
    /// Addresses of this same Worker that settings just moved away from (a changed custom hostname), so the next deploy keeps the pairing.
    var ownPreviousURLs: [String] = []
    /// What the last deploy asked the user to know (Bot Fight Mode, reconnecting connectors).
    var lastDeployWarnings: [String] = []
    private var monitor: NWPathMonitor?
    private var observers: [NSObjectProtocol] = []

    init(controller: AppController) {
        self.controller = controller
        let dir = controller.supportDirectory
        store = RelayStateStore(file: dir.appendingPathComponent("relay.json"))
        dedupe = RelayDedupe(file: dir.appendingPathComponent("relay-dedupe.json"))
        // A throwaway support folder (tests, HERALD_SUPPORT_DIR) gets its own Keychain item, never the real token's.
        let isDefault = dir.standardizedFileURL == HeraldPaths.defaultSupportDirectory.standardizedFileURL
        tokens = KeychainTokenStore(service: isDefault ? "com.ivg.herald.relay" : "com.ivg.herald.relay.\(Self.stableHash(dir.path))", directory: dir)
        cloudConfig = RelayCloudConfigStore(file: dir.appendingPathComponent("relay-cloudflare.json"))
        cloudSecrets = KeychainCloudflareSecrets(service: isDefault ? "com.ivg.herald.cloudflare" : "com.ivg.herald.cloudflare.\(Self.stableHash(dir.path))", directory: dir)
        client = RelayClient(host: self, store: store, dedupe: dedupe, tokens: tokens)
        client.pingSeconds = TimeInterval(cloudConfig.value.pingSeconds)
        // No relay is shared by default. An earlier build pointed unpaired installs at the maintainer's own instance: forget that.
        if tokens.load() == nil, store.value.relayURL == RelayDefaults.legacyHostedURL { store.update { $0.relayURL = "" } }
        client.onChange = { [weak self] in
            // Online again: a "relay is not answering" from an earlier attempt is stale and must not keep showing.
            if self?.client.state == .online { self?.deployFailure = nil }
            self?.controller.changed(); self?.relaySwitch?.sync()
        }
        relaySwitch = RelaySwitch(backend: self)
        relaySwitch.onChange = { [weak self] in self?.controller.changed() }
    }

    /// A hash that is the same on every launch (`hashValue` is not).
    private static func stableHash(_ s: String) -> String {
        var h: UInt64 = 5381
        for b in s.utf8 { h = (h &* 33) ^ UInt64(b) }
        return String(h, radix: 16)
    }

    var relayURL: String {
        get { store.value.relayURL }
        set { store.update { $0.relayURL = newValue.trimmingCharacters(in: .whitespacesAndNewlines) }; controller.changed() }
    }

    var isPaired: Bool { client.isPaired }

    // MARK: Lifecycle

    func start() {
        client.start()
        if isPaired { Task { await refreshKeys() } }
        observe()
    }

    private func observe() {
        guard monitor == nil else { return }
        // Wake and network changes: connect again now instead of waiting out the backoff.
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.client.reconnectNow() }
        })
        observers.append(NotificationCenter.default.addObserver(forName: .heraldChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.client.publishStatus() }
        })
        let m = NWPathMonitor()
        var wasSatisfied = true
        m.pathUpdateHandler = { [weak self] path in
            let ok = path.status == .satisfied
            let changedBack = ok && !wasSatisfied
            wasSatisfied = ok
            if changedBack { Task { @MainActor in self?.client.reconnectNow() } }
        }
        m.start(queue: DispatchQueue(label: "herald.relay.path"))
        monitor = m
    }

    // MARK: RelayHost

    func relayInputs(for envelope: RelayEnvelope) -> (muted: Bool, quiet: HeraldQuietStatus) {
        let n = RelayPolicy.notification(for: envelope, silenceSpeech: false)
        return (AppSettings.shared.muted, QuietHoursCoordinator.shared.state(for: n))
    }

    func relayStatusNow() -> (muted: Bool, quiet: HeraldQuietStatus) {
        (AppSettings.shared.muted, QuietHoursCoordinator.shared.status())
    }

    func relayEnsureIssuer(_ key: RelayKeyRef) async {
        guard !issuerKeys.contains(key.id) else { return }
        var info = keys.first { $0.id == key.id }
        if info == nil { await refreshKeys(); info = keys.first { $0.id == key.id } }
        await registerIssuer(name: key.name, client: key.client, info: info)
        issuerKeys.insert(key.id)
    }

    /// The connector's own name (its OAuth `client_name`) for an oauth key; nil for a static key.
    private func clientName(of key: RelayKeyInfo?) -> String? { key.flatMap { $0.isOAuth ? $0.displayName : nil } }

    private func registerIssuer(name: String, client: String, info: RelayKeyInfo? = nil, source known: AutoIcon.Source? = nil) async {
        let clientName = clientName(of: info)
        guard let agent = AgentIdentity(cloudKeyName: name, client: client, clientName: clientName) else { return }
        let custom = RelayIcon.customFile(slug: agent.slug, folder: AgentIssuer.iconsFolder(in: controller.supportDirectory))
        var png = try? Data(contentsOf: custom)
        if png == nil { png = await AgentInstall.iconPNG(for: agent, picked: nil) }
        _ = try? AgentIssuer.register(agent, iconPNG: png, supportDirectory: controller.supportDirectory, registry: controller.registry,
                                      manifests: controller.manifests, templates: controller.templates)
        // No icon of its own: the product's icon on this Mac (ChatGPT.app, Claude, Codex), else a cloud / key tile.
        let flavor = AutoIcon.flavor([clientName, name, client == "other" ? nil : client])
        let source: AutoIcon.Source = known ?? info.map { $0.isOAuth ? .connector : .staticKey } ?? .connector
        let support = controller.supportDirectory, registry = controller.registry
        await Task.detached {
            if let auto = AutoIcon.png(flavor: flavor, source: source) {
                AutoIcon.assign(app: agent.appID, png: auto, supportDirectory: support, registry: registry)
            }
        }.value
        controller.changed()
    }

    /// Apps of the relay's keys: connectors take the client's name, and an app without an icon gets the automatic one.
    func reconcileCloudApps() {
        let keys = self.keys, registry = controller.registry, manifests = controller.manifests, support = controller.supportDirectory
        guard !keys.isEmpty else { return }
        Task.detached { [weak controller] in
            let renamed = CloudApps.reconcile(keys: keys, registry: registry, manifests: manifests, supportDirectory: support)
            await MainActor.run { _ = renamed; AppIcons.invalidate(); controller?.changed() }
        }
    }

    /// The icon a notification brought, applied once per distinct value for this key. The user's own icon (set in Settings) wins:
    /// `AgentIssuer.register` leaves one that does not live in Herald's icon folder alone.
    func relayApplyIcon(_ source: String, for key: RelayKeyRef) async {
        let info = keys.first { $0.id == key.id }
        guard appliedIcons[key.id] != source,
              let agent = AgentIdentity(cloudKeyName: key.name, client: key.client, clientName: clientName(of: info)) else { return }
        appliedIcons[key.id] = source
        guard let data = await RelayIcon.bytes(from: source), let png = RelayIcon.png(from: data) else { return }
        let folder = AgentIssuer.iconsFolder(in: controller.supportDirectory)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? png.write(to: RelayIcon.customFile(slug: agent.slug, folder: folder), options: .atomic)
        _ = try? AgentIssuer.register(agent, iconPNG: png, supportDirectory: controller.supportDirectory, registry: controller.registry,
                                      manifests: controller.manifests, templates: controller.templates)
        controller.changed()
    }
    private var appliedIcons: [String: String] = [:]

    func relayDeliver(_ notification: HeraldNotification) async throws { _ = try await controller.notify(notification) }

    // MARK: Connector approvals (OAuth)

    /// Requests that can still be approved, newest first.
    var pendingConsents: [RelayConsent] { consentBook.pending }
    var consents: [RelayConsent] { consentBook.consents }

    /// Connectors (oauth keys) that are connected now.
    var connectors: [RelayKeyInfo] { keys.filter { $0.isActive && $0.isOAuth } }

    func relayConsentRequested(_ consent: RelayConsent) {
        let action = consentBook.receive(consent)
        controller.changed()
        switch action {
        case .banner:
            // A new request, or the same one with a new code (its banner is updated in place). A reconnect's re-send never lands here.
            Task { await presentConsentBanner(consent) }
            scheduleConsentExpiry()
        case .listOnly: scheduleConsentExpiry()
        case .none:
            if !consent.isPending() { dismissConsentBanner(id: consent.id) }
        }
    }

    func relayConsentResolved(id: String, status: String) {
        consentBook.remove(id: id)
        dismissConsentBanner(id: id)
        controller.changed()
        if status == "approved" { Task { await refreshKeys() } }
    }

    private func dismissConsentBanner(id: String) {
        controller.confirmations.drop(app: Self.consentApp, id: id)
        controller.dismissItem(app: Self.consentApp, id: id, action: nil)
    }

    /// A request that ran out leaves the pending list and its banner goes with it, without waiting for the relay to say so.
    private func scheduleConsentExpiry() {
        guard let next = consentBook.nextExpiry else { return }
        consentExpiry?.cancel()
        consentExpiry = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(max(0.5, next.timeIntervalSinceNow + 0.5) * 1e9))
            guard !Task.isCancelled, let self else { return }
            for gone in self.consentBook.expire() { self.dismissConsentBanner(id: gone.id) }
            self.controller.changed()
            self.scheduleConsentExpiry()
        }
    }

    /// The question lives on a banner (the inline strip of DESIGN 8): Approve / Deny, no window, no focus change. Closing the
    /// banner without answering leaves the request pending; its code is still in Settings > Cloud.
    private func presentConsentBanner(_ c: RelayConsent) async {
        HeraldIdentity.ensureRegistered(registry: controller.registry, supportDirectory: controller.supportDirectory, iconPNG: nil)
        let body = c.isDevice
            ? "Approve \(c.clientName) to send you notifications? Code \(c.userCode ?? "")"
            : "\(c.clientName) is asking to connect to Herald."
        var n = HeraldNotification(app: Self.consentApp, id: c.id, title: "Connector request", body: body)
        n.persistent = true
        n.group = HeraldIdentity.connectorsGroup
        n.metadata = .object(["source": .string("connector-approval")])
        guard (try? await controller.notify(n)) != nil else { return }
        let host = c.redirectHost ?? "its own site"
        let question: BannerConfirmation = c.isDevice
            ? .connectorConsent(name: c.clientName, host: host, code: c.userCode)
            : .connectorConsent(name: c.clientName, host: host)
        controller.confirmations.ask(question, app: Self.consentApp, id: c.id) { [weak self] choice in
            switch choice {
            case .approve: Task { await self?.decideConsent(id: c.id, approve: true) }
            case .deny: Task { await self?.decideConsent(id: c.id, approve: false) }
            default: break
            }
        }
    }

    /// Approve or deny from the banner or Settings. A request already settled elsewhere (409) or expired (410) just goes away.
    func decideConsent(id: String, approve: Bool) async {
        guard let api = client.api, isPaired else { return }
        do {
            try await api.decideConsent(id: id, approve: approve)
            lastError = nil
        } catch RelayError.http(let code, _) where code == 409 || code == 410 {
            lastError = code == 410 ? "That connector request expired. Start the connection again." : nil
        } catch {
            lastError = error.localizedDescription
            controller.changed()
            return
        }
        consentBook.remove(id: id)
        dismissConsentBanner(id: id)
        await refreshKeys()
    }

    /// Settings > Cloud opens: what the relay still holds. The list is refreshed silently: a request is a banner once, when it arrives.
    func refreshConsents() async {
        guard let api = client.api, isPaired, let list = try? await api.consents() else { return }
        consentBook.replaceAll(with: list)
        scheduleConsentExpiry()
        controller.changed()
    }

    func relayConnectors() async -> RelayConnectorsReply {
        if isPaired { await refreshKeys(); await refreshConsents() }
        return RelayConnectorsReply(
            connectors: connectors,
            pending: pendingConsents.map { .init(id: $0.id, clientName: $0.clientName, redirectHost: $0.redirectHost, expiresAt: $0.expiresAt, userCode: $0.isDevice ? $0.userCode : nil) })
    }

    // MARK: Hooks from the rest of the app

    static func isCloud(_ app: String) -> Bool { app.hasPrefix(RelayDefaults.appPrefix) }

    func speechFinished(app: String, id: String) { if Self.isCloud(app) { client.reportSpoken(id: id) } }
    func replySent(app: String, id: String, text: String) { if Self.isCloud(app) { client.reportReply(id: id, text: text) } }

    // MARK: Pairing and keys (Settings, API)

    func relayPair() async throws -> (code: String, deviceId: String) {
        guard let api = client.api else { throw RelayError.transport("the relay URL is not valid") }
        let custom = cloudConfig.value.deviceName
        let name = custom.isEmpty ? (Host.current().localizedName ?? "Mac") : custom
        lastError = nil
        do {
            let started = try await api.startPairing(deviceName: name, pairingSecret: cloudSecrets.get(.pairingSecret))
            pairingCode = started.code
            controller.changed()
            let paired = try await api.pair(code: started.code, deviceName: name)
            guard tokens.save(paired.deviceToken) else { throw RelayError.transport("could not save the device token in the Keychain") }
            store.update { $0.deviceId = paired.deviceId; $0.pairedAt = Date() }
            pairingCode = nil
            client.start()
            // This Mac may have paired before (an unpair that did not reach the relay, a redeploy that rotated its secrets): drop its
            // same-name and stale entries so the relay never points an approval at a dead one.
            await pruneDevices()
            await refreshKeys()
            controller.changed()
            return (started.code, paired.deviceId)
        } catch {
            pairingCode = nil
            lastError = error.localizedDescription
            controller.changed()
            throw error
        }
    }

    /// Tells the relay to forget this Mac (revoking every key and connector), then forgets the pairing here. When the relay cannot
    /// be reached nothing is forgotten (so nothing stays valid unseen) unless `force`.
    func relayUnpair() async throws { try await relayUnpair(force: false) }

    func relayUnpair(force: Bool) async throws {
        if let api = client.api {
            do { try await api.unpair() }
            catch RelayError.http(let code, _) where code == 401 || code == 404 { /* already gone */ }
            catch { if !force { throw error } }
        }
        client.stop()
        tokens.delete()
        store.update { $0.deviceId = nil; $0.pairedAt = nil; $0.lastSeenAt = nil }
        keys = []; usage = nil; issuerKeys = []; consentBook = ConsentBook(); devices = []
        client.start()
        controller.changed()
    }

    /// The Macs on the relay, as the last call saw them (Settings > Cloud > Advanced).
    private(set) var devices: [RelayDeviceEntry] = []

    /// Asks the relay to drop this Mac's same-name and stale siblings. Best effort: an older relay answers 404.
    func pruneDevices() async {
        guard let api = client.api, isPaired, let r = try? await api.prune() else { return }
        devices = r.devices
        controller.changed()
    }

    func refreshDevices() async {
        guard let api = client.api, isPaired, let list = try? await api.devices() else { return }
        devices = list
        controller.changed()
    }

    /// Removes an entry the relay allows this Mac to remove (same name, rotated credentials or idle for a week).
    func removeDevice(id: String) async throws {
        guard let api = client.api, isPaired else { throw RelayError.notPaired }
        try await api.removeDevice(id: id)
        await refreshDevices()
    }

    func refreshKeys() async {
        guard let api = client.api, isPaired else { return }
        do {
            keys = try await api.listKeys()
            lastError = nil
            reconcileCloudApps()
        } catch { lastError = error.localizedDescription }
        controller.changed()
    }

    func relayCreateKey(name: String, client kind: String) async throws -> RelayKeyCreated {
        guard let api = client.api, isPaired else { throw RelayError.notPaired }
        let made = try await api.createKey(name: name, client: kind)
        await registerIssuer(name: made.name, client: made.client, source: .staticKey)
        issuerKeys.insert(made.id)
        await refreshKeys()
        return RelayKeyCreated(id: made.id, name: made.name, client: made.client, scope: made.scope, key: made.key,
                               mcpURL: ConnectorConfig.mcpURL(relay: relayURL),
                               connectorConfig: ConnectorConfig.block(relayURL: relayURL, key: made.key, name: made.name))
    }

    func relayRevokeKey(id: String) async throws {
        guard let api = client.api, isPaired else { throw RelayError.notPaired }
        try await api.revokeKey(id: id)
        await refreshKeys()
    }

    func relayUsage() async throws -> RelayUsage {
        guard let api = client.api, isPaired else { throw RelayError.notPaired }
        let u = try await api.usage()
        usage = u
        controller.changed()
        return u
    }

    func relayStatus() async -> RelayStatusReply {
        if isPaired { await refreshKeys(); await refreshDevices() }
        let s = store.value
        return RelayStatusReply(paired: isPaired, state: client.state.label, online: client.state == .online, relayURL: s.relayURL,
                                mcpURL: ConnectorConfig.mcpURL(relay: s.relayURL), deviceId: s.deviceId, lastSeenAt: s.lastSeenAt,
                                keys: keys, log: s.log, devices: isPaired ? devices : nil)
    }
}
