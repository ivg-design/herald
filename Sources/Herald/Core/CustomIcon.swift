import AppKit
import Foundation

/// The icon a user picks for an app in Settings > Apps (issue #86): the picture is kept as a 256 px PNG under the support folder's
/// `app-icons`, and the app's record points at it. Removing it goes back to the app's own or the automatic icon.
public enum CustomIcon {
    public static func folder(in support: URL) -> URL { support.appendingPathComponent("app-icons", isDirectory: true) }

    static func file(for app: String, in support: URL) -> URL {
        let safe = String(app.map { $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" || $0 == "_" ? $0 : "_" })
        return folder(in: support).appendingPathComponent(safe + ".png")
    }

    public enum Failure: Error, Equatable { case notAnImage, noSuchApp, cannotWrite }

    /// Sets the icon of a registered app from an image file. The file is converted to PNG (so it can be moved or deleted after).
    @discardableResult
    public static func set(app: String, from source: URL, supportDirectory: URL, registry: AppRegistry) throws -> URL {
        guard registry.record(for: app) != nil else { throw Failure.noSuchApp }
        guard let image = NSImage(contentsOf: source), let png = IconArt.png(of: image) else { throw Failure.notAnImage }
        let dest = file(for: app, in: supportDirectory)
        do {
            try FileManager.default.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
            try png.write(to: dest, options: .atomic)
        } catch { throw Failure.cannotWrite }
        registry.update(app) { $0.customIcon = dest.path }
        return dest
    }

    /// Back to the automatic icon: forgets the choice and deletes the file Herald made for it.
    public static func remove(app: String, supportDirectory: URL, registry: AppRegistry) {
        guard let path = registry.record(for: app)?.customIcon else { return }
        registry.update(app) { $0.customIcon = nil }
        if path.hasPrefix(folder(in: supportDirectory).path) { try? FileManager.default.removeItem(atPath: path) }
    }
}
