import SwiftUI
import AppKit

/// `badge`: a small pill with a value, such as an unread count.
struct BadgeComponentView: View {
    let component: HeraldBadgeComponent
    let ctx: GridContext

    var body: some View {
        let bound = ctx.bind(component.binding)
        let fill = ctx.color(component.color ?? "accent", legible: false) ?? .accentColor
        let text = ctx.color(component.textColor, legible: false) ?? GridStyle.contrastingText(on: fillNSColor)
        let drawable = component.symbol.map { SymbolStyle.isDrawable($0, ctx) } ?? false
        let parts = component.parts(symbolDrawable: drawable)
        HStack(spacing: 3) {
            if parts.leadingSymbol, let sym = component.symbol { SymbolImage(symbol: sym, ctx: ctx, tint: text, size: 9.5, defaultWeight: .semibold) }
            if parts.text {
                Text(bound ?? " ")
                    .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
                    .foregroundStyle(text)
                    .lineLimit(1)
            }
            if parts.trailingSymbol, let sym = component.symbol { SymbolImage(symbol: sym, ctx: ctx, tint: text, size: 9.5, defaultWeight: .semibold) }
        }
            .padding(.horizontal, 6).padding(.vertical, 1.5)
            .frame(minWidth: 17)
            .background(Capsule().fill(fill))
            .fixedSize()
            .opacity(bound == nil ? 0 : 1)
    }

    /// The pill colour as an NSColor, to pick a legible text colour. `accent` and keywords have no fixed value.
    private var fillNSColor: NSColor? {
        guard let spec = component.color else { return NSColor.controlAccentColor }
        return BannerModel.color(fromHex: spec) ?? NSColor.controlAccentColor
    }
}
