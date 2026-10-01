import SwiftUI
import AppKit

// The "Design Template" window (DESIGN 7.4): issuer and template list and the palette on the left, the
// editing canvas and a live preview in the middle, the inspector on the right. `DesignerWindow.show` opens
// (or re-focuses) it; `DesignerView` is the root; `DesignerBackend.live` connects the model to the app.

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
        return b
    }
}

// MARK: - Window

@MainActor
enum DesignerWindow {
    private static var window: NSWindow?
    private static var model: DesignerModel?
    private static var delegate: WindowDelegate?
    private static var keyMonitor: Any?

    /// Opens the designer, or brings it forward. With `app` (and `template`) it switches to that issuer's
    /// template; a window with unsaved edits asks first.
    static func show(controller: AppController, app: String? = nil, template: String? = nil) {
        if let w = window, let m = model {
            if let app { m.switchIssuer(app, template: template, force: false); if let template, app == m.app { m.select(template: template) } }
            NSApp.activate(ignoringOtherApps: true)
            w.makeKeyAndOrderFront(nil)
            return
        }
        let m = DesignerModel(backend: .live(controller), app: app, template: template)
        m.confirmDiscard = {
            DesignerAlerts.confirm(title: "Discard unsaved changes?",
                                   message: "\u{201C}\(m.draft.name)\u{201D} has edits that were not saved.", confirm: "Discard")
        }
        let root = DesignerView(model: m, iconFor: { AppIcons.icon(for: controller.registry.record(for: $0), app: $0) })
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 720),
                         styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        w.title = "Design Template"
        w.isReleasedWhenClosed = false
        w.tabbingMode = .disallowed
        w.minSize = NSSize(width: 1020, height: 620)
        w.contentView = NSHostingView(rootView: root)
        w.setContentSize(NSSize(width: 1100, height: 720))
        w.center()
        w.setFrameAutosaveName("HeraldDesigner")
        let d = WindowDelegate(model: m)
        w.delegate = d
        window = w; model = m; delegate = d
        installKeyMonitor()
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }

    private static func teardown() {
        if let k = keyMonitor { NSEvent.removeMonitor(k) }
        keyMonitor = nil; window = nil; model = nil; delegate = nil
    }

    /// Delete removes the selected component, but only while no text field is being edited.
    private static func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let consumed = MainActor.assumeIsolated { consumesDelete(event) }
            return consumed ? nil : event
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
    let iconFor: (String) -> NSImage

    private var scheme: ColorScheme { model.appearance == .dark ? .dark : .light }

    var body: some View {
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
        .frame(minWidth: 1020, minHeight: 620)
        .onReceive(NotificationCenter.default.publisher(for: .heraldChanged)) { _ in model.refreshFromDisk() }
        .sheet(item: $model.actionEditor) { req in ActionFormView(model: model, request: req) }
        .task(id: model.status) {
            guard let s = model.status else { return }
            try? await Task.sleep(nanoseconds: s.kind == .error ? 10_000_000_000 : 5_000_000_000)
            if model.status == s { model.status = nil }
        }
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
