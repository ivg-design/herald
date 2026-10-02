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
    private(set) var consents: [RelayConsent] = []
    static let consentApp = "herald.connectors"
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
        client.onChange = { [weak self] in self?.controller.changed(); self?.relaySwitch?.sync() }
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
        await registerIssuer(name: key.name, client: key.client)
        issuerKeys.insert(key.id)
    }

    private func registerIssuer(name: String, client: String) async {
        guard let agent = AgentIdentity(cloudKeyName: name, client: client) else { return }
        let custom = RelayIcon.customFile(slug: agent.slug, folder: AgentIssuer.iconsFolder(in: controller.supportDirectory))
        var png = try? Data(contentsOf: custom)
        if png == nil { png = await AgentInstall.iconPNG(for: agent, picked: nil) }
        _ = try? AgentIssuer.register(agent, iconPNG: png, supportDirectory: controller.supportDirectory, registry: controller.registry,
                                      manifests: controller.manifests, templates: controller.templates)
        controller.changed()
    }

    /// The icon a notification brought, applied once per distinct value for this key. The user's own icon (set in Settings) wins:
    /// `AgentIssuer.register` leaves one that does not live in Herald's icon folder alone.
    func relayApplyIcon(_ source: String, for key: RelayKeyRef) async {
        guard appliedIcons[key.id] != source, let agent = AgentIdentity(cloudKeyName: key.name, client: key.client) else { return }
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
    var pendingConsents: [RelayConsent] { consents.filter { $0.isPending() } }

    /// Connectors (oauth keys) that are connected now.
    var connectors: [RelayKeyInfo] { keys.filter { $0.isActive && $0.isOAuth } }

    func relayConsentRequested(_ consent: RelayConsent) {
        guard consent.status == "pending" else { return }
        let isNew = !consents.contains { $0.id == consent.id }
        consents.removeAll { $0.id == consent.id }
        consents.insert(consent, at: 0)
        controller.changed()
        // A reconnect re-sends what is still pending: ask once per request.
        if isNew { Task { await presentConsentBanner(consent) } }
    }

    func relayConsentResolved(id: String, status: String) {
        consents.removeAll { $0.id == id }
        controller.confirmations.drop(app: Self.consentApp, id: id)
        controller.dismissItem(app: Self.consentApp, id: id, action: nil)
        controller.changed()
        if status == "approved" { Task { await refreshKeys() } }
    }

    /// The question lives on a banner (the inline strip of DESIGN 8): Approve / Deny, no window, no focus change. Closing the
    /// banner without answering leaves the request pending; its code is still in Settings > Cloud.
    private func presentConsentBanner(_ c: RelayConsent) async {
        _ = try? controller.register(HeraldAppRegistration(app: Self.consentApp, appName: "Herald connectors"))
        let body = c.isDevice
            ? "Approve \(c.clientName) to send you notifications? Code \(c.userCode ?? "")"
            : "\(c.clientName) is asking to connect to Herald."
        var n = HeraldNotification(app: Self.consentApp, id: c.id, title: "Connector request", body: body)
        n.persistent = true
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
        consents.removeAll { $0.id == id }
        controller.confirmations.drop(app: Self.consentApp, id: id)
        controller.dismissItem(app: Self.consentApp, id: id, action: nil)
        await refreshKeys()
    }

    /// Settings > Cloud opens: what the relay still holds (a request pushed while Herald was off would not be on screen).
    func refreshConsents() async {
        guard let api = client.api, isPaired, let list = try? await api.consents() else { return }
        let pending = list.filter { $0.isPending() }
        let known = Set(consents.map(\.id))
        consents = pending
        controller.changed()
        for c in pending where !known.contains(c.id) { await presentConsentBanner(c) }
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
        keys = []; usage = nil; issuerKeys = []; consents = []
        client.start()
        controller.changed()
    }

    func refreshKeys() async {
        guard let api = client.api, isPaired else { return }
        do {
            keys = try await api.listKeys()
            lastError = nil
        } catch { lastError = error.localizedDescription }
        controller.changed()
    }

    func relayCreateKey(name: String, client kind: String) async throws -> RelayKeyCreated {
        guard let api = client.api, isPaired else { throw RelayError.notPaired }
        let made = try await api.createKey(name: name, client: kind)
        await registerIssuer(name: made.name, client: made.client)
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
        if isPaired { await refreshKeys() }
        let s = store.value
        return RelayStatusReply(paired: isPaired, state: client.state.label, online: client.state == .online, relayURL: s.relayURL,
                                mcpURL: ConnectorConfig.mcpURL(relay: s.relayURL), deviceId: s.deviceId, lastSeenAt: s.lastSeenAt,
                                keys: keys, log: s.log)
    }
}
