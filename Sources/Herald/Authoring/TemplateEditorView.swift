import SwiftUI
import AppKit

// MARK: - Window

/// Opens (or re-focuses) the template editor for one app. One window per app so a second click on
/// "Templates…" brings the existing editor forward instead of stacking duplicates.
@MainActor
enum TemplateEditorWindow {
    private static var windows: [String: NSWindow] = [:]

    static func show(controller: AppController, app: String, template: String? = nil) {
        let w: NSWindow
        if let existing = windows[app] { w = existing } else {
            w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 980, height: 660),
                         styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
            w.title = "Templates \u{2014} \(controller.registry.record(for: app)?.displayName ?? app)"
            w.isReleasedWhenClosed = false
            w.tabbingMode = .disallowed
            w.contentView = NSHostingView(rootView: TemplateEditorView(controller: controller, app: app, initialName: template))
            w.setFrameAutosaveName("HeraldTemplateEditor")
            w.center()
            windows[app] = w
        }
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }
}

// MARK: - Editor

/// Edits the templates of one app: a list on the left, the form in the middle, and a live preview
/// (rendered by the same `BannerView` as real banners) with a sample-data drawer on the right.
struct TemplateEditorView: View {
    let controller: AppController
    let app: String
    var initialName: String?

    @State private var templates: [HeraldTemplate] = []
    /// Name the draft was loaded under; nil while it is a brand-new, never-saved template.
    @State private var savedName: String?
    @State private var draft: HeraldTemplate
    @State private var saved: HeraldTemplate?
    @State private var rows: [SampleRow] = []
    @State private var error: String?

    init(controller: AppController, app: String, initialName: String? = nil) {
        self.controller = controller
        self.app = app
        self.initialName = initialName
        _draft = State(initialValue: HeraldTemplate(name: "", app: app))
    }

    private var isDirty: Bool { saved.map { $0 != draft } ?? true }
    private var lastItem: HeraldHistoryItem? { controller.history.items(app: app, limit: 1).first }

    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 190)
            Divider()
            form.frame(minWidth: 340, maxWidth: .infinity)
            Divider()
            previewColumn.frame(width: 430)
        }
        .onAppear(perform: onAppear)
    }

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            List(selection: Binding(get: { savedName }, set: { select($0) })) {
                ForEach(templates) { t in
                    Label(t.name, systemImage: icon(for: t.layout)).tag(Optional(t.name))
                }
                if savedName == nil {
                    Label(draft.name.isEmpty ? "New template" : draft.name, systemImage: "plus.square.dashed")
                        .foregroundStyle(.secondary)
                }
            }
            Divider()
            HStack {
                Button { startNew() } label: { Label("New", systemImage: "plus") }
                Spacer()
            }
            .padding(8)
        }
    }

    private func icon(for l: HeraldLayout) -> String {
        switch l {
        case .imageLeft: return "rectangle.lefthalf.inset.filled"
        case .imageRight: return "rectangle.righthalf.inset.filled"
        case .hero: return "rectangle.tophalf.inset.filled"
        case .compact: return "minus.rectangle"
        }
    }

    // MARK: Form

    // TODO: reuse ComposerView's form components (buttons editor, sound picker) once they are
    // shared; until then these are minimal local sections.
    private var form: some View {
        VStack(spacing: 0) {
            Form {
                Section("Template") {
                    TextField("Name", text: $draft.name)
                    Picker("Layout", selection: $draft.layout) {
                        ForEach(HeraldLayout.allCases, id: \.self) { Text(Self.layoutTitle($0)).tag($0) }
                    }
                    ComposerColorRow(hex: $draft.accentColor)
                    Toggle("Show subtitle", isOn: $draft.showSubtitle)
                    Toggle("Show body", isOn: $draft.showBody)
                    Toggle("Show time", isOn: $draft.showTimestamp)
                    Stepper("Body lines: \(draft.maxBodyLines)", value: $draft.maxBodyLines, in: 1...20)
                }
                Section {
                    TextField("Title", text: optional($draft.title))
                    TextField("Subtitle", text: optional($draft.subtitle))
                    TextField("Body", text: optional($draft.body), prompt: Text("Markdown links ok"), axis: .vertical).lineLimit(2...5)
                    TextField("Image", text: optional($draft.image), prompt: Text("path, URL or data: URI"))
                    TextField("Click URL", text: optional($draft.url))
                } header: { Text("Content") } footer: {
                    Text("Use {name} for values from the notification's metadata, e.g. {amount}.")
                }
                Section("Buttons") {
                    ButtonsEditorSection(buttons: $draft.buttons)
                }
                Section("Behavior") {
                    Picker("Sound", selection: Binding(get: { draft.sound ?? "" }, set: { draft.sound = $0.isEmpty ? nil : $0 })) {
                        Text("App default").tag("")
                        Text("none").tag("none")
                        ForEach(SoundPlayer.systemSoundNames, id: \.self) { Text($0).tag($0) }
                        if let s = draft.sound, s != "none", !SoundPlayer.systemSoundNames.contains(s) {
                            Text((s as NSString).lastPathComponent).tag(s)
                        }
                    }
                    TriStatePicker(title: "Stay until dismissed", value: $draft.persistent)
                    HStack {
                        Text("Auto-dismiss after (s)")
                        Spacer()
                        TextField("inherit", value: $draft.timeout, format: .number).frame(width: 70)
                    }
                    TriStatePicker(title: "Snooze menu", value: $draft.snooze)
                    Picker("Priority", selection: Binding(get: { draft.priority ?? "" }, set: { draft.priority = $0.isEmpty ? nil : $0 })) {
                        Text("Default").tag("")
                        Text("low").tag("low")
                        Text("normal").tag("normal")
                        Text("high").tag("high")
                    }
                    TextField("Reminder title", text: reminderTitle)
                    TextField("Reminder due (ISO 8601)", text: reminderDue)
                }
            }
            .formStyle(.grouped)
            Divider()
            toolbar
        }
    }

    private var toolbar: some View {
        HStack {
            if let error { Text(error).font(.caption).foregroundStyle(.red).lineLimit(2) }
            Spacer()
            if draft.usesGrid {
                Button("Open in Designer") { DesignerWindow.show(controller: controller, app: app, template: savedName) }
                    .disabled(savedName == nil)
                    .help("Edit this grid template visually. Opens the saved version.")
            }
            Button("Delete", role: .destructive, action: delete).disabled(savedName == nil)
            Button("Duplicate", action: duplicate).disabled(savedName == nil)
            Button("Save", action: save)
                .keyboardShortcut("s", modifiers: .command)
                .disabled(!isDirty || draft.name.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(10)
    }

    static func layoutTitle(_ l: HeraldLayout) -> String {
        switch l {
        case .imageLeft: return "Image left"
        case .imageRight: return "Image right"
        case .hero: return "Hero (image on top)"
        case .compact: return "Compact (one line)"
        }
    }

    // MARK: Preview

    private var previewColumn: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Preview").font(.headline)
                ForEach([ColorScheme.light, .dark], id: \.self) { scheme in
                    previewBanner(scheme)
                }
                Divider()
                SampleDataDrawer(rows: $rows,
                                 placeholders: SampleData.placeholders(in: draft),
                                 canFillFromLast: lastItem != nil,
                                 onFillFromLast: fillFromLast)
            }
            .padding(14)
        }
    }

    /// The preview feeds a sample notification through `TemplateResolver`, exactly like POST /v1/notify,
    /// so layout, defaults, and placeholder substitution all match what a real banner will show.
    private func previewBanner(_ scheme: ColorScheme) -> some View {
        var sample = HeraldNotification(app: app, id: "template-preview", title: "")
        sample.metadata = SampleData.metadata(from: rows)
        let resolved = TemplateResolver.resolve(sample, with: draft)
        let record = controller.registry.record(for: app)
        let model = BannerPreviewFactory.model(
            for: resolved, appName: record?.displayName ?? app,
            icon: AppIcons.icon(for: record, app: app), image: Self.previewImage(resolved.image))
        return BannerPreviewView(model: model, scheme: scheme)
    }

    /// Local file or `data:` URI from the template, else a stock gradient: a real notification will
    /// bring its own picture, and an empty slot would hide what the layout does with one. Remote URLs
    /// are not fetched while typing; they get the stock picture too.
    private static func previewImage(_ spec: String?) -> NSImage {
        if let spec, !spec.isEmpty {
            if spec.hasPrefix("data:"), let comma = spec.firstIndex(of: ","),
               let d = Data(base64Encoded: String(spec[spec.index(after: comma)...]), options: .ignoreUnknownCharacters),
               let img = NSImage(data: d) { return img }
            if !spec.hasPrefix("http"), let img = NSImage(contentsOfFile: (spec as NSString).expandingTildeInPath) { return img }
        }
        return BannerSamples.image()
    }

    // MARK: Actions

    private func onAppear() {
        reload()
        if let n = initialName, let t = templates.first(where: { $0.name == n }) { load(t) }
        else if let first = templates.first { load(first) }
        else { startNew() }
    }

    private func reload() { templates = controller.templates.list(app: app) }

    private func load(_ t: HeraldTemplate) {
        draft = t; saved = t; savedName = t.name; error = nil
        rows = SampleData.merge([], placeholders: SampleData.placeholders(in: t))
    }

    private func startNew() {
        guard confirmDiscard() else { return }
        var n = 1
        while templates.contains(where: { $0.name == "template-\(n)" }) { n += 1 }
        draft = HeraldTemplate(name: "template-\(n)", app: app)
        saved = nil; savedName = nil; error = nil
        rows = []
    }

    private func select(_ name: String?) {
        guard let name, name != savedName, let t = templates.first(where: { $0.name == name }), confirmDiscard() else { return }
        load(t)
    }

    /// Asks before throwing away unsaved edits; existing-but-unchanged drafts switch silently.
    private func confirmDiscard() -> Bool {
        guard isDirty, saved != nil || draft != HeraldTemplate(name: draft.name, app: app) else { return true }
        let a = NSAlert()
        a.messageText = "Discard unsaved changes?"
        a.informativeText = "\u{201C}\(draft.name)\u{201D} has edits that were not saved."
        a.addButton(withTitle: "Discard")
        a.addButton(withTitle: "Cancel")
        return a.runModal() == .alertFirstButtonReturn
    }

    private func save() {
        let name = draft.name.trimmingCharacters(in: .whitespaces)
        guard Self.isValidName(name) else { error = "Name must not be empty or contain / or start with a dot."; return }
        if name != savedName, templates.contains(where: { $0.name == name }) { error = "A template named \u{201C}\(name)\u{201D} already exists."; return }
        draft.name = name
        draft.app = app
        guard controller.templates.put(draft) else { error = "Could not write the template file."; return }
        // Renaming = write the new file, then drop the old one.
        if let old = savedName, old != name { controller.templates.delete(app: app, name: old) }
        error = nil
        saved = draft; savedName = name
        reload()
    }

    private func duplicate() {
        guard savedName != nil else { return }
        var copy = draft
        var n = 1
        var name = draft.name + " copy"
        while templates.contains(where: { $0.name == name }) { n += 1; name = draft.name + " copy \(n)" }
        copy.name = name
        guard controller.templates.put(copy) else { error = "Could not write the template file."; return }
        reload()
        load(copy)
    }

    private func delete() {
        guard let name = savedName else { return }
        let a = NSAlert()
        a.messageText = "Delete template \u{201C}\(name)\u{201D}?"
        a.informativeText = "Notifications that reference it will fall back to plain banners."
        a.alertStyle = .warning
        a.addButton(withTitle: "Delete")
        a.addButton(withTitle: "Cancel")
        guard a.runModal() == .alertFirstButtonReturn else { return }
        controller.templates.delete(app: app, name: name)
        reload()
        saved = nil; savedName = nil
        if let first = templates.first { load(first) } else { startNew() }
    }

    /// Pulls the newest history item's metadata for this app; also adds rows for placeholders it lacks.
    private func fillFromLast() {
        guard let item = lastItem else { return }
        rows = SampleData.merge(SampleData.rows(from: item.notification.metadata), placeholders: SampleData.placeholders(in: draft))
    }

    static func isValidName(_ n: String) -> Bool {
        !n.isEmpty && !n.contains("/") && !n.contains(":") && !n.hasPrefix(".")
    }

    // MARK: Bindings

    private func optional(_ b: Binding<String?>) -> Binding<String> {
        Binding(get: { b.wrappedValue ?? "" }, set: { b.wrappedValue = $0.isEmpty ? nil : $0 })
    }
    private var reminderTitle: Binding<String> {
        Binding(get: { draft.reminder?.title ?? "" }, set: { v in updateReminder { $0.title = v.isEmpty ? nil : v } })
    }
    private var reminderDue: Binding<String> {
        Binding(get: { draft.reminder?.due ?? "" }, set: { v in updateReminder { $0.due = v.isEmpty ? nil : v } })
    }
    private func updateReminder(_ f: (inout HeraldReminder) -> Void) {
        var r = draft.reminder ?? HeraldReminder()
        f(&r)
        draft.reminder = (r.title == nil && r.due == nil) ? nil : r
    }
}

// MARK: - Small form components

/// Optional boolean as inherit / on / off, because templates distinguish "unset" from "false".
private struct TriStatePicker: View {
    let title: String
    @Binding var value: Bool?
    var body: some View {
        Picker(title, selection: Binding(get: { value.map { $0 ? 1 : 0 } ?? -1 }, set: { value = $0 < 0 ? nil : $0 == 1 })) {
            Text("Inherit").tag(-1)
            Text("On").tag(1)
            Text("Off").tag(0)
        }
    }
}


/// Minimal buttons editor: label, action kind (url / command / callback), value, style.
private struct ButtonsEditorSection: View {
    @Binding var buttons: [HeraldButton]

    private enum Kind: String, CaseIterable { case url, command, callback }

    private func kind(_ b: HeraldButton) -> Kind {
        if b.command != nil { return .command }
        if b.callback != nil { return .callback }
        return .url
    }

    private func value(_ b: HeraldButton) -> String {
        switch kind(b) {
        case .url: return b.url ?? ""
        case .command: return b.command ?? ""
        case .callback:
            guard let p = b.callback?.payload, let d = try? HeraldJSON.encoder().encode(p) else { return "" }
            return String(data: d, encoding: .utf8) ?? ""
        }
    }

    /// Rebuilds the button so exactly one action field is set, as the API requires.
    private func rebuilt(_ b: HeraldButton, kind k: Kind, value v: String) -> HeraldButton {
        var n = HeraldButton(label: b.label, style: b.style)
        switch k {
        case .url: n.url = v
        case .command: n.command = v
        case .callback:
            let payload = v.isEmpty ? nil : (try? HeraldJSON.decoder().decode(JSONValue.self, from: Data(v.utf8)))
            n.callback = HeraldCallback(payload: payload)
        }
        return n
    }

    var body: some View {
        ForEach(buttons.indices, id: \.self) { i in
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    TextField("Label", text: Binding(get: { buttons[i].label }, set: { buttons[i].label = $0 }), prompt: Text("Button label"))
                        .labelsHidden()
                    Picker("", selection: Binding(get: { kind(buttons[i]) }, set: { buttons[i] = rebuilt(buttons[i], kind: $0, value: value(buttons[i])) })) {
                        ForEach(Kind.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }.labelsHidden().frame(width: 100)
                    Picker("", selection: Binding(get: { buttons[i].style ?? "default" }, set: { buttons[i].style = $0 == "default" ? nil : $0 })) {
                        Text("default").tag("default"); Text("destructive").tag("destructive"); Text("cancel").tag("cancel")
                    }.labelsHidden().frame(width: 110)
                    Button { buttons.remove(at: i) } label: { Image(systemName: "minus.circle") }.buttonStyle(.borderless)
                }
                TextField(kind(buttons[i]) == .callback ? "Callback payload (JSON)" : (kind(buttons[i]) == .url ? "URL" : "Shell command"),
                          text: Binding(get: { value(buttons[i]) }, set: { buttons[i] = rebuilt(buttons[i], kind: kind(buttons[i]), value: $0) }))
                    .font(.system(size: 12, design: .monospaced))
            }
        }
        Button { buttons.append(HeraldButton(label: "Button", url: "")) } label: { Label("Add button", systemImage: "plus") }
    }
}
