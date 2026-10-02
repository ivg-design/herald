import SwiftUI
import AppKit

/// Everything a component needs to draw one notification, built by `GridBannerView` from the `BannerModel`
/// each time it draws. Components read fields, resolve actions and report presses through it; none of them
/// knows about templates, history or the banner panel.
@MainActor
struct GridContext {
    /// Resolved fields (`TemplateResolver.fields`): what every `{token}` binds to.
    var fields: [String: HeraldFieldValue]
    /// The resolved action list: issuer buttons through the template's rules, plus template-added actions.
    var actions: [HeraldResolvedAction]
    var notification: HeraldNotification
    var appName: String
    var icon: NSImage
    /// The cached copy of the notification's own `image` (downloaded once by the history store).
    var cachedImage: NSImage?
    var deliveredAt: Date
    /// The template accent nudged to be legible on the current appearance; nil when none is set.
    var accent: Color?
    var scheme: ColorScheme
    /// Line limit of `body` text with no `maxLines` of its own.
    var maxBodyLines: Int
    var reminderState: ReminderState
    var hovering: Bool
    /// The issuer's manifest, for components that need its assets (Rive).
    var manifest: HeraldManifest?
    /// True for an offscreen render: `ImageRenderer` cannot draw AppKit-backed views (menus, Rive), so those
    /// components draw a static stand-in instead.
    var offscreen: Bool
    /// An action was pressed. Dismiss goes through `dismiss`, the built-in snooze menu through `snooze` and
    /// Add to Reminders through `addReminder`; everything else lands here with where the action came from.
    var perform: (HeraldAction, HeraldActionOrigin) -> Void
    var snooze: (SnoozeOption) -> Void
    var addReminder: () -> Void
    var dismiss: () -> Void
    /// This card is the top of a stack of this many notifications (1 when it is alone), and pressing the stack
    /// counter (`stackBadge`) opens the stack in place.
    var stackCount = 1
    var expandStack: () -> Void = {}

    // MARK: Data

    /// The text of a binding, or nil when every token in it is absent.
    func bind(_ binding: String) -> String? { TemplateResolver.bind(binding, fields: fields) }

    /// An action label with `{token}` placeholders filled; the id when that leaves nothing.
    func label(for action: HeraldAction) -> String {
        let s = TemplateResolver.fill(action.label, fields: fields).trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? action.id : s
    }

    /// The action a button points at: its inline action (the user's own, so template origin), else the
    /// resolved action its `actionRef` names. nil when the ref is not in the list (hidden by a rule, or the
    /// issuer did not send it).
    func action(inline: HeraldAction?, ref: String?) -> (action: HeraldAction, origin: HeraldActionOrigin)? {
        if let inline { return (inline, .template) }
        guard let ref, !ref.isEmpty, let r = actions.first(where: { $0.action.id == ref }) else { return nil }
        return (r.action, r.origin)
    }

    /// The picture a binding names: the cached copy when it is the notification's own image, else a local
    /// file or `data:` URI. nil for a remote URL (see `isRemoteImage`) and for anything unreadable.
    func image(forBinding binding: String) -> NSImage? {
        guard let spec = bind(binding) else { return nil }
        if let cachedImage, isCachedImage(spec) { return cachedImage }
        return GridImageLoader.image(for: spec)
    }

    /// A binding that resolves to an http(s) URL that is not the notification's cached image: drawn with
    /// `AsyncImage`, since only the payload's own `image` is downloaded ahead of time.
    func remoteImageURL(forBinding binding: String) -> URL? {
        guard let spec = bind(binding), GridImageLoader.isRemote(spec) else { return nil }
        if cachedImage != nil, isCachedImage(spec) { return nil }
        return URL(string: spec)
    }

    /// The cached picture stands for whatever the `image` field says (the notification's own image source, or
    /// the data a preview supplied), so any binding that resolves to the same text shows it.
    private func isCachedImage(_ spec: String) -> Bool {
        if spec == notification.image || spec == BannerModel.cachedImageToken { return true }
        if let v = fields["image"] { return TemplateResolver.string(for: v) == spec }
        return false
    }

    // MARK: Colours

    /// A colour spec from a template: `#RGB` / `#RRGGBB` / `#RRGGBBAA`, or `accent`, `primary`, `secondary`.
    /// Hex colours are nudged until they read on the current appearance (`legible`), keywords follow the system.
    func color(_ spec: String?, legible: Bool = true) -> Color? {
        guard let spec = spec?.trimmingCharacters(in: .whitespaces), !spec.isEmpty else { return nil }
        switch spec.lowercased() {
        case "accent": return accent ?? .accentColor
        case "primary": return .primary
        case "secondary": return .secondary
        default: break
        }
        guard let ns = BannerModel.color(fromHex: spec) else { return nil }
        return Color(nsColor: legible ? BannerView.legible(ns, dark: scheme == .dark) : ns)
    }
}

// MARK: - Alignment

extension HeraldAlign {
    /// The SwiftUI alignment of the nine points.
    var alignment: Alignment {
        switch self {
        case .topLeading: return .topLeading
        case .top: return .top
        case .topTrailing: return .topTrailing
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        case .bottomLeading: return .bottomLeading
        case .bottom: return .bottom
        case .bottomTrailing: return .bottomTrailing
        }
    }

    var horizontalAlignment: HorizontalAlignment {
        switch horizontal {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }

    var textAlignment: TextAlignment {
        switch horizontal {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }
}

extension HeraldTextAlignment {
    var alignment: Alignment {
        switch self {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }

    var textAlignment: TextAlignment {
        switch self {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }
}

// MARK: - Text styles

enum GridStyle {
    static func font(_ style: HeraldTextStyle, size: Double? = nil, weight: HeraldFontWeight? = nil) -> Font {
        let base: (size: CGFloat, weight: Font.Weight, design: Font.Design)
        switch style {
        case .title: base = (13, .semibold, .default)
        case .subtitle: base = (12, .regular, .default)
        case .body: base = (12, .regular, .default)
        case .caption: base = (10, .regular, .default)
        case .mono: base = (11, .regular, .monospaced)
        }
        let w: Font.Weight
        switch weight {
        case .regular?: w = .regular
        case .medium?: w = .medium
        case .semibold?: w = .semibold
        case .bold?: w = .bold
        case nil: w = base.weight
        }
        return .system(size: CGFloat(size ?? Double(base.size)), weight: w, design: base.design)
    }

    /// Subtitle and caption are secondary text, everything else primary.
    static func defaultColor(_ style: HeraldTextStyle) -> Color {
        switch style {
        case .subtitle, .caption: return .secondary
        case .title, .body, .mono: return .primary
        }
    }

    /// Line limit when the component sets none: what v1 used for each line.
    static func defaultLines(_ style: HeraldTextStyle, body: Int) -> Int {
        switch style {
        case .title, .subtitle: return 2
        case .body: return body
        case .caption: return 1
        case .mono: return 4
        }
    }

    /// A long label would run out of the card; the full text stays in the tooltip.
    static func shortLabel(_ label: String, limit: Int = 40) -> String {
        label.count > limit ? String(label.prefix(limit - 1)) + "\u{2026}" : label
    }

    /// Black or white, whichever reads on `color`.
    static func contrastingText(on color: NSColor?) -> Color {
        guard let rgb = color?.usingColorSpace(.sRGB) else { return .white }
        let l = 0.2126 * rgb.redComponent + 0.7152 * rgb.greenComponent + 0.0722 * rgb.blueComponent
        return l > 0.62 ? .black : .white
    }

    /// An SF Symbol name that exists, else a question mark, so a typo in a template still draws something.
    static func symbol(_ name: String) -> String {
        NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil ? name : "questionmark.circle"
    }
}

// MARK: - Markdown

/// Inline Markdown (`[text](url)`) for `text` components, parsed once per distinct string. Inline-only so a
/// stray `#` or `-` is not turned into a heading or a list; whitespace (newlines) is preserved.
@MainActor
enum GridMarkdown {
    private static var cache: [String: AttributedString] = [:]

    static func parse(_ text: String) -> AttributedString {
        if let hit = cache[text] { return hit }
        let opts = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        let parsed = (try? AttributedString(markdown: text, options: opts)) ?? AttributedString(text)
        if cache.count > 200 { cache.removeAll() }
        cache[text] = parsed
        return parsed
    }
}

// MARK: - Images

@MainActor
enum GridImageLoader {
    private static let cache: NSCache<NSString, NSImage> = {
        let c = NSCache<NSString, NSImage>()
        c.countLimit = 64
        return c
    }()

    static func isRemote(_ spec: String) -> Bool {
        let s = spec.lowercased()
        return s.hasPrefix("http://") || s.hasPrefix("https://")
    }

    /// A picture from a file path (`~` expanded), a `file:` URL or a `data:` URI. Remote URLs are not fetched here.
    static func image(for spec: String) -> NSImage? {
        let key = spec as NSString
        if let hit = cache.object(forKey: key) { return hit }
        var img: NSImage?
        if spec.hasPrefix("data:") {
            if let comma = spec.firstIndex(of: ","),
               let data = Data(base64Encoded: String(spec[spec.index(after: comma)...]), options: .ignoreUnknownCharacters) {
                img = NSImage(data: data)
            }
        } else if spec.lowercased().hasPrefix("file:") {
            if let url = URL(string: spec) { img = NSImage(contentsOf: url) }
        } else if !isRemote(spec) {
            img = NSImage(contentsOfFile: (spec as NSString).expandingTildeInPath)
        }
        if let img { cache.setObject(img, forKey: key) }
        return img
    }
}
