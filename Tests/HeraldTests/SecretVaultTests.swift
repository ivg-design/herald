import XCTest
import Security
@testable import HeraldCore

/// A stand-in for the Keychain: a legacy login keychain and a data-protection keychain, each a dictionary, with switches for
/// the failures that matter (no entitlement, a denied prompt).
final class FakeSecItems: SecItemLayer, @unchecked Sendable {
    private let lock = NSLock()
    var legacy: [String: Data] = [:]
    var protected: [String: Data] = [:]
    /// `SecItemAdd` into the data-protection keychain fails (a Developer ID app without an application identifier: -34018).
    var protectedAddStatus: OSStatus = errSecSuccess
    /// What reading the legacy item answers instead of the data (the user pressed Deny, the keychain is locked, ...).
    var legacyReadStatus: OSStatus = errSecSuccess
    private(set) var legacyReads = 0
    private(set) var legacyDeletes = 0

    private func key(_ q: [String: Any]) -> String { "\(q[kSecAttrService as String] as? String ?? "")/\(q[kSecAttrAccount as String] as? String ?? "")" }
    private func isProtected(_ q: [String: Any]) -> Bool { (q[kSecUseDataProtectionKeychain as String] as? Bool) == true }

    func add(_ a: [String: Any]) -> OSStatus {
        lock.lock(); defer { lock.unlock() }
        guard isProtected(a) else { legacy[key(a)] = a[kSecValueData as String] as? Data; return errSecSuccess }
        if protectedAddStatus != errSecSuccess { return protectedAddStatus }
        protected[key(a)] = a[kSecValueData as String] as? Data
        return errSecSuccess
    }
    func copy(_ q: [String: Any]) -> (OSStatus, Data?) {
        lock.lock(); defer { lock.unlock() }
        if isProtected(q) { if let d = protected[key(q)] { return (errSecSuccess, d) }; return (errSecItemNotFound, nil) }
        legacyReads += 1
        if legacyReadStatus != errSecSuccess { return (legacyReadStatus, nil) }
        if let d = legacy[key(q)] { return (errSecSuccess, d) }
        return (errSecItemNotFound, nil)
    }
    func delete(_ q: [String: Any]) -> OSStatus {
        lock.lock(); defer { lock.unlock() }
        if isProtected(q) { return protected.removeValue(forKey: key(q)) == nil ? errSecItemNotFound : errSecSuccess }
        legacyDeletes += 1
        return legacy.removeValue(forKey: key(q)) == nil ? errSecItemNotFound : errSecSuccess
    }
}

final class SecretVaultTests: XCTestCase {
    private var dir: URL!
    override func setUp() { dir = FileManager.default.temporaryDirectory.appendingPathComponent("herald-vault-\(UUID().uuidString)") }
    override func tearDown() { try? FileManager.default.removeItem(at: dir) }

    private func vault(_ layer: FakeSecItems, directory: URL? = nil) -> SecretVault {
        SecretVault(service: "com.ivg.herald.test", account: "tok", directory: directory ?? dir, layer: layer)
    }
    private let k = "com.ivg.herald.test/tok"

    func testSavesToTheDataProtectionKeychainAndNeverTouchesTheLegacyOne() {
        let l = FakeSecItems()
        let v = vault(l)
        XCTAssertTrue(v.save("secret"))
        XCTAssertEqual(l.protected[k], Data("secret".utf8))
        XCTAssertTrue(l.legacy.isEmpty)
        XCTAssertEqual(v.load(), "secret")
        XCTAssertEqual(l.legacyReads, 0, "a stored secret never reads the legacy item")
        v.delete()
        XCTAssertNil(l.protected[k])
        XCTAssertEqual(l.legacyDeletes, 0, "delete does not touch the legacy item (that can prompt)")
    }

    func testWithoutTheEntitlementTheSecretLivesInAPrivateFile() throws {
        let l = FakeSecItems()
        l.protectedAddStatus = -34018   // errSecMissingEntitlement
        let v = vault(l)
        XCTAssertTrue(v.save("secret"))
        XCTAssertTrue(l.protected.isEmpty)
        let file = dir.appendingPathComponent("secrets/com.ivg.herald.test.tok")
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "secret")
        let mode = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? Int
        XCTAssertEqual(mode, 0o600)
        XCTAssertEqual(vault(l).load(), "secret", "a new launch finds it")
        v.delete()
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        XCTAssertNil(vault(l).load())
    }

    func testSaveWithoutAFolderAndWithoutTheEntitlementFailsHonestly() {
        let l = FakeSecItems()
        l.protectedAddStatus = -34018
        XCTAssertFalse(SecretVault(service: "s", account: "a", directory: nil, layer: l).save("x"))
    }

    func testMigratesTheLegacyItemOnceAndDeletesIt() {
        let l = FakeSecItems()
        l.legacy[k] = Data("old".utf8)
        let v = vault(l)
        XCTAssertEqual(v.load(), "old")
        XCTAssertEqual(l.protected[k], Data("old".utf8), "copied into the new store")
        XCTAssertNil(l.legacy[k], "and removed from the old one")
        XCTAssertEqual(l.legacyReads, 1)
        XCTAssertEqual(vault(l).load(), "old")
        XCTAssertEqual(l.legacyReads, 1, "found in the new store: the legacy item is not read again")
    }

    func testMigrationWithoutTheEntitlementLandsInTheFile() {
        let l = FakeSecItems()
        l.protectedAddStatus = -34018
        l.legacy[k] = Data("old".utf8)
        XCTAssertEqual(vault(l).load(), "old")
        XCTAssertNil(l.legacy[k])
        XCTAssertEqual(vault(l).load(), "old")
        XCTAssertEqual(l.legacyReads, 1)
    }

    func testNothingToMigrateIsNotFoundAndNotRetried() {
        let l = FakeSecItems()
        let v = vault(l)
        XCTAssertNil(v.load())
        XCTAssertNil(v.load())
        XCTAssertNil(vault(l).load(), "a new launch has the marker file: still no second read")
        XCTAssertEqual(l.legacyReads, 1)
    }

    func testDeniedPromptsAreNotFoundNeverBlockedNeverLooped() {
        for status in [errSecAuthFailed, errSecInteractionNotAllowed, errSecUserCanceled, errSecNotAvailable, errSecDecode] {
            let l = FakeSecItems()
            l.legacy[k] = Data("old".utf8)
            l.legacyReadStatus = status
            let d = FileManager.default.temporaryDirectory.appendingPathComponent("herald-vault-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: d) }
            let v = vault(l, directory: d)
            XCTAssertNil(v.load(), "status \(status)")
            for _ in 0..<5 { XCTAssertNil(v.load()) }
            XCTAssertNil(vault(l, directory: d).load(), "even a new launch does not ask again")
            XCTAssertEqual(l.legacyReads, 1, "status \(status): one read in total")
            XCTAssertNotNil(l.legacy[k], "the legacy item is left alone when it could not be read")
            // the user can still pair again: a fresh save works and is found
            XCTAssertTrue(v.save("new"))
            XCTAssertEqual(vault(l, directory: d).load(), "new")
        }
    }

    func testAMemoryOnlyVaultAlsoReadsTheLegacyItemOnlyOnce() {
        let l = FakeSecItems()
        l.legacyReadStatus = errSecAuthFailed
        let v = SecretVault(service: "s", account: "a", directory: nil, layer: l)
        for _ in 0..<4 { XCTAssertNil(v.load()) }
        XCTAssertEqual(l.legacyReads, 1)
    }

    func testTheTokenStoreAndCloudflareSecretsUseTheVault() {
        let l = FakeSecItems()
        let t = KeychainTokenStore(service: "svc", directory: dir, layer: l)
        XCTAssertTrue(t.save("hrd_x"))
        XCTAssertEqual(l.protected["svc/relay-device-token"], Data("hrd_x".utf8))
        XCTAssertEqual(t.load(), "hrd_x")
        t.delete()
        XCTAssertNil(l.protected["svc/relay-device-token"])
        let c = KeychainCloudflareSecrets(service: "cf", directory: dir, layer: l)
        XCTAssertTrue(c.set(.apiToken, "tok"))
        XCTAssertEqual(l.protected["cf/cloudflare-api-token"], Data("tok".utf8))
        XCTAssertEqual(c.get(.apiToken), "tok")
        c.remove(.apiToken)
        XCTAssertNil(c.get(.apiToken))
    }
}
