import Foundation

// Tooltips on every control in Herald's own windows (issue #53). One modifier, `.heraldHelp(...)`, one catalog
// (`HeraldHelpCatalog`, filled per area in `HelpCatalog+*.swift`), one Settings > General choice for how much to say.

enum TooltipLevel: String, CaseIterable, Identifiable {
    case nameOnly, nameAndDescription
    var id: String { rawValue }
    var title: String { self == .nameOnly ? "Name only" : "Name and description" }
    static let defaultLevel: TooltipLevel = .nameAndDescription
}

/// One control: "Merge cells", "join the selected cells into one slot", "\u{2318}E".
struct HelpEntry: Equatable {
    let id: String
    let name: String
    let detail: String
    let shortcut: String?
    init(_ id: String, _ name: String, _ detail: String, _ shortcut: String? = nil) {
        self.id = id; self.name = name; self.detail = detail; self.shortcut = shortcut
    }
}

enum HeraldHelpFormat {
    /// Name only: "Merge cells". Full: "Merge cells \u{2014} join the selected cells into one slot \u{00B7} \u{2318}E".
    static func text(name: String, detail: String, shortcut: String?, level: TooltipLevel) -> String {
        guard level == .nameAndDescription else { return name }
        var s = detail.isEmpty ? name : "\(name) \u{2014} \(detail)"
        if let shortcut, !shortcut.isEmpty { s += " \u{00B7} \(shortcut)" }
        return s
    }
    static func text(_ e: HelpEntry, level: TooltipLevel) -> String {
        text(name: e.name, detail: e.detail, shortcut: e.shortcut, level: level)
    }
}

enum HeraldHelpCatalog {
    /// Every entry of every area; the catalog test walks this.
    static var all: [HelpEntry] { designer + authoring + history + settings + palette }
    static func entry(_ id: String) -> HelpEntry? { all.first { $0.id == id } }
}


/// "Herald 1.4.1 (Build 8)", shown at the bottom right of Settings > General.
enum HeraldVersionLabel {
    static func text(version: String?, build: String?) -> String {
        let v = (version ?? "").trimmingCharacters(in: .whitespaces), b = (build ?? "").trimmingCharacters(in: .whitespaces)
        switch (v.isEmpty, b.isEmpty) {
        case (true, true): return "Herald"
        case (false, true): return "Herald \(v)"
        case (true, false): return "Herald (Build \(b))"
        case (false, false): return "Herald \(v) (Build \(b))"
        }
    }
    static var current: String {
        let info = Bundle.main.infoDictionary
        return text(version: info?["CFBundleShortVersionString"] as? String, build: info?["CFBundleVersion"] as? String)
    }
}
