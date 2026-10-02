import AppKit
import Network
import Foundation
import HeraldClient

/// The app's side of the cloud relay: owns the `RelayClient`, answers Settings > Cloud and `/v1/relay/*`, registers an issuer
/// (`cloud.<key name>`) per agent key, and wires speech, replies and voice replies to the relay's receipts.
@MainActor
final class RelayController: RelayHost, RelayBackend {
    private unowned let controller: AppController
    let store: RelayStateStore
    let dedupe: RelayDedupe
    let tokens: RelayTokenStore
    private(set) var client: RelayClient!
    private(set) var keys: [RelayKeyInfo] = []
    private(set) var usage: RelayUsage?
    private(set) var pairingCode: String?
    private(set) var lastError: String?
    private var issuerKeys = Set<String>()
    private var monitor: NWPathMonitor?
    private var observers: [NSObjectProtocol] = []

    init(controller: AppController) {
        self.controller = controller
        let dir = controller.supportDirectory
        store = RelayStateStore(file: dir.appendingPathComponent("relay.json"))
        dedupe = RelayDedupe(file: dir.appendingPathComponent("relay-dedupe.json"))
        // A throwaway support folder (tests, HERALD_SUPPORT_DIR) gets its own Keychain item, never the real token's.
        let isDefault = dir.standardizedFileURL == HeraldPaths.defaultSupportDirectory.standardizedFileURL
        tokens = KeychainTokenStore(service: isDefault ? "com.ivg.herald.relay" : "com.ivg.herald.relay.\(Self.stableHash(dir.path))")
        client = RelayClient(host: self, store: store, dedupe: dedupe, tokens: tokens)
        client.onChange = { [weak self] in self?.controller.changed() }
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
        let png = await AgentInstall.iconPNG(for: agent, picked: nil)
        _ = try? AgentIssuer.register(agent, iconPNG: png, supportDirectory: controller.supportDirectory, registry: controller.registry,
                                      manifests: controller.manifests, templates: controller.templates)
        controller.changed()
    }

    func relayDeliver(_ notification: HeraldNotification) async throws { _ = try await controller.notify(notification) }

    // MARK: Hooks from the rest of the app

    static func isCloud(_ app: String) -> Bool { app.hasPrefix(RelayDefaults.appPrefix) }

    func speechFinished(app: String, id: String) { if Self.isCloud(app) { client.reportSpoken(id: id) } }
    func replySent(app: String, id: String, text: String) { if Self.isCloud(app) { client.reportReply(id: id, text: text) } }

    // MARK: Pairing and keys (Settings, API)

    func relayPair() async throws -> (code: String, deviceId: String) {
        guard let api = client.api else { throw RelayError.transport("the relay URL is not valid") }
        let name = Host.current().localizedName ?? "Mac"
        lastError = nil
        do {
            let started = try await api.startPairing(deviceName: name)
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

    func relayUnpair() async throws {
        if let api = client.api { try? await api.unpair() }
        client.stop()
        tokens.delete()
        store.update { $0.deviceId = nil; $0.pairedAt = nil; $0.lastSeenAt = nil }
        keys = []; usage = nil; issuerKeys = []
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
