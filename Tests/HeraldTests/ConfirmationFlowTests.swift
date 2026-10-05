import XCTest
@testable import HeraldCore
import HeraldClient

/// A banner stand-in: records the question it was asked to show and the clears.
@MainActor
final class FakeSurface: ConfirmationSurface {
    var up: Set<String> = ["acme/1"]
    var shown: [String: BannerConfirmation] = [:]
    var presented: [BannerConfirmation] = []
    var cleared: [String] = []

    func presentConfirmation(_ confirmation: BannerConfirmation, app: String, id: String) -> Bool {
        guard up.contains("\(app)/\(id)") else { return false }
        shown["\(app)/\(id)"] = confirmation
        presented.append(confirmation)
        return true
    }

    func clearConfirmation(app: String, id: String) {
        shown["\(app)/\(id)"] = nil
        cleared.append("\(app)/\(id)")
    }
}

/// What the confirmed action would have done: a command run, a callback sent, Privacy Settings opened.
@MainActor
final class FakeRunner {
    private(set) var runs = 0
    private(set) var settingsOpened = 0
    func run() { runs += 1 }
    func openSettings() { settingsOpened += 1 }
}

/// Issue #40: confirmations are inline rows inside the banner. These cover the state machine (once, always,
/// cancel, a banner that goes away, a second question on the same banner) and that each answer persists exactly
/// what the modal alerts persisted: per app, per template, per host.
@MainActor
final class ConfirmationFlowTests: XCTestCase {
    var dir: URL!
    var registry: AppRegistry!
    var approvals: TemplateCommandApprovals!
    var surface: FakeSurface!
    var runner: FakeRunner!
    var flow: ConfirmationFlow!
    var changes = 0

    private var appsFile: URL { dir.appendingPathComponent("apps.json") }
    private var approvalsFile: URL { dir.appendingPathComponent("template-approvals.json") }

    override func setUp() {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("herald-confirm-\(UUID().uuidString)")
        registry = AppRegistry(file: appsFile)
        registry.register(HeraldAppRegistration(app: "acme", appName: "Acme", allowCommands: true))
        approvals = TemplateCommandApprovals(file: approvalsFile)
        surface = FakeSurface()
        runner = FakeRunner()
        changes = 0
        flow = ConfirmationFlow(registry: registry, approvals: approvals) { [unowned self] in changes += 1 }
        flow.surface = surface
    }

    override func tearDown() { try? FileManager.default.removeItem(at: dir) }

    // MARK: Helpers

    private func askCommand(_ text: String = "say hello", kind: HeraldActionKind = .command) {
        flow.askCommand(app: "acme", id: "1", name: "Acme", kind: kind, text: text) { [runner] in runner!.run() }
    }

    private func askTemplate(pressed: String = "echo one", others: [String] = ["echo two", "script: a.sh sha256:ff"],
                             replaced: String? = nil) {
        flow.askTemplateCommand(app: "acme", id: "1", template: "ops", name: "Acme", kind: .command,
                                pressedText: pressed, approvalKey: pressed, all: [pressed] + others,
                                replacedIssuerLabel: replaced) { [runner] in runner!.run() }
    }

    private func askHost(_ host: String = "hooks.example.com") {
        flow.askCallbackHost(app: "acme", id: "1", name: "Acme", host: host, url: "https://\(host)/cb") { [runner] in runner!.run() }
    }

    // MARK: The question is drawn on the banner

    func testAskingShowsTheQuestionOnTheBannerAndWaitsForAnAnswer() {
        askCommand("rm -rf /tmp/herald-demo")
        let c = surface.shown["acme/1"]
        XCTAssertNotNil(c)
        XCTAssertEqual(flow.confirmation(app: "acme", id: "1"), c)
        XCTAssertEqual(flow.pendingCount, 1)
        XCTAssertEqual(runner.runs, 0, "nothing runs until the user answers")
        XCTAssertFalse(registry.record(for: "acme")!.commandsConfirmed)
    }

    func testTheCommandRowShowsTheExactCommandAndTheThreeButtons() {
        askCommand("osascript -e 'beep 3'")
        let c = surface.shown["acme/1"]!
        XCTAssertEqual(c.kind, .command)
        XCTAssertEqual(c.title, "Run this command for Acme?")
        XCTAssertEqual(c.command, "osascript -e 'beep 3'", "the exact text, not a summary")
        XCTAssertEqual(c.buttons.map(\.title), ["Run once", "Always allow Acme", "Cancel"])
        XCTAssertEqual(c.buttons.map(\.choice), [.once, .always, .cancel])
        XCTAssertEqual(c.buttons.first?.role, .primary, "the safe answer is the prominent one")
        XCTAssertEqual(c.buttons[1].role, .secondary, "the lasting permission is not")
    }

    func testScriptAndShortcutRowsSayWhatKindOfCodeRuns() {
        askCommand("script: notify.sh\nsha256: abc", kind: .script)
        XCTAssertEqual(surface.shown["acme/1"]?.kind, .script)
        XCTAssertEqual(surface.shown["acme/1"]?.title, "Run this script for Acme?")
        askCommand("shortcut: Log\ninput: x", kind: .shortcut)
        XCTAssertEqual(surface.shown["acme/1"]?.kind, .shortcut)
        XCTAssertEqual(surface.shown["acme/1"]?.title, "Run this Shortcut for Acme?")
    }

    func testAFollowUpQuestionSaysItIsAFollowUpAndWhyItAsks() {
        let c = BannerConfirmation.appCommand(kind: .script, name: "Acme", text: "script: notify.sh", followUpSeconds: 600)
        XCTAssertEqual(c.title, "Run this follow-up for Acme?")
        XCTAssertEqual(c.kind, .script)
        XCTAssertEqual(c.detail, "This banner was left up for 10 minutes, so its follow-up wants to run. It runs a script from your Herald scripts folder with your user permissions. Herald cannot verify that Acme sent the notification.")
        XCTAssertEqual(c.buttons, BannerConfirmation.appCommand(kind: .script, name: "Acme", text: "script: notify.sh").buttons)
        XCTAssertTrue(BannerConfirmation.appCommand(kind: .shortcut, name: "Acme", text: "x", followUpSeconds: 90).detail
            .hasPrefix("This banner was left up for 90 seconds, so"))
        XCTAssertTrue(BannerConfirmation.appCommand(kind: .command, name: "Acme", text: "x", followUpSeconds: 7200).detail
            .hasPrefix("This banner was left up for 2 hours, so"))
        // Pressed buttons are unchanged.
        XCTAssertEqual(BannerConfirmation.appCommand(kind: .script, name: "Acme", text: "x").title, "Run this script for Acme?")
    }

    func testAFollowUpFromATemplateNamesTheTemplate() {
        let c = BannerConfirmation.templateCommand(kind: .shortcut, template: "ops", name: "Acme", pressedText: "shortcut: Log",
                                                   others: [], replacedIssuerLabel: nil, followUpSeconds: 60)
        XCTAssertEqual(c.title, "Run this follow-up from the \u{201C}ops\u{201D} template?")
        XCTAssertTrue(c.detail.hasPrefix("This banner was left up for 1 minute, so its follow-up wants to run. This template for Acme runs code"), c.detail)
        XCTAssertEqual(c.kind, .templateCommand)
    }

    func testTheCallbackRowShowsTheHostAndTheFullAddress() {
        askHost("hooks.example.com")
        let c = surface.shown["acme/1"]!
        XCTAssertEqual(c.kind, .callbackHost)
        XCTAssertEqual(c.title, "Send Acme's button action to hooks.example.com?")
        XCTAssertEqual(c.command, "https://hooks.example.com/cb")
        XCTAssertEqual(c.buttons.map(\.title), ["Send once", "Always allow hooks.example.com", "Cancel"])
    }

    func testAVeryLongHostIsShortenedInsideTheButtonButShownInFullAbove() {
        let host = String(repeating: "a", count: 60) + ".example.com"
        askHost(host)
        let c = surface.shown["acme/1"]!
        XCTAssertTrue(c.title.contains(host))
        XCTAssertEqual(c.command, "https://\(host)/cb")
        XCTAssertLessThanOrEqual(c.buttons[1].title.count, "Always allow ".count + 32)
        XCTAssertTrue(c.buttons[1].title.hasSuffix("\u{2026}"))
        flow.answer(app: "acme", id: "1", .always)
        XCTAssertEqual(registry.record(for: "acme")!.callbackHostApproved, host, "the full host is what is remembered")
    }

    func testTheTemplateRowListsEverythingAlwaysAllowCovers() {
        askTemplate(pressed: "echo one", others: ["echo two", "shortcut: Log input: x"], replaced: "Approve")
        let c = surface.shown["acme/1"]!
        XCTAssertEqual(c.kind, .templateCommand)
        XCTAssertEqual(c.title, "Run a command from the \"ops\" template?")
        XCTAssertEqual(c.command, "Running now:\necho one\n\nAlso in this template:\necho two\nshortcut: Log input: x")
        XCTAssertTrue(c.detail.contains("replaces Acme's own \"Approve\" button"))
        XCTAssertTrue(c.detail.contains("Always allow covers everything listed"))
        XCTAssertEqual(c.buttons.map(\.title), ["Run once", "Always allow this template", "Cancel"])
    }

    func testTheTemplateRowForASingleCommandShowsJustThatCommand() {
        askTemplate(pressed: "echo one", others: [])
        let c = surface.shown["acme/1"]!
        XCTAssertEqual(c.command, "echo one")
        XCTAssertFalse(c.detail.contains("covers everything listed"))
    }

    func testTheRemindersErrorIsANoticeWithOKAndPrivacySettingsWhenDenied() {
        flow.showReminderError(app: "acme", id: "1", message: "Reminders access is denied", canOpenSettings: true) { [runner] in
            runner!.openSettings()
        }
        let c = surface.shown["acme/1"]!
        XCTAssertEqual(c.title, "Couldn't add to Reminders")
        XCTAssertEqual(c.detail, "Reminders access is denied")
        XCTAssertEqual(c.tone, .error)
        XCTAssertNil(c.command)
        XCTAssertEqual(c.buttons.map(\.title), ["OK", "Open Privacy Settings"])
        flow.showReminderError(app: "acme", id: "1", message: "disk full", canOpenSettings: false) {}
        XCTAssertEqual(surface.shown["acme/1"]?.buttons.map(\.title), ["OK"])
    }

    // MARK: Issuer command: once / always / cancel

    func testCommandRunOnceRunsAndRemembersNothing() {
        askCommand()
        XCTAssertTrue(flow.answer(app: "acme", id: "1", .once))
        XCTAssertEqual(runner.runs, 1)
        XCTAssertFalse(registry.record(for: "acme")!.commandsConfirmed)
        XCTAssertFalse(AppRegistry(file: appsFile).record(for: "acme")!.commandsConfirmed)
        XCTAssertEqual(changes, 0)
        XCTAssertNil(surface.shown["acme/1"], "the row is taken off the banner")
        XCTAssertEqual(flow.pendingCount, 0)
    }

    func testCommandAlwaysAllowRunsAndApprovesTheAppAndSurvivesARelaunch() {
        askCommand()
        XCTAssertTrue(flow.answer(app: "acme", id: "1", .always))
        XCTAssertEqual(runner.runs, 1)
        XCTAssertTrue(registry.record(for: "acme")!.commandsConfirmed)
        XCTAssertTrue(AppRegistry(file: appsFile).record(for: "acme")!.commandsConfirmed, "persisted to apps.json")
        XCTAssertEqual(changes, 1)
        XCTAssertNil(surface.shown["acme/1"])
    }

    func testCommandCancelRunsNothingAndRemembersNothing() {
        askCommand()
        XCTAssertTrue(flow.answer(app: "acme", id: "1", .cancel))
        XCTAssertEqual(runner.runs, 0)
        XCTAssertFalse(registry.record(for: "acme")!.commandsConfirmed)
        XCTAssertEqual(changes, 0)
        XCTAssertNil(surface.shown["acme/1"])
        XCTAssertEqual(flow.pendingCount, 0)
    }

    // MARK: Template code: once / always / cancel

    func testTemplateRunOnceRunsWithoutApproving() {
        askTemplate()
        flow.answer(app: "acme", id: "1", .once)
        XCTAssertEqual(runner.runs, 1)
        XCTAssertFalse(approvals.isApproved(app: "acme", template: "ops", command: "echo one"))
        XCTAssertTrue(TemplateCommandApprovals(file: approvalsFile).all().isEmpty)
    }

    func testTemplateAlwaysAllowApprovesExactlyWhatWasListedForThatTemplate() {
        askTemplate(pressed: "echo one", others: ["echo two", "script: a.sh sha256:ff"])
        flow.answer(app: "acme", id: "1", .always)
        XCTAssertEqual(runner.runs, 1)
        let reloaded = TemplateCommandApprovals(file: approvalsFile)
        for key in ["echo one", "echo two", "script: a.sh sha256:ff"] {
            XCTAssertTrue(reloaded.isApproved(app: "acme", template: "ops", command: key), key)
        }
        XCTAssertFalse(reloaded.isApproved(app: "acme", template: "ops", command: "echo three"), "something not shown is not approved")
        XCTAssertFalse(reloaded.isApproved(app: "acme", template: "other", command: "echo one"), "approval is per template")
        XCTAssertFalse(reloaded.isApproved(app: "beta", template: "ops", command: "echo one"), "and per app")
        XCTAssertFalse(registry.record(for: "acme")!.commandsConfirmed, "a template approval is not the app's command permission")
        XCTAssertEqual(changes, 1)
    }

    func testTemplateCancelApprovesNothing() {
        askTemplate()
        flow.answer(app: "acme", id: "1", .cancel)
        XCTAssertEqual(runner.runs, 0)
        XCTAssertTrue(TemplateCommandApprovals(file: approvalsFile).all().isEmpty)
        XCTAssertEqual(changes, 0)
    }

    // MARK: Callback host: once / always / cancel

    func testCallbackSendOnceSendsWithoutApprovingTheHost() {
        askHost()
        flow.answer(app: "acme", id: "1", .once)
        XCTAssertEqual(runner.runs, 1)
        XCTAssertNil(registry.record(for: "acme")!.callbackHostApproved)
        XCTAssertNil(AppRegistry(file: appsFile).record(for: "acme")!.callbackHostApproved)
    }

    func testCallbackAlwaysAllowSendsAndApprovesTheHostOnTheAppRecord() {
        askHost("hooks.example.com")
        flow.answer(app: "acme", id: "1", .always)
        XCTAssertEqual(runner.runs, 1)
        XCTAssertEqual(registry.record(for: "acme")!.callbackHostApproved, "hooks.example.com")
        XCTAssertEqual(AppRegistry(file: appsFile).record(for: "acme")!.callbackHostApproved, "hooks.example.com")
        XCTAssertEqual(changes, 1)
    }

    func testCallbackCancelSendsNothingAndApprovesNothing() {
        askHost()
        flow.answer(app: "acme", id: "1", .cancel)
        XCTAssertEqual(runner.runs, 0)
        XCTAssertNil(registry.record(for: "acme")!.callbackHostApproved)
        XCTAssertEqual(changes, 0)
    }

    // MARK: Reminders error

    func testRemindersOKJustClearsTheRow() {
        flow.showReminderError(app: "acme", id: "1", message: "denied", canOpenSettings: true) { [runner] in runner!.openSettings() }
        XCTAssertTrue(flow.answer(app: "acme", id: "1", .ok))
        XCTAssertEqual(runner.settingsOpened, 0)
        XCTAssertNil(surface.shown["acme/1"])
    }

    func testRemindersOpenPrivacySettingsOpensThemOnce() {
        flow.showReminderError(app: "acme", id: "1", message: "denied", canOpenSettings: true) { [runner] in runner!.openSettings() }
        XCTAssertTrue(flow.answer(app: "acme", id: "1", .openSettings))
        XCTAssertEqual(runner.settingsOpened, 1)
        XCTAssertNil(surface.shown["acme/1"])
        XCTAssertFalse(flow.answer(app: "acme", id: "1", .openSettings), "answered once only")
        XCTAssertEqual(runner.settingsOpened, 1)
    }

    func testAPlainRemindersErrorDoesNotOfferPrivacySettings() {
        flow.showReminderError(app: "acme", id: "1", message: "boom", canOpenSettings: false) { [runner] in runner!.openSettings() }
        XCTAssertFalse(flow.answer(app: "acme", id: "1", .openSettings), "a choice the row did not offer is ignored")
        XCTAssertNotNil(surface.shown["acme/1"], "and the question stays")
        XCTAssertEqual(runner.settingsOpened, 0)
    }

    // MARK: Answers that must not count

    func testAnAnswerIsTakenOnce() {
        askCommand()
        XCTAssertTrue(flow.answer(app: "acme", id: "1", .once))
        XCTAssertFalse(flow.answer(app: "acme", id: "1", .once), "a double click cannot run it twice")
        XCTAssertFalse(flow.answer(app: "acme", id: "1", .always))
        XCTAssertEqual(runner.runs, 1)
        XCTAssertFalse(registry.record(for: "acme")!.commandsConfirmed)
    }

    func testAChoiceTheRowDidNotOfferIsIgnored() {
        askCommand()
        XCTAssertFalse(flow.answer(app: "acme", id: "1", .ok))
        XCTAssertFalse(flow.answer(app: "acme", id: "1", .openSettings))
        XCTAssertEqual(runner.runs, 0)
        XCTAssertNotNil(flow.confirmation(app: "acme", id: "1"), "still waiting")
    }

    func testAnAnswerWithNothingPendingIsIgnored() {
        XCTAssertFalse(flow.answer(app: "acme", id: "1", .always))
        XCTAssertFalse(registry.record(for: "acme")!.commandsConfirmed)
    }

    func testAPressBelongingToAReplacedQuestionIsIgnored() {
        askCommand("first")
        let first = surface.shown["acme/1"]!.id
        askCommand("second")
        XCTAssertFalse(flow.answer(app: "acme", id: "1", confirmation: first, .always), "the row it came from is gone")
        XCTAssertFalse(registry.record(for: "acme")!.commandsConfirmed)
        XCTAssertTrue(flow.answer(app: "acme", id: "1", confirmation: surface.shown["acme/1"]!.id, .once))
        XCTAssertEqual(runner.runs, 1, "only the question on screen ran")
    }

    // MARK: A second question, a banner that goes away

    func testAQuestionOnTheSameBannerCancelsTheEarlierOne() {
        askCommand("first")
        askCommand("second")
        XCTAssertEqual(flow.pendingCount, 1)
        XCTAssertEqual(surface.shown["acme/1"]?.command, "second")
        XCTAssertEqual(surface.presented.count, 2)
        XCTAssertEqual(runner.runs, 0, "cancelling the first ran nothing")
        flow.answer(app: "acme", id: "1", .once)
        XCTAssertEqual(runner.runs, 1)
    }

    func testQuestionsOnDifferentBannersAreIndependent() {
        surface.up.insert("acme/2")
        askCommand("first")
        flow.askCommand(app: "acme", id: "2", name: "Acme", kind: .command, text: "second") { [runner] in runner!.run() }
        XCTAssertEqual(flow.pendingCount, 2)
        flow.answer(app: "acme", id: "2", .cancel)
        XCTAssertEqual(flow.pendingCount, 1)
        XCTAssertNotNil(surface.shown["acme/1"])
        flow.answer(app: "acme", id: "1", .once)
        XCTAssertEqual(runner.runs, 1)
    }

    func testDroppingTheBannerCancelsTheQuestion() {
        askCommand()
        flow.drop(app: "acme", id: "1")
        XCTAssertEqual(runner.runs, 0)
        XCTAssertEqual(flow.pendingCount, 0)
        XCTAssertNil(surface.shown["acme/1"])
        XCTAssertFalse(flow.answer(app: "acme", id: "1", .always), "an answer after the banner went is ignored")
        XCTAssertFalse(registry.record(for: "acme")!.commandsConfirmed)
        XCTAssertEqual(changes, 0)
    }

    func testDroppingABannerWithNoQuestionIsHarmless() {
        flow.drop(app: "acme", id: "1")
        XCTAssertTrue(surface.cleared.isEmpty)
    }

    func testDropAllCancelsEveryQuestion() {
        surface.up.insert("acme/2")
        askCommand()
        flow.askCallbackHost(app: "acme", id: "2", name: "Acme", host: "h.example", url: "https://h.example/x") { [runner] in runner!.run() }
        flow.dropAll()
        XCTAssertEqual(flow.pendingCount, 0)
        XCTAssertEqual(runner.runs, 0)
        XCTAssertTrue(surface.shown.isEmpty)
    }

    func testWithNoBannerToAskOnNothingRunsAndNothingIsRemembered() {
        surface.up = []
        askCommand()
        askTemplate()
        askHost()
        XCTAssertEqual(runner.runs, 0)
        XCTAssertEqual(flow.pendingCount, 0)
        XCTAssertFalse(registry.record(for: "acme")!.commandsConfirmed)
        XCTAssertTrue(approvals.all().isEmpty)
        XCTAssertNil(registry.record(for: "acme")!.callbackHostApproved)
    }

    func testWithNoSurfaceAtAllNothingRuns() {
        flow.surface = nil
        askCommand()
        XCTAssertEqual(runner.runs, 0)
        XCTAssertEqual(flow.pendingCount, 0)
    }

    // MARK: /v1/preview

    private func decode(_ json: String) async -> (HTTPResponse, PreviewBackend) {
        let backend = PreviewBackend()
        let router = Router(token: "t", backend: backend, version: "1.2.0", pid: 1)
        let req = HTTPRequest(method: "POST", path: "/v1/preview", query: [:],
                              headers: ["authorization": "Bearer t"], body: Data(json.utf8))
        return (await router.handle(req), backend)
    }

    func testPreviewRequestCarriesAConfirmation() async {
        let (r, backend) = await decode(#"{"template":"builtin.imageLeft","app":"acme","confirmation":{"kind":"command","command":"say hi","name":"Acme"}}"#)
        XCTAssertEqual(r.status, 200)
        let c = backend.requests.first?.confirmation
        XCTAssertEqual(c?.kind, .command)
        XCTAssertEqual(c?.command, "say hi")
        XCTAssertEqual(c?.title, "Run this command for Acme?")
        XCTAssertEqual(c?.buttons.map(\.title), ["Run once", "Always allow Acme", "Cancel"])
    }

    func testPreviewConfirmationShorthandUsesTheAppNameAndKindsAreForgiving() async {
        for kind in ["callbackHost", "callback-host", "CALLBACK_HOST"] {
            let (r, backend) = await decode(#"{"app":"acme","confirmation":"\#(kind)"}"#)
            XCTAssertEqual(r.status, 200, kind)
            XCTAssertEqual(backend.requests.first?.confirmation?.kind, .callbackHost, kind)
            XCTAssertTrue(backend.requests.first?.confirmation?.title.contains("acme") ?? false, kind)
        }
        let (_, tmpl) = await decode(#"{"app":"acme","confirmation":{"kind":"templateCommand","template":"deploy","others":["echo b"],"replaces":"Approve"}}"#)
        let t = tmpl.requests.first?.confirmation
        XCTAssertEqual(t?.kind, .templateCommand)
        XCTAssertTrue(t?.title.contains("deploy") ?? false)
        XCTAssertTrue(t?.command?.contains("echo b") ?? false)
        XCTAssertTrue(t?.detail.contains("Approve") ?? false)
        let (_, rem) = await decode(#"{"app":"acme","confirmation":{"kind":"remindersDenied","message":"nope"}}"#)
        XCTAssertEqual(rem.requests.first?.confirmation?.buttons.map(\.title), ["OK", "Open Privacy Settings"])
        XCTAssertEqual(rem.requests.first?.confirmation?.detail, "nope")
    }

    func testPreviewWithoutAConfirmationHasNone() async {
        let (r, backend) = await decode(#"{"app":"acme"}"#)
        XCTAssertEqual(r.status, 200)
        XCTAssertNil(backend.requests.first?.confirmation)
    }

    func testPreviewRejectsAnUnknownOrMalformedConfirmation() async {
        for body in [#"{"app":"acme","confirmation":"nope"}"#, #"{"app":"acme","confirmation":{"command":"x"}}"#,
                     #"{"app":"acme","confirmation":5}"#, #"{"app":"acme","confirmation":{"kind":"command","command":3}}"#,
                     #"{"app":"acme","confirmation":{"kind":"templateCommand","others":"x"}}"#] {
            let (r, backend) = await decode(body)
            XCTAssertEqual(r.status, 400, body)
            XCTAssertTrue(backend.requests.isEmpty, body)
        }
    }
}
