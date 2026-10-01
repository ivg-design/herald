import Foundation

public enum TokenStore {
    /// Reads the token, creating a new 256-bit hex token (mode 0600) on first use.
    @discardableResult
    public static func loadOrCreate(in dir: URL) throws -> String {
        try ensureDirectory(dir)
        let url = HeraldPaths.tokenURL(in: dir)
        if let existing = HeraldPaths.readToken(in: dir) {
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            return existing
        }
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw CocoaError(.fileWriteUnknown)
        }
        let token = bytes.map { String(format: "%02x", $0) }.joined()
        try writePrivate(token, to: url)
        return token
    }

    public static func writePort(_ port: Int, in dir: URL) throws {
        try ensureDirectory(dir)
        try writePrivate(String(port), to: HeraldPaths.portURL(in: dir), mode: 0o644)
    }

    static func ensureDirectory(_ dir: URL) throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
    }

    private static func writePrivate(_ s: String, to url: URL, mode: Int = 0o600) throws {
        // Create with the final mode up front so the secret is never world-readable.
        let fd = open(url.path, O_WRONLY | O_CREAT | O_TRUNC, mode_t(mode))
        guard fd >= 0 else { throw CocoaError(.fileWriteNoPermission) }
        defer { close(fd) }
        fchmod(fd, mode_t(mode))
        let data = Data(s.utf8)
        let n = data.withUnsafeBytes { write(fd, $0.baseAddress, data.count) }
        guard n == data.count else { throw CocoaError(.fileWriteUnknown) }
    }
}
