import SwiftUI
import AppKit

// Quick send (issue #31): the old Compose window as a mode of the Designer. A form on the left (the shared
// sections in FormSections.swift), a live preview on the right, and a bar of actions underneath. The preview is
// `BannerView` itself (through `BannerPreviewFactory`), fed the template-RESOLVED notification, so what is drawn
// here is what a real banner will show. How a banner LOOKS is the Designer's job (its Design mode), which the
// "Design Template" button opens for the same app.

/// The quick-send form. `model` belongs to the Designer window (`DesignerModel.quickSend`), so a half-written
/// message survives switching to Design mode and back.
@MainActor
struct QuickSendView: View {
    let controller: AppController
    @ObservedObject var model: ComposerModel
    /// Opens Design mode on this app.
    var openDesigner: (String) -> Void = { _ in }
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
            ComposerIdentitySection(model: model, apps: controller.registry.all().map { ($0.registration.app, $0.displayName) },
                                    templates: templates)
            ComposerContentSection(model: model)
            ComposerButtonsSection(model: model)
            ComposerBehaviorSection(model: model, play: playSound)
            ComposerMetadataSection(model: model)
            lookSection
        }
        .formStyle(.grouped)
    }

    /// The look of a banner moved to the Designer; this only points the way.
    private var lookSection: some View {
        Section {
            HStack {
                Text("How the banner looks comes from its template.").font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Button("Design Template\u{2026}") { openDesigner(model.app.trimmingCharacters(in: .whitespacesAndNewlines)) }
                    .controlSize(.small)
                    .heraldHelp(.designTemplate)
            }
        } header: { Text("Look") }
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
                .heraldHelp(.clear)
            Menu("Copy as\u{2026}") {
                ForEach(CodeExportFormat.allCases) { f in Button(f.title) { copy(f) }.heraldHelp(.copyFormat) }
            }
            .menuStyle(.borderedButton).fixedSize()
            .heraldHelp(.copyAs)
            Button("Save as Template\u{2026}") { newTemplateName = model.template?.name ?? ""; showSaveSheet = true }
                .disabled(model.app.trimmingCharacters(in: .whitespaces).isEmpty
                          || model.title.trimmingCharacters(in: .whitespaces).isEmpty)
                .heraldHelp(.saveAsTemplate)
            Button("Send Now", action: send)
                .keyboardShortcut(.return, modifiers: .command)
                .buttonStyle(.borderedProminent)
                .disabled(!model.issues.isEmpty || sending)
                .heraldHelp(.sendNow)
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
            TextField("Template name", text: $newTemplateName).onSubmit { saveTemplate() }.heraldHelp(.saveSheetName)
            if exists {
                Label("A template with this name exists and will be replaced.", systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
            }
            HStack {
                Spacer()
                Button("Cancel") { showSaveSheet = false }.keyboardShortcut(.cancelAction).heraldHelp(.saveSheetCancel)
                Button(exists ? "Replace" : "Save") { saveTemplate() }
                    .keyboardShortcut(.defaultAction).disabled(name.isEmpty).heraldHelp(.saveSheetSave)
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
