import XCTest
@testable import HeraldCore

/// The composer's payload logic: what the form means on the wire, relative to a saved template.
@MainActor
final class ComposerModelTests: XCTestCase {
    private func template() -> HeraldTemplate {
        var t = HeraldTemplate(name: "bid-won", app: "bidbot", layout: .hero)
        t.accentColor = "#34C759"
        t.maxBodyLines = 3
        t.title = "{customer} accepted"
        t.body = "Bid of {amount} won."
        t.url = "https://example.com/bids/{id}"
        t.buttons = [HeraldButton(label: "Open", url: "https://example.com")]
        t.sound = "Glass"
        t.snooze = true
        return t
    }

    private func model(app: String = "bidbot") -> ComposerModel { ComposerModel(app: app) }

    // MARK: No template

    func testPlainFormSendsOnlyWhatWasSet() {
        let m = model()
        m.title = "Hello"
        let p = m.payload
        XCTAssertEqual(p, HeraldNotification(app: "bidbot", title: "Hello"))
        XCTAssertEqual(m.resolved, p)
        XCTAssertTrue(m.issues.isEmpty)
    }

    func testChangedLookAndBehaviourBecomePayloadFields() {
        let m = model()
        m.title = "Hello"; m.subtitle = "Sub"; m.body = "Body"; m.clickURL = " https://x.test "; m.notificationID = "n-1"
        m.layout = .compact; m.accentColor = "#FF0000"; m.showTimestamp = false; m.maxBodyLines = 2
        m.soundSelection = "Ping"; m.persistent = false; m.timeoutText = "15"; m.snooze = true; m.priority = "high"
        m.reminderOn = true; m.reminderTitle = "Follow up"
        let p = m.payload
        XCTAssertEqual(p.id, "n-1"); XCTAssertEqual(p.subtitle, "Sub"); XCTAssertEqual(p.body, "Body")
        XCTAssertEqual(p.url, "https://x.test")
        XCTAssertEqual(p.layout, .compact); XCTAssertEqual(p.accentColor, "#FF0000")
        XCTAssertEqual(p.showTimestamp, false); XCTAssertNil(p.showSubtitle); XCTAssertEqual(p.maxBodyLines, 2)
        XCTAssertEqual(p.sound, "Ping"); XCTAssertEqual(p.persistent, false); XCTAssertEqual(p.timeout, 15)
        XCTAssertEqual(p.snooze, true); XCTAssertEqual(p.priority, "high")
        XCTAssertEqual(p.reminder, HeraldReminder(title: "Follow up", due: nil))
        XCTAssertNil(p.template)
    }

    func testTokensTypedIntoTheFormAreExpandedFromMetadata() {
        let m = model()
        m.title = "{n} new bids"
        m.metadata = [MetadataRow(key: "n", value: "3"), MetadataRow(key: "  ", value: "ignored")]
        XCTAssertEqual(m.payload.title, "3 new bids")
        XCTAssertEqual(m.payload.metadata, .object(["n": .string("3")]))
    }

    func testIssues() {
        let m = model(app: " ")
        XCTAssertEqual(m.issues.count, 2)
        m.app = "a"; m.title = "t"
        XCTAssertTrue(m.issues.isEmpty)
        m.timeoutText = "soon"
        XCTAssertEqual(m.issues, ["Auto-dismiss must be a number of seconds."])
        m.timeoutText = "-5"
        XCTAssertEqual(m.issues.count, 1)
        m.timeoutText = ""
        var b = ComposerButton(); b.label = "Go"; b.action = .callback; b.payload = "{not json"
        m.buttons = [b]
        XCTAssertEqual(m.issues.count, 1)
        m.buttons[0].payload = "{\"ok\":1}"
        XCTAssertTrue(m.issues.isEmpty)
    }

    func testButtonRowsBuildWireButtons() {
        var url = ComposerButton(); url.label = " Open "; url.value = "https://x"
        var cmd = ComposerButton(); cmd.label = "Run"; cmd.action = .command; cmd.value = "do it"; cmd.style = .destructive
        var cb = ComposerButton(); cb.label = "Done"; cb.action = .callback; cb.payload = "{\"id\":7}"; cb.value = "http://127.0.0.1:9/h"
        var blank = ComposerButton(); blank.label = "  "
        let m = model(); m.title = "t"; m.buttons = [url, cmd, cb, blank]
        XCTAssertEqual(m.payload.buttons, [
            HeraldButton(label: "Open", url: "https://x"),
            HeraldButton(label: "Run", style: "destructive", command: "do it"),
            HeraldButton(label: "Done", callback: HeraldCallback(url: "http://127.0.0.1:9/h", payload: .object(["id": .number(7)]))),
        ])
        // Rows survive a trip through a template.
        let again = m.draftTemplate(named: "x").buttons.map(ComposerButton.init).compactMap { $0.build() }
        XCTAssertEqual(again, m.payload.buttons)
    }

    func testSoundSelection() {
        let m = model(); m.title = "t"
        m.soundSelection = "none"; XCTAssertEqual(m.payload.sound, "none")
        m.soundSelection = ComposerModel.customSoundTag; m.customSoundPath = "/tmp/a.aiff"
        XCTAssertEqual(m.payload.sound, "/tmp/a.aiff")
        m.customSoundPath = ""; XCTAssertNil(m.payload.sound)
        XCTAssertEqual(ComposerModel.soundFields("~/x.wav").selection, ComposerModel.customSoundTag)
        XCTAssertEqual(ComposerModel.soundFields("Glass").selection, "Glass")
        XCTAssertEqual(ComposerModel.soundFields(nil).selection, "")
    }

    func testReminderDueIsLocalISOAndParsesBack() {
        let m = model(); m.title = "t"
        m.reminderOn = true; m.reminderHasDue = true
        m.reminderDue = ISODate.parse("2026-10-02T09:00:00-04:00")!
        let due = try! XCTUnwrap(m.payload.reminder?.due)
        XCTAssertNotNil(ISODate.parse(due))
        XCTAssertEqual(ISODate.parse(due), m.reminderDue)
        XCTAssertEqual(ComposerModel.localISO(m.reminderDue, timeZone: TimeZone(secondsFromGMT: -4 * 3600)!), "2026-10-02T09:00:00-04:00")
    }

    // MARK: With a template

    func testUntouchedTemplateStaysATemplateReference() {
        let m = model()
        m.applyTemplate(template())
        m.metadata = [MetadataRow(key: "customer", value: "Acme"), MetadataRow(key: "amount", value: "$4,200"),
                      MetadataRow(key: "id", value: "42")]
        let p = m.payload
        XCTAssertEqual(p.template, "bid-won")
        XCTAssertEqual(p.title, "")          // inherited, so the resolver fills and expands it
        XCTAssertNil(p.body); XCTAssertNil(p.url); XCTAssertNil(p.buttons); XCTAssertNil(p.sound)
        XCTAssertNil(p.layout); XCTAssertNil(p.accentColor); XCTAssertNil(p.maxBodyLines); XCTAssertNil(p.snooze)
        let r = m.resolved
        XCTAssertEqual(r.title, "Acme accepted")
        XCTAssertEqual(r.body, "Bid of $4,200 won.")
        XCTAssertEqual(r.url, "https://example.com/bids/42")
        XCTAssertEqual(r.layout, .hero); XCTAssertEqual(r.accentColor, "#34C759"); XCTAssertEqual(r.maxBodyLines, 3)
        XCTAssertEqual(r.buttons, template().buttons); XCTAssertEqual(r.sound, "Glass"); XCTAssertEqual(r.snooze, true)
        XCTAssertTrue(m.issues.isEmpty)
    }

    func testEditedTemplateFieldsOverride() {
        let m = model()
        m.applyTemplate(template())
        m.metadata = [MetadataRow(key: "customer", value: "Acme")]
        m.title = "Custom for {customer}"
        m.layout = .compact
        m.buttons = []
        let p = m.payload
        XCTAssertEqual(p.title, "Custom for Acme")
        XCTAssertEqual(p.layout, .compact)
        XCTAssertEqual(p.buttons, [])                        // deliberate "no buttons" wins over the template
        XCTAssertEqual(m.resolved.buttons, [])
        XCTAssertEqual(m.resolved.layout, .compact)
        XCTAssertEqual(m.resolved.accentColor, "#34C759")     // untouched look still comes from the template
    }

    func testClearedTemplateTextStaysCleared() {
        let m = model()
        m.applyTemplate(template())
        m.body = ""
        XCTAssertEqual(m.payload.body, "")
        XCTAssertEqual(m.resolved.body, "")
        m.snooze = false
        XCTAssertEqual(m.payload.snooze, false)
        XCTAssertEqual(m.resolved.snooze, false)
    }

    func testDetachingTheTemplateKeepsTheValues() {
        let m = model()
        m.applyTemplate(template())
        m.applyTemplate(nil)
        XCTAssertNil(m.template)
        XCTAssertNil(m.payload.template)
        XCTAssertEqual(m.title, "{customer} accepted")           // the form keeps the text as typed...
        XCTAssertEqual(m.payload.title, " accepted")             // ...and the payload expands it (unknown token becomes empty)
        XCTAssertEqual(m.payload.layout, .hero)                  // now a plain override of the default look
    }

    func testDraftTemplateKeepsPlaceholdersAndLook() {
        let m = model()
        m.title = "{customer} accepted"; m.body = "Bid {amount}"
        m.layout = .imageRight; m.accentColor = "#112233"; m.showBody = false; m.maxBodyLines = 5
        m.snooze = true; m.soundSelection = "Hero"; m.timeoutText = "20"; m.persistent = false
        m.metadata = [MetadataRow(key: "customer", value: "Acme")]
        let t = m.draftTemplate(named: "won")
        XCTAssertEqual(t.name, "won"); XCTAssertEqual(t.app, "bidbot")
        XCTAssertEqual(t.title, "{customer} accepted"); XCTAssertEqual(t.body, "Bid {amount}")
        XCTAssertNil(t.subtitle)
        XCTAssertEqual(t.layout, .imageRight); XCTAssertEqual(t.accentColor, "#112233")
        XCTAssertEqual(t.showBody, false); XCTAssertEqual(t.maxBodyLines, 5)
        XCTAssertEqual(t.snooze, true); XCTAssertEqual(t.sound, "Hero"); XCTAssertEqual(t.timeout, 20); XCTAssertEqual(t.persistent, false)
        // Metadata is sample data, not part of the template.
        let data = try! HeraldJSON.encoder().encode(t)
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("Acme"))
        // Re-applying it as the baseline sends nothing extra.
        m.applyTemplate(t)
        XCTAssertEqual(m.payload.title, "")
        XCTAssertNil(m.payload.layout)
        XCTAssertEqual(m.resolved.title, "Acme accepted")
    }

    func testClearResetsEverythingButTheApp() {
        let m = model()
        m.applyTemplate(template()); m.notificationID = "x"; m.metadata = [MetadataRow(key: "a", value: "b")]
        m.clear()
        XCTAssertEqual(m.app, "bidbot"); XCTAssertNil(m.template)
        XCTAssertEqual(m.payload, HeraldNotification(app: "bidbot", title: ""))
    }
}
