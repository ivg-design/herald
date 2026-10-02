import Foundation
import Security

/// Where the device token lives. The Keychain in the app; memory in tests.
public protocol RelayTokenStore: AnyObject, Sendable {
    func load() -> String?
    func save(_ token: String) -> Bool
    func delete()
}

public final class MemoryTokenStore: RelayTokenStore, @unchecked Sendable {
    private let lock = NSLock()
    private var token: String?
    public init(token: String? = nil) { self.token = token }
    public func load() -> String? { lock.lock(); defer { lock.unlock() }; return token }
    public func save(_ t: String) -> Bool { lock.lock(); token = t; lock.unlock(); return true }
    public func delete() { lock.lock(); token = nil; lock.unlock() }
}

/// The device token in the macOS Keychain (generic password, this device only, available after first unlock so the
/// relay reconnects at login). `service` is per support folder so a test instance never touches the real token.
public final class KeychainTokenStore: RelayTokenStore, @unchecked Sendable {
    private let service: String
    private let account = "relay-device-token"
    public init(service: String = "com.ivg.herald.relay") { self.service = service }

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }

    public func load() -> String? {
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }

    public func save(_ token: String) -> Bool {
        delete()
        var q = query
        q[kSecValueData as String] = Data(token.utf8)
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(q as CFDictionary, nil) == errSecSuccess
    }

    public func delete() { SecItemDelete(query as CFDictionary) }
}

/// What Herald remembers about the relay between launches (not the token): which relay, which device, and the log of
/// the last items. One small JSON file in the support folder.
public struct RelayState: Codable, Equatable, Sendable {
    public var relayURL: String = ""
    public var deviceId: String?
    public var pairedAt: Date?
    public var lastSeenAt: Date?
    public var log: [RelayLogEntry] = []
}

public final class RelayStateStore: @unchecked Sendable {
    private let lock = NSLock()
    private let file: URL?
    private var state: RelayState

    public init(file: URL?) {
        self.file = file
        if let file, let d = try? Data(contentsOf: file), let s = try? HeraldJSONCoding.decoder.decode(RelayState.self, from: d) { state = s }
        else { state = RelayState() }
    }

    public var value: RelayState { lock.lock(); defer { lock.unlock() }; return state }

    public func update(_ change: (inout RelayState) -> Void) {
        lock.lock(); change(&state)
        if state.log.count > RelayDefaults.logLimit { state.log = Array(state.log.prefix(RelayDefaults.logLimit)) }
        let snapshot = state
        lock.unlock()
        save(snapshot)
    }

    /// Newest first. An existing entry with the same id is updated in place by `change`.
    public func logEntry(_ id: String, create: @autoclosure () -> RelayLogEntry, _ change: (inout RelayLogEntry) -> Void) {
        update { s in
            if let i = s.log.firstIndex(where: { $0.id == id }) { change(&s.log[i]) }
            else { var e = create(); change(&e); s.log.insert(e, at: 0) }
        }
    }

    private func save(_ s: RelayState) {
        guard let file, let d = try? HeraldJSONCoding.encoder.encode(s) else { return }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? d.write(to: file, options: .atomic)
    }
}

enum HeraldJSONCoding {
    static var decoder: JSONDecoder { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }
    static var encoder: JSONEncoder { let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; e.outputFormatting = [.prettyPrinted, .sortedKeys]; return e }
}

/// Relay delivery ids already seen, kept 24 hours on disk so a redelivery after a reconnect or a restart never shows a
/// second banner. Remembers what was already reported for each so a duplicate can be answered again.
public final class RelayDedupe: @unchecked Sendable {
    public struct Entry: Codable, Equatable, Sendable {
        public var at: Date
        public var pair: String          // "<keyId>:<notificationId>"
        public var displayed = false
        public var suppressed: String?
    }
    private let lock = NSLock()
    private let file: URL?
    private var entries: [String: Entry]
    private let ttl: TimeInterval

    public init(file: URL?, ttl: TimeInterval = RelayDefaults.dedupeHours * 3600) {
        self.file = file; self.ttl = ttl
        if let file, let d = try? Data(contentsOf: file), let e = try? HeraldJSONCoding.decoder.decode([String: Entry].self, from: d) { entries = e }
        else { entries = [:] }
    }

    /// True when this delivery (by relay id, or by key + sender id) was already seen. Otherwise it is recorded.
    public func seenBefore(id: String, keyId: String, notificationId: String, now: Date = Date()) -> Bool {
        lock.lock(); defer { lock.unlock() }
        prune(now)
        let pair = keyId + ":" + notificationId
        if entries[id] != nil || entries.values.contains(where: { $0.pair == pair }) { return true }
        entries[id] = Entry(at: now, pair: pair)
        save()
        return false
    }

    public func entry(_ id: String) -> Entry? { lock.lock(); defer { lock.unlock() }; return entries[id] }

    /// What is known about a delivery: by its relay id, else by the key and sender id it was first seen under.
    public func entry(id: String, keyId: String, notificationId: String) -> Entry? {
        lock.lock(); defer { lock.unlock() }
        return entries[id] ?? entries.values.first { $0.pair == keyId + ":" + notificationId }
    }

    public func mark(_ id: String, _ change: (inout Entry) -> Void) {
        lock.lock(); defer { lock.unlock() }
        guard var e = entries[id] else { return }
        change(&e); entries[id] = e; save()
    }

    public var count: Int { lock.lock(); defer { lock.unlock() }; return entries.count }

    private func prune(_ now: Date) { entries = entries.filter { now.timeIntervalSince($0.value.at) < ttl } }

    private func save() {
        guard let file, let d = try? HeraldJSONCoding.encoder.encode(entries) else { return }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? d.write(to: file, options: .atomic)
    }
}
