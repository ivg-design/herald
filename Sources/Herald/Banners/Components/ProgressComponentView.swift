import SwiftUI

/// `progress`: a thin bar. The bound value is a fraction (0 to 1), or a percentage when it is above 1.
struct ProgressComponentView: View {
    let component: HeraldProgressComponent
    let ctx: GridContext

    var body: some View {
        let fraction = ctx.bind(component.binding).flatMap(GridFormat.progressFraction)
        let height = CGFloat(max(component.height ?? 4, 1))
        let tint = ctx.color(component.color ?? "accent") ?? .accentColor
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.12))
                Capsule().fill(tint).frame(width: g.size.width * CGFloat(fraction ?? 0))
            }
        }
        .frame(minWidth: 40, idealWidth: 120, minHeight: height, maxHeight: height)
        .opacity(fraction == nil ? 0 : 1)
        .accessibilityValue(fraction.map { "\(Int($0 * 100)) percent" } ?? "")
    }
}
