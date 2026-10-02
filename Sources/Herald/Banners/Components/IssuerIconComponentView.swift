import SwiftUI

/// `issuerIcon`: the sending app's icon, round or rounded-square.
struct IssuerIconComponentView: View {
    let component: HeraldIssuerIconComponent
    let ctx: GridContext

    var body: some View {
        let side = CGFloat(max(component.size, 1))
        if let sym = component.symbol, SymbolStyle.isDrawable(sym, ctx) {
            SymbolImage(symbol: sym, ctx: ctx, tint: .primary, size: side * 0.62)
                .frame(width: side, height: side)
                .help(ctx.appName)
        } else {
            appIcon(side: side)
        }
    }

    @ViewBuilder private func appIcon(side: CGFloat) -> some View {
        let img = Image(nsImage: ctx.icon).resizable().interpolation(.high).frame(width: side, height: side)
        Group {
            switch component.shape {
            case .circle:
                img.clipShape(Circle())
            case .rounded:
                img.clipShape(RoundedRectangle(cornerRadius: CGFloat(component.cornerRadius ?? component.size * 0.22),
                                               style: .continuous))
            }
        }
        .help(ctx.appName)
    }
}
