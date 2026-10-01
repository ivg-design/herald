import Foundation

/// Which URLs Herald will hand to the system when a banner, a button or a History row is clicked.
///
/// A notification's `url` and a button's `url` come from the sender (and a sender may be relaying text it
/// scraped from somewhere else), so opening them blindly would let one click launch a `file:` path, a
/// `smb:` share, a Shortcuts or other custom-scheme URL. Only web and mail links are opened.
public enum LinkPolicy {
    public static let openableSchemes: Set<String> = ["http", "https", "mailto"]

    public static func isOpenable(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), openableSchemes.contains(scheme) else { return false }
        if scheme == "mailto" { return true }
        return url.host?.isEmpty == false
    }

    public static func isOpenable(_ string: String) -> Bool {
        URL(string: string).map(isOpenable) ?? false
    }
}

/// Recognises the image formats Herald is willing to cache, from the bytes alone.
///
/// The extension of a cached image decides which program LaunchServices uses to open the file, so it must
/// never come from the sender (`data:application/terminal;base64,...` would be stored as `.terminal`).
/// It comes from here, and anything that is not a known image is not stored.
public enum ImageSniffer {
    /// File extension for the image format `data` starts with, or nil when it is not a supported image.
    public static func fileExtension(for data: Data) -> String? {
        let b = [UInt8](data.prefix(32))
        func starts(_ sig: [UInt8], at offset: Int = 0) -> Bool {
            b.count >= offset + sig.count && Array(b[offset..<(offset + sig.count)]) == sig
        }
        func ascii(_ s: String) -> [UInt8] { Array(s.utf8) }

        if starts([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) { return "png" }
        if starts([0xFF, 0xD8, 0xFF]) { return "jpg" }
        if starts(ascii("GIF87a")) || starts(ascii("GIF89a")) { return "gif" }
        if starts(ascii("RIFF")) && starts(ascii("WEBP"), at: 8) { return "webp" }
        if starts([0x49, 0x49, 0x2A, 0x00]) || starts([0x4D, 0x4D, 0x00, 0x2A]) { return "tiff" }
        if starts(ascii("BM")) && b.count >= 14 { return "bmp" }
        if starts(ascii("ftyp"), at: 4), b.count >= 12 {
            let brand = String(decoding: b[8..<12], as: UTF8.self)
            if ["heic", "heix", "hevc", "hevx", "heim", "heis", "mif1", "msf1"].contains(brand) { return "heic" }
            if ["avif", "avis"].contains(brand) { return "avif" }
        }
        return nil
    }
}

/// Size limits for what a client may send. They bound what one notification can cost in history, in the
/// image cache and in banner rendering, whatever the sender is (a bug in a script, or something hostile).
public enum PayloadLimits {
    public static let maxAppBytes = 128
    public static let maxIdBytes = 256
    public static let maxTitleBytes = 1024
    public static let maxSubtitleBytes = 1024
    public static let maxBodyBytes = 16 * 1024
    public static let maxMetadataBytes = 64 * 1024
    public static let maxButtons = 8
    public static let maxButtonsBytes = 64 * 1024
    /// A `data:` URI, path or URL naming an image or an app icon.
    public static let maxImageSpecBytes = 256 * 1024
    /// Any other single text field (url, sound, template, colour, ...).
    public static let maxSmallFieldBytes = 2048

    /// Throws a 413 `BackendError` naming the first field that is too large.
    public static func validate(_ n: HeraldNotification) throws {
        try check("app", n.app, maxAppBytes)
        try check("id", n.id, maxIdBytes)
        try check("title", n.title, maxTitleBytes)
        try check("subtitle", n.subtitle, maxSubtitleBytes)
        try check("body", n.body, maxBodyBytes)
        try check("image", n.image, maxImageSpecBytes)
        for (name, value) in [("url", n.url), ("sound", n.sound), ("priority", n.priority), ("template", n.template),
                              ("accentColor", n.accentColor)] {
            try check(name, value, maxSmallFieldBytes)
        }
        if let buttons = n.buttons {
            guard buttons.count <= maxButtons else { throw BackendError(413, "too many buttons (at most \(maxButtons))") }
            try checkEncoded("buttons", buttons, maxButtonsBytes)
        }
        if let metadata = n.metadata { try checkEncoded("metadata", metadata, maxMetadataBytes) }
        if let reminder = n.reminder {
            try check("reminder.title", reminder.title, maxTitleBytes)
            try check("reminder.due", reminder.due, maxSmallFieldBytes)
        }
    }

    public static func validate(_ r: HeraldAppRegistration) throws {
        try check("app", r.app, maxAppBytes)
        try check("appName", r.appName, maxSmallFieldBytes)
        try check("icon", r.icon, maxImageSpecBytes)
        try check("bundleId", r.bundleId, maxSmallFieldBytes)
        try check("callbackURL", r.callbackURL, maxSmallFieldBytes)
    }

    private static func check(_ name: String, _ value: String?, _ limit: Int) throws {
        guard let value, value.utf8.count > limit else { return }
        throw BackendError(413, "\(name) is too large (at most \(limit) bytes)")
    }

    private static func checkEncoded<T: Encodable>(_ name: String, _ value: T, _ limit: Int) throws {
        guard let data = try? HeraldJSON.encoder().encode(value), data.count > limit else { return }
        throw BackendError(413, "\(name) is too large (at most \(limit) bytes)")
    }
}

/// "Latest request for a key wins" for work that suspends midway (a notify that downloads its image).
/// `begin` returns a ticket; a later `begin` or `invalidate` for the same key makes it stale, and the work
/// checks `isCurrent` after it resumes, so an older request can never overwrite or resurrect a newer state.
public struct SupersedeTracker: Sendable {
    private var counter: UInt64 = 0
    private var current: [String: UInt64] = [:]

    public init() {}

    public mutating func begin(_ key: String) -> UInt64 {
        counter += 1
        current[key] = counter
        return counter
    }

    public func isCurrent(_ key: String, _ ticket: UInt64) -> Bool { current[key] == ticket }

    /// Forgets the ticket once its work is done (only if nothing superseded it), so the table never grows.
    public mutating func finish(_ key: String, _ ticket: UInt64) {
        if current[key] == ticket { current[key] = nil }
    }

    /// Makes any request in flight for `key` stale (a dismiss that arrives while a notify is suspended).
    public mutating func invalidate(_ key: String) { current[key] = nil }

    /// Same for every key that starts with `prefix`; nil means all of them.
    public mutating func invalidateAll(prefix: String? = nil) {
        guard let prefix else { current.removeAll(); return }
        for key in current.keys where key.hasPrefix(prefix) { current[key] = nil }
    }

    public var pendingCount: Int { current.count }
}

/// Where the banners of one screen corner go. Pure so the arithmetic is tested; `BannerCenter` applies it.
/// Banners stack newest first from the corner; once the next one would run past the visible height it and
/// everything older stay hidden, and one "+N more" pill takes the place after the last visible banner.
public struct BannerStackPlan: Equatable, Sendable {
    /// Distance from the corner edge for each visible banner, newest first.
    public var offsets: [CGFloat]
    /// Banners that do not fit (the oldest ones).
    public var overflow: Int
    /// Distance from the corner edge for the "+N more" pill, nil when no pill is needed.
    public var stubOffset: CGFloat?

    public var visibleCount: Int { offsets.count }

    /// `heights` are newest first. The newest banner is always visible, even if it is taller than `available`.
    /// `forceStub` reserves the pill's place although nothing here overflows (banners deferred elsewhere).
    public static func make(heights: [CGFloat], available: CGFloat, gap: CGFloat, stubHeight: CGFloat,
                            forceStub: Bool = false) -> BannerStackPlan {
        var offsets: [CGFloat] = []
        var used: CGFloat = 0
        for h in heights {
            let top = offsets.isEmpty ? 0 : used + gap
            if !offsets.isEmpty && top + h > available { break }
            offsets.append(top)
            used = top + h
        }
        let overflow = heights.count - offsets.count
        guard overflow > 0 || forceStub else {
            return BannerStackPlan(offsets: offsets, overflow: 0, stubOffset: nil)
        }
        // Make room for the pill by taking the oldest visible banners back, but never the newest one.
        while offsets.count > 1 && used + gap + stubHeight > available {
            offsets.removeLast()
            used = offsets[offsets.count - 1] + heights[offsets.count - 1]
        }
        return BannerStackPlan(offsets: offsets, overflow: heights.count - offsets.count,
                               stubOffset: offsets.isEmpty ? 0 : used + gap)
    }
}
