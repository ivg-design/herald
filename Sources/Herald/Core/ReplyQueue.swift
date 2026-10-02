import Foundation
import HeraldClient

/// The answers users typed into banners (the inline Reply), kept per app until an agent reads them. MCP agents have no
/// callback server, so they ask a question with `send_notification`, then read the answer with `get_replies` or wait for it
/// with `wait_for_reply` (docs/MCP.md, "Ask the user a question"). The reply is also on the notification's history record
/// (`reply`, `repliedAt`), which outlives the queue: reading with `consume` empties the queue, not History.
///
/// Persisted in one small JSON file so a reply survives a restart of Herald; at most `capPerApp` replies are kept per app,
/// the oldest dropped first.
public final class ReplyQueue: @unchecked Sendable {
    public static let capPerApp = 200
    public static let maxTextBytes = 4000

    private let lock = NSLock()
    private let file: URL?
    private var items: [HeraldReplyRecord] = []

    /// `file` nil keeps the queue in memory (tests, previews).
    public init(file: URL? = nil) {
        self.file = file
        if let file, let data = try? Data(contentsOf: file),
           let loaded = try? HeraldJSON.decoder().decode([HeraldReplyRecord].self, from: data) {
            items = loaded
        }
    }

    /// The reply text as stored: trimmed and cut at `maxTextBytes`. nil when nothing is left.
    public static func clean(_ text: String) -> String? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        if t.utf8.count <= maxTextBytes { return t }
        var out = ""
        for ch in t { if (out + String(ch)).utf8.count > maxTextBytes { break }; out.append(ch) }
        return out
    }

    /// Adds a reply; one for the same notification replaces the earlier one.
    public func add(_ record: HeraldReplyRecord) {
        lock.lock(); defer { lock.unlock() }
        items.removeAll { $0.notificationId == record.notificationId && $0.app == record.app }
        items.append(record)
        let mine = items.filter { $0.app == record.app }
        if mine.count > Self.capPerApp {
            let drop = Set(mine.sorted { $0.repliedAt < $1.repliedAt }.prefix(mine.count - Self.capPerApp).map(\.id))
            items.removeAll { drop.contains($0.id) }
        }
        save()
    }

    /// The queued replies, oldest first: for `app` (nil: every app), newer than `since`. With `consume` they leave the queue.
    @discardableResult
    public func list(app: String? = nil, since: Date? = nil, consume: Bool = false) -> [HeraldReplyRecord] {
        lock.lock(); defer { lock.unlock() }
        let out = items.filter { (app == nil || $0.app == app) && (since == nil || $0.repliedAt > since!) }
            .sorted { $0.repliedAt < $1.repliedAt }
        if consume, !out.isEmpty {
            let gone = Set(out.map(\.id))
            items.removeAll { gone.contains($0.id) }
            save()
        }
        return out
    }

    /// The queued reply to one notification. `app` nil matches any app.
    public func reply(to notificationId: String, app: String? = nil, consume: Bool = false) -> HeraldReplyRecord? {
        lock.lock(); defer { lock.unlock() }
        guard let i = items.firstIndex(where: { $0.notificationId == notificationId && (app == nil || $0.app == app) }) else { return nil }
        let r = items[i]
        if consume { items.remove(at: i); save() }
        return r
    }

    public var count: Int { lock.lock(); defer { lock.unlock() }; return items.count }

    private func save() {
        guard let file, let data = try? HeraldJSON.encoder().encode(items) else { return }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
    }
}

/// What happens to a reply the user sent from a banner, apart from the banner itself: the text goes onto the notification's
/// History record (`reply`, `repliedAt`) and into the app's reply queue. Kept here, not in the controller, so it is tested
/// without a window.
public enum ReplyRecorder {
    /// The record that was stored; nil when the text is empty or the notification is not in History.
    @discardableResult
    public static func record(app: String, id: String, text: String, history: HistoryStore, queue: ReplyQueue,
                              now: Date = Date()) -> HeraldReplyRecord? {
        guard let clean = ReplyQueue.clean(text), let item = history.item(app: app, id: id) else { return nil }
        _ = history.update(app: app, id: id) { $0.reply = clean; $0.repliedAt = now }
        let record = HeraldReplyRecord(notificationId: id, app: app, text: clean, repliedAt: now, title: item.notification.title)
        queue.add(record)
        return record
    }
}
