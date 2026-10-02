import AppKit
import Foundation

/// The `icon` a cloud notification may carry: an https image or a small `data:` image, turned into a PNG for the sender's issuer.
/// The picture is only ever decoded as an image (no file path, no scheme but https and data), capped at 256 KB, and kept as
/// `<support>/agent-icons/<slug>.custom.png` so a restart does not lose it.
enum RelayIcon {
    static let maxBytes = 256 * 1024

    /// The image bytes behind `source`, or nil. https is fetched once with a short timeout.
    static func bytes(from source: String) async -> Data? {
        if source.hasPrefix("data:image/") {
            guard let comma = source.firstIndex(of: ","), source[..<comma].hasSuffix(";base64"),
                  let d = Data(base64Encoded: String(source[source.index(after: comma)...])), d.count <= maxBytes else { return nil }
            return d
        }
        guard let url = URL(string: source), url.scheme == "https" else { return nil }
        var req = URLRequest(url: url, timeoutInterval: 6)
        req.httpShouldHandleCookies = false
        guard let (d, resp) = try? await URLSession.shared.data(for: req), (resp as? HTTPURLResponse)?.statusCode == 200, d.count <= maxBytes else { return nil }
        return d
    }

    /// A square PNG of at most 256 px, or nil when the bytes are not an image.
    static func png(from data: Data) -> Data? {
        guard let image = NSImage(data: data), image.size.width > 0, image.size.height > 0,
              let rep = NSBitmapImageRep(data: data) ?? image.tiffRepresentation.flatMap({ NSBitmapImageRep(data: $0) }) else { return nil }
        let side = min(256, max(rep.pixelsWide, rep.pixelsHigh))
        let out = NSImage(size: NSSize(width: side, height: side))
        out.lockFocus()
        let scale = CGFloat(side) / max(image.size.width, image.size.height)
        let w = image.size.width * scale, h = image.size.height * scale
        image.draw(in: NSRect(x: (CGFloat(side) - w) / 2, y: (CGFloat(side) - h) / 2, width: w, height: h))
        out.unlockFocus()
        guard let tiff = out.tiffRepresentation, let r = NSBitmapImageRep(data: tiff) else { return nil }
        return r.representation(using: .png, properties: [:])
    }

    static func customFile(slug: String, folder: URL) -> URL { folder.appendingPathComponent(slug + ".custom.png") }
}
