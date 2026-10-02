import SwiftUI
import AppKit

// The Designer's right column: Cell (position, span, alignment, the component's properties, bindings with a
// token picker, what it does when empty), Template (name, accent, collapse empty fields or leave them in
// place, grid and tracks) and Actions (ActionEditorView). Also the small form widgets they share.

struct InspectorView: View {
    @ObservedObject var model: DesignerModel
    var width: CGFloat = 340

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $model.tab) {
                ForEach(DesignerTab.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden().padding(10)
            Divider()
            ScrollView {
                content.padding(12).frame(width: width, alignment: .leading)
            }
        }
        .frame(width: width)
        .clipped()
    }

    @ViewBuilder private var content: some View {
        switch model.tab {
        case .cell: CellInspector(model: model)
        case .template: TemplateInspector(model: model)
        case .actions: ActionEditorView(model: model)
        }
    }
}

// MARK: - Shared widgets

struct InspectorSection<Content: View>: View {
    let title: String
    var hint: String?
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PaletteHeader(title: title, hint: hint)
            content()
        }
    }
}

struct FieldRow<Content: View>: View {
    let label: String
    @ViewBuilder var content: () -> Content
    init(_ label: String, @ViewBuilder content: @escaping () -> Content) { self.label = label; self.content = content }
    var body: some View {
        HStack(spacing: 6) {
            Text(label).font(.caption).foregroundStyle(.secondary).frame(width: 66, alignment: .leading)
            content()
            Spacer(minLength: 0)
        }
    }
}

/// Inserts a field token. The list is the manifest's fields, the standard keys, your extra values, keys seen
/// in real notifications and custom ones; "Custom token" adds a new one.
struct TokenMenu: View {
    @ObservedObject var model: DesignerModel
    let onPick: (String) -> Void

    var body: some View {
        let all = model.tokenSuggestions
        Menu {
            ForEach([TokenSuggestion.Group.issuer, .standard, .extra, .seen, .custom], id: \.rawValue) { g in
                let items = all.filter { $0.group == g }
                if !items.isEmpty {
                    Section(g.rawValue) {
                        ForEach(items) { t in
                            Button { onPick(t.token) } label: {
                                if let s = t.sample, !s.isEmpty { Text("\(t.token)   \(s.prefix(30))") } else { Text(t.token) }
                            }
                        }
                    }
                }
            }
            Divider()
            Button("Custom token\u{2026}") {
                if let k = DesignerAlerts.prompt(title: "Custom token", message: "The name of a key the issuer sends, for example customer.name",
                                                 placeholder: "key"), DesignerModel.isTokenName(k.trimmingCharacters(in: CharacterSet(charactersIn: "{} "))) {
                    let key = k.trimmingCharacters(in: CharacterSet(charactersIn: "{} "))
                    model.addCustomToken(key)
                    onPick("{\(key)}")
                }
            }
        } label: { Image(systemName: "curlybraces") }
            .menuStyle(.borderlessButton).fixedSize().heraldHelp(.designerInsertField)
    }
}

/// A binding text field with a token menu; picking a token replaces a blank or single-token text and is
/// appended to anything longer.
struct TokenTextField: View {
    @ObservedObject var model: DesignerModel
    let title: String
    @Binding var text: String
    var multiline = false

    var body: some View {
        HStack(alignment: .top, spacing: 4) {
            TextField(title, text: $text, axis: multiline ? .vertical : .horizontal)
                .lineLimit(multiline ? 1...4 : 1...1).heraldHelp(.designerFieldBinding)
                .font(.system(size: 12, design: .monospaced))
                .textFieldStyle(.roundedBorder)
            TokenMenu(model: model) { picked in
                let key = String(picked.dropFirst().dropLast())
                text = DesignerPalette.binding(text, adding: key)
            }
        }
    }
}

struct NumberField: View {
    @Binding var value: Double
    var range: ClosedRange<Double> = 0...4000
    var width: CGFloat = 54
    var body: some View {
        HStack(spacing: 2) {
            TextField("", value: Binding(get: { value }, set: { value = min(max($0, range.lowerBound), range.upperBound) }), format: .number)
                .multilineTextAlignment(.trailing).frame(width: width).textFieldStyle(.roundedBorder)
            Stepper("", value: Binding(get: { value }, set: { value = min(max($0, range.lowerBound), range.upperBound) }), in: range)
                .labelsHidden()
        }
    }
}

/// A number that may be unset (empty field = nil).
struct OptionalNumberField: View {
    @Binding var value: Double?
    var placeholder = "auto"
    var width: CGFloat = 64
    @State private var text = ""

    private static func format(_ v: Double?) -> String {
        guard let v else { return "" }
        return v == v.rounded() ? String(Int(v)) : String(v)
    }

    var body: some View {
        TextField("", text: $text, prompt: Text(placeholder))
            .multilineTextAlignment(.trailing).frame(width: width).textFieldStyle(.roundedBorder)
            .onAppear { text = Self.format(value) }
            .onChange(of: text) { t in
                let s = t.trimmingCharacters(in: .whitespaces)
                if s.isEmpty { if value != nil { value = nil } }
                else if let d = Double(s), d.isFinite, d != value { value = d }
            }
            .onChange(of: value) { v in
                if Double(text.trimmingCharacters(in: .whitespaces)) != v, !(v == nil && text.trimmingCharacters(in: .whitespaces).isEmpty) {
                    text = Self.format(v)
                }
            }
    }
}

struct OptionalIntField: View {
    @Binding var value: Int?
    var placeholder = "auto"
    var body: some View {
        OptionalNumberField(value: Binding(get: { value.map(Double.init) },
                                           set: { value = $0.map { max(1, Int($0)) } }), placeholder: placeholder)
    }
}

struct OptionalPicker<T: Hashable>: View {
    @Binding var selection: T?
    let options: [(value: T, label: String)]
    var noneLabel = "Auto"
    var body: some View {
        Picker("", selection: $selection) {
            Text(noneLabel).tag(Optional<T>.none)
            ForEach(options.indices, id: \.self) { Text(options[$0].label).tag(Optional(options[$0].value)) }
        }
        .labelsHidden().fixedSize()
    }
}

/// A colour: hex, or one of the keywords the renderer knows. nil follows the style's own colour.
struct ColorFieldRow: View {
    @Binding var value: String?
    var keywords = true
    var autoLabel = "Auto"
    @State private var hex = ""

    private enum Mode: Hashable { case auto, accent, primary, secondary, custom }

    private var mode: Mode {
        switch value {
        case nil: return .auto
        case "accent"?: return .accent
        case "primary"?: return .primary
        case "secondary"?: return .secondary
        default: return .custom
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Picker("", selection: Binding(get: { mode }, set: setMode)) {
                Text(autoLabel).tag(Mode.auto)
                if keywords {
                    Text("Accent").tag(Mode.accent); Text("Primary").tag(Mode.primary); Text("Secondary").tag(Mode.secondary)
                }
                Text("Custom").tag(Mode.custom)
            }.heraldHelp(.designerColorMode)
            .labelsHidden().fixedSize()
            if mode == .custom {
                ColorPicker("", selection: Binding(get: { ComposerColorRow.color(value ?? "") ?? .accentColor },
                                                   set: { value = ComposerColorRow.hex($0); hex = value ?? "" }), supportsOpacity: false)
                    .labelsHidden().heraldHelp(.designerColorWell)
                TextField("#RRGGBB", text: $hex).textFieldStyle(.roundedBorder).font(.system(size: 11, design: .monospaced)).heraldHelp(.designerColorHex)
                    .frame(width: 84)
                    .onChange(of: hex) { h in
                        let t = h.trimmingCharacters(in: .whitespaces)
                        if HeraldTemplate.isValidColor(t, allowKeywords: false), t != value { value = t }
                    }
            }
        }
        .onAppear { hex = value ?? "" }
        .onChange(of: value) { v in if let v, mode == .custom, v != hex, HeraldTemplate.isValidColor(hex, allowKeywords: false) == false || hex.isEmpty { hex = v } }
    }

    private func setMode(_ m: Mode) {
        switch m {
        case .auto: value = nil
        case .accent: value = "accent"
        case .primary: value = "primary"
        case .secondary: value = "secondary"
        case .custom:
            if mode != .custom { value = "#0A84FF"; hex = "#0A84FF" }
        }
    }
}

/// The nine alignment points of a cell.
struct AlignmentGrid: View {
    @Binding var selection: HeraldAlign
    private let rows: [[HeraldAlign]] = [[.topLeading, .top, .topTrailing], [.leading, .center, .trailing],
                                         [.bottomLeading, .bottom, .bottomTrailing]]
    var body: some View {
        VStack(spacing: 3) {
            ForEach(rows.indices, id: \.self) { r in
                HStack(spacing: 3) {
                    ForEach(rows[r], id: \.self) { a in
                        Button { selection = a } label: {
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(selection == a ? Color.accentColor : Color.secondary.opacity(0.18))
                                .frame(width: 22, height: 18)
                                .overlay(Circle().fill(selection == a ? Color.white : Color.secondary.opacity(0.55)).frame(width: 5, height: 5))
                        }
                        .buttonStyle(.plain).heraldHelp(.designerAlignPoint)
                    }
                }
            }
        }
    }
}

// MARK: - Typed access to a cell's component

/// Binds one property of a cell's component payload (`HeraldTextComponent.style`, ...) to a control.
@MainActor
struct PayloadBinder<P> {
    let model: DesignerModel
    let id: String
    let extract: (HeraldComponent) -> P?
    let embed: (P) -> HeraldComponent

    func binding<T>(_ kp: WritableKeyPath<P, T>, _ fallback: T) -> Binding<T> {
        Binding(
            get: { model.draft.cell(withID: id).flatMap { extract($0.component) }.map { $0[keyPath: kp] } ?? fallback },
            set: { v in
                model.updateCell(id) { cell in
                    guard var p = extract(cell.component) else { return }
                    p[keyPath: kp] = v
                    cell.component = embed(p)
                }
            })
    }
}

extension PayloadBinder where P == HeraldTextComponent {
    static func of(_ m: DesignerModel, _ id: String) -> Self { .init(model: m, id: id, extract: { if case .text(let p) = $0 { return p }; return nil }, embed: { .text($0) }) }
}
extension PayloadBinder where P == HeraldImageComponent {
    static func of(_ m: DesignerModel, _ id: String) -> Self { .init(model: m, id: id, extract: { if case .image(let p) = $0 { return p }; return nil }, embed: { .image($0) }) }
}
extension PayloadBinder where P == HeraldIssuerIconComponent {
    static func of(_ m: DesignerModel, _ id: String) -> Self { .init(model: m, id: id, extract: { if case .issuerIcon(let p) = $0 { return p }; return nil }, embed: { .issuerIcon($0) }) }
}
extension PayloadBinder where P == HeraldTimestampComponent {
    static func of(_ m: DesignerModel, _ id: String) -> Self { .init(model: m, id: id, extract: { if case .timestamp(let p) = $0 { return p }; return nil }, embed: { .timestamp($0) }) }
}
extension PayloadBinder where P == HeraldButtonComponent {
    static func of(_ m: DesignerModel, _ id: String) -> Self { .init(model: m, id: id, extract: { if case .button(let p) = $0 { return p }; return nil }, embed: { .button($0) }) }
}
extension PayloadBinder where P == HeraldActionsComponent {
    static func of(_ m: DesignerModel, _ id: String) -> Self { .init(model: m, id: id, extract: { if case .actions(let p) = $0 { return p }; return nil }, embed: { .actions($0) }) }
}
extension PayloadBinder where P == HeraldIconButtonComponent {
    static func of(_ m: DesignerModel, _ id: String) -> Self { .init(model: m, id: id, extract: { if case .iconButton(let p) = $0 { return p }; return nil }, embed: { .iconButton($0) }) }
}
extension PayloadBinder where P == HeraldBadgeComponent {
    static func of(_ m: DesignerModel, _ id: String) -> Self { .init(model: m, id: id, extract: { if case .badge(let p) = $0 { return p }; return nil }, embed: { .badge($0) }) }
}
extension PayloadBinder where P == HeraldStackBadgeComponent {
    static func of(_ m: DesignerModel, _ id: String) -> Self { .init(model: m, id: id, extract: { if case .stackBadge(let p) = $0 { return p }; return nil }, embed: { .stackBadge($0) }) }
}
extension PayloadBinder where P == HeraldProgressComponent {
    static func of(_ m: DesignerModel, _ id: String) -> Self { .init(model: m, id: id, extract: { if case .progress(let p) = $0 { return p }; return nil }, embed: { .progress($0) }) }
}
extension PayloadBinder where P == HeraldRiveComponent {
    static func of(_ m: DesignerModel, _ id: String) -> Self { .init(model: m, id: id, extract: { if case .rive(let p) = $0 { return p }; return nil }, embed: { .rive($0) }) }
}

// MARK: - Cell tab

struct CellInspector: View {
    @ObservedObject var model: DesignerModel

    var body: some View {
        if let cell = model.selectedCell {
            CellEditor(model: model, cell: cell).id(cell.id)
        } else if let sel = model.selection {
            VStack(alignment: .leading, spacing: 12) {
                Label(sel.area == 1 ? "Empty slot" : "\(sel.area) slots selected", systemImage: "square.dashed").font(.headline)
                Text(sel.area == 1
                     ? "Drag a component or field here, or pick a component to put in it."
                     : "Merge the selected slots into one cell, then drop a component into it.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if sel.area > 1 {
                    Button { model.mergeSelection() } label: { Label("Merge slots", systemImage: "rectangle.compress.vertical") }
                        .disabled(!model.canMerge).heraldHelp(.designerMergeSlots)
                } else {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 6) {
                        ForEach(DesignerPalette.components) { c in
                            Button { model.addComponent(type: c.type) } label: {
                                Label(c.title, systemImage: c.symbol).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                            }.controlSize(.small).heraldHelp(.designerAddComponent)
                        }
                    }
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Label("Nothing selected", systemImage: "cursorarrow.click").font(.headline)
                Text("Click a cell on the canvas to edit it. Shift-click to select several slots and merge them. Drag components and fields in from the left.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct CellEditor: View {
    @ObservedObject var model: DesignerModel
    let cell: HeraldCell

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 2) {
                Label(DesignerPalette.title(for: cell.component.typeName), systemImage: DesignerPalette.symbol(for: cell.component.typeName))
                    .font(.headline)
                Text("\(cell.id) \u{00B7} row \(cell.row + 1), column \(cell.col + 1) \u{00B7} \(cell.colSpan) \u{00D7} \(cell.rowSpan)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            placement
            InspectorSection(title: "Component") {
                FieldRow("Type") {
                    Picker("", selection: Binding(get: { cell.component.typeName }, set: { model.setComponentType(cell: cell.id, type: $0) })) {
                        ForEach(DesignerPalette.components) { Text($0.title).tag($0.type) }
                    }.labelsHidden().fixedSize().heraldHelp(.designerComponentType)
                }
                componentEditor
            }
            if cell.component.canBeEmpty { EmptyBehaviorSection(model: model, cell: cell) }
        }
    }

    private var placement: some View {
        let g = model.grid
        let id = cell.id
        let room = GridEditing.growRoom(cell: id, in: model.draft)
        let canGrow = room.rows > cell.rowSpan || room.cols > cell.colSpan || cell.rowSpan > 1 || cell.colSpan > 1
        return InspectorSection(title: "Position and span", hint: "Where the cell sits, and how much of the grid it covers") {
            Text("Position").font(.caption.weight(.semibold))
            HStack {
                Stepper("Row \(cell.row + 1)", value: Binding(get: { cell.row + 1 }, set: { model.setPosition(cell: id, row: $0 - 1, col: cell.col) }), in: 1...max(g.rows, 1)).heraldHelp(.designerCellRow)
                Stepper("Column \(cell.col + 1)", value: Binding(get: { cell.col + 1 }, set: { model.setPosition(cell: id, row: cell.row, col: $0 - 1) }), in: 1...max(g.cols, 1)).heraldHelp(.designerCellColumn)
            }
            Text("Span").font(.caption.weight(.semibold))
            HStack {
                Stepper("Rows \(cell.rowSpan)", value: Binding(get: { cell.rowSpan }, set: { model.setSpan(cell: id, rowSpan: $0, colSpan: cell.colSpan) }), in: 1...max(room.rows, 1)).heraldHelp(.designerRowSpan)
                    .disabled(room.rows <= 1)
                Stepper("Columns \(cell.colSpan)", value: Binding(get: { cell.colSpan }, set: { model.setSpan(cell: id, rowSpan: cell.rowSpan, colSpan: $0) }), in: 1...max(room.cols, 1)).heraldHelp(.designerColSpan)
                    .disabled(room.cols <= 1)
            }
            .opacity(canGrow ? 1 : 0.45)
            Text(canGrow ? "Position is the cell\u{2019}s top-left slot. Span is how many rows and columns it covers; it can only grow into empty slots."
                         : "This cell cannot grow: the slots around it are taken or it is on the grid\u{2019}s edge. Position is its top-left slot.")
                .font(.caption2).foregroundStyle(.secondary)
            FieldRow("Align") {
                AlignmentGrid(selection: Binding(get: { cell.align }, set: { a in model.updateCell(id) { $0.align = a } }))
            }
            FieldRow("Padding") {
                NumberField(value: Binding(get: { cell.padding }, set: { v in model.updateCell(id) { $0.padding = v } }), range: 0...64).heraldHelp(.designerCellPadding)
            }
            HStack {
                Button { model.splitSelection() } label: { Label("Split", systemImage: "rectangle.expand.vertical") }.disabled(!model.canSplit).heraldHelp(.designerSplitCell)
                Button { model.duplicateSelection() } label: { Label("Duplicate", systemImage: "plus.square.on.square") }.heraldHelp(.designerDuplicateCell)
                Button(role: .destructive) { model.deleteSelection() } label: { Label("Delete", systemImage: "trash") }.heraldHelp(.designerDeleteCell)
            }.controlSize(.small)
        }
    }

    @ViewBuilder private var componentEditor: some View {
        switch cell.component {
        case .text: TextComponentEditor(model: model, id: cell.id)
        case .image: ImageComponentEditor(model: model, id: cell.id)
        case .issuerIcon: IssuerIconEditor(model: model, id: cell.id)
        case .timestamp: TimestampEditor(model: model, id: cell.id)
        case .button: ButtonEditor(model: model, id: cell.id)
        case .actions: ActionsRowEditor(model: model, id: cell.id)
        case .iconButton: IconButtonEditor(model: model, id: cell.id)
        case .badge: BadgeEditor(model: model, id: cell.id)
        case .stackBadge: StackBadgeEditor(model: model, id: cell.id)
        case .progress: ProgressEditor(model: model, id: cell.id)
        case .rive: RiveEditor(model: model, id: cell.id)
        case .spacer:
            Text("A spacer holds an area of the grid open. Pick a component type above, or drop one onto the cell.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - When empty

private struct EmptyBehaviorSection: View {
    @ObservedObject var model: DesignerModel
    let cell: HeraldCell

    private var tokens: [String] { cell.component.referencedTokens }
    private var absent: Bool { !tokens.isEmpty && tokens.allSatisfy { model.absentTokens.contains($0) } }

    var body: some View {
        let inherited = model.draft.collapseEmpty ? "collapse" : "leave the space"
        let current = model.draft.behavior(for: cell.component)
        InspectorSection(title: "When empty", hint: "What this component does when the notification has no value for what it shows.") {
            Picker("", selection: Binding<HeraldEmptyBehavior?>(get: { cell.component.emptyBehavior },
                                                                 set: { model.setEmptyBehavior(cell: cell.id, $0) })) {
                Text("Template (\(inherited))").tag(Optional<HeraldEmptyBehavior>.none)
                Text("Collapse").tag(Optional(HeraldEmptyBehavior.collapse))
                Text("Keep space").tag(Optional(HeraldEmptyBehavior.keep))
            }.heraldHelp(.designerEmptyBehavior)
            .labelsHidden().pickerStyle(.radioGroup)
            Text(current == .collapse
                 ? "Disappears, and its row or column closes up if nothing else is in it."
                 : "Stays blank so the layout does not shift.")
                .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if !tokens.isEmpty {
                Toggle(isOn: Binding(get: { absent }, set: { on in
                    if on { model.absentTokens.formUnion(tokens) } else { model.absentTokens.subtract(tokens) }
                })) { Text("Preview without \(tokens.map { "{\($0)}" }.joined(separator: ", "))").font(.caption) }
                    .toggleStyle(.checkbox).heraldHelp(.designerPreviewWithout)
            }
        }
    }
}

// MARK: - Component editors

private struct TextComponentEditor: View {
    @ObservedObject var model: DesignerModel
    let id: String
    var body: some View {
        let b = PayloadBinder<HeraldTextComponent>.of(model, id)
        FieldRow("Text") { TokenTextField(model: model, title: "{title} \u{2014} {count}", text: b.binding(\.binding, ""), multiline: true) }
        FieldRow("Style") {
            Picker("", selection: b.binding(\.style, .body)) {
                ForEach(HeraldTextStyle.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
            }.labelsHidden().fixedSize().heraldHelp(.designerTextStyle)
        }
        FieldRow("Lines") { OptionalIntField(value: b.binding(\.maxLines, nil), placeholder: "style").heraldHelp(.designerMaxLines) }
        FieldRow("Size") { OptionalNumberField(value: b.binding(\.fontSize, nil), placeholder: "style").heraldHelp(.designerFontSize) }
        FieldRow("Weight") {
            OptionalPicker(selection: b.binding(\.weight, nil), options: HeraldFontWeight.allCases.map { ($0, $0.rawValue.capitalized) }, noneLabel: "Style").heraldHelp(.designerFontWeight)
        }
        FieldRow("Align") {
            OptionalPicker(selection: b.binding(\.alignment, nil), options: HeraldTextAlignment.allCases.map { ($0, $0.rawValue.capitalized) }, noneLabel: "Cell").heraldHelp(.designerTextAlignment)
        }
        FieldRow("Color") { ColorFieldRow(value: b.binding(\.color, nil), autoLabel: "Style") }
        FieldRow("Links") {
            OptionalPicker(selection: b.binding(\.markdown, nil), options: [(true, "Markdown on"), (false, "Plain")], noneLabel: "Style").heraldHelp(.designerMarkdown)
        }
    }
}

private struct ImageComponentEditor: View {
    @ObservedObject var model: DesignerModel
    let id: String
    var body: some View {
        let b = PayloadBinder<HeraldImageComponent>.of(model, id)
        FieldRow("Image") { TokenTextField(model: model, title: "{image}", text: b.binding(\.binding, "{image}")) }
        FieldRow("Fit") {
            Picker("", selection: b.binding(\.fit, .cover)) {
                Text("Fit").tag(HeraldImageFit.fit); Text("Fill").tag(HeraldImageFit.fill); Text("Cover").tag(HeraldImageFit.cover)
            }.labelsHidden().pickerStyle(.segmented).heraldHelp(.designerImageFit)
        }
        FieldRow("Corners") { NumberField(value: b.binding(\.cornerRadius, 0), range: 0...200).heraldHelp(.designerCornerRadius) }
        FieldRow("Ratio") { OptionalNumberField(value: b.binding(\.aspectRatio, nil), placeholder: "w / h").heraldHelp(.designerAspectRatio) }
        FieldRow("Height") { OptionalNumberField(value: b.binding(\.height, nil), placeholder: "auto").heraldHelp(.designerHeight) }
    }
}

private struct IssuerIconEditor: View {
    @ObservedObject var model: DesignerModel
    let id: String
    var body: some View {
        let b = PayloadBinder<HeraldIssuerIconComponent>.of(model, id)
        FieldRow("Size") { NumberField(value: b.binding(\.size, 22), range: 8...128).heraldHelp(.designerIconSize) }
        FieldRow("Shape") {
            Picker("", selection: b.binding(\.shape, .rounded)) {
                Text("Rounded").tag(HeraldIconShape.rounded); Text("Circle").tag(HeraldIconShape.circle)
            }.labelsHidden().pickerStyle(.segmented).heraldHelp(.designerIconShape)
        }
        FieldRow("Corners") { OptionalNumberField(value: b.binding(\.cornerRadius, nil), placeholder: "auto").heraldHelp(.designerIconCorners) }
        Text("The issuing app\u{2019}s icon.").font(.caption2).foregroundStyle(.secondary)
        Divider()
        SymbolPanel(model: model, symbol: b.binding(\.symbol, nil), showsPlacement: false)
    }
}

private struct TimestampEditor: View {
    @ObservedObject var model: DesignerModel
    let id: String
    var body: some View {
        let b = PayloadBinder<HeraldTimestampComponent>.of(model, id)
        FieldRow("Date") {
            TokenTextField(model: model, title: "delivery time", text: Binding(get: { b.binding(\.binding, nil).wrappedValue ?? "" },
                                                                               set: { b.binding(\.binding, nil).wrappedValue = $0.isEmpty ? nil : $0 }))
        }
        Text("Leave empty to show when the banner arrived. Bind a date field such as {receivedAt} to show that instead.")
            .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        FieldRow("Format") {
            Picker("", selection: b.binding(\.relative, false)) { Text("Clock time").tag(false); Text("3 min ago").tag(true) }
                .labelsHidden().pickerStyle(.segmented).heraldHelp(.designerTimeFormat)
        }
        FieldRow("Style") {
            Picker("", selection: b.binding(\.style, .caption)) {
                ForEach(HeraldTextStyle.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
            }.labelsHidden().fixedSize().heraldHelp(.designerTimeStyle)
        }
        FieldRow("Size") { OptionalNumberField(value: b.binding(\.fontSize, nil), placeholder: "style").heraldHelp(.designerFontSize) }
        FieldRow("Color") { ColorFieldRow(value: b.binding(\.color, nil), autoLabel: "Style") }
    }
}

private struct ButtonEditor: View {
    @ObservedObject var model: DesignerModel
    let id: String
    var body: some View {
        let b = PayloadBinder<HeraldButtonComponent>.of(model, id)
        ActionSlotEditor(model: model, id: id, allowNone: false)
        FieldRow("Style") {
            OptionalPicker(selection: b.binding(\.style, nil),
                           options: [("default", "Default"), ("destructive", "Destructive"), ("cancel", "Quiet")], noneLabel: "Action\u{2019}s own").heraldHelp(.designerButtonStyle)
        }
        Divider()
        SymbolPanel(model: model, symbol: b.binding(\.symbol, nil))
    }
}

private struct ActionsRowEditor: View {
    @ObservedObject var model: DesignerModel
    let id: String
    var body: some View {
        let b = PayloadBinder<HeraldActionsComponent>.of(model, id)
        FieldRow("Shows") {
            Picker("", selection: b.binding(\.source, .merged)) {
                Text("Both").tag(HeraldActionSource.merged); Text("Issuer").tag(HeraldActionSource.issuer); Text("Mine").tag(HeraldActionSource.template)
            }.labelsHidden().pickerStyle(.segmented).heraldHelp(.designerActionsSource)
        }
        FieldRow("Layout") {
            Picker("", selection: b.binding(\.layout, .wrap)) {
                Text("Wrap").tag(HeraldActionsLayout.wrap); Text("Row").tag(HeraldActionsLayout.row); Text("Stack").tag(HeraldActionsLayout.stack)
            }.labelsHidden().pickerStyle(.segmented).heraldHelp(.designerActionsLayout)
        }
        FieldRow("Max") { OptionalIntField(value: b.binding(\.maxVisible, nil), placeholder: "all").heraldHelp(.designerMaxButtons) }
        Button { model.tab = .actions } label: { Label("Edit the buttons\u{2026}", systemImage: "slider.horizontal.3") }
            .buttonStyle(.borderless).controlSize(.small).heraldHelp(.designerEditButtons)
        Divider()
        SymbolPanel(model: model, symbol: b.binding(\.symbol, nil))
    }
}

private struct IconButtonEditor: View {
    @ObservedObject var model: DesignerModel
    let id: String
    private static let symbols = ["xmark", "xmark.circle.fill", "checkmark", "checkmark.circle", "trash", "archivebox", "envelope.open",
                                  "bell.slash", "clock", "moon.zzz", "arrow.up.right", "star", "flag", "pin", "bolt", "ellipsis"]
    var body: some View {
        let b = PayloadBinder<HeraldIconButtonComponent>.of(model, id)
        SymbolPanel(model: model, symbol: Binding(
            get: { b.binding(\.symbol, "").wrappedValue.isEmpty ? nil : b.binding(\.symbolStyle, nil).wrappedValue.map { var x = $0; x.name = b.binding(\.symbol, "").wrappedValue; return x } ?? HeraldSymbol(name: b.binding(\.symbol, "").wrappedValue) },
            set: { new in
                b.binding(\.symbol, "").wrappedValue = new?.name ?? ""
                b.binding(\.symbolStyle, nil).wrappedValue = (new?.styled ?? false) ? new : nil
            }), showsPlacement: false)
        FieldRow("Size") { OptionalNumberField(value: b.binding(\.size, nil), placeholder: "18").heraldHelp(.designerIconButtonSize) }
        FieldRow("Color") { ColorFieldRow(value: b.binding(\.color, nil)) }
        FieldRow("Tooltip") {
            TextField("", text: Binding(get: { b.binding(\.tooltip, nil).wrappedValue ?? "" }, set: { b.binding(\.tooltip, nil).wrappedValue = $0.isEmpty ? nil : $0 }))
                .textFieldStyle(.roundedBorder).heraldHelp(.designerIconButtonTooltip)
        }
        ActionSlotEditor(model: model, id: id, allowNone: false)
    }
}

private struct BadgeEditor: View {
    @ObservedObject var model: DesignerModel
    let id: String
    var body: some View {
        let b = PayloadBinder<HeraldBadgeComponent>.of(model, id)
        FieldRow("Value") { TokenTextField(model: model, title: "{count}", text: b.binding(\.binding, "")) }
        FieldRow("Color") { ColorFieldRow(value: b.binding(\.color, nil), autoLabel: "Accent") }
        FieldRow("Text") { ColorFieldRow(value: b.binding(\.textColor, nil), autoLabel: "Automatic") }
        Divider()
        SymbolPanel(model: model, symbol: b.binding(\.symbol, nil))
    }
}

private struct StackBadgeEditor: View {
    @ObservedObject var model: DesignerModel
    let id: String
    var body: some View {
        let b = PayloadBinder<HeraldStackBadgeComponent>.of(model, id)
        Text("Shows {stack.count}, the number of notifications folded into this banner. Empty while the banner is alone; click it to expand the stack.")
            .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        FieldRow("Color") { ColorFieldRow(value: b.binding(\.color, nil), autoLabel: "Accent") }
        FieldRow("Text") { ColorFieldRow(value: b.binding(\.textColor, nil), autoLabel: "Automatic") }
    }
}

private struct ProgressEditor: View {
    @ObservedObject var model: DesignerModel
    let id: String
    var body: some View {
        let b = PayloadBinder<HeraldProgressComponent>.of(model, id)
        FieldRow("Value") { TokenTextField(model: model, title: "{percent}", text: b.binding(\.binding, "")) }
        Text("A fraction from 0 to 1, or a percentage above 1.").font(.caption2).foregroundStyle(.secondary)
        FieldRow("Color") { ColorFieldRow(value: b.binding(\.color, nil), autoLabel: "Accent") }
        FieldRow("Thickness") { OptionalNumberField(value: b.binding(\.height, nil), placeholder: "4").heraldHelp(.designerThickness) }
    }
}

// MARK: - Rive

private struct RiveEditor: View {
    @ObservedObject var model: DesignerModel
    let id: String

    private var component: HeraldRiveComponent {
        if case .rive(let p)? = model.draft.cell(withID: id)?.component { return p }
        return HeraldRiveComponent()
    }

    var body: some View {
        let b = PayloadBinder<HeraldRiveComponent>.of(model, id)
        let assets = (model.manifest?.assets ?? []).filter { $0.type.lowercased() == "rive" }
        let asset = assets.first { $0.id == b.binding(\.asset, nil).wrappedValue }
        let comp = component
        // What the file holds (read with the Rive runtime): artboards, state machines, inputs.
        let info = model.riveFileInfo(for: comp)
        let board = info?.artboard(named: comp.artboard)
        let machine = info?.machine(comp.stateMachine, artboard: comp.artboard)
        FieldRow("Asset") {
            Picker("", selection: Binding<String?>(get: { b.binding(\.asset, nil).wrappedValue }, set: { id in
                b.binding(\.asset, nil).wrappedValue = id
                if let a = assets.first(where: { $0.id == id }), b.binding(\.stateMachine, nil).wrappedValue == nil { b.binding(\.stateMachine, nil).wrappedValue = a.stateMachine }
            })) {
                Text("A file\u{2026}").tag(Optional<String>.none)
                ForEach(assets, id: \.id) { Text($0.id).tag(Optional($0.id)) }
            }.labelsHidden().fixedSize().heraldHelp(.designerRiveAsset)
        }
        if b.binding(\.asset, nil).wrappedValue == nil {
            FieldRow("File") {
                TextField("animation.riv or /path/to/animation.riv", text: Binding(get: { b.binding(\.path, nil).wrappedValue ?? "" },
                                                                   set: { b.binding(\.path, nil).wrappedValue = $0.isEmpty ? nil : $0 }))
                    .textFieldStyle(.roundedBorder).font(.system(size: 11, design: .monospaced)).heraldHelp(.designerRivePath)
                let stored = model.assets.filter { !$0.declared }
                if !stored.isEmpty {
                    Menu {
                        ForEach(stored) { a in Button(a.file) { b.binding(\.path, nil).wrappedValue = a.file } }
                    } label: { Image(systemName: "folder") }.menuStyle(.borderlessButton).fixedSize()
                        .heraldHelp(.designerRiveStored)
                }
            }
        } else if assets.isEmpty {
            Text("The manifest declares no Rive assets.").font(.caption2).foregroundStyle(.secondary)
        }
        RiveFileSummary(info: info, found: model.riveFileFound(for: comp), component: comp)
        FieldRow("Artboard") {
            if let info, info.artboards.count > 1 {
                Picker("", selection: Binding<String?>(get: { b.binding(\.artboard, nil).wrappedValue }, set: { b.binding(\.artboard, nil).wrappedValue = $0 })) {
                    Text("Default (\(info.artboards.first?.name ?? ""))").tag(Optional<String>.none)
                    ForEach(info.artboards, id: \.name) { Text($0.name).tag(Optional($0.name)) }
                    if let cur = comp.artboard, !info.artboards.contains(where: { $0.name == cur }) { Text("\(cur) (not in the file)").tag(Optional(cur)) }
                }.labelsHidden().fixedSize().heraldHelp(.designerRiveArtboard)
            } else {
                TextField(board?.name ?? "default", text: Binding(get: { b.binding(\.artboard, nil).wrappedValue ?? "" },
                                                                    set: { b.binding(\.artboard, nil).wrappedValue = $0.isEmpty ? nil : $0 })).textFieldStyle(.roundedBorder).heraldHelp(.designerRiveArtboardName)
            }
        }
        FieldRow("State machine") {
            if let board, !board.machines.isEmpty {
                Picker("", selection: Binding<String?>(get: { b.binding(\.stateMachine, nil).wrappedValue }, set: { b.binding(\.stateMachine, nil).wrappedValue = $0 })) {
                    Text("Default (\(board.machines.first { $0.name == board.defaultMachine }?.name ?? board.machines.first?.name ?? ""))").tag(Optional<String>.none)
                    ForEach(board.machines, id: \.name) { Text($0.name).tag(Optional($0.name)) }
                    if let cur = comp.stateMachine, !cur.isEmpty, !board.machines.contains(where: { $0.name == cur }) { Text("\(cur) (not in the file)").tag(Optional(cur)) }
                }.labelsHidden().fixedSize().heraldHelp(.designerRiveMachine)
            } else {
                TextField("Main", text: Binding(get: { b.binding(\.stateMachine, nil).wrappedValue ?? "" },
                                                set: { b.binding(\.stateMachine, nil).wrappedValue = $0.isEmpty ? nil : $0 })).textFieldStyle(.roundedBorder).heraldHelp(.designerRiveMachineName)
            }
        }
        if let board, board.machines.isEmpty, let first = board.animations.first {
            Text("No state machine: plays the animation \u{201C}\(first)\u{201D}.").font(.caption2).foregroundStyle(.secondary)
        }
        RiveInputsEditor(model: model, id: id, suggestions: Self.suggestions(machine: machine, declared: asset?.inputs ?? []))
        FieldRow("Loop") {
            OptionalPicker(selection: b.binding(\.loop, nil), options: [(true, "Loop"), (false, "Once")], noneLabel: "Animation\u{2019}s own").heraldHelp(.designerRiveLoop)
        }
        FieldRow("Ratio") { OptionalNumberField(value: b.binding(\.aspectRatio, nil), placeholder: board?.aspectRatio.map { String(format: "%.2f", $0) } ?? "w / h").heraldHelp(.designerRiveRatio) }
        FieldRow("Height") { OptionalNumberField(value: b.binding(\.height, nil), placeholder: "auto").heraldHelp(.designerHeight) }
        ActionSlotEditor(model: model, id: id, allowNone: true)
    }

    /// The inputs the state machine in the file has, then those the manifest names that the file does not show.
    static func suggestions(machine: RiveFileInfo.Machine?, declared: [String]) -> [RiveInputSuggestion] {
        var out = (machine?.inputs ?? []).map { RiveInputSuggestion(name: $0.name, kind: $0.kind.rawValue) }
        for d in declared where !out.contains(where: { $0.name == d }) { out.append(RiveInputSuggestion(name: d, kind: nil)) }
        return out
    }
}

struct RiveInputSuggestion: Equatable {
    var name: String
    /// number, bool or trigger; nil when only the manifest knows the input.
    var kind: String?
    var label: String { kind.map { "\(name) \u{00B7} \($0)" } ?? name }
}

/// What the Rive runtime found in the file: artboard, and each state machine with its inputs.
private struct RiveFileSummary: View {
    let info: RiveFileInfo?
    let found: Bool
    let component: HeraldRiveComponent
    @State private var open = false

    var body: some View {
        if let info {
            DisclosureGroup(isExpanded: $open) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(info.artboards, id: \.name) { a in
                        Text("\(a.name) \u{00B7} \(Int(a.width)) \u{00D7} \(Int(a.height))").font(.caption.weight(.medium))
                        ForEach(a.machines, id: \.name) { m in
                            VStack(alignment: .leading, spacing: 1) {
                                Text("\(m.name)\(m.name == a.defaultMachine ? " (default)" : "")").font(.system(size: 11, design: .monospaced))
                                Text(m.inputs.isEmpty ? "no inputs" : m.inputs.map { "\($0.name) \($0.kind.rawValue)" }.joined(separator: ", "))
                                    .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            }.padding(.leading, 8)
                        }
                        if a.machines.isEmpty && !a.animations.isEmpty {
                            Text("animations: " + a.animations.joined(separator: ", ")).font(.caption2).foregroundStyle(.secondary).padding(.leading, 8)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 2)
            } label: {
                let machines = info.artboards.reduce(0) { $0 + $1.machines.count }
                let inputs = info.artboards.reduce(0) { $0 + $1.machines.reduce(0) { $0 + $1.inputs.count } }
                Text("In the file: \(info.artboards.count) artboard\(info.artboards.count == 1 ? "" : "s"), \(machines) state machine\(machines == 1 ? "" : "s"), \(inputs) input\(inputs == 1 ? "" : "s")")
                    .font(.caption).foregroundStyle(.secondary)
            }.heraldHelp(.designerRiveDetails)
            .font(.caption)
        } else if found {
            Text("The Rive runtime could not read this file.").font(.caption2).foregroundStyle(.orange)
        } else if component.asset != nil || component.path != nil {
            Text("File not found: add it in Assets, or check the name.").font(.caption2).foregroundStyle(.orange)
        }
    }
}

/// Maps state machine inputs to tokens (`{count}`) or to `hover` / `pressed`.
private struct RiveInputsEditor: View {
    @ObservedObject var model: DesignerModel
    let id: String
    let suggestions: [RiveInputSuggestion]
    private struct Row: Identifiable, Equatable { var id = UUID(); var name: String; var value: String }
    @State private var rows: [Row] = []

    private func dict(_ rows: [Row]) -> [String: String] {
        var out: [String: String] = [:]
        for r in rows where !r.name.isEmpty && !r.value.isEmpty && out[r.name] == nil { out[r.name] = r.value }
        return out
    }
    private func load(_ d: [String: String]) -> [Row] { d.keys.sorted().map { Row(name: $0, value: d[$0] ?? "") } }
    private var current: [String: String] {
        if case .rive(let p)? = model.draft.cell(withID: id)?.component { return p.inputBindings }
        return [:]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Inputs").font(.caption).foregroundStyle(.secondary)
            ForEach($rows) { $row in
                HStack(spacing: 4) {
                    TextField("input", text: $row.name).font(.system(size: 11, design: .monospaced)).frame(width: 74)
                        .heraldHelp(.designerRiveInputName)
                    TextField("{count}", text: $row.value).font(.system(size: 11, design: .monospaced)).heraldHelp(.designerRiveInputValue)
                    Menu {
                        ForEach(HeraldRiveComponent.pointerKeywords, id: \.self) { k in Button(k) { row.value = k } }
                        Divider()
                        ForEach(model.tokenSuggestions.prefix(24)) { t in Button(t.token) { row.value = t.token } }
                    } label: { Image(systemName: "curlybraces") }.menuStyle(.borderlessButton).fixedSize().heraldHelp(.designerRiveInputPick)
                    Button { rows.removeAll { $0.id == row.id } } label: { Image(systemName: "minus.circle") }.buttonStyle(.borderless).heraldHelp(.designerRemoveRiveInput)
                }
                .textFieldStyle(.roundedBorder)
            }
            HStack {
                Button { rows.append(Row(name: "", value: "")) } label: { Label("Add input", systemImage: "plus") }.heraldHelp(.designerAddRiveInput)
                if !suggestions.isEmpty {
                    Menu("From file") {
                        ForEach(suggestions.filter { s in !rows.contains { $0.name == s.name } }, id: \.name) { s in
                            Button(s.label) { rows.append(Row(name: s.name, value: HeraldRiveComponent.pointerKeywords.contains(s.name) ? s.name : "{\(s.name)}")) }
                        }
                    }.menuStyle(.borderlessButton).fixedSize()
                    .heraldHelp(.designerRiveInputsFromFile)
                }
            }
            .buttonStyle(.borderless).controlSize(.small)
        }
        .onAppear { rows = load(current) }
        .onChange(of: rows) { r in
            let d = dict(r)
            if d != current { model.updateCell(id) { cell in if case .rive(var p) = cell.component { p.inputBindings = d; cell.component = .rive(p) } } }
        }
        .onChange(of: current) { c in if c != dict(rows) { rows = load(c) } }
    }
}

// MARK: - Action slot

/// Which action a button, icon button or Rive click runs: one of the resolved actions (the issuer's or one
/// you added), or an action of its own defined right here.
private struct ActionSlotEditor: View {
    @ObservedObject var model: DesignerModel
    let id: String
    let allowNone: Bool

    private enum Mode: Hashable { case none, ref, own }

    var body: some View {
        let slot = model.actionSlot(cell: id) ?? (nil, nil)
        let mode: Mode = slot.inline != nil ? .own : (slot.ref != nil ? .ref : .none)
        VStack(alignment: .leading, spacing: 8) {
            FieldRow("Runs") {
                Picker("", selection: Binding(get: { mode }, set: { setMode($0, slot: slot) })) {
                    if allowNone { Text("None").tag(Mode.none) }
                    Text("Listed").tag(Mode.ref)
                    Text("Own").tag(Mode.own)
                }.labelsHidden().pickerStyle(.segmented).heraldHelp(.designerSlotMode)
            }
            switch mode {
            case .ref:
                Text("One of the buttons from the issuer or that you added (Actions tab).").font(.caption2).foregroundStyle(.secondary)
                let rows = model.actionRows
                FieldRow("Action") {
                    Picker("", selection: Binding(get: { slot.ref ?? "" }, set: { model.setActionSlot(cell: id, inline: nil, ref: $0.isEmpty ? nil : $0) })) {
                        if let r = slot.ref, !rows.contains(where: { $0.id == r }) { Text("\(r) (missing)").tag(r) }
                        ForEach(rows) { Text($0.hidden ? "\($0.action.label) (hidden)" : $0.action.label).tag($0.id) }
                    }.labelsHidden().fixedSize().heraldHelp(.designerSlotAction)
                }
                if let r = slot.ref, !model.previewActions.contains(where: { $0.id == r }) {
                    Text("This action is not in the current preview, so the button is empty and follows the empty behaviour below.")
                        .font(.caption2).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                }
            case .own:
                if let a = slot.inline {
                    HStack(spacing: 8) {
                        Image(systemName: a.kind.designerSymbol).foregroundStyle(Color.accentColor)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(a.label).font(.system(size: 12, weight: .medium)).lineLimit(1)
                            Text(a.designerSummary).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        Button("Edit\u{2026}") { model.editInlineAction(cell: id) }.controlSize(.small).heraldHelp(.designerEditSlotAction)
                    }
                    .padding(8).background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.secondary.opacity(0.10)))
                }
            case .none:
                Text("Clicking the animation does nothing.").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private func setMode(_ m: Mode, slot: (inline: HeraldAction?, ref: String?)) {
        switch m {
        case .none: model.setActionSlot(cell: id, inline: nil, ref: nil)
        case .ref: model.setActionSlot(cell: id, inline: nil, ref: slot.ref ?? model.actionRows.first { !$0.hidden }?.id)
        case .own:
            let a = slot.inline ?? HeraldAction(id: "open", label: "Open", kind: .url, url: "{url}")
            model.setActionSlot(cell: id, inline: a, ref: nil)
            model.editInlineAction(cell: id)
        }
    }
}

// MARK: - Template tab

struct TemplateInspector: View {
    @ObservedObject var model: DesignerModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            InspectorSection(title: "Template") {
                FieldRow("Name") { TextField("name", text: Binding(get: { model.draft.name }, set: { v in model.edit { $0.name = v } })).textFieldStyle(.roundedBorder).heraldHelp(.designerTemplateName) }
                FieldRow("Accent") {
                    ColorFieldRow(value: Binding(get: { model.draft.accentColor }, set: { v in model.edit { $0.accentColor = v } }),
                                  keywords: false, autoLabel: "System")
                }
                if model.convertedFromV1 {
                    Label("Converted from an old layout. Save to keep it as a grid template.", systemImage: "arrow.triangle.2.circlepath")
                        .font(.caption2).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                }
                if model.diskChanged {
                    HStack {
                        Label("Changed on disk while you were editing.", systemImage: "exclamationmark.triangle").font(.caption2).foregroundStyle(.orange)
                        Button("Reload") { model.reloadFromDisk() }.controlSize(.small).heraldHelp(.designerReloadTemplate)
                    }
                }
            }

            InspectorSection(title: "Empty fields", hint: "What happens when a notification has no value for something a component shows.") {
                Picker("", selection: Binding(get: { model.draft.collapseEmpty }, set: { v in model.perform { $0.collapseEmpty = v } })) {
                    Text("Collapse").tag(true); Text("Leave in place").tag(false)
                }.heraldHelp(.designerCollapseEmpty)
                .labelsHidden().pickerStyle(.segmented)
                Text(model.draft.collapseEmpty
                     ? "An empty field disappears and its row or column closes up, so the banner shrinks to what it has."
                     : "An empty field leaves its space, so every banner from this template has the same layout.")
                    .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Text("Each component can override this under \u{201C}When empty\u{201D} on the Cell tab. Test it with Preview without\u{2026} or the preview bar\u{2019}s Fields button.")
                    .font(.caption2).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true)
            }

            gridSection
            InspectorSection(title: "Text") {
                FieldRow("Body lines") {
                    Stepper("\(model.draft.maxBodyLines)", value: Binding(get: { model.draft.maxBodyLines }, set: { v in model.edit { $0.maxBodyLines = v } }), in: 1...30).heraldHelp(.designerBodyLines)
                }
                Text("Line limit for body text that sets none of its own.").font(.caption2).foregroundStyle(.secondary)
            }
            ChecksSection(model: model)
        }
    }

    // MARK: Grid

    private var gridSection: some View {
        let g = model.grid
        return InspectorSection(title: "Grid") {
            FieldRow("Width") { NumberField(value: gridValue(\.width), range: HeraldTemplate.widthRange).heraldHelp(.designerGridWidth) }
            FieldRow("Gap") { NumberField(value: gridValue(\.gap), range: 0...64).heraldHelp(.designerGridGap) }
            FieldRow("Padding") { NumberField(value: gridValue(\.padding), range: 0...64).heraldHelp(.designerGridPadding) }
            Text("Columns").font(.caption).foregroundStyle(.secondary).padding(.top, 4)
            ForEach(0..<g.cols, id: \.self) { i in
                TrackRow(title: "Column \(i + 1)", size: sizeBinding(columns: true, i), canRemove: g.cols > 1) { model.removeColumn(at: i) }
            }
            Button { model.insertColumn(at: g.cols) } label: { Label("Add column", systemImage: "plus") }
                .buttonStyle(.borderless).controlSize(.small).disabled(g.cols >= HeraldTemplate.maxGridTracks).heraldHelp(.designerAddColumn)
            Text("Rows").font(.caption).foregroundStyle(.secondary).padding(.top, 4)
            ForEach(0..<g.rows, id: \.self) { i in
                TrackRow(title: "Row \(i + 1)", size: sizeBinding(columns: false, i), canRemove: g.rows > 1) { model.removeRow(at: i) }
            }
            Button { model.insertRow(at: g.rows) } label: { Label("Add row", systemImage: "plus") }
                .buttonStyle(.borderless).controlSize(.small).disabled(g.rows >= HeraldTemplate.maxGridTracks).heraldHelp(.designerAddRow)
            Text("Auto is as big as its content, Fill shares what is left, a number is exact. Rows grow to fit their content.")
                .font(.caption2).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func gridValue(_ kp: WritableKeyPath<HeraldGrid, Double>) -> Binding<Double> {
        Binding(get: { model.grid[keyPath: kp] }, set: { v in model.edit { t in if var g = t.grid { g[keyPath: kp] = v; t.grid = g } } })
    }

    private func sizeBinding(columns: Bool, _ i: Int) -> Binding<HeraldSize> {
        Binding(
            get: { columns ? model.grid.colSize(at: i) : model.grid.rowSize(at: i) },
            set: { v in
                model.edit { t in
                    guard var g = t.grid else { return }
                    GridEditing.fixSizes(&g)
                    if columns, g.colSizes.indices.contains(i) { g.colSizes[i] = v }
                    if !columns, g.rowSizes.indices.contains(i) { g.rowSizes[i] = v }
                    t.grid = g
                }
            })
    }
}

private struct TrackRow: View {
    let title: String
    @Binding var size: HeraldSize
    let canRemove: Bool
    let remove: () -> Void

    private enum Kind: Hashable { case auto, fill, points }
    private var kind: Kind {
        switch size { case .auto: return .auto; case .fill: return .fill; case .points: return .points }
    }

    var body: some View {
        HStack(spacing: 6) {
            Text(title).font(.caption).frame(width: 70, alignment: .leading)
            Picker("", selection: Binding(get: { kind }, set: { k in
                switch k {
                case .auto: size = .auto
                case .fill: size = .fill
                case .points: if case .points = size {} else { size = .points(72) }
                }
            })) {
                Text("Auto").tag(Kind.auto); Text("Fill").tag(Kind.fill); Text("Points").tag(Kind.points)
            }.heraldHelp(.designerTrackSize)
            .labelsHidden().fixedSize()
            if case .points(let p) = size {
                NumberField(value: Binding(get: { p }, set: { size = .points($0) }), range: 0...4000)
            }
            Spacer(minLength: 0)
            Button(role: .destructive, action: remove) { Image(systemName: "minus.circle") }
                .buttonStyle(.borderless).disabled(!canRemove).heraldHelp(.designerRemoveTrack)
        }
    }
}

/// Problems found by `HeraldTemplate.validate`; click one to select its cell.
private struct ChecksSection: View {
    @ObservedObject var model: DesignerModel
    var body: some View {
        if !model.issues.isEmpty {
            InspectorSection(title: "Checks") {
                ForEach(model.issues.indices, id: \.self) { i in
                    let issue = model.issues[i]
                    Button {
                        if let c = issue.cellId { model.select(cell: c) }
                    } label: {
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: issue.isError ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                                .foregroundStyle(issue.isError ? Color.red : Color.orange)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(issue.message).font(.caption).fixedSize(horizontal: false, vertical: true)
                                Text(issue.cellId.map { "cell \($0) \u{00B7} \(issue.path)" } ?? issue.path)
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
