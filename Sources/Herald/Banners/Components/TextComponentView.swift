import SwiftUI

/// `text`: a binding (or structured `lines`) drawn in one of the five styles. Each line is its own `Text` built
/// from an AttributedString of styled runs, stacked with the component's `lineSpacing`, so a line can have its own
/// alignment. An empty text that is kept (not collapsed) holds one invisible line, so the row keeps its height.
struct TextComponentView: View {
    let component: HeraldTextComponent
    let ctx: GridContext
    let align: HeraldAlign
    /// `emptyBehavior` after the template default: true keeps a line whose tokens are all absent as a blank line.
    var keepEmptyLines: Bool?

    var body: some View {
        RichTextLines(component: component, resolved: component.resolvedLines(fields: ctx.fields, keepEmptyLines: keepEmptyLines ?? (component.emptyBehavior == .keep)),
                      align: align, maxBodyLines: ctx.maxBodyLines,
                      color: { ctx.color($0) }, links: component.rendersMarkdown)
    }
}

/// The drawing half, shared with the Designer's live preview (which has no GridContext).
struct RichTextLines: View {
    let component: HeraldTextComponent
    let resolved: [HeraldResolvedLine]?
    let align: HeraldAlign
    let maxBodyLines: Int
    let color: (String?) -> Color?
    var links = false

    var body: some View {
        let limit = max(component.maxLines ?? GridStyle.defaultLines(component.style, body: maxBodyLines), 1)
        let base = color(component.color) ?? GridStyle.defaultColor(component.style)
        // A text that names its own alignment (or has a line that does) fills the cell's width and aligns inside
        // it; otherwise it hugs its content and the cell's alignment places it.
        let fills = component.alignment != nil || (resolved ?? []).contains { $0.align != nil }
        let cellAlign = component.alignment?.textAlignment ?? align.textAlignment
        let shown = Array((resolved ?? []).prefix(limit))
        // A logical line that wraps may use what the other lines leave of the limit.
        let perLine = max(limit - max(shown.count - 1, 0), 1)
        VStack(alignment: stackAlignment(cellAlign), spacing: CGFloat(component.lineSpacing ?? 0)) {
            if resolved == nil || shown.isEmpty {
                Text(" ").font(GridStyle.font(component.style, size: component.fontSize, weight: component.weight))
            } else {
                ForEach(Array(shown.enumerated()), id: \.offset) { _, line in
                    let a = line.align?.textAlignment ?? cellAlign
                    Text(attributed(line, base: base))
                        .lineLimit(perLine)
                        .multilineTextAlignment(a)
                        .frame(maxWidth: fills ? .infinity : nil, alignment: frameAlignment(a))
                }
            }
        }
        .opacity(resolved == nil ? 0 : 1)
        .frame(maxWidth: fills ? .infinity : nil, alignment: .leading)
    }

    private func stackAlignment(_ a: TextAlignment) -> HorizontalAlignment {
        switch a { case .leading: return .leading; case .center: return .center; case .trailing: return .trailing }
    }
    private func frameAlignment(_ a: TextAlignment) -> Alignment {
        switch a { case .leading: return .leading; case .center: return .center; case .trailing: return .trailing }
    }

    /// One line as an AttributedString: each run carries its font, colour, underline and strike.
    private func attributed(_ line: HeraldResolvedLine, base: Color) -> AttributedString {
        var out = AttributedString()
        for r in line.runs {
            var a = links ? GridMarkdown.parse(r.text) : AttributedString(r.text)
            a.font = GridStyle.runFont(component.style, size: r.size ?? component.fontSize,
                                       weight: r.weight ?? component.weight, family: r.font, italic: r.italic)
            a.foregroundColor = color(r.color) ?? base
            if r.underline { a.underlineStyle = .single }
            if r.strike { a.strikethroughStyle = .single }
            out += a
        }
        if out.characters.isEmpty { out = AttributedString(" ") }
        return out
    }
}
