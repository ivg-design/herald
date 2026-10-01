import SwiftUI
import AppKit
import UniformTypeIdentifiers

// The form components the authoring windows share (issue #31): the quick-send form in the Designer
// (`QuickSendView`) and the older per-app template editor (`TemplateEditorView`) build their screens from
// these, so a button row, a sound picker or a colour field looks and behaves the same everywhere.
//
//   sections   ComposerIdentitySection, ComposerContentSection, ComposerButtonsSection, ComposerBehaviorSection,
//              ComposerMetadataSection: one `Form` section each, editing a `ComposerModel`.
//   rows       ComposerButtonsEditor (rows of `ComposerButton`), HeraldButtonsEditor (the same rows over a template's
//              `[HeraldButton]`), SoundPickerRows / SoundField, ComposerColorRow.
//   panels     FormPanels: the open panels the Browse buttons use.

// MARK: - Titles

extension HeraldLayout {
    /// How a v1 layout reads in a menu or a picker.
    var formTitle: String {
        switch self {
        case .imageLeft: return "Image left"
        case .imageRight: return "Image right"
        case .hero: return "Hero (image on top)"
        case .compact: return "Compact (one line)"
        }
    }
}

// MARK: - Panels

enum FormPanels {
    @MainActor
    static func chooseFile(types: [UTType]) -> String? {
        let p = NSOpenPanel()
        p.allowedContentTypes = types
        p.allowsMultipleSelection = false
        return p.runModal() == .OK ? p.url?.path : nil
    }
}

// MARK: - Sections over a ComposerModel

/// App, template and notification id.
struct ComposerIdentitySection: View {
    @ObservedObject var model: ComposerModel
    /// Apps to offer in the menu (any other id may still be typed).
    let apps: [(id: String, name: String)]
    /// Saved templates of the chosen app.
    let templates: [HeraldTemplate]

    var body: some View {
        Section("Notification") {
            HStack {
                TextField("App", text: $model.app, prompt: Text("app id, e.g. bidbot"))
                Menu {
                    ForEach(apps, id: \.id) { a in Button(a.name) { model.app = a.id } }
                } label: { Image(systemName: "chevron.up.chevron.down") }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                    .help("Registered apps. Any other id is accepted too.")
            }
            Picker("Template", selection: Binding(get: { model.template?.name ?? "" },
                                                  set: { name in model.applyTemplate(templates.first { $0.name == name }) })) {
                Text("None").tag("")
                ForEach(templates) { Text($0.name).tag($0.name) }
            }
            TextField("ID", text: $model.notificationID, prompt: Text("optional, replaces the banner with this id"))
        }
    }
}

/// Title, subtitle, body, picture and click URL.
struct ComposerContentSection: View {
    @ObservedObject var model: ComposerModel

    var body: some View {
        Section {
            TextField("Title", text: $model.title)
            TextField("Subtitle", text: $model.subtitle)
            TextField("Body", text: $model.body, axis: .vertical).lineLimit(3...8)
            HStack {
                TextField("Image", text: $model.imageSpec, prompt: Text("file path, https URL or data: URI"))
                Button("Browse\u{2026}") { if let p = FormPanels.chooseFile(types: [.image]) { model.imageSpec = p } }
            }
            TextField("Click URL", text: $model.clickURL, prompt: Text("opened when the banner is clicked"))
        } header: { Text("Content") } footer: {
            Text("Body supports [text](url) links. {name} is filled from the metadata rows below.")
        }
    }
}

struct ComposerButtonsSection: View {
    @ObservedObject var model: ComposerModel
    var body: some View { Section("Buttons") { ComposerButtonsEditor(buttons: $model.buttons) } }
}

/// Sound, how long it stays, snooze, reminder and priority.
struct ComposerBehaviorSection: View {
    @ObservedObject var model: ComposerModel
    /// Plays the sound the form would deliver with (nil hides the play button).
    var play: (() -> Void)?

    var body: some View {
        Section("Behavior") {
            SoundPickerRows(selection: $model.soundSelection, customPath: $model.customSoundPath, play: play)
            Picker("Stay on screen", selection: Binding(get: { model.persistent.map { $0 ? 1 : 0 } ?? -1 },
                                                        set: { model.persistent = $0 < 0 ? nil : $0 == 1 })) {
                Text("Default").tag(-1)
                Text("Until dismissed").tag(1)
                Text("Auto-dismiss").tag(0)
            }
            TextField("Auto-dismiss after", text: $model.timeoutText, prompt: Text("seconds; empty for the default"))
            Toggle("Snooze menu", isOn: $model.snooze)
            Toggle("Add to Reminders button", isOn: $model.reminderOn)
            if model.reminderOn {
                TextField("Reminder title", text: $model.reminderTitle, prompt: Text("defaults to the notification title"))
                Toggle("Reminder due date", isOn: $model.reminderHasDue)
                if model.reminderHasDue {
                    DatePicker("Due", selection: $model.reminderDue, displayedComponents: [.date, .hourAndMinute])
                }
            }
            Picker("Priority", selection: $model.priority) {
                Text("Default").tag("")
                Text("Low").tag("low")
                Text("Normal").tag("normal")
                Text("High").tag("high")
            }
        }
    }
}

struct ComposerMetadataSection: View {
    @ObservedObject var model: ComposerModel

    var body: some View {
        Section {
            ForEach($model.metadata) { $row in
                HStack {
                    TextField("Key", text: $row.key, prompt: Text("key")).labelsHidden()
                    TextField("Value", text: $row.value, prompt: Text("value")).labelsHidden()
                    Button { model.metadata.removeAll { $0.id == row.id } } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.borderless).help("Remove")
                }
            }
            Button { model.metadata.append(MetadataRow()) } label: { Label("Add Row", systemImage: "plus") }
                .buttonStyle(.borderless)
        } header: { Text("Metadata") } footer: {
            Text("Sent with the notification. Each key fills the {placeholder} of the same name in a template or in the text above.")
        }
    }
}

// MARK: - Sound

/// The sound picker with its preview button and, for a file of the user's own, a path field with Browse.
/// `selection` is "" (the app's default), "none", a system sound name or `ComposerModel.customSoundTag`.
struct SoundPickerRows: View {
    @Binding var selection: String
    @Binding var customPath: String
    var play: (() -> Void)?

    private var names: [String] {
        var all = SoundPlayer.systemSoundNames
        // A template can name a sound this Mac does not have; keep it selectable instead of blanking the picker.
        if !selection.isEmpty, selection != "none", selection != ComposerModel.customSoundTag, !all.contains(selection) { all.append(selection) }
        return all
    }

    var body: some View {
        HStack {
            Picker("Sound", selection: $selection) {
                Text("App default").tag("")
                Text("None").tag("none")
                Divider()
                ForEach(names, id: \.self) { Text($0).tag($0) }
                Divider()
                Text("Custom file\u{2026}").tag(ComposerModel.customSoundTag)
            }
            if let play {
                Button(action: play) { Image(systemName: "play.fill") }.buttonStyle(.borderless).help("Preview the sound")
            }
        }
        if selection == ComposerModel.customSoundTag {
            HStack {
                TextField("Sound file", text: $customPath, prompt: Text("path to an audio file"))
                Button("Browse\u{2026}") { if let p = FormPanels.chooseFile(types: [.audio]) { customPath = p } }
            }
        }
    }
}

/// `SoundPickerRows` over a template's optional sound string (nil is the app's default). Keeps the "custom
/// file" choice while its path is still empty, which the string alone could not.
struct SoundField: View {
    @Binding var sound: String?
    var play: (() -> Void)?
    @State private var selection = ""
    @State private var customPath = ""

    var body: some View {
        SoundPickerRows(selection: $selection, customPath: $customPath, play: play)
            .onAppear(perform: load)
            .onChange(of: sound) { _ in
                // Follow outside changes (another template was loaded), not our own writes.
                if Self.value(selection, customPath) != sound { load() }
            }
            .onChange(of: selection) { _ in push() }
            .onChange(of: customPath) { _ in push() }
    }

    private func load() { (selection, customPath) = ComposerModel.soundFields(sound) }

    private func push() {
        let v = Self.value(selection, customPath)
        if v != sound { sound = v }
    }

    /// The template value for a selection: nil for the default, the path for a custom file (nil while empty).
    static func value(_ selection: String, _ path: String) -> String? {
        switch selection {
        case "": return nil
        case ComposerModel.customSoundTag: return path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : path
        default: return selection
        }
    }
}

// MARK: - Buttons

/// Rows for the buttons a notification carries: label, action kind (open a URL, post a callback, run a
/// command), its value and the visual style. Unfinished rows (no label) are ignored when building the payload.
struct ComposerButtonsEditor: View {
    @Binding var buttons: [ComposerButton]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach($buttons) { $b in
                ComposerButtonRow(button: $b) { buttons.removeAll { $0.id == b.id } }
            }
            Button { buttons.append(ComposerButton()) } label: { Label("Add Button", systemImage: "plus") }
                .buttonStyle(.borderless)
        }
    }
}

/// `ComposerButtonsEditor` over a template's `[HeraldButton]`. The rows live here as `ComposerButton`s so a
/// row without a label (just added, still being typed) survives until it is finished.
struct HeraldButtonsEditor: View {
    @Binding var buttons: [HeraldButton]
    @State private var rows: [ComposerButton] = []

    var body: some View {
        ComposerButtonsEditor(buttons: $rows)
            .onAppear { rows = buttons.map(ComposerButton.init) }
            .onChange(of: rows) { r in
                let built = r.compactMap { $0.build() }
                if built != buttons { buttons = built }
            }
            .onChange(of: buttons) { b in
                if b != rows.compactMap({ $0.build() }) { rows = b.map(ComposerButton.init) }
            }
    }
}

private struct ComposerButtonRow: View {
    @Binding var button: ComposerButton
    var onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                TextField("Label", text: $button.label, prompt: Text("Label")).labelsHidden()
                Picker("Action", selection: $button.action) {
                    Text("Open URL").tag(ComposerButton.Action.url)
                    Text("Callback").tag(ComposerButton.Action.callback)
                    Text("Command").tag(ComposerButton.Action.command)
                }
                .labelsHidden().frame(width: 104)
                Picker("Style", selection: $button.style) {
                    Text("Default").tag(ComposerButton.Style.default)
                    Text("Destructive").tag(ComposerButton.Style.destructive)
                    Text("Cancel").tag(ComposerButton.Style.cancel)
                }
                .labelsHidden().frame(width: 118)
                Button(action: onRemove) { Image(systemName: "minus.circle") }
                    .buttonStyle(.borderless).help("Remove button")
            }
            switch button.action {
            case .url:
                TextField("URL", text: $button.value, prompt: Text("https://\u{2026}")).labelsHidden()
            case .command:
                TextField("Command", text: $button.value, prompt: Text("shell command; the app must be allowed to run commands")).labelsHidden()
            case .callback:
                TextField("Callback URL", text: $button.value, prompt: Text("callback URL (optional; defaults to the app's own)")).labelsHidden()
                TextField("Payload", text: $button.payload, prompt: Text("payload JSON (optional), e.g. {\"bid\": 42}")).labelsHidden()
                if button.hasInvalidPayload {
                    Text("The payload is not valid JSON.").font(.caption).foregroundStyle(.red)
                }
            }
        }
    }
}

// MARK: - Colour

/// Accent colour as a hex string with an off state. The text field only commits a complete, valid hex,
/// so half-typed values never reach the payload.
struct ComposerColorRow: View {
    @Binding var hex: String?
    @State private var text = ""

    var body: some View {
        HStack {
            Toggle("Accent color", isOn: Binding(
                get: { hex != nil },
                set: { on in hex = on ? (hex ?? "#0A84FF") : nil }))
            Spacer()
            if hex != nil {
                ColorPicker("", selection: Binding(
                    get: { Self.color(hex ?? "") ?? .accentColor },
                    set: { hex = Self.hex($0) }), supportsOpacity: false)
                    .labelsHidden()
                TextField("Hex", text: $text, prompt: Text("#RRGGBB"))
                    .labelsHidden()
                    .lineLimit(1)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 104)
                    .onChange(of: text) { t in
                        if let n = Self.normalized(t), n != hex { hex = n }
                    }
            }
        }
        .onAppear { text = hex ?? "" }
        .onChange(of: hex) { new in
            // Keep the field in step with the colour well, but leave a half-typed value alone.
            if let new, Self.normalized(text) != new { text = new }
        }
    }

    /// `#RGB` or `#RRGGBB` (the `#` optional), upper-cased with a leading `#`; nil when incomplete or invalid.
    static func normalized(_ raw: String) -> String? {
        var s = raw.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.allSatisfy({ $0.isHexDigit }) else { return nil }
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        guard s.count == 6 else { return nil }
        return "#" + s.uppercased()
    }

    static func color(_ hex: String) -> Color? {
        guard let n = normalized(hex), let v = UInt32(n.dropFirst(), radix: 16) else { return nil }
        return Color(red: Double((v >> 16) & 255) / 255, green: Double((v >> 8) & 255) / 255, blue: Double(v & 255) / 255)
    }

    static func hex(_ c: Color) -> String {
        let ns = NSColor(c).usingColorSpace(.sRGB) ?? .systemBlue
        return String(format: "#%02X%02X%02X", Int((ns.redComponent * 255).rounded()),
                      Int((ns.greenComponent * 255).rounded()), Int((ns.blueComponent * 255).rounded()))
    }
}
