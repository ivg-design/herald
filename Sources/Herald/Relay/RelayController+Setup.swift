import AppKit
import Foundation
import HeraldClient

/// The deploy steps as they come in, readable from the UI while the deploy runs on another thread.
final class DeployLog: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [DeployEvent] = []
    var events: [DeployEvent] { lock.lock(); defer { lock.unlock() }; return items }
    func reset() { lock.lock(); items = []; lock.unlock() }
    func add(_ e: DeployEvent) {
        lock.lock()
        // a step's "started" is replaced by its "done" / "failed"
        if let i = items.lastIndex(where: { $0.step == e.step && $0.phase == .started }) { items[i] = e } else { items.append(e) }
        lock.unlock()
    }
}

/// Enable relay: deploy the relay to the user's Cloudflare account, pair with it, keep it up to date, and everything the Advanced
/// section and the local API/MCP tools do with it.
extension RelayController: RelaySwitchBackend, RelaySetupBackend {
    // MARK: Switch backend

    var isOnline: Bool { client.state == .online }

    func pair() async throws { _ = try await relayPair() }
    func unpair() async throws { try await relayUnpair() }

    func connect(timeout seconds: Double) async -> Bool {
        client.start()
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            if client.state == .online { return true }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        return client.state == .online
    }

    // MARK: Bundle and version

    /// Resources/relay in the app bundle (worker.js and bundle.json), made by `make relay-bundle`.
    var bundle: WorkerBundle? {
        guard let meta = Bundle.main.url(forResource: "bundle", withExtension: "json", subdirectory: "relay") else { return nil }
        return try? WorkerBundle.load(from: meta.deletingLastPathComponent())
    }

    var bundledVersion: String { String((bundle?.sourceHash ?? "").prefix(12)) }
    var deployedVersion: String? {
        let h = healthBundle ?? (cloudConfig.value.deployedHash.isEmpty ? nil : cloudConfig.value.deployedHash)
        return h.map { String($0.prefix(12)) }
    }
    var updateAvailable: Bool {
        guard let b = bundle?.sourceHash, let d = healthBundle ?? (cloudConfig.value.deployedHash.isEmpty ? nil : cloudConfig.value.deployedHash) else { return false }
        return b != d
    }

    /// Asks the relay what it is running (GET /health), for "Update available".
    func refreshHealth() async {
        guard !relayURL.isEmpty else { healthBundle = nil; return }
        if case .success(let h) = await CloudflareDeployer.health(url: relayURL, http: URLSessionRelayHTTP()) { healthBundle = h.bundle }
        controller.changed()
    }

    var hasCloudflareToken: Bool { !(cloudSecrets.get(.apiToken) ?? "").isEmpty }
    var deployEvents: [DeployEvent] { deployLog.events }
    var pairingSecretValue: String? { cloudSecrets.get(.pairingSecret) }

    // MARK: Token

    func setCloudflareToken(_ token: String) async throws {
        let t = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.count >= 20, !t.contains(" ") else { throw BackendError(400, "That does not look like a Cloudflare API token.") }
        guard cloudSecrets.set(.apiToken, t) else { throw BackendError(500, "Could not save the token in the Keychain.") }
        deployFailure = nil
        controller.changed()
    }

    func forgetCloudflareToken() { cloudSecrets.remove(.apiToken); controller.changed() }

    // MARK: Deploy

    func deployRelay() async throws -> RelayDeployReply {
        guard !deployRunning else { throw BackendError(409, "A deploy is already running.") }
        guard let bundle else { throw BackendError(500, "This build of Herald has no bundled relay (Resources/relay).") }
        deployRunning = true; deployFailure = nil; deployLog.reset(); controller.changed()
        defer { deployRunning = false; controller.changed() }
        let log = deployLog
        let deployer = CloudflareDeployer(secrets: cloudSecrets)
        do {
            let r = try await deployer.deploy(config: cloudConfig.value, bundle: bundle) { [weak self] e in
                log.add(e)
                DispatchQueue.main.async { self?.controller.changed() }
            }
            let previousCustom = cloudConfig.value.customURL
            defer { ownPreviousURLs = [] }
            cloudConfig.update {
                $0.accountId = r.accountId; $0.subdomain = r.subdomain; $0.deployedHash = r.bundleHash; $0.deployedAt = Date()
                if $0.customDomain != nil { $0.customDomain?.attached = r.customURL != nil }
            }
            healthBundle = r.bundleHash
            var warnings = r.warnings
            let target = r.customURL ?? r.workerURL
            if relayURL != target {
                // The same Worker answers on both addresses and the device token is signed by the Worker, not tied to a hostname:
                // moving between them keeps this Mac paired. Only a different relay (or a token the relay refuses) re-pairs.
                let sameWorker = isPaired && ([r.workerURL, r.customURL, previousCustom].compactMap { $0 } + ownPreviousURLs).contains(relayURL)
                if sameWorker {
                    client.stop(); relayURL = target; healthBundle = r.bundleHash
                    client.start()
                    if await !deviceTokenWorks() {
                        try? await relayUnpair(force: true)
                    } else if r.customURL != nil {
                        warnings.append("Connectors already added to a cloud agent are bound to the old address. Reconnect them with the new one: \(ConnectorConfig.mcpURL(relay: target)).")
                    }
                } else {
                    if isPaired { try? await relayUnpair(force: true) }
                    relayURL = target
                }
            }
            await relaySwitch.turnOn()
            if case .failed(let m) = relaySwitch.state { deployFailure = m; throw BackendError(502, m) }
            await refreshKeys()
            lastDeployWarnings = warnings
            return RelayDeployReply(deployed: true, upgraded: r.upgraded, relayURL: target, paired: isPaired, online: isOnline,
                                    steps: log.events.map(RelayStepReport.init), workersDevURL: r.workerURL, customURL: r.customURL, warnings: warnings)
        } catch let e as BackendError { throw e }
        catch let e as CloudflareError { deployFailure = e.message; throw BackendError(e.status == 0 ? 502 : e.status, e.errorDescription ?? e.message) }
        catch { deployFailure = error.localizedDescription; throw error }
    }

    /// Does the relay at the current URL accept this Mac's device token? (A 401 means pair again.)
    private func deviceTokenWorks() async -> Bool {
        guard let api = client.api else { return false }
        do { _ = try await api.listKeys(); return true }
        catch RelayError.http(let code, _) where code == 401 { return false }
        catch { return true }   // unreachable for now is not a token problem
    }

    func relayZones() async throws -> RelayZonesReply {
        do {
            let z = try await CloudflareDeployer(secrets: cloudSecrets).zones(config: cloudConfig.value)
            return RelayZonesReply(zones: z.map { RelayZone(id: $0.id, name: $0.name, status: $0.status) })
        } catch let e as CloudflareError { throw BackendError(e.status == 0 ? 502 : e.status, e.errorDescription ?? e.message) }
    }

    func deleteRelay() async throws -> RelayDeleteReply {
        let deployer = CloudflareDeployer(secrets: cloudSecrets)
        do {
            try? await relayUnpair(force: true)
            let note = try await deployer.deleteRelay(config: cloudConfig.value)
            cloudConfig.update { $0.deployedHash = ""; $0.deployedAt = nil; $0.customDomain?.attached = false }
            cloudSecrets.remove(.pairingSecret); cloudSecrets.remove(.relaySecret)
            relayURL = ""; healthBundle = nil
            relaySwitch.sync()
            return RelayDeleteReply(deleted: true, note: note)
        } catch let e as CloudflareError { throw BackendError(e.status == 0 ? 502 : e.status, e.errorDescription ?? e.message) }
    }

    // MARK: Settings

    func relaySettings() async -> RelaySettingsReply {
        RelaySettingsReply(settings: cloudConfig.value, pairingSecretSet: pairingSecretValue != nil, errors: cloudConfig.value.validate(),
                           redeployed: false, steps: [])
    }

    /// Validates and saves; a change to a value that lives in the Worker redeploys it.
    func updateRelaySettings(_ patch: [String: JSONValue]) async throws -> RelaySettingsReply {
        var patch = patch
        var newURL: String?
        var newPairing: String?
        if case .string(let u)? = patch.removeValue(forKey: "relayURL") {
            let t = u.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty, URL(string: t)?.scheme?.hasPrefix("http") != true { throw BackendError(400, "relayURL must be an http(s) address") }
            newURL = t
        }
        if case .string(let p)? = patch.removeValue(forKey: "pairingSecret") {
            guard p.count >= 8 else { throw BackendError(400, "pairingSecret must be at least 8 characters") }
            newPairing = p
        }
        let old = cloudConfig.value
        let new = try old.applying(patch)
        let errors = new.validate()
        guard errors.isEmpty else { throw BackendError(400, errors.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)" }.joined(separator: "; ")) }
        ownPreviousURLs = [old.canonicalURL].compactMap { $0 }
        cloudConfig.update { $0 = new.with(deployedHash: old.deployedHash, deployedAt: old.deployedAt) }
        client.pingSeconds = TimeInterval(new.pingSeconds)
        if let newURL, newURL != relayURL { relayURL = newURL; healthBundle = nil }
        if let newPairing { cloudSecrets.set(.pairingSecret, newPairing) }
        var steps: [RelayStepReport] = []
        var redeployed = false
        let deployed = !old.deployedHash.isEmpty
        if deployed, new.needsRedeploy(comparedTo: old) || newPairing != nil {
            let r = try await deployRelay()
            steps = r.steps; redeployed = true
        }
        controller.changed()
        return RelaySettingsReply(settings: cloudConfig.value, pairingSecretSet: pairingSecretValue != nil, errors: [:], redeployed: redeployed, steps: steps, warnings: redeployed ? lastDeployWarnings : [])
    }

    // MARK: Status

    func setupStatus() async -> RelaySetupStatus {
        if isPaired, healthBundle == nil { await refreshHealth() }
        let url = relayURL
        let state: String
        if deployRunning { state = "deploying" }
        else if deployFailure != nil, !isPaired { state = "error" }
        else if url.isEmpty { state = hasCloudflareToken ? "ready" : "token-needed" }
        else if !isPaired { state = deployFailure != nil ? "error" : "ready" }
        else { state = isOnline ? "online" : (client.state == .connecting ? "connecting" : "offline") }
        return RelaySetupStatus(
            state: state, hasToken: hasCloudflareToken, paired: isPaired, online: isOnline, relayURL: url,
            mcpURL: url.isEmpty ? "" : ConnectorConfig.mcpURL(relay: url),
            workersDevURL: cloudConfig.value.workerURL, customURL: cloudConfig.value.customURL,
            customDomainRecommended: isPaired && cloudConfig.value.customDomain == nil, bundledVersion: bundledVersion, deployedVersion: deployedVersion,
            updateAvailable: updateAvailable, message: deployFailure ?? lastError, steps: deployEvents.map(RelayStepReport.init), usage: usage)
    }

    // MARK: Test, instructions

    func testRelay() async throws -> RelayTestReply {
        var r = try await testRelayCore()
        let bic = await CloudflareDeployer.browserCheckActive(url: relayURL, http: URLSessionRelayHTTP())
        r.browserCheckActive = bic
        if bic == true {
            r.detail += " Browser Integrity Check is active on this hostname (expected on workers.dev): Python's default User-Agent (Python-urllib/3.x) is rejected with Error 1010. Agents must send a custom User-Agent such as Herald-Agent/1.0, or set up a custom domain."
        }
        return r
    }

    private func testRelayCore() async throws -> RelayTestReply {
        let url = relayURL
        guard !url.isEmpty else { throw BackendError(409, "No relay is set up yet (relay_status).") }
        let http = URLSessionRelayHTTP()
        guard case .success = await CloudflareDeployer.health(url: url, http: http) else {
            return RelayTestReply(healthy: false, paired: isPaired, online: isOnline, roundTrip: false, receipt: nil, detail: "The relay did not answer GET /health.")
        }
        guard isPaired, let api = client.api else {
            return RelayTestReply(healthy: true, paired: false, online: false, roundTrip: false, receipt: nil, detail: "The relay is up, but this Mac is not paired with it.")
        }
        guard isOnline else {
            return RelayTestReply(healthy: true, paired: true, online: false, roundTrip: false, receipt: nil, detail: "Paired, but the connection is not up yet.")
        }
        // A temporary key sends a notification through the relay; the Mac shows it and reports the receipt back.
        let name = "herald-test-" + String(UUID().uuidString.prefix(6)).lowercased()
        let made = try await api.createKey(name: name, client: "other")
        defer { Task { try? await api.revokeKey(id: made.id); await refreshKeys() } }
        let nid = "test-" + UUID().uuidString.prefix(8)
        var r = URLRequest(url: URL(string: url + "/v1/notify")!)
        r.httpMethod = "POST"; r.setValue("Bearer " + made.key, forHTTPHeaderField: "Authorization"); r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.httpBody = try JSONSerialization.data(withJSONObject: ["title": "Herald relay test", "body": "The relay works.", "notificationId": String(nid)])
        let (_, h) = try await http.send(r)
        guard (200..<300).contains(h.statusCode) else {
            return RelayTestReply(healthy: true, paired: true, online: true, roundTrip: false, receipt: nil, detail: "The relay refused the test notification (\(h.statusCode)).")
        }
        for _ in 0..<20 {
            try? await Task.sleep(nanoseconds: 500_000_000)
            var g = URLRequest(url: URL(string: url + "/v1/receipts/\(nid)")!)
            g.setValue("Bearer " + made.key, forHTTPHeaderField: "Authorization")
            if let (d, gh) = try? await http.send(g), gh.statusCode == 200, let o = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] {
                if o["displayed"] as? Bool == true { return RelayTestReply(healthy: true, paired: true, online: true, roundTrip: true, receipt: "displayed", detail: "A test notification went through the relay and was shown on this Mac.") }
                if o["suppressed"] as? Bool == true {
                    return RelayTestReply(healthy: true, paired: true, online: true, roundTrip: true, receipt: "suppressed", detail: "It reached this Mac; your settings held the banner back (\(o["reason"] as? String ?? "suppressed")).")
                }
            }
        }
        return RelayTestReply(healthy: true, paired: true, online: true, roundTrip: false, receipt: nil, detail: "The notification was accepted but no receipt came back in 10 seconds.")
    }

    func relayInstructions(client kind: String) async throws -> String {
        let url = ConnectorConfig.mcpURL(relay: relayURL.isEmpty ? "https://your-relay.workers.dev" : relayURL)
        switch kind.lowercased() {
        case "chatgpt", "openai": return RelayInstructions.oauth(mcpURL: url)
        case "claude", "codex", "claude-code": return RelayInstructions.staticKey(mcpURL: url)
        case "device", "no-browser": return RelayInstructions.deviceFlow(origin: relayURL.isEmpty ? "https://your-relay.workers.dev" : relayURL)
        default: throw BackendError(400, "client must be chatgpt, claude, codex or device")
        }
    }
}

extension RelayCloudConfig {
    func with(deployedHash: String, deployedAt: Date?) -> RelayCloudConfig {
        var c = self; c.deployedHash = deployedHash; c.deployedAt = deployedAt; return c
    }
}
