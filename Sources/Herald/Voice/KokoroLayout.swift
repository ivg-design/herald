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
