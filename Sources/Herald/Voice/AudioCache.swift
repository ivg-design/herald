import Foundation

/// Recognises the audio formats Herald will play, from the bytes alone (the extension never comes from the sender).
public enum AudioSniffer {
    public static func fileExtension(for data: Data) -> String? {
        let b = [UInt8](data.prefix(16))
        func starts(_ s: String, at o: Int = 0) -> Bool {
            let sig = Array(s.utf8)
            return b.count >= o + sig.count && Array(b[o..<(o + sig.count)]) == sig
        }
        if starts("RIFF") && starts("WAVE", at: 8) { return "wav" }
        if starts("ID3") { return "mp3" }
        if b.count >= 2, b[0] == 0xFF, b[1] & 0xE0 == 0xE0 { return "mp3" }   // MPEG frame sync
        if starts("ftyp", at: 4) { return "m4a" }
        if starts("FORM") && (starts("AIFF", at: 8) || starts("AIFC", at: 8)) { return "aiff" }
        if starts("caff") { return "caf" }
        return nil
    }
}

/// Caches a notification's `audio` (path, `data:` URI or https URL) under `history/audio/`, content-addressed,
/// at most `maxBytes`, and only when the bytes are a known audio format.
public struct AudioCache: Sendable {
    public static let maxBytes = 20 * 1024 * 1024
    public let directory: URL
    public init(directory: URL) { self.directory = directory }

    public func cache(_ spec: String) async -> URL? {
        guard let data = await load(spec), data.count <= Self.maxBytes,
              let ext = AudioSniffer.fileExtension(for: data) else { return nil }
        return store(data, ext: ext)
    }

    public func load(_ spec: String) async -> Data? {
        if spec.hasPrefix("data:") {
            guard let comma = spec.firstIndex(of: ","), spec[..<comma].contains(";base64"),
                  let data = Data(base64Encoded: String(spec[spec.index(after: comma)...]), options: .ignoreUnknownCharacters)
            else { return nil }
            return data
        }
        if spec.hasPrefix("http://") || spec.hasPrefix("https://") {
            guard let url = URL(string: spec) else { return nil }
            var req = URLRequest(url: url)
            req.timeoutInterval = 20
            guard let (data, resp) = try? await URLSession.shared.data(for: req),
                  (resp as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            return data
        }
        let path = (spec as NSString).expandingTildeInPath
        let size = (try? FileManager.default.attributesOfItem(atPath: path))?[.size] as? NSNumber
        guard let size, size.intValue <= Self.maxBytes else { return nil }
        return try? Data(contentsOf: URL(fileURLWithPath: path))
    }

    /// A new file name for audio Herald synthesizes itself (the worker writes it).
    public func newSpeechURL() -> URL {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("speech-\(UUID().uuidString).wav")
    }

    /// Keeps the newest `keep` files; speech is cheap to re-synthesize from the history text.
    public func prune(keep: Int = 300) {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey]),
              files.count > keep else { return }
        let dated = files.map { ($0, (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) }
        for (url, _) in dated.sorted(by: { $0.1 > $1.1 }).dropFirst(keep) { try? fm.removeItem(at: url) }
    }

    private func store(_ data: Data, ext: String) -> URL? {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // Content-addressed by a cheap stable hash so the same message is stored once.
        var h: UInt64 = 1469598103934665603
        for byte in data { h = (h ^ UInt64(byte)) &* 1099511628211 }
        let url = directory.appendingPathComponent(String(format: "audio-%016llx-%d.%@", h, data.count, ext))
        if !FileManager.default.fileExists(atPath: url.path) {
            do { try data.write(to: url, options: .atomic) } catch { return nil }
        }
        return url
    }
}
