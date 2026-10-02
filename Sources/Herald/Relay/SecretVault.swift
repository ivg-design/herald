import Foundation
import Security

/// The few SecItem calls the vault makes, so tests can stand a fake in for the Keychain.
public protocol SecItemLayer: Sendable {
    func add(_ attributes: [String: Any]) -> OSStatus
    func copy(_ query: [String: Any]) -> (OSStatus, Data?)
    func delete(_ query: [String: Any]) -> OSStatus
}

public struct SystemSecItem: SecItemLayer {
    public init() {}
    public func add(_ attributes: [String: Any]) -> OSStatus { SecItemAdd(attributes as CFDictionary, nil) }
    public func copy(_ query: [String: Any]) -> (OSStatus, Data?) {
        var out: AnyObject?
        let s = SecItemCopyMatching(query as CFDictionary, &out)
        return (s, s == errSecSuccess ? out as? Data : nil)
    }
    public func delete(_ query: [String: Any]) -> OSStatus { SecItemDelete(query as CFDictionary) }
}

/// One secret of Herald's (the relay device token, the Cloudflare token, ...) kept where it never asks the user for a password.
///
/// The old store was the legacy login keychain. Its access list is tied to the app's code signature, so every update that changes
/// the signature makes macOS ask "Herald wants to use your confidential information ... enter your keychain password", and a
/// user whose keychain password is out of sync cannot answer. The vault instead uses
///  1. the **data-protection keychain** (`kSecUseDataProtectionKeychain`, this device only, after first unlock): no per-signature
///     access list, no prompt. On macOS it needs the app's application identifier from a provisioning profile; a Developer ID app
///     built without one gets `errSecMissingEntitlement` (-34018) and the vault falls back to
///  2. a **0600 file in Herald's support folder** (`secrets/<service>.<account>`), the same protection the local API token already has.
///
/// Migration: when neither holds the secret, the legacy item is read **once** (it may prompt one last time; Deny, a wrong password,
/// a locked keychain and every other failure count as "not found"), copied into the new store and deleted from the old one. The
/// attempt is recorded in a marker file before the read, so it is never repeated and never loops, whatever happened.
public final class SecretVault: @unchecked Sendable {
    public let service: String
    public let account: String
    private let directory: URL?
    private let layer: SecItemLayer
    private let lock = NSLock()
    private var migrationTried = false

    /// `directory` is the support folder (nil: no file fallback and no persisted migration marker, for callers that only want the keychain).
    public init(service: String, account: String, directory: URL?, layer: SecItemLayer = SystemSecItem()) {
        self.service = service; self.account = account; self.directory = directory; self.layer = layer
    }

    // MARK: Queries

    private var base: [String: Any] { [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account] }
    private var protectedQuery: [String: Any] { var q = base; q[kSecUseDataProtectionKeychain as String] = true; return q }
    private var legacyQuery: [String: Any] { var q = base; q[kSecUseDataProtectionKeychain as String] = false; return q }

    // MARK: Files

    private var secretsFolder: URL? { directory?.appendingPathComponent("secrets", isDirectory: true) }
    private var secretFile: URL? { secretsFolder?.appendingPathComponent("\(service).\(account)") }
    private var markerFile: URL? { secretsFolder?.appendingPathComponent("\(service).\(account).migrated") }

    private func readFile() -> String? {
        guard let f = secretFile, let d = try? Data(contentsOf: f) else { return nil }
        return String(data: d, encoding: .utf8)
    }

    private func writeFile(_ value: String) -> Bool {
        guard let folder = secretsFolder, let f = secretFile else { return false }
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try Data(value.utf8).write(to: f, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: f.path)
            return true
        } catch { return false }
    }

    // MARK: Protected keychain

    private func readProtected() -> String? {
        var q = protectedQuery
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        let (s, d) = layer.copy(q)
        guard s == errSecSuccess, let d else { return nil }
        return String(data: d, encoding: .utf8)
    }

    private func writeProtected(_ value: String) -> OSStatus {
        _ = layer.delete(protectedQuery)
        var q = protectedQuery
        q[kSecValueData as String] = Data(value.utf8)
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return layer.add(q)
    }

    // MARK: API

    public func load() -> String? {
        if let v = readProtected() { return v }
        if let v = readFile() { return v }
        return migrateLegacyOnce()
    }

    @discardableResult
    public func save(_ value: String) -> Bool {
        if writeProtected(value) == errSecSuccess {
            if let f = secretFile { try? FileManager.default.removeItem(at: f) }   // one home for the secret
            return true
        }
        // The data-protection keychain refused (no application identifier: -34018, or anything else): the 0600 file keeps it.
        return writeFile(value)
    }

    /// Removes the secret from the new stores. The legacy item is not touched here (deleting it can prompt); the migration does that.
    public func delete() {
        _ = layer.delete(protectedQuery)
        if let f = secretFile { try? FileManager.default.removeItem(at: f) }
    }

    /// Reads the legacy login-keychain item the first time the new stores are empty. Never blocks twice, never throws.
    private func migrateLegacyOnce() -> String? {
        lock.lock(); defer { lock.unlock() }
        if migrationTried { return nil }
        migrationTried = true
        if let m = markerFile, FileManager.default.fileExists(atPath: m.path) { return nil }
        // Mark first: a crash, a quit or a Deny during the read must not make the next launch ask again.
        if let m = markerFile, let folder = secretsFolder {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try? Data().write(to: m)
        }
        var q = legacyQuery
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        let (status, data) = layer.copy(q)
        // errSecItemNotFound, errSecAuthFailed, errSecInteractionNotAllowed, a cancelled prompt (errSecUserCanceled), ...: nothing to migrate.
        guard status == errSecSuccess, let data, let value = String(data: data, encoding: .utf8) else { return nil }
        guard save(value) else { return value }   // could not be stored anywhere new: keep the legacy item, use the value this launch
        _ = layer.delete(legacyQuery)
        return value
    }
}
