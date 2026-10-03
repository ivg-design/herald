import AppKit

@MainActor
enum AppIcons {
    private static var cache: [String: NSImage] = [:]

    static func invalidate() { cache.removeAll() }

    /// The icon every list draws for `app`: Apps, History, banners and the preview all come through here, from the registry.
    static func icon(in registry: AppRegistry, app: String) -> NSImage { icon(for: registry.record(for: app), app: app) }

    static func icon(for record: AppRecord?, app: String) -> NSImage {
        if let c = cache[app] { return c }
        let img = load(record) ?? generic(app)
        cache[app] = img
        return img
    }

    private static func load(_ record: AppRecord?) -> NSImage? {
        guard let reg = record?.registration else { return nil }
        // The user's own choice wins, then the app's registered (or automatic) icon, then its application's icon.
        if let custom = record?.customIcon, let img = NSImage(contentsOfFile: custom) { return img }
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

    /// An app with nothing else gets a bell tile (an SF Symbol on Herald's accent), never a bare letter.
    private static func generic(_ app: String) -> NSImage {
        if let png = IconArt.symbolTilePNG(symbol: "bell.fill"), let img = NSImage(data: png) { return img }
        return NSImage(size: NSSize(width: 64, height: 64))
    }
}
