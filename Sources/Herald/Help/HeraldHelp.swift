import SwiftUI

// The tooltip modifier (issue #53). The catalog and the formatting are in HelpCatalog.swift (unit tested).

private struct HeraldHelpModifier: ViewModifier {
    let name: String, detail: String, shortcut: String?
    @ObservedObject private var settings = AppSettings.shared
    func body(content: Content) -> some View {
        content.help(HeraldHelpFormat.text(name: name, detail: detail, shortcut: shortcut, level: settings.tooltipLevel))
    }
}

extension View {
    func heraldHelp(name: String, detail: String, shortcut: String? = nil) -> some View {
        modifier(HeraldHelpModifier(name: name, detail: detail, shortcut: shortcut))
    }
    func heraldHelp(_ e: HelpEntry) -> some View { heraldHelp(name: e.name, detail: e.detail, shortcut: e.shortcut) }
}
