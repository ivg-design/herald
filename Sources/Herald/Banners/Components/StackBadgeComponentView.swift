import SwiftUI
import AppKit

/// `stackBadge`: the pill that shows `{stack.count}`, drawn like a `badge`. It is empty (invisible, and it collapses
/// by the template's rules) while the banner is alone; on a stack's top card a click opens the stack in place, which
/// never activates Herald (DESIGN section 8).
struct StackBadgeComponentView: View {
    let component: HeraldStackBadgeComponent
    let ctx: GridContext

    var body: some View {
        let live = ctx.stackCount > 1
        BadgeComponentView(component: component.asBadge, ctx: ctx)
            .contentShape(Capsule())
            .onTapGesture { if live { ctx.expandStack() } }
            .allowsHitTesting(live)
            .help(live ? "Show all \(ctx.stackCount)" : "")
    }
}
