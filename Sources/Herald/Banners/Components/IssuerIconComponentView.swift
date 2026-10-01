import SwiftUI

/// `issuerIcon`: the sending app's icon, round or rounded-square.
struct IssuerIconComponentView: View {
    let component: HeraldIssuerIconComponent
    let ctx: GridContext

    var body: some View {
        let side = CGFloat(max(component.size, 1))
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
