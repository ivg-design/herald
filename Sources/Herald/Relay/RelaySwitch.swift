import Foundation

/// Settings > Cloud has one switch, "Enable relay". On: pair this Mac with the relay (the hosted one unless the user chose another
/// under Advanced), handling the pairing code internally, and wait until the connection is up. Off: unpair, which revokes every key
/// and connector. This is the whole state machine behind it, with no UI and no network of its own (the controller supplies a backend).
public enum RelaySwitchState: Equatable, Sendable {
    case off
    case pairing
    case connecting
    case online
    /// The last attempt failed; `paired` says whether this Mac is nevertheless paired (turning on again then skips pairing).
    case failed(String)

    public var label: String {
        switch self {
        case .off: return "Off"
        case .pairing: return "Pairing\u{2026}"
        case .connecting: return "Connecting\u{2026}"
        case .online: return "Online"
        case .failed(let m): return m
        }
    }
}

@MainActor
public protocol RelaySwitchBackend: AnyObject {
    /// Paired with the relay (a device token is stored).
    var isPaired: Bool { get }
    /// The live connection is up.
    var isOnline: Bool { get }
    /// Pairs with the relay in one step: asks for a code and redeems it. Throws a `RelayError`.
    func pair() async throws
    /// Tells the relay to forget this Mac (which revokes every key and connector), then forgets the token here.
    /// Throws when the relay could not be told, in which case nothing is forgotten.
    func unpair() async throws
    /// Starts (or restarts) the connection and waits up to `seconds` for it to come up.
    func connect(timeout seconds: Double) async -> Bool
}

@MainActor
public final class RelaySwitch {
    public private(set) var state: RelaySwitchState = .off
    private let backend: RelaySwitchBackend
    private var busy = false
    public var onChange: (() -> Void)?
    public var connectTimeout: Double = 15

    public init(backend: RelaySwitchBackend) {
        self.backend = backend
        sync()
    }

    /// The switch as the user sees it: on while paired, pairing or connecting; off otherwise (also after a failed first pairing).
    public var isOn: Bool {
        switch state {
        case .off: return false
        case .pairing, .connecting, .online: return true
        case .failed: return backend.isPaired
        }
    }

    public var isBusy: Bool { busy }

    /// Follows the world: called when the app starts and whenever the connection changes. Never overrides an attempt in flight.
    public func sync() {
        guard !busy else { return }
        let next: RelaySwitchState
        if backend.isPaired {
            next = backend.isOnline ? .online : (state == .online || state == .off ? .connecting : state)
        } else if case .failed = state { next = state }
        else { next = .off }
        set(next)
    }

    public func toggle(_ on: Bool) async {
        if on { await turnOn() } else { await turnOff() }
    }

    public func turnOn() async {
        guard !busy else { return }
        busy = true; defer { busy = false }
        if !backend.isPaired {
            set(.pairing)
            do { try await backend.pair() }
            catch { set(.failed(RelaySwitchMessages.friendly(error))); return }
        }
        set(.connecting)
        if backend.isOnline { set(.online); return }
        let up = await backend.connect(timeout: connectTimeout)
        set(up ? .online : .failed(RelaySwitchMessages.paired_but_silent))
    }

    public func turnOff() async {
        guard !busy else { return }
        busy = true; defer { busy = false }
        do { try await backend.unpair(); set(.off) }
        catch { set(.failed(RelaySwitchMessages.unpairFailed(error))) }
    }

    private func set(_ s: RelaySwitchState) {
        guard s != state else { return }
        state = s
        onChange?()
    }
}

/// What the user reads when something goes wrong: plain sentences, no status codes.
public enum RelaySwitchMessages {
    public static let paired_but_silent = "Paired, but the relay is not answering. Check your internet connection, then turn the relay on again."

    public static func friendly(_ error: Error) -> String {
        guard let e = error as? RelayError else { return "Could not turn the relay on: \(error.localizedDescription)" }
        switch e {
        case .transport(let m):
            return m.isEmpty ? "Could not reach the relay. Check your internet connection." : "Could not reach the relay (\(m)). Check your internet connection."
        case .limited(_, let retry):
            if let retry, retry > 0 { return "The relay is limiting new pairings from this network. Try again in \(duration(retry))." }
            return "The relay is limiting new pairings from this network. Try again later."
        case .http(let code, let m):
            if code == 403, m.contains("paired Macs") { return "This relay has no room for another Mac right now." }
            if code == 401 { return "This relay asks for a pairing secret. Open Advanced and use Pair with a code." }
            return "The relay refused the pairing (\(code)). Try again, or open Advanced to use another relay."
        case .notPaired: return "Herald is not paired with a relay."
        }
    }

    public static func unpairFailed(_ error: Error) -> String {
        "Could not reach the relay to revoke your agents and connectors, so the relay is still on. Try again when you are online."
    }

    static func duration(_ seconds: Int) -> String {
        if seconds >= 3600 { return "\(seconds / 3600) hour" + (seconds >= 7200 ? "s" : "") }
        if seconds >= 60 { return "\(seconds / 60) minutes" }
        return "\(seconds) seconds"
    }
}
