import Foundation

extension HelpEntry {
    static let tooltipLevel = HelpEntry("settings.tooltips", "Tooltips", "how much a tooltip says: just the control's name, or its name and what it does")
}

extension HeraldHelpCatalog {
    static let settings: [HelpEntry] = [HelpEntry.tooltipLevel]
}
