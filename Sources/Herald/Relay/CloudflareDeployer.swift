import Foundation
import Security
import CryptoKit

// MARK: - Secrets (Keychain)

/// The three secrets of a relay Herald deploys. The Keychain in the app, memory in tests.
public protocol CloudflareSecrets: AnyObject, Sendable {
    func get(_ name: CloudflareSecretName) -> String?
    @discardableResult func set(_ name: CloudflareSecretName, _ value: String) -> Bool
    func remove(_ name: CloudflareSecretName)
}

public enum CloudflareSecretName: String, Sendable, CaseIterable {
    /// The user's Cloudflare API token (only ever sent to api.cloudflare.com).
    case apiToken = "cloudflare-api-token"
    /// Demanded by the relay on POST /v1/pair/start (X-Pairing-Secret); made by Herald at the first deploy.
    case pairingSecret = "relay-pairing-secret"
    /// Signs device ids inside the Worker; made by Herald at the first deploy, kept only to be able to redeploy from scratch.
    case relaySecret = "relay-signing-secret"
}

public final class MemoryCloudflareSecrets: CloudflareSecrets, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [CloudflareSecretName: String] = [:]
    public init() {}
    public func get(_ n: CloudflareSecretName) -> String? { lock.lock(); defer { lock.unlock() }; return values[n] }
    public func set(_ n: CloudflareSecretName, _ v: String) -> Bool { lock.lock(); values[n] = v; lock.unlock(); return true }
    public func remove(_ n: CloudflareSecretName) { lock.lock(); values[n] = nil; lock.unlock() }
}

public final class KeychainCloudflareSecrets: CloudflareSecrets, @unchecked Sendable {
    private let service: String
    public init(service: String = "com.ivg.herald.cloudflare") { self.service = service }
    private func query(_ n: CloudflareSecretName) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: n.rawValue]
    }
    public func get(_ n: CloudflareSecretName) -> String? {
        var q = query(n); q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }
    public func set(_ n: CloudflareSecretName, _ v: String) -> Bool {
        remove(n)
        var q = query(n); q[kSecValueData as String] = Data(v.utf8)
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(q as CFDictionary, nil) == errSecSuccess
    }
    public func remove(_ n: CloudflareSecretName) { SecItemDelete(query(n) as CFDictionary) }
}

// MARK: - Bundle

/// The relay Worker as Herald ships it: one ES module (Resources/relay/worker.js, made by `make relay-bundle`) and its source hash.
public struct WorkerBundle: Sendable {
    public var script: Data
    public var sourceHash: String
    public var compatibilityDate: String
    public var mainModule: String

    public init(script: Data, sourceHash: String, compatibilityDate: String, mainModule: String = "worker.js") {
        self.script = script; self.sourceHash = sourceHash; self.compatibilityDate = compatibilityDate; self.mainModule = mainModule
    }

    /// Loads `worker.js` and `bundle.json` from a folder (the app's Resources/relay).
    public static func load(from dir: URL) throws -> WorkerBundle {
        struct Meta: Decodable { var sourceHash: String; var compatibilityDate: String; var mainModule: String }
        let script = try Data(contentsOf: dir.appendingPathComponent("worker.js"))
        let meta = try JSONDecoder().decode(Meta.self, from: Data(contentsOf: dir.appendingPathComponent("bundle.json")))
        return WorkerBundle(script: script, sourceHash: meta.sourceHash, compatibilityDate: meta.compatibilityDate, mainModule: meta.mainModule)
    }

    /// The hash `scripts/relay-bundle.sh` records: sha256 of the sorted "<sha256>  <path>" listing of relay/src/*.ts + wrangler.toml.
    public static func sourceHash(relayDirectory: URL) throws -> String {
        let src = relayDirectory.appendingPathComponent("src")
        var names = try FileManager.default.contentsOfDirectory(atPath: src.path).filter { $0.hasSuffix(".ts") }.map { "src/" + $0 }
        names.sort { Array($0.utf8).lexicographicallyPrecedes(Array($1.utf8)) }
        names.append("wrangler.toml")
        var listing = ""
        for n in names {
            let d = try Data(contentsOf: relayDirectory.appendingPathComponent(n))
            listing += SHA256.hash(data: d).map { String(format: "%02x", $0) }.joined() + "  " + n + "\n"
        }
        return SHA256.hash(data: Data(listing.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Errors, progress

public struct CloudflareError: Error, LocalizedError, Equatable, Sendable {
    public var step: DeployStep
    public var status: Int
    /// Cloudflare's own message(s), verbatim.
    public var message: String
    public var errorDescription: String? { "\(step.title): \(message)" }
}

public enum DeployStep: String, CaseIterable, Sendable {
    case verifyToken, account, subdomain, bucket, lifecycle, upload, route, health, delete
    // The custom domain (only when one is set): see docs/CLOUD.md "Custom domain".
    case zone, domain, configRule, wafSkip, botMode, domainHealth

    public var title: String {
        switch self {
        case .verifyToken: return "Check the API token"
        case .account: return "Find your Cloudflare account"
        case .subdomain: return "Find the workers.dev address"
        case .bucket: return "Create the voice-reply bucket"
        case .lifecycle: return "Set voice replies to expire"
        case .upload: return "Upload the relay"
        case .route: return "Switch on the workers.dev address"
        case .health: return "Wait for the relay to answer"
        case .delete: return "Delete the relay"
        case .zone: return "Find the zone"
        case .domain: return "Attach the custom domain"
        case .configRule: return "Switch off Browser Integrity Check for it"
        case .wafSkip: return "Skip the security-level challenge for it"
        case .botMode: return "Check Bot Fight Mode"
        case .domainHealth: return "Wait for the custom domain to answer"
        }
    }
}

public struct DeployEvent: Equatable, Sendable {
    public enum Phase: Equatable, Sendable { case started, done, failed }
    public var step: DeployStep
    public var phase: Phase
    public var detail: String
}

public struct DeployResult: Equatable, Sendable {
    public var accountId: String
    public var subdomain: String
    public var workerURL: String
    public var bundleHash: String
    public var upgraded: Bool
    /// https://<hostname> once the custom domain is attached and answering.
    public var customURL: String? = nil
    /// Not fatal, but the user must know (Bot Fight Mode on the zone, a rule that could not be written).
    public var warnings: [String] = []
}

public struct CloudflareZoneInfo: Equatable, Sendable { public var id: String; public var name: String; public var status: String }

// MARK: - Deployer

/// Deploys the relay Worker to the user's own Cloudflare account through the REST API: no wrangler, no Node. Every step is
/// idempotent, so running it again upgrades the Worker in place (same name, same Durable Object data, same secrets).
public struct CloudflareDeployer: Sendable {
    public static let apiBase = "https://api.cloudflare.com/client/v4"

    public var http: RelayHTTP
    public var secrets: CloudflareSecrets
    /// Waits between health polls; tests make it instant.
    public var sleep: @Sendable (TimeInterval) async -> Void
    public var healthAttempts = 30
    public var healthInterval: TimeInterval = 2

    public init(http: RelayHTTP = URLSessionRelayHTTP(), secrets: CloudflareSecrets,
                sleep: @escaping @Sendable (TimeInterval) async -> Void = { try? await Task.sleep(nanoseconds: UInt64($0 * 1e9)) }) {
        self.http = http; self.secrets = secrets; self.sleep = sleep
    }

    // MARK: Requests

    private struct Envelope: Decodable {
        struct E: Decodable { var code: Int?; var message: String? }
        var success: Bool?
        var errors: [E]?
        var result: AnyDecodable?
    }
    private struct AnyDecodable: Decodable {
        let value: Any
        init(from d: Decoder) throws {
            let c = try d.singleValueContainer()
            if c.decodeNil() { value = NSNull() }
            else if let v = try? c.decode(Bool.self) { value = v }
            else if let v = try? c.decode(Int.self) { value = v }
            else if let v = try? c.decode(Double.self) { value = v }
            else if let v = try? c.decode(String.self) { value = v }
            else if let v = try? c.decode([AnyDecodable].self) { value = v.map(\.value) }
            else if let v = try? c.decode([String: AnyDecodable].self) { value = v.mapValues(\.value) }
            else { value = NSNull() }
        }
    }

    private struct Reply { var status: Int; var result: Any?; var errors: [(code: Int, message: String)]; var ok: Bool }

    private func call(_ method: String, _ path: String, token: String, json: Any? = nil, body: Data? = nil, contentType: String? = nil) async throws -> Reply {
        var r = URLRequest(url: URL(string: Self.apiBase + path)!)
        r.httpMethod = method
        r.timeoutInterval = 60
        r.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        if let json { r.httpBody = try JSONSerialization.data(withJSONObject: json); r.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        if let body { r.httpBody = body; r.setValue(contentType, forHTTPHeaderField: "Content-Type") }
        let (d, h) = try await http.send(r)
        let env = try? JSONDecoder().decode(Envelope.self, from: d)
        let errs = (env?.errors ?? []).map { (code: $0.code ?? 0, message: $0.message ?? "") }
        let ok = (200..<300).contains(h.statusCode) && (env?.success ?? true)
        return Reply(status: h.statusCode, result: env?.result?.value, errors: errs, ok: ok)
    }

    private func fail(_ step: DeployStep, _ r: Reply) -> CloudflareError {
        let m = r.errors.map { $0.message }.filter { !$0.isEmpty }.joined(separator: "; ")
        return CloudflareError(step: step, status: r.status, message: m.isEmpty ? "Cloudflare answered \(r.status)" : m)
    }

    // MARK: Deploy

    /// Deploys (or upgrades) the relay. `config` is updated by the caller from the result. Progress is reported per step.
    public func deploy(config: RelayCloudConfig, bundle: WorkerBundle, progress: @escaping @Sendable (DeployEvent) -> Void = { _ in }) async throws -> DeployResult {
        guard let token = secrets.get(.apiToken), !token.isEmpty else {
            throw CloudflareError(step: .verifyToken, status: 0, message: "Paste your Cloudflare API token first.")
        }
        func run<T>(_ step: DeployStep, _ work: () async throws -> (T, String)) async throws -> T {
            progress(.init(step: step, phase: .started, detail: ""))
            do {
                let (v, detail) = try await work()
                progress(.init(step: step, phase: .done, detail: detail))
                return v
            } catch let e as CloudflareError {
                progress(.init(step: step, phase: .failed, detail: e.message)); throw e
            } catch {
                let e = CloudflareError(step: step, status: 0, message: error.localizedDescription)
                progress(.init(step: step, phase: .failed, detail: e.message)); throw e
            }
        }

        // 1. The token works.
        try await run(.verifyToken) { () -> (Void, String) in
            let r = try await call("GET", "/user/tokens/verify", token: token)
            guard r.ok else { throw fail(.verifyToken, r) }
            let status = ((r.result as? [String: Any])?["status"] as? String) ?? "active"
            guard status == "active" else { throw CloudflareError(step: .verifyToken, status: r.status, message: "The token is \(status). Create a new one.") }
            return ((), "token is active")
        }

        // 2. The account.
        let accountId: String = try await run(.account) { () -> (String, String) in
            if !config.accountId.isEmpty { return (config.accountId, config.accountId) }
            let r = try await call("GET", "/accounts", token: token)
            guard r.ok else { throw fail(.account, r) }
            let list = (r.result as? [[String: Any]]) ?? []
            guard let first = list.first, let id = first["id"] as? String else {
                throw CloudflareError(step: .account, status: r.status, message: "No Cloudflare account is visible to this token. Give it the Account Settings Read permission.")
            }
            if list.count > 1 {
                throw CloudflareError(step: .account, status: r.status, message: "This token sees \(list.count) accounts. Open Advanced and enter the account id to use.")
            }
            return (id, (first["name"] as? String) ?? id)
        }

        // 3. The workers.dev subdomain: use the account's, or make one.
        let subdomain: String = try await run(.subdomain) { () -> (String, String) in
            let r = try await call("GET", "/accounts/\(accountId)/workers/subdomain", token: token)
            if r.ok, let s = (r.result as? [String: Any])?["subdomain"] as? String, !s.isEmpty { return (s, s + ".workers.dev") }
            let wanted = config.subdomain.isEmpty ? "herald-" + Self.randomHex(3) : config.subdomain
            let put = try await call("PUT", "/accounts/\(accountId)/workers/subdomain", token: token, json: ["subdomain": wanted])
            guard put.ok else { throw fail(.subdomain, put) }
            let made = ((put.result as? [String: Any])?["subdomain"] as? String) ?? wanted
            return (made, "created \(made).workers.dev")
        }

        // 4. The R2 bucket (an existing one is fine).
        try await run(.bucket) { () -> (Void, String) in
            let r = try await call("POST", "/accounts/\(accountId)/r2/buckets", token: token, json: ["name": config.bucket])
            if r.ok { return ((), "created \(config.bucket)") }
            if r.status == 409 || r.errors.contains(where: { $0.code == 10004 }) { return ((), "\(config.bucket) already exists") }
            throw fail(.bucket, r)
        }

        // 5. Voice replies expire.
        try await run(.lifecycle) { () -> (Void, String) in
            let rule: [String: Any] = [
                "id": "expire-audio", "enabled": true, "conditions": ["prefix": ""],
                "deleteObjectsTransition": ["condition": ["type": "Age", "maxAge": config.audioRetentionDays * 86_400]],
            ]
            let r = try await call("PUT", "/accounts/\(accountId)/r2/buckets/\(config.bucket)/lifecycle", token: token, json: ["rules": [rule]])
            guard r.ok else { throw fail(.lifecycle, r) }
            return ((), "deleted after \(config.audioRetentionDays) days")
        }

        // 6. The Worker. First deploy: new Durable Object classes and the signing secret; later: same bindings, secrets kept.
        let upgraded: Bool = try await run(.upload) { () -> (Bool, String) in
            let exists = try await call("GET", "/accounts/\(accountId)/workers/scripts/\(config.workerName)/settings", token: token)
            let isUpgrade = exists.ok
            if !isUpgrade, exists.status != 404, !exists.errors.contains(where: { $0.code == 10007 }) { throw fail(.upload, exists) }

            var pairing = secrets.get(.pairingSecret)
            if pairing == nil { let p = Self.randomHex(16); secrets.set(.pairingSecret, p); pairing = p }
            var bindings: [[String: Any]] = [
                ["type": "durable_object_namespace", "name": "MAILBOX", "class_name": "Mailbox"],
                ["type": "durable_object_namespace", "name": "REGISTRY", "class_name": "Registry"],
                ["type": "r2_bucket", "name": "AUDIO", "bucket_name": config.bucket],
                ["type": "secret_text", "name": "PAIRING_SECRET", "text": pairing ?? ""],
            ]
            for (k, v) in config.workerVars(bundleHash: bundle.sourceHash).sorted(by: { $0.key < $1.key }) {
                bindings.append(["type": "plain_text", "name": k, "text": v])
            }
            var metadata: [String: Any] = [
                "main_module": bundle.mainModule, "compatibility_date": bundle.compatibilityDate,
                "observability": ["enabled": true],
            ]
            if isUpgrade {
                metadata["keep_bindings"] = ["secret_text"]
                if let own = secrets.get(.relaySecret) { bindings.append(["type": "secret_text", "name": "RELAY_SECRET", "text": own]) }
            } else {
                var signing = secrets.get(.relaySecret)
                if signing == nil { let s = Self.randomHex(32); secrets.set(.relaySecret, s); signing = s }
                bindings.append(["type": "secret_text", "name": "RELAY_SECRET", "text": signing ?? ""])
                metadata["migrations"] = ["new_tag": "v1", "new_sqlite_classes": ["Mailbox", "Registry"]]
            }
            metadata["bindings"] = bindings

            var form = MultipartForm()
            form.addJSON(name: "metadata", try JSONSerialization.data(withJSONObject: metadata, options: [.sortedKeys]))
            form.addFile(name: bundle.mainModule, filename: bundle.mainModule, contentType: "application/javascript+module", data: bundle.script)
            let r = try await call("PUT", "/accounts/\(accountId)/workers/scripts/\(config.workerName)", token: token,
                                   body: form.data, contentType: form.contentType)
            guard r.ok else { throw fail(.upload, r) }
            return (isUpgrade, isUpgrade ? "upgraded in place" : "created \(config.workerName)")
        }

        // 7. The workers.dev route.
        try await run(.route) { () -> (Void, String) in
            let r = try await call("POST", "/accounts/\(accountId)/workers/scripts/\(config.workerName)/subdomain", token: token,
                                   json: ["enabled": true, "previews_enabled": false])
            guard r.ok else { throw fail(.route, r) }
            return ((), "on")
        }

        // 8. It answers.
        let url = "https://\(config.workerName).\(subdomain).workers.dev"
        try await run(.health) { () -> (Void, String) in
            var last = "no answer yet"
            for attempt in 0..<healthAttempts {
                if attempt > 0 { await sleep(healthInterval) }
                switch await Self.health(url: url, http: http) {
                case .success(let h):
                    if h.bundle == bundle.sourceHash || h.bundle == nil { return ((), url) }
                    last = "still serving the previous version"
                case .failure(let e): last = e.localizedDescription
                }
            }
            throw CloudflareError(step: .health, status: 0, message: "\(url) did not answer in time (\(last)). It can take a minute after the first deploy; press Retry.")
        }

        // 9. The custom domain: Cloudflare's Browser Integrity Check blocks non-browser clients (cloud agents) on workers.dev and
        //    cannot be switched off there, so the relay also answers on a hostname in a zone the user controls.
        var customURL: String?
        var warnings: [String] = []
        if let cd = config.customDomain, !cd.hostname.isEmpty {
            let zone: CloudflareZoneInfo = try await run(.zone) { () -> (CloudflareZoneInfo, String) in
                let r = try await call("GET", "/zones?name=\(cd.zone)&account.id=\(accountId)", token: token)
                guard r.ok else { throw zoneFail(.zone, r) }
                guard let z = Self.zoneList(r).first(where: { $0.name == cd.zone }) else {
                    throw CloudflareError(step: .zone, status: 404, message: "No zone named \(cd.zone) in this Cloudflare account. Pick one of the zones Herald lists, or skip the custom domain.")
                }
                return (z, z.name)
            }
            try await run(.domain) { () -> (Void, String) in
                let body: [String: Any] = ["hostname": cd.hostname, "service": config.workerName, "environment": "production", "zone_id": zone.id, "zone_name": zone.name]
                let r = try await call("PUT", "/accounts/\(accountId)/workers/domains", token: token, json: body)
                guard r.ok else { throw zoneFail(.domain, r) }
                return ((), cd.hostname)
            }
            let expression = "(http.host eq \"\(cd.hostname)\")"
            try await run(.configRule) { () -> (Void, String) in
                let rule: [String: Any] = ["description": Self.ruleDescription, "expression": expression, "enabled": true,
                                           "action": "set_config", "action_parameters": ["bic": false]]
                return ((), try await upsertRule(step: .configRule, zoneId: zone.id, phase: "http_config_settings", rule: rule, token: token))
            }
            // The WAF skip and the Bot Fight Mode check are helpful, not the fix itself: a token without Zone WAF still gets the rest.
            do {
                try await run(.wafSkip) { () -> (Void, String) in
                    let rule: [String: Any] = ["description": Self.ruleDescription, "expression": expression, "enabled": true,
                                               "action": "skip", "action_parameters": ["products": ["bic", "securityLevel"]]]
                    return ((), try await upsertRule(step: .wafSkip, zoneId: zone.id, phase: "http_request_firewall_custom", rule: rule, token: token))
                }
            } catch let e as CloudflareError { warnings.append("The WAF skip rule was not written: \(e.message)") }
            do {
                try await run(.botMode) { () -> (Void, String) in
                    let r = try await call("GET", "/zones/\(zone.id)/bot_management", token: token)
                    guard r.ok else { throw zoneFail(.botMode, r) }
                    let o = (r.result as? [String: Any]) ?? [:]
                    var found: [String] = []
                    if o["fight_mode"] as? Bool == true {
                        found.append("Bot Fight Mode is on for \(zone.name). On the free plan no rule can bypass it, so it can still challenge cloud agents: turn it off under Security > Bots in the Cloudflare dashboard.")
                    }
                    if let m = o["sbfm_definitely_automated"] as? String, m != "allow" {
                        found.append("Super Bot Fight Mode is set to \(m) for definitely automated traffic on \(zone.name): set it to Allow under Security > Bots, or cloud agents are still blocked.")
                    }
                    warnings += found
                    return ((), found.isEmpty ? "off" : "ON: see the note")
                }
            } catch let e as CloudflareError { warnings.append("Could not check Bot Fight Mode: \(e.message)") }
            let host = "https://" + cd.hostname
            try await run(.domainHealth) { () -> (Void, String) in
                var last = "no answer yet"
                for attempt in 0..<healthAttempts {
                    if attempt > 0 { await sleep(healthInterval) }
                    switch await Self.health(url: host, http: http) {
                    case .success: return ((), host)
                    case .failure(let e): last = e.localizedDescription
                    }
                }
                throw CloudflareError(step: .domainHealth, status: 0, message: "\(host) did not answer in time (\(last)). Cloudflare issues the certificate in a minute or two; press Retry.")
            }
            customURL = host
        }
        return DeployResult(accountId: accountId, subdomain: subdomain, workerURL: url, bundleHash: bundle.sourceHash, upgraded: upgraded, customURL: customURL, warnings: warnings)
    }

    // MARK: Custom domain helpers

    public static let ruleDescription = "Herald relay: allow non-browser clients"

    private static let permissionHint = "Token is missing Zone permissions (Zone: Read, DNS: Edit, Workers Routes: Edit, Zone Settings: Edit, Config Settings: Edit, Zone WAF: Edit). Create a new token from the pre-filled page in Herald and paste it, or turn off the custom domain."

    /// A 401/403 on a zone call means the token lacks the Zone permissions; say so instead of Cloudflare's bare message.
    private func zoneFail(_ step: DeployStep, _ r: Reply) -> CloudflareError {
        if r.status == 401 || r.status == 403 || r.errors.contains(where: { [9109, 10000].contains($0.code) }) {
            let detail = r.errors.map(\.message).filter { !$0.isEmpty }.joined(separator: "; ")
            return CloudflareError(step: step, status: r.status, message: Self.permissionHint + (detail.isEmpty ? "" : " (Cloudflare: \(detail))"))
        }
        return fail(step, r)
    }

    private static func zoneList(_ r: Reply) -> [CloudflareZoneInfo] {
        ((r.result as? [[String: Any]]) ?? []).compactMap {
            guard let id = $0["id"] as? String, let name = $0["name"] as? String else { return nil }
            return CloudflareZoneInfo(id: id, name: name, status: ($0["status"] as? String) ?? "")
        }
    }

    /// Creates the phase's entry-point ruleset with the rule, or adds / updates the one rule (found by description) in it, leaving
    /// every other rule alone. Returns "created" / "updated" / "added".
    private func upsertRule(step: DeployStep, zoneId: String, phase: String, rule: [String: Any], token: String) async throws -> String {
        let base = "/zones/\(zoneId)/rulesets"
        let entry = try await call("GET", "\(base)/phases/\(phase)/entrypoint", token: token)
        if !entry.ok {
            if entry.status == 404 || entry.errors.contains(where: { $0.code == 10003 }) {
                let made = try await call("PUT", "\(base)/phases/\(phase)/entrypoint", token: token, json: ["rules": [rule]])
                guard made.ok else { throw zoneFail(step, made) }
                return "created"
            }
            throw zoneFail(step, entry)
        }
        let o = (entry.result as? [String: Any]) ?? [:]
        guard let rulesetId = o["id"] as? String else { throw CloudflareError(step: step, status: entry.status, message: "Cloudflare returned no ruleset for \(phase).") }
        let existing = ((o["rules"] as? [[String: Any]]) ?? []).first { $0["description"] as? String == Self.ruleDescription }
        if let rid = existing?["id"] as? String {
            let r = try await call("PATCH", "\(base)/\(rulesetId)/rules/\(rid)", token: token, json: rule)
            guard r.ok else { throw zoneFail(step, r) }
            return "updated"
        }
        let r = try await call("POST", "\(base)/\(rulesetId)/rules", token: token, json: rule)
        guard r.ok else { throw zoneFail(step, r) }
        return "added"
    }

    /// The zones this token can see in the account, for the custom-domain picker.
    public func zones(config: RelayCloudConfig) async throws -> [CloudflareZoneInfo] {
        guard let token = secrets.get(.apiToken), !token.isEmpty else {
            throw CloudflareError(step: .zone, status: 0, message: "Paste your Cloudflare API token first.")
        }
        var account = config.accountId
        if account.isEmpty {
            let r = try await call("GET", "/accounts", token: token)
            guard r.ok else { throw fail(.account, r) }
            let list = (r.result as? [[String: Any]]) ?? []
            guard list.count == 1, let id = list[0]["id"] as? String else {
                throw CloudflareError(step: .account, status: r.status, message: "Enter the account id in Advanced first (the token sees \(list.count) accounts).")
            }
            account = id
        }
        let r = try await call("GET", "/zones?account.id=\(account)&per_page=50", token: token)
        guard r.ok else { throw zoneFail(.zone, r) }
        return Self.zoneList(r).sorted { $0.name < $1.name }
    }

    // MARK: Health

    public struct Health: Equatable, Sendable { public var ok: Bool; public var bundle: String? }

    public static func health(url: String, http: RelayHTTP) async -> Swift.Result<Health, RelayError> {
        guard let u = URL(string: url + "/health") else { return .failure(.transport("bad URL")) }
        var r = URLRequest(url: u); r.timeoutInterval = 15
        do {
            let (d, h) = try await http.send(r)
            guard h.statusCode == 200, let o = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any], o["service"] as? String == "herald-relay" else {
                return .failure(.http(h.statusCode, "not a Herald relay"))
            }
            return .success(Health(ok: (o["ok"] as? Bool) ?? false, bundle: o["bundle"] as? String))
        } catch let e as RelayError { return .failure(e) } catch { return .failure(.transport(error.localizedDescription)) }
    }

    public static let defaultLibraryUserAgent = "Python-urllib/3.12"

    /// Is Cloudflare's Browser Integrity Check active on this hostname? Asks /health and /mcp with Python's default User-Agent and
    /// with a custom one: 403 for the first only (Error 1010) means yes. nil when the relay cannot be reached either way.
    public static func browserCheckActive(url: String, http: RelayHTTP) async -> Bool? {
        func status(_ path: String, ua: String) async -> Int? {
            guard let u = URL(string: url + path) else { return nil }
            var r = URLRequest(url: u); r.timeoutInterval = 15; r.setValue(ua, forHTTPHeaderField: "User-Agent")
            return try? await http.send(r).1.statusCode
        }
        var answered = false
        for path in ["/health", "/mcp"] {
            guard let plain = await status(path, ua: "Herald-Agent/1.0") else { continue }
            answered = true
            if let lib = await status(path, ua: defaultLibraryUserAgent), lib == 403, plain != 403 { return true }
        }
        return answered ? false : nil
    }

    // MARK: Delete

    /// Deletes the Worker (and, with it, every mailbox, key and queued notification) and tries to delete the bucket.
    /// A bucket that still holds voice replies cannot be deleted by Cloudflare; that is reported, not fatal.
    public func deleteRelay(config: RelayCloudConfig, progress: @escaping @Sendable (DeployEvent) -> Void = { _ in }) async throws -> String? {
        guard let token = secrets.get(.apiToken), !config.accountId.isEmpty else {
            throw CloudflareError(step: .delete, status: 0, message: "Herald needs the API token and the account id to delete the relay.")
        }
        progress(.init(step: .delete, phase: .started, detail: ""))
        let r = try await call("DELETE", "/accounts/\(config.accountId)/workers/scripts/\(config.workerName)?force=true", token: token)
        if !r.ok, r.status != 404 {
            let e = fail(.delete, r); progress(.init(step: .delete, phase: .failed, detail: e.message)); throw e
        }
        let b = try await call("DELETE", "/accounts/\(config.accountId)/r2/buckets/\(config.bucket)", token: token)
        var note: String?
        if !b.ok, b.status != 404 {
            note = "The Worker is deleted. The bucket \(config.bucket) still holds voice replies (Cloudflare only deletes empty buckets); delete it in the dashboard under R2."
        }
        progress(.init(step: .delete, phase: .done, detail: note ?? "deleted"))
        return note
    }

    static func randomHex(_ n: Int) -> String {
        var g = SystemRandomNumberGenerator()
        return (0..<n).map { _ in String(format: "%02x", UInt8.random(in: 0...255, using: &g)) }.joined()
    }
}

// MARK: - The API token page

public enum CloudflareLinks {
    public static let signUp = URL(string: "https://dash.cloudflare.com/sign-up")!

    /// The permissions the relay's deploy needs, as Cloudflare's token template keys. Shown to the user and used to pre-fill the page.
    public static let tokenPermissions: [(key: String, type: String, title: String, why: String)] = [
        ("workers_scripts", "edit", "Workers Scripts: Edit", "upload the relay, switch on its workers.dev address, set its variables"),
        ("workers_r2", "edit", "Workers R2 Storage: Edit", "create the bucket that holds voice replies and its 7-day expiry"),
        ("account_settings", "read", "Account Settings: Read", "find your account id"),
        // Custom domain (needed by cloud agents such as ChatGPT: Cloudflare blocks them on workers.dev). Zone scope.
        ("zone", "read", "Zone: Read", "list your zones and find the one for the custom domain"),
        ("dns", "edit", "DNS: Edit", "Cloudflare creates the DNS record for the custom domain"),
        ("workers_routes", "edit", "Workers Routes: Edit", "attach the relay to the custom domain"),
        ("zone_settings", "edit", "Zone Settings: Edit", "read the zone's settings"),
        ("config_settings", "edit", "Config Settings: Edit", "the Configuration Rule that switches Browser Integrity Check off for the relay hostname"),
        ("waf", "edit", "Zone WAF: Edit", "a narrow rule that skips the security-level challenge for the relay hostname"),
    ]

    /// Cloudflare's "create a token from a link" page, pre-filled with the permissions above and the name "Herald relay".
    public static func prefilledTokenURL() -> URL {
        let perms = "[" + tokenPermissions.map { "{\"key\":\"\($0.key)\",\"type\":\"\($0.type)\"}" }.joined(separator: ",") + "]"
        var c = URLComponents(string: "https://dash.cloudflare.com/profile/api-tokens")!
        c.queryItems = [
            URLQueryItem(name: "permissionGroupKeys", value: perms),
            URLQueryItem(name: "accountId", value: "*"),
            URLQueryItem(name: "zoneId", value: "all"),
            URLQueryItem(name: "name", value: "Herald relay"),
        ]
        // URLComponents leaves "[" "]" "{" ... unescaped in values; Cloudflare expects a fully encoded JSON array.
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        let q = c.queryItems!.map { "\($0.name)=\(($0.value ?? "").addingPercentEncoding(withAllowedCharacters: allowed) ?? "")" }.joined(separator: "&")
        return URL(string: "https://dash.cloudflare.com/profile/api-tokens?" + q)!
    }
}

// MARK: - multipart

struct MultipartForm {
    private let boundary = "herald-" + UUID().uuidString
    private(set) var data = Data()
    var contentType: String { "multipart/form-data; boundary=\(boundary)" }

    mutating func addJSON(name: String, _ json: Data) {
        data.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\nContent-Type: application/json\r\n\r\n".utf8))
        data.append(json); data.append(Data("\r\n".utf8))
    }
    mutating func addFile(name: String, filename: String, contentType: String, data file: Data) {
        data.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\nContent-Type: \(contentType)\r\n\r\n".utf8))
        data.append(file); data.append(Data("\r\n--\(boundary)--\r\n".utf8))
    }
}
