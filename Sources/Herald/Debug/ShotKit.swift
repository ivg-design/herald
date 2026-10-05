#if DEBUG
import SwiftUI
import AppKit
import CoreGraphics
import ObjectiveC

/// Offscreen placement and capture for the documentation screenshots (`ScreenshotMode`). Nothing here ever shows a window
/// on a display, activates the app or makes a window key.
///
/// Placement: a window is given alpha 0 and its origin far outside every display, ordered in without activating, moved
/// again (ordering in may let AppKit constrain it), and only then made opaque. `place` refuses (and orders the window out
/// again) if it still touches a display, so a failure shows up as a missing shot, never as a window on the owner's screen.
///
/// Capture, in this order, the first that yields a correct image being kept for the rest of the run:
///  1. `screencapture -l <windowNumber> -o -x` (needs Screen Recording permission for the launching process);
///  2. `CGWindowListCreateImage(.null, .optionIncludingWindow, id, [.boundsIgnoreFraming, .bestResolution])`;
///  3. in-process `cacheDisplay(in:to:)` of the window's frame view into a 2x bitmap (needs nothing).
/// An image counts as correct when its size matches the window (2x) and it is not blank (pixel variance).
@MainActor
enum ShotKit {
    static let far = NSPoint(x: -30000, y: -30000)

    enum Method: String, CaseIterable { case screencapture, cgWindow, cacheDisplay }
    /// The first method that has produced a correct image; tried first from then on.
    static var working: Method?
    private static var failedMethods = Set<Method>()

    // MARK: Placement

    static func isOffscreen(_ w: NSWindow) -> Bool {
        !NSScreen.screens.contains { $0.frame.insetBy(dx: -1, dy: -1).intersects(w.frame) }
    }

    /// AppKit pulls a visible window back toward a display (`constrainFrameRect`, also on `setFrameOrigin`). The window gets a runtime
    /// subclass of its own class that returns the frame unchanged, so it can sit far outside every display.
    static func unconstrain(_ w: NSWindow) {
        let base: AnyClass = type(of: w)
        let name = "HeraldShotUnconstrained_" + NSStringFromClass(base).replacingOccurrences(of: ".", with: "_")
        if NSStringFromClass(base) == name { return }
        var cls: AnyClass? = NSClassFromString(name)
        if cls == nil {
            cls = objc_allocateClassPair(base, name, 0)
            let block: @convention(block) (AnyObject, NSRect, AnyObject?) -> NSRect = { _, r, _ in r }
            class_addMethod(cls, NSSelectorFromString("constrainFrameRect:toScreen:"), imp_implementationWithBlock(block),
                            "{CGRect={CGPoint=dd}{CGSize=dd}}@:{CGRect={CGPoint=dd}{CGSize=dd}}@")
            // Reports key and main (title bar and controls draw as active); the window is never really key.
            let yes: @convention(block) (AnyObject) -> Bool = { _ in true }
            for name in ["isKeyWindow", "isMainWindow", "_hasKeyAppearance", "_hasMainAppearance", "_hasActiveControls", "_hasActiveAppearance", "hasKeyAppearance", "_hasActiveAppearanceIgnoringKeyFocus"] {
                class_addMethod(cls, NSSelectorFromString(name), imp_implementationWithBlock(yes), "B@:")
            }
            objc_registerClassPair(cls!)
        }
        if let cls { object_setClass(w, cls) }
    }

    /// Orders `w` in, outside every display, without activating or making it key. False (window ordered out) if it ended up touching a display.
    @discardableResult
    static func place(_ w: NSWindow, size: NSSize? = nil) -> Bool {
        unconstrain(w)
        swizzleAppActive()
        forceActiveLook(w)
        let wasHidden = !w.isVisible
        let alpha = w.alphaValue
        if wasHidden { w.alphaValue = 0 }
        if let size { w.setContentSize(size) }
        // Ordering in lets AppKit pull a window that is outside every display back onto one, so it is ordered in where it is
        // (invisible: alpha 0) and moved away afterwards; setFrameOrigin does not constrain.
        w.orderFrontRegardless()
        if !isOffscreen(w) { w.setFrameOrigin(far) }
        guard isOffscreen(w) else {
            log("screens: " + NSScreen.screens.map { NSStringFromRect($0.frame) }.joined(separator: " "))
            w.orderOut(nil)
            log("REFUSED: \(w.title) would touch a display at \(NSStringFromRect(w.frame)); ordered out")
            return false
        }
        w.alphaValue = wasHidden ? 1 : alpha
        // Tell the views the window is active (it reports key and main, see ShotWindow) so controls and the title bar draw in colour.
        do {
            NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: NSApp)
            NotificationCenter.default.post(name: NSWindow.didBecomeMainNotification, object: w)
            NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: w)
        }
        return true
    }

    /// Puts a window that AppKit moved back toward a display (a sheet, a popover, a resize) outside them again, at once.
    static func keepOffscreen(_ w: NSWindow) {
        if !isOffscreen(w) { w.alphaValue = 0; w.setFrameOrigin(far); w.alphaValue = 1 }
    }

    /// Private switches that make a window's controls draw as active (accent tint) although it is never key.
    static func forceActiveLook(_ w: NSWindow) {
        typealias SetBool = @convention(c) (AnyObject, Selector, Bool) -> Void
        for name in ["_setForceActiveControls:", "_setHasActiveAppearance:"] {
            let sel = Selector(name)
            if w.responds(to: sel), let m = class_getInstanceMethod(NSWindow.self, sel) {
                unsafeBitCast(method_getImplementation(m), to: SetBool.self)(w, sel, true)
            }
        }
    }

    private static var appSwizzled = false
    /// NSApplication.isActive reports true for this process (nothing is activated).
    static func swizzleAppActive() {
        guard !appSwizzled else { return }
        appSwizzled = true
        let yes: @convention(block) (AnyObject) -> Bool = { _ in true }
        if let m = class_getInstanceMethod(NSApplication.self, #selector(getter: NSApplication.isActive)) {
            method_setImplementation(m, imp_implementationWithBlock(yes))
        }
    }

    /// Selected rows of lists and tables draw in the accent colour (emphasised) although the window is never key.
    static func emphasizeRows(_ v: NSView) {
        if let r = v as? NSTableRowView { r.isEmphasized = true }
        for s in v.subviews { emphasizeRows(s) }
    }

    static func log(_ s: String) { FileHandle.standardError.write(Data(("screenshots: " + s + "\n").utf8)) }

    // MARK: Capture

    struct Grab { var image: CGImage; var method: Method }

    /// A correct image of `w` (all of it, frame and title bar included), or nil.
    static func grab(_ w: NSWindow, name: String) async -> Grab? {
        let order = (working.map { [$0] } ?? []) + Method.allCases.filter { $0 != working && !failedMethods.contains($0) }
        if let root = w.contentView?.superview { emphasizeRows(root) }
        let want = CGSize(width: w.frame.width * 2, height: w.frame.height * 2)
        for m in order {
            let img: CGImage?
            switch m {
            case .screencapture: img = await viaScreencapture(w)
            case .cgWindow: img = viaCGWindow(w)
            case .cacheDisplay: img = viaCacheDisplay(w)
            }
            guard let img else { log("\(name): \(m.rawValue) gave nothing"); if working != m { failedMethods.insert(m) }; continue }
            if let why = problem(img, want: want) {
                log("\(name): \(m.rawValue) rejected (\(why))")
                if working != m { failedMethods.insert(m) }
                continue
            }
            working = m
            return Grab(image: img, method: m)
        }
        return nil
    }

    private static func viaScreencapture(_ w: NSWindow) async -> CGImage? {
        let file = NSTemporaryDirectory() + "herald-shot-\(getpid())-\(w.windowNumber).png"
        try? FileManager.default.removeItem(atPath: file)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        p.arguments = ["-l", String(w.windowNumber), "-o", "-x", file]
        p.standardError = FileHandle.nullDevice
        let ok: Bool = await withCheckedContinuation { k in
            p.terminationHandler = { _ in k.resume(returning: true) }
            do { try p.run() } catch { k.resume(returning: false) }
        }
        defer { try? FileManager.default.removeItem(atPath: file) }
        guard ok, let data = try? Data(contentsOf: URL(fileURLWithPath: file)), let rep = NSBitmapImageRep(data: data) else { return nil }
        return rep.cgImage
    }

    private typealias WindowListImage = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?

    private static func viaCGWindow(_ w: NSWindow) -> CGImage? {
        // Looked up by name: the function is unavailable to the compiler on current SDKs but still in CoreGraphics.
        guard let h = dlopen(nil, RTLD_NOW), let sym = dlsym(h, "CGWindowListCreateImage") else { return nil }
        let f = unsafeBitCast(sym, to: WindowListImage.self)
        let optionIncludingWindow: UInt32 = 1 << 3, boundsIgnoreFraming: UInt32 = 1 << 0, bestResolution: UInt32 = 1 << 3
        return f(.null, optionIncludingWindow, UInt32(w.windowNumber), boundsIgnoreFraming | bestResolution)?.takeRetainedValue()
    }

    private static func viaCacheDisplay(_ w: NSWindow) -> CGImage? {
        guard let content = w.contentView else { return nil }
        let view = content.superview ?? content
        let bounds = view.bounds
        guard bounds.width > 1, bounds.height > 1,
              let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(bounds.width * 2), pixelsHigh: Int(bounds.height * 2),
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        rep.size = bounds.size
        view.cacheDisplay(in: bounds, to: rep)
        return rep.cgImage
    }

    /// Why an image is not a correct capture of a window of this size (nil when it is).
    static func problem(_ img: CGImage, want: CGSize) -> String? {
        if abs(CGFloat(img.width) - want.width) > 4 || abs(CGFloat(img.height) - want.height) > 4 {
            return "size \(img.width)x\(img.height), wanted \(Int(want.width))x\(Int(want.height))"
        }
        let stats = pixelStats(img)
        if stats.opaqueFraction < 0.02 { return "fully transparent" }
        if stats.distinctColors < 6 || stats.lumaSpread < 12 { return "blank (\(stats.distinctColors) colours, luma spread \(Int(stats.lumaSpread)))" }
        return nil
    }

    struct Stats { var distinctColors: Int; var lumaSpread: Double; var opaqueFraction: Double }

    static func pixelStats(_ img: CGImage) -> Stats {
        let w = img.width, h = img.height
        guard let px = rgba(img) else { return Stats(distinctColors: 0, lumaSpread: 0, opaqueFraction: 0) }
        var colors = Set<UInt32>(), lo = 255.0, hi = 0.0, opaque = 0, n = 0
        let step = max(1, min(w, h) / 90)
        var y = 0
        while y < h {
            var x = 0
            while x < w {
                let i = (y * w + x) * 4
                let a = Int(px[i + 3]); n += 1
                if a > 8 {
                    opaque += 1
                    let r = Int(px[i]), g = Int(px[i + 1]), b = Int(px[i + 2])
                    colors.insert(UInt32((r >> 3) << 10 | (g >> 3) << 5 | (b >> 3)))
                    let l = 0.299 * Double(r) + 0.587 * Double(g) + 0.114 * Double(b)
                    lo = min(lo, l); hi = max(hi, l)
                }
                x += step
            }
            y += step
        }
        return Stats(distinctColors: colors.count, lumaSpread: hi > lo ? hi - lo : 0, opaqueFraction: n == 0 ? 0 : Double(opaque) / Double(n))
    }

    /// Straight RGBA bytes (premultiplication undone is not needed for statistics).
    static func rgba(_ img: CGImage) -> [UInt8]? {
        let w = img.width, h = img.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let ok = data.withUnsafeMutableBytes { buf -> Bool in
            guard let ctx = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        return ok ? data : nil
    }

    // MARK: Cropping and trimming

    /// `rect` is in points from the window's top-left (the image is 2x).
    static func crop(_ img: CGImage, points rect: CGRect, scale: CGFloat = 2) -> CGImage? {
        let r = CGRect(x: rect.minX * scale, y: rect.minY * scale, width: rect.width * scale, height: rect.height * scale)
            .intersection(CGRect(x: 0, y: 0, width: img.width, height: img.height)).integral
        return img.cropping(to: r)
    }

    /// Cuts the empty background off the bottom of a window image (a Settings window made taller than its tab), keeping `pad` points.
    static func trimBottom(_ img: CGImage, pad: CGFloat = 14) -> CGImage {
        guard let px = rgba(img) else { return img }
        let w = img.width, h = img.height
        let bg = Array(px[((h - 6) * w + w / 2) * 4 ..< ((h - 6) * w + w / 2) * 4 + 3])
        var last = h - 6
        rowLoop: while last > 0 {
            for x in stride(from: 40, to: Int(Double(w) * 0.62), by: 2) {
                let i = (last * w + x) * 4
                if abs(Int(px[i]) - Int(bg[0])) > 3 || abs(Int(px[i + 1]) - Int(bg[1])) > 3 || abs(Int(px[i + 2]) - Int(bg[2])) > 3 { break rowLoop }
            }
            last -= 1
        }
        let keep = min(h, last + 1 + Int(pad * 2))
        return img.cropping(to: CGRect(x: 0, y: 0, width: w, height: keep)) ?? img
    }

    /// Makes the corners transparent (a window capture whose frame view did not clip, or a pane crop shown as a card).
    static func rounded(_ img: CGImage, radius points: CGFloat, scale: CGFloat = 2) -> CGImage? {
        let w = img.width, h = img.height
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let r = points * scale
        ctx.addPath(CGPath(roundedRect: CGRect(x: 0, y: 0, width: w, height: h), cornerWidth: r, cornerHeight: r, transform: nil))
        ctx.clip()
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage()
    }

    static func png(_ img: CGImage) -> Data? {
        let rep = NSBitmapImageRep(cgImage: img)
        rep.size = NSSize(width: CGFloat(img.width) / 2, height: CGFloat(img.height) / 2)   // 144 dpi
        return rep.representation(using: .png, properties: [:])
    }
}
#endif
