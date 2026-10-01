import XCTest
@testable import HeraldClient
@testable import HeraldCore

final class QuietHoursTests: XCTestCase {
    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        return c
    }()

    /// 2026-10-05 is a Monday.
    private func at(_ day: Int, _ h: Int, _ m: Int = 0) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 10, day: day, hour: h, minute: m))!
    }
    private func st(_ now: Date, _ cfg: HeraldQuietHours) -> HeraldQuietStatus {
        QuietEvaluator.status(at: now, config: cfg, calendar: cal)
    }
    private let night = QuietWindow(id: "n", days: [], start: "22:30", end: "07:30")

    func testTimeParsing() {
        XCTAssertEqual(QuietEvaluator.minutes("07:30"), 450)
        XCTAssertEqual(QuietEvaluator.minutes("23:59"), 1439)
        for bad in ["24:00", "7:5", "0730", "12:60", "", "ab:cd", "-1:00"] { XCTAssertNil(QuietEvaluator.minutes(bad), bad) }
    }

    func testOvernightWindowAcrossMidnight() {
        let cfg = HeraldQuietHours(windows: [night])
        XCTAssertFalse(st(at(5, 22, 29), cfg).active)
        XCTAssertTrue(st(at(5, 22, 30), cfg).active)          // start inclusive
        XCTAssertTrue(st(at(5, 23, 59), cfg).active)
        XCTAssertTrue(st(at(6, 0, 1), cfg).active)            // after midnight
        XCTAssertTrue(st(at(6, 7, 29), cfg).active)
        XCTAssertFalse(st(at(6, 7, 30), cfg).active)          // end exclusive
        XCTAssertFalse(st(at(6, 12), cfg).active)
        XCTAssertEqual(st(at(6, 1), cfg).until, at(6, 7, 30))
    }

    func testSameDayWindow() {
        let cfg = HeraldQuietHours(windows: [QuietWindow(id: "w", days: [], start: "13:00", end: "14:00")])
        XCTAssertFalse(st(at(5, 12, 59), cfg).active)
        XCTAssertTrue(st(at(5, 13), cfg).active)
        XCTAssertFalse(st(at(5, 14), cfg).active)
    }

    func testDaysBelongToTheStartingDay() {
        // Friday-night window: Fri 22:30 to Sat 07:30. Fri 2026-10-09, Sat 10-10.
        let cfg = HeraldQuietHours(windows: [QuietWindow(id: "f", days: ["fri"], start: "22:30", end: "07:30")])
        XCTAssertFalse(st(at(9, 21), cfg).active)
        XCTAssertTrue(st(at(9, 23), cfg).active)
        XCTAssertTrue(st(at(10, 6), cfg).active)              // Saturday morning belongs to Friday's window
        XCTAssertFalse(st(at(10, 8), cfg).active)
        XCTAssertFalse(st(at(10, 23), cfg).active)            // Saturday night does not
        XCTAssertFalse(st(at(8, 23), cfg).active)             // Thursday night does not
        XCTAssertFalse(st(at(9, 6), cfg).active)              // Friday morning is Thursday's window: not selected
    }

    func testDayNamesAreForgiving() {
        let cfg = HeraldQuietHours(windows: [QuietWindow(id: "m", days: ["Monday"], start: "09:00", end: "10:00")])
        XCTAssertTrue(st(at(5, 9, 30), cfg).active)
        XCTAssertFalse(st(at(6, 9, 30), cfg).active)
    }

    func testFlagsAreUnionedAndSpeechOnlyByDefault() {
        let a = QuietWindow(id: "a", start: "22:00", end: "08:00")
        var b = QuietWindow(id: "b", start: "23:00", end: "06:00", speech: false, sounds: true, banners: true)
        b.days = []
        let s = st(at(5, 23, 30), HeraldQuietHours(windows: [a, b]))
        XCTAssertTrue(s.speech); XCTAssertTrue(s.sounds); XCTAssertTrue(s.banners)
        XCTAssertEqual(s.until, at(6, 8))                       // the latest end
        let only = st(at(5, 22, 30), HeraldQuietHours(windows: [a]))
        XCTAssertTrue(only.speech); XCTAssertFalse(only.sounds); XCTAssertFalse(only.banners)
    }

    func testInvalidWindowNeverActive() {
        let bad = QuietWindow(id: "x", start: "10:00", end: "10:00")
        XCTAssertFalse(st(at(5, 10, 30), HeraldQuietHours(windows: [bad])).active)
    }

    // MARK: urgent

    func testUrgentBreaksOnlyWhenTheAppAllowsIt() {
        let s = st(at(5, 23), HeraldQuietHours(windows: [night]))
        XCTAssertTrue(QuietEvaluator.effective(s, priority: "urgent", urgentBreaksQuiet: false).active)
        XCTAssertFalse(QuietEvaluator.effective(s, priority: "urgent", urgentBreaksQuiet: true).active)
        XCTAssertFalse(QuietEvaluator.effective(s, priority: "URGENT", urgentBreaksQuiet: true).active)
        XCTAssertTrue(QuietEvaluator.effective(s, priority: "high", urgentBreaksQuiet: true).active)
        XCTAssertTrue(QuietEvaluator.effective(s, priority: nil, urgentBreaksQuiet: true).active)
    }

    // MARK: ad hoc and resume

    func testAdHocSilencesOutsideTheSchedule() throws {
        let now = at(5, 12)
        let cfg = try QuietEvaluator.apply(.init(adHoc: .init(minutes: 60)), to: HeraldQuietHours(), now: now, calendar: cal)
        XCTAssertTrue(st(at(5, 12, 59), cfg).active)
        XCTAssertEqual(st(at(5, 12, 59), cfg).source, "adhoc")
        XCTAssertTrue(st(at(5, 12, 59), cfg).sounds)            // ad hoc silences speech and sounds
        XCTAssertFalse(st(at(5, 12, 59), cfg).banners)
        XCTAssertFalse(st(at(5, 13, 0), cfg).active)
    }

    func testAdHocUntilClockTimeRollsToTomorrow() throws {
        let cfg = try QuietEvaluator.apply(.init(adHoc: .init(until: "07:30")), to: HeraldQuietHours(), now: at(5, 23), calendar: cal)
        XCTAssertEqual(cfg.adHoc?.until, at(6, 7, 30))
        let today = try QuietEvaluator.apply(.init(adHoc: .init(until: "18:00")), to: HeraldQuietHours(), now: at(5, 9), calendar: cal)
        XCTAssertEqual(today.adHoc?.until, at(5, 18))
    }

    func testResumeEndsTheCurrentWindowOnlyForThatOccurrence() {
        let cfg = HeraldQuietHours(windows: [night])
        let resumed = QuietEvaluator.resume(cfg, now: at(5, 23), calendar: cal)
        XCTAssertFalse(st(at(5, 23, 30), resumed).active)
        XCTAssertFalse(st(at(6, 5), resumed).active)            // the rest of this night
        XCTAssertTrue(st(at(6, 22, 45), resumed).active)        // tomorrow night is quiet again
    }

    func testResumeClearsAdHocAndAdHocAfterResumeWins() throws {
        var cfg = HeraldQuietHours(windows: [night])
        cfg = try QuietEvaluator.apply(.init(adHoc: .init(minutes: 600)), to: cfg, now: at(5, 23), calendar: cal)
        cfg = QuietEvaluator.resume(cfg, now: at(5, 23, 10), calendar: cal)
        XCTAssertNil(cfg.adHoc)
        XCTAssertFalse(st(at(5, 23, 20), cfg).active)
        // A new ad-hoc silence started after the resume takes precedence over it.
        cfg = try QuietEvaluator.apply(.init(adHoc: .init(minutes: 30)), to: cfg, now: at(5, 23, 20), calendar: cal)
        XCTAssertTrue(st(at(5, 23, 40), cfg).active)
        XCTAssertEqual(st(at(5, 23, 40), cfg).source, "adhoc")
        XCTAssertFalse(st(at(5, 23, 55), cfg).active)           // and then the resumed window stays resumed
    }

    func testResumeAndAdHocInOneUpdateKeepsTheAdHoc() throws {
        let cfg = try QuietEvaluator.apply(.init(adHoc: .init(minutes: 30), resume: true), to: HeraldQuietHours(windows: [night]),
                                           now: at(5, 23), calendar: cal)
        XCTAssertTrue(st(at(5, 23, 10), cfg).active)
        XCTAssertEqual(st(at(5, 23, 10), cfg).source, "adhoc")
    }

    func testOffWithNothingActiveChangesNothing() {
        let cfg = HeraldQuietHours(windows: [night])
        XCTAssertEqual(QuietEvaluator.resume(cfg, now: at(5, 12), calendar: cal), cfg)
    }

    // MARK: validation and summaries

    func testApplyValidatesWindows() {
        func bad(_ w: QuietWindow) { XCTAssertThrowsError(try QuietEvaluator.apply(.init(windows: [w]), to: .init(), now: Date(), calendar: cal)) }
        bad(QuietWindow(start: "25:00", end: "07:00"))
        bad(QuietWindow(start: "22:00", end: "22:00"))
        bad(QuietWindow(days: ["funday"], start: "22:00", end: "07:00"))
        XCTAssertThrowsError(try QuietEvaluator.apply(.init(adHoc: .init(minutes: 0)), to: .init(), now: Date()))
        XCTAssertThrowsError(try QuietEvaluator.apply(.init(adHoc: .init()), to: .init(), now: Date()))
        XCTAssertThrowsError(try QuietEvaluator.apply(.init(adHoc: .init(until: "soon")), to: .init(), now: Date()))
    }

    func testWindowJSONDefaultsAndRoundTrip() throws {
        let w = try JSONDecoder().decode(QuietWindow.self, from: Data(#"{"days":["Mon","tue"],"start":"22:30","end":"07:30"}"#.utf8))
        XCTAssertTrue(w.speech); XCTAssertFalse(w.sounds); XCTAssertFalse(w.banners); XCTAssertFalse(w.speakSummary)
        XCTAssertFalse(w.id.isEmpty)
        let cfg = try QuietEvaluator.apply(.init(windows: [w]), to: .init(), now: Date(), calendar: cal)
        XCTAssertEqual(cfg.windows[0].days, ["mon", "tue"])
    }

    func testSummaryWindowsAndText() {
        var w = night; w.speakSummary = true
        XCTAssertEqual(QuietEvaluator.summaryWindowIDs(at: at(5, 23), config: .init(windows: [w]), calendar: cal), ["n"])
        XCTAssertEqual(QuietEvaluator.summaryWindowIDs(at: at(5, 12), config: .init(windows: [w]), calendar: cal), [])
        XCTAssertEqual(QuietSummary.text(titles: ["Build"]), "1 message while you were away: Build")
        XCTAssertEqual(QuietSummary.text(titles: ["A", "B", "C", "D", "E", "F"]),
                       "6 messages while you were away: A, B, C, D, and 2 more")
        XCTAssertNil(QuietSummary.text(titles: []))
    }
}

final class QuietHoursPlumbingTests: XCTestCase {
    private func req(_ args: [String]) throws -> CLIRequest {
        guard case .request(let r) = try CLIArguments.parse(args).action else { throw CLIParseError("x") }
        return r
    }

    func testCLIQuiet() throws {
        var r = try req(["quiet", "--until", "07:30"])
        XCTAssertEqual(r.method, "PUT"); XCTAssertEqual(r.path, "/v1/settings/quiet-hours")
        XCTAssertEqual((r.body?["adHoc"] as? [String: Any])?["until"] as? String, "07:30")
        r = try req(["quiet", "--for", "60", "--banners"])
        XCTAssertEqual((r.body?["adHoc"] as? [String: Any])?["minutes"] as? Int, 60)
        XCTAssertEqual((r.body?["adHoc"] as? [String: Any])?["banners"] as? Bool, true)
        r = try req(["quiet", "off"])
        XCTAssertEqual(r.body?["resume"] as? Bool, true)
        r = try req(["quiet", "status"])
        XCTAssertEqual(r.method, "GET")
        XCTAssertThrowsError(try req(["quiet"]))
        XCTAssertThrowsError(try req(["quiet", "--until", "7pm"]))
        XCTAssertThrowsError(try req(["quiet", "--until", "07:30", "--for", "5"]))
        XCTAssertNoThrow(try req(["notify", "--app", "a", "--title", "t", "--priority", "urgent"]))
    }

    final class QuietBackend: HeraldBackend, @unchecked Sendable {
        var cfg = HeraldQuietHours()
        func notify(_ n: HeraldNotification) async throws -> String { "x" }
        func register(_ r: HeraldAppRegistration) async throws {}
        func dismiss(app: String, id: String) async throws {}
        func dismissAll(app: String?) async throws {}
        func history(app: String?, limit: Int) async throws -> [HeraldHistoryItem] { [] }
        func clearHistory(app: String?) async throws {}
        func apps() async throws -> [HeraldAppRegistration] { [] }
        func quietHours() async throws -> HeraldQuietReply { QuietEvaluator.reply(for: cfg, now: Date()) }
        func updateQuietHours(_ u: HeraldQuietUpdate) async throws -> HeraldQuietReply {
            do { cfg = try QuietEvaluator.apply(u, to: cfg, now: Date()) } catch let e as QuietEvaluator.InvalidUpdate { throw BackendError(400, e.message) }
            return QuietEvaluator.reply(for: cfg, now: Date())
        }
    }

    func testRoute() async throws {
        let router = Router(token: "t", backend: QuietBackend(), version: "1", pid: 1)
        func call(_ m: String, _ body: String = "") async -> HTTPResponse {
            await router.handle(HTTPRequest(method: m, path: "/v1/settings/quiet-hours", query: [:],
                                            headers: ["authorization": "Bearer t"], body: Data(body.utf8)))
        }
        var r = await call("PUT", #"{"windows":[{"days":["mon"],"start":"22:30","end":"07:30"}]}"#)
        XCTAssertEqual(r.status, 200)
        r = await call("PUT", #"{"adHoc":{"minutes":30}}"#)
        let reply = try HeraldJSON.decoder().decode(HeraldQuietReply.self, from: r.body)
        XCTAssertTrue(reply.status.active); XCTAssertEqual(reply.windows.count, 1)
        r = await call("PUT", #"{"resume":true}"#)
        XCTAssertFalse(try HeraldJSON.decoder().decode(HeraldQuietReply.self, from: r.body).status.active)
        r = await call("GET")
        XCTAssertEqual(r.status, 200)
        r = await call("PUT", #"{"windows":[{"start":"99:00","end":"07:30"}]}"#)
        XCTAssertEqual(r.status, 400)
    }
}
