import SwiftUI

/// `button`: one action, inline or by reference to the resolved list. A reference to an action that is not
/// in the list (hidden by a rule, not sent by the issuer) leaves a blank placeholder when kept.
struct ButtonComponentView: View {
    let component: HeraldButtonComponent
    let ctx: GridContext

    var body: some View {
        if let found = ctx.action(inline: component.action, ref: component.actionRef) {
            let label = ctx.label(for: found.action)
            Button { ctx.perform(found.action, found.origin) } label: {
                SymbolLabel(text: GridStyle.shortLabel(label), symbol: found.action.symbol ?? component.symbol, ctx: ctx)
            }
                .buttonStyle(BannerButtonStyle(kind: component.style ?? found.action.style ?? "default", accent: ctx.accent))
                .help(label)
        } else {
            Button(" ") {}.buttonStyle(BannerButtonStyle(kind: "default")).hidden()
        }
    }
}
