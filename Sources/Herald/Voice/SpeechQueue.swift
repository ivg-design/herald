import Foundation

/// One thing to say or play.
public enum SpeechUtterance: Equatable, Sendable {
    /// A WAV/MP3/M4A file.
    case file(URL)
    /// Spoken directly by the system synthesizer (no file).
    case system(text: String, voice: String?, speed: Double)
}

/// Plays one utterance and returns when it has finished (or been stopped).
@MainActor
public protocol SpeechPlayer: AnyObject {
    func play(_ utterance: SpeechUtterance) async
    /// Cuts off whatever is playing; the pending `play` returns.
    func stop()
}

/// Speech never overlaps: jobs play one after another in the order they were queued, even when their audio is
/// still being synthesized (synthesis starts at once and overlaps the previous job's playback).
@MainActor
public final class SpeechQueue {
    public struct Job {
        /// Groups jobs of one notification (`app\u{1}id`) so a Dismiss can interrupt exactly those.
        public var key: String
        /// Produces what to play; nil means "nothing to play" (synthesis failed). Started when queued.
        public var utterance: @Sendable () async -> SpeechUtterance?
        /// An explicit replay plays even while Herald is muted (like the sound preview buttons).
        public var ignoresMute: Bool
        /// Called when the job is over: true when its audio played to the end, false when it was skipped (muted, nothing
        /// to play) or cut off (dismissed, stopped). The cloud relay's `spoken` receipt hangs on this.
        public var finished: (@MainActor (Bool) -> Void)?
        public init(key: String, ignoresMute: Bool = false, finished: (@MainActor (Bool) -> Void)? = nil,
                    utterance: @escaping @Sendable () async -> SpeechUtterance?) {
            self.key = key; self.ignoresMute = ignoresMute; self.finished = finished; self.utterance = utterance
        }
    }

    private struct Entry { let key: String; let ignoresMute: Bool; let task: Task<SpeechUtterance?, Never>; let finished: (@MainActor (Bool) -> Void)? }

    public static let maxPending = 20
    private let player: SpeechPlayer
    private let isMuted: () -> Bool
    private var entries: [Entry] = []
    private var currentKey: String?
    private var skipCurrent = false
    private var runner: Task<Void, Never>?
    /// Keys in the order they started playing (tests and diagnostics).
    public private(set) var played: [String] = []

    public init(player: SpeechPlayer, isMuted: @escaping () -> Bool = { false }) {
        self.player = player; self.isMuted = isMuted
    }

    public var isIdle: Bool { currentKey == nil && entries.isEmpty }
    public var pendingCount: Int { entries.count + (currentKey == nil ? 0 : 1) }

    public func enqueue(_ job: Job) {
        entries.append(Entry(key: job.key, ignoresMute: job.ignoresMute, task: Task { await job.utterance() }, finished: job.finished))
        // A flood of notifications must not read out for minutes: the oldest waiting jobs are dropped.
        while entries.count > Self.maxPending { entries.removeFirst().task.cancel() }
        startRunner()
    }

    /// Dismiss of one notification: stops it if it is speaking and forgets its queued jobs.
    public func cancel(key: String) {
        entries.removeAll { if $0.key == key { $0.task.cancel(); return true }; return false }
        if currentKey == key { skipCurrent = true; player.stop() }
    }

    /// Dismiss All, mute, quit: stops the current speech and empties the queue.
    public func stopAll() {
        entries.forEach { $0.task.cancel() }
        entries.removeAll()
        if currentKey != nil { skipCurrent = true; player.stop() }
    }

    /// Resolves when the queue has drained.
    public func waitUntilIdle() async { await runner?.value }

    private func startRunner() {
        guard runner == nil else { return }
        runner = Task { [weak self] in
            while let self, !self.entries.isEmpty {
                let entry = self.entries.removeFirst()
                self.currentKey = entry.key
                self.skipCurrent = false
                let utterance = await entry.task.value
                // Muted, dismissed or stopped while the audio was being prepared: skip it.
                var completed = false
                if let utterance, !self.skipCurrent, entry.ignoresMute || !self.isMuted() {
                    self.played.append(entry.key)
                    await self.player.play(utterance)
                    completed = !self.skipCurrent
                }
                self.currentKey = nil
                entry.finished?(completed)
            }
            self?.runner = nil
        }
    }
}
