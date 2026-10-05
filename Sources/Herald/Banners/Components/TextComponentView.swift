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
                      color: { ctx.color($0) }, links: component.rendersMarkdown, expanded: ctx.expanded)
    }
}

/// True when any text under a view is cut short by its line limit.
struct TextTruncatedKey: PreferenceKey {
    static var defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) { value = value || nextValue() }
}

/// Sits behind a line-limited text and reports whether the same text, at the same width, would be taller without the limit.
private struct TruncationProbe: View {
    let text: AttributedString
    let alignment: TextAlignment

    var body: some View {
        GeometryReader { shown in
            Text(text)
                .multilineTextAlignment(alignment)
                .fixedSize(horizontal: false, vertical: true)
                .hidden()
                .background(GeometryReader { full in
                    Color.clear.preference(key: TextTruncatedKey.self, value: full.size.height > shown.size.height + 1)
                })
                .frame(width: shown.size.width, alignment: .topLeading)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
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
    /// Lifts the line limits (a live banner the user clicked to read in full).
    var expanded = false

    /// Far more lines than a banner holds; "no limit" without changing the layout maths below.
    private static let unlimited = 400

    var body: some View {
        let limit = expanded ? Self.unlimited : max(component.maxLines ?? GridStyle.defaultLines(component.style, body: maxBodyLines), 1)
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
                    let text = attributed(line, base: base)
                    Text(text)
                        .lineLimit(perLine)
                        .multilineTextAlignment(a)
                        .background(TruncationProbe(text: text, alignment: a))
                        .frame(maxWidth: fills ? .infinity : nil, alignment: frameAlignment(a))
                }
            }
        }
        .opacity(resolved == nil ? 0 : 1)
        .frame(maxWidth: fills ? .infinity : nil, alignment: .leading)
        // Whole lines dropped by the limit count as cut short too.
        .preference(key: TextTruncatedKey.self, value: (resolved ?? []).count > limit)
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
            // A link keeps the link colour unless the run names its own.
            let tint = color(r.color)
            for piece in a.runs where piece.link == nil || tint != nil {
                a[piece.range].foregroundColor = tint ?? base
            }
            if r.underline { a.underlineStyle = .single }
            if r.strike { a.strikethroughStyle = .single }
            out += a
        }
        if out.characters.isEmpty { out = AttributedString(" ") }
        return out
    }
}
