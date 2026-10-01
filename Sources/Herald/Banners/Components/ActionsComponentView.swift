import SwiftUI

/// `actions`: every resolved action from `source` as capsule buttons, in `row` (one line), `wrap` (flows onto
/// further lines) or `stack` (one per line). `maxVisible` caps the buttons; the rest sit behind a "+N" menu.
/// The built-in extras of a v1 banner live here too: the snooze menu pinned to the trailing edge and the
/// Add to Reminders button after the last action.
struct ActionsComponentView: View {
    let component: HeraldActionsComponent
    let ctx: GridContext

    /// The extras only belong to the issuer's side of the list, never to a template-only action row.
    private var includesExtras: Bool { component.source != .template }

    private var listed: [HeraldResolvedAction] { ctx.actions.filter { component.source.includes($0.origin) } }
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
            HStack(alignment: .top, spacing: 6) {
                flow.frame(maxWidth: .infinity, alignment: .leading)
                if hasSnoozeMenu { snoozeMenu }
            }
        }
    }

    static let buttonHeight: CGFloat = 24

    // MARK: Layouts

    private var visibleCount: Int { ActionOverflow.visibleCount(total: buttons.count, maxVisible: component.maxVisible) }

    @ViewBuilder private var flow: some View {
        switch component.layout {
        case .wrap:
            FlowLayout(spacing: 6, lineSpacing: 6) { items(visible: visibleCount) }
        case .stack:
            VStack(alignment: .leading, spacing: 6) { items(visible: visibleCount) }
        case .row:
            // The first variant that fits the width wins: all the buttons, else one fewer plus "+N", and so on.
            ViewThatFits(in: .horizontal) {
                ForEach(Array(stride(from: visibleCount, through: 0, by: -1)), id: \.self) { k in
                    HStack(spacing: 6) { items(visible: k) }.fixedSize()
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
        return Button(GridStyle.shortLabel(label)) { ctx.perform(r.action, r.origin) }
            .buttonStyle(BannerButtonStyle(kind: r.action.style ?? "default", accent: ctx.accent))
            .help(label)
    }

    private func overflowLabel(_ hidden: Int) -> some View {
        Text(ActionOverflow.menuTitle(hidden: hidden))
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(Capsule().fill(Color.secondary.opacity(0.12)))
    }

    @ViewBuilder private func overflowMenu(_ hidden: [HeraldResolvedAction]) -> some View {
        if ctx.offscreen { overflowLabel(hidden.count) } else { liveOverflowMenu(hidden) }
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
