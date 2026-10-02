import Foundation
import Combine

/// Per-app voice preferences (Settings > Voice).
struct AppVoicePrefs: Codable, Equatable {
    /// The per-app "Speak" toggle: off silences every `speak` / `audio` from this app.
    var speak = true
    var voice: String?
    var speed: Double?
    /// "Urgent can break quiet hours": a `priority: "urgent"` notification from this app is spoken during quiet
    /// hours. Off by default.
    var urgentBreaksQuiet = false

    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        speak = try c.decodeIfPresent(Bool.self, forKey: .speak) ?? true
        voice = try c.decodeIfPresent(String.self, forKey: .voice)
        speed = try c.decodeIfPresent(Double.self, forKey: .speed)
        urgentBreaksQuiet = try c.decodeIfPresent(Bool.self, forKey: .urgentBreaksQuiet) ?? false
    }
}

/// Voice preferences. They live in UserDefaults, or in a private suite when HERALD_SUPPORT_DIR points the app at
/// a development data folder, so a test instance never writes into the installed Herald's preferences.
@MainActor
final class VoiceSettings: ObservableObject {
    static let shared = VoiceSettings()
    private let d: UserDefaults

    @Published var engine: VoiceEngineKind { didSet { d.set(engine.rawValue, forKey: "voiceEngine"); changed() } }
    @Published var defaultVoice: String { didSet { d.set(defaultVoice, forKey: "voiceDefault") } }
    @Published var speed: Double { didSet { d.set(speed, forKey: "voiceSpeed") } }
    @Published var lang: String { didSet { d.set(lang, forKey: "voiceLang") } }
    /// The AVSpeechSynthesisVoice identifier used by the System engine.
    @Published var systemVoice: String? { didSet { d.set(systemVoice, forKey: "voiceSystem") } }
    @Published var perApp: [String: AppVoicePrefs] { didSet { persistPerApp() } }

    /// Posted when the engine changes, so the coordinator can restart its worker.
    static let engineChanged = Notification.Name.heraldVoiceEngineChanged

    private init() {
        if ProcessInfo.processInfo.environment["HERALD_SUPPORT_DIR"]?.isEmpty == false,
           let suite = UserDefaults(suiteName: "com.ivg.herald.voice-dev") {
            d = suite
        } else {
            d = .standard
        }
        engine = d.string(forKey: "voiceEngine").flatMap(VoiceEngineKind.init(rawValue:)) ?? .system
        defaultVoice = d.string(forKey: "voiceDefault") ?? "af_heart"
        let s = d.double(forKey: "voiceSpeed")
        speed = s == 0 ? 1.0 : min(max(s, 0.5), 2.0)
        lang = d.string(forKey: "voiceLang") ?? "en-us"
        systemVoice = d.string(forKey: "voiceSystem")
        if let data = d.data(forKey: "voicePerApp"), let m = try? JSONDecoder().decode([String: AppVoicePrefs].self, from: data) {
            perApp = m
        } else {
            perApp = [:]
        }
    }

    func prefs(for app: String) -> AppVoicePrefs { perApp[app] ?? AppVoicePrefs() }

    func update(app: String, _ mutate: (inout AppVoicePrefs) -> Void) {
        var p = prefs(for: app)
        mutate(&p)
        perApp[app] = p
    }

    private func persistPerApp() {
        if let data = try? JSONEncoder().encode(perApp) { d.set(data, forKey: "voicePerApp") }
    }

    private func changed() { NotificationCenter.default.post(name: Self.engineChanged, object: nil) }
}
