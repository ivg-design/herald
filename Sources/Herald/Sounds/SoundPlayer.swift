import AppKit
import Combine

/// Plays notification sounds: system names, installed sounds, file paths, or "none".
///
/// Names are checked against the disk (`SoundCatalog`) instead of being handed to NSSound blindly: an
/// unknown name used to fail silently, so a typo in a client meant a notification that never made a sound
/// and nothing to explain why. Now it is logged once per bad name and the app's default sound plays instead.
@MainActor
final class SoundPlayer {
    static let systemSoundsDirectory = SoundCatalog.systemDirectory
    private var playing: [NSSound] = []
    private var warned: Set<String> = []
    private var muteObserver: AnyCancellable?

    init() {
        // Muting (menu bar or Settings) cuts off a chime that is already playing, not just future ones.
        muteObserver = AppSettings.shared.$muted.dropFirst().sink { [weak self] muted in
            guard muted else { return }
            MainActor.assumeIsolated { self?.stopAll() }
        }
    }

    static var systemSoundNames: [String] { SoundCatalog.names(in: systemSoundsDirectory) }

    /// Whether `spec` is "none", "default", an installed sound or an existing audio file.
    static func isValid(_ spec: String) -> Bool { SoundCatalog.isValid(spec) }

    /// Plays `spec`. If it names no sound that exists, the first playable entry of `fallback` plays instead
    /// (callers pass the app's default sound, then the built-in one). Mute is the caller's business: the
    /// ▶ preview buttons in Settings and the composer play even while Herald is muted.
    /// Returns false when nothing could be played; "none" counts as played (silence was asked for).
    @discardableResult
    func play(_ spec: String, fallback: [String] = []) -> Bool {
        for candidate in [spec] + fallback {
            switch SoundCatalog.resolve(candidate) {
            case .silent:
                return true
            case .useDefault:
                continue
            case .invalid(let why):
                warn(candidate, why)
            case .file(let path):
                guard let sound = NSSound(contentsOfFile: path, byReference: true) else {
                    warn(candidate, "cannot load \(path)")
                    continue
                }
                playing.removeAll { !$0.isPlaying }
                playing.append(sound)
                sound.play()
                return true
            }
        }
        return false
    }

    func stopAll() {
        playing.forEach { $0.stop() }
        playing.removeAll()
    }

    private func warn(_ spec: String, _ why: String) {
        guard warned.insert(spec).inserted else { return }
        NSLog("Herald: sound \"%@\" ignored: %@", spec, why)
    }
}
