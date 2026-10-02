import Foundation

extension HelpEntry {
    // History controls: id, name, detail, shortcut.
    static let historySearch = HelpEntry("history.search", "Search history", "Narrows History to notifications whose title, subtitle, body or app match the text", "⌘F")
    static let historyClearSearch = HelpEntry("history.clearSearch", "Clear search", "Empties the search so every notification shows again")
    static let historyMore = HelpEntry("history.more", "More actions", "Export of the visible notifications as JSON, or clearing one app's history")
    static let historyKeep = HelpEntry("history.keepPerApp", "Keep per app", "How many notifications History keeps for each app; older ones are deleted")
}

extension HeraldHelpCatalog {
    static let history: [HelpEntry] = [
        .historySearch,
        .historyClearSearch,
        .historyMore,
        .historyKeep,
    ]
}
