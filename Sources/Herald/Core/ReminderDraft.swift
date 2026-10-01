import Foundation

/// Everything a reminder is made of, already reduced to plain values.
struct ReminderDraft: Equatable {
    var title: String
    var notes: String?
    var url: URL?
    var due: Date?

    /// Title from `reminder.title` (else the notification title), notes from the notification body as plain
    /// text with the link kept as a line of its own, `url` from the notification url, due from `reminder.due`.
    init(notification n: HeraldNotification, reminder: HeraldReminder) {
        let title = reminder.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.title = title.isEmpty ? n.title : title
        self.url = n.url.flatMap { URL(string: $0) }
        self.due = reminder.due.flatMap { ISODate.parse($0) }
        let body = n.body.map(Self.plainText)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = [body, n.url].compactMap { $0 }.filter { !$0.isEmpty }
        self.notes = parts.isEmpty ? nil : parts.joined(separator: "\n\n")
    }

    init(title: String, notes: String? = nil, url: URL? = nil, due: Date? = nil) {
        self.title = title; self.notes = notes; self.url = url; self.due = due
    }

    /// Markdown (`[text](url)`) flattened to what a reader sees.
    static func plainText(_ markdown: String) -> String {
        let opts = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: markdown, options: opts)).map { String($0.characters) } ?? markdown
    }
}
