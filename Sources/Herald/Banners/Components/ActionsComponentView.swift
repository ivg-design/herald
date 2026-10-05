import SwiftUI

/// `actions`: every resolved action from `source` as capsule buttons, in `row` (one line), `wrap` (flows onto
/// further lines) or `stack` (one per line). `maxVisible` caps the buttons; the rest sit behind a "+N" menu.
/// The built-in extras of a v1 banner live here too: the snooze menu pinned to the trailing edge and the
/// Add to Reminders button after the last action.
struct ActionsComponentView: View {
    let component: HeraldActionsComponent
    let ctx: GridContext
    /// The cell's 9-point alignment: the row's alignment when the component sets none.
    var cellAlign: HeraldAlign = .topLeading
    private var align: HeraldActionsAlign { component.effectiveAlign(in: cellAlign) }

    /// The extras only belong to the issuer's side of the list, never to a template-only action row.
    private var includesExtras: Bool { component.source != .template }

    /// What this cell shows: the actions the template's assignment gave it (`include`, or whatever no other cell
    /// claims), else, with no assignment, every action of `source`.
    private var listed: [HeraldResolvedAction] {
        (ctx.cellActions ?? ctx.actions).filter { component.source.includes($0.origin) }
    }
    /// A snooze action with no fixed minutes is the menu, not a button.
    private var hasSnoozeMenu: Bool { listed.contains(where: Self.isSnoozeMenu) }
    private var buttons: [HeraldResolvedAction] { listed.filter { !Self.isSnoozeMenu($0) } }
    private var showsReminder: Bool { includesExtras && ctx.notification.reminder != nil }

    static func isSnoozeMenu(_ r: HeraldResolvedAction) -> Bool {
        r.action.kind == .snooze && r.action.snoozeMinutes == nil
    }

    var body: some View {
        if buttons.isEmpty && !hasSnoozeMenu && !showsReminder {
            Color.clear.frame(width: 0, height: Self.buttonHeight)   // a kept, empty row holds one button's height
        } else {
            HStack(alignment: .top, spacing: gap) {
                flow.frame(maxWidth: .infinity, alignment: .leading)
                if hasSnoozeMenu { snoozeMenu }
            }
        }
    }

    static let buttonHeight: CGFloat = 24

    // MARK: Layouts

    private var visibleCount: Int { ActionOverflow.visibleCount(total: buttons.count, maxVisible: component.maxVisible) }

    private var gap: CGFloat { CGFloat(component.effectiveSpacing) }

    @ViewBuilder private var flow: some View {
        switch component.layout {
        case .stack:
            VStack(alignment: align.horizontal, spacing: gap) { items(visible: visibleCount) }
                .frame(maxWidth: .infinity, alignment: align.frame)
        case .wrap, .row:
            if component.wraps {
                ActionRowLayout(spacing: gap, lineSpacing: gap, wrap: true, align: align) {
                    items(visible: visibleCount)
                }
            } else {
                // The first variant that fits the width wins: all the buttons, else one fewer plus "+N", and so on.
                ViewThatFits(in: .horizontal) {
                    ForEach(Array(stride(from: visibleCount, through: 0, by: -1)), id: \.self) { k in
                        ActionRowLayout(spacing: gap, lineSpacing: gap, wrap: false, align: align) {
                            items(visible: k)
                        }
                    }
                }
            }
        }
    }

    /// The first `visible` buttons, then the "+N" menu for the rest of the list, then Add to Reminders.
    @ViewBuilder private func items(visible: Int) -> some View {
        ForEach(Array(buttons.prefix(visible).enumerated()), id: \.offset) { _, r in actionButton(r) }
        if visible < buttons.count { overflowMenu(Array(buttons.dropFirst(visible))) }
        if showsReminder { ReminderButton(state: ctx.reminderState, action: ctx.addReminder) }
    }

    private func actionButton(_ r: HeraldResolvedAction) -> some View {
        let label = ctx.label(for: r.action)
        return Button { ctx.perform(r.action, r.origin) } label: {
            SymbolLabel(text: GridStyle.shortLabel(label), symbol: r.action.symbol ?? component.symbol, ctx: ctx)
        }
            .buttonStyle(BannerButtonStyle(kind: r.action.style ?? "default", accent: ctx.accent))
            .help(label)
    }

    /// Documentation screenshots (Debug only): a live menu draws just its text offscreen, so the capsule label stands in.
    private static var captureStandIn: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.environment["HERALD_SCREENSHOTS"]?.isEmpty == false
        #else
        return false
        #endif
    }

    private func overflowLabel(_ hidden: Int) -> some View {
        Text(ActionOverflow.menuTitle(hidden: hidden))
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(Capsule().fill(Color.secondary.opacity(0.12)))
    }

    @ViewBuilder private func overflowMenu(_ hidden: [HeraldResolvedAction]) -> some View {
        if ctx.offscreen || Self.captureStandIn { overflowLabel(hidden.count) } else { liveOverflowMenu(hidden) }

    }

    private func liveOverflowMenu(_ hidden: [HeraldResolvedAction]) -> some View {
        Menu {
            ForEach(Array(hidden.enumerated()), id: \.offset) { _, r in
                Button(role: r.action.style == "destructive" ? .destructive : nil) {
                    ctx.perform(r.action, r.origin)
                } label: { Text(ctx.label(for: r.action)) }
            }
        } label: {
            overflowLabel(hidden.count)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("\(hidden.count) more")
    }

    private var snoozeLabel: some View { Text("\u{23F0}").font(.system(size: 13)) }

    @ViewBuilder private var snoozeMenu: some View {
        if ctx.offscreen { snoozeLabel } else { liveSnoozeMenu }
    }

    private var liveSnoozeMenu: some View {
        Menu {
            ForEach(SnoozeOption.allCases, id: \.self) { o in Button(o.title) { ctx.snooze(o) } }
        } label: {
            snoozeLabel
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Snooze")
    }
}

/// Add to Reminders, with its working / added / failed states (the v1 button).
struct ReminderButton: View {
    let state: ReminderState
    let action: () -> Void

    var body: some View {
        switch state {
        case .idle, .working:
            Button("Add to Reminders", action: action).buttonStyle(BannerButtonStyle(kind: "cancel"))
        case .added:
            Text("Added to Reminders \u{2713}").font(.system(size: 11)).foregroundStyle(.secondary)
                .lineLimit(1).fixedSize()
        case .failed(let message):
            Button("Reminders unavailable", action: action)
                .buttonStyle(BannerButtonStyle(kind: "destructive")).help(message)
        }
    }
}


extension HeraldActionsAlign {
    var horizontal: HorizontalAlignment {
        switch self {
        case .leading, .spaceBetween: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }
    var frame: Alignment {
        switch self {
        case .leading, .spaceBetween: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }
}

/// Lays the buttons of an `actions` cell out with `ActionRowMath`: left to right, onto further lines when `wrap`
/// is on and they do not fit, each line placed by `align`. With a width to fill, a non-leading alignment takes all
/// of it so the buttons can sit against the trailing edge or the middle.
struct ActionRowLayout: Layout {
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat = 6
    var wrap = true
    var align: HeraldActionsAlign = .leading

    private func result(_ subviews: Subviews, width: CGFloat?) -> ActionRowMath.Result {
        ActionRowMath.arrange(sizes: subviews.map { $0.sizeThatFits(.unspecified) }, width: width,
                              spacing: spacing, lineSpacing: lineSpacing, wrap: wrap, align: align)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        result(subviews, width: proposal.width).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let r = result(subviews, width: bounds.width)
        for (i, f) in r.frames.enumerated() {
            subviews[i].place(at: CGPoint(x: bounds.minX + f.minX, y: bounds.minY + f.minY), anchor: .topLeading,
                              proposal: .unspecified)
        }
    }
}
