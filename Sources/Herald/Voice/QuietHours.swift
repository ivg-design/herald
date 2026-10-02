import Foundation

/// Pure quiet-hours logic (DESIGN section 7.9.1): which windows are active at an instant, how an ad-hoc silence
/// and "Resume now" combine with them, whether an urgent notification may break through, how an update is applied.
public enum QuietEvaluator {

    // MARK: Times

    /// "HH:MM" (also "H:MM") to minutes after midnight; nil unless it is a valid 24-hour time.
    public static func minutes(_ s: String) -> Int? {
        let parts = s.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]),
              (0..<24).contains(h), (0..<60).contains(m), parts[1].count == 2 else { return nil }
        return h * 60 + m
    }

    public static func isValid(_ w: QuietWindow) -> Bool {
        guard let s = minutes(w.start), let e = minutes(w.end), s != e else { return false }
        return w.days.allSatisfy { QuietDay.normalize($0) != nil }
    }

    /// The first moment after `date` at which the clock reads `hhmm` (today if still ahead, else tomorrow).
    public static func next(_ hhmm: String, after date: Date, calendar: Calendar = .current) -> Date? {
        guard let m = minutes(hhmm) else { return nil }
        let today = calendar.startOfDay(for: date)
        for offset in 0...2 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                  let t = calendar.date(bySettingHour: m / 60, minute: m % 60, second: 0, of: day), t > date else { continue }
            return t
        }
        return nil
    }

    // MARK: Windows

    /// The occurrence of `w` that contains `now` (start inclusive, end exclusive), if any. A window belongs to the
    /// day it STARTS on: Mon 22:30 to 07:30 runs Monday evening into Tuesday morning.
    public static func occurrence(of w: QuietWindow, at now: Date, calendar: Calendar = .current) -> (start: Date, end: Date)? {
        guard isValid(w), let s = minutes(w.start), let e = minutes(w.end) else { return nil }
        let days = Set(w.days.compactMap { QuietDay.normalize($0).flatMap(QuietDay.weekday) })
        let today = calendar.startOfDay(for: now)
        for offset in [0, -1] {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
            if !days.isEmpty && !days.contains(calendar.component(.weekday, from: day)) { continue }
            guard let start = calendar.date(bySettingHour: s / 60, minute: s % 60, second: 0, of: day) else { continue }
            let endDay = s < e ? day : (calendar.date(byAdding: .day, value: 1, to: day) ?? day)
            guard let end = calendar.date(bySettingHour: e / 60, minute: e % 60, second: 0, of: endDay) else { continue }
            if start <= now && now < end { return (start, end) }
        }
        return nil
    }

    // MARK: State

    /// What is silenced at `now`: the union of the active, not-resumed windows and an unexpired ad-hoc silence.
    public static func status(at now: Date, config: HeraldQuietHours, calendar: Calendar = .current) -> HeraldQuietStatus {
        var st = HeraldQuietStatus()
        var fromWindow = false, fromAdHoc = false
        for w in config.windows {
            guard let occ = occurrence(of: w, at: now, calendar: calendar) else { continue }
            if let r = config.resumedUntil, occ.end <= r { continue }   // "Resume now" ended this occurrence
            st.speech = st.speech || w.speech; st.sounds = st.sounds || w.sounds; st.banners = st.banners || w.banners
            st.until = max(st.until ?? occ.end, occ.end)
            fromWindow = true
        }
        if let a = config.adHoc, now < a.until {
            st.speech = st.speech || a.speech; st.sounds = st.sounds || a.sounds; st.banners = st.banners || a.banners
            st.until = max(st.until ?? a.until, a.until)
            fromAdHoc = true
        }
        st.active = fromWindow || fromAdHoc
        st.source = fromWindow && fromAdHoc ? "both" : fromWindow ? "window" : fromAdHoc ? "adhoc" : nil
        // A window that silences nothing is not "quiet" for the menu.
        if st.active && !(st.speech || st.sounds || st.banners) { st.active = false; st.source = nil; st.until = nil }
        return st
    }

    /// IDs of the active windows that asked for an end-of-window summary.
    public static func summaryWindowIDs(at now: Date, config: HeraldQuietHours, calendar: Calendar = .current) -> [String] {
        config.windows.filter { w in
            guard w.speakSummary, w.speech, let occ = occurrence(of: w, at: now, calendar: calendar) else { return false }
            return config.resumedUntil.map { occ.end > $0 } ?? true
        }.map(\.id)
    }

    /// `priority: "urgent"` breaks quiet hours only when the app's "Urgent can break quiet hours" is on.
    public static func effective(_ status: HeraldQuietStatus, priority: String?, urgentBreaksQuiet: Bool) -> HeraldQuietStatus {
        guard status.active, urgentBreaksQuiet, priority?.lowercased() == "urgent" else { return status }
        return HeraldQuietStatus()
    }

    // MARK: Updates

    public struct InvalidUpdate: Error, Equatable { public var message: String }

    /// Applies a `PUT /v1/settings/quiet-hours` body (windows, then resume, then ad-hoc). An ad-hoc silence started
    /// by the same update wins over a resume in it.
    public static func apply(_ u: HeraldQuietUpdate, to config: HeraldQuietHours, now: Date,
                             calendar: Calendar = .current) throws -> HeraldQuietHours {
        var c = config
        if let windows = u.windows {
            guard windows.count <= 24 else { throw InvalidUpdate(message: "at most 24 windows") }
            var seen = Set<String>()
            for (i, w) in windows.enumerated() {
                guard minutes(w.start) != nil else { throw InvalidUpdate(message: "windows[\(i)].start must be HH:MM (24-hour)") }
                guard minutes(w.end) != nil else { throw InvalidUpdate(message: "windows[\(i)].end must be HH:MM (24-hour)") }
                guard w.start != w.end else { throw InvalidUpdate(message: "windows[\(i)]: start and end are the same") }
                for d in w.days where QuietDay.normalize(d) == nil {
                    throw InvalidUpdate(message: "windows[\(i)].days: unknown day '\(d)'")
                }
                if !seen.insert(w.id).inserted { throw InvalidUpdate(message: "windows[\(i)]: duplicate id") }
            }
            c.windows = windows.map { w in var x = w; x.days = w.days.compactMap(QuietDay.normalize); return x }
        }
        if u.resume == true { c = resume(c, now: now, calendar: calendar) }
        if let a = u.adHoc {
            let until: Date
            if let m = a.minutes {
                guard m > 0, m <= 60 * 24 * 7 else { throw InvalidUpdate(message: "adHoc.minutes must be greater than 0 and at most 10080") }
                until = now.addingTimeInterval(m * 60)
            } else if let s = a.until, !s.isEmpty {
                if minutes(s) != nil { guard let t = next(s, after: now, calendar: calendar) else { throw InvalidUpdate(message: "adHoc.until: bad time") }; until = t }
                else if let t = ISODate.parse(s) { guard t > now else { throw InvalidUpdate(message: "adHoc.until is in the past") }; until = t }
                else { throw InvalidUpdate(message: "adHoc.until must be HH:MM or an ISO 8601 date") }
            } else { throw InvalidUpdate(message: "adHoc needs until or minutes") }
            c.adHoc = HeraldQuietAdHoc(until: until, speech: a.speech ?? true, sounds: a.sounds ?? true, banners: a.banners ?? false)
        }
        return c
    }

    /// "Resume now": ends an ad-hoc silence and the occurrence of every window active at `now`.
    public static func resume(_ config: HeraldQuietHours, now: Date, calendar: Calendar = .current) -> HeraldQuietHours {
        var c = config
        c.adHoc = nil
        let ends = c.windows.compactMap { occurrence(of: $0, at: now, calendar: calendar)?.end }
        if let latest = ends.max() { c.resumedUntil = max(c.resumedUntil ?? latest, latest) }
        return c
    }

    public static func reply(for config: HeraldQuietHours, now: Date, calendar: Calendar = .current) -> HeraldQuietReply {
        HeraldQuietReply(windows: config.windows, adHoc: config.adHoc.flatMap { now < $0.until ? $0 : nil },
                         status: status(at: now, config: config, calendar: calendar))
    }
}

/// The end-of-window summary: "3 messages while you were away: Build, Deploy and 1 more".
public enum QuietSummary {
    public static func text(titles: [String], limit: Int = 4) -> String? {
        let clean = titles.map { HeraldSpeak.clean($0) }.filter { !$0.isEmpty }
        guard !clean.isEmpty else { return nil }
        let n = titles.count
        let shown = Array(clean.prefix(limit))
        var list = shown.joined(separator: ", ")
        if n > shown.count { list += ", and \(n - shown.count) more" }
        return "\(n) message\(n == 1 ? "" : "s") while you were away: \(list)"
    }
}


/// The end-of-window summary state machine, kept apart from the timer and the speech engine so it can be tested
/// (issue #37): titles of messages whose speech was silenced are held while a window that asked for a summary is
/// active; the tick that sees speech become audible again returns the one-line summary to speak, once.
public struct QuietSummaryTracker: Sendable {
    public private(set) var held: [String] = []
    private var heldForSummary = false
    private var wasSpeechQuiet = false

    public init(wasSpeechQuiet: Bool = false) { self.wasSpeechQuiet = wasSpeechQuiet }

    public mutating func hold(title: String, config: HeraldQuietHours, at now: Date, calendar: Calendar = .current) {
        if !QuietEvaluator.summaryWindowIDs(at: now, config: config, calendar: calendar).isEmpty {
            held.append(title); heldForSummary = true
        }
    }

    /// `speechQuiet` is the current status. Returns the text to speak when a silencing period just ended.
    public mutating func tick(speechQuiet: Bool) -> String? {
        defer { wasSpeechQuiet = speechQuiet }
        guard !speechQuiet, wasSpeechQuiet else { return nil }
        let titles = held
        held = []
        defer { heldForSummary = false }
        return heldForSummary ? QuietSummary.text(titles: titles) : nil
    }
}
