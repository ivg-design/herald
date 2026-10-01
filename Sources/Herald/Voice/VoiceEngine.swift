import AVFoundation
import Foundation

enum VoiceEngineKind: String, CaseIterable, Identifiable, Codable {
    case kokoro, system, off
    var id: String { rawValue }
    var title: String {
        switch self {
        case .kokoro: return "Kokoro (local, natural)"
        case .system: return "System voice"
        case .off: return "Off"
        }
    }
}

struct VoiceRequest: Sendable {
    var text: String
    var voice: String?
    var speed: Double
    var lang: String
}

struct PreparedSpeech: Sendable {
    var utterance: SpeechUtterance
    /// The synthesized WAV, nil when the engine speaks directly.
    var audioPath: String?
    var duration: Double?
}

struct VoiceInfo: Identifiable, Hashable, Sendable {
    var id: String
    var name: String
}

/// Turns text into something the `SpeechQueue` can play. Everything is local.
protocol VoiceEngine: AnyObject, Sendable {
    var kind: VoiceEngineKind { get }
    func prepare(_ request: VoiceRequest, cache: AudioCache) async throws -> PreparedSpeech
    func voices() async -> [VoiceInfo]
    func shutdown() async
}

/// Voices Kokoro ships with, for the picker before the worker has reported the model's own list.
let kokoroDefaultVoices: [VoiceInfo] = ["af_heart", "af_bella", "af_nicole", "am_michael", "bf_emma", "bm_george"]
    .map { VoiceInfo(id: $0, name: $0) }

/// Kokoro through the persistent Python worker.
final class KokoroEngine: VoiceEngine, @unchecked Sendable {
    let kind = VoiceEngineKind.kokoro
    private let layout: KokoroLayout
    private let worker: TTSWorker

    init(layout: KokoroLayout, script: URL?) {
        self.layout = layout
        worker = TTSWorker {
            guard layout.isInstalled else { throw TTSWorkerError.notInstalled(layout.missing.joined(separator: ", ")) }
            guard let script else { throw TTSWorkerError.notInstalled("tts_worker.py is missing from the app bundle") }
            return PythonTTSProcess(python: layout.python, script: script, directory: layout.root)
        }
    }

    func prepare(_ request: VoiceRequest, cache: AudioCache) async throws -> PreparedSpeech {
        let out = cache.newSpeechURL()
        let duration = try await worker.synthesize(text: request.text, voice: request.voice ?? "af_heart",
                                                   speed: request.speed, lang: request.lang, out: out)
        return PreparedSpeech(utterance: .file(out), audioPath: out.path, duration: duration)
    }

    func voices() async -> [VoiceInfo] {
        guard let names = try? await worker.voices(), !names.isEmpty else { return kokoroDefaultVoices }
        return names.map { VoiceInfo(id: $0, name: $0) }
    }

    func shutdown() async { await worker.shutdown() }
}

/// AVSpeechSynthesizer fallback. It speaks straight to the output device, so there is no WAV to cache.
final class SystemVoiceEngine: VoiceEngine, @unchecked Sendable {
    let kind = VoiceEngineKind.system
    /// A system voice identifier chosen in Settings; Kokoro voice names (`af_heart`) are never valid here.
    private let voiceIdentifier: String?
    init(voiceIdentifier: String?) { self.voiceIdentifier = voiceIdentifier }

    func prepare(_ request: VoiceRequest, cache: AudioCache) async throws -> PreparedSpeech {
        let voice = AVSpeechSynthesisVoice.speechVoices().contains { $0.identifier == request.voice } ? request.voice : voiceIdentifier
        return PreparedSpeech(utterance: .system(text: request.text, voice: voice, speed: request.speed),
                              audioPath: nil, duration: nil)
    }

    func voices() async -> [VoiceInfo] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("en") }
            .map { VoiceInfo(id: $0.identifier, name: "\($0.name) (\($0.language))") }
            .sorted { $0.name < $1.name }
    }

    func shutdown() async {}
}

/// Speech is switched off: nothing is synthesized or played.
final class OffEngine: VoiceEngine, @unchecked Sendable {
    let kind = VoiceEngineKind.off
    func prepare(_ request: VoiceRequest, cache: AudioCache) async throws -> PreparedSpeech {
        throw TTSWorkerError.failed("speech is turned off")
    }
    func voices() async -> [VoiceInfo] { [] }
    func shutdown() async {}
}

/// The real `SpeechPlayer`: AVAudioPlayer for files, AVSpeechSynthesizer for system speech.
@MainActor
final class AVSpeechPlayer: NSObject, SpeechPlayer, AVAudioPlayerDelegate, AVSpeechSynthesizerDelegate {
    private var audio: AVAudioPlayer?
    private let synth = AVSpeechSynthesizer()
    private var continuation: CheckedContinuation<Void, Never>?
    private var currentUtterance: AVSpeechUtterance?

    override init() {
        super.init()
        synth.delegate = self
    }

    func play(_ utterance: SpeechUtterance) async {
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            continuation = c
            switch utterance {
            case .file(let url):
                guard let p = try? AVAudioPlayer(contentsOf: url) else { finish(); return }
                p.delegate = self
                audio = p
                if !p.play() { finish() }
            case .system(let text, let voice, let speed):
                let u = AVSpeechUtterance(string: text)
                if let voice { u.voice = AVSpeechSynthesisVoice(identifier: voice) }
                u.rate = Float(min(max(Double(AVSpeechUtteranceDefaultSpeechRate) * speed, Double(AVSpeechUtteranceMinimumSpeechRate)),
                                   Double(AVSpeechUtteranceMaximumSpeechRate)))
                currentUtterance = u
                synth.speak(u)
            }
        }
    }

    func stop() {
        audio?.stop()
        if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
        finish()
    }

    private func finish() {
        audio = nil
        currentUtterance = nil
        let c = continuation
        continuation = nil
        c?.resume()
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in if player === self.audio { self.finish() } }
    }
    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor in if player === self.audio { self.finish() } }
    }
    // Callbacks from an utterance that was already replaced (stop, then a new play) must not end the new one.
    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish u: AVSpeechUtterance) {
        Task { @MainActor in if u === self.currentUtterance { self.finish() } }
    }
    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didCancel u: AVSpeechUtterance) {
        Task { @MainActor in if u === self.currentUtterance { self.finish() } }
    }
}
