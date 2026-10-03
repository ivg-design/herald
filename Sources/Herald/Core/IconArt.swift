import AppKit
import UniformTypeIdentifiers

/// Rendering and checking of the icons Herald keeps as PNG files: Herald's own app icon, and the SF Symbol tiles that stand in for
/// an app with no icon of its own. Everything goes through one 256 px bitmap so two images can be compared pixel for pixel.
public enum IconArt {
    public static let side = 256
    /// Herald's accent: the blue of its app icon.
    public static let accent = NSColor(srgbRed: 0.18, green: 0.49, blue: 0.96, alpha: 1)

    /// `image` drawn into a `side` x `side` RGBA bitmap, centred and scaled to fit.
    public static func bitmap(of image: NSImage, side: Int = IconArt.side) -> NSBitmapImageRep? {
        guard image.size.width > 0, image.size.height > 0,
              let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8, samplesPerPixel: 4,
                                         hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        if let data = rep.bitmapData { memset(data, 0, rep.bytesPerRow * rep.pixelsHigh) }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx
        let s = CGFloat(side) / max(image.size.width, image.size.height)
        let w = image.size.width * s, h = image.size.height * s
        image.draw(in: NSRect(x: (CGFloat(side) - w) / 2, y: (CGFloat(side) - h) / 2, width: w, height: h),
                   from: .zero, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }

    public static func png(of image: NSImage, side: Int = IconArt.side) -> Data? {
        bitmap(of: image, side: side)?.representation(using: .png, properties: [:])
    }

    /// The share of pixels that are visible (alpha above 6 %). A blank or fully transparent export is near 0.
    public static func opaqueFraction(of png: Data) -> Double {
        guard let image = NSImage(data: png), let rep = bitmap(of: image), let px = rep.bitmapData else { return 0 }
        var seen = 0
        let total = rep.pixelsWide * rep.pixelsHigh
        for i in 0..<total where px[rep.bytesPerRow * (i / rep.pixelsWide) + 4 * (i % rep.pixelsWide) + 3] > 16 { seen += 1 }
        return Double(seen) / Double(max(total, 1))
    }

    /// What macOS draws for an application with no icon: the grey rounded square with the guide lines.
    public static func genericApplicationPNG() -> Data? {
        png(of: NSWorkspace.shared.icon(for: .applicationBundle))
    }

    /// True when `png` is (to the eye) macOS's generic application icon.
    public static func isGenericApplicationIcon(_ png: Data) -> Bool {
        guard let generic = genericApplicationPNG(), let a = pixels(generic), let b = pixels(png), a.count == b.count else { return false }
        var diff = 0
        for i in 0..<a.count { diff += abs(Int(a[i]) - Int(b[i])) }
        return Double(diff) / Double(a.count) < 3
    }

    private static func pixels(_ png: Data) -> [UInt8]? {
        guard let image = NSImage(data: png), let rep = bitmap(of: image), let px = rep.bitmapData else { return nil }
        return Array(UnsafeBufferPointer(start: px, count: rep.bytesPerRow * rep.pixelsHigh))
    }

    /// A real app icon: an image, at least 30 % visible, and not the system placeholder.
    public static func isUsableAppIcon(_ png: Data) -> Bool {
        NSImage(data: png) != nil && opaqueFraction(of: png) >= 0.30 && !isGenericApplicationIcon(png)
    }

    /// Herald's own icon as a 256 px PNG. The candidates are tried in order and the first usable one wins: the bundle's
    /// `AppIcon.icns`, the catalog image, the image by name, what Finder draws for the bundle, the running app's icon. A candidate
    /// that is the system placeholder, empty or mostly transparent is skipped, so the export never stores a blank tile.
    public static func appIconPNG(bundle: Bundle = .main, candidates: [() -> NSImage?]? = nil) -> Data? {
        let list: [() -> NSImage?] = candidates ?? [
            { bundle.url(forResource: "AppIcon", withExtension: "icns").flatMap { NSImage(contentsOf: $0) } },
            { bundle.image(forResource: "AppIcon") },
            { NSImage(named: "AppIcon") },
            { NSWorkspace.shared.icon(forFile: bundle.bundlePath) },
            { NSApp?.applicationIconImage },
        ]
        for make in list {
            if let image = make(), let png = png(of: image), isUsableAppIcon(png) { return png }
        }
        return nil
    }

    /// An SF Symbol, white, on a rounded square in Herald's accent, as a 256 px PNG.
    public static func symbolTilePNG(symbol: String, color: NSColor = IconArt.accent) -> Data? {
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8, samplesPerPixel: 4,
                                         hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        if let data = rep.bitmapData { memset(data, 0, rep.bytesPerRow * rep.pixelsHigh) }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx
        let full = NSRect(x: 0, y: 0, width: side, height: side)
        let body = full.insetBy(dx: 16, dy: 16)
        let top = color.blended(withFraction: 0.25, of: .white) ?? color
        NSGradient(starting: top, ending: color)?.draw(in: NSBezierPath(roundedRect: body, xRadius: 52, yRadius: 52), angle: -90)
        let config = NSImage.SymbolConfiguration(pointSize: 110, weight: .semibold).applying(.init(paletteColors: [.white]))
        if let sym = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?.withSymbolConfiguration(config) {
            let s = min(body.width * 0.58 / sym.size.width, body.height * 0.58 / sym.size.height)
            let w = sym.size.width * s, h = sym.size.height * s
            sym.draw(in: NSRect(x: full.midX - w / 2, y: full.midY - h / 2, width: w, height: h), from: .zero, operation: .sourceOver, fraction: 1)
        }
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }
}
