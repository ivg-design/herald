import Foundation

/// Quiet hours at delivery time (DESIGN section 7.9.1): answers "what is silenced for this notification", holds
/// the titles of messages whose speech was suppressed, and speaks one summary when a window that asked for it
/// ends (or on "Resume now").
@MainActor
final class QuietHoursCoordinator {
    static let shared = QuietHoursCoordinator()

    private var tracker = QuietSummaryTracker()
    private var timer: Timer?

    private var config: HeraldQuietHours {
        get { AppSettings.shared.quiet }
        set { AppSettings.shared.quiet = newValue }
    }

    /// What is silenced right now, ignoring any notification.
    func status(at now: Date = Date()) -> HeraldQuietStatus {
        QuietEvaluator.status(at: now, config: config)
    }

    /// What is silenced for `n`: the current status, unless `n` is urgent and its app lets urgent break quiet hours.
    func state(for n: HeraldNotification, at now: Date = Date()) -> HeraldQuietStatus {
        QuietEvaluator.effective(status(at: now), priority: n.priority,
                                 urgentBreaksQuiet: VoiceSettings.shared.prefs(for: n.app).urgentBreaksQuiet)
    }

    /// Remembers a notification whose speech was suppressed, for the end-of-window summary.
    func hold(title: String, at now: Date = Date()) {
        tracker.hold(title: title, config: config, at: now)
    }

    func start() {
        tracker = QuietSummaryTracker(wasSpeechQuiet: status().speech)
        timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    /// Detects the end of a speech-silencing period; speaks the summary if one was asked for.
    func tick(at now: Date = Date()) {
        if let text = tracker.tick(speechQuiet: status(at: now).speech) { VoiceCoordinator.shared.speakSummary(text) }
        // The menu and the Settings pane follow the clock too.
        NotificationCenter.default.post(name: .heraldChanged, object: nil)
    }

    // MARK: Changes (menu, Settings, API)

    func apply(_ update: HeraldQuietUpdate, now: Date = Date()) throws -> HeraldQuietReply {
        do { config = try QuietEvaluator.apply(update, to: config, now: now) }
        catch let e as QuietEvaluator.InvalidUpdate { throw BackendError(400, e.message) }
        tick(at: now)
        return QuietEvaluator.reply(for: config, now: now)
    }

    func reply(now: Date = Date()) -> HeraldQuietReply { QuietEvaluator.reply(for: config, now: now) }

    func quietFor(minutes: Double) { _ = try? apply(HeraldQuietUpdate(adHoc: .init(minutes: minutes))) }
    func resumeNow() { _ = try? apply(HeraldQuietUpdate(resume: true)) }
}
