import Foundation

/// Times follow-ups (`HeraldFollowUp`): one timer per banner key, started when the banner actually appears.
///
/// - `start` arms the timer once; a banner that is only redrawn (a failure line, an update in place) keeps it.
/// - `cancel` is any user action on the banner (dismiss, a button, a reply, opening it): the notification is attended
///   and does not arm again, even if the banner is drawn again (a failure line).
/// - `snoozed` drops the timer without marking it attended: the banner that comes back is shown again, and `start`
///   then arms a fresh timer.
/// - A follow-up fires at most once per notification (`hasFired`); `reset` forgets that for a notification that was
///   delivered again under the same id.
/// - Nothing is saved: quitting Herald drops every timer (`cancelAll`).
///
/// The clock and the timer are injected, so tests drive time by hand. Not thread-safe: the app uses it on the main
/// thread only.
public final class FollowUpScheduler {
    /// Something that can be cancelled (a timer).
    public typealias Cancel = () -> Void
    /// Calls `fire` after `seconds`, unless the returned cancel runs first.
    public typealias Timer = (_ seconds: TimeInterval, _ fire: @escaping () -> Void) -> Cancel

    private struct Pending {
        let token: UUID
        let startedAt: Date
        let cancel: Cancel
    }

    private let now: () -> Date
    private let timer: Timer
    private var pending: [String: Pending] = [:]
    private var fired: Set<String> = []
    private var attended: Set<String> = []
    /// Called on fire with the banner key and how long the banner was up, unattended.
    public var onFire: (_ key: String, _ unattendedSeconds: Int) -> Void = { _, _ in }

    public init(now: @escaping () -> Date = Date.init, timer: @escaping Timer = FollowUpScheduler.dispatchTimer) {
        self.now = now; self.timer = timer
    }

    /// A main-queue timer.
    public static let dispatchTimer: Timer = { seconds, fire in
        let item = DispatchWorkItem(block: fire)
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: item)
        return { item.cancel() }
    }

    /// Arms the timer for `key` (the banner is now on screen). False, and nothing changes, when one is already armed
    /// or the follow-up has already fired for this notification.
    @discardableResult
    public func start(key: String, after seconds: TimeInterval) -> Bool {
        guard pending[key] == nil, !fired.contains(key), !attended.contains(key), seconds.isFinite, seconds >= 0 else { return false }
        let token = UUID()
        let started = now()
        let cancel = timer(seconds) { [weak self] in self?.fire(key: key, token: token) }
        pending[key] = Pending(token: token, startedAt: started, cancel: cancel)
        return true
    }

    /// The user did something with the banner: the armed timer (if any) is dropped. A follow-up that already fired
    /// stays fired.
    public func cancel(key: String) {
        pending.removeValue(forKey: key)?.cancel()
        attended.insert(key)
    }

    /// The banner was snoozed: the timer goes, and the banner that comes back starts a fresh one.
    public func snoozed(key: String) {
        pending.removeValue(forKey: key)?.cancel()
        attended.remove(key)
    }

    /// The notification was delivered again under the same id: it may follow up again.
    public func reset(key: String) {
        pending.removeValue(forKey: key)?.cancel()
        fired.remove(key)
        attended.remove(key)
    }

    /// Herald is quitting: every timer goes, nothing is kept.
    public func cancelAll() {
        for p in pending.values { p.cancel() }
        pending.removeAll()
        fired.removeAll()
        attended.removeAll()
    }

    public func isArmed(_ key: String) -> Bool { pending[key] != nil }
    public func isAttended(_ key: String) -> Bool { attended.contains(key) }
    public func hasFired(_ key: String) -> Bool { fired.contains(key) }
    public var armedKeys: [String] { pending.keys.sorted() }

    private func fire(key: String, token: UUID) {
        guard let p = pending[key], p.token == token else { return }   // cancelled or re-armed meanwhile
        pending.removeValue(forKey: key)
        fired.insert(key)
        onFire(key, max(0, Int(now().timeIntervalSince(p.startedAt).rounded())))
    }
}
