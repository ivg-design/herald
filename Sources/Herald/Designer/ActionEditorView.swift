import SwiftUI
import AppKit

// The Designer's two-way actions editor (DESIGN 7.3). Buttons on a banner come from two places: the issuer
// (its manifest, or the notification's own buttons) and you. Here you hide, rename, restyle and reorder the
// issuer's, add your own (a link, a shell command, a script, an Apple Shortcut, a callback, snooze, dismiss),
// and author the `extra` values every action receives next to the issuer's fields.

// MARK: - Kinds

extension HeraldActionKind {
    var designerTitle: String {
        switch self {
        case .url: return "Open link"
        case .callback: return "Call back the issuer"
        case .command: return "Run shell command"
        case .script: return "Run script"
        case .shortcut: return "Run Apple Shortcut"
        case .dismiss: return "Dismiss"
        case .snooze: return "Snooze"
        }
    }

    var designerSymbol: String {
        switch self {
        case .url: return "link"
        case .callback: return "arrow.uturn.backward.circle"
        case .command: return "terminal"
        case .script: return "doc.text"
        case .shortcut: return "wand.and.stars"
        case .dismiss: return "xmark.circle"
        case .snooze: return "moon.zzz"
        }
    }
}

extension HeraldAction {
    /// One line saying what pressing the action does.
    var designerSummary: String {
        func line(_ s: String?) -> String { (s ?? "").split(separator: "\n").first.map(String.init) ?? "" }
        switch kind {
        case .url: return line(url)
        case .callback: return "Calls the issuer back"
        case .command: return line(command)
        case .script: return script ?? ""
        case .shortcut: return shortcut.map { "Shortcut \u{201C}\($0)\u{201D}" } ?? "Shortcut"
        case .dismiss: return "Closes the banner"
        case .snooze: return "Snoozes for \(snoozeMinutes ?? HeraldAction.defaultSnoozeMinutes) min"
        }
    }
}

// MARK: - Actions tab

struct ActionEditorView: View {
    @ObservedObject var model: DesignerModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Buttons come from the issuer and from you. Rename, hide, restyle or reorder the issuer\u{2019}s, and add your own: a link, a shell command, a script or an Apple Shortcut.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 8) {
                PaletteHeader(title: "Buttons", hint: model.previewSource == .lastReal
                              ? "From the last real notification."
                              : (model.manifest == nil ? "No manifest: the issuer\u{2019}s buttons are unknown until it sends one." : "From the issuer\u{2019}s manifest."))
                let rows = model.actionRows
                let visible = rows.filter { !$0.hidden }.map(\.id)
                ForEach(rows) { row in
                    ActionRowView(model: model, row: row, position: visible.firstIndex(of: row.id), count: visible.count)
                }
                if rows.isEmpty { Text("Nothing yet. Add an action below.").font(.caption).foregroundStyle(.secondary) }
            }

            VStack(alignment: .leading, spacing: 8) {
                PaletteHeader(title: "Add your own")
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 6) {
                    ForEach([HeraldActionKind.shortcut, .script, .command, .url, .callback, .snooze], id: \.self) { k in
                        Button { model.openActionEditor(model.newActionRequest(kind: k)) } label: {
                            Label(k.designerTitle, systemImage: k.designerSymbol).lineLimit(1).minimumScaleFactor(0.8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .controlSize(.small)
                    }
                }
                Text("Your actions are yours: a command, script or Shortcut you add runs after one confirmation per template.")
                    .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }

            ExtraRowsEditor(model: model)
        }
    }
}

private struct ActionRowView: View {
    @ObservedObject var model: DesignerModel
    let row: DesignerActionRow
    /// Index among the visible actions; nil when hidden.
    let position: Int?
    let count: Int

    private var isIssuer: Bool { row.origin == .issuer }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                if isIssuer {
                    Button { model.setActionHidden(row.id, !row.hidden) } label: {
                        Image(systemName: row.hidden ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.borderless).help(row.hidden ? "Show this button" : "Hide this button")
                }
                Image(systemName: row.action.kind.designerSymbol).foregroundStyle(row.hidden ? Color.secondary : Color.accentColor).frame(width: 16)
                if isIssuer {
                    RelabelField(model: model, row: row)
                } else {
                    Text(row.action.label).font(.system(size: 12, weight: .medium)).lineLimit(1)
                    Spacer(minLength: 0)
                }
                if let p = position {
                    Button { model.moveAction(row.id, by: -1) } label: { Image(systemName: "chevron.up") }
                        .buttonStyle(.borderless).disabled(p == 0).help("Move up")
                    Button { model.moveAction(row.id, by: 1) } label: { Image(systemName: "chevron.down") }
                        .buttonStyle(.borderless).disabled(p >= count - 1).help("Move down")
                }
            }
            HStack(spacing: 8) {
                Text(isIssuer ? "\(row.action.kind.rawValue) \u{00B7} from the issuer" : row.action.designerSummary)
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                Spacer(minLength: 0)
                if isIssuer {
                    Menu {
                        ForEach(["default", "destructive", "cancel"], id: \.self) { s in
                            Button { model.setActionStyle(row.id, style: s, original: row.base?.style) } label: {
                                if (row.action.style ?? "default") == s { Label(s, systemImage: "checkmark") } else { Text(s) }
                            }
                        }
                    } label: { Text(row.action.style ?? "default").font(.caption2) }
                        .menuStyle(.borderlessButton).fixedSize().disabled(row.hidden)
                    if row.isRelabeled || row.isRestyled || row.hidden {
                        Button { model.resetAction(row.id) } label: { Image(systemName: "arrow.counterclockwise") }
                            .buttonStyle(.borderless).help("Back to what the issuer sent")
                    }
                } else {
                    Button { model.editTemplateAction(row.id) } label: { Image(systemName: "pencil") }
                        .buttonStyle(.borderless).help("Edit")
                    Button(role: .destructive) { model.removeTemplateAction(row.id) } label: { Image(systemName: "trash") }
                        .buttonStyle(.borderless).help("Remove")
                }
            }
            .padding(.leading, isIssuer ? 22 : 0)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.secondary.opacity(row.hidden ? 0.05 : 0.10)))
        .opacity(row.hidden ? 0.7 : 1)
    }
}

/// The label of an issuer action, editable. Local text so emptying the field does not snap back to the
/// issuer's label mid-edit.
private struct RelabelField: View {
    @ObservedObject var model: DesignerModel
    let row: DesignerActionRow
    @State private var text = ""

    var body: some View {
        TextField(row.base?.label ?? "Label", text: $text)
            .textFieldStyle(.plain)
            .font(.system(size: 12, weight: .medium))
            .strikethrough(row.hidden)
            .onAppear { text = row.action.label }
            .onChange(of: text) { t in
                if t != row.action.label { model.setActionLabel(row.id, label: t, original: row.base?.label ?? "") }
            }
            .onChange(of: row.action.label) { l in if l != text, !text.isEmpty || l != row.base?.label { text = l } }
    }
}

// MARK: - Extra values

/// The template's own key/values (`extra`): sent to every action next to the issuer's fields, and readable in
/// bindings as `{extra.key}`.
struct ExtraRowsEditor: View {
    @ObservedObject var model: DesignerModel
    private struct Row: Identifiable, Equatable { var id = UUID(); var key: String; var value: String }
    @State private var rows: [Row] = []

    private func dict(_ rows: [Row]) -> [String: String] {
        var out: [String: String] = [:]
        for r in rows where DesignerModel.isTokenName(r.key) && out[r.key] == nil { out[r.key] = r.value }
        return out
    }

    private func load(_ d: [String: String]) -> [Row] { d.keys.sorted().map { Row(key: $0, value: d[$0] ?? "") } }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            PaletteHeader(title: "Extra data",
                          hint: "Your own values. Every action receives them with the issuer\u{2019}s fields, and a binding can read one as {extra.key}.")
            ForEach($rows) { $row in
                HStack(spacing: 4) {
                    TextField("key", text: $row.key).font(.system(size: 11, design: .monospaced)).frame(width: 90)
                        .foregroundStyle(row.key.isEmpty || DesignerModel.isTokenName(row.key) ? Color.primary : Color.red)
                    TextField("value", text: $row.value).font(.system(size: 11))
                    Button { rows.removeAll { $0.id == row.id } } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.borderless).help("Remove")
                }
                .textFieldStyle(.roundedBorder)
            }
            Button { rows.append(Row(key: "", value: "")) } label: { Label("Add value", systemImage: "plus") }
                .buttonStyle(.borderless).controlSize(.small)
            if rows.contains(where: { !$0.key.isEmpty && !DesignerModel.isTokenName($0.key) }) {
                Text("Keys use letters, digits, _ . and -.").font(.caption2).foregroundStyle(.red)
            }
        }
        .onAppear { rows = load(model.draft.extra) }
        .onChange(of: rows) { r in
            let d = dict(r)
            if d != model.draft.extra { model.edit { $0.extra = d } }
        }
        .onChange(of: model.draft.extra) { e in if e != dict(rows) { rows = load(e) } }
    }
}

// MARK: - Action form (sheet)

/// Adds or edits one action. Used for the user's own actions in the template and for the inline action of a
/// button, icon button or Rive cell.
struct ActionFormView: View {
    @ObservedObject var model: DesignerModel
    @State private var request: ActionEditorRequest
    @State private var idEdited = false
    @State private var payloadText = ""
    @State private var shortcuts = ShortcutsState.idle
    @State private var query = ""

    enum ShortcutsState: Equatable { case idle, loading, loaded([String]), failed(String) }

    init(model: DesignerModel, request: ActionEditorRequest) {
        self.model = model
        _request = State(initialValue: request)
        if request.mode != .addToTemplate { _idEdited = State(initialValue: true) }
        if let p = request.action.callback?.payload, let d = try? HeraldJSON.encoder().encode(p) {
            _payloadText = State(initialValue: String(data: d, encoding: .utf8) ?? "")
        }
    }

    private var title: String {
        switch request.mode {
        case .addToTemplate: return "Add action"
        case .editTemplate: return "Edit action"
        case .inline: return "Button action"
        }
    }

    private var action: Binding<HeraldAction> { $request.action }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section(title) {
                    HStack {
                        TextField("Label", text: action.label)
                        TokenMenu(model: model) { action.wrappedValue.label += $0 }
                    }
                    Picker("Does this", selection: kindBinding) {
                        ForEach(HeraldActionKind.allCases, id: \.self) { Label($0.designerTitle, systemImage: $0.designerSymbol).tag($0) }
                    }
                    Picker("Style", selection: Binding(get: { request.action.style ?? "default" },
                                                       set: { request.action.style = $0 == "default" ? nil : $0 })) {
                        Text("Default").tag("default"); Text("Destructive").tag("destructive"); Text("Quiet").tag("cancel")
                    }
                }
                detail
                Section {
                    SymbolPanel(model: model, symbol: Binding(get: { request.action.symbol }, set: { request.action.symbol = $0 }))
                }
                Section {
                    DisclosureGroup("Advanced") {
                        TextField("Id", text: Binding(get: { request.action.id }, set: { request.action.id = $0; idEdited = true }))
                            .font(.system(size: 12, design: .monospaced))
                        Text("What rules and button cells refer to. Letters, digits, - and _.").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)
            Divider()
            HStack {
                if let e = formError { Text(e).font(.caption).foregroundStyle(.red).lineLimit(2) }
                Spacer()
                Button("Cancel") { model.actionEditor = nil }.keyboardShortcut(.cancelAction)
                Button("Save") { model.commitActionEditor(request) }
                    .keyboardShortcut(.defaultAction).disabled(formError != nil)
            }
            .padding(12)
        }
        .frame(width: 480, height: 560)
        .onChange(of: request.action.label) { l in
            if !idEdited { request.action.id = HeraldAction.slug(l) }
        }
        .task(id: request.action.kind) { if request.action.kind == .shortcut, shortcuts == .idle { await loadShortcuts() } }
    }

    private var kindBinding: Binding<HeraldActionKind> {
        Binding(get: { request.action.kind }, set: { k in
            let old = request.action
            var a = HeraldAction(id: old.id, label: old.label, kind: k, style: old.style)
            if k == .url { a.url = "{url}" }
            if k == .snooze { a.snoozeMinutes = HeraldAction.defaultSnoozeMinutes }
            if k == .callback { a.callback = HeraldCallback() }
            request.action = a
            payloadText = ""
        })
    }

    // MARK: Validation

    private var payloadError: Bool {
        let t = payloadText.trimmingCharacters(in: .whitespacesAndNewlines)
        return !t.isEmpty && (try? HeraldJSON.decoder().decode(JSONValue.self, from: Data(t.utf8))) == nil
    }

    private var formError: String? {
        let a = request.action
        func blank(_ s: String?) -> Bool { (s ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if blank(a.label) { return "Give the action a label." }
        if blank(a.id) { return "The id cannot be empty." }
        switch a.kind {
        case .url:
            if blank(a.url) { return "Enter the link to open." }
            if let u = a.url, !u.contains("{"), !["http://", "https://", "mailto:"].contains(where: { u.lowercased().hasPrefix($0) }) {
                return "Only http, https and mailto links can be opened."
            }
        case .command: if blank(a.command) { return "Enter the command to run." }
        case .script:
            if blank(a.script) { return "Choose a script from the scripts folder." }
            if let s = a.script, s.contains("..") || s.hasPrefix("/") || s.hasPrefix("~") { return "A script is a file inside the scripts folder." }
        case .shortcut: if blank(a.shortcut) { return "Choose a Shortcut." }
        case .callback: if payloadError { return "The payload is not valid JSON." }
        case .snooze: break
        case .dismiss: break
        }
        return nil
    }

    // MARK: Kind-specific fields

    @ViewBuilder private var detail: some View {
        switch request.action.kind {
        case .url:
            Section("Link") {
                HStack {
                    TextField("https://\u{2026}", text: optional(action.url)).font(.system(size: 12, design: .monospaced))
                    TokenMenu(model: model) { action.wrappedValue.url = (action.wrappedValue.url ?? "") + $0 }
                }
                note("Opens in your browser. Tokens such as {url} are filled in from the notification. Only http, https and mailto links open.")
            }
        case .command:
            Section("Shell command") {
                TextEditor(text: optional(action.command)).font(.system(size: 12, design: .monospaced)).frame(height: 80)
                note("Runs with /bin/zsh -lc. The notification arrives as JSON on stdin and as HERALD_* variables, never pasted into the command line. Herald asks you to confirm it once per template.")
            }
        case .script: scriptSection
        case .shortcut: shortcutSection
        case .callback:
            Section("Payload sent to the issuer") {
                TextEditor(text: $payloadText).font(.system(size: 12, design: .monospaced)).frame(height: 70)
                    .onChange(of: payloadText) { t in
                        let trimmed = t.trimmingCharacters(in: .whitespacesAndNewlines)
                        let v = trimmed.isEmpty ? nil : try? HeraldJSON.decoder().decode(JSONValue.self, from: Data(trimmed.utf8))
                        if trimmed.isEmpty || v != nil { request.action.callback = HeraldCallback(url: nil, payload: v) }
                    }
                if payloadError { Text("Not valid JSON.").font(.caption).foregroundStyle(.red) }
                note("POSTed to the issuing app\u{2019}s callback URL together with the notification id and your extra values. Leave empty to send just the press.")
            }
        case .snooze:
            Section("Snooze") {
                Stepper("For \(request.action.snoozeMinutes ?? HeraldAction.defaultSnoozeMinutes) min",
                        value: Binding(get: { request.action.snoozeMinutes ?? HeraldAction.defaultSnoozeMinutes },
                                       set: { request.action.snoozeMinutes = $0 }), in: 1...10080, step: 5)
                HStack {
                    ForEach([(5, "5 min"), (15, "15 min"), (60, "1 h"), (240, "4 h"), (1440, "1 day")], id: \.0) { m in
                        Button(m.1) { request.action.snoozeMinutes = m.0 }.controlSize(.small)
                    }
                }
            }
        case .dismiss:
            Section { note("Closes the banner.") }
        }
    }

    private func note(_ s: String) -> some View {
        Text(s).font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }

    private func optional(_ b: Binding<String?>) -> Binding<String> {
        Binding(get: { b.wrappedValue ?? "" }, set: { b.wrappedValue = $0.isEmpty ? nil : $0 })
    }

    // MARK: Script

    @ViewBuilder private var scriptSection: some View {
        let files = model.backend.scripts()
        Section("Script") {
            HStack {
                TextField("script.sh", text: optional(action.script)).font(.system(size: 12, design: .monospaced))
                Menu {
                    if files.isEmpty { Text("The scripts folder is empty") }
                    ForEach(files, id: \.self) { f in Button(f) { request.action.script = f } }
                } label: { Image(systemName: "chevron.down.circle") }
                    .menuStyle(.borderlessButton).fixedSize()
            }
            if let folder = model.backend.scriptsFolder() {
                Button { NSWorkspace.shared.open(folder) } label: { Label("Open scripts folder", systemImage: "folder") }
                    .buttonStyle(.borderless).controlSize(.small)
            }
            note("A file in Herald\u{2019}s scripts folder. It gets the notification as JSON on stdin and HERALD_* variables, and runs after one confirmation per template.")
        }
    }

    // MARK: Shortcut

    @ViewBuilder private var shortcutSection: some View {
        Section("Apple Shortcut") {
            HStack {
                TextField("Shortcut name", text: optional(action.shortcut))
                Button { Task { await loadShortcuts() } } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless).help("Reload the list of Shortcuts")
            }
            shortcutList
            Picker("Input", selection: Binding(get: { request.action.input != nil },
                                               set: { request.action.input = $0 ? (request.action.input ?? "{title}\n{url}") : nil })) {
                Text("Notification (JSON)").tag(false)
                Text("Text").tag(true)
            }
            .pickerStyle(.segmented)
            if request.action.input != nil {
                HStack(alignment: .top) {
                    TextEditor(text: optional(action.input)).font(.system(size: 12, design: .monospaced)).frame(height: 64)
                    TokenMenu(model: model) { action.wrappedValue.input = (action.wrappedValue.input ?? "") + $0 }
                }
                note("Handed to the Shortcut as text; tokens such as {title} are filled in.")
            } else {
                note("The Shortcut receives the whole notification as JSON: its fields, your extra values and the original payload.")
            }
        }
    }

    @ViewBuilder private var shortcutList: some View {
        switch shortcuts {
        case .idle, .loading:
            HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Asking Shortcuts\u{2026}").font(.caption).foregroundStyle(.secondary) }
        case .failed(let why):
            VStack(alignment: .leading, spacing: 4) {
                Text(why).font(.caption).foregroundStyle(.red)
                Text("You can still type the name of a Shortcut above.").font(.caption2).foregroundStyle(.secondary)
            }
        case .loaded(let names):
            if names.isEmpty {
                HStack {
                    Text("No Shortcuts found.").font(.caption).foregroundStyle(.secondary)
                    Button("Open Shortcuts") { NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Shortcuts.app")) }
                        .buttonStyle(.borderless).controlSize(.small)
                }
            } else {
                let shown = query.isEmpty ? names : names.filter { $0.localizedCaseInsensitiveContains(query) }
                if names.count > 8 { TextField("Search \(names.count) Shortcuts", text: $query).textFieldStyle(.roundedBorder).controlSize(.small) }
                List(shown, id: \.self, selection: Binding<String?>(get: { request.action.shortcut }, set: { if let n = $0 { request.action.shortcut = n } })) { name in
                    Label(name, systemImage: "wand.and.stars").lineLimit(1)
                }
                .listStyle(.bordered)
                .frame(height: 118)
            }
        }
    }

    private func loadShortcuts() async {
        shortcuts = .loading
        do { shortcuts = .loaded(try await model.backend.shortcuts()) }
        catch { shortcuts = .failed(error.localizedDescription) }
    }
}
