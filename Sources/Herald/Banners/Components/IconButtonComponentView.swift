import SwiftUI

/// `iconButton`: a round button with an SF Symbol. An action that is the built-in snooze (no fixed minutes)
/// opens the snooze menu instead of firing.
struct IconButtonComponentView: View {
    let component: HeraldIconButtonComponent
    let ctx: GridContext

    var body: some View {
        let side = CGFloat(max(component.size ?? 18, 8))
        let tint = ctx.color(component.color) ?? .secondary
        if let found = ctx.action(inline: component.action, ref: component.actionRef) {
            let tip = component.tooltip ?? ctx.label(for: found.action)
            if found.action.kind == .snooze, found.action.snoozeMinutes == nil, ctx.offscreen {
                glyph(side: side, tint: tint)
            } else if found.action.kind == .snooze, found.action.snoozeMinutes == nil {
                Menu {
                    ForEach(SnoozeOption.allCases, id: \.self) { o in Button(o.title) { ctx.snooze(o) } }
                } label: { glyph(side: side, tint: tint) }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                    .help(tip)
            } else {
                Button { ctx.perform(found.action, found.origin) } label: { glyph(side: side, tint: tint) }
                    .buttonStyle(.plain)
                    .help(tip)
                    .accessibilityLabel(tip)
            }
        } else {
            glyph(side: side, tint: tint).hidden()
        }
    }

    private func glyph(side: CGFloat, tint: Color) -> some View {
        Image(systemName: GridStyle.symbol(component.symbol))
            .font(.system(size: side > 18 ? 10 : 9, weight: .bold))
            .foregroundStyle(tint)
            .frame(width: side, height: side)
            .background(Circle().fill(Color.primary.opacity(0.08)))
            .contentShape(Circle())
    }
}
