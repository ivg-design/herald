import XCTest
import Foundation
@testable import HeraldClient
@testable import HeraldCore

// Add to Reminders (issue #23). The EventKit half cannot run in `swift test` (it needs the app's TCC identity), so it
// was checked by hand on a Developer ID signed, hardened-runtime copy of the app with its own bundle id:
//  1. First press: the system prompt "would like to access your Reminders" appears (UserNotificationCenter window)
//     and the entitlement com.apple.security.personal-information.calendars is present in the signature.
//  2. After Allow: the banner shows "Added to Reminders" and an "Open Reminders" button, and
//     `tell application "Reminders" to get {name, due date, body} of (first reminder whose name contains ...)` returns the
//     title from reminder.title, the due date from reminder.due, and notes = body + url.
//  3. Denied or restricted: ReminderError.denied / .restricted show an alert with "Open Privacy Settings" (code path
//     only; macOS shows the prompt once per bundle id, so it cannot be repeated without a new id).
// What a unit test can pin down is how the notification is turned into the reminder.

final class ReminderDraftTests: XCTestCase {
    private func note(title: String = "Bid accepted", body: String? = nil, url: String? = nil) -> HeraldNotification {
        HeraldNotification(app: "bidbot", title: title, body: body, url: url)
    }

    func testTitleDefaultsToTheNotificationTitle() {
        for blank in [nil, "", "   \n"] {
            let d = ReminderDraft(notification: note(), reminder: HeraldReminder(title: blank, due: nil))
            XCTAssertEqual(d.title, "Bid accepted", "title \(String(describing: blank))")
        }
        XCTAssertEqual(ReminderDraft(notification: note(), reminder: HeraldReminder(title: "  Follow up on Acme ", due: nil)).title,
                       "Follow up on Acme")
    }

    func testNotesAreTheBodyAsPlainTextThenTheUrl() {
        let d = ReminderDraft(notification: note(body: "Your bid of $4,200 was accepted. [Open proposal](https://acme.example/p/42)",
                                                 url: "https://acme.example/bids/42"),
                              reminder: HeraldReminder())
        XCTAssertEqual(d.notes, "Your bid of $4,200 was accepted. Open proposal\n\nhttps://acme.example/bids/42")
        XCTAssertEqual(d.url, URL(string: "https://acme.example/bids/42"))
    }

    func testNotesWithOnlyOneOfBodyAndUrlAndWithNeither() {
        XCTAssertEqual(ReminderDraft(notification: note(body: "Just a body"), reminder: HeraldReminder()).notes, "Just a body")
        XCTAssertEqual(ReminderDraft(notification: note(url: "https://x.example"), reminder: HeraldReminder()).notes, "https://x.example")
        XCTAssertNil(ReminderDraft(notification: note(), reminder: HeraldReminder()).notes)
        XCTAssertNil(ReminderDraft(notification: note(body: "  \n "), reminder: HeraldReminder()).notes)
    }

    func testDueIsReadAsISO8601WithItsOffset() throws {
        let d = ReminderDraft(notification: note(), reminder: HeraldReminder(title: nil, due: "2030-01-02T09:00:00-05:00"))
        XCTAssertEqual(d.due, ISODate.parse("2030-01-02T14:00:00Z"))
        // A bad date is no due date, never a crash or a reminder due "now".
        XCTAssertNil(ReminderDraft(notification: note(), reminder: HeraldReminder(title: nil, due: "next tuesday")).due)
        XCTAssertNil(ReminderDraft(notification: note(), reminder: HeraldReminder()).due)
    }

    func testAnUnparsableUrlIsDroppedFromTheReminderButKeptInTheNotes() {
        let d = ReminderDraft(notification: note(url: "http://[not-an-address"), reminder: HeraldReminder())
        XCTAssertNil(d.url)
        XCTAssertEqual(d.notes, "http://[not-an-address")
    }
}
