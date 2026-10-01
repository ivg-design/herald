import SwiftUI

/// `timestamp`: a date from a binding (ISO 8601 or epoch seconds), or the banner's own delivery time when the
/// component has no binding. `relative` shows "3 min. ago" and keeps itself current.
struct TimestampComponentView: View {
    let component: HeraldTimestampComponent
    let ctx: GridContext

    var body: some View {
        let font = GridStyle.font(component.style, size: component.fontSize)
        let color = ctx.color(component.color) ?? GridStyle.defaultColor(component.style)
        Group {
            if component.relative, let date = date {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    Text(GridFormat.relative(date, now: context.date))
                }
            } else {
                Text(text)
            }
        }
        .font(font)
        .foregroundStyle(color)
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
    }

    private var binding: String? {
        guard let b = component.binding, !b.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return b
    }

    /// nil when the bound text is not a date (it is then shown as typed).
    private var date: Date? {
        guard let b = binding else { return ctx.deliveredAt }
        guard let s = ctx.bind(b) else { return nil }
        return TemplateResolver.date(from: s)
    }

    private var text: String {
        if let b = binding { return ctx.bind(b).map { s in date.map { GridFormat.absolute($0) } ?? s } ?? " " }
        return GridFormat.absolute(ctx.deliveredAt)
    }
}
