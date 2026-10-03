import SwiftUI
import AppKit

struct SettingsView: View {
    let controller: AppController
    var body: some View {
        TabView {
            GeneralSettingsView(controller: controller).tabItem { Label("General", systemImage: "gearshape") }
            AppsSettingsView(controller: controller).tabItem { Label("Apps", systemImage: "square.grid.2x2") }
            ActionsSettingsView(controller: controller).tabItem { Label("Actions", systemImage: "bolt") }
            VoiceSettingsView(controller: controller).tabItem { Label("Voice", systemImage: "waveform") }
            CloudSettingsView(controller: controller).tabItem { Label("Cloud", systemImage: "icloud") }
            MCPSettingsView(controller: controller).tabItem { Label("MCP", systemImage: "puzzlepiece.extension") }
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
                    TextField("Port", text: $portText).frame(width: 80) .heraldHelp(.apiPort)
                    Button("Apply") { applyPort() } .heraldHelp(.apiApply)
                    Button("Reset to \(HeraldPaths.defaultPort)") { portText = String(HeraldPaths.defaultPort); applyPort() } .heraldHelp(.apiReset)
                }
                Text({ _ = ticker.tick; return controller.serverStatus }())
                    .font(.caption).foregroundStyle(controller.serverRunning ? Color.secondary : Color.red)
                Button("Reveal Token File in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([HeraldPaths.tokenURL()])
                } .heraldHelp(.revealToken)
            } header: { Text("Local API") }
            Section {
                Toggle("Launch at login", isOn: Binding(get: { settings.launchAtLogin }, set: { settings.launchAtLogin = $0 })) .heraldHelp(.launchAtLogin)
                Toggle("Mute all sounds", isOn: $settings.muted) .heraldHelp(.muteSounds)
                Picker("Tooltips", selection: $settings.tooltipLevel) {
                    ForEach(TooltipLevel.allCases) { Text($0.title).tag($0) }
                }
                .heraldHelp(.tooltipLevel)
            } header: { Text("General") }
            // Editor-specific preferences (Designer, Quick send) live in sections of this window, not in a window of their own.
            HistoryCapSettingsView(history: controller.history)
        }
        .formStyle(.grouped)
        .overlay(alignment: .bottomTrailing) {
            Text(HeraldVersionLabel.current)
                .font(.caption2).foregroundStyle(.secondary)
                .padding(.trailing, 6).padding(.bottom, 2)
                .onTapGesture {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(HeraldVersionLabel.current, forType: .string)
                }
                .heraldHelp(.appVersion)
        }
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
                    Image(nsImage: AppIcons.icon(in: controller.registry, app: r.registration.app)).resizable().frame(width: 20, height: 20)
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

    /// A file picker for the app's icon. The picture is copied into Herald's support folder, so the file can move or go.
    private func chooseIcon() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.message = "Choose an icon for \(record.displayName)"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try CustomIcon.set(app: app, from: url, supportDirectory: controller.supportDirectory, registry: controller.registry)
            AppIcons.invalidate(); controller.changed()
        } catch {
            let a = NSAlert()
            a.messageText = "That file is not an image Herald can use."
            a.runModal()
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
                HStack(spacing: 12) {
                    Image(nsImage: AppIcons.icon(in: controller.registry, app: app)).resizable().frame(width: 40, height: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(record.displayName).font(.headline)
                        Text(record.customIcon != nil ? "Your icon" : "Automatic icon").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Change icon\u{2026}") { chooseIcon() }
                    if record.customIcon != nil {
                        Button("Remove") {
                            CustomIcon.remove(app: app, supportDirectory: controller.supportDirectory, registry: controller.registry)
                            AppIcons.invalidate(); controller.changed()
                        }
                    }
                }
            }
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
                } .heraldHelp(.defaultSound)
                Button("Choose Sound File\u{2026}") {
                    let p = NSOpenPanel()
                    p.allowedContentTypes = [.audio]
                    if p.runModal() == .OK, let u = p.url { editDefaults { $0.sound = u.path } }
                } .heraldHelp(.chooseSound)
                Toggle("Stay until dismissed", isOn: Binding(
                    get: { d.persistent ?? true }, set: { v in editDefaults { $0.persistent = v } })) .heraldHelp(.stayUntilDismissed)
                HStack {
                    Text("Auto-dismiss after (seconds, 0 = never)")
                    Spacer()
                    TextField("", value: Binding(get: { d.timeout ?? 0 }, set: { v in editDefaults { $0.timeout = max(0, v) } }),
                              format: .number).frame(width: 60) .heraldHelp(.autoDismiss)
                }
            } header: { Text("Defaults") }
            AppDisplaySettingsView(controller: controller, app: app)
            Section {
                Button("Templates\u{2026}") { TemplateEditorWindow.show(controller: controller, app: app) } .heraldHelp(.openTemplates)
            } header: { Text("Templates") } footer: {
                Text("Reusable banner layouts and defaults that notifications can reference with \"template\".")
            }
            Section {
                Toggle("Allow this app to run commands", isOn: Binding(
                    get: { record.commandsConfirmed },
                    set: { v in
                        if v { confirmCommands() } else { edit { $0.commandsConfirmed = false } }
                    })) .heraldHelp(.allowCommands)
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
                        })) .heraldHelp(.allowCallbacks)
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

/// Scripts and template commands: the two places where a banner button runs code on this Mac.
struct ActionsSettingsView: View {
    let controller: AppController
    @StateObject private var ticker = ChangeTicker()
    @State private var scripts: [ActionRunner.ScriptEntry] = []

    private struct CommandRow: Identifiable {
        enum Status { case confirmed, changed, notConfirmed, templateRemoved }
        var id: String
        var app: String
        var appName: String
        var template: String
        var commands: [String]
        var status: Status
        var hasApproval: Bool
    }

    /// Every template that carries commands of its own, with whether the user confirmed them, plus approvals
    /// whose template has gone (so they can still be revoked).
    private var rows: [CommandRow] {
        _ = ticker.tick
        let approvals = controller.commandApprovals.all()
        var out: [CommandRow] = []
        var seen = Set<String>()
        for t in controller.templates.list() {
            let commands = controller.actionRunner.templateApprovalKeys(of: t)
            guard !commands.isEmpty else { continue }
            seen.insert(t.id)
            let approval = approvals.first { $0.id == t.id }
            let status: CommandRow.Status = approval == nil ? .notConfirmed
                : (commands.allSatisfy { approval!.commands.contains($0) } ? .confirmed : .changed)
            out.append(CommandRow(id: t.id, app: t.app, appName: controller.registry.displayName(for: t.app),
                                  template: t.name, commands: commands, status: status, hasApproval: approval != nil))
        }
        for a in approvals where !seen.contains(a.id) {
            out.append(CommandRow(id: a.id, app: a.app, appName: controller.registry.displayName(for: a.app),
                                  template: a.template, commands: a.commands, status: .templateRemoved, hasApproval: true))
        }
        return out.sorted { ($0.appName, $0.template) < ($1.appName, $1.template) }
    }

    var body: some View {
        Form {
            Section {
                if scripts.isEmpty {
                    Text("No scripts yet. Put a file in this folder, then add an action of kind \"script\" to a template.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(scripts) { sc in
                        HStack {
                            Text(sc.name).font(.system(.body, design: .monospaced)).lineLimit(1).truncationMode(.middle)
                            Spacer()
                            Text(Self.runsWith(sc)).font(.caption)
                                .foregroundStyle(sc.runnable ? Color.secondary : Color.orange)
                        }
                    }
                }
                HStack {
                    Button("Reveal in Finder") {
                        controller.actionRunner.ensureScriptsDirectory()
                        NSWorkspace.shared.open(controller.actionRunner.scriptsDirectory)
                    } .heraldHelp(.revealScripts)
                    Button("Refresh") { scripts = controller.actionRunner.listScripts() } .heraldHelp(.refreshScripts)
                    Spacer()
                    Button("Show Log") { revealLog() } .heraldHelp(.showActionLog)
                }
            } header: { Text("Scripts") } footer: {
                Text("A script action runs the file with the notification as JSON on standard input and HERALD_APP, HERALD_ACTION, HERALD_FIELD_<NAME> and HERALD_EXTRA_<KEY> in the environment. It has 30 seconds. Output goes to ~/Library/Logs/Herald/actions.log.")
            }
            Section {
                if rows.isEmpty {
                    Text("No template carries a command, script or Shortcut of its own.").foregroundStyle(.secondary)
                }
                ForEach(rows) { row in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("\(row.appName) / \(row.template)").font(.headline)
                            Spacer()
                            statusLabel(row.status)
                            if row.hasApproval {
                                Button("Revoke") {
                                    controller.commandApprovals.revoke(app: row.app, template: row.template)
                                    controller.changed()
                                } .heraldHelp(.revokeApproval)
                            }
                        }
                        ForEach(row.commands, id: \.self) { c in
                            Text(c).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                                .lineLimit(2).truncationMode(.tail).textSelection(.enabled)
                        }
                    }
                    .padding(.vertical, 2)
                }
            } header: { Text("Template commands, scripts and Shortcuts") } footer: {
                Text("A command, script or Shortcut a template carries itself asks for one confirmation per template the first time it runs. Changing the command, the script file or the Shortcut's name or input asks again. Commands an app sends in its own buttons follow the per-app switch under Apps.")
            }
        }
        .formStyle(.grouped)
        .onAppear { scripts = controller.actionRunner.listScripts() }
    }

    private static func runsWith(_ s: ActionRunner.ScriptEntry) -> String {
        if s.isExecutable { return "executable" }
        if let i = s.interpreter { return "runs with \((i as NSString).lastPathComponent)" }
        return "not runnable (chmod +x)"
    }

    @ViewBuilder private func statusLabel(_ status: CommandRow.Status) -> some View {
        switch status {
        case .confirmed: Text("Confirmed").font(.caption).foregroundStyle(.green)
        case .changed: Text("Changed since confirmed").font(.caption).foregroundStyle(.orange)
        case .notConfirmed: Text("Not confirmed yet").font(.caption).foregroundStyle(.secondary)
        case .templateRemoved: Text("Template removed").font(.caption).foregroundStyle(.secondary)
        }
    }

    private func revealLog() {
        let url = controller.actionRunner.log.url
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            NSWorkspace.shared.open(url.deletingLastPathComponent())
        }
    }
}
