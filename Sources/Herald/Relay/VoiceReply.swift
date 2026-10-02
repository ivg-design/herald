import Foundation

/// How a voice reply is recorded, transcribed and sent. The pieces that touch the microphone and Speech are protocols so the
/// state machine is tested without either (and without a window).
@MainActor
public protocol AudioRecording: AnyObject {
    /// Starts writing AAC (m4a, mono, about 32 kbps) to `url`. Throws when the microphone cannot be opened.
    func start(to url: URL) throws
    /// Stops and returns the length in seconds.
    func stop() -> Double
    func cancel()
}

public protocol Transcribing: Sendable {
    /// On-device transcript of the file, nil when none can be made (no model, no permission, nothing said).
    func transcribe(_ url: URL) async -> String?
}

public enum VoiceReplyLimits {
    public static let maxSeconds = 60.0
    public static let maxUploadBytes = RelayAPI.maxAudioBytes
}

public struct BannerRecordPrompt: Equatable, Identifiable, Sendable {
    public enum Phase: Equatable, Sendable {
        case requestingPermission
        case recording
        case recorded
        case sending
        case failed(String)
    }
    public let id: UUID
    public var phase: Phase
    public var elapsed: Double
    public var maxSeconds: Double

    public init(id: UUID = UUID(), phase: Phase = .requestingPermission, elapsed: Double = 0, maxSeconds: Double = VoiceReplyLimits.maxSeconds) {
        self.id = id; self.phase = phase; self.elapsed = elapsed; self.maxSeconds = maxSeconds
    }

    public var elapsedText: String {
        let s = Int(elapsed.rounded(.down))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

/// One voice reply, from the Record press to the upload. Never starts by itself: `start()` is only called by the button.
@MainActor
public final class VoiceReplySession {
    public private(set) var prompt: BannerRecordPrompt { didSet { if prompt != oldValue { onChange?(prompt) } } }
    public var onChange: ((BannerRecordPrompt) -> Void)?
    public private(set) var fileURL: URL
    public private(set) var recordedSeconds = 0.0

    private let recorder: AudioRecording
    private let transcriber: Transcribing
    private let permission: () async -> Bool
    private let transcribeTimeout: TimeInterval

    public init(recorder: AudioRecording, transcriber: Transcribing, permission: @escaping () async -> Bool, file: URL,
                maxSeconds: Double = VoiceReplyLimits.maxSeconds, transcribeTimeout: TimeInterval = 20) {
        self.recorder = recorder; self.transcriber = transcriber; self.permission = permission
        self.fileURL = file; self.transcribeTimeout = transcribeTimeout
        prompt = BannerRecordPrompt(maxSeconds: maxSeconds)
    }

    public var phase: BannerRecordPrompt.Phase { prompt.phase }

    /// Asks for the microphone on first use, then records.
    public func start() async {
        guard prompt.phase == .requestingPermission || { if case .failed = prompt.phase { return true }; return false }() else { return }
        prompt.phase = .requestingPermission
        guard await permission() else {
            prompt.phase = .failed("Microphone access is off. Allow Herald in System Settings > Privacy & Security > Microphone.")
            return
        }
        do {
            try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? FileManager.default.removeItem(at: fileURL)
            try recorder.start(to: fileURL)
            prompt.elapsed = 0
            prompt.phase = .recording
        } catch {
            prompt.phase = .failed("Could not start recording: \(error.localizedDescription)")
        }
    }

    /// Called about ten times a second while recording; stops at the limit.
    public func tick(_ dt: Double) {
        guard prompt.phase == .recording else { return }
        prompt.elapsed = min(prompt.elapsed + dt, prompt.maxSeconds)
        if prompt.elapsed >= prompt.maxSeconds { stop() }
    }

    public func stop() {
        guard prompt.phase == .recording else { return }
        recordedSeconds = recorder.stop()
        prompt.elapsed = recordedSeconds > 0 ? min(recordedSeconds, prompt.maxSeconds) : prompt.elapsed
        prompt.phase = .recorded
    }

    public func cancel() {
        if prompt.phase == .recording { recorder.cancel() }
        try? FileManager.default.removeItem(at: fileURL)
        prompt.phase = .failed("cancelled")
    }

    public struct Result: Equatable, Sendable {
        public var m4a: Data
        public var transcript: String?
        public var seconds: Double
        public var file: URL
    }

    /// Stops if still recording, transcribes on this Mac (no transcript is not an error), and hands the audio to `deliver`.
    /// Returns nil (with `phase` failed) when the audio is empty or over the upload limit or `deliver` throws.
    @discardableResult
    public func send(deliver: (Result) async throws -> Void) async -> Result? {
        if prompt.phase == .recording { stop() }
        guard prompt.phase == .recorded else { return nil }
        prompt.phase = .sending
        guard let data = try? Data(contentsOf: fileURL), !data.isEmpty else {
            prompt.phase = .failed("Nothing was recorded.")
            return nil
        }
        guard data.count <= VoiceReplyLimits.maxUploadBytes else {
            prompt.phase = .failed("That recording is too large to send (1 MB at most).")
            return nil
        }
        let transcript = await Self.withTimeout(transcribeTimeout) { [transcriber, fileURL] in await transcriber.transcribe(fileURL) }
        let clean = transcript?.trimmingCharacters(in: .whitespacesAndNewlines)
        let result = Result(m4a: data, transcript: (clean?.isEmpty == false) ? clean : nil, seconds: recordedSeconds, file: fileURL)
        do { try await deliver(result) }
        catch {
            prompt.phase = .failed("Could not send: \(error.localizedDescription)")
            return nil
        }
        return result
    }

    /// The value of `work`, or nil after `seconds`.
    static func withTimeout<T: Sendable>(_ seconds: TimeInterval, _ work: @escaping @Sendable () async -> T?) async -> T? {
        await withTaskGroup(of: T?.self) { g in
            g.addTask { await work() }
            g.addTask { try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000)); return nil }
            let first = await g.next() ?? nil
            g.cancelAll()
            return first
        }
    }
}
