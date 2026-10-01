import XCTest
@testable import HeraldCore

final class SnoozeTests: XCTestCase {
    var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        return c
    }()

    private func date(_ s: String) -> Date { ISODate.parse(s, calendar: cal)! }

    func testRelativeOptions() {
        let now = date("2026-10-01T11:30:00")
        XCTAssertEqual(SnoozeOption.minutes5.fireDate(from: now, calendar: cal), date("2026-10-01T11:35:00"))
        XCTAssertEqual(SnoozeOption.minutes15.fireDate(from: now, calendar: cal), date("2026-10-01T11:45:00"))
        XCTAssertEqual(SnoozeOption.hour1.fireDate(from: now, calendar: cal), date("2026-10-01T12:30:00"))
    }

    func testTomorrowNineIsNextDayEvenBeforeNine() {
        XCTAssertEqual(SnoozeOption.tomorrow9.fireDate(from: date("2026-10-01T23:50:00"), calendar: cal), date("2026-10-02T09:00:00"))
        XCTAssertEqual(SnoozeOption.tomorrow9.fireDate(from: date("2026-10-01T06:00:00"), calendar: cal), date("2026-10-02T09:00:00"))
    }

    func testTomorrowNineAcrossDST() {
        // US DST ends 2026-11-01; tomorrow 09:00 local must stay 09:00 wall-clock.
        let fire = SnoozeOption.tomorrow9.fireDate(from: date("2026-10-31T20:00:00"), calendar: cal)
        XCTAssertEqual(cal.dateComponents([.year, .month, .day, .hour, .minute], from: fire),
                       DateComponents(year: 2026, month: 11, day: 1, hour: 9, minute: 0))
    }
}

// MARK: Hardening: DST, midnight, other zones, restore plan, marker, routes

final class SnoozeScheduleTests: XCTestCase {
    private func calendar(_ id: String) -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: id)!
        return c
    }
    /// ISO 8601 with an explicit offset, so the instant is unambiguous whatever zone the test runs in.
    private func at(_ s: String) -> Date { ISODate.parse(s)! }
    private let ny = "America/New_York"

    // Relative options are elapsed time

    func testRelativeSnoozeIsElapsedTimeAcrossFallBack() {
        let cal = calendar(ny)
        // 2026-11-01: 01:30 happens twice (EDT then EST).
        let first = at("2026-11-01T00:30:00-04:00")
        XCTAssertEqual(SnoozeOption.hour1.fireDate(from: first, calendar: cal), at("2026-11-01T01:30:00-04:00"))
        let ambiguous = at("2026-11-01T01:30:00-04:00")
        XCTAssertEqual(SnoozeOption.hour1.fireDate(from: ambiguous, calendar: cal), at("2026-11-01T01:30:00-05:00"))
        XCTAssertEqual(SnoozeOption.hour1.fireDate(from: ambiguous, calendar: cal).timeIntervalSince(ambiguous), 3600)
    }

    func testRelativeSnoozeAcrossSpringForwardGap() {
        let cal = calendar(ny)
        // 02:00-03:00 does not exist on 2026-03-08.
        let now = at("2026-03-08T01:58:00-05:00")
        XCTAssertEqual(SnoozeOption.minutes5.fireDate(from: now, calendar: cal), at("2026-03-08T03:03:00-04:00"))
        XCTAssertEqual(SnoozeOption.minutes15.fireDate(from: now, calendar: cal).timeIntervalSince(now), 900)
    }

    // Tomorrow 9:00

    func testTomorrowNineAcrossSpringForward() {
        let cal = calendar(ny)
        XCTAssertEqual(SnoozeOption.tomorrow9.fireDate(from: at("2026-03-07T22:00:00-05:00"), calendar: cal),
                       at("2026-03-08T09:00:00-04:00"))
        XCTAssertEqual(SnoozeOption.tomorrow9.fireDate(from: at("2026-03-08T01:30:00-05:00"), calendar: cal),
                       at("2026-03-09T09:00:00-04:00"))
    }

    func testTomorrowNineAcrossFallBackFromBothOneThirties() {
        let cal = calendar(ny)
        let expected = at("2026-11-02T09:00:00-05:00")
        XCTAssertEqual(SnoozeOption.tomorrow9.fireDate(from: at("2026-11-01T01:30:00-04:00"), calendar: cal), expected)
        XCTAssertEqual(SnoozeOption.tomorrow9.fireDate(from: at("2026-11-01T01:30:00-05:00"), calendar: cal), expected)
    }

    func testTomorrowNineAroundMidnight() {
        let cal = calendar(ny)
        let expected = at("2026-10-02T09:00:00-04:00")
        XCTAssertEqual(SnoozeOption.tomorrow9.fireDate(from: at("2026-10-01T00:00:00-04:00"), calendar: cal), expected)
        XCTAssertEqual(SnoozeOption.tomorrow9.fireDate(from: at("2026-10-01T00:00:01-04:00"), calendar: cal), expected)
        XCTAssertEqual(SnoozeOption.tomorrow9.fireDate(from: at("2026-10-01T23:59:59-04:00"), calendar: cal), expected)
        // Exactly at 09:00 and just after it: still tomorrow, never "later today".
        XCTAssertEqual(SnoozeOption.tomorrow9.fireDate(from: at("2026-10-01T09:00:00-04:00"), calendar: cal), expected)
    }

    func testTomorrowNineAcrossYearAndLeapDay() {
        let cal = calendar(ny)
        XCTAssertEqual(SnoozeOption.tomorrow9.fireDate(from: at("2026-12-31T23:00:00-05:00"), calendar: cal),
                       at("2027-01-01T09:00:00-05:00"))
        XCTAssertEqual(SnoozeOption.tomorrow9.fireDate(from: at("2028-02-28T10:00:00-05:00"), calendar: cal),
                       at("2028-02-29T09:00:00-05:00"))
        XCTAssertEqual(SnoozeOption.tomorrow9.fireDate(from: at("2027-02-28T10:00:00-05:00"), calendar: cal),
                       at("2027-03-01T09:00:00-05:00"))
    }

    func testTomorrowIsComputedInTheUsersCalendar() {
        // 2026-10-01 20:00 UTC is still Oct 1 in New York but already Oct 2 in Kolkata.
        let now = at("2026-10-01T20:00:00Z")
        XCTAssertEqual(SnoozeOption.tomorrow9.fireDate(from: now, calendar: calendar(ny)), at("2026-10-02T09:00:00-04:00"))
        XCTAssertEqual(SnoozeOption.tomorrow9.fireDate(from: now, calendar: calendar("Asia/Kolkata")), at("2026-10-03T09:00:00+05:30"))
        XCTAssertEqual(SnoozeOption.tomorrow9.fireDate(from: at("2026-10-01T23:30:00+09:00"), calendar: calendar("Asia/Tokyo")),
                       at("2026-10-02T09:00:00+09:00"))
    }

    func testZoneThatSkipsMidnightOnDSTDay() {
        // Brazil 2018-11-04: clocks went 00:00 -> 01:00, so that day starts at 01:00.
        let cal = calendar("America/Sao_Paulo")
        XCTAssertEqual(SnoozeOption.tomorrow9.fireDate(from: at("2018-11-03T20:00:00-03:00"), calendar: cal),
                       at("2018-11-04T09:00:00-02:00"))
        XCTAssertEqual(SnoozeOption.tomorrow9.fireDate(from: at("2018-11-04T05:00:00-02:00"), calendar: cal),
                       at("2018-11-05T09:00:00-02:00"))
    }

    func testZoneThatSkippedAWholeDay() {
        // Samoa skipped 2011-12-30 entirely: "tomorrow" from Dec 29 is Dec 31.
        let cal = calendar("Pacific/Apia")
        XCTAssertEqual(SnoozeOption.tomorrow9.fireDate(from: at("2011-12-29T23:00:00-10:00"), calendar: cal),
                       at("2011-12-31T09:00:00+14:00"))
    }

    /// Every half hour around the DST changes of five zones (one with a 30 minute shift): the result is
    /// in the future, at 09:00:00 local, on the next calendar day, and at most 34 hours away.
    func testTomorrowNineInvariantsAcrossDSTWindows() {
        let windows: [(String, String, String)] = [
            (ny, "2026-03-07T00:00:00-05:00", "2026-03-10T00:00:00-04:00"),
            (ny, "2026-10-31T00:00:00-04:00", "2026-11-03T00:00:00-05:00"),
            ("Europe/London", "2026-03-27T00:00:00Z", "2026-03-30T00:00:00Z"),
            ("Europe/London", "2026-10-24T00:00:00Z", "2026-10-27T00:00:00Z"),
            ("Australia/Lord_Howe", "2026-04-03T00:00:00+11:00", "2026-04-06T00:00:00+10:30"),
            ("Australia/Lord_Howe", "2026-10-03T00:00:00+10:30", "2026-10-06T00:00:00+11:00"),
            ("America/Sao_Paulo", "2018-11-02T00:00:00-03:00", "2018-11-06T00:00:00-02:00"),
        ]
        for (zone, from, to) in windows {
            let cal = calendar(zone)
            var now = at(from)
            let end = at(to)
            while now < end {
                let fire = SnoozeOption.tomorrow9.fireDate(from: now, calendar: cal)
                let local = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: fire)
                let tomorrow = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now))!
                let want = cal.dateComponents([.year, .month, .day], from: tomorrow)
                XCTAssertGreaterThan(fire, now, "\(zone) \(now)")
                XCTAssertEqual([local.hour, local.minute, local.second], [9, 0, 0], "\(zone) \(now)")
                XCTAssertEqual([local.year, local.month, local.day], [want.year, want.month, want.day], "\(zone) \(now)")
                XCTAssertLessThanOrEqual(fire.timeIntervalSince(now), 34 * 3600, "\(zone) \(now)")
                now = now.addingTimeInterval(1800)
            }
        }
    }

    // API minutes

    func testMinutesValidation() {
        XCTAssertTrue(Snooze.isValid(minutes: 1))
        XCTAssertTrue(Snooze.isValid(minutes: 0.5))
        XCTAssertTrue(Snooze.isValid(minutes: Snooze.maxMinutes))
        for bad in [0, -5, Snooze.maxMinutes + 1, .nan, .infinity] as [Double] {
            XCTAssertFalse(Snooze.isValid(minutes: bad), "\(bad)")
        }
        let now = at("2026-10-01T12:00:00-04:00")
        XCTAssertEqual(Snooze.fireDate(afterMinutes: 90, from: now), at("2026-10-01T13:30:00-04:00"))
    }

    // Restore on relaunch

    func testRestorePlan() {
        let now = at("2026-10-01T12:00:00-04:00")
        let later = now.addingTimeInterval(600), earlier = now.addingTimeInterval(-600)
        XCTAssertEqual(Snooze.restoreAction(snoozedUntil: later, persistent: true, now: now), .schedule(later))
        XCTAssertEqual(Snooze.restoreAction(snoozedUntil: earlier, persistent: true, now: now), .fireNow)
        XCTAssertEqual(Snooze.restoreAction(snoozedUntil: now, persistent: true, now: now), .fireNow)
        XCTAssertEqual(Snooze.restoreAction(snoozedUntil: nil, persistent: true, now: now), .showNow)
        XCTAssertEqual(Snooze.restoreAction(snoozedUntil: nil, persistent: false, now: now), .expire)
        // A snoozed transient notification is still snoozed: it must not be expired by the relaunch.
        XCTAssertEqual(Snooze.restoreAction(snoozedUntil: later, persistent: false, now: now), .schedule(later))
        XCTAssertEqual(Snooze.restoreAction(snoozedUntil: earlier, persistent: false, now: now), .fireNow)
    }

    /// The persisted `snoozedUntil` is what survives a relaunch: it must round-trip through the history file.
    func testSnoozedUntilSurvivesHistoryRoundTrip() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("herald-snooze-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let until = at("2026-10-02T09:00:00-04:00")
        let store = HistoryStore(directory: dir)
        store.upsert(HeraldHistoryItem(id: "n", app: "a", notification: HeraldNotification(app: "a", id: "n", title: "t", snooze: true),
                                       deliveredAt: at("2026-10-01T12:00:00-04:00")))
        store.update(app: "a", id: "n") { $0.snoozedUntil = until }
        let reopened = HistoryStore(directory: dir)
        XCTAssertEqual(reopened.item(app: "a", id: "n")?.snoozedUntil, until)
        XCTAssertEqual(reopened.undismissed().map(\.id), ["n"], "a snoozed item stays in the undismissed set")
    }

    // History marker

    func testSnoozeMarker() {
        let cal = calendar(ny)
        let us = Locale(identifier: "en_US")
        let now = at("2026-10-01T11:30:00-04:00")
        var item = HeraldHistoryItem(id: "n", app: "a", notification: HeraldNotification(app: "a", title: "t"), deliveredAt: now)
        XCTAssertFalse(item.isSnoozed)
        XCTAssertNil(item.snoozeMarker(now: now, calendar: cal, locale: us))

        item.snoozedUntil = at("2026-10-01T15:15:00-04:00")
        XCTAssertTrue(item.isSnoozed)
        let today = item.snoozeMarker(now: now, calendar: cal, locale: us)!
        XCTAssertTrue(today.hasPrefix("\u{23F0} Snoozed until "), today)
        XCTAssertTrue(today.contains("3:15"), today)
        XCTAssertFalse(today.contains("Oct"), today)

        item.snoozedUntil = at("2026-10-02T09:00:00-04:00")
        let tomorrow = item.snoozeMarker(now: now, calendar: cal, locale: us)!
        XCTAssertTrue(tomorrow.contains("Oct 2") && tomorrow.contains("9:00"), tomorrow)

        item.dismissedAt = now
        XCTAssertFalse(item.isSnoozed)
        XCTAssertNil(item.snoozeMarker(now: now, calendar: cal, locale: us))
    }
}

// MARK: POST /v1/snooze and /v1/unsnooze

final class SnoozeRouteTests: XCTestCase {
    final class MockSnoozeBackend: HeraldSnoozeBackend, @unchecked Sendable {
        var snoozed: [(String, String, Double)] = []
        var unsnoozed: [(String, String)] = []
        var error: BackendError?
        let until = Date(timeIntervalSince1970: 1_800_000_000)
        func snooze(app: String, id: String, minutes: Double) async throws -> Date {
            if let error { throw error }
            snoozed.append((app, id, minutes)); return until
        }
        func unsnooze(app: String, id: String) async throws {
            if let error { throw error }
            unsnoozed.append((app, id))
        }
    }

    let token = "secret-token"
    var backend = MockSnoozeBackend()

    override func setUp() { backend = MockSnoozeBackend() }

    private func req(_ method: String = "POST", _ path: String, body: String = "", token: String? = "secret-token") -> HTTPRequest {
        var h: [String: String] = [:]
        if let token { h["authorization"] = "Bearer \(token)" }
        return HTTPRequest(method: method, path: path, headers: h, body: Data(body.utf8))
    }

    private func call(_ r: HTTPRequest) async -> HTTPResponse? {
        await SnoozeRoutes.handle(r, token: token, backend: backend)
    }

    private func text(_ r: HTTPResponse?) -> String { String(data: r?.body ?? Data(), encoding: .utf8) ?? "" }

    func testOtherPathsAreNotHandled() async {
        let r1 = await call(req("GET", "/v1/apps")); XCTAssertNil(r1)
        let r2 = await call(req("POST", "/v1/notify")); XCTAssertNil(r2)
    }

    func testAuthIsRequired() async {
        for path in [SnoozeRoutes.snoozePath, SnoozeRoutes.unsnoozePath] {
            for t in [nil, "wrong", "secret-token-x"] as [String?] {
                let r = await call(req("POST", path, body: "{\"app\":\"a\",\"id\":\"n\",\"minutes\":5}", token: t))
                XCTAssertEqual(r?.status, 401)
            }
        }
        XCTAssertTrue(backend.snoozed.isEmpty && backend.unsnoozed.isEmpty)
    }

    func testOnlyPostIsAllowed() async {
        let r = await call(req("GET", "/v1/snooze"))
        XCTAssertEqual(r?.status, 405)
        let d = await call(req("DELETE", "/v1/unsnooze"))
        XCTAssertEqual(d?.status, 405)
    }

    func testSnoozeSuccess() async throws {
        let r = await call(req("POST", "/v1/snooze", body: "{\"app\":\"bidbot\",\"id\":\"bid-42\",\"minutes\":15}"))
        XCTAssertEqual(r?.status, 200)
        XCTAssertEqual(backend.snoozed.count, 1)
        XCTAssertEqual(backend.snoozed[0].0, "bidbot")
        XCTAssertEqual(backend.snoozed[0].1, "bid-42")
        XCTAssertEqual(backend.snoozed[0].2, 15)
        let obj = try JSONSerialization.jsonObject(with: r!.body) as! [String: Any]
        XCTAssertEqual(obj["ok"] as? Bool, true)
        XCTAssertEqual(ISODate.parse(obj["until"] as! String), backend.until)
    }

    func testSnoozeValidation() async {
        let cases: [(String, String)] = [
            ("{\"id\":\"n\",\"minutes\":5}", "app"),
            ("{\"app\":\"a\",\"minutes\":5}", "id"),
            ("{\"app\":\"a\",\"id\":\"n\"}", "minutes"),
            ("{\"app\":\"a\",\"id\":\"n\",\"minutes\":0}", "minutes"),
            ("{\"app\":\"a\",\"id\":\"n\",\"minutes\":-3}", "minutes"),
            ("{\"app\":\"a\",\"id\":\"n\",\"minutes\":999999}", "minutes"),
            ("{\"app\":\"a\",\"id\":\"n\",\"minutes\":\"soon\"}", "minutes"),
            ("not json", "JSON"),
            ("", "JSON"),
        ]
        for (body, word) in cases {
            let r = await call(req("POST", "/v1/snooze", body: body))
            XCTAssertEqual(r?.status, 400, body)
            XCTAssertTrue(text(r).contains(word), "\(body) -> \(text(r))")
        }
        XCTAssertTrue(backend.snoozed.isEmpty)
    }

    func testBackendErrorsKeepTheirStatus() async {
        backend.error = BackendError(404, "notification not found")
        let r = await call(req("POST", "/v1/snooze", body: "{\"app\":\"a\",\"id\":\"n\",\"minutes\":5}"))
        XCTAssertEqual(r?.status, 404)
        XCTAssertTrue(text(r).contains("not found"))
        let u = await call(req("POST", "/v1/unsnooze", body: "{\"app\":\"a\",\"id\":\"n\"}"))
        XCTAssertEqual(u?.status, 404)
    }

    func testUnsnooze() async {
        let r = await call(req("POST", "/v1/unsnooze", body: "{\"app\":\"a\",\"id\":\"n\"}"))
        XCTAssertEqual(r?.status, 200)
        XCTAssertEqual(text(r), "{\"ok\":true}")
        XCTAssertEqual(backend.unsnoozed.count, 1)
        let bad = await call(req("POST", "/v1/unsnooze", body: "{\"app\":\"a\"}"))
        XCTAssertEqual(bad?.status, 400)
    }

    func testHandlerFallsThroughForOtherRoutes() async {
        let handler = SnoozeRoutes.handler(token: token, backend: backend) { req in .error(404, "fallback \(req.path)") }
        let other = await handler(req("GET", "/v1/apps"))
        XCTAssertEqual(other.status, 404)
        XCTAssertTrue(String(data: other.body, encoding: .utf8)!.contains("fallback /v1/apps"))
        let mine = await handler(req("POST", "/v1/snooze", body: "{\"app\":\"a\",\"id\":\"n\",\"minutes\":5}"))
        XCTAssertEqual(mine.status, 200)
    }

    func testRoutesOverTheRealListener() async throws {
        let l = HTTPLoopbackListener(port: 0, handler: SnoozeRoutes.handler(token: token, backend: backend) { _ in .error(404, "fallback") })
        try l.start(); defer { l.stop() }
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(l.port)/v1/snooze")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = Data("{\"app\":\"a\",\"id\":\"n\",\"minutes\":10}".utf8)
        let (data, resp) = try await URLSession.shared.data(for: request)
        XCTAssertEqual((resp as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertTrue(String(data: data, encoding: .utf8)!.contains("\"until\""))
        XCTAssertEqual(backend.snoozed.first?.2, 10)
    }
}
