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
        glyphImage(tint: tint, side: side)
            .frame(width: side, height: side)
            .background(Circle().fill(Color.primary.opacity(0.08)))
            .contentShape(Circle())
    }

    @ViewBuilder private func glyphImage(tint: Color, side: CGFloat) -> some View {
        let sym = component.fullSymbol
        if SymbolStyle.isDrawable(sym, ctx) {
            SymbolImage(symbol: sym, ctx: ctx, tint: tint, size: side > 18 ? 10 : 9, defaultWeight: .bold)
        } else {
            // An unknown name keeps the old behaviour: a question mark, so a typo still draws something.
            Image(systemName: "questionmark.circle").font(.system(size: side > 18 ? 10 : 9, weight: .bold)).foregroundStyle(tint)
        }
    }
}
