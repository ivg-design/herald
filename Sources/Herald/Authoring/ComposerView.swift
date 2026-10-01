import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Composer window content

/// The authoring window (DESIGN section 6): a form on the left, a live preview on the right, and a
/// bar of actions underneath. The preview is `BannerView` itself (through `BannerPreviewFactory`), fed
/// the template-RESOLVED notification, so what is drawn here is what a real banner will show.
@MainActor
struct ComposerView: View {
    let controller: AppController
    @StateObject private var model: ComposerModel
    @StateObject private var imageLoader = ComposerImageLoader()
    @State private var templates: [HeraldTemplate] = []
    @State private var status: Status?
    @State private var sending = false
    @State private var showSaveSheet = false
    @State private var newTemplateName = ""

    enum Status: Equatable {
        case info(String), error(String)
        var text: String { switch self { case .info(let s), .error(let s): return s } }
        var isError: Bool { if case .error = self { return true }; return false }
    }

    init(controller: AppController, app: String? = nil) {
        self.controller = controller
        let first = app ?? controller.registry.all().first?.registration.app ?? ""
        _model = StateObject(wrappedValue: ComposerModel(app: first))
    }

    /// Opens on an existing model (a seam for snapshot rendering and for opening the composer prefilled).
    init(controller: AppController, model: ComposerModel) {
        self.controller = controller
        _model = StateObject(wrappedValue: model)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                formColumn.frame(minWidth: 400, maxWidth: .infinity)
                Divider()
                previewColumn.frame(width: 440)
            }
            Divider()
            actionBar
        }
        .frame(minWidth: 860, minHeight: 560)
        .onAppear {
            reloadTemplates()
            imageLoader.load(model.resolved.image ?? "")
        }
        .onChange(of: model.app) { _ in
            if let t = model.template, t.app != model.app.trimmingCharacters(in: .whitespacesAndNewlines) { model.applyTemplate(nil) }
            reloadTemplates()
        }
        .onChange(of: model.resolved.image) { imageLoader.load($0 ?? "") }
        .onReceive(NotificationCenter.default.publisher(for: .heraldChanged)) { _ in reloadTemplates() }
        .sheet(isPresented: $showSaveSheet) { saveSheet }
    }

    // MARK: Form

    private var formColumn: some View {
        Form {
            identitySection
            contentSection
            Section("Buttons") { ComposerButtonsEditor(buttons: $model.buttons) }
            behaviorSection
            lookSection
            metadataSection
        }
        .formStyle(.grouped)
    }

    private var identitySection: some View {
        Section("Notification") {
            HStack {
                TextField("App", text: $model.app, prompt: Text("app id, e.g. bidbot"))
                Menu {
                    ForEach(controller.registry.all(), id: \.registration.app) { r in
                        Button(r.displayName) { model.app = r.registration.app }
                    }
                } label: { Image(systemName: "chevron.up.chevron.down") }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                    .help("Registered apps. Any other id is accepted too.")
            }
            Picker("Template", selection: templateTag) {
                Text("None").tag("")
                ForEach(templates) { Text($0.name).tag($0.name) }
            }
            TextField("ID", text: $model.notificationID, prompt: Text("optional, replaces the banner with this id"))
        }
    }

    private var templateTag: Binding<String> {
        Binding(get: { model.template?.name ?? "" },
                set: { name in model.applyTemplate(templates.first { $0.name == name }) })
    }

    private var contentSection: some View {
        Section {
            TextField("Title", text: $model.title)
            TextField("Subtitle", text: $model.subtitle)
            TextField("Body", text: $model.body, axis: .vertical).lineLimit(3...8)
            HStack {
                TextField("Image", text: $model.imageSpec, prompt: Text("file path, https URL or data: URI"))
                Button("Browse\u{2026}", action: browseImage)
            }
            TextField("Click URL", text: $model.clickURL, prompt: Text("opened when the banner is clicked"))
        } header: { Text("Content") } footer: {
            Text("Body supports [text](url) links. {name} is filled from the metadata rows below.")
        }
    }

    private var behaviorSection: some View {
        Section("Behavior") {
            HStack {
                Picker("Sound", selection: $model.soundSelection) {
                    Text("App default").tag("")
                    Text("None").tag("none")
                    Divider()
                    ForEach(soundNames, id: \.self) { Text($0).tag($0) }
                    Divider()
                    Text("Custom file\u{2026}").tag(ComposerModel.customSoundTag)
                }
                Button(action: playSound) { Image(systemName: "play.fill") }
                    .buttonStyle(.borderless).help("Preview the sound")
            }
            if model.soundSelection == ComposerModel.customSoundTag {
                HStack {
                    TextField("Sound file", text: $model.customSoundPath, prompt: Text("path to an audio file"))
                    Button("Browse\u{2026}", action: browseSound)
                }
            }
            Picker("Stay on screen", selection: persistentTag) {
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

    private var soundNames: [String] {
        var names = SoundPlayer.systemSoundNames
        let s = model.soundSelection
        // A template can name a sound this Mac does not have; keep it selectable instead of blanking the picker.
        if !s.isEmpty, s != "none", s != ComposerModel.customSoundTag, !names.contains(s) { names.append(s) }
        return names
    }

    private var persistentTag: Binding<Int> {
        Binding(get: { model.persistent.map { $0 ? 1 : 0 } ?? -1 },
                set: { model.persistent = $0 < 0 ? nil : $0 == 1 })
    }

    private var lookSection: some View {
        Section("Look") {
            Picker("Layout", selection: $model.layout) {
                ForEach(HeraldLayout.allCases, id: \.self) { Text(Self.layoutTitle($0)).tag($0) }
            }
            .pickerStyle(.segmented)
            ComposerColorRow(hex: $model.accentColor)
            Toggle("Show subtitle", isOn: $model.showSubtitle)
            Toggle("Show body", isOn: $model.showBody)
            Toggle("Show time", isOn: $model.showTimestamp)
            Stepper("Body lines: \(model.maxBodyLines)", value: $model.maxBodyLines, in: 1...20)
        }
    }

    static func layoutTitle(_ l: HeraldLayout) -> String {
        switch l {
        case .imageLeft: return "Left"
        case .imageRight: return "Right"
        case .hero: return "Hero"
        case .compact: return "Compact"
        }
    }

    private var metadataSection: some View {
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

    // MARK: Preview

    private var previewColumn: some View {
        let banner = previewModel()
        return ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("Preview").font(.headline)
                Text("Light").font(.caption).foregroundStyle(.secondary)
                BannerPreviewView(model: banner, scheme: .light)
                Text("Dark").font(.caption).foregroundStyle(.secondary).padding(.top, 4)
                BannerPreviewView(model: banner, scheme: .dark)
                Text(behaviorSummary).font(.caption).foregroundStyle(.secondary).padding(.top, 6)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// One model drives both appearances: the view reads the forced colour scheme from its environment.
    private func previewModel() -> BannerModel {
        let n = model.resolved
        let app = model.app.trimmingCharacters(in: .whitespacesAndNewlines)
        let record = controller.registry.record(for: app)
        return BannerPreviewFactory.model(for: n, appName: record?.displayName ?? (app.isEmpty ? "App" : app),
                                          icon: AppIcons.icon(for: record, app: app), image: imageLoader.image)
    }

    /// What the real delivery will do with sound and lifetime, so "App default" is not a mystery.
    private var behaviorSummary: String {
        let n = model.resolved
        let eff = EffectiveSettings.resolve(n, controller.registry.record(for: n.app))
        let sound = eff.sound == "none" ? "silent" : "sound \(((eff.sound as NSString).lastPathComponent as NSString).deletingPathExtension)"
        let life = eff.timeout.map { "disappears after \(ComposerModel.timeoutString($0)) s" } ?? "stays until dismissed"
        return "On delivery: \(sound), \(life)."
    }

    // MARK: Action bar

    private var actionBar: some View {
        HStack(spacing: 10) {
            statusLine
            Spacer(minLength: 8)
            Button("Clear") { model.clear(); status = nil }
            Menu("Copy as\u{2026}") {
                ForEach(CodeExportFormat.allCases) { f in Button(f.title) { copy(f) } }
            }
            .menuStyle(.borderedButton).fixedSize()
            Button("Save as Template\u{2026}") { newTemplateName = model.template?.name ?? ""; showSaveSheet = true }
                .disabled(model.app.trimmingCharacters(in: .whitespaces).isEmpty
                          || model.title.trimmingCharacters(in: .whitespaces).isEmpty)
            Button("Send Now", action: send)
                .keyboardShortcut(.return, modifiers: .command)
                .buttonStyle(.borderedProminent)
                .disabled(!model.issues.isEmpty || sending)
        }
        .padding(10)
    }

    @ViewBuilder private var statusLine: some View {
        if let issue = model.issues.first {
            Label(issue, systemImage: "exclamationmark.circle").font(.caption).foregroundStyle(.secondary).lineLimit(2)
        } else if let status {
            Label(status.text, systemImage: status.isError ? "xmark.octagon" : "checkmark.circle")
                .font(.caption).foregroundStyle(status.isError ? Color.red : Color.secondary).lineLimit(2)
        }
    }

    private var saveSheet: some View {
        let name = newTemplateName.trimmingCharacters(in: .whitespacesAndNewlines)
        let app = model.app.trimmingCharacters(in: .whitespacesAndNewlines)
        let exists = templates.contains { $0.name == name }
        return VStack(alignment: .leading, spacing: 12) {
            Text("Save as Template").font(.headline)
            Text("Stores this look, text, buttons and behavior for \(app). {placeholders} stay as typed; metadata rows are not saved.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            TextField("Template name", text: $newTemplateName).onSubmit { saveTemplate() }
            if exists {
                Label("A template with this name exists and will be replaced.", systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
            }
            HStack {
                Spacer()
                Button("Cancel") { showSaveSheet = false }.keyboardShortcut(.cancelAction)
                Button(exists ? "Replace" : "Save") { saveTemplate() }
                    .keyboardShortcut(.defaultAction).disabled(name.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 400)
    }

    // MARK: Actions

    private func reloadTemplates() {
        let app = model.app.trimmingCharacters(in: .whitespacesAndNewlines)
        // list(app:) treats an empty id as "every app", which is not what a picker for one app wants.
        let found = app.isEmpty ? [] : controller.templates.list(app: app)
        if found != templates { templates = found }
    }

    private func send() {
        let payload = model.payload
        let title = model.resolved.title
        sending = true
        Task { @MainActor in
            defer { sending = false }
            do {
                let id = try await controller.notify(payload)
                flash(.info("Sent \u{201C}\(title)\u{201D} (\(id))"))
            } catch let e as BackendError {
                flash(.error(e.message))
            } catch {
                flash(.error(error.localizedDescription))
            }
        }
    }

    private func copy(_ format: CodeExportFormat) {
        let code = CodeExport.export(model.payload, as: format)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(code, forType: .string)
        flash(.info("Copied \(format.title) code to the clipboard"))
    }

    private func saveTemplate() {
        let name = newTemplateName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let t = model.draftTemplate(named: name)
        do {
            try controller.putTemplate(t)
            reloadTemplates()
            // Make the saved template the baseline: from now on the payload is "template + overrides".
            model.applyTemplate(controller.templates.get(app: t.app, name: t.name) ?? t)
            showSaveSheet = false
            flash(.info("Saved template \u{201C}\(name)\u{201D}"))
        } catch let e as BackendError {
            flash(.error(e.message)); showSaveSheet = false
        } catch {
            flash(.error(error.localizedDescription)); showSaveSheet = false
        }
    }

    private func playSound() {
        let n = model.resolved
        let eff = EffectiveSettings.resolve(n, controller.registry.record(for: n.app))
        controller.sounds.play(eff.sound)
    }

    private func browseImage() {
        let p = NSOpenPanel()
        p.allowedContentTypes = [.image]
        p.allowsMultipleSelection = false
        if p.runModal() == .OK, let u = p.url { model.imageSpec = u.path }
    }

    private func browseSound() {
        let p = NSOpenPanel()
        p.allowedContentTypes = [.audio]
        p.allowsMultipleSelection = false
        if p.runModal() == .OK, let u = p.url { model.customSoundPath = u.path }
    }

    /// Shows a status message and clears it after a few seconds unless a newer one replaced it.
    private func flash(_ s: Status) {
        status = s
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            if status == s { status = nil }
        }
    }
}

// MARK: - Preview image

/// Loads the picture the preview shows: a file path or `data:` URI immediately, an https URL in the
/// background (a live banner downloads it too). A stale download never overwrites a newer choice.
@MainActor
final class ComposerImageLoader: ObservableObject {
    @Published private(set) var image: NSImage?
    private var spec = ""
    private var task: Task<Void, Never>?

    func load(_ raw: String) {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard s != spec else { return }
        spec = s
        task?.cancel(); task = nil
        image = nil
        guard !s.isEmpty else { return }
        if s.hasPrefix("data:") {
            if let comma = s.firstIndex(of: ","),
               let d = Data(base64Encoded: String(s[s.index(after: comma)...]), options: .ignoreUnknownCharacters) {
                image = NSImage(data: d)
            }
        } else if s.hasPrefix("http://") || s.hasPrefix("https://") {
            guard let url = URL(string: s) else { return }
            task = Task { [weak self] in
                guard let (data, _) = try? await URLSession.shared.data(from: url), !Task.isCancelled,
                      let img = NSImage(data: data), self?.spec == s else { return }
                self?.image = img
            }
        } else {
            image = NSImage(contentsOfFile: (s as NSString).expandingTildeInPath)
        }
    }
}

// MARK: - Form components

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
