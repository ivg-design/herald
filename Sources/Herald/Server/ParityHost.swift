import Foundation
import AppKit

/// The running app's side of the parity routes (`ParityService`): the settings that live in UserDefaults, the login
/// item, the displays, the Kokoro and MCP installers, and showing a banner.
final class AppParityHost: ParityHost, @unchecked Sendable {
    private unowned let controller: AppController
    init(controller: AppController) { self.controller = controller }

    // MARK: General settings

    func settingValue(_ key: String) async -> JSONValue? {
        await MainActor.run {
            let s = controller.settings, v = VoiceSettings.shared
            switch key {
            case "port": return .number(Double(s.effectivePort))
            case "launchAtLogin": return .bool(s.launchAtLogin)
            case "muteAllSounds": return .bool(s.muted)
            case "stacking": return .string(s.stacking.rawValue)
            case "historyCapPerApp": return .number(Double(controller.history.capPerApp))
            case "tooltipLevel": return .string(s.tooltipLevel.rawValue)
            case "voiceEngine": return .string(v.engine.rawValue)
            case "voiceDefault": return .string(v.defaultVoice)
            case "voiceSpeed": return .number(v.speed)
            case "voiceLang": return .string(v.lang)
            case "voiceSystem": return v.systemVoice.map { .string($0) } ?? .null
            default: return nil
            }
        }
    }

    func applySetting(_ key: String, _ value: JSONValue) async throws {
        try await MainActor.run {
            let s = controller.settings, v = VoiceSettings.shared
            switch key {
            case "port":
                guard let p = value.parityNumber.map(Int.init) else { return }
                s.portOverride = (p == HeraldPaths.defaultPort) ? 0 : p
                // The reply to this very request is still being written: restart the server just after it.
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 600_000_000)
                    controller.startServer()
                }
            case "launchAtLogin": s.launchAtLogin = value.parityBool ?? false
            case "muteAllSounds": controller.muted = value.parityBool ?? false
            case "stacking": if let l = value.parityString.flatMap(StackingLevel.init(rawValue:)) { s.stacking = l }
            case "tooltipLevel": if let l = value.parityString.flatMap(TooltipLevel.init(rawValue:)) { s.tooltipLevel = l }
            case "historyCapPerApp":
                if let n = value.parityNumber.map(Int.init) {
                    HistoryCapSetting.save(n)
                    controller.history.capPerApp = n
                }
            case "voiceEngine": if let e = value.parityString.flatMap(VoiceEngineKind.init(rawValue:)) { v.engine = e }
            case "voiceDefault": if let n = value.parityString { v.defaultVoice = n }
            case "voiceSpeed": if let n = value.parityNumber { v.speed = n }
            case "voiceLang": if let n = value.parityString { v.lang = n }
            case "voiceSystem": v.systemVoice = value.parityString
            default: throw BackendError(400, "unknown setting: \(key)")
            }
        }
    }

    func options() async -> [String: JSONValue] {
        await MainActor.run {
            [
                "sounds": .array((["none"] + SoundPlayer.systemSoundNames).map { .string($0) }),
                "displays": .array(BannerDisplays.choices().map { .object(["id": .string($0.id), "name": .string($0.name)]) }),
                "corners": .array(SettingsSchema.corners.map { .string($0) }),
                "stackingLevels": .array(StackingLevel.allCases.map { .string($0.rawValue) }),
                "voiceEngines": .array(SettingsSchema.engines.map { .string($0) }),
                "voices": .array(VoiceCoordinator.shared.availableVoices.map { .object(["id": .string($0.id), "name": .string($0.name)]) }),
                "historyCapChoices": .array(HistoryCapSetting.choices.map { .number(Double($0)) }),
            ]
        }
    }

    // MARK: Per-app voice

    func appVoice(_ app: String) async -> [String: JSONValue] {
        await MainActor.run {
            let p = VoiceSettings.shared.prefs(for: app)
            return ["speak": .bool(p.speak), "voice": p.voice.map { .string($0) } ?? .null,
                    "speed": p.speed.map { .number($0) } ?? .null, "urgentBreaksQuiet": .bool(p.urgentBreaksQuiet)]
        }
    }

    func applyAppVoice(app: String, key: String, value: JSONValue) async throws {
        await MainActor.run {
            VoiceSettings.shared.update(app: app) { p in
                switch key {
                case "speak": p.speak = value.parityBool ?? true
                case "voice": p.voice = value.parityString
                case "urgentBreaksQuiet": p.urgentBreaksQuiet = value.parityBool ?? false
                default: break
                }
            }
        }
    }

    // MARK: Voice (Kokoro)

    func voiceState() async throws -> JSONValue {
        await MainActor.run {
            let c = VoiceCoordinator.shared, installer = c.installer, layout = installer.layout
            var phase: [String: JSONValue] = [:]
            switch installer.phase {
            case .idle: phase = ["state": .string("idle")]
            case .downloading(let file, let fraction): phase = ["state": .string("downloading"), "file": .string(file), "fraction": .number(fraction)]
            case .settingUp(let what): phase = ["state": .string("settingUp"), "step": .string(what)]
            case .done: phase = ["state": .string("done")]
            case .failed(let why): phase = ["state": .string("failed"), "error": .string(why)]
            }
            return .object([
                "engine": .string(VoiceSettings.shared.engine.rawValue),
                "kokoro": .object([
                    "installed": .bool(layout.isInstalled), "missing": .array(layout.missing.map { .string($0) }),
                    "folder": .string(layout.root.path), "busy": .bool(installer.isBusy), "phase": .object(phase),
                    "existingInstallationAvailable": .bool(installer.existing != nil),
                    "log": .array(installer.log.suffix(8).map { .string($0) }),
                ]),
                "voices": .array(c.availableVoices.map { .object(["id": .string($0.id), "name": .string($0.name)]) }),
                "lastError": c.lastError.map { .string($0) } ?? .null,
            ])
        }
    }

    func voiceInstall(action: String) async throws -> JSONValue {
        try await MainActor.run {
            let installer = VoiceCoordinator.shared.installer
            switch action {
            case "install":
                guard !installer.layout.isInstalled else { throw BackendError(409, "Kokoro is already installed") }
                installer.install()
            case "cancel": installer.cancel()
            case "useExisting":
                guard let existing = installer.existing else { throw BackendError(404, "there is no complete installation at ~/.claude/tts") }
                installer.useExisting(existing)
            default: throw BackendError(400, "unknown action")
            }
            return .object(["ok": .bool(true), "action": .string(action), "next": .string("Poll GET /v1/voice for progress.")])
        }
    }

    // MARK: MCP

    private static let clientNames: [(key: String, client: MCPClient?)] = [
        ("claudeCode", .claudeCode), ("codex", .codex), ("claudeDesktop", .claudeDesktop), ("generic", .generic),
    ]

    func mcpStatus() async throws -> JSONValue {
        await Task.detached {
            let installer = MCPInstaller()
            var clients: [JSONValue] = []
            for (key, client) in Self.clientNames {
                guard let client else { continue }
                let st = installer.status(client)
                clients.append(.object(["client": .string(key), "name": .string(client.rawValue), "status": .string(st.label)]))
            }
            return JSONValue.object([
                "server": .string(installer.serverPath), "clients": .array(clients),
                "genericConfig": .string(installer.genericJSON), "genericCommandLine": .string(installer.genericCommandLine),
                "cli": .object(["destination": .string("/usr/local/bin/herald"),
                                "installed": .bool(FileManager.default.isExecutableFile(atPath: "/usr/local/bin/herald"))]),
            ])
        }.value
    }

    func mcpInstall(client: String, reinstall: Bool, name: String?, icon: String?, opens: String?, detectedHost: String?) async throws -> JSONValue {
        if client == "cli" {
            let r = await Task.detached { MCPInstaller().installCLI() }.value
            guard r.ok else { throw BackendError(400, r.message) }
            return .object(["ok": .bool(true), "message": .string(r.message), "touched": .string(r.touched)])
        }
        // The client's configuration gets `--agent <slug>`, and the agent is registered as an issuer (issue #62).
        let env = await MainActor.run {
            AgentInstall.Environment(registry: controller.registry, manifests: controller.manifests, templates: controller.templates,
                                     support: controller.supportDirectory)
        }
        let outcome = await AgentInstall.run(client: client, genericName: name, iconFile: icon.map { URL(fileURLWithPath: $0) },
                                             reinstall: reinstall, opens: opens, detectedHost: detectedHost, env: env)
        guard outcome.install.ok else { throw BackendError(outcome.install.alreadyExists ? 409 : 400, outcome.install.message) }
        await MainActor.run { controller.changed() }
        var json = outcome.json
        if client == "generic", let slug = outcome.identity?.slug, case .object(var o) = json {
            o["config"] = .string(env.installer.genericJSON(agent: slug))
            json = .object(o)
        }
        return json
    }

    // MARK: History and banners

    func reshow(_ n: HeraldNotification) async throws -> String { try await controller.notify(n) }

    func closeBanner(app: String, id: String) async {
        await MainActor.run { controller.banners.close(app: app, id: id) }
    }

    func changed() async { await MainActor.run { controller.changed() } }
}
