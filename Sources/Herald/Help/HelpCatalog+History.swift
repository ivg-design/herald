import Foundation

extension HelpEntry {
    // History controls: id, name, detail, shortcut.
    static let historySearch = HelpEntry("history.search", "Search history", "filter notifications by title, subtitle, body or app", "⌘F")
    static let historyClearSearch = HelpEntry("history.clearSearch", "Clear search", "empty the search field and show every notification")
    static let historyMore = HelpEntry("history.more", "More actions", "export the visible notifications as JSON or clear an app's history")
    static let historyKeep = HelpEntry("history.keepPerApp", "Keep per app", "how many notifications History keeps for each app; older ones are deleted")
}

extension HeraldHelpCatalog {
    static let history: [HelpEntry] = [
        .historySearch,
        .historyClearSearch,
        .historyMore,
        .historyKeep,
    ]
}
