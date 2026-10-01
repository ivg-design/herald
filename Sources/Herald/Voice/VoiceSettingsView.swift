import SwiftUI
import AppKit

/// Settings > Voice (DESIGN section 7.9): engine, the optional Kokoro download, voice, speed, per-app Speak
/// toggles and a test button. Everything runs on this Mac.
struct VoiceSettingsView: View {
    let controller: AppController
    @ObservedObject private var settings = VoiceSettings.shared
    @ObservedObject private var voice = VoiceCoordinator.shared
    @StateObject private var installer = KokoroInstaller(layout: VoiceCoordinator.shared.layout)
    @StateObject private var ticker = ChangeTicker()
    @State private var testText = "Herald voice test one two three"

    private var apps: [AppRecord] { _ = ticker.tick; return controller.registry.all() }

    var body: some View {
        Form {
            Section {
                Picker("Engine", selection: $settings.engine) {
                    ForEach(VoiceEngineKind.allCases) { Text($0.title).tag($0) }
                }
                if settings.engine == .kokoro { kokoroSection }
                if settings.engine != .off { voiceSection }
            } header: { Text("Speech") }
            footer: {
                Text("Spoken notifications are synthesized locally; no text or audio leaves this Mac.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            if settings.engine != .off {
                Section {
                    HStack {
                        TextField("Test text", text: $testText)
                        Button("Speak") { voice.test(text: testText) }
                    }
                    if let e = voice.lastError { Text(e).font(.caption).foregroundStyle(.red) }
                } header: { Text("Test") }
            }

            QuietHoursSettingsView()

            Section {
                if apps.isEmpty {
                    Text("Apps appear here after their first notification.").foregroundStyle(.secondary)
                }
                ForEach(apps, id: \.registration.app) { rec in
                    HStack {
                        Toggle(rec.displayName, isOn: Binding(
                            get: { settings.prefs(for: rec.registration.app).speak },
                            set: { v in settings.update(app: rec.registration.app) { $0.speak = v } }))
                        Spacer()
                        Toggle("Urgent can break quiet hours", isOn: Binding(
                            get: { settings.prefs(for: rec.registration.app).urgentBreaksQuiet },
                            set: { v in settings.update(app: rec.registration.app) { $0.urgentBreaksQuiet = v } }))
                            .toggleStyle(.checkbox).font(.caption).fixedSize()
                        Picker("", selection: Binding(
                            get: { settings.prefs(for: rec.registration.app).voice ?? "" },
                            set: { v in settings.update(app: rec.registration.app) { $0.voice = v.isEmpty ? nil : v } })) {
                            Text("Default voice").tag("")
                            ForEach(voice.availableVoices) { Text($0.name).tag($0.id) }
                        }
                        .labelsHidden().frame(width: 190)
                    }
                }
            } header: { Text("Speak per app") }
        }
        .formStyle(.grouped)
        .task { await voice.refreshVoices() }
        .onChange(of: installer.revision) { _ in Task { await voice.refreshVoices() } }
    }

    // MARK: Kokoro

    @ViewBuilder private var kokoroSection: some View {
        let layout = installer.layout
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: layout.isInstalled ? "checkmark.circle.fill" : "exclamationmark.circle")
                    .foregroundStyle(layout.isInstalled ? Color.green : Color.orange)
                Text(layout.isInstalled ? "Kokoro is installed" : "Kokoro is not installed (missing: \(layout.missing.joined(separator: ", ")))")
                Spacer()
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([layout.root]) }
                    .disabled(!FileManager.default.fileExists(atPath: layout.root.path))
            }
            if !layout.isInstalled {
                if let existing = installer.existing {
                    Button("Use existing installation at ~/.claude/tts") { installer.useExisting(existing) }
                        .disabled(installer.isBusy)
                    Text("Links the models and Python environment already there; nothing is copied or changed.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                HStack {
                    Button("Download Kokoro (about 340 MB)") { installer.install() }.disabled(installer.isBusy)
                    if installer.isBusy { Button("Cancel") { installer.cancel() } }
                }
                Text("Downloads kokoro-v1.0.onnx and voices-v1.0.bin from the kokoro-onnx GitHub release into Herald's folder and builds a Python environment (uv, or python3 and pip).")
                    .font(.caption).foregroundStyle(.secondary)
            }
            progressView
            ForEach(installer.checksums.sorted(by: { $0.key < $1.key }), id: \.key) { name, sum in
                Text("\(name)\nSHA-256 \(sum)").font(.system(size: 10, design: .monospaced)).textSelection(.enabled)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private var progressView: some View {
        switch installer.phase {
        case .downloading(let file, let fraction):
            ProgressView(value: fraction) { Text("Downloading \(file)  \(Int(fraction * 100))%").font(.caption) }
        case .settingUp(let what):
            HStack { ProgressView().controlSize(.small); Text(what).font(.caption) }
        case .failed(let why):
            Text(why).font(.caption).foregroundStyle(.red).textSelection(.enabled)
        default:
            EmptyView()
        }
    }

    // MARK: Voice

    @ViewBuilder private var voiceSection: some View {
        if settings.engine == .kokoro {
            Picker("Voice", selection: $settings.defaultVoice) {
                ForEach(voice.availableVoices) { Text($0.name).tag($0.id) }
            }
        } else {
            Picker("Voice", selection: Binding(get: { settings.systemVoice ?? "" }, set: { settings.systemVoice = $0.isEmpty ? nil : $0; voice.resetEngine() })) {
                Text("System default").tag("")
                ForEach(voice.availableVoices) { Text($0.name).tag($0.id) }
            }
        }
        HStack {
            Text("Speed")
            Slider(value: $settings.speed, in: 0.5...2.0, step: 0.05)
            Text(String(format: "%.2fx", settings.speed)).monospacedDigit().frame(width: 52, alignment: .trailing)
        }
    }
}
