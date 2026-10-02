import SwiftUI

/// `button`: one action, inline or by reference to the resolved list. A reference to an action that is not
/// in the list (hidden by a rule, not sent by the issuer, or drawn by an earlier cell) leaves a blank
/// placeholder when kept.
struct ButtonComponentView: View {
    let component: HeraldButtonComponent
    let ctx: GridContext

    /// The action as pressed: the button's own `style` wins over its action's and travels with the press, so a
    /// `destructive` button is asked about before anything runs.
    private func pressed(_ action: HeraldAction) -> HeraldAction {
        var a = action
        if let style = component.style { a.style = style }
        return a
    }

    var body: some View {
        if let found = ctx.action(inline: component.action, ref: component.actionRef) {
            let label = ctx.label(for: found.action)
            let action = pressed(found.action)
            Button { ctx.perform(action, found.origin) } label: {
                SymbolLabel(text: GridStyle.shortLabel(label), symbol: found.action.symbol ?? component.symbol, ctx: ctx)
            }
                .buttonStyle(BannerButtonStyle(kind: action.style ?? "normal", accent: ctx.accent))
                .help(label)
        } else {
            Button(" ") {}.buttonStyle(BannerButtonStyle(kind: "normal")).hidden()
        }
    }
}
