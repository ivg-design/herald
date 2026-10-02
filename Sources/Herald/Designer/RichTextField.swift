import SwiftUI
import AppKit

// The Designer's rich text editor (issue #64): a multi-line field showing the markup, a formatting bar that acts on
// the selection, a per-line alignment control and a live rendered preview. The edits themselves are the pure
// functions in HeraldRichText (unit-tested); this file only wires them to an NSTextView.

/// Holds the text view so the bar can read the selection and apply edits to it.
@MainActor
final class RichTextController: ObservableObject {
    weak var textView: NSTextView?
    /// The alignment written on the caret's line, for the segmented control.
    @Published var caretAlign: HeraldTextAlignment?
    var onChange: (String) -> Void = { _ in }

    var text: String { textView?.string ?? "" }
    var selection: NSRange { textView?.selectedRange() ?? NSRange(location: 0, length: 0) }

    func apply(_ edit: HeraldRichText.Edit) {
        guard let tv = textView else { return }
        if tv.string != edit.text { tv.string = edit.text }
        tv.setSelectedRange(edit.selection)
        onChange(edit.text)
        refreshCaret()
    }

    func refreshCaret() {
        let a = HeraldRichText.align(in: text, caret: selection.location)
        if a != caretAlign { caretAlign = a }
    }

    func toggle(_ m: HeraldRichText.Mark) { apply(HeraldRichText.toggle(m, in: text, selection: selection)) }
    func step(_ delta: Double, base: Double) { apply(HeraldRichText.stepSize(by: delta, base: base, in: text, selection: selection)) }
    func color(_ hex: String?) { apply(HeraldRichText.setSpan("color", to: hex, in: text, selection: selection)) }
    func align(_ a: HeraldTextAlignment?) { apply(HeraldRichText.setAlign(a, in: text, caret: selection.location)) }
    func insertToken(_ key: String) { apply(HeraldRichText.insertToken(key, in: text, selection: selection)) }
}

/// A plain NSTextView in a scroll view: Enter and Option-Enter insert a line break, Command-Enter finishes editing.
struct RichTextEditorView: NSViewRepresentable {
    let initial: String
    /// The text the model currently holds, to follow outside changes (undo, another cell) while not editing.
    let external: String
    let controller: RichTextController

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.drawsBackground = true
        let tv = NSTextView()
        tv.isRichText = false
        tv.allowsUndo = true
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        tv.textContainerInset = NSSize(width: 4, height: 4)
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]
        tv.textContainer?.widthTracksTextView = true
        tv.string = initial
        tv.delegate = context.coordinator
        scroll.documentView = tv
        controller.textView = tv
        controller.refreshCaret()
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let tv = scroll.documentView as? NSTextView else { return }
        controller.textView = tv
        context.coordinator.controller = controller
        let editing = tv.window?.firstResponder === tv
        if !editing, tv.string != external { tv.string = external; controller.refreshCaret() }
    }

    func makeCoordinator() -> Coordinator { Coordinator(controller) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var controller: RichTextController
        init(_ c: RichTextController) { controller = c }

        func textDidChange(_ n: Notification) {
            guard let tv = n.object as? NSTextView else { return }
            controller.onChange(tv.string)
            controller.refreshCaret()
        }

        func textViewDidChangeSelection(_ n: Notification) { controller.refreshCaret() }

        func textView(_ tv: NSTextView, doCommandBy sel: Selector) -> Bool {
            if sel == #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)) {   // Option-Enter
                tv.insertText("\n", replacementRange: tv.selectedRange())
                return true
            }
            if sel == #selector(NSResponder.insertNewline(_:)) {
                if NSApp.currentEvent?.modifierFlags.contains(.command) == true {    // Command-Enter commits
                    controller.onChange(tv.string)
                    tv.window?.makeFirstResponder(nil)
                    return true
                }
                tv.insertText("\n", replacementRange: tv.selectedRange())
                return true
            }
            return false
        }
    }
}

/// The inspector's "Text" block of the text component.
struct RichTextField: View {
    @ObservedObject var model: DesignerModel
    let id: String
    @StateObject private var controller = RichTextController()
    @Environment(\.colorScheme) private var scheme

    private static let swatches: [(String, String)] = [
        ("Accent", "accent"), ("Primary", "primary"), ("Secondary", "secondary"),
        ("Red", "#FF3B30"), ("Orange", "#FF9500"), ("Green", "#34C759"), ("Blue", "#0A84FF"), ("Purple", "#AF52DE"), ("Gray", "#8E8E93"),
    ]

    private var component: HeraldTextComponent? {
        if case .text(let p)? = model.draft.cell(withID: id)?.component { return p }
        return nil
    }

    /// What the field shows for the model's text.
    private var markup: String {
        guard let p = component else { return "" }
        if let lines = p.lines { return HeraldRichText.markup(for: lines) }
        return p.binding
    }

    /// Stores the typed markup: structured `lines` when anything is styled, else the plain `binding`.
    private func commit(_ text: String) {
        model.updateCell(id) { cell in
            guard case .text(var p) = cell.component else { return }
            let parsed = HeraldRichText.parse(text).lines
            if HeraldRichText.hasStyling(parsed) {
                p.lines = parsed
                p.binding = HeraldRichText.plainText(parsed)
            } else {
                p.lines = nil
                p.binding = text
            }
            cell.component = .text(p)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            bar
            RichTextEditorView(initial: markup, external: markup, controller: controller)
                .frame(height: 76).heraldHelp(.designerRichEditor)
            Text("Return: new line  \u{00B7}  \u{2318}Return: done").font(.caption2).foregroundStyle(.tertiary)
            preview
        }
        .onAppear { controller.onChange = { commit($0) } }
        .id(id)
    }

    private var bar: some View {
        let base = component.map { $0.fontSize ?? GridStyle.baseSize($0.style) } ?? 12
        return HStack(spacing: 2) {
            barButton("bold", .designerRichBold) { controller.toggle(.bold) }
            barButton("italic", .designerRichItalic) { controller.toggle(.italic) }
            barButton("chevron.left.forwardslash.chevron.right", .designerRichMono) { controller.toggle(.mono) }
            barButton("underline", .designerRichUnderline) { controller.toggle(.underline) }
            barButton("strikethrough", .designerRichStrike) { controller.toggle(.strike) }
            Divider().frame(height: 14)
            barButton("textformat.size.smaller", .designerRichSizeDown) { controller.step(-1, base: base) }
            barButton("textformat.size.larger", .designerRichSizeUp) { controller.step(1, base: base) }
            Menu {
                ForEach(Self.swatches, id: \.1) { name, value in Button(name) { controller.color(value) } }
                Divider()
                Button("No colour") { controller.color(nil) }
            } label: { Image(systemName: "paintpalette") }
                .menuStyle(.borderlessButton).fixedSize().heraldHelp(.designerRichColor)
            Divider().frame(height: 14)
            Picker("", selection: Binding(get: { controller.caretAlign }, set: { controller.align($0) })) {
                Text("Cell").tag(HeraldTextAlignment?.none)
                Image(systemName: "text.alignleft").tag(HeraldTextAlignment?.some(.leading))
                Image(systemName: "text.aligncenter").tag(HeraldTextAlignment?.some(.center))
                Image(systemName: "text.alignright").tag(HeraldTextAlignment?.some(.trailing))
            }.pickerStyle(.segmented).labelsHidden().fixedSize().heraldHelp(.designerRichLineAlign)
            Spacer(minLength: 0)
            TokenMenu(model: model) { picked in controller.insertToken(String(picked.dropFirst().dropLast())) }
        }
    }

    private func barButton(_ symbol: String, _ help: HelpEntry, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).frame(width: 18, height: 16) }
            .buttonStyle(.borderless).heraldHelp(help)
    }

    @ViewBuilder private var preview: some View {
        if let p = component {
            RichTextLines(component: p, resolved: p.resolvedLines(fields: model.previewFields, keepEmptyLines: p.emptyBehavior == .keep),
                          align: .topLeading, maxBodyLines: 8,
                          color: { GridStyle.color($0, accent: nil, scheme: scheme) }, links: p.rendersMarkdown)
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.06)))
        }
    }
}
