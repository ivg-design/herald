import Foundation
import HeraldClient

/// Wire types of the cloud relay (relay/ in this repo, docs/CLOUD.md). Everything here is pure: no sockets, no UI.

public enum RelayDefaults {
    /// The relay deployed for this repo. Settings > Cloud can point Herald at another one.
    /// The maintainer's own relay. Not a default: Herald pairs with a relay in the user's own Cloudflare account. Only used to forget it.
    public static let legacyHostedURL = "https://herald-relay.ivg-design.workers.dev"
    public static let dedupeHours = 24.0
    public static let logLimit = 20
    /// Keepalive: a text "ping" the relay answers itself ("pong", without waking its Durable Object). Every 5 minutes at most
    /// often: the free plan's budget (docs/CLOUD.md, "Free plan budget").
    public static let pingSeconds = 300.0
    public static let appPrefix = "cloud."
}

public struct RelayKeyRef: Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var client: String
}

/// What the relay hands the Mac for one notification. The payload is the relay's text-only schema.
public struct RelayEnvelope: Codable, Equatable, Sendable {
    public struct Payload: Codable, Equatable, Sendable {
        public var title: String
        public var subtitle: String?
        public var body: String?
        public var status: String?
        public var project: String?
        public var session: String?
        public var task: String?
        public var tool: String?
        public var duration: String?
        public var link: String?
        public var group: String?
        public var priority: String?
        public var speak: JSONValue?
        public var expectReply: Bool?
        public var allowVoiceReply: Bool?
        // Presentation (non-executable; docs/CLOUD.md "Presentation fields"). Every one is optional.
        public var persistent: Bool?
        public var timeoutSeconds: Double?
        public var sound: String?
        public var voice: String?
        public var speed: Double?
        public var presentation: String?
        public var icon: String?
        public var imageURL: String?
        public var tags: [String]?
    }
    public var type: String
    /// The relay's id for this delivery (`r_<hex>`): the Herald notification id, the receipt key and the dedupe key.
    public var id: String
    public var notificationId: String
    public var createdAt: String?
    public var key: RelayKeyRef
    public var payload: Payload

    public init(id: String, notificationId: String, key: RelayKeyRef, payload: Payload, createdAt: String? = nil) {
        self.type = "notify"; self.id = id; self.notificationId = notificationId; self.key = key; self.payload = payload
        self.createdAt = createdAt
    }
}

public enum RelayReceiptKind: String, Codable, Sendable { case displayed, spoken, replied, suppressed }

public struct RelayReceipt: Codable, Equatable, Sendable {
    public var type = "receipt"
    public var id: String
    public var kind: RelayReceiptKind
    public var reason: String?
    /// For `suppressed`: `all` (nothing shown) or `speech` (the banner showed, the speech did not).
    public var scope: String?
    public var text: String?
    public var transcript: String?
    public var durationSeconds: Double?

    public init(id: String, kind: RelayReceiptKind, reason: String? = nil, scope: String? = nil, text: String? = nil,
                transcript: String? = nil, durationSeconds: Double? = nil) {
        self.id = id; self.kind = kind; self.reason = reason; self.scope = scope; self.text = text
        self.transcript = transcript; self.durationSeconds = durationSeconds
    }
}

/// An agent key as the relay lists it (never the secret).
public struct RelayKeyInfo: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var client: String
    public var scope: String
    /// `static` for a key made in Settings, `oauth` for a connector approved through the OAuth flow (ChatGPT and friends).
    public var kind: String?
    /// The connector's own name for an oauth key ("ChatGPT"); `name` is its slug.
    public var displayName: String?
    public var createdAt: String?
    public var lastUsedAt: String?
    public var revokedAt: String?
    public var isActive: Bool { revokedAt == nil }
    public var isOAuth: Bool { kind == "oauth" }
    /// What a person calls it: the connector's name for an oauth key, otherwise the key name.
    public var title: String { isOAuth ? (displayName ?? name) : name }
}

/// A connector asking to be approved (the OAuth flow, docs/CLOUD.md "Connect ChatGPT"): the relay pushes it down the socket,
/// Herald asks on a banner, and the 6-digit `code` is the fallback the user can type on the consent page.
public struct RelayConsent: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var clientId: String?
    public var clientName: String
    /// Where the browser goes after the decision (the connector's own host), so a look-alike name is visible.
    public var redirectHost: String?
    public var scope: String?
    public var code: String
    /// `pending`, `approved`, `denied` or `expired`.
    public var status: String
    public var createdAt: String?
    public var expiresAt: String?
    /// `device` for an agent with no browser (RFC 8628), `code` for the browser flow. Absent from an older relay.
    public var flow: String?
    /// Device flow only: the code the agent printed (`BDFG-HJKM`), shown so the user can match it. `code` stays the 6-digit
    /// approval code for the relay's /activate page.
    public var userCode: String?

    public init(id: String, clientId: String? = nil, clientName: String, redirectHost: String? = nil, scope: String? = "notify",
                code: String, status: String = "pending", createdAt: String? = nil, expiresAt: String? = nil,
                flow: String? = nil, userCode: String? = nil) {
        self.id = id; self.clientId = clientId; self.clientName = clientName; self.redirectHost = redirectHost; self.scope = scope
        self.code = code; self.status = status; self.createdAt = createdAt; self.expiresAt = expiresAt
        self.flow = flow; self.userCode = userCode
    }

    public var isDevice: Bool { flow == "device" && userCode?.isEmpty == false }

    public var expiresDate: Date? {
        guard let expiresAt else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: expiresAt) ?? ISO8601DateFormatter().date(from: expiresAt)
    }
    public func isPending(now: Date = Date()) -> Bool {
        status == "pending" && (expiresDate.map { $0 > now } ?? true)
    }
    /// "123 456": the code as it is read off the screen.
    public var spacedCode: String { code.count == 6 ? String(code.prefix(3)) + " " + String(code.suffix(3)) : code }
}

/// A key just minted: the only time its secret is ever shown.
public struct RelayNewKey: Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var client: String
    public var scope: String
    public var key: String
    public var createdAt: String?
}

public struct RelayUsage: Codable, Equatable, Sendable {
    public var day: String
    public var requests: Int
    public var wsMessages: Int
    public var notifications: Int
    public var pollSeconds: Int
    public var audioUploads: Int
    public var audioBytes: Int
    public var queued: Int
    public var storageBytes: Int
    public var requestsPercent: Int
    public var budgetExhausted: Bool
}

public struct RelayDeviceInfo: Codable, Equatable, Sendable {
    public struct Quiet: Codable, Equatable, Sendable { public var active: Bool; public var until: String? }
    public var online: Bool
    public var lastSeenAt: String?
    public var pending: Int
    public var keys: Int
    public var quietHours: Quiet?
}

public enum RelayConnectionState: Equatable, Sendable {
    case unpaired
    case disconnected
    case connecting
    case online
    /// The relay (or Cloudflare) refused with a limit: the reason, and when to try again.
    case limited(String)
    case failed(String)

    public var label: String {
        switch self {
        case .unpaired: return "Not paired"
        case .disconnected: return "Offline"
        case .connecting: return "Connecting\u{2026}"
        case .online: return "Online"
        case .limited: return "Relay offline \u{2014} limit reached"
        case .failed(let m): return "Offline: \(m)"
        }
    }
}

/// One line of the Settings > Cloud log (the last 20 relay items) and its receipt states.
public struct RelayLogEntry: Codable, Equatable, Sendable, Identifiable {
    public var id: String          // relay delivery id
    public var key: String         // agent key name
    public var title: String
    public var receivedAt: Date
    public var displayed: Bool = false
    public var spoken: Bool = false
    public var replied: Bool = false
    public var suppressed: String?
    public var duplicate: Bool = false

    public var summary: String {
        var parts: [String] = []
        if let s = suppressed { parts.append("suppressed (\(s))") }
        if displayed { parts.append("displayed") }
        if spoken { parts.append("spoken") }
        if replied { parts.append("replied") }
        return parts.isEmpty ? "received" : parts.joined(separator: ", ")
    }
}
