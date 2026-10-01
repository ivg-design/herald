import AppKit
import Combine
import Foundation

/// Decides what is spoken for a delivered notification, synthesizes it and queues it (DESIGN section 7.9).
/// Everything runs on this Mac: the worker is a local Python process and the files stay in Application Support.
@MainActor
final class VoiceCoordinator: ObservableObject {
    static let shared = VoiceCoordinator()

    /// Set by the app controller: shows the banner for an item whose voice-only delivery failed.
    var showBanner: ((HeraldHistoryItem) -> Void)?
    /// Set by the app controller: where history lives.
    var history: HistoryStore?

    let settings = VoiceSettings.shared
    @Published private(set) var availableVoices: [VoiceInfo] = kokoroDefaultVoices
    @Published private(set) var lastError: String?
    @Published private(set) var isSpeaking = false

    private lazy var queue = SpeechQueue(player: player, isMuted: { AppSettings.shared.muted })
    private let player = AVSpeechPlayer()
    private var engine: VoiceEngine?
    private var observers: [AnyCancellable] = []

    private init() {
        // Muting cuts the current speech and clears the queue, like the sound player.
        observers.append(AppSettings.shared.$muted.dropFirst().sink { [weak self] muted in
            guard muted else { return }
            MainActor.assumeIsolated { self?.queue.stopAll() }
        })
        NotificationCenter.default.addObserver(forName: VoiceSettings.engineChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.resetEngine() }
        }
    }

    // MARK: Locations

    var supportDirectory: URL { HeraldPaths.defaultSupportDirectory }
    var layout: KokoroLayout { KokoroLayout(supportDirectory: supportDirectory) }
    var audioCache: AudioCache { AudioCache(directory: supportDirectory.appendingPathComponent("history/audio", isDirectory: true)) }

    private var workerScript: URL? {
        if let url = Bundle.main.url(forResource: "tts_worker", withExtension: "py") { return url }
        if let dev = ProcessInfo.processInfo.environment["HERALD_TTS_WORKER"], !dev.isEmpty { return URL(fileURLWithPath: dev) }
        return nil
    }

    // MARK: Engine

    func currentEngine() -> VoiceEngine {
        if let engine, engine.kind == settings.engine { return engine }
        let e: VoiceEngine
        switch settings.engine {
        case .kokoro: e = KokoroEngine(layout: layout, script: workerScript)
        case .system: e = SystemVoiceEngine(voiceIdentifier: settings.systemVoice)
        case .off: e = OffEngine()
        }
        let old = engine
        engine = e
        if let old { Task { await old.shutdown() } }
        return e
    }

    /// Drops the engine (and its worker) so the next request builds a fresh one: the engine, the voice or the
    /// installation changed.
    func resetEngine() {
        let old = engine
        engine = nil
        if let old { Task { await old.shutdown() } }
        Task { await refreshVoices() }
    }

    func refreshVoices() async {
        let e = currentEngine()
        let list = await e.voices()
        availableVoices = list.isEmpty ? kokoroDefaultVoices : list
    }

    // MARK: Delivery

    private func key(_ app: String, _ id: String) -> String { app + "\u{1}" + id }

    struct Plan {
        var speakText: String?
        var voice: String?
        var speed: Double
        var lang: String
        var audio: String?
        var suppressBanner: Bool
    }

    /// What this notification asks for, after the app's Speak toggle, the engine and the mute switch.
    func plan(for n: HeraldNotification) -> Plan {
        let prefs = settings.prefs(for: n.app)
        let presentation = n.presentation ?? .banner
        let speakRequested = n.speak != nil || presentation != .banner
        var plan = Plan(speakText: nil, voice: nil, speed: 1, lang: settings.lang, audio: nil, suppressBanner: false)
        guard prefs.speak, speakRequested || n.audio != nil else { return plan }

        if speakRequested, n.audio == nil || n.speak != nil, settings.engine != .off {
            let speak = n.speak ?? HeraldSpeak()
            let text = speak.resolvedText(title: n.title, body: n.body)
            if !text.isEmpty {
                plan.speakText = text
                plan.voice = speak.voice ?? prefs.voice ?? (settings.engine == .kokoro ? settings.defaultVoice : nil)
                plan.speed = min(max(speak.speed ?? prefs.speed ?? settings.speed, 0.5), 2.0)
                plan.lang = speak.lang ?? settings.lang
            }
        }
        if let a = n.audio, !a.isEmpty { plan.audio = a }
        // Voice-only is honoured only when something will actually be heard; a muted Herald, an app with Speak
        // off or an engine that is off falls back to the banner so the notification is never lost.
        plan.suppressBanner = presentation == .voice && !AppSettings.shared.muted && (plan.speakText != nil || plan.audio != nil)
        return plan
    }

    /// Called by the controller right after a notification was stored. Returns true when the banner (and the
    /// chime) must be skipped because the notification is voice-only.
    @discardableResult
    func handle(notification n: HeraldNotification, historyItem item: HeraldHistoryItem,
                quiet: HeraldQuietStatus = HeraldQuietStatus()) -> Bool {
        let plan = plan(for: n)
        guard plan.speakText != nil || plan.audio != nil else { return false }
        if AppSettings.shared.muted { return false }   // global mute silences speech (banners still show)
        if quiet.active && quiet.speech {
            // Quiet hours (DESIGN section 7.9.1): nothing is synthesized or played; history says why. A voice-only
            // notification falls back to its banner (which the quiet window may itself hold back).
            record(item, HeraldSpeech(text: plan.speakText ?? item.notification.title, voice: plan.voice, suppressed: "quiet-hours"))
            QuietHoursCoordinator.shared.hold(title: n.title)
            return false
        }
        let k = key(item.app, item.id)
        let voiceOnly = plan.suppressBanner
        let group = JobGroup(total: (plan.speakText == nil ? 0 : 1) + (plan.audio == nil ? 0 : 1)) { [weak self] anySucceeded in
            guard let self, voiceOnly, !anySucceeded else { return }
            // Nothing could be prepared for a voice-only notification: bring it back as a banner.
            self.history?.update(app: item.app, id: item.id) { $0.dismissedAt = nil; $0.actionUsed = nil }
            if let current = self.history?.items(app: item.app).first(where: { $0.id == item.id }) { self.showBanner?(current) }
        }

        if let text = plan.speakText {
            record(item, HeraldSpeech(text: text, voice: plan.voice))
            let request = VoiceRequest(text: text, voice: plan.voice, speed: plan.speed, lang: plan.lang)
            let engine = currentEngine(), cache = audioCache
            queue.enqueue(.init(key: k) { [weak self] in
                do {
                    let prepared = try await engine.prepare(request, cache: cache)
                    await MainActor.run {
                        self?.record(item, HeraldSpeech(text: text, voice: plan.voice, audioPath: prepared.audioPath,
                                                        durationSeconds: prepared.duration))
                        self?.lastError = nil
                        group.finish(true)
                    }
                    return prepared.utterance
                } catch {
                    await MainActor.run { self?.lastError = error.localizedDescription; group.finish(false) }
                    NSLog("Herald: speech failed: %@", error.localizedDescription)
                    return nil
                }
            })
        }
        if let spec = plan.audio {
            let cache = audioCache
            queue.enqueue(.init(key: k) { [weak self] in
                guard let url = await cache.cache(spec) else {
                    NSLog("Herald: audio for %@ ignored: not a readable WAV/MP3/M4A of at most 20 MB", item.app)
                    await MainActor.run { group.finish(false) }
                    return nil
                }
                await MainActor.run {
                    if plan.speakText == nil { self?.record(item, HeraldSpeech(text: item.notification.title, audioPath: url.path)) }
                    group.finish(true)
                }
                return .file(url)
            })
        }
        if voiceOnly {
            // No banner: the history entry is the record, already read.
            history?.update(app: item.app, id: item.id) { $0.dismissedAt = Date(); $0.actionUsed = "voice" }
        }
        return voiceOnly
    }

    /// Plays a history entry's speech again (the file if it is still cached, else re-synthesized from the text).
    func replay(app: String, id: String, speech: HeraldSpeech) {
        let k = key(app, id)
        queue.cancel(key: k)
        if let path = speech.audioPath, FileManager.default.fileExists(atPath: path) {
            queue.enqueue(.init(key: k, ignoresMute: true) { .file(URL(fileURLWithPath: path)) })
            return
        }
        guard settings.engine != .off else { return }
        let request = VoiceRequest(text: HeraldSpeak.clean(speech.text), voice: speech.voice, speed: settings.speed, lang: settings.lang)
        let engine = currentEngine(), cache = audioCache
        queue.enqueue(.init(key: k, ignoresMute: true) { [weak self] in
            do { return try await engine.prepare(request, cache: cache).utterance }
            catch {
                await MainActor.run { self?.lastError = error.localizedDescription }
                return nil
            }
        })
    }

    /// Settings > Voice "Test": speaks `text` with the current settings, even while muted.
    func test(text: String) {
        guard settings.engine != .off else { lastError = "Speech is turned off."; return }
        let request = VoiceRequest(text: HeraldSpeak.clean(text),
                                   voice: settings.engine == .kokoro ? settings.defaultVoice : nil,
                                   speed: settings.speed, lang: settings.lang)
        let engine = currentEngine(), cache = audioCache
        queue.stopAll()
        queue.enqueue(.init(key: "test", ignoresMute: true) { [weak self] in
            do {
                let p = try await engine.prepare(request, cache: cache)
                await MainActor.run { self?.lastError = nil }
                return p.utterance
            } catch {
                await MainActor.run { self?.lastError = error.localizedDescription }
                return nil
            }
        })
    }

    /// The end-of-quiet-hours summary ("3 messages while you were away: ...").
    func speakSummary(_ text: String) {
        guard settings.engine != .off, !AppSettings.shared.muted else { return }
        let request = VoiceRequest(text: HeraldSpeak.clean(text), voice: settings.engine == .kokoro ? settings.defaultVoice : nil,
                                   speed: settings.speed, lang: settings.lang)
        let engine = currentEngine(), cache = audioCache
        queue.enqueue(.init(key: "summary") { [weak self] in
            do { return try await engine.prepare(request, cache: cache).utterance }
            catch { await MainActor.run { self?.lastError = error.localizedDescription }; return nil }
        })
    }

    /// Dismiss of one notification interrupts its speech.
    func cancel(app: String, id: String) { queue.cancel(key: key(app, id)) }
    /// Dismiss All.
    func stopAll() { queue.stopAll() }

    func start() {
        QuietHoursCoordinator.shared.start()
        audioCache.prune()
        Task { await refreshVoices() }
    }

    private func record(_ item: HeraldHistoryItem, _ speech: HeraldSpeech) {
        history?.update(app: item.app, id: item.id) { $0.speech = speech }
        NotificationCenter.default.post(name: .heraldChanged, object: nil)
    }

    /// Counts the jobs of one notification and reports once all are done.
    @MainActor
    final class JobGroup {
        private var remaining: Int
        private var anySucceeded = false
        private let done: (Bool) -> Void
        init(total: Int, done: @escaping (Bool) -> Void) { remaining = total; self.done = done }
        func finish(_ ok: Bool) {
            anySucceeded = anySucceeded || ok
            remaining -= 1
            if remaining == 0 { done(anySucceeded) }
        }
    }
}
