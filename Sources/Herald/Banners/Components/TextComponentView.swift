import SwiftUI

/// `text`: a binding drawn in one of the five styles. An empty text that is kept (not collapsed) holds one
/// invisible line, so the row keeps its height.
struct TextComponentView: View {
    let component: HeraldTextComponent
    let ctx: GridContext
    let align: HeraldAlign

    var body: some View {
        let bound = ctx.bind(component.binding)
        let lines = max(component.maxLines ?? GridStyle.defaultLines(component.style, body: ctx.maxBodyLines), 1)
        let color = ctx.color(component.color) ?? GridStyle.defaultColor(component.style)
        // A text that names its own alignment fills the cell's width and aligns inside it; otherwise it hugs
        // its content and the cell's alignment places it.
        let lineAlign = component.alignment?.textAlignment ?? align.textAlignment
        label(bound)
            .font(GridStyle.font(component.style, size: component.fontSize, weight: component.weight))
            .foregroundStyle(color)
            .lineLimit(lines)
            .multilineTextAlignment(lineAlign)
            .opacity(bound == nil ? 0 : 1)
            .frame(maxWidth: component.alignment == nil ? nil : .infinity,
                   alignment: component.alignment?.alignment ?? .leading)
    }

    @ViewBuilder private func label(_ bound: String?) -> some View {
        if let bound {
            if component.rendersMarkdown { Text(GridMarkdown.parse(bound)) } else { Text(bound) }
        } else {
            Text(" ")
        }
    }
}
