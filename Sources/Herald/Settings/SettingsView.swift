import SwiftUI
import AppKit

struct SettingsView: View {
    let controller: AppController
    var body: some View {
        TabView {
            GeneralSettingsView(controller: controller).tabItem { Label("General", systemImage: "gearshape") }
            AppsSettingsView(controller: controller).tabItem { Label("Apps", systemImage: "square.grid.2x2") }
        }
        .padding(16)
        .frame(minWidth: 600, minHeight: 420)
    }
}

struct GeneralSettingsView: View {
    let controller: AppController
    @ObservedObject private var settings = AppSettings.shared
    @StateObject private var ticker = ChangeTicker()
    @State private var portText = ""

    var body: some View {
        Form {
            Section {
                HStack {
                    TextField("Port", text: $portText).frame(width: 80)
                    Button("Apply") { applyPort() }
                    Button("Reset to \(HeraldPaths.defaultPort)") { portText = String(HeraldPaths.defaultPort); applyPort() }
                }
                Text({ _ = ticker.tick; return controller.serverStatus }())
                    .font(.caption).foregroundStyle(controller.serverRunning ? Color.secondary : Color.red)
                Button("Reveal Token File in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([HeraldPaths.tokenURL()])
                }
            } header: { Text("Local API") }
            Section {
                Toggle("Launch at login", isOn: Binding(get: { settings.launchAtLogin }, set: { settings.launchAtLogin = $0 }))
                Toggle("Mute all sounds", isOn: $settings.muted)
            } header: { Text("General") }
        }
        .formStyle(.grouped)
        .onAppear { portText = String(settings.effectivePort) }
    }

    private func applyPort() {
        guard let p = Int(portText), (1024...65535).contains(p) else { portText = String(settings.effectivePort); NSSound.beep(); return }
        settings.portOverride = (p == HeraldPaths.defaultPort) ? 0 : p
        controller.startServer()
    }
}

struct AppsSettingsView: View {
    let controller: AppController
    @StateObject private var ticker = ChangeTicker()
    @State private var selection: String?

    private var records: [AppRecord] { _ = ticker.tick; return controller.registry.all() }

    var body: some View {
        HStack(spacing: 0) {
            List(records, id: \.registration.app, selection: $selection) { r in
                HStack {
                    Image(nsImage: AppIcons.icon(for: r, app: r.registration.app)).resizable().frame(width: 20, height: 20)
                    Text(r.displayName)
                }.tag(r.registration.app)
            }
            .frame(width: 190)
            Divider()
            if let sel = selection, let rec = records.first(where: { $0.registration.app == sel }) {
                AppDetail(controller: controller, record: rec).id(sel + "\(ticker.tick)")
            } else {
                Text(records.isEmpty ? "Apps appear here after their first notification." : "Select an app")
                    .foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

struct AppDetail: View {
    let controller: AppController
    let record: AppRecord
    private var app: String { record.registration.app }
    private var d: HeraldAppDefaults { record.registration.defaults ?? HeraldAppDefaults() }

    private func edit(_ f: @escaping (inout AppRecord) -> Void) {
        controller.registry.update(app, f)
        AppIcons.invalidate()
        controller.changed()
    }
    private func editDefaults(_ f: @escaping (inout HeraldAppDefaults) -> Void) {
        edit { r in
            var x = r.registration.defaults ?? HeraldAppDefaults()
            f(&x)
            r.registration.defaults = x
        }
    }

    private var soundOptions: [String] {
        var opts = ["none"] + SoundPlayer.systemSoundNames
        if let s = d.sound, !opts.contains(s) { opts.append(s) }
        return opts
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("Identifier", value: app)
                if let b = record.registration.bundleId { LabeledContent("Bundle ID", value: b) }
                if let c = record.registration.callbackURL { LabeledContent("Callback URL", value: c) }
                if let host = remoteCallbackHost {
                    Text("Not on this Mac: \(host). Callback buttons send their payload there only after you approve it below.")
                        .font(.caption).foregroundStyle(.orange)
                }
            }
            Section {
                Picker("Sound", selection: Binding(
                    get: { d.sound ?? EffectiveSettings.fallbackSound },
                    set: { v in editDefaults { $0.sound = v }; if v != "none" { controller.sounds.play(v) } })) {
                    ForEach(soundOptions, id: \.self) { Text(($0 as NSString).lastPathComponent) }
                }
                Button("Choose Sound File\u{2026}") {
                    let p = NSOpenPanel()
                    p.allowedContentTypes = [.audio]
                    if p.runModal() == .OK, let u = p.url { editDefaults { $0.sound = u.path } }
                }
                Toggle("Stay until dismissed", isOn: Binding(
                    get: { d.persistent ?? true }, set: { v in editDefaults { $0.persistent = v } }))
                HStack {
                    Text("Auto-dismiss after (seconds, 0 = never)")
                    Spacer()
                    TextField("", value: Binding(get: { d.timeout ?? 0 }, set: { v in editDefaults { $0.timeout = max(0, v) } }),
                              format: .number).frame(width: 60)
                }
                Picker("Screen corner", selection: Binding(
                    get: { d.corner ?? .topRight }, set: { v in editDefaults { $0.corner = v } })) {
                    Text("Top right").tag(HeraldCorner.topRight)
                    Text("Top left").tag(HeraldCorner.topLeft)
                    Text("Bottom right").tag(HeraldCorner.bottomRight)
                    Text("Bottom left").tag(HeraldCorner.bottomLeft)
                }
            } header: { Text("Defaults") }
            Section {
                Button("Templates\u{2026}") { TemplateEditorWindow.show(controller: controller, app: app) }
            } header: { Text("Templates") } footer: {
                Text("Reusable banner layouts and defaults that notifications can reference with \"template\".")
            }
            Section {
                Toggle("Allow this app to run commands", isOn: Binding(
                    get: { record.commandsConfirmed },
                    set: { v in
                        if v { confirmCommands() } else { edit { $0.commandsConfirmed = false } }
                    }))
                if record.commandsConfirmed && record.registration.allowCommands != true {
                    Text("Confirmed, but the app has not requested command access.").font(.caption).foregroundStyle(.secondary)
                }
            } header: { Text("Commands") } footer: {
                Text("Command buttons run through /bin/zsh as you. Only enable for apps you trust.")
            }
            if let host = remoteCallbackHost {
                Section {
                    Toggle("Allow callbacks to \(host)", isOn: Binding(
                        get: { record.callbackHostApproved == host },
                        set: { v in
                            if v { confirmCallbackHost(host) } else { edit { $0.callbackHostApproved = nil } }
                        }))
                } header: { Text("Callbacks") } footer: {
                    Text("Callback buttons POST their action and payload to a URL. Local addresses always work; any other host needs this approval.")
                }
            }
        }
        .formStyle(.grouped)
    }

    /// A callback host that is not on this Mac: the registered one, or one the user approved earlier.
    private var remoteCallbackHost: String? {
        if let h = record.registeredCallbackHost, !CallbackDelivery.isLoopback(host: h) { return h }
        return record.callbackHostApproved
    }

    private func confirmCallbackHost(_ host: String) {
        let a = NSAlert()
        a.messageText = "Allow \(record.displayName) callbacks to \(host)?"
        a.informativeText = "When you press a callback button, Herald will send the button's action and payload to \(host), which is not on this Mac."
        a.alertStyle = .warning
        a.addButton(withTitle: "Allow")
        a.addButton(withTitle: "Cancel")
        if a.runModal() == .alertFirstButtonReturn { edit { $0.callbackHostApproved = host } }
    }

    private func confirmCommands() {
        let a = NSAlert()
        a.messageText = "Allow \(record.displayName) to run commands?"
        a.informativeText = "Buttons in its notifications will execute shell commands with your user permissions."
        a.alertStyle = .warning
        a.addButton(withTitle: "Allow")
        a.addButton(withTitle: "Cancel")
        if a.runModal() == .alertFirstButtonReturn { edit { $0.commandsConfirmed = true } }
    }
}
