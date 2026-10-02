import Foundation

/// What the History sidebar has selected: every app at once (the default) or one app.
public enum HistorySelection: Hashable, Sendable {
    case all
    case app(String)

    /// The sidebar rows are tagged with a string; this one is "All Apps".
    public static let allID = "__all__"
    public var id: String { if case .app(let a) = self { return a } else { return Self.allID } }
    public init(id: String?) { self = (id == nil || id == Self.allID) ? .all : .app(id!) }
    public var app: String? { if case .app(let a) = self { return a } else { return nil } }
}

/// The History window without the window: the selection, the search, what is listed and what a delete takes. All Apps is the default
/// and lists every app's items newest first; search spans every app; a multi-select may cross apps.
public struct HistoryBrowser: Sendable {
    public var selection: HistorySelection = .all
    public var search = ""

    public init(selection: HistorySelection = .all, search: String = "") { self.selection = selection; self.search = search }

    /// One sidebar row: "All Apps" first (with the total), then each app.
    public struct Row: Equatable, Sendable, Identifiable {
        public var selection: HistorySelection
        public var title: String
        public var total: Int
        public var unread: Int
        public var id: String { selection.id }
    }

    public func rows(history: HistoryStore, name: (String) -> String) -> [Row] {
        let counts = history.counts()
        var out = [Row(selection: .all, title: "All Apps", total: counts.values.reduce(0) { $0 + $1.total }, unread: counts.values.reduce(0) { $0 + $1.unread })]
        for app in history.apps() { out.append(Row(selection: .app(app), title: name(app), total: counts[app]?.total ?? 0, unread: counts[app]?.unread ?? 0)) }
        return out
    }

    /// The items to list, newest delivery first. `name` gives the app's display name (searched along with the text).
    public func items(history: HistoryStore, name: (String) -> String) -> [HeraldHistoryItem] {
        let base = selection.app.map { history.items(app: $0) } ?? history.allItems()
        return HistorySearch.filter(HistorySearch.scoped(base, app: selection.app), query: search, appName: name)
    }

    /// A selected app that no longer has history (or was deleted) falls back to All Apps.
    public mutating func reconcile(history: HistoryStore) {
        if let a = selection.app, !history.apps().contains(a) { selection = .all }
    }

    /// Deletes items of any mix of apps, one transaction per app.
    public static func delete(_ items: [HeraldHistoryItem], from history: HistoryStore) {
        for (app, group) in Dictionary(grouping: items, by: \.app) { history.delete(app: app, ids: Set(group.map(\.id))) }
    }
}
