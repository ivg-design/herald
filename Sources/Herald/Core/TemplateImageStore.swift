import Foundation
import CryptoKit
import ImageIO
import HeraldClient

/// Where an Image component gets its picture, as the Designer's Source control puts it. On the wire it is only the
/// component's `binding`, so a template written by hand and one made in the Designer are the same thing.
public enum ImageSourceChoice: Equatable, Sendable {
    /// `{image}`: the image the sending app attached to its notification.
    case issuer
    /// `{key}`: another field (of type image) the manifest declares, or one a notification carries.
    case field(String)
    /// A picture chosen in the Designer and kept in Herald's support folder (a path, a `file:` URL or a data URI):
    /// it is the same for every notification and overrides the issuer's.
    case fixed(String)
    /// Anything else: text mixing tokens, edited by hand.
    case custom(String)

    public static let issuerBinding = "{image}"

    public static func classify(_ binding: String) -> ImageSourceChoice {
        let b = binding.trimmingCharacters(in: .whitespacesAndNewlines)
        if b.isEmpty || b == issuerBinding { return .issuer }
        if b.hasPrefix("{"), b.hasSuffix("}"), !b.dropFirst().dropLast().contains(where: { "{}".contains($0) }) {
            return .field(String(b.dropFirst().dropLast()))
        }
        if !b.contains("{") { return .fixed(b) }
        return .custom(b)
    }

    /// The binding text for each choice.
    public var binding: String {
        switch self {
        case .issuer: return Self.issuerBinding
        case .field(let k): return "{\(k)}"
        case .fixed(let p), .custom(let p): return p
        }
    }
}

public struct TemplateImageError: Error, LocalizedError, Equatable, Sendable {
    public var message: String
    public var errorDescription: String? { message }
}

/// Pictures a template carries itself (the Image component's "Fixed image"), copied into
/// `~/Library/Application Support/Herald/template-images/<app>/` so the template keeps working when the original
/// file moves. The copy's name carries a short hash of its content: choosing the same file twice makes one copy,
/// and a changed file never overwrites what other templates already point at.
public struct TemplateImageStore: Sendable {
    public static let maxBytes = 10 * 1024 * 1024
    public static let allowedExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "heic", "avif", "tif", "tiff", "bmp"]

    public static let shared = TemplateImageStore(
        directory: HeraldPaths.defaultSupportDirectory.appendingPathComponent("template-images", isDirectory: true))

    public let directory: URL
    public init(directory: URL) { self.directory = directory }

    public func folder(for app: String) -> URL {
        directory.appendingPathComponent(TemplateStore.component(app), isDirectory: true)
    }

    /// True when `path` (or a `file:` URL) points inside the store.
    public func contains(_ path: String) -> Bool {
        let url = path.hasPrefix("file:") ? URL(string: path) : URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        guard let p = url?.standardizedFileURL.resolvingSymlinksInPath().path else { return false }
        return p.hasPrefix(directory.standardizedFileURL.resolvingSymlinksInPath().path + "/")
    }

    /// Copies `source` into the app's folder and returns the copy. Throws when it is not a picture Herald can draw
    /// (by extension, size and what ImageIO can read).
    @discardableResult
    public func install(_ source: URL, app: String) throws -> URL {
        let src = source.resolvingSymlinksInPath()
        let ext = src.pathExtension.lowercased()
        guard Self.allowedExtensions.contains(ext) else {
            throw TemplateImageError(message: "\u{201C}\(src.lastPathComponent)\u{201D} is not a picture Herald can show (PNG, JPEG, GIF, WebP, HEIC, AVIF, TIFF or BMP).")
        }
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: src.path),
              (attrs[.type] as? FileAttributeType) == .typeRegular,
              let size = (attrs[.size] as? NSNumber)?.intValue, size > 0 else {
            throw TemplateImageError(message: "\u{201C}\(src.lastPathComponent)\u{201D} is not a readable file.")
        }
        guard size <= Self.maxBytes else {
            throw TemplateImageError(message: "\u{201C}\(src.lastPathComponent)\u{201D} is over 10 MB.")
        }
        let data = try Data(contentsOf: src)
        guard let image = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(image) > 0 else {
            throw TemplateImageError(message: "\u{201C}\(src.lastPathComponent)\u{201D} does not contain a picture.")
        }
        let hash = SHA256.hash(data: data).prefix(4).map { String(format: "%02x", $0) }.joined()
        let stem = TemplateStore.component(src.deletingPathExtension().lastPathComponent)
        let dest = folder(for: app).appendingPathComponent("\(stem)-\(hash).\(ext)")
        if !FileManager.default.fileExists(atPath: dest.path) {
            try FileManager.default.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: dest, options: .atomic)
        }
        return dest
    }
}
