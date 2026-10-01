import AppKit

/// The connected displays as banners see them (issue #28). A display is named by the number macOS gives it
/// (`NSScreenNumber`, the `CGDirectDisplayID`) as a string; `BannerDisplay.main` is the primary display, the one
/// with the menu bar, which is `NSScreen.screens.first`. (`NSScreen.main` is the display of the key window and
/// moves around, so it is never used.)
enum BannerDisplays {
    static func id(of screen: NSScreen) -> String? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber).map { String($0.uint32Value) }
    }

    /// The ids of the connected displays, primary first.
    static var connectedIDs: [String] { NSScreen.screens.compactMap(id(of:)) }

    /// The display a choice stands for right now (the primary one when that display is not connected).
    static func screen(for choice: String?) -> NSScreen? {
        let resolved = BannerDisplay.resolve(choice, connected: connectedIDs)
        return NSScreen.screens.first { id(of: $0) == resolved } ?? NSScreen.screens.first
    }

    /// The area banners may use on that display (below the menu bar, clear of the Dock).
    static func visibleFrame(of choice: String?) -> NSRect {
        screen(for: choice)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
    }

    /// Just right of every display, where a banner is parked (invisible) while SwiftUI measures it.
    static var parkingX: CGFloat { (NSScreen.screens.map { $0.frame.maxX }.max() ?? 1440) + 40 }

    struct Choice: Identifiable, Equatable {
        let id: String
        let name: String
    }

    /// What the per-app picker offers: the primary display, then every display by name. A saved choice whose
    /// display is not connected is listed as such, so the picker still shows what is stored.
    static func choices(including saved: String? = nil) -> [Choice] {
        var out = [Choice(id: BannerDisplay.main, name: "Main display")]
        for s in NSScreen.screens {
            guard let i = id(of: s) else { continue }
            out.append(Choice(id: i, name: s.localizedName))
        }
        if let saved, saved != BannerDisplay.main, !out.contains(where: { $0.id == saved }) {
            out.append(Choice(id: saved, name: "Display not connected"))
        }
        return out
    }
}
