import SwiftUI
import AppKit

enum ReminderState { case idle, working, added, failed(String) }

/// Everything one banner needs to draw itself. The presentation fields (`layout`, `accentColor`,
/// `show*`, `maxBodyLines`) are derived from the notification that is already RESOLVED against its
/// template (the router resolves before anything else). A v2 grid template is handed in separately
/// (`template`); without one the banner is drawn from the built-in grid for its v1 `layout`, so every
/// notification renders through `GridBannerView`.
/// Everything derived (grid, fields, actions, accent) is stored, not computed, so previews can nudge
/// one of them, and it is rebuilt whenever `item`, `template`, `manifest` or `fieldsOverride` is replaced,
/// which is how a same-id update changes a live banner's layout in place.
@MainActor
final class BannerModel: ObservableObject {
    @Published var item: HeraldHistoryItem { didSet { refresh() } }
    @Published var appName: String
    @Published var icon: NSImage
    @Published var image: NSImage? { didSet { refresh() } }
    @Published var reminderState: ReminderState = .idle
    /// "Action failed - why", shown under the grid for a few seconds after an action fails. It is the card's own
    /// line, not a template field, so it shows whatever the template draws.
    @Published var failureLine: String?
    @Published var hovering = false
    /// False when `ImageRenderer` draws the banner (the preview PNG): it cannot draw AppKit-backed views, so
    /// Rive animations and menus (snooze, "+N") are drawn as static stand-ins.
    @Published var liveAnimations = true

    /// The template to draw. nil, or a v1 template, draws the built-in grid for the notification's `layout`.
    @Published var template: HeraldTemplate? { didSet { refresh() } }
    /// The issuer's manifest: gives issuer actions their declared ids (what a template's rules match).
    @Published var manifest: HeraldManifest? { didSet { refresh() } }
    /// Data for the bindings, replacing what the item carries (designer samples, "last real notification").
    /// nil binds the item's own fields.
    @Published var fieldsOverride: [String: HeraldFieldValue]? { didSet { refresh() } }

    // v1 presentation fields, kept in step with the notification (the composer and tests read them).
    @Published var layout: HeraldLayout = .imageLeft
    /// Parsed from the notification's hex string; nil means "use the system accent / primary text".
    @Published var accentColor: NSColor?
    @Published var showSubtitle = true
    @Published var showBody = true
    @Published var showTimestamp = true
    @Published var maxBodyLines = BannerModel.defaultBodyLines

    /// The grid template being drawn.
    private(set) var grid: HeraldTemplate
    /// What the bindings read: the item's fields (or `fieldsOverride`), with the notification's own title,
    /// subtitle and body laid over them (a failure line replaces the subtitle without touching the item's
    /// stored fields) and the template's `extra` values as `extra.<key>`.
    private(set) var fields: [String: HeraldFieldValue] = [:]
    /// Issuer actions (the payload's buttons and the built-in snooze) through the template's rules, plus the
    /// template's added actions.
    private(set) var actions: [HeraldResolvedAction] = []

    static let defaultBodyLines = 8
    /// What `{image}` holds when the model was given a picture but the notification names no image source
    /// (a composer preview): the picture is shown, and the binding counts as present.
    static let cachedImageToken = "herald-cached-image"

    var onClose: () -> Void = {}
    var onOpen: () -> Void = {}
    /// An action other than dismiss, the snooze menu and Add to Reminders was pressed. `BannerCenter` routes it
    /// to the app controller; a preview leaves it a no-op.
    var onAction: (HeraldAction, HeraldActionOrigin) -> Void = { _, _ in }
    var onSnooze: (SnoozeOption) -> Void = { _ in }
    var onReminder: () -> Void = {}
    var onHeight: (CGFloat) -> Void = { _ in }

    init(item: HeraldHistoryItem, appName: String, icon: NSImage, image: NSImage?,
         template: HeraldTemplate? = nil, manifest: HeraldManifest? = nil,
         fields: [String: HeraldFieldValue]? = nil) {
        self.item = item; self.appName = appName; self.icon = icon; self.image = image
        self.template = template; self.manifest = manifest; self.fieldsOverride = fields
        self.grid = BuiltinTemplates.gridTemplate(for: item.notification)
        refresh()
    }

    /// Banner width in points: the grid's `width`, clamped to what the validator allows.
    var bannerWidth: CGFloat {
        CGFloat(GridSolver.clampedWidth(grid.grid?.width ?? Double(BannerView.width)))
    }

    /// The template accent nudged until it is legible on the given appearance; nil when none is set.
    func accent(dark: Bool) -> Color? {
        accentColor.map { Color(nsColor: BannerView.legible($0, dark: dark)) }
    }

    /// An action was pressed: dismiss closes the banner, everything else goes to `onAction`.
    func perform(_ action: HeraldAction, origin: HeraldActionOrigin) {
        if action.kind == .dismiss { onClose() } else { onAction(action, origin) }
    }

    private func refresh() {
        let n = item.notification
        // The built-in grids have an image column only when there is a picture for it (see BuiltinTemplates).
        var hasImage = image != nil || !(n.image ?? "").trimmingCharacters(in: .whitespaces).isEmpty
        if case .text(let s)? = fieldsOverride?["image"], !s.isEmpty { hasImage = true }
        var g = BuiltinTemplates.gridTemplate(for: n, hasImage: hasImage)
        if let t = template {
            if t.usesGrid {
                if let layout = BuiltinTemplates.layout(forName: t.name), t == BuiltinTemplates.named(t.name, app: t.app) {
                    // An untouched `builtin.*` template named by the notification: the same grid, with or without
                    // the image column as the data needs.
                    g = BuiltinTemplates.template(layout: layout, app: t.app, hasImage: hasImage)
                } else {
                    g = t
                }
            } else {
                // A v1 template contributes its action rules and extra values to the built-in grid.
                g.actionRules = t.actionRules; g.extra = t.extra; g.collapseEmpty = t.collapseEmpty
            }
        }
        grid = g

        layout = n.layout ?? .imageLeft
        accentColor = Self.color(fromHex: n.accentColor ?? g.accentColor)
        showSubtitle = n.showSubtitle ?? true
        showBody = n.showBody ?? true
        showTimestamp = n.showTimestamp ?? true
        // Clamped so a typo in a template ("0", "9999") can neither hide the body nor grow a banner without bound.
        let templateLines = template?.usesGrid == true ? g.maxBodyLines : Self.defaultBodyLines
        maxBodyLines = max(1, min(n.maxBodyLines ?? templateLines, 30))

        fields = BannerData.fields(for: n, stored: item.fields, override: fieldsOverride, manifest: manifest,
                                   extra: g.extra, deliveredAt: item.deliveredAt, hasPicture: image != nil)
        actions = BannerData.actions(for: n, manifest: manifest, rules: g.actionRules, template: template)
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

/// The hosting view of a banner panel. A banner panel is non-activating and not key until it is clicked, and a
/// SwiftUI `onTapGesture` (the banner's own "open it" tap, which also has to leave link clicks alone) does not
/// see the click that makes a window key: without this, the first click on a banner's text did nothing and only
/// the second one opened it (issue #24). Buttons were never affected, which is why it went unnoticed.
final class BannerHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
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

/// The ONE banner: live panels, the composer preview, history rows and the preview PNG all draw this view.
/// It is the card (material, border, tint, height report) around `GridBannerView`, which lays out and draws
/// the template's grid; a notification without a v2 template is drawn from the built-in grid for its layout.
struct BannerView: View {
    /// The width of the built-in templates. A v2 template sets its own (`BannerModel.bannerWidth`).
    static let width: CGFloat = 380

    @ObservedObject var model: BannerModel
    @Environment(\.colorScheme) private var scheme
    /// True only for the card `BannerCenter` puts in a live banner panel (History rows, the composer, the designer
    /// and offscreen previews draw the same view without the replay control). A plain value rather than an AppKit
    /// probe view: an NSViewRepresentable renders as ImageRenderer's yellow "no entry" placeholder in /v1/preview.
    var isLive = false

    /// A first guess for the panel height before SwiftUI has measured the real one, so the off-screen
    /// parked panel is already roughly the right size.
    @MainActor static func estimatedHeight(for model: BannerModel) -> CGFloat {
        GridEstimator.height(for: model)
    }

    // MARK: Colours

    /// Mixes `c` toward white (dark appearance) or black (light appearance) just far enough to reach a
    /// minimum perceived lightness / maximum lightness. Colours that already read well are untouched. The
    /// template accent goes through this, so a pale yellow on a light card or a navy on a dark card does not
    /// vanish.
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
        VStack(spacing: 0) {
            GridBannerView(model: model, showsReplay: isLive)
            if let line = model.failureLine { FailureLine(text: line, inset: model.grid.grid?.padding ?? 14) }
        }
            .frame(width: model.bannerWidth, alignment: .topLeading)
            .fixedSize(horizontal: false, vertical: true)
            .background(BannerSurface())
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
            .tint(model.accent(dark: scheme == .dark))
            .background(GeometryReader { g in Color.clear.preference(key: BannerHeightKey.self, value: g.size.height) })
            .onPreferenceChange(BannerHeightKey.self) { model.onHeight($0) }
    }
}

/// The strip under the grid that says an action failed.
struct FailureLine: View {
    let text: String
    let inset: Double

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill").font(.caption)
            Text(text).font(.caption).lineLimit(2)
            Spacer(minLength: 0)
        }
        .foregroundStyle(Color.red)
        .padding(.horizontal, inset).padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red.opacity(0.10))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(text)
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
