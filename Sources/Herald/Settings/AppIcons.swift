import AppKit

@MainActor
enum AppIcons {
    private static var cache: [String: NSImage] = [:]

    static func invalidate() { cache.removeAll() }

    static func icon(for record: AppRecord?, app: String) -> NSImage {
        if let c = cache[app] { return c }
        let img = load(record) ?? generic(app)
        cache[app] = img
        return img
    }

    private static func load(_ record: AppRecord?) -> NSImage? {
        guard let reg = record?.registration else { return nil }
        if let icon = reg.icon {
            if icon.hasPrefix("data:"), let comma = icon.firstIndex(of: ","),
               let data = Data(base64Encoded: String(icon[icon.index(after: comma)...]), options: .ignoreUnknownCharacters),
               let img = NSImage(data: data) { return img }
            if let img = NSImage(contentsOfFile: (icon as NSString).expandingTildeInPath) { return img }
        }
        if let bid = reg.bundleId, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bid) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return nil
    }

    /// Rounded letter tile used when an app has no icon.
    private static func generic(_ app: String) -> NSImage {
        let size = NSSize(width: 64, height: 64)
        let letter = String(app.first.map { Character($0.uppercased()) } ?? "?")
        let hue = CGFloat(abs(app.hashValue % 360)) / 360
        return NSImage(size: size, flipped: false) { rect in
            NSColor(hue: hue, saturation: 0.5, brightness: 0.75, alpha: 1).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 14, yRadius: 14).fill()
            let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 34, weight: .semibold),
                                                        .foregroundColor: NSColor.white]
            let s = NSAttributedString(string: letter, attributes: attrs)
            let sz = s.size()
            s.draw(at: NSPoint(x: rect.midX - sz.width / 2, y: rect.midY - sz.height / 2))
            return true
        }
    }
}
