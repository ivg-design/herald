import SwiftUI
import AppKit

enum ReminderState { case idle, working, added, failed(String) }

/// Everything one banner needs to draw itself. The presentation fields (`layout`, `accentColor`,
/// `show*`, `maxBodyLines`) are derived from the notification that is already RESOLVED against its
/// template (the router resolves before anything else), so the view never has to know templates exist.
/// They are stored (not computed) so previews can nudge one of them, and they re-sync whenever `item`
/// is replaced, which is how a same-id update changes a live banner's layout in place.
@MainActor
final class BannerModel: ObservableObject {
    @Published var item: HeraldHistoryItem { didSet { applyPresentation(from: item.notification) } }
    @Published var appName: String
    @Published var icon: NSImage
    @Published var image: NSImage?
    @Published var reminderState: ReminderState = .idle
    @Published var hovering = false

    @Published var layout: HeraldLayout = .imageLeft
    /// Parsed from the notification's hex string; nil means "use the system accent / primary text".
    @Published var accentColor: NSColor?
    @Published var showSubtitle = true
    @Published var showBody = true
    @Published var showTimestamp = true
    @Published var maxBodyLines = BannerModel.defaultBodyLines
    /// The body parsed as Markdown, kept so a redraw (a hover, the timer) never re-parses it; it is rebuilt
    /// only when the body text itself changes.
    private(set) var bodyText: AttributedString?
    private var bodyTextSource: String?

    static let defaultBodyLines = 8

    var onClose: () -> Void = {}
    var onOpen: () -> Void = {}
    var onButton: (HeraldButton) -> Void = { _ in }
    var onSnooze: (SnoozeOption) -> Void = { _ in }
    var onReminder: () -> Void = {}
    var onHeight: (CGFloat) -> Void = { _ in }

    init(item: HeraldHistoryItem, appName: String, icon: NSImage, image: NSImage?) {
        self.item = item; self.appName = appName; self.icon = icon; self.image = image
        applyPresentation(from: item.notification)
    }

    private func applyPresentation(from n: HeraldNotification) {
        if n.body != bodyTextSource {
            bodyTextSource = n.body
            bodyText = Self.markdown(n.body)
        }
        layout = n.layout ?? .imageLeft
        accentColor = Self.color(fromHex: n.accentColor)
        showSubtitle = n.showSubtitle ?? true
        showBody = n.showBody ?? true
        showTimestamp = n.showTimestamp ?? true
        // Clamped so a typo in a template ("0", "9999") can neither hide the body nor grow a banner without bound.
        maxBodyLines = max(1, min(n.maxBodyLines ?? Self.defaultBodyLines, 30))
    }

    /// Body with `[text](url)` Markdown links. Inline-only so a stray `#` or `-` is not turned into a
    /// heading or list; whitespace (newlines) is preserved.
    static func markdown(_ body: String?) -> AttributedString? {
        guard let b = body, !b.isEmpty else { return nil }
        let opts = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: b, options: opts)) ?? AttributedString(b)
    }

    /// `#RGB`, `#RGBA`, `#RRGGBB` or `#RRGGBBAA` (the leading `#` is optional). Garbage returns nil rather
    /// than a surprise colour, so a bad template value degrades to the default look.
    static func color(fromHex raw: String?) -> NSColor? {
        guard var s = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.allSatisfy({ $0.isHexDigit }) else { return nil }
        if s.count == 3 || s.count == 4 { s = s.map { "\($0)\($0)" }.joined() }
        guard s.count == 6 || s.count == 8, let v = UInt64(s, radix: 16) else { return nil }
        let hasAlpha = s.count == 8
        func comp(_ shift: UInt64) -> CGFloat { CGFloat((v >> shift) & 0xFF) / 255 }
        return NSColor(srgbRed: comp(hasAlpha ? 24 : 16), green: comp(hasAlpha ? 16 : 8),
                       blue: comp(hasAlpha ? 8 : 0), alpha: hasAlpha ? comp(0) : 1)
    }
}

/// Capsule button used for banner actions. `kind` follows the API's button `style`:
/// `default` is tinted with the template accent (or the system accent), `destructive` is always red and a
/// touch stronger (outlined) so it never reads as a primary action, `cancel` is a quiet grey.
struct BannerButtonStyle: ButtonStyle {
    let kind: String
    /// Already contrast-adjusted for the current appearance by the caller.
    var accent: Color? = nil

    func makeBody(configuration: Configuration) -> some View {
        BannerButtonBody(configuration: configuration, kind: kind, accent: accent)
    }
}

private struct BannerButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let kind: String
    let accent: Color?
    @State private var hovering = false

    private var destructive: Bool { kind == "destructive" }

    private var color: Color {
        switch kind {
        case "destructive": return Color(nsColor: .systemRed)
        case "cancel": return .secondary
        default: return accent ?? .accentColor
        }
    }

    var body: some View {
        let pressed = configuration.isPressed
        let fill = pressed ? 0.28 : (hovering ? 0.2 : (destructive ? 0.14 : 0.12))
        configuration.label
            // A label never wraps inside its capsule; the action row wraps whole buttons instead.
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .font(.system(size: 12, weight: destructive ? .semibold : .medium))
            .foregroundStyle(color)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background {
                // Fill and outline share one ZStack inside the background so the outline is clipped with the fill.
                ZStack {
                    Capsule().fill(color.opacity(fill))
                    if destructive { Capsule().stroke(color.opacity(0.45), lineWidth: 1).clipShape(Capsule()) }
                }
            }
            .onHover { hovering = $0 }
            .contentShape(Capsule())
    }
}

struct BannerHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// The card background. Live banners use the system material (the approved look). A preview that forces
/// the OPPOSITE appearance from the system (the composer's side-by-side light/dark) cannot get a
/// matching material, so it falls back to a flat fill in that appearance's colours; text colours already
/// follow the environment, so both cases stay legible.
private struct BannerSurface: View {
    @Environment(\.colorScheme) private var scheme

    private var systemIsDark: Bool {
        let appearance = NSApp?.effectiveAppearance ?? NSAppearance.currentDrawing()
        return appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    var body: some View {
        if (scheme == .dark) == systemIsDark {
            Rectangle().fill(.regularMaterial)
        } else {
            Rectangle().fill(scheme == .dark ? Color(white: 0.17).opacity(0.94) : Color(white: 0.97).opacity(0.94))
        }
    }
}

/// The ONE banner renderer: live panels, the composer preview and history previews all draw this view.
/// Layouts are variants of one view (shared text column, meta column and action row), not separate views.
struct BannerView: View {
    static let width: CGFloat = 380
    /// Hero images are 16:9 across the full card width.
    static let heroImageHeight: CGFloat = width * 9 / 16

    @ObservedObject var model: BannerModel
    @Environment(\.colorScheme) private var scheme
    /// Set by the link action so the row's tap gesture (open url + dismiss) can tell it was a link click.
    @State private var linkClickedAt: Date = .distantPast

    private var n: HeraldNotification { model.item.notification }

    /// A first guess for the panel height before SwiftUI has measured the real one, so the off-screen
    /// parked panel is already roughly the right size.
    static func estimatedHeight(layout: HeraldLayout, hasImage: Bool) -> CGFloat {
        switch layout {
        case .compact: return 44
        case .hero: return hasImage ? heroImageHeight + 90 : 90
        case .imageLeft, .imageRight: return hasImage ? 96 : 80
        }
    }

    // MARK: Colours

    /// The template accent, nudged until it is legible on the current appearance (a pale yellow on a light
    /// card or a navy on a dark card would otherwise vanish). Returns nil when no accent is set.
    private var accent: Color? {
        guard let c = model.accentColor else { return nil }
        return Color(nsColor: Self.legible(c, dark: scheme == .dark))
    }

    /// Mixes `c` toward white (dark appearance) or black (light appearance) just far enough to reach a
    /// minimum perceived lightness / maximum lightness. Colours that already read well are untouched.
    static func legible(_ c: NSColor, dark: Bool) -> NSColor {
        guard let rgb = c.usingColorSpace(.sRGB) else { return c }
        let l = 0.2126 * rgb.redComponent + 0.7152 * rgb.greenComponent + 0.0722 * rgb.blueComponent
        let minDark: CGFloat = 0.55, maxLight: CGFloat = 0.45
        if dark, l < minDark {
            let f = (minDark - l) / (1 - l)
            return rgb.blended(withFraction: f, of: .white) ?? rgb
        }
        if !dark, l > maxLight {
            let f = (l - maxLight) / l
            return rgb.blended(withFraction: f, of: .black) ?? rgb
        }
        return rgb
    }

    // MARK: Body

    var body: some View {
        card
            .frame(width: Self.width, alignment: .topLeading)
            .fixedSize(horizontal: false, vertical: true)
            .background(BannerSurface())
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
            .tint(accent)
            .environment(\.openURL, linkAction)
            .background(GeometryReader { g in Color.clear.preference(key: BannerHeightKey.self, value: g.size.height) })
            .onPreferenceChange(BannerHeightKey.self) { model.onHeight($0) }
    }

    @ViewBuilder private var card: some View {
        switch model.layout {
        case .imageLeft, .imageRight: rowCard
        case .hero: heroCard
        case .compact: compactCard
        }
    }

    // MARK: Layouts

    /// imageLeft (default, unchanged look) and imageRight: thumbnail beside the text.
    private var rowCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                if model.layout == .imageLeft { thumbnail }
                textColumn(titleSize: 13)
                if model.layout == .imageRight { thumbnail }
                metaColumn(includeClose: true)
            }
            .contentShape(Rectangle())
            .onTapGesture { rowTapped() }

            if hasActionRow { actionRow }
        }
        .padding(12)
    }

    /// hero: the image spans the full card width at 16:9 (no inset, the card's rounded clip trims the
    /// corners), text below. Without an image it degrades to a text-only card with the close button
    /// back in the meta column, since there is no image to float it over.
    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                if let img = model.image {
                    ZStack(alignment: .topTrailing) {
                        Image(nsImage: img)
                            .resizable().scaledToFill()
                            .frame(width: Self.width, height: Self.heroImageHeight)
                            .clipped()
                        closeButton(size: 20, floating: true).padding(8)
                    }
                }
                HStack(alignment: .top, spacing: 12) {
                    textColumn(titleSize: 14)
                    metaColumn(includeClose: model.image == nil)
                }
                .padding(.horizontal, 12)
                .padding(.top, model.image == nil ? 12 : 10)
                .padding(.bottom, hasActionRow ? 10 : 12)
            }
            .contentShape(Rectangle())
            .onTapGesture { rowTapped() }

            if hasActionRow { actionRow.padding(.horizontal, 12).padding(.bottom, 12) }
        }
    }

    /// compact: one line (app icon, title, time, close). No image, subtitle or body by design; buttons,
    /// when the notification has any, sit on a second row so they stay reachable.
    private var compactCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(nsImage: model.icon)
                    .resizable().frame(width: 18, height: 18)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .help(model.appName)
                Text(n.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(accent ?? Color.primary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if model.showTimestamp { timestamp }
                closeButton(size: 16, floating: false)
            }
            .contentShape(Rectangle())
            .onTapGesture { rowTapped() }

            if hasActionRow { actionRow }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    // MARK: Pieces

    @ViewBuilder private var thumbnail: some View {
        if let img = model.image {
            Image(nsImage: img)
                .resizable().scaledToFill()
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private func textColumn(titleSize: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(n.title)
                .font(.system(size: titleSize, weight: .semibold))
                .foregroundStyle(accent ?? Color.primary)
                .lineLimit(2)
            if model.showSubtitle, let s = n.subtitle, !s.isEmpty {
                Text(s).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(2)
            }
            if model.showBody, let t = bodyText {
                Text(t).font(.system(size: 12)).lineLimit(model.maxBodyLines)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func metaColumn(includeClose: Bool) -> some View {
        VStack(alignment: .trailing, spacing: 6) {
            if includeClose { closeButton(size: 18, floating: false) }
            Image(nsImage: model.icon)
                .resizable().frame(width: 22, height: 22)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                .help(model.appName)
            if model.showTimestamp { timestamp }
        }
    }

    private var timestamp: some View {
        Text(model.item.deliveredAt, style: .time)
            .font(.system(size: 10)).foregroundStyle(.secondary)
    }

    /// `floating` puts the glyph on a material disc so it stays visible over any hero image.
    private func closeButton(size: CGFloat, floating: Bool) -> some View {
        Button(action: model.onClose) {
            Image(systemName: "xmark").font(.system(size: size > 18 ? 10 : 9, weight: .bold))
                .foregroundStyle(floating ? Color.primary : Color.secondary)
                .frame(width: size, height: size)
                .background(Circle().fill(floating ? AnyShapeStyle(.ultraThinMaterial) : AnyShapeStyle(Color.primary.opacity(0.08))))
        }
        .buttonStyle(.plain)
        .help("Dismiss")
        .accessibilityLabel("Dismiss")
    }

    // MARK: Body text and links

    /// Parsed once per body by the model (`BannerModel.bodyText`).
    private var bodyText: AttributedString? { model.bodyText }

    /// Body links open in the default browser, but only for web and mail schemes: a notification body
    /// must not be able to launch an arbitrary `file:` or custom-scheme URL on a stray click. The click is
    /// also recorded so the row's tap gesture does not additionally open the notification's own url and
    /// dismiss the banner.
    private var linkAction: OpenURLAction {
        OpenURLAction { url in
            guard LinkPolicy.isOpenable(url) else { return .discarded }
            linkClickedAt = Date()
            return .systemAction
        }
    }

    /// The tap gesture and the link action can both fire for one click on a link, in either order. One
    /// main-queue hop lets the link action run first, then a link click is ignored here.
    private func rowTapped() {
        DispatchQueue.main.async {
            if Date().timeIntervalSince(linkClickedAt) < 0.5 { return }
            model.onOpen()
        }
    }

    // MARK: Actions

    private var hasActionRow: Bool {
        !(n.buttons ?? []).isEmpty || n.snooze == true || n.reminder != nil
    }

    /// A long label would run out of the card; the full text stays in the tooltip.
    private static func shortLabel(_ label: String, limit: Int = 40) -> String {
        label.count > limit ? String(label.prefix(limit - 1)) + "\u{2026}" : label
    }

    /// Buttons wrap as whole capsules onto further rows; the snooze menu stays pinned to the trailing edge.
    private var actionRow: some View {
        HStack(alignment: .top, spacing: 6) {
            FlowLayout(spacing: 6, lineSpacing: 6) {
                ForEach(Array((n.buttons ?? []).enumerated()), id: \.offset) { _, b in
                    Button(Self.shortLabel(b.label)) { model.onButton(b) }
                        .buttonStyle(BannerButtonStyle(kind: b.style ?? "default", accent: accent))
                        .help(b.label)
                }
                if n.reminder != nil { reminderButton }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if n.snooze == true {
                Menu {
                    ForEach(SnoozeOption.allCases, id: \.self) { o in
                        Button(o.title) { model.onSnooze(o) }
                    }
                } label: {
                    Text("\u{23F0}").font(.system(size: 13))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Snooze")
            }
        }
    }

    @ViewBuilder private var reminderButton: some View {
        switch model.reminderState {
        case .idle, .working:
            Button("Add to Reminders") { model.onReminder() }.buttonStyle(BannerButtonStyle(kind: "cancel"))
        case .added:
            Text("Added to Reminders \u{2713}").font(.system(size: 11)).foregroundStyle(.secondary)
                .lineLimit(1).fixedSize()
        case .failed(let m):
            Button("Reminders unavailable") { model.onReminder() }
                .buttonStyle(BannerButtonStyle(kind: "destructive")).help(m)
        }
    }
}

/// Lays its children out left to right and starts a new row when the next one would not fit, so a row of
/// buttons that is too wide wraps between buttons instead of inside them.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(subviews, in: proposal.width ?? .infinity).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let arranged = arrange(subviews, in: bounds.width)
        for (index, point) in arranged.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y),
                                  anchor: .topLeading, proposal: .unspecified)
        }
    }

    private func arrange(_ subviews: Subviews, in maxWidth: CGFloat) -> (size: CGSize, positions: [CGPoint]) {
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, widest: CGFloat = 0
        var positions: [CGPoint] = []
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > maxWidth {
                x = 0
                y += rowHeight + lineSpacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            x += size.width
            widest = max(widest, x)
            x += spacing
            rowHeight = max(rowHeight, size.height)
        }
        return (CGSize(width: widest, height: positions.isEmpty ? 0 : y + rowHeight), positions)
    }
}
