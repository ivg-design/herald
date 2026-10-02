import Foundation
import HeraldClient

// MARK: Sockets

public protocol RelaySocket: AnyObject, Sendable {
    func send(_ text: String) async throws
    /// The next text frame; throws when the socket closed or failed.
    func receive() async throws -> String
    func close()
}

public protocol RelaySocketFactory: Sendable {
    func connect(url: URL, token: String) async throws -> RelaySocket
}

/// The real socket: `URLSessionWebSocketTask`. The handshake is lazy, so a refusal (a limit, a revoked token) shows up
/// on the first `receive`; it is turned into a `RelayError` there.
public final class URLSessionRelaySocket: RelaySocket, @unchecked Sendable {
    private let task: URLSessionWebSocketTask
    public init(task: URLSessionWebSocketTask) { self.task = task }

    public func send(_ text: String) async throws { try await task.send(.string(text)) }

    public func receive() async throws -> String {
        do {
            switch try await task.receive() {
            case .string(let s): return s
            case .data(let d): return String(decoding: d, as: UTF8.self)
            @unknown default: return ""
            }
        } catch {
            if let h = task.response as? HTTPURLResponse, !(101...101).contains(h.statusCode) {
                throw RelayAPI.failure(h, Data())
            }
            throw error
        }
    }

    public func close() { task.cancel(with: .goingAway, reason: nil) }
}

public struct URLSessionRelaySocketFactory: RelaySocketFactory {
    public init() {}
    public func connect(url: URL, token: String) async throws -> RelaySocket {
        var r = URLRequest(url: url)
        r.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        let task = URLSession.shared.webSocketTask(with: r)
        task.resume()
        return URLSessionRelaySocket(task: task)
    }
}

// MARK: Host

/// What the app provides to the client: the user's settings and the normal notification path.
@MainActor
public protocol RelayHost: AnyObject {
    /// Mute and the quiet-hours status for this notification (priority already applied).
    func relayInputs(for envelope: RelayEnvelope) -> (muted: Bool, quiet: HeraldQuietStatus)
    /// Mute and the quiet-hours status right now, for the relay's `herald_status`.
    func relayStatusNow() -> (muted: Bool, quiet: HeraldQuietStatus)
    /// Makes sure the agent key's issuer (`cloud.<name>`: manifest, template, icon) exists.
    func relayEnsureIssuer(_ key: RelayKeyRef) async
    /// Sends the notification through the normal path and returns once its banner is up (or the item is in History when the
    /// banner is not shown). Throws when it could not be delivered.
    func relayDeliver(_ notification: HeraldNotification) async throws
    /// A connector (ChatGPT, ...) asks to be approved. Herald shows the question on a banner; it never takes focus.
    func relayConsentRequested(_ consent: RelayConsent)
    /// The request was settled somewhere else (the 6-digit code on the consent page, the page's Deny, a timeout).
    func relayConsentResolved(id: String, status: String)
    /// The notification carried an acceptable `icon` (an https URL or a small data: image): make it the sender's icon.
    func relayApplyIcon(_ source: String, for key: RelayKeyRef) async
}

public extension RelayHost {
    func relayApplyIcon(_ source: String, for key: RelayKeyRef) async {}
    func relayConsentRequested(_ consent: RelayConsent) {}
    func relayConsentResolved(id: String, status: String) {}
}

public enum RelayBackoff {
    /// 1 s, 2 s, 4 s ... up to 5 minutes, with +-20 % jitter (`jitter` is 0...1).
    public static func delay(attempt: Int, jitter: Double = 0.5) -> TimeInterval {
        let base = min(pow(2.0, Double(max(0, attempt))), 300)
        return base * (0.8 + 0.4 * min(max(jitter, 0), 1))
    }
}

// MARK: Client

/// The Mac's side of the relay: one outbound WebSocket, notifications in, receipts out. There is no inbound port. Everything
/// that arrives goes through `RelayPolicy` (mute, quiet hours), the dedupe store and then the app's normal notify path.
@MainActor
public final class RelayClient {
    public private(set) var state: RelayConnectionState = .disconnected { didSet { if state != oldValue { onChange?() } } }
    public var onChange: (() -> Void)?

    public let store: RelayStateStore
    public let dedupe: RelayDedupe
    private let tokens: RelayTokenStore
    private let socketFactory: RelaySocketFactory
    private let httpFactory: (URL, String?) -> RelayAPI
    private weak var host: RelayHost?

    private var socket: RelaySocket?
    private var runner: Task<Void, Never>?
    private var pinger: Task<Void, Never>?
    private var wake: CheckedContinuation<Void, Never>?
    private var pendingReceipts: [RelayReceipt] = []
    private var attempt = 0
    private var lastStatusSignature = ""
    public var pingSeconds: TimeInterval = RelayDefaults.pingSeconds
    /// Test hook: replaces the sleep between reconnect attempts.
    var sleep: (TimeInterval) async -> Void = { try? await Task.sleep(nanoseconds: UInt64($0 * 1_000_000_000)) }

    public init(host: RelayHost, store: RelayStateStore, dedupe: RelayDedupe, tokens: RelayTokenStore,
                socketFactory: RelaySocketFactory = URLSessionRelaySocketFactory(),
                http: RelayHTTP = URLSessionRelayHTTP()) {
        self.host = host; self.store = store; self.dedupe = dedupe; self.tokens = tokens; self.socketFactory = socketFactory
        self.httpFactory = { RelayAPI(baseURL: $0, token: $1, http: http) }
        if tokens.load() == nil { state = .unpaired }
    }

    // MARK: Lifecycle

    public var isPaired: Bool { tokens.load() != nil && store.value.deviceId != nil }

    public var api: RelayAPI? {
        guard let url = URL(string: store.value.relayURL) else { return nil }
        return httpFactory(url, tokens.load())
    }

    public var streamURL: URL? {
        guard var c = URLComponents(string: store.value.relayURL) else { return nil }
        c.scheme = c.scheme == "http" ? "ws" : "wss"
        c.path = "/v1/device/stream"
        return c.url
    }

    /// Starts (or restarts) the connection loop. No-op when not paired.
    public func start() {
        stop()
        guard tokens.load() != nil else { state = .unpaired; return }
        state = .connecting
        runner = Task { [weak self] in await self?.runLoop() }
    }

    public func stop() {
        runner?.cancel(); runner = nil
        pinger?.cancel(); pinger = nil
        socket?.close(); socket = nil
        wake?.resume(); wake = nil
        if tokens.load() == nil { state = .unpaired } else if state != .unpaired { state = .disconnected }
    }

    /// After wake or a network change: drop the (probably dead) socket and connect now, without waiting out the backoff.
    public func reconnectNow() {
        guard tokens.load() != nil else { return }
        attempt = 0
        if runner == nil { start(); return }
        socket?.close()
        wake?.resume(); wake = nil
    }

    private func runLoop() async {
        while !Task.isCancelled {
            guard let token = tokens.load(), let url = streamURL else { state = .unpaired; return }
            state = .connecting
            do {
                let s = try await socketFactory.connect(url: url, token: token)
                try await session(s)
            } catch let e as RelayError {
                switch e {
                case .limited(let m, let retry):
                    state = .limited(m)
                    await pause(TimeInterval(max(retry ?? 0, Int(RelayBackoff.delay(attempt: attempt + 3)))))
                    attempt += 1
                    continue
                case .http(let code, let m) where code == 401 || code == 403:
                    state = .failed("the relay rejected this Mac's token (\(m)); pair again")
                    await pause(300)
                    continue
                default: state = .failed(e.localizedDescription)
                }
            } catch {
                if Task.isCancelled { return }
                state = .disconnected
            }
            if Task.isCancelled { return }
            let d = RelayBackoff.delay(attempt: attempt, jitter: Double.random(in: 0...1))
            attempt += 1
            await pause(d)
        }
    }

    private func pause(_ seconds: TimeInterval) async {
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            wake = c
            Task { [weak self] in
                await self?.sleep(seconds)
                if let self, let w = self.wake { self.wake = nil; w.resume() }
            }
        }
    }

    /// One connection, from the first frame to its end. Throws when the socket closes.
    public func session(_ s: RelaySocket) async throws {
        socket = s
        defer { socket = nil; pinger?.cancel(); pinger = nil; store.update { $0.lastSeenAt = Date() } }
        // The relay greets every connection with "welcome": that, not the lazy handshake, is what makes us online.
        var greeted = false
        while !Task.isCancelled {
            let frame = try await s.receive()
            if !greeted {
                greeted = true
                state = .online
                attempt = 0
                store.update { $0.lastSeenAt = Date() }
                await sendHello(s)
                await flushReceipts(s)
                startPinger(s)
            }
            await handle(frame: frame)
        }
    }

    private func sendHello(_ s: RelaySocket) async {
        let st = host?.relayStatusNow() ?? (muted: false, quiet: HeraldQuietStatus())
        lastStatusSignature = "\(st.quiet.active)|\(st.quiet.until.map { Int($0.timeIntervalSince1970) } ?? 0)|\(st.muted)"
        var o: [String: Any] = ["type": "hello", "quietActive": st.quiet.active, "muted": st.muted]
        if let u = st.quiet.until { o["quietUntil"] = ISO8601DateFormatter().string(from: u) }
        try? await s.send(Self.json(o))
    }

    /// Tells the relay the quiet-hours state changed (the menu, Settings or the clock).
    public func publishStatus() {
        guard let s = socket, let st = host?.relayStatusNow() else { return }
        // Only a change is worth a message: every one counts against the relay's free-plan budget.
        let signature = "\(st.quiet.active)|\(st.quiet.until.map { Int($0.timeIntervalSince1970) } ?? 0)|\(st.muted)"
        guard signature != lastStatusSignature else { return }
        lastStatusSignature = signature
        var o: [String: Any] = ["type": "status", "quietActive": st.quiet.active, "muted": st.muted]
        if let u = st.quiet.until { o["quietUntil"] = ISO8601DateFormatter().string(from: u) }
        Task { try? await s.send(Self.json(o)) }
    }

    private func startPinger(_ s: RelaySocket) {
        pinger?.cancel()
        let every = pingSeconds
        pinger = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(every * 1_000_000_000))
                if Task.isCancelled { return }
                do { try await s.send("ping") } catch { self?.socket?.close(); return }
            }
        }
    }

    // MARK: Incoming

    public func handle(frame: String) async {
        guard let data = frame.data(using: .utf8),
              let type = ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])?["type"] as? String else { return }
        if type == "consent" {
            if let c = try? JSONDecoder().decode(RelayConsent.self, from: data) { host?.relayConsentRequested(c) }
            return
        }
        if type == "consent_resolved" {
            let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            if let id = o?["id"] as? String { host?.relayConsentResolved(id: id, status: o?["status"] as? String ?? "") }
            return
        }
        guard type == "notify" else { return }   // "welcome", "pong" and anything unknown are ignored
        guard let env = try? JSONDecoder().decode(RelayEnvelope.self, from: data) else { return }
        await handleNotify(env)
    }

    private func handleNotify(_ env: RelayEnvelope) async {
        guard let host else { return }
        if dedupe.seenBefore(id: env.id, keyId: env.key.id, notificationId: env.notificationId) {
            // A redelivery: never a second banner. Answer again with what is already known.
            await ack(env.id)
            if let e = dedupe.entry(id: env.id, keyId: env.key.id, notificationId: env.notificationId) {
                if e.displayed { await send(RelayReceipt(id: env.id, kind: .displayed)) }
                if let r = e.suppressed { await send(RelayReceipt(id: env.id, kind: .suppressed, reason: r, scope: "all")) }
            }
            return
        }
        store.logEntry(env.id, create: RelayLogEntry(id: env.id, key: env.key.name, title: env.payload.title, receivedAt: Date())) { _ in }
        await host.relayEnsureIssuer(env.key)
        if let icon = RelayPolicy.iconSource(for: env) { await host.relayApplyIcon(icon, for: env.key) }
        let inputs = host.relayInputs(for: env)
        switch RelayPolicy.decide(muted: inputs.muted, quiet: inputs.quiet) {
        case .suppress(let reason):
            dedupe.mark(env.id) { $0.suppressed = reason }
            store.logEntry(env.id, create: RelayLogEntry(id: env.id, key: env.key.name, title: env.payload.title, receivedAt: Date())) { $0.suppressed = reason }
            await ack(env.id)
            await send(RelayReceipt(id: env.id, kind: .suppressed, reason: reason, scope: "all"))
        case .deliver(let silence):
            let n = RelayPolicy.notification(for: env, silenceSpeech: silence != nil)
            do {
                try await host.relayDeliver(n)
                dedupe.mark(env.id) { $0.displayed = true }
                store.logEntry(env.id, create: RelayLogEntry(id: env.id, key: env.key.name, title: env.payload.title, receivedAt: Date())) { $0.displayed = true }
                await ack(env.id)
                await send(RelayReceipt(id: env.id, kind: .displayed))
                if let silence, env.payload.speak != nil, env.payload.speak != .bool(false) {
                    store.logEntry(env.id, create: RelayLogEntry(id: env.id, key: env.key.name, title: env.payload.title, receivedAt: Date())) { $0.suppressed = "speech: " + silence }
                    await send(RelayReceipt(id: env.id, kind: .suppressed, reason: silence, scope: "speech"))
                }
            } catch {
                dedupe.mark(env.id) { $0.suppressed = "delivery-failed" }
                await ack(env.id)
                await send(RelayReceipt(id: env.id, kind: .suppressed, reason: "delivery-failed", scope: "all"))
            }
        }
    }

    // MARK: Outgoing receipts

    private func ack(_ id: String) async {
        guard let s = socket else { return }
        try? await s.send(Self.json(["type": "ack", "id": id]))
    }

    /// Over the socket when there is one, otherwise kept and sent when the connection is back.
    public func send(_ r: RelayReceipt) async {
        if let s = socket, let text = try? String(data: JSONEncoder().encode(r), encoding: .utf8) {
            do { try await s.send(text); return } catch { /* fall through to the queue */ }
        }
        pendingReceipts.append(r)
        if pendingReceipts.count > 200 { pendingReceipts.removeFirst() }
    }

    private func flushReceipts(_ s: RelaySocket) async {
        let todo = pendingReceipts
        pendingReceipts = []
        for r in todo { await send(r) }
    }

    /// Speech for this delivery played to the end.
    public func reportSpoken(id: String) {
        store.logEntry(id, create: RelayLogEntry(id: id, key: "", title: "", receivedAt: Date())) { $0.spoken = true }
        Task { await send(RelayReceipt(id: id, kind: .spoken)) }
    }

    /// The user typed a reply into the banner.
    public func reportReply(id: String, text: String) {
        store.logEntry(id, create: RelayLogEntry(id: id, key: "", title: "", receivedAt: Date())) { $0.replied = true }
        Task { await send(RelayReceipt(id: id, kind: .replied, text: text)) }
    }

    /// The user recorded a voice reply: the m4a goes up first (so the audio is there when the reply flips to replied), then the
    /// transcript made on this Mac. `transcript` nil means none could be made.
    public func reportVoiceReply(id: String, m4a: Data, transcript: String?, seconds: Double) async throws {
        guard let api else { throw RelayError.notPaired }
        try await api.uploadAudio(id: id, m4a: m4a)
        try await api.sendReceipt(RelayReceipt(id: id, kind: .replied, transcript: transcript, durationSeconds: seconds))
        store.logEntry(id, create: RelayLogEntry(id: id, key: "", title: "", receivedAt: Date())) { $0.replied = true }
    }

    private static func json(_ o: [String: Any]) -> String {
        String(data: (try? JSONSerialization.data(withJSONObject: o)) ?? Data(), encoding: .utf8) ?? "{}"
    }
}
