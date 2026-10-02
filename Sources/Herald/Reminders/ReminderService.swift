import AppKit
import EventKit
import Foundation

enum ReminderError: LocalizedError {
    case denied, restricted, noCalendar
    case saveFailed(String)

    var errorDescription: String? {
        switch self {
        case .denied:
            return "Herald does not have access to Reminders. Allow it in System Settings > Privacy & Security > Reminders."
        case .restricted:
            return "Access to Reminders is restricted on this Mac (for example by a profile), so Herald cannot add reminders."
        case .noCalendar:
            return "There is no Reminders list to add to. Open Reminders and create a list first."
        case .saveFailed(let why):
            return "Reminders could not save the reminder: \(why)"
        }
    }
}

/// Adds reminders through EventKit. Permission is requested lazily, on the first "Add to Reminders" press.
@MainActor
final class ReminderService {
    private let store = EKEventStore()

    /// The Reminders app, for the "Open Reminders" button that follows a successful add.
    static var remindersAppURL: URL {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.reminders")
            ?? URL(fileURLWithPath: "/System/Applications/Reminders.app")
    }

    static let privacySettingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders")!

    static func openRemindersApp() { NSWorkspace.shared.open(remindersAppURL) }
    static func openPrivacySettings() { NSWorkspace.shared.open(privacySettingsURL) }

    /// Creates the reminder in the user's default Reminders list.
    func add(_ draft: ReminderDraft) async throws {
        try await ensureAccess()
        guard let calendar = store.defaultCalendarForNewReminders()
                ?? store.calendars(for: .reminder).first(where: { $0.allowsContentModifications })
        else { throw ReminderError.noCalendar }

        let r = EKReminder(eventStore: store)
        r.title = draft.title
        r.notes = draft.notes
        r.url = draft.url
        r.calendar = calendar
        if let due = draft.due {
            let cal = Calendar.current
            let c = cal.dateComponents([.year, .month, .day, .hour, .minute], from: due)
            r.dueDateComponents = DateComponents(calendar: cal, timeZone: cal.timeZone, year: c.year, month: c.month,
                                                 day: c.day, hour: c.hour, minute: c.minute)
            // An alarm in the past never fires; the reminder is simply overdue, which is the honest state.
            if due > Date() { r.addAlarm(EKAlarm(absoluteDate: due)) }
        }
        do { try store.save(r, commit: true) }
        catch { throw ReminderError.saveFailed(error.localizedDescription) }
    }

    func add(title: String, notes: String?, due: Date?) async throws {
        try await add(ReminderDraft(title: title, notes: notes, url: nil, due: due))
    }

    /// macOS 14 split calendar access into full and write-only and renamed the reminders call; macOS 13 has
    /// the older one. A denial is reported without asking again, since macOS would not show the prompt anyway.
    private func ensureAccess() async throws {
        let status = EKEventStore.authorizationStatus(for: .reminder)
        switch status {
        case .restricted: throw ReminderError.restricted
        case .denied: throw ReminderError.denied
        default: break
        }
        if hasFullAccess(status) { return }
        // No NSApp.activate here (DESIGN 8): this runs from a banner button or the HTTP API, and activating Herald
        // would take the keyboard from the app the user is typing in. The one-time Reminders permission prompt is
        // a system (tccd) dialog, which macOS puts in front on its own.
        let granted: Bool
        if #available(macOS 14.0, *) {
            granted = try await store.requestFullAccessToReminders()
        } else {
            granted = try await store.requestAccess(to: .reminder)
        }
        guard granted else { throw ReminderError.denied }
    }

    private func hasFullAccess(_ status: EKAuthorizationStatus) -> Bool {
        if #available(macOS 14.0, *) { return status == .fullAccess }
        return status == .authorized
    }
}
