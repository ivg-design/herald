import SwiftUI
import AppKit

// The Designer's left column: the issuer and its templates on top (New / Duplicate / Delete / Set as
// default), then the palette: components to drag onto the canvas, the issuer's fields as tokens with their
// sample values, and the actions (the issuer's own and the ones you add).

struct PaletteView: View {
    @ObservedObject var model: DesignerModel

    var body: some View {
        VStack(spacing: 0) {
            IssuerTemplatesView(model: model)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ComponentsPalette(model: model)
                    FieldsPalette(model: model)
                    ActionsPalette(model: model)
                }
                .padding(12)
            }
        }
    }
}

struct PaletteHeader: View {
    let title: String
    var hint: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased()).font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
            if let hint { Text(hint).font(.caption2).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true) }
        }
    }
}

// MARK: - Issuer and templates

struct IssuerTemplatesView: View {
    @ObservedObject var model: DesignerModel
    private let newRowTag = "\u{0}new"

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PaletteHeader(title: "Issuer")
            Picker("Issuer", selection: Binding(get: { model.app }, set: { model.switchIssuer($0) })) {
                if model.issuers.isEmpty { Text("No issuers yet").tag(model.app) }
                else if !model.issuers.contains(where: { $0.id == model.app }) { Text(model.app).tag(model.app) }
                ForEach(model.issuers) { Text($0.name).tag($0.id) }
            }
            .labelsHidden()
            if let issuer = model.currentIssuer, !issuer.hasManifest {
                Text("No manifest yet: only the standard fields are known.")
                    .font(.caption2).foregroundStyle(.secondary)
            }

            PaletteHeader(title: "Templates")
            List(selection: Binding<String?>(get: { model.savedName ?? newRowTag },
                                             set: { if let n = $0, n != newRowTag { model.select(template: n) } })) {
                if model.isNew {
                    Label(model.draft.name.isEmpty ? "New template" : model.draft.name, systemImage: "plus.square.dashed")
                        .foregroundStyle(.secondary).tag(newRowTag)
                }
                ForEach(model.templates) { t in row(t).tag(t.name) }
            }
            .listStyle(.bordered)
            .frame(height: 118)

            HStack(spacing: 6) {
                Menu {
                    Button("Blank 3 \u{00D7} 4 grid") { model.startNew(from: nil) }
                    Divider()
                    ForEach(HeraldLayout.allCases, id: \.self) { l in
                        Button("From \u{201C}\(TemplateEditorView.layoutTitle(l))\u{201D}") { model.startNew(from: l) }
                    }
                } label: { Label("New", systemImage: "plus") }
                    .menuStyle(.borderlessButton).fixedSize()
                    .disabled(model.app.isEmpty)
                Button { model.duplicate() } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
                    .disabled(model.app.isEmpty)
                    .help("Save a copy of this template, with your current edits, under a new name")
                Button(role: .destructive) { confirmDelete() } label: { Label("Delete", systemImage: "trash") }
                    .disabled(model.isNew)
            }
            .controlSize(.small)
            .buttonStyle(.borderless)

            Button { model.setAsDefault() } label: {
                Label(model.savedName.map { model.isDefault($0) } == true ? "Issuer default" : "Set as issuer default",
                      systemImage: model.savedName.map { model.isDefault($0) } == true ? "star.fill" : "star")
            }
            .controlSize(.small)
            .disabled(model.isNew || model.savedName.map { model.isDefault($0) } == true)
            .help("Notifications from this issuer that name no template use this one")
        }
        .padding(12)
    }

    private func row(_ t: HeraldTemplate) -> some View {
        HStack(spacing: 6) {
            Image(systemName: t.usesGrid ? "square.grid.3x2" : "rectangle.lefthalf.inset.filled").foregroundStyle(.secondary)
            Text(t.name).lineLimit(1)
            Spacer(minLength: 0)
            if !t.usesGrid {
                Text("v1").font(.system(size: 9, weight: .medium)).padding(.horizontal, 4)
                    .background(Capsule().fill(Color.secondary.opacity(0.2))).help("Old layout: opens converted to a grid")
            }
            if model.isDefault(t.name) { Image(systemName: "star.fill").font(.system(size: 9)).foregroundStyle(.yellow).help("Issuer's default template") }
            if t.name == model.savedName, model.isDirty { Circle().fill(.orange).frame(width: 6, height: 6).help("Unsaved changes") }
        }
    }

    private func confirmDelete() {
        guard let name = model.savedName else { return }
        if DesignerAlerts.confirm(title: "Delete template \u{201C}\(name)\u{201D}?",
                                  message: "Notifications that reference it fall back to plain banners.",
                                  confirm: "Delete", destructive: true) { model.deleteSaved() }
    }
}

// MARK: - Components

private struct PaletteChip: View {
    let symbol: String
    let title: String
    let payload: DragPayload
    let help: String
    let tap: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).frame(width: 15).foregroundStyle(Color.accentColor)
            Text(title).font(.system(size: 11.5)).lineLimit(1).minimumScaleFactor(0.85)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6).padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.secondary.opacity(0.10)))
        .contentShape(Rectangle())
        .onTapGesture(perform: tap)
        .draggable(payload.string) {
            Label(title, systemImage: symbol).padding(6).background(Capsule().fill(Color.accentColor.opacity(0.9))).foregroundStyle(.white)
        }
        .help(help)
    }
}

struct ComponentsPalette: View {
    @ObservedObject var model: DesignerModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            PaletteHeader(title: "Components", hint: "Drag onto the canvas, or click to add to the selected slot.")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 6) {
                ForEach(DesignerPalette.components) { c in
                    PaletteChip(symbol: c.symbol, title: c.title, payload: .component(c.type),
                                help: "Drag onto the canvas, or click to add") { model.addComponent(type: c.type) }
                }
            }
        }
    }
}

// MARK: - Fields

extension HeraldFieldType {
    var designerSymbol: String {
        switch self {
        case .text: return "textformat"
        case .number: return "number"
        case .date: return "calendar"
        case .url: return "link"
        case .image: return "photo"
        case .bool: return "checkmark.circle"
        case .list: return "list.bullet"
        }
    }
}

struct FieldsPalette: View {
    @ObservedObject var model: DesignerModel
    @State private var custom = ""
    private let order: [TokenSuggestion.Group] = [.issuer, .standard, .extra, .seen, .custom]

    var body: some View {
        let all = model.tokenSuggestions
        VStack(alignment: .leading, spacing: 6) {
            PaletteHeader(title: "Fields", hint: "Drag a field onto a cell to bind it, or onto an empty slot to place it. Samples drive the preview.")
            ForEach(order, id: \.rawValue) { group in
                let items = all.filter { $0.group == group }
                if !items.isEmpty {
                    Text(group.rawValue).font(.caption).foregroundStyle(.secondary).padding(.top, 2)
                    ForEach(items) { t in FieldChip(model: model, token: t) }
                }
            }
            HStack(spacing: 4) {
                TextField("custom.token", text: $custom).textFieldStyle(.roundedBorder).font(.system(size: 11, design: .monospaced))
                    .onSubmit(addCustom)
                Button("Add", action: addCustom).disabled(!DesignerModel.isTokenName(custom.trimmingCharacters(in: CharacterSet(charactersIn: "{} "))))
            }
            .controlSize(.small)
            .help("A key the issuer may send in its metadata that the manifest does not declare")
        }
    }

    private func addCustom() { model.addCustomToken(custom); custom = "" }
}

private struct FieldChip: View {
    @ObservedObject var model: DesignerModel
    let token: TokenSuggestion

    var body: some View {
        let absent = model.absentTokens.contains(token.key)
        HStack(spacing: 6) {
            Image(systemName: absent ? "eye.slash" : (token.type?.designerSymbol ?? "curlybraces"))
                .frame(width: 14).foregroundStyle(absent ? Color.orange : Color.accentColor)
            Text(token.token).font(.system(size: 11, design: .monospaced)).lineLimit(1)
            Spacer(minLength: 4)
            if let s = token.sample, !s.isEmpty {
                Text(s.replacingOccurrences(of: "\n", with: " ")).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    .truncationMode(.tail).frame(maxWidth: 70, alignment: .trailing)
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.secondary.opacity(0.10)))
        .contentShape(Rectangle())
        .onTapGesture { model.insertField(key: token.key) }
        .draggable(DragPayload.field(token.key).string) {
            Text(token.token).font(.system(size: 11, design: .monospaced)).padding(6)
                .background(Capsule().fill(Color.accentColor.opacity(0.9))).foregroundStyle(.white)
        }
        .contextMenu {
            Button(absent ? "Preview as present" : "Preview as absent") {
                if absent { model.absentTokens.remove(token.key) } else { model.absentTokens.insert(token.key) }
            }
            Button("Copy {\(token.key)}") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(token.token, forType: .string)
            }
        }
        .help(token.sample.map { "\(token.token) \u{2014} \($0)" } ?? token.token)
    }
}

// MARK: - Actions

struct ActionsPalette: View {
    @ObservedObject var model: DesignerModel

    var body: some View {
        let rows = model.actionRows.filter { !$0.hidden }
        VStack(alignment: .leading, spacing: 6) {
            PaletteHeader(title: "Actions", hint: "Drag an action onto the canvas for a button of its own. An action row component lists them all.")
            ForEach(rows) { row in
                PaletteChip(symbol: row.action.kind.designerSymbol, title: row.action.label,
                            payload: .action(row.id), help: "\(row.action.kind.designerTitle) \u{00B7} \(row.origin == .issuer ? "from the issuer" : "added by you")") {
                    model.insertAction(id: row.id)
                }
                .overlay(alignment: .trailing) {
                    if row.origin == .template {
                        Text("you").font(.system(size: 9, weight: .medium)).foregroundStyle(.white)
                            .padding(.horizontal, 5).padding(.vertical, 1).background(Capsule().fill(Color.accentColor)).padding(.trailing, 6)
                    }
                }
            }
            if rows.isEmpty {
                Text(model.manifest == nil ? "No issuer actions known yet." : "The issuer declares no actions.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Menu {
                ForEach([HeraldActionKind.shortcut, .script, .command, .url, .callback, .snooze, .dismiss], id: \.self) { k in
                    Button { model.openActionEditor(model.newActionRequest(kind: k)) } label: { Label(k.designerTitle, systemImage: k.designerSymbol) }
                }
            } label: { Label("Add action\u{2026}", systemImage: "plus.circle") }
                .menuStyle(.borderlessButton).fixedSize()
                .controlSize(.small)
        }
    }
}
