import SwiftUI
import AppKit

// The stacked banner (DESIGN section 9): the newest notification of a group drawn by the ONE banner view, with the
// edges of the cards behind it and a count badge, and the open stack, a scrollable list of the group's banners each
// drawn with its own template. `StackCenter` decides who is on top and what is open; these views only draw it, and
// none of them activates Herald (DESIGN section 8): they sit in the same non-activating panel a banner does.

// MARK: - Model

/// One banner of an open stack: the id the list keys it by and the model it draws.
struct StackListMember: Identifiable {
    let id: String
    let model: BannerModel
}

/// What one panel needs to know about the stack its banner is in. Owned by the banner's entry; `StackCenter` keeps
/// it current. A banner that is alone (count 1) draws exactly as it always did.
@MainActor
final class StackModel: ObservableObject {
    /// The stack's size (1 when the banner is alone).
    @Published var count = 1
    /// The banner is the stack's top card. A card under another one has no panel on screen while the stack is closed.
    @Published var isTop = true
    /// The stack is open as a list (drawn by the top card's panel).
    @Published var expanded = false
    /// The stack's banners, newest first, for the open list.
    @Published var members: [StackListMember] = []
    /// The open panel's width: that of the widest member.
    @Published var width: CGFloat = BannerView.width
    /// Rows sit against the panel's right edge for a right-hand corner, its left edge for a left-hand one.
    @Published var trailing = true
    /// The tallest the open list may be, from its slot's visible height (`StackListLayout.cap`), so Collapse and
    /// Dismiss all never fall off the screen. Unbounded until the center sets it (and in an offscreen preview).
    @Published var maxListHeight: CGFloat = .infinity

    var onExpand: () -> Void = {}
    var onCollapse: () -> Void = {}
    var onDismissAll: () -> Void = {}

    /// What the count badge and the title do: open a closed stack, close an open one.
    func toggle() {
        switch StackToggle.action(expanded: expanded) {
        case .expand: onExpand()
        case .collapse: onCollapse()
        }
    }
}

// MARK: - The panel's root view

/// What a banner panel shows: the card (stacked when it stands for more than one notification) or, while its stack
/// is open, the list. One path for a lone banner too, so a banner that gains or loses stack mates keeps its view
/// (and a Rive animation keeps running) instead of being rebuilt.
struct StackRootView: View {
    @ObservedObject var model: BannerModel
    @ObservedObject var stack: StackModel

    var body: some View {
        if stack.isTop && stack.expanded && stack.count > 1 {
            StackListView(model: model, stack: stack)
        } else {
            StackedCardView(model: model, count: stack.isTop ? stack.count : 1, isLive: true, onExpand: { stack.toggle() })
        }
    }
}

// MARK: - Stacked card

struct StackHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// The card of a stack: the banner, the edges of the cards behind it peeking out below, and the count badge on its
/// top edge at the right. A template that has its own `stackBadge` places the counter itself and gets no default
/// one. With a count of 1 it is the plain banner. It reports the height of the whole panel (edges and badge
/// included), which is why the card inside it does not.
struct StackedCardView: View {
    @ObservedObject var model: BannerModel
    /// How many notifications the card stands for.
    var count: Int
    var isLive = false
    /// The default badge was pressed.
    var onExpand: () -> Void = {}
    /// False when the caller measures (the preview PNG).
    var reportsHeight = true
    @Environment(\.colorScheme) private var scheme

    /// How far each edge peeks out below the card.
    static let edgeStep: CGFloat = 6
    /// How much of the badge rises above the card's top edge.
    static let badgeOverhang: CGFloat = 9

    private var stacked: Bool { count > 1 }
    private var edges: Int { stacked ? min(count - 1, 2) : 0 }
    /// Does the template draw the counter itself?
    private var hasOwnBadge: Bool {
        model.grid.cells.contains { if case .stackBadge = $0.component { return true } else { return false } }
    }
    private var showsDefaultBadge: Bool { stacked && !hasOwnBadge }

    var body: some View {
        BannerView(model: model, isLive: isLive, reportsHeight: false)
            .background(alignment: .top) { if stacked { StackEdges(edges: edges) } }
            .overlay(alignment: .topTrailing) {
                if showsDefaultBadge {
                    StackCountPill(count: count, fill: model.accent(dark: scheme == .dark) ?? .accentColor,
                                   text: GridStyle.contrastingText(on: model.accentColor ?? NSColor.controlAccentColor),
                                   onTap: onExpand)
                        .padding(.trailing, 10)
                        .offset(y: -Self.badgeOverhang)
                }
            }
            .padding(.top, showsDefaultBadge ? Self.badgeOverhang : 0)
            .padding(.bottom, CGFloat(edges) * Self.edgeStep)
            .background(GeometryReader { g in Color.clear.preference(key: StackHeightKey.self, value: g.size.height) })
            .onPreferenceChange(StackHeightKey.self) { if reportsHeight { model.onHeight($0) } }
    }
}

/// The cards behind the top one: each a little narrower and a little lower than the one in front.
private struct StackEdges: View {
    let edges: Int
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .top) {
                ForEach(Array((1...max(edges, 1)).reversed()), id: \.self) { i in
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(fill(depth: i))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.2), lineWidth: 0.5))
                        .shadow(color: Color.black.opacity(0.16), radius: 2, y: 1)
                        .frame(width: max(g.size.width - CGFloat(i) * 16, 0), height: g.size.height)
                        .offset(y: CGFloat(i) * StackedCardView.edgeStep)
                }
            }
            .frame(width: g.size.width, height: g.size.height, alignment: .top)
        }
    }

    /// Flat, opaque enough to read as a card, a shade darker the further back it is.
    private func fill(depth: Int) -> Color {
        let base: Double = scheme == .dark ? 0.25 : 0.95
        let step: Double = scheme == .dark ? -0.04 : -0.06
        return Color(white: base + step * Double(depth - 1)).opacity(0.96)
    }
}

/// The default counter: a capsule with the number, pressed to open the stack.
struct StackCountPill: View {
    let count: Int
    let fill: Color
    let text: Color
    var onTap: () -> Void = {}

    var body: some View {
        Button(action: onTap) {
            Text("\(count)")
                .font(.system(size: 11, weight: .bold).monospacedDigit())
                .foregroundStyle(text)
                .lineLimit(1)
                .padding(.horizontal, 6)
                .frame(minWidth: 19, minHeight: 18)
                .background(Capsule().fill(fill))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.4), lineWidth: 1))
                .shadow(color: Color.black.opacity(0.25), radius: 1.5, y: 0.5)
                .fixedSize()
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { inside in if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() } }
        .help("Show all \(count)")
        .accessibilityLabel(StackToggle.badgeLabel(count: count))
    }
}

// MARK: - Open stack

struct StackRowHeightsKey: PreferenceKey {
    static var defaultValue: [String: CGFloat] = [:]
    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
        value.merge(nextValue()) { _, new in new }
    }
}

/// The open stack: the group's banners newest first, each drawn with its own template and fully live (its url, its
/// actions, its close button act on that notification alone), at most 6 tall (and never taller than the screen
/// leaves room for, `StackModel.maxListHeight`) before the list scrolls, then Collapse and Dismiss all.
struct StackListView: View {
    @ObservedObject var model: BannerModel
    @ObservedObject var stack: StackModel
    /// False in an offscreen render (the preview PNG): `ImageRenderer` cannot draw a scroll view, so the first rows
    /// are drawn and the rest clipped, as the list looks before it is scrolled.
    var scrolls = true
    @State private var rowHeights: [String: CGFloat] = [:]

    /// Rows shown before the list scrolls.
    static let maxVisible = StackListLayout.maxVisible
    static let gap = StackListLayout.gap

    var body: some View {
        let members = stack.members
        let rowAlignment: Alignment = stack.trailing ? .topTrailing : .topLeading
        let list = visibleHeight(members)
        VStack(spacing: Self.gap) {
            let rows = VStack(spacing: Self.gap) {
                ForEach(members) { m in
                    BannerView(model: m.model, isLive: scrolls, reportsHeight: false)
                        .background(GeometryReader { g in
                            Color.clear.preference(key: StackRowHeightsKey.self, value: [m.id: g.size.height])
                        })
                        .frame(width: stack.width, alignment: rowAlignment)
                }
            }
            if scrolls {
                ScrollView(.vertical, showsIndicators: members.count > Self.maxVisible || list.capped) { rows }
                    .frame(width: stack.width, height: list.height)
            } else {
                rows.frame(width: stack.width, height: list.height, alignment: .top).clipped()
            }
            StackFooter(stack: stack)
        }
        .frame(width: stack.width, alignment: .top)
        .fixedSize(horizontal: false, vertical: true)
        .onPreferenceChange(StackRowHeightsKey.self) { rowHeights = $0 }
        .background(GeometryReader { g in Color.clear.preference(key: StackHeightKey.self, value: g.size.height) })
        .onPreferenceChange(StackHeightKey.self) { model.onHeight($0) }
        .onExitCommand { stack.onCollapse() }
    }

    /// Room for the first `maxVisible` rows, from their measured heights (an estimate for a row not measured yet),
    /// held to what the screen leaves (`stack.maxListHeight`).
    private func visibleHeight(_ members: [StackListMember]) -> (height: CGFloat, capped: Bool) {
        StackListLayout.height(rows: members.prefix(Self.maxVisible).map { rowHeights[$0.id] ?? BannerView.estimatedHeight(for: $0.model) },
                               cap: stack.maxListHeight)
    }
}

/// Collapse and Dismiss all, on a card of their own under the list.
private struct StackFooter: View {
    @ObservedObject var stack: StackModel

    var body: some View {
        HStack(spacing: 8) {
            Button { stack.onCollapse() } label: {
                HStack(spacing: 4) { Image(systemName: "chevron.up").font(.system(size: 9, weight: .bold)); Text("Collapse") }
            }
            .buttonStyle(BannerButtonStyle(kind: "default"))
            Spacer(minLength: 4)
            Text("\(stack.count) notifications").font(.caption).foregroundStyle(.secondary).lineLimit(1)
            Spacer(minLength: 4)
            Button { stack.onDismissAll() } label: { Text("Dismiss all") }
                .buttonStyle(BannerButtonStyle(kind: "destructive"))
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .frame(width: stack.width)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.regularMaterial))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
    }
}
