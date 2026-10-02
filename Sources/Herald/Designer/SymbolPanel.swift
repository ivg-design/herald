import SwiftUI
import AppKit

/// The inspector's "Symbol" panel: a searchable picker over the SF Symbols on this Mac, then weight, scale,
/// placement, rendering mode with colour wells (hex, accent/primary/secondary, or a {token}), a variable value
/// (a number, a slider, or a {token}) and the macOS 14 effect with its trigger and speed. Every change goes
/// through `SymbolEditing` and lands on the canvas and the live preview at once.
struct SymbolPanel: View {
    @ObservedObject var model: DesignerModel
    @Binding var symbol: HeraldSymbol?
    /// Buttons can drop the label (`only`); a badge or the issuer icon use the same placements.
    var showsPlacement = true

    @State private var picking = false

    private var s: HeraldSymbol { symbol ?? HeraldSymbol(name: "") }
    private func set(_ new: HeraldSymbol) { symbol = SymbolEditing.normalized(new) }
    private func applyPicked(_ name: String) { symbol = SymbolEditing.normalized(SymbolEditing.setName(symbol, name)) }

    /// The floating browser: a child of the window this panel is in, never activating the app.
    private func openPanel() {
        let binding = $symbol
        let designer = model
        SymbolBrowserPanel.show(parent: NSApp.keyWindow ?? NSApp.mainWindow) {
            SymbolBrowserHost(designer: designer, current: { binding.wrappedValue ?? HeraldSymbol(name: "") },
                              apply: { binding.wrappedValue = SymbolEditing.normalized(SymbolEditing.setName(binding.wrappedValue, $0)) })
        }
    }

    var body: some View {
        InspectorSection(title: "Symbol", hint: "An SF Symbol on this component") {
            FieldRow("Name") {
                TextField("bell.badge", text: Binding(get: { s.name }, set: { symbol = SymbolEditing.normalized(SymbolEditing.setName(symbol, $0)) }))
                    .textFieldStyle(.roundedBorder).font(.system(size: 12, design: .monospaced))
                Menu {
                    Button("Browse in a sheet") { picking = true }
                    Button("Browse in a floating panel") { openPanel() }
                } label: {
                    Image(systemName: s.name.isEmpty || !HeraldSymbol.isKnown(s.name) ? "square.grid.3x3" : s.name)
                } primaryAction: { picking = true }
                .menuStyle(.borderedButton).controlSize(.small).fixedSize()
                .help("Browse the SF Symbols on this Mac (the arrow opens a floating panel)")
                .sheet(isPresented: $picking) {
                    SymbolBrowserHost(designer: model, current: { s }, apply: { applyPicked($0) },
                                      closeAfterUse: { picking = false }, onClose: { picking = false },
                                      onFloat: { picking = false; openPanel() })
                }
                if symbol != nil {
                    Button { symbol = nil } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.borderless).help("Remove the symbol")
                }
            }
            if let _ = symbol {
                if !s.name.contains("{"), !HeraldSymbol.isKnown(s.name) {
                    Text("Not an SF Symbol on this Mac: the default look is drawn.").font(.caption2).foregroundStyle(.orange)
                }
                FieldRow("Weight") {
                    Picker("", selection: Binding(get: { s.weight ?? .regular }, set: { var n = s; n.weight = $0; set(n) })) {
                        ForEach(HeraldSymbolWeight.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }.labelsHidden().fixedSize()
                }
                FieldRow("Scale") {
                    Picker("", selection: Binding(get: { s.scale ?? .medium }, set: { var n = s; n.scale = $0; set(n) })) {
                        ForEach(HeraldSymbolScale.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                    }.labelsHidden().pickerStyle(.segmented)
                }
                if showsPlacement {
                    FieldRow("Place") {
                        Picker("", selection: Binding(get: { s.placement ?? .leading }, set: { var n = s; n.placement = $0; set(n) })) {
                            Text("Before").tag(HeraldSymbolPlacement.leading); Text("After").tag(HeraldSymbolPlacement.trailing)
                            Text("Only").tag(HeraldSymbolPlacement.only)
                        }.labelsHidden().pickerStyle(.segmented)
                    }
                }
                FieldRow("Mode") {
                    Picker("", selection: Binding(get: { s.renderingMode ?? .monochrome }, set: { set(SymbolEditing.setMode(s, $0)) })) {
                        Text("Monochrome").tag(HeraldSymbolRenderingMode.monochrome)
                        Text("Hierarchical").tag(HeraldSymbolRenderingMode.hierarchical)
                        Text("Palette").tag(HeraldSymbolRenderingMode.palette)
                        Text("Multicolor").tag(HeraldSymbolRenderingMode.multicolor)
                    }.labelsHidden().fixedSize()
                }
                if s.renderingMode != .multicolor { colorRows }
                variableRow
                effectRows
            }
        }
    }

    // MARK: Colours

    @ViewBuilder private var colorRows: some View {
        let colors = s.colors ?? []
        let wanted = (s.renderingMode ?? .monochrome) == .palette ? 3 : 1
        ForEach(Array(colors.enumerated()), id: \.offset) { i, c in
            FieldRow(i == 0 ? "Color" : "Color \(i + 1)") {
                SymbolColorWell(model: model, value: Binding(get: { c }, set: { set(SymbolEditing.setColor(s, at: i, $0)) }))
                if colors.count > 1 || s.renderingMode == .palette && colors.count > 2 {
                    Button { set(SymbolEditing.removeColor(s, at: i)) } label: { Image(systemName: "minus.circle") }.buttonStyle(.borderless)
                }
            }
        }
        if colors.count < wanted {
            Button { set(SymbolEditing.addColor(s)) } label: { Label(colors.isEmpty ? "Set a color" : "Add a color", systemImage: "plus.circle") }
                .buttonStyle(.borderless).controlSize(.small)
        }
    }

    // MARK: Variable value

    @ViewBuilder private var variableRow: some View {
        let text = s.variableValue ?? ""
        FieldRow("Variable") {
            TokenTextField(model: model, title: "0.5 or {progress}", text: Binding(get: { text }, set: { set(SymbolEditing.setVariableValue(s, $0)) }))
        }
        if let d = Double(text) {
            Slider(value: Binding(get: { d }, set: { set(SymbolEditing.setVariableValue(s, String(format: "%.2f", $0))) }), in: 0...1)
                .controlSize(.small)
        }
    }

    // MARK: Effect

    @ViewBuilder private var effectRows: some View {
        FieldRow("Effect") {
            Picker("", selection: Binding(get: { s.effect?.kind }, set: { set(SymbolEditing.setEffect(s, $0)) })) {
                Text("None").tag(Optional<HeraldSymbolEffectKind>.none)
                ForEach(HeraldSymbolEffectKind.allCases, id: \.self) { Text($0.rawValue).tag(Optional($0)) }
            }.labelsHidden().fixedSize()
        }
        if let e = s.effect {
            FieldRow("When") {
                Picker("", selection: Binding(get: { e.resolvedTrigger }, set: { set(SymbolEditing.setTrigger(s, $0)) })) {
                    Text("On appear").tag(HeraldSymbolTrigger.onAppear); Text("On change").tag(HeraldSymbolTrigger.onChange)
                    Text("On hover").tag(HeraldSymbolTrigger.onHover); Text("Repeating").tag(HeraldSymbolTrigger.repeating)
                }.labelsHidden().fixedSize()
            }
            FieldRow("Speed") {
                Slider(value: Binding(get: { e.resolvedSpeed }, set: { set(SymbolEditing.setSpeed(s, $0)) }), in: 0.25...4).controlSize(.small)
                Text(String(format: "%.2g\u{00D7}", e.resolvedSpeed)).font(.caption.monospacedDigit()).frame(width: 34)
            }
            if e.kind == .variableColor {
                Toggle("Cumulative", isOn: Binding(get: { e.cumulative ?? false }, set: { var n = s; n.effect?.cumulative = $0 ? true : nil; set(n) })).controlSize(.small)
                Toggle("Reversing", isOn: Binding(get: { e.reversing ?? false }, set: { var n = s; n.effect?.reversing = $0 ? true : nil; set(n) })).controlSize(.small)
            }
            Text(effectNote(e)).font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func effectNote(_ e: HeraldSymbolEffect) -> String {
        var t = "Effects play in live banners and the live preview (macOS 14+), not in static renders, and not with Reduce Motion."
        if e.kind == .replace { t += " Replace swaps the symbol when its name changes: use a {token} as the name." }
        return t
    }
}

/// A colour: the keywords, a hex colour (with a well) or a {token}.
private struct SymbolColorWell: View {
    @ObservedObject var model: DesignerModel
    @Binding var value: String

    var body: some View {
        HStack(spacing: 4) {
            ColorPicker("", selection: Binding(get: { ComposerColorRow.color(value) ?? .accentColor },
                                               set: { value = ComposerColorRow.hex($0) }), supportsOpacity: false)
                .labelsHidden()
            TextField("accent", text: $value).textFieldStyle(.roundedBorder).font(.system(size: 11, design: .monospaced))
            Menu {
                Button("Accent") { value = "accent" }; Button("Primary") { value = "primary" }; Button("Secondary") { value = "secondary" }
            } label: { Image(systemName: "paintpalette") }.menuStyle(.borderlessButton).fixedSize()
            TokenMenu(model: model) { value = $0 }
        }
    }
}
