import SwiftUI
import AppKit
import UniformTypeIdentifiers

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
                    AssetsPalette(model: model)
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
            .labelsHidden().heraldHelp(.designerIssuerPicker)
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
                        Button("From \u{201C}\(l.formTitle)\u{201D}") { model.startNew(from: l) }
                    }
                } label: { Label("New", systemImage: "plus") }
                    .menuStyle(.borderlessButton).fixedSize()
                    .disabled(model.app.isEmpty).heraldHelp(.designerNewTemplate)
                Button { model.duplicate() } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
                    .disabled(model.app.isEmpty)
                    .heraldHelp(.designerDuplicateTemplate)
                Button(role: .destructive) { confirmDelete() } label: { Label("Delete", systemImage: "trash") }
                    .disabled(model.isNew).heraldHelp(.designerDeleteTemplate)
            }
            .controlSize(.small)
            .buttonStyle(.borderless)

            Button { model.setAsDefault() } label: {
                Label(model.savedName.map { model.isDefault($0) } == true ? "Issuer default" : "Set as issuer default",
                      systemImage: model.savedName.map { model.isDefault($0) } == true ? "star.fill" : "star")
            }
            .controlSize(.small)
            .disabled(model.isNew || model.savedName.map { model.isDefault($0) } == true)
            .heraldHelp(.designerSetDefault)
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
                    .background(Capsule().fill(Color.secondary.opacity(0.2))).heraldHelp(.designerOldLayoutBadge)
            }
            if model.isDefault(t.name) { Image(systemName: "star.fill").font(.system(size: 9)).foregroundStyle(.yellow).heraldHelp(.designerDefaultBadge) }
            if t.name == model.savedName, model.isDirty { Circle().fill(.orange).frame(width: 6, height: 6).heraldHelp(.designerUnsavedDot) }
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
    @ObservedObject var model: DesignerModel
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
        .onDrag {
            model.dragging = payload
            return DesignerDrag.provider(payload)
        } preview: {
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
                    PaletteChip(model: model, symbol: c.symbol, title: c.title, payload: .component(c.type),
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
                Button("Add", action: addCustom).disabled(!DesignerModel.isTokenName(custom.trimmingCharacters(in: CharacterSet(charactersIn: "{} ")))).heraldHelp(.designerAddCustomField)
            }
            .controlSize(.small)
            .heraldHelp(.designerCustomField)
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
        .onDrag {
            model.dragging = .field(token.key)
            return DesignerDrag.provider(.field(token.key))
        } preview: {
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
                PaletteChip(model: model, symbol: row.action.kind.designerSymbol, title: row.action.label,
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
                .menuStyle(.borderlessButton).fixedSize().heraldHelp(.designerAddAction)
                .controlSize(.small)
        }
    }
}


// MARK: - Assets (issue #33)

/// The issuer's Rive files: each with a live preview, drag onto the canvas (or click) to play it in a cell,
/// Add... copies a `.riv` into the app's assets folder, Remove deletes a file.
struct AssetsPalette: View {
    @ObservedObject var model: DesignerModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                PaletteHeader(title: "Assets", hint: "Rive animations of this issuer. Drag one onto the canvas, or click to add it to the selected slot.")
                Spacer(minLength: 0)
            }
            if model.assets.isEmpty {
                Text("No animation files for \(model.issuerName) yet.").font(.caption2).foregroundStyle(.secondary)
            }
            ForEach(model.assets) { asset in AssetRow(model: model, asset: asset) }
            Button { addFiles() } label: { Label("Add\u{2026}", systemImage: "plus.circle") }
                .buttonStyle(.borderless).controlSize(.small).disabled(model.app.isEmpty)
                .heraldHelp(.designerAddAsset)
        }
    }

    private func addFiles() {
        let p = NSOpenPanel()
        p.title = "Add Animation"
        p.message = "Choose Rive (.riv) files to add to \(model.issuerName)."
        p.allowedContentTypes = [UTType(filenameExtension: "riv") ?? .data]
        p.allowsMultipleSelection = true
        p.canChooseDirectories = false
        guard p.runModal() == .OK else { return }
        for url in p.urls { model.addAsset(from: url) }
    }
}

private struct AssetRow: View {
    @ObservedObject var model: DesignerModel
    let asset: DesignerAsset

    private var detail: String {
        var parts = [Self.size(asset.bytes)]
        parts.append(asset.declared ? "from the issuer" : "added by you")
        if !asset.usedBy.isEmpty { parts.append("used by \(asset.usedBy.count)") }
        return parts.joined(separator: " \u{00B7} ")
    }

    var body: some View {
        HStack(spacing: 8) {
            // A live preview straight from the file (an absolute path resolves through the asset store).
            RiveComponentView(component: HeraldRiveComponent(path: asset.url.path, height: 40), app: model.app)
                .frame(width: 52, height: 40)
                .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Color.secondary.opacity(0.10)))
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                .allowsHitTesting(false)
            VStack(alignment: .leading, spacing: 1) {
                Text(asset.file).font(.system(size: 11.5, weight: .medium)).lineLimit(1).truncationMode(.middle)
                Text(detail).font(.system(size: 9.5)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
            Button { remove() } label: { Image(systemName: "trash") }
                .buttonStyle(.borderless).controlSize(.small).heraldHelp(.designerRemoveAsset)
        }
        .padding(5)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.secondary.opacity(0.07)))
        .contentShape(Rectangle())
        .onTapGesture { model.insertAsset(id: asset.id) }
        .onDrag {
            model.dragging = .rive(asset.id)
            return DesignerDrag.provider(.rive(asset.id))
        } preview: {
            Label(asset.file, systemImage: "play.rectangle").padding(6).background(Capsule().fill(Color.accentColor.opacity(0.9))).foregroundStyle(.white)
        }
        .contextMenu {
            Button("Add to Selected Slot") { model.insertAsset(id: asset.id) }
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([asset.url]) }
            Divider()
            Button("Remove\u{2026}", role: .destructive) { remove() }
        }
        .help("\(asset.url.path)\nDrag onto the canvas, or click to add it to the selected slot.")
    }

    private func remove() {
        var message = "\u{201C}\(asset.file)\u{201D} is deleted from this issuer's assets folder."
        if !asset.usedBy.isEmpty {
            message += " Templates that play it (\(asset.usedBy.prefix(4).joined(separator: ", "))\(asset.usedBy.count > 4 ? ", ..." : "")) show a placeholder until it is added again."
        }
        if asset.declared { message += " The issuer declares this animation, so Herald copies it back the next time it loads the issuer's manifest." }
        if DesignerAlerts.confirm(title: "Remove \u{201C}\(asset.file)\u{201D}?", message: message, confirm: "Remove", destructive: true) {
            model.removeAsset(asset)
        }
    }

    static func size(_ bytes: Int) -> String {
        bytes >= 1_048_576 ? String(format: "%.1f MB", Double(bytes) / 1_048_576) : String(format: "%.0f KB", max(Double(bytes) / 1024, 1))
    }
}
