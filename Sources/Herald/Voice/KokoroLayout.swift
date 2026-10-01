import Foundation
import CryptoKit

/// Where Kokoro lives: `<support>/tts/{venv, kokoro-v1.0.onnx, voices-v1.0.bin}`, the same layout as the
/// user's `~/.claude/tts`, so "use existing installation" is three symlinks.
public struct KokoroLayout: Equatable, Sendable {
    public static let modelFile = "kokoro-v1.0.onnx"
    public static let voicesFile = "voices-v1.0.bin"
    public static let releaseBase = "https://github.com/thewh1teagle/kokoro-onnx/releases/download/model-files-v1.0/"

    public let root: URL
    public init(root: URL) { self.root = root }
    public init(supportDirectory: URL) { self.root = supportDirectory.appendingPathComponent("tts", isDirectory: true) }

    public var model: URL { root.appendingPathComponent(Self.modelFile) }
    public var voices: URL { root.appendingPathComponent(Self.voicesFile) }
    public var venv: URL { root.appendingPathComponent("venv", isDirectory: true) }
    public var python: URL { venv.appendingPathComponent("bin/python") }

    private func exists(_ u: URL) -> Bool { FileManager.default.fileExists(atPath: u.path) }
    public var hasModels: Bool { exists(model) && exists(voices) }
    public var hasPython: Bool { FileManager.default.isExecutableFile(atPath: python.path) }
    /// Written inside a venv Herald built itself once its packages were installed and imported cleanly.
    public var environmentMarker: URL { venv.appendingPathComponent(".herald-env-ready") }
    /// True for a venv that is a symlink (a linked existing installation, which is the user's own).
    public var venvIsLinked: Bool { (try? FileManager.default.destinationOfSymbolicLink(atPath: venv.path)) != nil }
    /// A venv Herald built itself that never finished (quit or crash between creating it and installing the
    /// packages): it has a python, but no marker. The installer rebuilds it instead of trusting it.
    public var environmentIncomplete: Bool { hasPython && !venvIsLinked && !exists(environmentMarker) }
    public var isInstalled: Bool { hasModels && hasPython }

    /// What is missing, for the Settings pane.
    public var missing: [String] {
        var m: [String] = []
        if !exists(model) { m.append(Self.modelFile) }
        if !exists(voices) { m.append(Self.voicesFile) }
        if !hasPython { m.append("Python environment") }
        return m
    }

    /// `~/.claude/tts` when it holds a complete installation, else nil.
    public static func existingInstallation(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> KokoroLayout? {
        let l = KokoroLayout(root: home.appendingPathComponent(".claude/tts", isDirectory: true))
        return l.isInstalled ? l : nil
    }

    /// Points this layout at another installation by symlinking its model, voices and venv (nothing is copied or
    /// modified in the source). An existing entry here is replaced only if it is itself a symlink or absent.
    public func link(to source: KokoroLayout) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        for (dest, src) in [(model, source.model), (voices, source.voices), (venv, source.venv)] {
            if (try? fm.destinationOfSymbolicLink(atPath: dest.path)) != nil { try fm.removeItem(at: dest) }
            else if fm.fileExists(atPath: dest.path) { continue }   // a real file/dir of our own stays
            try fm.createSymbolicLink(at: dest, withDestinationURL: src)
        }
    }

    /// Streams the file through SHA-256 (the model is ~300 MB).
    public static func sha256(of url: URL) throws -> String {
        let h = try FileHandle(forReadingFrom: url)
        defer { try? h.close() }
        var hasher = SHA256()
        while let chunk = try h.read(upToCount: 4 * 1024 * 1024), !chunk.isEmpty { hasher.update(data: chunk) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

/// What the server's answer to a `Range: bytes=N-` request means for a download that continues from bytes already
/// on disk. Pure, so the resume rules are unit tested; `ResumableDownloader` acts on the decision.
public enum DownloadResume {
    public enum Decision: Equatable, Sendable {
        /// 206: the server continues from the offset; `total` is the whole file's size (0 when unknown).
        case resume(total: Int64)
        /// 200: the server ignored the range (or there was nothing to resume): start over.
        case restart(total: Int64)
        /// 416 and the bytes on disk are the whole file.
        case alreadyComplete
        /// 416 and the bytes on disk are more than the file has: they are not a prefix of it, so they are discarded.
        case discardPart
        /// Anything else is an error.
        case fail(Int)
    }

    public static func rangeHeader(have: Int64) -> String? { have > 0 ? "bytes=\(have)-" : nil }

    /// The total size in `Content-Range` ("bytes 100-299/300" or, on a 416, "bytes */300"); nil when absent or "*".
    public static func total(fromContentRange header: String?) -> Int64? {
        guard let header, let slash = header.lastIndex(of: "/") else { return nil }
        return Int64(header[header.index(after: slash)...].trimmingCharacters(in: .whitespaces))
    }

    public static func decide(status: Int, have: Int64, contentLength: Int64, contentRange: String?) -> Decision {
        switch status {
        case 206:
            let total = total(fromContentRange: contentRange) ?? (contentLength >= 0 ? have + contentLength : 0)
            return .resume(total: total)
        case 200:
            return .restart(total: max(contentLength, 0))
        case 416:
            // Without a total to compare with, the old assumption stands: a range the server cannot satisfy
            // means the file is already complete.
            guard let total = total(fromContentRange: contentRange) else { return .alreadyComplete }
            return have == total ? .alreadyComplete : .discardPart
        default:
            return .fail(status)
        }
    }
}
