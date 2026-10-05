import XCTest
@testable import HeraldClient
@testable import HeraldCore

/// Follow-ups: the model and its wire shapes, durations, validation, which declaration wins, the scheduler, the gates a
/// follow-up runs under, what the action receives, the History record and the cloud-connector path.
final class FollowUpTests: XCTestCase {
    private var dir: URL!
    private var scripts: URL { dir.appendingPathComponent("scripts", isDirectory: true) }
    private var fake: FakeLauncher!

    override func setUp() {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("herald-followup-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: scripts, withIntermediateDirectories: true)
        fake = FakeLauncher()
    }

    override func tearDown() { try? FileManager.default.removeItem(at: dir) }

    private func runner() -> ActionRunner {
        ActionRunner(scriptsDirectory: scripts, shell: "/bin/zsh", shellArguments: ["-c"], shortcutsPath: "/usr/bin/shortcuts",
                     launcher: fake, log: CommandLog(url: dir.appendingPathComponent("logs/actions.log")))
    }

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try HeraldJSON.decoder().decode(T.self, from: Data(json.utf8))
    }

    private func reencode<T: Codable>(_ v: T) throws -> T {
        try HeraldJSON.decoder().decode(T.self, from: HeraldJSON.encoder().encode(v))
    }

    private let forward = HeraldButton(label: "Forward", shortcut: "Forward to phone", input: "{title}")

    // MARK: Durations

    func testDurationParsingAndDescription() {
        XCTAssertEqual(HeraldFollowUp.parseDuration("600"), 600)
        XCTAssertEqual(HeraldFollowUp.parseDuration("90s"), 90)
        XCTAssertEqual(HeraldFollowUp.parseDuration("10m"), 600)
        XCTAssertEqual(HeraldFollowUp.parseDuration("10 min"), 600)
        XCTAssertEqual(HeraldFollowUp.parseDuration("2h"), 7200)
        XCTAssertEqual(HeraldFollowUp.parseDuration(" 1.5H "), 5400)
        for bad in ["", "soon", "-5m", "10x", "m"] { XCTAssertNil(HeraldFollowUp.parseDuration(bad), bad) }
        XCTAssertEqual(HeraldFollowUp.describe(seconds: 90), "90 seconds")
        XCTAssertEqual(HeraldFollowUp.describe(seconds: 60), "1 minute")
        XCTAssertEqual(HeraldFollowUp.describe(seconds: 600), "10 minutes")
        XCTAssertEqual(HeraldFollowUp.describe(seconds: 7200), "2 hours")
        XCTAssertEqual(HeraldFollowUp.describe(seconds: 5400), "1 hour 30 minutes")
    }

    // MARK: Round trips

    func testFollowUpRoundTripsOnManifestNotificationAndTemplate() throws {
        let m = try decode(HeraldManifest.self, """
        {"app":"bidbot","actions":[{"id":"forward","label":"Forward","kind":"shortcut","shortcut":"Forward to phone","input":"{title}"}],
         "followUp":{"after":"10m","actionRef":"forward"}}
        """)
        XCTAssertEqual(m.followUp, HeraldFollowUp(after: 600, actionRef: "forward"))
        XCTAssertEqual(try reencode(m), m)
        XCTAssertTrue(String(decoding: try HeraldJSON.encoder().encode(m), as: UTF8.self).contains(#""after":600"#), "a string is normalised to seconds")
        XCTAssertEqual(m.validationErrors(), [])

        let n = try decode(HeraldNotification.self, """
        {"app":"bidbot","title":"Outbid","buttons":[{"label":"Log","script":"log.sh"},{"label":"Fwd","shortcut":"F","input":"{title}"}],
         "followUp":{"after":90,"action":{"label":"Fwd","kind":"shortcut","shortcut":"F"}}}
        """)
        XCTAssertEqual(n.buttons?[0], HeraldButton(label: "Log", script: "log.sh"))
        XCTAssertEqual(n.buttons?[1], HeraldButton(label: "Fwd", shortcut: "F", input: "{title}"))
        XCTAssertEqual(n.followUp?.after, 90)
        XCTAssertEqual(n.followUp?.action?.kind, .shortcut)
        XCTAssertEqual(try reencode(n), n)

        var t = HeraldTemplate.blank(name: "t", app: "bidbot")
        t.followUp = HeraldFollowUp(enabled: false)
        let back = try reencode(t)
        XCTAssertEqual(back.followUp, HeraldFollowUp(enabled: false))
        XCTAssertFalse(back.followUp!.isEnabled)

        XCTAssertThrowsError(try decode(HeraldFollowUp.self, #"{"after":"soon","actionRef":"x"}"#))
    }

    func testIssuerScriptAndShortcutButtonsBecomeActionsOfThatKind() {
        let a = ActionRunner.legacyAction(forward)
        XCTAssertEqual(a.kind, .shortcut); XCTAssertEqual(a.shortcut, "Forward to phone"); XCTAssertEqual(a.input, "{title}")
        XCTAssertEqual(ActionRunner.legacyAction(HeraldButton(label: "Log", script: "log.sh")).kind, .script)
        XCTAssertEqual(HeraldAction(button: HeraldButton(label: "Log", script: "log.sh")).script, "log.sh")
        XCTAssertEqual(ActionRunner.gate(for: a, origin: .issuer), .appPermission)
    }

    // MARK: Validation

    func testValidationOfKindsRangesAndShape() {
        func errors(_ f: HeraldFollowUp, ids: [String]? = nil, timeout: Double? = nil) -> [String] {
            f.problems(knownActionIDs: ids, timeout: timeout).filter(\.isError).map(\.message)
        }
        XCTAssertEqual(errors(HeraldFollowUp(after: 60, actionRef: "forward"), ids: ["forward"]), [])
        XCTAssertFalse(errors(HeraldFollowUp(after: 4, actionRef: "forward")).isEmpty, "below 5 s")
        XCTAssertFalse(errors(HeraldFollowUp(after: 700_000, actionRef: "forward")).isEmpty, "above 7 days")
        XCTAssertFalse(errors(HeraldFollowUp(actionRef: "forward")).isEmpty, "after is required")
        XCTAssertFalse(errors(HeraldFollowUp(after: 60)).isEmpty, "an action is required")
        XCTAssertFalse(errors(HeraldFollowUp(after: 60, actionRef: "a", action: HeraldAction(id: "b", label: "B", kind: .command, command: "x"))).isEmpty)
        XCTAssertFalse(errors(HeraldFollowUp(after: 60, actionRef: "nope"), ids: ["forward"]).isEmpty)
        XCTAssertEqual(errors(HeraldFollowUp(enabled: false)), [], "switched off needs nothing else")
        for kind in [HeraldActionKind.url, .openApp, .reply, .snooze, .dismiss] {
            let msgs = errors(HeraldFollowUp(after: 60, action: HeraldAction(id: "x", label: "X", kind: kind, url: "https://x")))
            XCTAssertTrue(msgs.contains { $0.contains("cannot be a '\(kind.rawValue)'") }, "\(kind): \(msgs)")
        }
        for kind in HeraldFollowUp.allowedKinds { XCTAssertNil(HeraldFollowUp.kindProblem(kind)) }
        XCTAssertFalse(errors(HeraldFollowUp(after: 60, action: HeraldAction(id: "s", label: "S", kind: .script, script: "../x.sh"))).isEmpty)
        // A banner that closes itself first never follows up: a warning, not an error.
        let warn = HeraldFollowUp(after: 600, actionRef: "f").problems(timeout: 30)
        XCTAssertTrue(warn.contains { !$0.isError && $0.message.contains("never follows up") })

        // The manifest checks its follow-up against its own actions and their kinds.
        let link = HeraldManifest(app: "x", actions: [HeraldButton(label: "Open", url: "https://x")], actionIDs: ["open"])
        var m = link; m.followUp = HeraldFollowUp(after: 60, actionRef: "open")
        XCTAssertTrue(m.validationErrors().contains { $0.contains("followUp.actionRef") }, "\(m.validationErrors())")
        // The template does too, with the manifest it is checked against.
        var t = HeraldTemplate.blank(name: "t", app: "x")
        t.followUp = HeraldFollowUp(after: 60, actionRef: "open")
        XCTAssertTrue(t.validate(manifest: link).contains { $0.isError && $0.path == "followUp.actionRef" })
        t.followUp = HeraldFollowUp(after: 60, action: HeraldAction(id: "f", label: "F", kind: .shortcut, shortcut: "F"))
        XCTAssertFalse(t.validate(manifest: link).contains { $0.isError && $0.path.hasPrefix("followUp") })
    }

    // MARK: Resolution

    func testResolutionPriorityOriginAndSwitchingOff() {
        var m = HeraldManifest(app: "bidbot", actions: [forward, HeraldButton(label: "Open", url: "https://x")], actionIDs: ["forward", "open"])
        m.followUp = HeraldFollowUp(after: 600, actionRef: "forward")
        var n = HeraldNotification(app: "bidbot", id: "1", title: "Outbid", actionIds: ["open"])
        func resolve(_ t: HeraldTemplate?) -> HeraldResolvedFollowUp? { ActionRunner.followUp(notification: n, manifest: m, template: t) }

        // The manifest's: its own action, even though this notification does not show it (hidden ones count).
        let fromManifest = resolve(nil)
        XCTAssertEqual(fromManifest?.source, .manifest)
        XCTAssertEqual(fromManifest?.after, 600)
        XCTAssertEqual(fromManifest?.action.shortcut, "Forward to phone")
        XCTAssertEqual(fromManifest?.origin, .issuer)

        // The notification's replaces it.
        n.followUp = HeraldFollowUp(after: 60, action: HeraldAction(id: "cb", label: "Tell me", kind: .callback))
        XCTAssertEqual(resolve(nil)?.source, .notification)
        XCTAssertEqual(resolve(nil)?.action.kind, .callback)
        XCTAssertEqual(resolve(nil)?.origin, .issuer)

        // The template's replaces both; an inline action is the template's own.
        var t = HeraldTemplate.blank(name: "t", app: "bidbot")
        t.followUp = HeraldFollowUp(after: 30, action: HeraldAction(id: "mine", label: "Mine", kind: .shortcut, shortcut: "Mine"))
        XCTAssertEqual(resolve(t)?.source, .template)
        XCTAssertEqual(resolve(t)?.origin, .template)
        // A template that names an issuer action by ref runs it as the issuer's (the app's permission applies).
        t.followUp = HeraldFollowUp(after: 30, actionRef: "forward")
        XCTAssertEqual(resolve(t)?.origin, .issuer)
        // ... and a rule-hidden issuer action can still be named.
        t.actionRules = [HeraldActionRule(match: "forward", hide: true)]
        XCTAssertEqual(resolve(t)?.action.id, "forward")
        // A template's own added action by ref stays the template's.
        t.actionRules = [HeraldActionRule(add: HeraldAction(id: "slack", label: "Slack", kind: .shortcut, shortcut: "Slack"))]
        t.followUp = HeraldFollowUp(after: 30, actionRef: "slack")
        XCTAssertEqual(resolve(t)?.origin, .template)

        // enabled:false in the template switches the issuer's off; in the notification, the manifest's.
        t.followUp = HeraldFollowUp(enabled: false)
        XCTAssertNil(resolve(t))
        n.followUp = HeraldFollowUp(enabled: false)
        XCTAssertNil(resolve(nil))
        // A kind that cannot follow up resolves to nothing.
        n.followUp = HeraldFollowUp(after: 60, actionRef: "open")
        XCTAssertNil(resolve(nil))
    }

    // MARK: Scheduler

    /// A hand-driven clock: timers fire when `advance` passes their deadline.
    private final class ManualClock {
        var now = Date(timeIntervalSince1970: 1_000)
        private var timers: [(at: Date, fire: () -> Void, cancelled: Bool, id: Int)] = []
        private var next = 0
        var scheduled: Int { timers.filter { !$0.cancelled }.count }
        func timer(_ seconds: TimeInterval, _ fire: @escaping () -> Void) -> FollowUpScheduler.Cancel {
            let id = next; next += 1
            timers.append((now.addingTimeInterval(seconds), fire, false, id))
            return { [weak self] in
                guard let self, let i = self.timers.firstIndex(where: { $0.id == id }) else { return }
                self.timers[i].cancelled = true
            }
        }
        func advance(_ seconds: TimeInterval) {
            now = now.addingTimeInterval(seconds)
            let due = timers.filter { !$0.cancelled && $0.at <= now }
            timers.removeAll { $0.at <= now }
            for t in due { t.fire() }
        }
    }

    func testSchedulerStartsOnShowCancelsOnUserActionsRestartsAfterSnoozeAndFiresOnce() {
        let clock = ManualClock()
        let s = FollowUpScheduler(now: { clock.now }, timer: clock.timer)
        var fired: [(String, Int)] = []
        s.onFire = { fired.append(($0, $1)) }

        // Nothing runs until the banner is shown (quiet hours or mute hold it: no start).
        clock.advance(1000)
        XCTAssertTrue(fired.isEmpty)
        XCTAssertTrue(s.start(key: "a", after: 600))
        XCTAssertFalse(s.start(key: "a", after: 600), "a redraw keeps the timer it has")
        clock.advance(599); XCTAssertTrue(fired.isEmpty)
        clock.advance(2)
        XCTAssertEqual(fired.map(\.0), ["a"]); XCTAssertEqual(fired.first?.1, 601)
        // At most once per notification.
        XCTAssertFalse(s.start(key: "a", after: 600))
        clock.advance(10_000); XCTAssertEqual(fired.count, 1)

        // Each user action cancels (dismiss, a button, a reply, opening it): an attended banner does not arm again.
        XCTAssertTrue(s.start(key: "b", after: 60))
        s.cancel(key: "b")
        XCTAssertFalse(s.start(key: "b", after: 60))
        clock.advance(120); XCTAssertEqual(fired.count, 1)

        // A snooze drops the timer; the banner that comes back starts a fresh one, counted from its return.
        XCTAssertTrue(s.start(key: "c", after: 60))
        clock.advance(50)
        s.snoozed(key: "c")
        clock.advance(300); XCTAssertEqual(fired.count, 1)
        XCTAssertTrue(s.start(key: "c", after: 60))
        clock.advance(59); XCTAssertEqual(fired.count, 1)
        clock.advance(1); XCTAssertEqual(fired.last?.0, "c"); XCTAssertEqual(fired.last?.1, 60)

        // A re-delivery under the same id may follow up again.
        s.reset(key: "a")
        XCTAssertTrue(s.start(key: "a", after: 5))

        // Quitting drops everything: nothing is kept, nothing fires later.
        XCTAssertTrue(s.start(key: "d", after: 60))
        s.cancelAll()
        XCTAssertEqual(s.armedKeys, [])
        clock.advance(1000)
        XCTAssertEqual(fired.count, 2)
        // A new instance (the next launch) knows nothing of the old timers.
        XCTAssertEqual(FollowUpScheduler(now: { clock.now }, timer: clock.timer).armedKeys, [])
    }

    // MARK: Gates

    func testIssuerFollowUpNeedsTheAppPermissionAndTheQuestionNamesWhatRuns() throws {
        let r = runner()
        let approvals = TemplateCommandApprovals(file: dir.appendingPathComponent("approvals.json"))
        let shortcut = ActionRunner.legacyAction(forward)
        // Not registered with allowCommands: refused, nothing runs.
        XCTAssertEqual(r.authorization(for: shortcut, origin: .issuer, app: "bidbot", record: nil, template: nil,
                                       templateName: "", approvals: approvals),
                       .denied("this app has not registered with allowCommands"))
        // Asked, not yet agreed: the banner asks, naming the Shortcut and its input.
        var rec = AppRecord(registration: HeraldAppRegistration(app: "bidbot", allowCommands: true))
        guard case .askApp(let text) = r.authorization(for: shortcut, origin: .issuer, app: "bidbot", record: rec, template: nil,
                                                       templateName: "", approvals: approvals) else { return XCTFail() }
        XCTAssertTrue(text.contains("shortcut: Forward to phone") && text.contains("input: {title}"), text)
        // A script: its name and SHA-256.
        try Data("echo hi\n".utf8).write(to: scripts.appendingPathComponent("log.sh"))
        guard case .askApp(let stext) = r.authorization(for: ActionRunner.legacyAction(HeraldButton(label: "Log", script: "log.sh")),
                                                        origin: .issuer, app: "bidbot", record: rec, template: nil,
                                                        templateName: "", approvals: approvals) else { return XCTFail() }
        XCTAssertTrue(stext.contains("script: log.sh") && stext.contains("sha256: ") && !stext.contains("sha256: missing"), stext)
        // The person allowed it ("Always allow"): it runs.
        rec.commandsConfirmed = true
        XCTAssertEqual(r.authorization(for: shortcut, origin: .issuer, app: "bidbot", record: rec, template: nil,
                                       templateName: "", approvals: approvals), .run)
        // A callback runs no code: nothing to ask.
        XCTAssertEqual(r.authorization(for: HeraldAction(id: "c", label: "C", kind: .callback), origin: .issuer, app: "bidbot",
                                       record: nil, template: nil, templateName: "", approvals: approvals), .run)
    }

    func testTemplateFollowUpAsksOnceThenRunsWithTheFollowUpInput() async throws {
        let r = runner()
        let approvals = TemplateCommandApprovals(file: dir.appendingPathComponent("approvals.json"))
        var t = HeraldTemplate.blank(name: "mine", app: "bidbot")
        let action = HeraldAction(id: "fwd", label: "Forward", kind: .shortcut, shortcut: "Forward", input: "{title} after {herald.unattendedSeconds}s")
        t.followUp = HeraldFollowUp(after: 600, action: action)
        let rec = AppRecord(registration: HeraldAppRegistration(app: "bidbot"))
        // Not approved: the banner asks, and "Always allow" would approve the follow-up's own key with the template's.
        guard case .askTemplate(let key, let all, let text) = r.authorization(for: action, origin: .template, app: "bidbot", record: rec,
                                                                             template: t, templateName: "mine", approvals: approvals)
        else { return XCTFail() }
        XCTAssertTrue(all.contains(key))
        XCTAssertTrue(r.templateApprovalKeys(of: t).contains(key), "the inline follow-up is the template's own code")
        XCTAssertTrue(text.contains("shortcut: Forward"), text)
        approvals.approve(app: "bidbot", template: "mine", commands: all)
        XCTAssertEqual(r.authorization(for: action, origin: .template, app: "bidbot", record: rec, template: t,
                                       templateName: "mine", approvals: approvals), .run)

        // It runs through the same plan as a button, with the follow-up's extra input.
        let n = HeraldNotification(app: "bidbot", id: "n1", title: "Outbid")
        let inv = ActionInvocation(notification: n, fields: TemplateResolver.fields(for: n), template: "mine", unattendedSeconds: 612)
        guard case .success(.process(let spec)) = r.plan(action, origin: .template, invocation: inv) else { return XCTFail() }
        let result = await r.run(spec, context: CommandContext(app: "bidbot", notificationId: "n1", action: "follow-up: Forward"), origin: .template)
        XCTAssertTrue(result.succeeded)
        XCTAssertEqual(fake.calls.first?.input, "Outbid after 612s")

        // A script receives the JSON with the herald object, and the environment says it is a follow-up.
        try Data("cat\n".utf8).write(to: scripts.appendingPathComponent("fwd.sh"))
        let script = HeraldAction(id: "s", label: "S", kind: .script, script: "fwd.sh")
        guard case .success(.process(let sspec)) = r.plan(script, origin: .template, invocation: inv) else { return XCTFail() }
        XCTAssertEqual(sspec.environment["HERALD_FOLLOW_UP"], "1")
        XCTAssertEqual(sspec.environment["HERALD_UNATTENDED_SECONDS"], "612")
        let json = try JSONSerialization.jsonObject(with: sspec.stdin ?? Data()) as? [String: Any]
        let herald = json?["herald"] as? [String: Any]
        XCTAssertEqual(herald?["followUp"] as? Bool, true)
        XCTAssertEqual(herald?["unattendedSeconds"] as? Int, 612)
        // A pressed button says it is not a follow-up, so one Shortcut can serve both.
        let pressed = ActionInvocation(notification: n, fields: TemplateResolver.fields(for: n))
        guard case .success(.process(let pspec)) = r.plan(script, origin: .template, invocation: pressed) else { return XCTFail() }
        XCTAssertNil(pspec.environment["HERALD_FOLLOW_UP"])
        let pjson = try JSONSerialization.jsonObject(with: pspec.stdin ?? Data()) as? [String: Any]
        XCTAssertEqual((pjson?["herald"] as? [String: Any])?["followUp"] as? Bool, false)
    }

    // MARK: Callback event, History record, log

    func testCallbackEventAndHistoryRecord() throws {
        let event = HeraldCallbackEvent(notificationId: "n1", app: "bidbot", action: "Tell me", event: HeraldCallbackEvent.unattendedEvent,
                                        unattendedSeconds: 600)
        let wire = String(decoding: try HeraldJSON.encoder().encode(event), as: UTF8.self)
        XCTAssertTrue(wire.contains(#""event":"unattended""#) && wire.contains(#""unattendedSeconds":600"#), wire)
        XCTAssertFalse(String(decoding: try HeraldJSON.encoder().encode(HeraldCallbackEvent(notificationId: "n", app: "a", action: "b")),
                              as: UTF8.self).contains("event"), "a pressed button's event is unchanged")

        let store = HistoryStore(directory: dir.appendingPathComponent("history", isDirectory: true))
        let n = HeraldNotification(app: "bidbot", id: "n1", title: "Outbid")
        store.upsert(HeraldHistoryItem(id: "n1", app: "bidbot", notification: n, deliveredAt: Date()))
        let at = Date(timeIntervalSince1970: 1_800_000_000)
        let record = HeraldFollowUpRecord(ranAt: at, action: "Forward", actionId: "fwd", kind: .shortcut, outcome: .ran, unattendedSeconds: 612)
        store.update(app: "bidbot", id: "n1") { $0.followUp = record }
        let reopened = HistoryStore(directory: dir.appendingPathComponent("history", isDirectory: true))
        XCTAssertEqual(reopened.item(app: "bidbot", id: "n1")?.followUp, record)
        XCTAssertEqual(record.bannerLine { _ in "14:05" }, "Follow-up ran: Forward at 14:05.")
        XCTAssertEqual(HeraldFollowUpRecord(ranAt: at, action: "Forward", outcome: .failed, detail: "exit 1").bannerLine { _ in "" },
                       "Follow-up failed: Forward (exit 1).")
        let denied = HeraldFollowUpRecord(ranAt: at, action: "Forward", outcome: .failed, detail: HeraldFollowUpRecord.notAllowedDetail(name: "BidBot"))
        XCTAssertTrue(denied.isNotAllowed)
        XCTAssertEqual(denied.bannerLine(appName: "BidBot") { _ in "" }, "Follow-up did not run: allow BidBot to run commands in Settings > Apps.")
        XCTAssertFalse(HeraldFollowUpRecord(ranAt: at, action: "Forward", outcome: .failed, detail: "exit 1").isNotAllowed)
        XCTAssertNil(HeraldFollowUpRecord(ranAt: at, action: "Forward", outcome: .waitingForApproval).bannerLine { _ in "" })

        let line = ActionLog.followUpEntry(app: "bidbot", notificationId: "n1",
                                           action: HeraldAction(id: "fwd", label: "Forward", kind: .shortcut), origin: .template,
                                           record: HeraldFollowUpRecord(ranAt: at, action: "Forward", outcome: .waitingForApproval, unattendedSeconds: 60))
        XCTAssertTrue(line.contains("follow-up waiting for approval") && line.contains("unattended=60s"), line)
    }

    // MARK: Cloud connectors

    /// A connector's notification arrives through the relay as `cloud.<name>`; the user's template for that app (the
    /// manifest's default, as `AppController.notify` picks it) carries the follow-up, and it is scheduled.
    func testRelayDeliveredNotificationSchedulesItsTemplatesFollowUp() throws {
        let frame: [String: Any] = ["type": "notify", "id": "r_1", "notificationId": "build-1", "createdAt": "2026-10-02T10:00:00Z",
                                    "key": ["id": "k1", "name": "build-bot", "client": "codex"],
                                    "payload": ["title": "Build finished", "body": "214 passed"]]
        let env = try JSONDecoder().decode(RelayEnvelope.self, from: JSONSerialization.data(withJSONObject: frame))
        var n = RelayPolicy.notification(for: env, silenceSpeech: false)
        XCTAssertEqual(n.app, "cloud.build-bot")
        XCTAssertNil(n.followUp, "the relay path never carries a follow-up of its own")

        let agent = try XCTUnwrap(AgentIdentity(cloudKeyName: "build-bot", client: "codex"))
        let manifest = agent.manifest()
        let templates = TemplateStore(directory: dir.appendingPathComponent("templates", isDirectory: true))
        var t = agent.template()
        t.followUp = HeraldFollowUp(after: 600, action: HeraldAction(id: "fwd", label: "Forward", kind: .shortcut, shortcut: "Forward to phone"))
        XCTAssertTrue(templates.put(t))
        XCTAssertEqual(t.validate(manifest: manifest).filter { $0.isError && $0.path.hasPrefix("followUp") }.count, 0)

        // notify(): a notification that names no template uses the manifest's default.
        if n.template?.isEmpty != false, let d = manifest.defaultTemplate, templates.get(app: n.app, name: d) != nil { n.template = d }
        let template = templates.template(for: n)
        XCTAssertEqual(template?.name, AgentIdentity.templateName)
        let f = try XCTUnwrap(ActionRunner.followUp(notification: n, manifest: manifest, template: template))
        XCTAssertEqual(f.origin, .template)
        XCTAssertEqual(f.action.shortcut, "Forward to phone")

        let clock = ManualClock()
        let s = FollowUpScheduler(now: { clock.now }, timer: clock.timer)
        var fired: [String] = []
        s.onFire = { k, _ in fired.append(k) }
        XCTAssertTrue(s.start(key: BannerKey.make(n.app, n.id ?? ""), after: f.after))
        clock.advance(600)
        XCTAssertEqual(fired, [BannerKey.make("cloud.build-bot", n.id ?? "")])
    }
}
