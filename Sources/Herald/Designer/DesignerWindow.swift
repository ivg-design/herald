import SwiftUI
import AppKit
import Combine
import UniformTypeIdentifiers

// The "Design Template" window (DESIGN 7.4): issuer and template list and the palette on the left, the
// editing canvas and a live preview in the middle, the inspector on the right. A mode switch on top turns the
// same window into Quick send (the old Compose form, issue #31). `DesignerWindow.show` opens (or re-focuses)
// it; `DesignerView` is the root; `DesignerBackend.live` connects the model to the app.

// MARK: - Alerts

enum DesignerAlerts {
    @MainActor
    static func confirm(title: String, message: String, confirm: String, destructive: Bool = false) -> Bool {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = message
        if destructive { a.alertStyle = .warning }
        a.addButton(withTitle: confirm)
        a.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        return a.runModal() == .alertFirstButtonReturn
    }

    /// The name of an imported template is taken: keep both, replace, or cancel (nil).
    @MainActor
    static func chooseConflict(_ preview: TemplateBundleService.Preview) -> TemplateBundleService.Conflict? {
        let a = NSAlert()
        a.messageText = "A template named \u{201C}\(preview.name)\u{201D} already exists"
        a.informativeText = "Keep both saves the imported one as \u{201C}\(HeraldTemplateBundle.uniqueName(preview.name, taken: [preview.name]))\u{201D}. Replace overwrites the one you have."
        a.addButton(withTitle: "Keep Both")
        a.addButton(withTitle: "Replace")
        a.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        switch a.runModal() {
        case .alertFirstButtonReturn: return .keepBoth
        case .alertSecondButtonReturn: return .replace
        default: return nil
        }
    }

    /// A one-line text prompt; nil when cancelled.
    @MainActor
    static func prompt(title: String, message: String, placeholder: String) -> String? {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = message
        a.addButton(withTitle: "OK")
        a.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.placeholderString = placeholder
        a.accessoryView = field
        a.window.initialFirstResponder = field
        NSApp.activate(ignoringOtherApps: true)
        return a.runModal() == .alertFirstButtonReturn ? field.stringValue : nil
    }
}

// MARK: - Backend

extension DesignerBackend {
    /// The live backend: everything goes through the in-process controller, like the HTTP API does.
    @MainActor
    static func live(_ c: AppController) -> DesignerBackend {
        var b = DesignerBackend()
        b.issuers = {
            var found: [String: DesignerIssuer] = [:]
            for m in c.manifestList() { found[m.app] = DesignerIssuer(id: m.app, name: m.appName, hasManifest: true) }
            for r in c.registeredApps() where found[r.app] == nil {
                found[r.app] = DesignerIssuer(id: r.app, name: r.appName ?? r.app, hasManifest: false)
            }
            for t in c.templateList(app: nil) where found[t.app] == nil {
                found[t.app] = DesignerIssuer(id: t.app, name: c.registry.record(for: t.app)?.displayName ?? t.app, hasManifest: false)
            }
            return Array(found.values)
        }
        b.manifest = { c.manifest(app: $0) }
        b.templates = { c.templateList(app: $0) }
        b.saveTemplate = { (try? c.putTemplate($0)) != nil }
        b.deleteTemplate = { app, name in (try? c.deleteTemplate(app: app, name: name)) != nil }
        b.setDefaultTemplate = { app, name in
            var m = c.manifest(app: app) ?? HeraldManifest(app: app, appName: c.registry.record(for: app)?.displayName)
            m.defaultTemplate = name
            return (try? c.putManifest(m)) != nil
        }
        b.lastItem = { app in c.history.items(app: app, limit: 1).first }
        b.shortcuts = { try await c.shortcutNames() }
        b.scripts = { c.actionRunner.listScripts().map(\.name) }
        b.scriptsFolder = { c.actionRunner.ensureScriptsDirectory(); return c.actionRunner.scriptsDirectory }
        b.sendTest = { try await c.notify($0) }

        // Animations (issue #33): the app's assets folder, through the asset store the banners use.
        let assets = AssetStore.shared
        b.assetFiles = { assets.list(app: $0) }
        b.installAsset = { app, asset in try assets.install(asset, app: app) }
        b.removeAssetFile = { app, url in
            // Only files that sit directly in the app's own folder.
            guard url.deletingLastPathComponent().standardizedFileURL == assets.folder(for: app).standardizedFileURL else { return false }
            return (try? FileManager.default.removeItem(at: url)) != nil
        }
        b.riveFile = { app, component in try? assets.resolve(component, app: app, manifest: c.manifest(app: app)) }
        b.riveInfo = { url in MainActor.assumeIsolated { RiveFileInspector.read(url) } }

        // Template bundles (issue #30).
        let bundles = TemplateBundleService(templates: c.templates, assets: assets, manifest: { c.manifest(app: $0) })
        b.exportBundle = { try bundles.export($0) }
        b.previewBundle = { try bundles.preview($0, intoApp: $1) }
        b.importBundle = { data, app, conflict in
            try bundles.importBundle(data, intoApp: app, onConflict: conflict) { try c.putTemplate($0) }
        }
        return b
    }
}

extension UTType {
    /// `.heraldtemplate`: a zip with a template and its animations.
    static let heraldTemplate = UTType(filenameExtension: HeraldTemplateBundle.fileExtension, conformingTo: .zip) ?? .zip
}

// MARK: - Window

@MainActor
enum DesignerWindow {
    private static var window: NSWindow?
    private static var model: DesignerModel?
    private static var delegate: WindowDelegate?
    private static var keyMonitor: Any?
    private static var mouseMonitor: Any?
    private static var titleSubscription: AnyCancellable?

    /// Opens the designer, or brings it forward. With `app` (and `template`) it switches to that issuer's
    /// template; a window with unsaved edits asks first. `quickSend` opens it in quick-send mode (Compose...).
    static func show(controller: AppController, app: String? = nil, template: String? = nil, quickSend: Bool = false) {
        if let w = window, let m = model {
            if quickSend { m.showQuickSend(app: app) }
            else { m.showDesign(app: app, template: template) }
            NSApp.activate(ignoringOtherApps: true)
            w.makeKeyAndOrderFront(nil)
            return
        }
        let m = DesignerModel(backend: .live(controller), app: app, template: template)
        m.confirmDiscard = {
            DesignerAlerts.confirm(title: "Discard unsaved changes?",
                                   message: "\u{201C}\(m.draft.name)\u{201D} has edits that were not saved.", confirm: "Discard")
        }
        m.chooseConflict = { preview in DesignerAlerts.chooseConflict(preview) }
        if quickSend { m.showQuickSend(app: app) }
        let root = DesignerView(model: m, controller: controller,
                                iconFor: { AppIcons.icon(for: controller.registry.record(for: $0), app: $0) })
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 720),
                         styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        w.title = m.mode.windowTitle
        w.isReleasedWhenClosed = false
        w.tabbingMode = .disallowed
        w.minSize = NSSize(width: 1020, height: 620)
        w.contentView = NSHostingView(rootView: root)
        w.setContentSize(NSSize(width: 1100, height: 720))
        w.center()
        w.setFrameAutosaveName("HeraldDesigner")
        let d = WindowDelegate(model: m)
        w.delegate = d
        titleSubscription = m.$mode.removeDuplicates().sink { [weak w] mode in w?.title = mode.windowTitle }
        window = w; model = m; delegate = d
        installKeyMonitor()
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }

    private static func teardown() {
        if let k = keyMonitor { NSEvent.removeMonitor(k) }
        if let k = mouseMonitor { NSEvent.removeMonitor(k) }
        titleSubscription = nil
        keyMonitor = nil; mouseMonitor = nil; window = nil; model = nil; delegate = nil
    }

    /// Delete removes the selected component, but only while no text field is being edited. A mouse press forgets
    /// the drag of an earlier gesture (SwiftUI reports no end for a drag that was cancelled), so the canvas never
    /// previews a drop from a drag that is long over.
    private static func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let consumed = MainActor.assumeIsolated { consumesDelete(event) }
            return consumed ? nil : event
        }
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { event in
            MainActor.assumeIsolated { if event.window === window { model?.endDrag() } }
            return event
        }
    }

    private static func consumesDelete(_ event: NSEvent) -> Bool {
        guard let w = window, event.window === w, let m = model,
              [51, 117].contains(event.keyCode),
              event.modifierFlags.intersection([.command, .option, .control]).isEmpty,
              !(w.firstResponder is NSText), m.selectedCell != nil, m.actionEditor == nil else { return false }
        m.deleteSelection()
        return true
    }

    private final class WindowDelegate: NSObject, NSWindowDelegate {
        let model: DesignerModel
        init(model: DesignerModel) { self.model = model }

        func windowShouldClose(_ sender: NSWindow) -> Bool {
            MainActor.assumeIsolated {
                guard model.isDirty else { return true }
                let a = NSAlert()
                a.messageText = "Save changes to \u{201C}\(model.draft.name)\u{201D}?"
                a.informativeText = "Your changes will be lost if you do not save them."
                a.addButton(withTitle: "Save")
                a.addButton(withTitle: "Don\u{2019}t Save")
                a.addButton(withTitle: "Cancel")
                switch a.runModal() {
                case .alertFirstButtonReturn: return model.save()
                case .alertSecondButtonReturn: return true
                default: return false
                }
            }
        }

        func windowWillClose(_ notification: Notification) {
            MainActor.assumeIsolated { DesignerWindow.teardown() }
        }
    }
}

// MARK: - Root view

struct DesignerView: View {
    @ObservedObject var model: DesignerModel
    let controller: AppController
    let iconFor: (String) -> NSImage

    private var scheme: ColorScheme { model.appearance == .dark ? .dark : .light }

    var body: some View {
        VStack(spacing: 0) {
            DesignerModeBar(model: model)
            Divider()
            switch model.mode {
            case .design: designContent
            case .quickSend:
                QuickSendView(controller: controller, model: model.quickSend, openDesigner: { model.showDesign(app: $0.isEmpty ? nil : $0) })
            }
        }
        .frame(minWidth: 1020, minHeight: 620)
        .onReceive(NotificationCenter.default.publisher(for: .heraldChanged)) { _ in model.refreshFromDisk() }
        .sheet(item: $model.actionEditor) { req in ActionFormView(model: model, request: req) }
        .task(id: model.status) {
            guard let s = model.status else { return }
            try? await Task.sleep(nanoseconds: s.kind == .error ? 10_000_000_000 : 5_000_000_000)
            if model.status == s { model.status = nil }
        }
        // A .heraldtemplate dropped from Finder is imported.
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            guard model.mode == .design, let item = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }) else { return false }
            _ = item.loadObject(ofClass: URL.self) { url, _ in
                guard let url, url.pathExtension.lowercased() == HeraldTemplateBundle.fileExtension else { return }
                DispatchQueue.main.async { MainActor.assumeIsolated { DesignerBundleActions.importFile(url, model: model) } }
            }
            return true
        }
    }

    private var designContent: some View {
        HStack(spacing: 0) {
            PaletteView(model: model).frame(width: 226)
            Divider()
            VStack(spacing: 0) {
                DesignerTopBar(model: model)
                Divider()
                GridCanvasView(model: model, appName: model.issuerName, icon: iconFor(model.app))
                    .environment(\.colorScheme, scheme)
                    .frame(minHeight: 180)
                Divider()
                DesignerLivePreview(model: model, appName: model.issuerName, icon: iconFor(model.app))
                    .environment(\.colorScheme, scheme)
                Divider()
                DesignerPreviewBar(model: model)
            }
            .frame(minWidth: 460)
            Divider()
            InspectorView(model: model)
        }
    }
}

// MARK: - Mode bar and bundles

/// The strip on top: Design | Quick send, and (in Design mode) Import... / Export... of `.heraldtemplate` bundles.
private struct DesignerModeBar: View {
    @ObservedObject var model: DesignerModel

    var body: some View {
        HStack(spacing: 10) {
            Picker("", selection: Binding(get: { model.mode }, set: { m in
                if m == .quickSend { model.showQuickSend() } else { model.showDesign() }
            })) {
                ForEach(DesignerMode.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden().frame(width: 190)
            .help("Design a template, or send a one-off notification")
            Spacer(minLength: 8)
            if model.mode == .design {
                Button { DesignerBundleActions.importPanel(model: model) } label: { Label("Import\u{2026}", systemImage: "square.and.arrow.down") }
                    .help("Add a template bundle (.heraldtemplate) with its animations. You can also drop one on this window.")
                Button { DesignerBundleActions.exportPanel(model: model) } label: { Label("Export\u{2026}", systemImage: "square.and.arrow.up") }
                    .disabled(model.draft.name.trimmingCharacters(in: .whitespaces).isEmpty || model.app.isEmpty)
                    .help("Save this template and the animations it plays as a .heraldtemplate bundle")
            }
        }
        .controlSize(.small)
        .padding(.horizontal, 12).padding(.vertical, 6)
    }
}

/// The panels and confirmation around template import and export (the work itself is `TemplateBundleService`'s).
@MainActor
enum DesignerBundleActions {
    static func exportPanel(model: DesignerModel) {
        let p = NSSavePanel()
        p.title = "Export Template"
        p.message = "The template and the animations it plays are saved together in one file."
        p.allowedContentTypes = [.heraldTemplate]
        p.nameFieldStringValue = model.suggestedBundleName
        p.canCreateDirectories = true
        guard p.runModal() == .OK, let url = p.url else { return }
        model.exportDraft(to: url)
    }

    static func importPanel(model: DesignerModel) {
        let p = NSOpenPanel()
        p.title = "Import Template"
        p.allowedContentTypes = [.heraldTemplate]
        p.allowsMultipleSelection = false
        p.canChooseDirectories = false
        guard p.runModal() == .OK, let url = p.url else { return }
        importFile(url, model: model)
    }

    /// Reads the bundle, says what is in it and for which app, then imports. When the bundle is for another app
    /// than the one being designed, a checkbox offers to import it for this one instead.
    static func importFile(_ url: URL, model: DesignerModel) {
        guard let (data, preview) = model.previewBundle(at: url) else { return }
        let a = NSAlert()
        a.messageText = "Import \u{201C}\(preview.name)\u{201D}?"
        let n = preview.assetFiles.count
        a.informativeText = "A template for \(preview.app)" + (n > 0 ? " with \(n) animation file\(n == 1 ? "" : "s"): \(preview.assetFiles.prefix(4).joined(separator: ", "))\(n > 4 ? ", ..." : "")." : ".")
        a.addButton(withTitle: "Import")
        a.addButton(withTitle: "Cancel")
        var retarget: NSButton?
        if !model.app.isEmpty, model.app != preview.app {
            let box = NSButton(checkboxWithTitle: "Import it for \(model.issuerName) instead", target: nil, action: nil)
            box.sizeToFit()
            a.accessoryView = box
            retarget = box
        }
        NSApp.activate(ignoringOtherApps: true)
        guard a.runModal() == .alertFirstButtonReturn else { return }
        model.importBundle(data, intoApp: retarget?.state == .on ? model.app : nil)
    }
}

// MARK: - Top bar

private struct DesignerTopBar: View {
    @ObservedObject var model: DesignerModel

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(model.draft.name.isEmpty ? "Untitled" : model.draft.name).font(.headline).lineLimit(1).truncationMode(.middle)
                Text(model.isNew ? "Not saved yet" : model.isDirty ? "Unsaved changes" : model.issuerName)
                    .font(.caption).foregroundStyle(model.isDirty || model.isNew ? Color.orange : Color.secondary).lineLimit(1)
            }
            .layoutPriority(-1)
            Spacer(minLength: 4)
            Group {
                Button { model.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                    .keyboardShortcut("z", modifiers: .command).disabled(!model.canUndo).help("Undo (\u{2318}Z)")
                Button { model.redo() } label: { Image(systemName: "arrow.uturn.forward") }
                    .keyboardShortcut("z", modifiers: [.command, .shift]).disabled(!model.canRedo).help("Redo (\u{21E7}\u{2318}Z)")
                Divider().frame(height: 16)
                Button { model.mergeSelection() } label: { Label("Merge", systemImage: "rectangle.compress.vertical") }
                    .disabled(!model.canMerge).help("Join the selected slots into one cell (shift-click to select several)")
                Button { model.splitSelection() } label: { Label("Split", systemImage: "rectangle.expand.vertical") }
                    .disabled(!model.canSplit).help("Cut a merged cell back into single slots")
                Divider().frame(height: 16)
                Button { model.duplicateSelection() } label: { Image(systemName: "plus.square.on.square") }
                    .keyboardShortcut("d", modifiers: .command).disabled(model.selectedCell == nil).help("Duplicate the selected component (\u{2318}D)")
                Button { model.deleteSelection() } label: { Image(systemName: "trash") }
                    .keyboardShortcut(.delete, modifiers: .command).disabled(model.selectedCell == nil)
                    .help("Remove the selected component (Delete)")
            }
            .controlSize(.small)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }
}

// MARK: - Live preview

private struct HeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// The banner exactly as a delivery draws it: collapsing applied, Rive running, over a desktop-like backdrop.
private struct DesignerLivePreview: View {
    @ObservedObject var model: DesignerModel
    let appName: String
    let icon: NSImage
    @State private var height: CGFloat = 150

    var body: some View {
        let banner = DesignerPreview.bannerModel(model, appName: appName, icon: icon, live: true)
        ScrollView(.vertical, showsIndicators: false) {
            HStack {
                Spacer(minLength: 0)
                BannerPreviewView(model: banner, scheme: model.appearance == .dark ? .dark : .light)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 8)
            .background(GeometryReader { Color.clear.preference(key: HeightKey.self, value: $0.size.height) })
        }
        .frame(height: min(max(height, 110), 270))
        .onPreferenceChange(HeightKey.self) { height = $0 }
        .overlay(alignment: .topLeading) {
            Text("Live preview").font(.system(size: 10, weight: .semibold)).foregroundStyle(.white.opacity(0.9))
                .padding(.horizontal, 6).padding(.vertical, 2).background(Capsule().fill(Color.black.opacity(0.35))).padding(8)
        }
    }
}

// MARK: - Preview bar

private struct DesignerPreviewBar: View {
    @ObservedObject var model: DesignerModel
    @State private var showFields = false
    @State private var showIssues = false

    var body: some View {
        VStack(spacing: 6) {
            if let s = model.status {
                Text(s.text).font(.caption).foregroundStyle(s.kind == .error ? Color.red : Color.secondary)
                    .lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: 8) {
                Picker("", selection: $model.previewSource) {
                    ForEach(DesignerPreviewSource.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 140)
                .help(model.lastItem == nil ? "No notification from this issuer yet: Last real shows the sample" : "Sample data from the manifest, or the newest real notification")
                Picker("", selection: $model.appearance) {
                    Image(systemName: "sun.max").tag(DesignerAppearance.light)
                    Image(systemName: "moon").tag(DesignerAppearance.dark)
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 70).help("Preview in light or dark appearance")
                Button { showFields.toggle() } label: {
                    Label(model.absentTokens.isEmpty ? "Fields" : "\(model.absentTokens.count) absent", systemImage: "eye")
                }
                .controlSize(.small).fixedSize().help("Preview a field as absent to see how the template handles it")
                .popover(isPresented: $showFields, arrowEdge: .top) { FieldsPopover(model: model) }
                if !model.issues.isEmpty {
                    Button { showIssues.toggle() } label: {
                        Label("\(model.issues.count)", systemImage: model.hasErrors ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(model.hasErrors ? Color.red : Color.orange)
                    }
                    .controlSize(.small).fixedSize().help("Problems found in the template")
                    .popover(isPresented: $showIssues, arrowEdge: .top) { IssuesPopover(model: model) }
                }
                Spacer(minLength: 0)
                Button { Task { await model.sendTest() } } label: {
                    if model.sending { ProgressView().controlSize(.small) } else { Label("Send test", systemImage: "paperplane") }
                }
                .controlSize(.small).fixedSize().disabled(model.sending || model.app.isEmpty)
                .help("Show this banner on screen through Herald, with the preview data")
                Button { model.save() } label: { Text("Save") }
                    .keyboardShortcut("s", modifiers: .command).disabled(!model.canSave).buttonStyle(.borderedProminent).controlSize(.small)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }
}

private struct FieldsPopover: View {
    @ObservedObject var model: DesignerModel

    private var tokens: [TokenSuggestion] {
        let used = Set(model.draft.referencedTokens)
        return model.tokenSuggestions.filter { used.contains($0.key) || $0.group == .issuer }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Preview with these fields").font(.headline)
            Text("Untick a field to see the banner without it, and what collapses.").font(.caption).foregroundStyle(.secondary)
            if tokens.isEmpty { Text("The template uses no fields yet.").font(.caption) }
            ForEach(tokens) { t in
                Toggle(isOn: Binding(get: { !model.absentTokens.contains(t.key) }, set: { on in
                    if on { model.absentTokens.remove(t.key) } else { model.absentTokens.insert(t.key) }
                })) {
                    HStack(spacing: 6) {
                        Text(t.token).font(.system(size: 12, design: .monospaced))
                        if let s = t.sample, !s.isEmpty { Text(s).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                    }
                }
                .toggleStyle(.checkbox)
            }
            if !model.absentTokens.isEmpty { Button("All present") { model.absentTokens = [] }.controlSize(.small) }
        }
        .padding(14).frame(width: 300)
    }
}

private struct IssuesPopover: View {
    @ObservedObject var model: DesignerModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(model.issues.indices, id: \.self) { i in
                    let issue = model.issues[i]
                    Button { if let c = issue.cellId { model.select(cell: c) } } label: {
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: issue.isError ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                                .foregroundStyle(issue.isError ? Color.red : Color.orange)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(issue.message).font(.caption).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                                Text(issue.cellId.map { "cell \($0) \u{00B7} \(issue.path)" } ?? issue.path).font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(14)
        }
        .frame(width: 340, height: min(CGFloat(model.issues.count) * 44 + 28, 320))
    }
}
