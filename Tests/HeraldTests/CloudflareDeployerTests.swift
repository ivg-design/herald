import XCTest
import Foundation
@testable import HeraldClient
@testable import HeraldCore

/// A tiny fake of api.cloudflare.com and the Worker's /health: a table of "METHOD path" -> (status, JSON), recording every request.
final class FakeCloudflare: RelayHTTP, @unchecked Sendable {
    struct Call { var method: String; var path: String; var body: Data; var contentType: String? }
    private let lock = NSLock()
    private(set) var calls: [Call] = []
    var scriptExists = false
    var bucketExists = false
    var subdomain: String? = "acme"
    var accounts: [[String: Any]] = [["id": String(repeating: "a", count: 32), "name": "Acme"]]
    var tokenStatus = "active"
    /// "METHOD path" -> forced reply
    var forced: [String: (Int, String)] = [:]
    var healthBundle: String? = nil   // nil: echo the uploaded BUNDLE_HASH
    var healthFailures = 0
    /// Cloudflare's Browser Integrity Check: Python's default urllib User-Agent gets 403 / Error 1010 on non-API hosts.
    var blockPythonUrllib = false
    /// After this many successful health answers every later one fails (nil: never).
    var failHealthAfter: Int?
    private var healthAnswered = 0
    private var uploadedHash: String?
    // Custom domain
    var zones: [[String: Any]] = [["id": "zone1", "name": "example.com", "status": "active"], ["id": "zone2", "name": "other.org", "status": "active"]]
    var zonePermissionsMissing = false       // every /zones call answers 403
    var wafPermissionMissing = false         // only the firewall phase answers 403
    var botManagement: [String: Any] = ["fight_mode": false, "sbfm_definitely_automated": "allow"]
    private(set) var attachedDomains: [[String: Any]] = []
    /// phase -> rules (each has an id), the entry-point rulesets that exist
    private(set) var rulesets: [String: [[String: Any]]] = [:]
    private var ruleCounter = 0

    func send(_ r: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let url = r.url!
        let path = url.path + (url.query.map { "?" + $0 } ?? "")
        let method = r.httpMethod ?? "GET"
        lock.lock(); calls.append(Call(method: method, path: path, body: r.httpBody ?? Data(), contentType: r.value(forHTTPHeaderField: "Content-Type"))); lock.unlock()
        func reply(_ status: Int, _ json: String) -> (Data, HTTPURLResponse) {
            (Data(json.utf8), HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!)
        }
        func ok(_ result: String) -> (Data, HTTPURLResponse) { reply(200, #"{"success":true,"errors":[],"result":\#(result)}"#) }
        if let f = forced["\(method) \(path)"] { return reply(f.0, f.1) }
        if url.host == "api.cloudflare.com" {
            precondition(r.value(forHTTPHeaderField: "Authorization") == "Bearer tok", "token missing")
            let p = path.replacingOccurrences(of: "/client/v4", with: "")
            if p.hasPrefix("/zones") || p.contains("/workers/domains") {
                let denied = reply(403, #"{"success":false,"errors":[{"code":10000,"message":"Authentication error"}]}"#)
                if zonePermissionsMissing { return denied }
                if wafPermissionMissing, p.contains("http_request_firewall_custom") { return denied }
                return zoneApi(method, p, r, reply, ok)
            }
            switch (method, p) {
            case ("GET", "/user/tokens/verify"): return ok(#"{"status":"\#(tokenStatus)"}"#)
            case ("GET", "/accounts"): return ok(String(data: try JSONSerialization.data(withJSONObject: accounts), encoding: .utf8)!)
            case ("GET", _) where p.hasSuffix("/workers/subdomain"):
                return subdomain.map { ok(#"{"subdomain":"\#($0)"}"#) } ?? reply(404, #"{"success":false,"errors":[{"code":10007,"message":"no subdomain"}]}"#)
            case ("PUT", _) where p.hasSuffix("/workers/subdomain"):
                let name = ((try? JSONSerialization.jsonObject(with: r.httpBody ?? Data())) as? [String: Any])?["subdomain"] as? String ?? ""
                subdomain = name; return ok(#"{"subdomain":"\#(name)"}"#)
            case ("POST", _) where p.hasSuffix("/r2/buckets"):
                if bucketExists { return reply(409, #"{"success":false,"errors":[{"code":10004,"message":"The bucket you tried to create already exists"}]}"#) }
                bucketExists = true; return ok(#"{"name":"b"}"#)
            case ("PUT", _) where p.hasSuffix("/lifecycle"): return ok("{}")
            case ("GET", _) where p.hasSuffix("/settings"):
                return scriptExists ? ok("{}") : reply(404, #"{"success":false,"errors":[{"code":10007,"message":"This Worker does not exist"}]}"#)
            case ("PUT", _) where p.contains("/workers/scripts/"):
                scriptExists = true
                let s = String(decoding: r.httpBody ?? Data(), as: UTF8.self)
                if let m = s.range(of: #"BUNDLE_HASH","text":"([0-9a-f]+)"#, options: .regularExpression) {
                    uploadedHash = String(s[m]).components(separatedBy: "\"").last
                }
                return ok(#"{"id":"herald-relay"}"#)
            case ("POST", _) where p.hasSuffix("/subdomain"): return ok(#"{"enabled":true}"#)
            case ("DELETE", _) where p.contains("/workers/scripts/"): scriptExists = false; return ok("null")
            case ("DELETE", _) where p.contains("/r2/buckets/"): bucketExists = false; return ok("null")
            default: return reply(404, #"{"success":false,"errors":[{"code":7003,"message":"No route for \#(method) \#(p)"}]}"#)
            }
        }
        // the workers.dev health check
        if blockPythonUrllib, r.value(forHTTPHeaderField: "User-Agent") == "Python-urllib/3.12" { return reply(403, "error code: 1010") }
        if healthFailures > 0 { healthFailures -= 1; throw RelayError.transport("could not resolve host") }
        if let n = failHealthAfter, healthAnswered >= n { throw RelayError.transport("could not resolve host") }
        healthAnswered += 1
        let bundle = healthBundle ?? uploadedHash
        return reply(200, #"{"service":"herald-relay","ok":true\#(bundle.map { #","bundle":"\#($0)""# } ?? "")}"#)
    }

    private func json(_ r: URLRequest) -> [String: Any] { ((try? JSONSerialization.jsonObject(with: r.httpBody ?? Data())) as? [String: Any]) ?? [:] }
    private func str(_ v: Any) -> String { String(decoding: (try? JSONSerialization.data(withJSONObject: v)) ?? Data(), as: UTF8.self) }

    private func zoneApi(_ method: String, _ p: String, _ r: URLRequest, _ reply: (Int, String) -> (Data, HTTPURLResponse), _ ok: (String) -> (Data, HTTPURLResponse)) -> (Data, HTTPURLResponse) {
        let path = p.components(separatedBy: "?")[0]
        if method == "GET", path == "/zones" { return ok(str(zones)) }
        if method == "PUT", path.hasSuffix("/workers/domains") {
            attachedDomains.removeAll { $0["hostname"] as? String == json(r)["hostname"] as? String }
            attachedDomains.append(json(r)); return ok(str(json(r)))
        }
        if method == "GET", path.hasSuffix("/bot_management") { return ok(str(botManagement)) }
        // /zones/{z}/rulesets/phases/{phase}/entrypoint and /zones/{z}/rulesets/{id}/rules[/{rid}]
        if path.contains("/rulesets/phases/"), let phase = path.components(separatedBy: "/phases/").last?.components(separatedBy: "/").first {
            if method == "GET" {
                guard rulesets[phase] != nil else { return reply(404, #"{"success":false,"errors":[{"code":10003,"message":"could not find entrypoint"}]}"#) }
                return ok(str(["id": "rs-" + phase, "rules": rulesets[phase]!]))
            }
            if method == "PUT" {
                rulesets[phase] = ((json(r)["rules"] as? [[String: Any]]) ?? []).map { var x = $0; ruleCounter += 1; x["id"] = "rule\(ruleCounter)"; return x }
                return ok(str(["id": "rs-" + phase, "rules": rulesets[phase]!]))
            }
        }
        if path.contains("/rulesets/rs-"), let phase = path.components(separatedBy: "/rulesets/rs-").last?.components(separatedBy: "/").first {
            if method == "POST" {
                ruleCounter += 1; var x = json(r); x["id"] = "rule\(ruleCounter)"; rulesets[phase, default: []].append(x); return ok(str(x))
            }
            if method == "PATCH", let rid = path.components(separatedBy: "/rules/").last, let i = rulesets[phase]?.firstIndex(where: { $0["id"] as? String == rid }) {
                var x = json(r); x["id"] = rid; rulesets[phase]![i] = x; return ok(str(x))
            }
        }
        return reply(404, #"{"success":false,"errors":[{"code":7003,"message":"No route"}]}"#)
    }

    func seedRuleset(_ phase: String, _ rules: [[String: Any]]) { rulesets[phase] = rules }
    func paths(_ method: String) -> [String] { calls.filter { $0.method == method }.map(\.path) }
}

final class CloudflareDeployerTests: XCTestCase {
    private let bundle = WorkerBundle(script: Data("export default {}".utf8), sourceHash: String(repeating: "c", count: 64), compatibilityDate: "2026-08-01")
    private var account: String { String(repeating: "a", count: 32) }

    private func make(_ http: FakeCloudflare, secrets: CloudflareSecrets? = nil) -> (CloudflareDeployer, CloudflareSecrets) {
        let s = secrets ?? { let m = MemoryCloudflareSecrets(); m.set(.apiToken, "tok"); return m }()
        var d = CloudflareDeployer(http: http, secrets: s, sleep: { _ in })
        d.healthAttempts = 5
        return (d, s)
    }

    private final class Log: @unchecked Sendable {
        private let lock = NSLock(); var events: [DeployEvent] = []
        func add(_ e: DeployEvent) { lock.lock(); events.append(e); lock.unlock() }
    }

    func testFirstDeployRunsEveryStepInOrderAndReportsThem() async throws {
        let http = FakeCloudflare(); let (d, secrets) = make(http); let log = Log()
        let r = try await d.deploy(config: RelayCloudConfig(), bundle: bundle, progress: log.add)
        XCTAssertEqual(r.workerURL, "https://herald-relay.acme.workers.dev")
        XCTAssertEqual(r.accountId, account); XCTAssertFalse(r.upgraded); XCTAssertEqual(r.bundleHash, bundle.sourceHash)
        let done = log.events.filter { $0.phase == .done }.map(\.step)
        XCTAssertEqual(done, [.verifyToken, .account, .subdomain, .bucket, .lifecycle, .upload, .route, .health])
        // secrets were made and kept
        XCTAssertEqual(secrets.get(.pairingSecret)?.count, 32); XCTAssertEqual(secrets.get(.relaySecret)?.count, 64)
        // the upload is multipart with the module, the DO migration, the R2 binding, the vars and the secrets
        let up = http.calls.first { $0.method == "PUT" && $0.path.contains("/workers/scripts/herald-relay") }!
        XCTAssertTrue(up.contentType!.hasPrefix("multipart/form-data; boundary="))
        let body = String(decoding: up.body, as: UTF8.self)
        for needle in ["\"main_module\":\"worker.js\"", "\"compatibility_date\":\"2026-08-01\"", "\"new_sqlite_classes\":[\"Mailbox\",\"Registry\"]",
                       "\"class_name\":\"Mailbox\"", "\"class_name\":\"Registry\"", "\"bucket_name\":\"herald-relay-audio\"", "\"name\":\"AUDIO\"",
                       "\"name\":\"RELAY_SECRET\"", "\"name\":\"PAIRING_SECRET\"", "\"name\":\"MAX_DEVICES\"", "\"name\":\"BUNDLE_HASH\"",
                       "filename=\"worker.js\"", "export default {}"] {
            XCTAssertTrue(body.contains(needle), needle)
        }
        XCTAssertFalse(body.contains("keep_bindings"))
        // the lifecycle rule is 7 days in seconds
        let lc = http.calls.first { $0.path.hasSuffix("/lifecycle") }!
        XCTAssertTrue(String(decoding: lc.body, as: UTF8.self).contains("604800"))
        // every Cloudflare call carried the token (the fake would have stopped otherwise)
        XCTAssertTrue(http.calls.contains { $0.path == "/health" })
    }

    func testRerunUpgradesInPlaceKeepingSecretsAndSkippingMigration() async throws {
        let http = FakeCloudflare(); let (d, secrets) = make(http)
        _ = try await d.deploy(config: RelayCloudConfig(), bundle: bundle)
        let pairing = secrets.get(.pairingSecret), signing = secrets.get(.relaySecret)
        let newer = WorkerBundle(script: Data("export default {v:2}".utf8), sourceHash: String(repeating: "d", count: 64), compatibilityDate: "2026-08-01")
        let r = try await d.deploy(config: RelayCloudConfig(), bundle: newer)
        XCTAssertTrue(r.upgraded)
        XCTAssertEqual(secrets.get(.pairingSecret), pairing); XCTAssertEqual(secrets.get(.relaySecret), signing)
        let up = http.calls.filter { $0.method == "PUT" && $0.path.contains("/workers/scripts/herald-relay") }.last!
        let body = String(decoding: up.body, as: UTF8.self)
        XCTAssertTrue(body.contains("\"keep_bindings\":[\"secret_text\"]"))
        XCTAssertFalse(body.contains("new_sqlite_classes"))
        XCTAssertTrue(body.contains("export default {v:2}"))
        // the bucket already existed: not an error
        XCTAssertEqual(http.paths("POST").filter { $0.hasSuffix("/r2/buckets") }.count, 2)
    }

    func testCreatesTheSubdomainWhenTheAccountHasNone() async throws {
        let http = FakeCloudflare(); http.subdomain = nil
        let (d, _) = make(http)
        let r = try await d.deploy(config: RelayCloudConfig(), bundle: bundle)
        XCTAssertTrue(r.subdomain.hasPrefix("herald-"))
        XCTAssertTrue(r.workerURL.contains(r.subdomain))
        XCTAssertEqual(http.paths("PUT").filter { $0.hasSuffix("/workers/subdomain") }.count, 1)
    }

    func testAdvancedValuesAreUsedAndSentAsVars() async throws {
        let http = FakeCloudflare(); let (d, _) = make(http)
        var c = RelayCloudConfig(); c.accountId = account; c.workerName = "my-relay"; c.bucket = "my-audio"; c.maxQueue = 7; c.audioRetentionDays = 2
        let r = try await d.deploy(config: c, bundle: bundle)
        XCTAssertEqual(r.workerURL, "https://my-relay.acme.workers.dev")
        XCTAssertFalse(http.calls.contains { $0.path.hasSuffix("/accounts") })   // account id given: not looked up
        let up = String(decoding: http.calls.first { $0.method == "PUT" && $0.path.contains("/workers/scripts/my-relay") }!.body, as: UTF8.self)
        XCTAssertTrue(up.contains("\"name\":\"DEVICE_QUEUE_MAX\"")); XCTAssertTrue(up.contains("\"text\":\"7\""))
        XCTAssertTrue(up.contains("\"bucket_name\":\"my-audio\""))
        XCTAssertTrue(String(decoding: http.calls.first { $0.path.contains("/r2/buckets/my-audio/lifecycle") }!.body, as: UTF8.self).contains("172800"))
    }

    func testErrorsSurfaceCloudflaresMessageAndStopAtTheStep() async throws {
        let http = FakeCloudflare()
        http.forced["PUT /client/v4/accounts/\(account)/workers/scripts/herald-relay"] =
            (403, #"{"success":false,"errors":[{"code":10000,"message":"Authentication error: missing Workers Scripts Write"}]}"#)
        let (d, _) = make(http); let log = Log()
        do { _ = try await d.deploy(config: RelayCloudConfig(), bundle: bundle, progress: log.add); XCTFail("should throw") }
        catch let e as CloudflareError {
            XCTAssertEqual(e.step, .upload); XCTAssertEqual(e.status, 403)
            XCTAssertEqual(e.message, "Authentication error: missing Workers Scripts Write")
        }
        XCTAssertEqual(log.events.last, DeployEvent(step: .upload, phase: .failed, detail: "Authentication error: missing Workers Scripts Write"))
        XCTAssertFalse(http.calls.contains { $0.path.hasSuffix("/subdomain") && $0.method == "POST" })   // nothing after the failure ran
        // Retry after the user fixes the token: the same call now works
        http.forced = [:]
        let r = try await d.deploy(config: RelayCloudConfig(), bundle: bundle)
        XCTAssertEqual(r.workerURL, "https://herald-relay.acme.workers.dev")
    }

    func testTokenProblemsAreExplainedBeforeAnythingIsCreated() async throws {
        let none = MemoryCloudflareSecrets()
        var (d, _) = make(FakeCloudflare(), secrets: none)
        do { _ = try await d.deploy(config: RelayCloudConfig(), bundle: bundle); XCTFail() } catch let e as CloudflareError { XCTAssertEqual(e.step, .verifyToken) }
        let http = FakeCloudflare(); http.tokenStatus = "expired"
        (d, _) = make(http)
        do { _ = try await d.deploy(config: RelayCloudConfig(), bundle: bundle); XCTFail() } catch let e as CloudflareError { XCTAssertTrue(e.message.contains("expired")) }
        XCTAssertEqual(http.calls.count, 1)
    }

    func testSeveralAccountsNeedAnExplicitChoice() async throws {
        let http = FakeCloudflare(); http.accounts.append(["id": String(repeating: "b", count: 32), "name": "Other"])
        let (d, _) = make(http)
        do { _ = try await d.deploy(config: RelayCloudConfig(), bundle: bundle); XCTFail() }
        catch let e as CloudflareError { XCTAssertEqual(e.step, .account); XCTAssertTrue(e.message.contains("account id")) }
    }

    func testWaitsForTheRelayToAnswerAndDoesNotAcceptAnOldVersion() async throws {
        let http = FakeCloudflare(); http.healthFailures = 3
        let (d, _) = make(http)
        _ = try await d.deploy(config: RelayCloudConfig(), bundle: bundle)
        XCTAssertEqual(http.calls.filter { $0.path == "/health" }.count, 4)

        let stale = FakeCloudflare(); stale.healthBundle = String(repeating: "0", count: 64)
        let (d2, _) = make(stale)
        do { _ = try await d2.deploy(config: RelayCloudConfig(), bundle: bundle); XCTFail() }
        catch let e as CloudflareError { XCTAssertEqual(e.step, .health); XCTAssertTrue(e.message.contains("previous version")) }
    }

    func testDeleteRemovesTheWorkerAndReportsABucketItCannotDelete() async throws {
        let http = FakeCloudflare(); let (d, _) = make(http)
        var c = RelayCloudConfig(); c.accountId = account
        _ = try await d.deploy(config: c, bundle: bundle)
        let note = try await d.deleteRelay(config: c)
        XCTAssertNil(note); XCTAssertFalse(http.scriptExists)
        XCTAssertTrue(http.calls.contains { $0.method == "DELETE" && $0.path.contains("herald-relay?force=true") })
        http.forced["DELETE /client/v4/accounts/\(account)/r2/buckets/herald-relay-audio"] = (409, #"{"success":false,"errors":[{"code":10008,"message":"bucket not empty"}]}"#)
        let note2 = try await d.deleteRelay(config: c)
        XCTAssertTrue(note2?.contains("still holds voice replies") == true)
    }

    func testHealthReadsTheDeployedBundleHash() async {
        let http = FakeCloudflare(); http.healthBundle = "abc"
        let r = await CloudflareDeployer.health(url: "https://x.workers.dev", http: http)
        XCTAssertEqual(try? r.get(), .init(ok: true, bundle: "abc"))
    }
}

final class CloudflareCustomDomainTests: XCTestCase {
    private let bundle = WorkerBundle(script: Data("export default {}".utf8), sourceHash: String(repeating: "c", count: 64), compatibilityDate: "2026-08-01")
    private func make(_ http: FakeCloudflare) -> CloudflareDeployer {
        let m = MemoryCloudflareSecrets(); m.set(.apiToken, "tok")
        var d = CloudflareDeployer(http: http, secrets: m, sleep: { _ in }); d.healthAttempts = 3; return d
    }
    private func config() -> RelayCloudConfig {
        var c = RelayCloudConfig(); c.customDomain = .init(zone: "example.com", hostname: "herald.example.com"); return c
    }
    private final class Log: @unchecked Sendable {
        private let lock = NSLock(); var events: [DeployEvent] = []
        func add(_ e: DeployEvent) { lock.lock(); events.append(e); lock.unlock() }
    }

    func testDomainAttachCreatesTheWorkersCustomDomainAndReturnsTheCanonicalURL() async throws {
        let http = FakeCloudflare(); let log = Log()
        let r = try await make(http).deploy(config: config(), bundle: bundle, progress: log.add)
        XCTAssertEqual(r.customURL, "https://herald.example.com")
        XCTAssertEqual(r.workerURL, "https://herald-relay.acme.workers.dev")
        XCTAssertEqual(log.events.filter { $0.phase == .done }.map(\.step),
                       [.verifyToken, .account, .subdomain, .bucket, .lifecycle, .upload, .route, .health, .zone, .domain, .configRule, .wafSkip, .botMode, .domainHealth])
        let d = try XCTUnwrap(http.attachedDomains.first)
        XCTAssertEqual(d["hostname"] as? String, "herald.example.com"); XCTAssertEqual(d["service"] as? String, "herald-relay")
        XCTAssertEqual(d["environment"] as? String, "production"); XCTAssertEqual(d["zone_id"] as? String, "zone1")
        XCTAssertTrue(http.calls.contains { $0.method == "PUT" && $0.path.hasSuffix("/workers/domains") })
        XCTAssertTrue(http.calls.contains { $0.path == "/health" })
    }

    func testNoCustomDomainRunsNoZoneStep() async throws {
        let http = FakeCloudflare()
        let r = try await make(http).deploy(config: RelayCloudConfig(), bundle: bundle)
        XCTAssertNil(r.customURL)
        XCTAssertFalse(http.calls.contains { $0.path.hasPrefix("/client/v4/zones") || $0.path.contains("/workers/domains") })
    }

    func testConfigRuleSwitchesBrowserIntegrityCheckOffForThatHostOnly() async throws {
        let http = FakeCloudflare()
        _ = try await make(http).deploy(config: config(), bundle: bundle)
        let rules = try XCTUnwrap(http.rulesets["http_config_settings"])
        XCTAssertEqual(rules.count, 1)
        let rule = rules[0]
        XCTAssertEqual(rule["description"] as? String, "Herald relay: allow non-browser clients")
        XCTAssertEqual(rule["action"] as? String, "set_config")
        XCTAssertEqual((rule["action_parameters"] as? [String: Any])?["bic"] as? Bool, false)
        XCTAssertEqual(rule["expression"] as? String, "(http.host eq \"herald.example.com\")")
    }

    func testConfigRuleIsIdempotentAndLeavesOtherRulesAlone() async throws {
        let http = FakeCloudflare()
        http.seedRuleset("http_config_settings", [["id": "keep", "description": "mine", "expression": "true", "action": "set_config", "action_parameters": ["rocket_loader": false]]])
        let d = make(http)
        _ = try await d.deploy(config: config(), bundle: bundle)
        XCTAssertEqual(http.rulesets["http_config_settings"]?.count, 2)   // added next to the user's rule
        _ = try await d.deploy(config: config(), bundle: bundle)
        XCTAssertEqual(http.rulesets["http_config_settings"]?.count, 2)   // second run: updated, not duplicated
        XCTAssertTrue(http.calls.contains { $0.method == "PATCH" && $0.path.contains("/rulesets/rs-http_config_settings/rules/") })
        XCTAssertEqual(http.rulesets["http_config_settings"]?.first?["id"] as? String, "keep")
        // a new hostname updates the same rule
        var c = config(); c.customDomain = .init(zone: "example.com", hostname: "relay.example.com")
        _ = try await d.deploy(config: c, bundle: bundle)
        let mine = http.rulesets["http_config_settings"]!.first { $0["description"] as? String == CloudflareDeployer.ruleDescription }!
        XCTAssertEqual(mine["expression"] as? String, "(http.host eq \"relay.example.com\")")
        XCTAssertEqual(http.rulesets["http_config_settings"]?.count, 2)
    }

    func testWafSkipRuleIsNarrowToTheHost() async throws {
        let http = FakeCloudflare()
        let r = try await make(http).deploy(config: config(), bundle: bundle)
        let rule = try XCTUnwrap(http.rulesets["http_request_firewall_custom"]?.first)
        XCTAssertEqual(rule["action"] as? String, "skip")
        XCTAssertEqual((rule["action_parameters"] as? [String: Any])?["products"] as? [String], ["bic", "securityLevel"])
        XCTAssertEqual(rule["expression"] as? String, "(http.host eq \"herald.example.com\")")
        XCTAssertTrue(r.warnings.isEmpty)
    }

    func testMissingWafPermissionIsAWarningNotAFailure() async throws {
        let http = FakeCloudflare(); http.wafPermissionMissing = true
        let r = try await make(http).deploy(config: config(), bundle: bundle)
        XCTAssertEqual(r.customURL, "https://herald.example.com")
        XCTAssertTrue(r.warnings.contains { $0.contains("WAF skip rule was not written") && $0.contains("Zone permissions") })
        XCTAssertNotNil(http.rulesets["http_config_settings"])   // the fix itself still went in
    }

    func testBotFightModeIsDetectedAndSurfaced() async throws {
        let http = FakeCloudflare(); http.botManagement = ["fight_mode": true, "sbfm_definitely_automated": "block"]
        let r = try await make(http).deploy(config: config(), bundle: bundle)
        XCTAssertTrue(r.warnings.contains { $0.contains("Bot Fight Mode is on") })
        XCTAssertTrue(r.warnings.contains { $0.contains("Super Bot Fight Mode") && $0.contains("block") })
    }

    func testTokenWithoutZonePermissionsGetsAClearError() async throws {
        let http = FakeCloudflare(); http.zonePermissionsMissing = true
        let log = Log()
        do { _ = try await make(http).deploy(config: config(), bundle: bundle, progress: log.add); XCTFail("should throw") }
        catch let e as CloudflareError {
            XCTAssertEqual(e.step, .zone); XCTAssertEqual(e.status, 403)
            XCTAssertTrue(e.message.hasPrefix("Token is missing Zone permissions"))
            XCTAssertTrue(e.message.contains("turn off the custom domain"))
        }
        // the relay itself was deployed before the zone step failed
        XCTAssertTrue(log.events.contains { $0.step == .health && $0.phase == .done })
        XCTAssertFalse(http.calls.contains { $0.path.contains("/workers/domains") })
    }

    func testUnknownZoneIsAnError() async throws {
        let http = FakeCloudflare(); var c = config(); c.customDomain = .init(zone: "nope.dev", hostname: "herald.nope.dev")
        do { _ = try await make(http).deploy(config: c, bundle: bundle); XCTFail() }
        catch let e as CloudflareError { XCTAssertEqual(e.step, .zone); XCTAssertTrue(e.message.contains("nope.dev")) }
    }

    func testDomainThatDoesNotAnswerIsReportedWithRetryAdvice() async throws {
        let http = FakeCloudflare()
        // workers.dev answers (3 failures would break it first), so fail only after it: make health fail forever after the first call
        http.failHealthAfter = 1
        do { _ = try await make(http).deploy(config: config(), bundle: bundle); XCTFail() }
        catch let e as CloudflareError { XCTAssertEqual(e.step, .domainHealth); XCTAssertTrue(e.message.contains("press Retry")) }
    }

    func testZonesListsWhatTheTokenSeesAndExplainsAMissingPermission() async throws {
        let http = FakeCloudflare()
        let z = try await make(http).zones(config: RelayCloudConfig())
        XCTAssertEqual(z.map(\.name), ["example.com", "other.org"])
        XCTAssertEqual(RelayZone(id: "1", name: "example.com", status: "active").suggestedHostname, "herald.example.com")
        http.zonePermissionsMissing = true
        do { _ = try await make(http).zones(config: RelayCloudConfig()); XCTFail() }
        catch let e as CloudflareError { XCTAssertTrue(e.message.hasPrefix("Token is missing Zone permissions")) }
    }

    func testBrowserCheckProbeDetectsTheUrllibBan() async {
        let http = FakeCloudflare(); http.blockPythonUrllib = true
        let on = await CloudflareDeployer.browserCheckActive(url: "https://herald-relay.acme.workers.dev", http: http)
        XCTAssertEqual(on, true)
        let ua = http.calls.count   // each path asked with a custom and the default User-Agent
        XCTAssertEqual(ua, 2)       // stops at the first path that shows the ban
        let off = FakeCloudflare()
        let none = await CloudflareDeployer.browserCheckActive(url: "https://herald.example.com", http: off)
        XCTAssertEqual(none, false)
        // everything blocked for everyone (not a User-Agent rule) is not reported as the browser check
        let down = FakeCloudflare(); down.healthFailures = 99
        let unknown = await CloudflareDeployer.browserCheckActive(url: "https://x.test", http: down)
        XCTAssertNil(unknown)
    }

    func testTokenPageAsksForTheZonePermissionsToo() {
        let keys = CloudflareLinks.tokenPermissions.map(\.key)
        for k in ["zone", "dns", "workers_routes", "zone_settings", "config_settings", "waf"] { XCTAssertTrue(keys.contains(k), k) }
        let url = CloudflareLinks.prefilledTokenURL().absoluteString
        XCTAssertTrue(url.contains("config_settings"))
    }

    func testCustomDomainPersistsAndValidates() {
        let f = FileManager.default.temporaryDirectory.appendingPathComponent("cfg-\(UUID().uuidString).json")
        let store = RelayCloudConfigStore(file: f)
        store.update { $0.customDomain = .init(zone: "example.com", hostname: "herald.example.com", attached: true) }
        let again = RelayCloudConfigStore(file: f).value
        XCTAssertEqual(again.customDomain, .init(zone: "example.com", hostname: "herald.example.com", attached: true))
        XCTAssertEqual(again.customURL, "https://herald.example.com"); XCTAssertEqual(again.canonicalURL, "https://herald.example.com")
        try? FileManager.default.removeItem(at: f)
        var c = RelayCloudConfig(); c.subdomain = "acme"
        XCTAssertEqual(c.canonicalURL, "https://herald-relay.acme.workers.dev")
        c.customDomain = .init(zone: "example.com", hostname: "herald.other.org"); XCTAssertNotNil(c.validate()["customDomain"])
        c.customDomain = .init(zone: "example.com", hostname: "Bad Host"); XCTAssertNotNil(c.validate()["customDomain"])
        c.customDomain = .init(zone: "example.com", hostname: "herald.example.com"); XCTAssertTrue(c.validate().isEmpty)
        XCTAssertNil(c.customURL)   // not attached yet
        // an old file without the key still loads
        let old = try? HeraldJSONCoding.decoder.decode(RelayCloudConfig.self, from: Data(#"{"workerName":"x"}"#.utf8))
        XCTAssertNil(old?.customDomain)
    }

    func testSettingsPatchSetsAndClearsTheCustomDomain() throws {
        var c = RelayCloudConfig()
        c = try c.applying(["customDomain": .object(["zone": .string("example.com"), "hostname": .string("Herald.Example.com")])])
        XCTAssertEqual(c.customDomain, .init(zone: "example.com", hostname: "herald.example.com"))
        c.customDomain?.attached = true
        c = try c.applying(["customDomain": .object(["zone": .string("example.com"), "hostname": .string("herald.example.com")])])
        XCTAssertEqual(c.customDomain?.attached, true)   // unchanged: stays attached
        c = try c.applying(["customDomain": .object(["zone": .string("example.com"), "hostname": .string("relay.example.com")])])
        XCTAssertEqual(c.customDomain?.attached, false)
        XCTAssertTrue(c.needsRedeploy(comparedTo: RelayCloudConfig()))
        c = try c.applying(["customDomain": .null]); XCTAssertNil(c.customDomain)
        XCTAssertThrowsError(try c.applying(["customDomain": .string("x")]))
    }
}

final class RelayCloudConfigTests: XCTestCase {
    func testDefaultsAreValidAndMatchTheWorkersDefaults() {
        let c = RelayCloudConfig()
        XCTAssertTrue(c.validate().isEmpty)
        XCTAssertEqual(c.workerVars(bundleHash: "h")["BUNDLE_HASH"], "h")
        XCTAssertEqual(c.workerVars(bundleHash: "h")["DEVICE_QUEUE_MAX"], "100")
        XCTAssertNil(c.workerURL)
    }

    func testValidationNamesTheFieldAndSaysWhatIsAllowed() {
        var c = RelayCloudConfig()
        c.workerName = "Bad Name"; c.bucket = "ab"; c.accountId = "xyz"; c.audioRetentionDays = 0; c.queueTTLHours = 999
        c.notificationsPerDay = 0; c.maxQueue = 5000; c.bodyLimitBytes = 10; c.ratePerKey = 0; c.maxDevices = 0; c.pingSeconds = 5
        c.deviceName = String(repeating: "x", count: 61)
        let e = c.validate()
        for k in ["workerName", "bucket", "accountId", "audioRetentionDays", "queueTTLHours", "notificationsPerDay", "maxQueue", "bodyLimitBytes", "ratePerKey", "maxDevices", "pingSeconds", "deviceName"] {
            XCTAssertNotNil(e[k], k)
        }
        XCTAssertEqual(e.count, 12)
    }

    func testChangingAWorkerValueMeansRedeploy() {
        let a = RelayCloudConfig(); var b = a
        XCTAssertFalse(b.needsRedeploy(comparedTo: a))
        b.deviceName = "Studio"; b.pingSeconds = 60
        XCTAssertFalse(b.needsRedeploy(comparedTo: a))   // Herald's own settings
        b.maxQueue = 50
        XCTAssertTrue(b.needsRedeploy(comparedTo: a))
        b = a; b.audioRetentionDays = 3
        XCTAssertTrue(b.needsRedeploy(comparedTo: a))
    }

    func testPersistsToDisk() {
        let f = FileManager.default.temporaryDirectory.appendingPathComponent("cfg-\(UUID().uuidString).json")
        let s = RelayCloudConfigStore(file: f)
        s.update { $0.subdomain = "acme"; $0.maxQueue = 9; $0.deployedAt = Date(timeIntervalSince1970: 1_700_000_000) }
        let again = RelayCloudConfigStore(file: f).value
        XCTAssertEqual(again.workerURL, "https://herald-relay.acme.workers.dev"); XCTAssertEqual(again.maxQueue, 9)
        XCTAssertNotNil(again.deployedAt)
        try? FileManager.default.removeItem(at: f)
    }
}

final class CloudflareSecretsTests: XCTestCase {
    func testKeychainStoresEachSecretSeparatelyAndRemovesThem() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("herald-secrets-\(UUID().uuidString)")
        let k = KeychainCloudflareSecrets(service: "com.ivg.herald.cloudflare.test.\(UUID().uuidString)", directory: dir, layer: FakeSecItems())
        defer { CloudflareSecretName.allCases.forEach { k.remove($0) }; try? FileManager.default.removeItem(at: dir) }
        XCTAssertNil(k.get(.apiToken))
        XCTAssertTrue(k.set(.apiToken, "tok-1")); XCTAssertTrue(k.set(.pairingSecret, "pair-1"))
        XCTAssertEqual(k.get(.apiToken), "tok-1"); XCTAssertEqual(k.get(.pairingSecret), "pair-1")
        XCTAssertTrue(k.set(.apiToken, "tok-2")); XCTAssertEqual(k.get(.apiToken), "tok-2")
        k.remove(.apiToken); XCTAssertNil(k.get(.apiToken)); XCTAssertEqual(k.get(.pairingSecret), "pair-1")
    }
}

final class RelayBundleTests: XCTestCase {
    private var repo: URL { URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent() }

    /// Fails when relay/src (or wrangler.toml) changed and `make relay-bundle` was not run: Herald would deploy an old relay.
    func testBundledWorkerIsCurrentWithRelaySources() throws {
        let bundle = try WorkerBundle.load(from: repo.appendingPathComponent("Resources/relay"))
        let now = try WorkerBundle.sourceHash(relayDirectory: repo.appendingPathComponent("relay"))
        XCTAssertEqual(bundle.sourceHash, now, "relay/ changed: run `make relay-bundle` and commit Resources/relay")
        XCTAssertGreaterThan(bundle.script.count, 10_000)
        XCTAssertEqual(bundle.mainModule, "worker.js")
        let js = String(decoding: bundle.script, as: UTF8.self)
        XCTAssertTrue(js.contains("class Mailbox") || js.contains("Mailbox"))
        XCTAssertTrue(js.contains("export {") || js.contains("export default"))
    }

    func testTokenLinkIsPrefilledWithTheThreePermissions() throws {
        let u = CloudflareLinks.prefilledTokenURL()
        XCTAssertEqual(u.host, "dash.cloudflare.com"); XCTAssertEqual(u.path, "/profile/api-tokens")
        let c = URLComponents(url: u, resolvingAgainstBaseURL: false)!
        let perms = c.queryItems!.first { $0.name == "permissionGroupKeys" }!.value!
        let arr = try JSONSerialization.jsonObject(with: Data(perms.utf8)) as! [[String: String]]
        XCTAssertEqual(arr.map { $0["key"]! }, ["workers_scripts", "workers_r2", "account_settings", "zone", "dns", "workers_routes", "zone_settings", "config_settings", "waf"])
        XCTAssertEqual(arr.map { $0["type"]! }, ["edit", "edit", "read", "read", "edit", "edit", "edit", "edit", "edit"])
        XCTAssertEqual(c.queryItems!.first { $0.name == "name" }!.value, "Herald relay")
        XCTAssertFalse(u.absoluteString.contains("{"))   // fully percent-encoded
    }
}

// MARK: - The enable switch

@MainActor
final class FakeSwitchBackend: RelaySwitchBackend {
    var isPaired = false
    var isOnline = false
    var pairError: Error?
    var unpairError: Error?
    var connects = true
    var pairCalls = 0, unpairCalls = 0, connectCalls = 0
    func pair() async throws { pairCalls += 1; if let e = pairError { throw e }; isPaired = true }
    func unpair() async throws { unpairCalls += 1; if let e = unpairError { throw e }; isPaired = false; isOnline = false }
    func connect(timeout seconds: Double) async -> Bool { connectCalls += 1; isOnline = connects; return connects }
}

@MainActor
final class RelaySwitchTests: XCTestCase {
    func testOffToPairingToOnlineToOff() async {
        let b = FakeSwitchBackend(); let sw = RelaySwitch(backend: b)
        var seen: [RelaySwitchState] = []
        sw.onChange = { seen.append(sw.state) }
        XCTAssertEqual(sw.state, .off); XCTAssertFalse(sw.isOn)
        await sw.toggle(true)
        XCTAssertEqual(seen, [.pairing, .connecting, .online])
        XCTAssertTrue(sw.isOn); XCTAssertEqual(b.pairCalls, 1)
        await sw.toggle(false)
        XCTAssertEqual(sw.state, .off); XCTAssertFalse(sw.isOn); XCTAssertEqual(b.unpairCalls, 1)
    }

    func testPairingFailureLeavesTheSwitchOffWithAReadableMessage() async {
        let b = FakeSwitchBackend(); b.pairError = RelayError.transport("offline"); let sw = RelaySwitch(backend: b)
        await sw.turnOn()
        guard case .failed(let m) = sw.state else { return XCTFail("\(sw.state)") }
        XCTAssertTrue(m.contains("Check your internet connection")); XCTAssertFalse(sw.isOn)
        // after the network is back, turning on again pairs and connects
        b.pairError = nil
        await sw.turnOn()
        XCTAssertEqual(sw.state, .online); XCTAssertEqual(b.pairCalls, 2)
    }

    func testPairedButSilentKeepsThePairingAndRetryDoesNotPairAgain() async {
        let b = FakeSwitchBackend(); b.connects = false; let sw = RelaySwitch(backend: b); sw.connectTimeout = 0
        await sw.turnOn()
        XCTAssertEqual(sw.state, .failed(RelaySwitchMessages.paired_but_silent)); XCTAssertTrue(sw.isOn)   // paired: the switch stays on
        b.connects = true
        await sw.turnOn()
        XCTAssertEqual(sw.state, .online); XCTAssertEqual(b.pairCalls, 1)
    }

    func testTurningOffWhenTheRelayCannotBeReachedChangesNothing() async {
        let b = FakeSwitchBackend(); let sw = RelaySwitch(backend: b)
        await sw.turnOn()
        b.unpairError = RelayError.transport("no route")
        await sw.turnOff()
        guard case .failed(let m) = sw.state else { return XCTFail() }
        XCTAssertTrue(m.contains("still on")); XCTAssertTrue(b.isPaired); XCTAssertTrue(sw.isOn)
    }

    func testLimitsAndFullRelaysAreExplained() {
        XCTAssertTrue(RelaySwitchMessages.friendly(RelayError.limited("x", retryAfter: 3600)).contains("1 hour"))
        XCTAssertTrue(RelaySwitchMessages.friendly(RelayError.http(403, "this relay already has 5 paired Macs")).contains("no room"))
        XCTAssertTrue(RelaySwitchMessages.friendly(RelayError.http(401, "pairing secret")).contains("pairing secret"))
    }

    func testSyncFollowsTheConnectionButNeverInterruptsAnAttempt() async {
        let b = FakeSwitchBackend(); b.isPaired = true; b.isOnline = true
        let sw = RelaySwitch(backend: b)
        XCTAssertEqual(sw.state, .online)          // launched already paired and connected
        b.isOnline = false; sw.sync()
        XCTAssertEqual(sw.state, .connecting)      // the connection dropped
        b.isOnline = true; sw.sync()
        XCTAssertEqual(sw.state, .online)
        b.isPaired = false; b.isOnline = false; sw.sync()
        XCTAssertEqual(sw.state, .off)             // unpaired elsewhere (the API)
    }
}

final class RelayInstructionsTests: XCTestCase {
    func testBothBlocksTellAgentsToSendACustomUserAgent() {
        for t in [RelayInstructions.oauth(mcpURL: "https://r.example.com/mcp"), RelayInstructions.staticKey(mcpURL: "https://r.example.com/mcp"),
                  RelayInstructions.staticKey(mcpURL: "https://r.example.com/mcp", key: "hrk_abc")] {
            XCTAssertTrue(t.contains("Send a custom User-Agent"))
            XCTAssertTrue(t.contains("Python-urllib/3.x")); XCTAssertTrue(t.contains("Error 1010"))
            XCTAssertTrue(t.contains(#""User-Agent": "Herald-Agent/1.0""#))
            XCTAssertTrue(t.contains("custom domain"))
        }
    }

    private let url = "https://herald-relay.acme.workers.dev/mcp"

    func testOAuthBlockIsForChatGPTAndNeedsNoKey() {
        let t = RelayInstructions.oauth(mcpURL: url)
        for needle in ["ChatGPT", "OpenAI", "Authentication: OAuth", url, "Approve", "Connector approvals", "6-digit", "Revoke"] {
            XCTAssertTrue(t.contains(needle), needle)
        }
        XCTAssertFalse(t.contains("hrk_")); XCTAssertFalse(t.contains("Bearer"))
    }

    func testStaticBlockHasClaudeCodeAndCodexAndHidesNothingBehindAPlaceholder() {
        let none = RelayInstructions.staticKey(mcpURL: url)
        XCTAssertTrue(none.contains("claude mcp add --transport http herald \(url)")); XCTAssertTrue(none.contains("<your key>"))
        XCTAssertTrue(none.contains("[mcp_servers.herald]")); XCTAssertTrue(none.contains("bearer_token_env_var = \"HERALD_RELAY_KEY\""))
        XCTAssertTrue(none.contains("Create a key below"))
        let with = RelayInstructions.staticKey(mcpURL: url, key: "hrk_abc")
        XCTAssertTrue(with.contains("Bearer hrk_abc")); XCTAssertFalse(with.contains("<your key>")); XCTAssertFalse(with.contains("Create a key below"))
    }
}

// MARK: - The setup routes

final class RelaySetupRoutesTests: XCTestCase {
    final class FakeSetup: RelaySetupBackend, @unchecked Sendable {
        var token: String?; var deployed = 0; var deleted = 0; var patches: [[String: JSONValue]] = []
        func setupStatus() async -> RelaySetupStatus {
            RelaySetupStatus(state: token == nil ? "token-needed" : "ready", hasToken: token != nil, paired: false, online: false, relayURL: "", mcpURL: "",
                             bundledVersion: "abc", deployedVersion: nil, updateAvailable: false, message: nil, steps: [], usage: nil)
        }
        func setCloudflareToken(_ t: String) async throws { token = t }
        func deployRelay() async throws -> RelayDeployReply {
            deployed += 1
            return RelayDeployReply(deployed: true, upgraded: deployed > 1, relayURL: "https://r.acme.workers.dev", paired: true, online: true,
                                    steps: [RelayStepReport(DeployEvent(step: .upload, phase: .done, detail: "created"))])
        }
        func relaySettings() async -> RelaySettingsReply { RelaySettingsReply(settings: RelayCloudConfig(), pairingSecretSet: true, errors: [:], redeployed: false, steps: []) }
        func updateRelaySettings(_ p: [String: JSONValue]) async throws -> RelaySettingsReply {
            patches.append(p)
            if p["maxQueue"] == .number(0) { throw BackendError(400, "maxQueue: Between 1 and 1000.") }
            return RelaySettingsReply(settings: RelayCloudConfig(), pairingSecretSet: true, errors: [:], redeployed: true, steps: [])
        }
        func deleteRelay() async throws -> RelayDeleteReply { deleted += 1; return RelayDeleteReply(deleted: true, note: nil) }
        func testRelay() async throws -> RelayTestReply { RelayTestReply(healthy: true, paired: true, online: true, roundTrip: true, receipt: "displayed", detail: "ok") }
        func relayZones() async throws -> RelayZonesReply { RelayZonesReply(zones: [RelayZone(id: "z1", name: "example.com", status: "active")]) }
        func relayInstructions(client: String) async throws -> String {
            guard ["chatgpt", "claude", "codex"].contains(client) else { throw BackendError(400, "client must be chatgpt, claude or codex") }
            return "instructions for \(client)"
        }
    }

    private func call(_ m: String, _ p: String, body: String = "", query: [String: String] = [:], token: String? = "tok", setup: FakeSetup) async -> HTTPResponse? {
        let r = HTTPRequest(method: m, path: p, query: query, headers: token.map { ["authorization": "Bearer \($0)"] } ?? [:], body: Data(body.utf8))
        return await RelayRoutes.handle(r, token: "tok", backend: RelayRoutesTests.FakeBackend(), setup: setup)
    }
    private func obj(_ r: HTTPResponse?) -> [String: Any] { (try? JSONSerialization.jsonObject(with: r!.body)) as? [String: Any] ?? [:] }

    func testSetupRoutesNeedTheTokenAndAreAbsentWithoutABackend() async {
        let s = FakeSetup()
        let denied = await call("GET", "/v1/relay/setup", token: nil, setup: s)
        XCTAssertEqual(denied?.status, 401)
        let none = await RelayRoutes.handle(HTTPRequest(method: "GET", path: "/v1/relay/setup", headers: ["authorization": "Bearer tok"], body: Data()), token: "tok", backend: RelayRoutesTests.FakeBackend())
        XCTAssertEqual(none?.status, 404)
    }

    func testWalkthroughTokenDeployUpgradeSettingsTestInstructionsDelete() async {
        let s = FakeSetup()
        var r = await call("GET", "/v1/relay/setup", setup: s)
        XCTAssertEqual(obj(r)["state"] as? String, "token-needed")
        r = await call("GET", "/v1/relay/token-url", setup: s)
        XCTAssertTrue((obj(r)["url"] as? String ?? "").hasPrefix("https://dash.cloudflare.com/profile/api-tokens?permissionGroupKeys="))
        XCTAssertEqual((obj(r)["permissions"] as? [[String: Any]])?.count, 9)
        r = await call("POST", "/v1/relay/token", body: #"{"token":"cf-secret-token-123456"}"#, setup: s)
        XCTAssertEqual(r?.status, 200); XCTAssertEqual(s.token, "cf-secret-token-123456")
        XCTAssertFalse(String(decoding: r!.body, as: UTF8.self).contains("cf-secret"))   // never echoed
        let state = await call("GET", "/v1/relay/setup", setup: s)
        XCTAssertFalse(String(decoding: state!.body, as: UTF8.self).contains("cf-secret"))
        r = await call("POST", "/v1/relay/token", body: "{}", setup: s); XCTAssertEqual(r?.status, 400)
        r = await call("POST", "/v1/relay/deploy", setup: s)
        XCTAssertEqual(obj(r)["upgraded"] as? Bool, false); XCTAssertEqual((obj(r)["steps"] as? [[String: Any]])?.first?["title"] as? String, "Upload the relay")
        r = await call("POST", "/v1/relay/deploy", setup: s); XCTAssertEqual(obj(r)["upgraded"] as? Bool, true)
        r = await call("PUT", "/v1/relay/settings", body: #"{"maxQueue":50}"#, setup: s)
        XCTAssertEqual(obj(r)["redeployed"] as? Bool, true); XCTAssertEqual(s.patches.last?["maxQueue"], .number(50))
        r = await call("PUT", "/v1/relay/settings", body: #"{"maxQueue":0}"#, setup: s); XCTAssertEqual(r?.status, 400)
        r = await call("GET", "/v1/relay/settings", setup: s)
        XCTAssertEqual(obj(r)["pairingSecretSet"] as? Bool, true); XCTAssertNil(obj(r)["pairingSecret"])
        r = await call("GET", "/v1/relay/zones", setup: s)
        XCTAssertEqual((obj(r)["zones"] as? [[String: Any]])?.first?["suggestedHostname"] as? String, "herald.example.com")
        r = await call("PUT", "/v1/relay/settings", body: #"{"customDomain":{"zone":"example.com","hostname":"herald.example.com"}}"#, setup: s)
        XCTAssertEqual(r?.status, 200)
        if case .object(let cd)? = s.patches.last?["customDomain"] { XCTAssertEqual(cd["hostname"], .string("herald.example.com")) } else { XCTFail("customDomain not passed") }
        r = await call("POST", "/v1/relay/test", setup: s); XCTAssertEqual(obj(r)["roundTrip"] as? Bool, true)
        r = await call("GET", "/v1/relay/instructions", query: ["client": "chatgpt"], setup: s); XCTAssertEqual(obj(r)["text"] as? String, "instructions for chatgpt")
        r = await call("GET", "/v1/relay/instructions", query: ["client": "bing"], setup: s); XCTAssertEqual(r?.status, 400)
        // delete needs an explicit confirmation
        r = await call("POST", "/v1/relay/delete", body: "{}", setup: s); XCTAssertEqual(r?.status, 400); XCTAssertEqual(s.deleted, 0)
        r = await call("POST", "/v1/relay/delete", body: #"{"confirm":true}"#, setup: s); XCTAssertEqual(r?.status, 200); XCTAssertEqual(s.deleted, 1)
    }

    func testStatusCarriesTheSetupStateMachine() async {
        let s = FakeSetup()
        let r = await call("GET", "/v1/relay/status", setup: s)
        XCTAssertEqual((obj(r)["setup"] as? [String: Any])?["state"] as? String, "token-needed")
    }

    func testApplyingSettingsValidatesNamesAndTypes() throws {
        let c = try RelayCloudConfig().applying(["maxQueue": .number(7), "workerName": .string(" my-relay ")])
        XCTAssertEqual(c.maxQueue, 7); XCTAssertEqual(c.workerName, "my-relay")
        XCTAssertThrowsError(try RelayCloudConfig().applying(["nope": .number(1)]))
        XCTAssertThrowsError(try RelayCloudConfig().applying(["maxQueue": .string("7")]))
        XCTAssertThrowsError(try RelayCloudConfig().applying(["maxQueue": .number(7.5)]))
    }
}
