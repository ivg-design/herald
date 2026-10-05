import Foundation

public protocol RelayHTTP: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionRelayHTTP: RelayHTTP {
    public init() {}
    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (d, r) = try await URLSession.shared.data(for: request)
        guard let h = r as? HTTPURLResponse else { throw RelayError.transport("no HTTP response") }
        return (d, h)
    }
}

public enum RelayError: Error, Equatable, LocalizedError, Sendable {
    case transport(String)
    case http(Int, String)
    case limited(String, retryAfter: Int?)
    case notPaired

    public var errorDescription: String? {
        switch self {
        case .transport(let m): return m
        case .http(let c, let m): return "relay answered \(c): \(m)"
        case .limited(let m, _): return m
        case .notPaired: return "Herald is not paired with a relay"
        }
    }
}

/// The calls Herald makes to its relay over HTTPS: pairing, agent keys, usage, voice-reply upload. The notification stream is
/// the WebSocket (`RelayClient`); nothing here polls.
public struct RelayAPI: Sendable {
    public var baseURL: URL
    public var token: String?
    public var http: RelayHTTP

    public init(baseURL: URL, token: String? = nil, http: RelayHTTP = URLSessionRelayHTTP()) {
        self.baseURL = baseURL; self.token = token; self.http = http
    }

    private func request(_ method: String, _ path: String, body: Data? = nil, contentType: String = "application/json",
                         authorized: Bool = true) throws -> URLRequest {
        guard let url = URL(string: path, relativeTo: baseURL)?.absoluteURL else { throw RelayError.transport("bad URL") }
        var r = URLRequest(url: url)
        r.httpMethod = method
        r.timeoutInterval = 30
        if authorized {
            guard let token else { throw RelayError.notPaired }
            r.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        }
        if let body { r.httpBody = body; r.setValue(contentType, forHTTPHeaderField: "Content-Type") }
        return r
    }

    private func run<T: Decodable>(_ r: URLRequest, as: T.Type) async throws -> T {
        let (d, h) = try await perform(r)
        do { return try HeraldJSONCoding.decoder.decode(T.self, from: d) }
        catch { throw RelayError.http(h.statusCode, "unreadable answer") }
    }

    @discardableResult
    private func perform(_ r: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let d: Data, h: HTTPURLResponse
        do { (d, h) = try await http.send(r) } catch let e as RelayError { throw e } catch { throw RelayError.transport(error.localizedDescription) }
        guard (200..<300).contains(h.statusCode) else { throw Self.failure(h, d) }
        return (d, h)
    }

    /// Maps an error response: 429 and 503 are limits (with Retry-After); anything else carries the relay's message.
    public static func failure(_ h: HTTPURLResponse, _ d: Data) -> RelayError {
        let msg = ((try? JSONSerialization.jsonObject(with: d)) as? [String: Any])?["message"] as? String ?? String(data: d.prefix(200), encoding: .utf8) ?? ""
        if h.statusCode == 429 || h.statusCode == 503 || msg.contains("1027") {
            return .limited(msg.isEmpty ? "limit reached" : msg, retryAfter: Int(h.value(forHTTPHeaderField: "Retry-After") ?? ""))
        }
        return .http(h.statusCode, msg)
    }

    // MARK: Pairing

    public func startPairing(deviceName: String, pairingSecret: String? = nil) async throws -> (code: String, expiresInSeconds: Int) {
        struct R: Decodable { var code: String; var expiresInSeconds: Int }
        var r = try request("POST", "/v1/pair/start", body: try JSONSerialization.data(withJSONObject: ["deviceName": deviceName]), authorized: false)
        if let pairingSecret { r.setValue(pairingSecret, forHTTPHeaderField: "X-Pairing-Secret") }
        let v = try await run(r, as: R.self)
        return (v.code, v.expiresInSeconds)
    }

    public func pair(code: String, deviceName: String) async throws -> (deviceId: String, deviceToken: String) {
        struct R: Decodable { var deviceId: String; var deviceToken: String }
        let body = try JSONSerialization.data(withJSONObject: ["code": code, "deviceName": deviceName])
        let v = try await run(try request("POST", "/v1/pair", body: body, authorized: false), as: R.self)
        return (v.deviceId, v.deviceToken)
    }

    public func unpair() async throws { try await perform(try request("DELETE", "/v1/device")) }

    // MARK: Keys, status, usage

    public func listKeys() async throws -> [RelayKeyInfo] {
        struct R: Decodable { var keys: [RelayKeyInfo] }
        return try await run(try request("GET", "/v1/device/keys"), as: R.self).keys
    }

    public func createKey(name: String, client: String) async throws -> RelayNewKey {
        let body = try JSONSerialization.data(withJSONObject: ["name": name, "client": client, "scope": "notify"])
        return try await run(try request("POST", "/v1/device/keys", body: body), as: RelayNewKey.self)
    }

    public func revokeKey(id: String) async throws { try await perform(try request("DELETE", "/v1/device/keys/\(id)")) }
    /// Forgets a throw-away key altogether (its row, tokens and what it sent), instead of leaving it listed as revoked.
    public func purgeKey(id: String) async throws { try await perform(try request("DELETE", "/v1/device/keys/\(id)?purge=1")) }
    public func info() async throws -> RelayDeviceInfo { try await run(try request("GET", "/v1/device/info"), as: RelayDeviceInfo.self) }
    public func usage() async throws -> RelayUsage { try await run(try request("GET", "/v1/device/usage"), as: RelayUsage.self) }

    // MARK: Devices on the relay

    /// Drops this Mac's same-name and stale siblings. Called after every pairing, so a Mac that paired again does not leave its old
    /// entry first in the relay's list.
    @discardableResult
    public func prune() async throws -> (removed: [String], devices: [RelayDeviceEntry]) {
        struct R: Decodable { var removed: [String]; var devices: [RelayDeviceEntry] }
        let v = try await run(try request("POST", "/v1/device/prune", body: Data("{}".utf8)), as: R.self)
        return (v.removed, v.devices)
    }

    public func devices() async throws -> [RelayDeviceEntry] {
        struct R: Decodable { var devices: [RelayDeviceEntry] }
        return try await run(try request("GET", "/v1/device/devices"), as: R.self).devices
    }

    /// 403 `not_removable` for an active different Mac.
    public func removeDevice(id: String) async throws { try await perform(try request("DELETE", "/v1/device/devices/\(id)")) }

    // MARK: Connector approvals (OAuth)

    public func consents() async throws -> [RelayConsent] {
        struct R: Decodable { var consents: [RelayConsent] }
        return try await run(try request("GET", "/v1/device/consents"), as: R.self).consents
    }

    /// 409 (already decided) and 410 (expired) come back as `RelayError.http`.
    public func decideConsent(id: String, approve: Bool) async throws {
        let body = try JSONSerialization.data(withJSONObject: ["id": id, "decision": approve ? "approve" : "deny"])
        try await perform(try request("POST", "/v1/device/consent", body: body))
    }

    // MARK: Event subscriptions (MCP Events)

    /// An older relay answers 404.
    public func events() async throws -> RelayEvents { try await run(try request("GET", "/v1/device/events"), as: RelayEvents.self) }

    public func removeEventSubscription(id: String) async throws { try await perform(try request("DELETE", "/v1/device/events/subscriptions/\(id)")) }

    // MARK: Receipts and voice replies

    public func sendReceipt(_ receipt: RelayReceipt) async throws {
        let path = receipt.kind == .replied ? "/v1/device/reply" : "/v1/device/receipt"
        try await perform(try request("POST", path, body: try JSONEncoder().encode(receipt)))
    }

    /// The largest voice reply the relay takes.
    public static let maxAudioBytes = 1024 * 1024

    public func uploadAudio(id: String, m4a: Data) async throws {
        guard m4a.count <= Self.maxAudioBytes else { throw RelayError.http(413, "audio is larger than 1 MB") }
        try await perform(try request("PUT", "/v1/device/reply/\(id)/audio", body: m4a, contentType: "audio/mp4"))
    }
}
