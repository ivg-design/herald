import Foundation

// Snooze scheduling, restore-on-relaunch planning, the History marker and the /v1/snooze routes.
// Everything here is Foundation-only so SnoozeTests can exercise it without AppKit.

public enum SnoozeOption: String, CaseIterable, Sendable {
    case minutes5, minutes15, hour1, tomorrow9

    public var title: String {
        switch self {
        case .minutes5: return "5 minutes"
        case .minutes15: return "15 minutes"
        case .hour1: return "1 hour"
        case .tomorrow9: return "Tomorrow 9:00"
        }
    }

    public func fireDate(from now: Date, calendar: Calendar = .current) -> Date {
        switch self {
        case .minutes5: return Snooze.fireDate(afterMinutes: 5, from: now)
        case .minutes15: return Snooze.fireDate(afterMinutes: 15, from: now)
        case .hour1: return Snooze.fireDate(afterMinutes: 60, from: now)
        case .tomorrow9: return Snooze.nextMorning(hour: 9, from: now, calendar: calendar)
        }
    }
}

public enum Snooze {
    /// Upper bound for the API's free-form `minutes` (30 days). A snooze that long is almost surely a mistake,
    /// and the persisted `snoozedUntil` would outlive any reasonable expectation of the caller.
    public static let maxMinutes: Double = 60 * 24 * 30

    public static func isValid(minutes: Double) -> Bool {
        minutes.isFinite && minutes > 0 && minutes <= maxMinutes
    }

    /// Relative snoozes are elapsed time, not wall-clock time: "1 hour" across a DST change is still
    /// exactly 3600 s later (01:30 EDT + 1 h = 01:30 EST). Adding seconds is what gives that.
    public static func fireDate(afterMinutes minutes: Double, from now: Date) -> Date {
        now.addingTimeInterval(minutes * 60)
    }

    /// The next calendar day at `hour`:00 in the user's calendar and time zone, no matter how early or
    /// late `now` is (23:50 and 06:00 both land on tomorrow, never on "today at 09:00").
    ///
    /// The day is found from the start of *today* so that midnight edge cases do not matter: some zones
    /// skip midnight on a DST day (`startOfDay` is then 01:00) and a few skipped a whole day once. The wall
    /// clock time is then set with `.nextTime`, so a 09:00 that does not exist is replaced by the next
    /// instant that does instead of by nothing.
    public static func nextMorning(hour: Int = 9, from now: Date, calendar: Calendar = .current) -> Date {
        let startOfToday = calendar.startOfDay(for: now)
        let fallback = now.addingTimeInterval(24 * 60 * 60)
        guard let startOfTomorrow = calendar.date(byAdding: .day, value: 1, to: startOfToday),
              let morning = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: startOfTomorrow,
                                          matchingPolicy: .nextTime, repeatedTimePolicy: .first,
                                          direction: .forward)
        else { return fallback }
        // Defensive: a calendar that cannot answer sensibly must never schedule a snooze in the past.
        return morning > now ? morning : fallback
    }
}

// MARK: Restore on relaunch

/// What to do with an undismissed history item when Herald starts.
public enum SnoozeRestoreAction: Equatable, Sendable {
    /// Not snoozed: put the banner back on screen.
    case showNow
    /// Not snoozed and transient: it would have timed out while Herald was not running.
    case expire
    /// Snooze still pending: arm a timer for this date, show nothing yet.
    case schedule(Date)
    /// The snooze ran out while Herald was not running: bring the banner back now.
    case fireNow
}

public extension Snooze {
    /// A snoozed item is restored as snoozed whether or not it is persistent. Expiring it because its banner
    /// was "transient" would silently lose exactly the notification the user asked to be reminded about.
    static func restoreAction(snoozedUntil: Date?, persistent: Bool, now: Date) -> SnoozeRestoreAction {
        if let until = snoozedUntil { return until > now ? .schedule(until) : .fireNow }
        return persistent ? .showNow : .expire
    }
}

// MARK: Re-arm after wake or clock change

/// One snoozed notification and when it is due.
public struct PendingSnooze: Equatable, Sendable {
    public var app: String
    public var id: String
    public var until: Date
    public init(app: String, id: String, until: Date) { self.app = app; self.id = id; self.until = until }
}

public struct SnoozeRearmPlan: Equatable, Sendable {
    /// Already due: bring back now, oldest due first, chiming once for the lot.
    public var fireNow: [PendingSnooze]
    /// Still pending: (re)arm a timer for the wall-clock date.
    public var schedule: [PendingSnooze]
}

public extension Snooze {
    /// What to do with the pending snoozes after the Mac woke from sleep or the clock changed (a timer set for a
    /// wall-clock time may have been missed, or now be too early or late). Pure, so it is unit tested (issue #23).
    static func rearmPlan(_ pending: [PendingSnooze], now: Date) -> SnoozeRearmPlan {
        SnoozeRearmPlan(fireNow: pending.filter { $0.until <= now }.sorted { $0.until < $1.until },
                        schedule: pending.filter { $0.until > now })
    }
}

// MARK: History marker

public enum SnoozeMarker {
    public static let symbol = "\u{23F0}"

    /// "⏰ Snoozed until 9:00 AM" for today, "⏰ Snoozed until Oct 2, 9:00 AM" for another day.
    public static func text(until: Date, now: Date = Date(), calendar: Calendar = .current,
                            locale: Locale = .current) -> String {
        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.locale = locale
        f.setLocalizedDateFormatFromTemplate(calendar.isDate(until, inSameDayAs: now) ? "jmm" : "MMMd jmm")
        return "\(symbol) Snoozed until \(f.string(from: until))"
    }
}

public extension HeraldHistoryItem {
    /// Waiting for its snooze to end (the banner is hidden, the item is still in History).
    var isSnoozed: Bool { dismissedAt == nil && snoozedUntil != nil }

    /// Text for the History row of a snoozed item, nil for everything else.
    func snoozeMarker(now: Date = Date(), calendar: Calendar = .current, locale: Locale = .current) -> String? {
        guard isSnoozed, let until = snoozedUntil else { return nil }
        return SnoozeMarker.text(until: until, now: now, calendar: calendar, locale: locale)
    }
}

// MARK: Authentication shared by routes that are served outside Router

public enum BearerAuth {
    /// Same check as `Router`: `Authorization: Bearer <token>`, compared in constant time.
    public static func isAuthorized(_ req: HTTPRequest, token: String) -> Bool {
        isAuthorized(header: req.headers["authorization"], token: token)
    }

    /// The same check on the raw header value, so the listener can run it on the request head alone.
    public static func isAuthorized(header: String?, token: String) -> Bool {
        guard let h = header, h.lowercased().hasPrefix("bearer ") else { return false }
        let given = Array(h.dropFirst(7).trimmingCharacters(in: .whitespaces).utf8)
        let want = Array(token.utf8)
        guard given.count == want.count else { return false }
        var diff: UInt8 = 0
        for i in 0..<want.count { diff |= given[i] ^ want[i] }
        return diff == 0
    }

    /// The pre-body check for Herald's own listener: only `GET /v1/health` is open, so an unauthenticated
    /// caller is answered 401 before any of its body is read. The router checks the token again.
    public static func headCheck(token: String) -> HTTPLoopbackListener.HeadCheck {
        return { head in
            if head.method == "GET" && head.path == "/v1/health" { return nil }
            return isAuthorized(header: head.headers["authorization"], token: token) ? nil : .error(401, "unauthorized")
        }
    }
}

// MARK: POST /v1/snooze and POST /v1/unsnooze

/// What the two snooze endpoints need from the app. Implemented by the AppController's backend adapter.
public protocol HeraldSnoozeBackend: AnyObject, Sendable {
    /// Hides the banner and brings it back after `minutes`. Returns the date it will come back.
    func snooze(app: String, id: String, minutes: Double) async throws -> Date
    /// Cancels a pending snooze and shows the banner again right away (silently: it is not a new alert).
    func unsnooze(app: String, id: String) async throws
}

/// `POST /v1/snooze {"app","id","minutes"}` -> `{"ok":true,"until":"<ISO 8601>"}` and
/// `POST /v1/unsnooze {"app","id"}` -> `{"ok":true}`.
///
/// Served by wrapping the router (`handler(token:backend:fallback:)`) rather than inside it, so these routes
/// do not touch `Router`/`HeraldBackend`, which the template routes are changing. When the router grows these
/// cases natively, drop the wrapper in `AppController.startServer`.
public enum SnoozeRoutes {
    public static let snoozePath = "/v1/snooze"
    public static let unsnoozePath = "/v1/unsnooze"

    /// A request handler that answers the snooze routes and passes everything else to `fallback`.
    public static func handler(token: String, backend: HeraldSnoozeBackend,
                               fallback: @escaping HTTPLoopbackListener.Handler) -> HTTPLoopbackListener.Handler {
        return { req in
            if let response = await handle(req, token: token, backend: backend) { return response }
            return await fallback(req)
        }
    }

    /// nil when `req` is not one of the snooze routes.
    public static func handle(_ req: HTTPRequest, token: String, backend: HeraldSnoozeBackend) async -> HTTPResponse? {
        guard req.path == snoozePath || req.path == unsnoozePath else { return nil }
        guard BearerAuth.isAuthorized(req, token: token) else { return .error(401, "unauthorized") }
        guard req.method == "POST" else { return .error(405, "method not allowed") }
        do {
            let body = try decode(req)
            guard let app = body.app, !app.isEmpty else { throw BackendError(400, "app is required") }
            guard let id = body.id, !id.isEmpty else { throw BackendError(400, "id is required") }
            if req.path == unsnoozePath {
                try await backend.unsnooze(app: app, id: id)
                return .json(200, ["ok": true])
            }
            guard let minutes = body.minutes else { throw BackendError(400, "minutes is required") }
            guard Snooze.isValid(minutes: minutes) else {
                throw BackendError(400, "minutes must be greater than 0 and at most \(Int(Snooze.maxMinutes))")
            }
            let until = try await backend.snooze(app: app, id: id, minutes: minutes)
            return .json(200, SnoozeReply(ok: true, until: ISODate.string(from: until)))
        } catch let e as BackendError {
            return .error(e.status, e.message)
        } catch {
            return .error(500, "\(error)")
        }
    }

    private struct Body: Decodable { var app: String?; var id: String?; var minutes: Double? }
    private struct SnoozeReply: Encodable { var ok: Bool; var until: String }

    private static func decode(_ req: HTTPRequest) throws -> Body {
        do { return try HeraldJSON.decoder().decode(Body.self, from: req.body) }
        catch let e as DecodingError {
            if case .typeMismatch(_, let c) = e {
                throw BackendError(400, "invalid field: \(c.codingPath.map(\.stringValue).joined(separator: "."))")
            }
            throw BackendError(400, "invalid JSON")
        } catch { throw BackendError(400, "invalid JSON") }
    }
}
