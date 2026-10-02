import Foundation

/// The SF Symbols available on this Mac, for the Designer's picker: names from the system's CoreGlyphs bundle
/// (`name_availability.plist`) with their search terms (`symbol_search.plist`). Reading the bundle needs no
/// symbol API and no window, so it is testable with a stand-in folder.
public struct SymbolCatalog: Sendable {
    public static let systemFolder = URL(fileURLWithPath: "/System/Library/CoreServices/CoreGlyphs.bundle/Contents/Resources", isDirectory: true)

    /// Names, sorted; locale and direction variants (`.ar`, `.hi`, `.rtl`...) are left out of the grid.
    public let names: [String]
    private let terms: [String: [String]]

    public init(names: [String], terms: [String: [String]] = [:]) {
        self.names = names.sorted()
        self.terms = terms
    }

    private static let variantSuffixes: Set<String> = ["ar", "hi", "he", "ja", "ko", "th", "zh", "rtl", "ltr", "el", "ru", "bn", "gu", "kn", "ml", "mr", "my", "or", "pa", "ta", "te", "ur", "km", "si", "ku", "ka", "hy", "am", "chr", "ml", "mni", "sat", "sa", "ne", "id", "vi"]

    /// nil when the folder has no symbol list.
    public static func load(from folder: URL = systemFolder) -> SymbolCatalog? {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent("name_availability.plist")),
              let plist = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any],
              let symbols = plist["symbols"] as? [String: Any] else { return nil }
        let names = symbols.keys.filter { name in
            guard let last = name.split(separator: ".").last else { return false }
            return !(name.contains(".") && variantSuffixes.contains(String(last)))
        }
        var terms: [String: [String]] = [:]
        if let sdata = try? Data(contentsOf: folder.appendingPathComponent("symbol_search.plist")),
           let search = (try? PropertyListSerialization.propertyList(from: sdata, format: nil)) as? [String: [String]] {
            terms = search
        }
        return SymbolCatalog(names: Array(names), terms: terms)
    }

    /// Names matching every word of `query` in the name or in a search term; name matches first (prefix, then
    /// contains), alphabetical within a group. An empty query returns the first `limit` names.
    public func search(_ query: String, limit: Int = 300) -> [String] {
        let words = query.lowercased().split(whereSeparator: { $0 == " " || $0 == "." }).map(String.init)
        guard !words.isEmpty else { return Array(names.prefix(limit)) }
        var starts: [String] = [], contains: [String] = [], viaTerms: [String] = []
        for n in names {
            let lower = n.lowercased()
            if words.allSatisfy({ lower.contains($0) }) {
                if lower.hasPrefix(words[0]) { starts.append(n) } else { contains.append(n) }
            } else if let t = terms[n]?.map({ $0.lowercased() }),
                      words.allSatisfy({ w in lower.contains(w) || t.contains { $0.contains(w) } }) {
                viaTerms.append(n)
            }
            if starts.count + contains.count + viaTerms.count >= limit * 3 { break }
        }
        return Array((starts + contains + viaTerms).prefix(limit))
    }

    public func contains(_ name: String) -> Bool { names.contains(name) }
}

/// The picker's recent and favourite symbols, remembered in UserDefaults.
public struct SymbolShortlist {
    public static let recentsKey = "designerSymbolRecents"
    public static let favoritesKey = "designerSymbolFavorites"
    public static let maxRecents = 16

    private let defaults: UserDefaults
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    public var recents: [String] { defaults.stringArray(forKey: Self.recentsKey) ?? [] }
    public var favorites: [String] { defaults.stringArray(forKey: Self.favoritesKey) ?? [] }

    public func noteUsed(_ name: String) {
        guard !name.isEmpty, !name.contains("{") else { return }
        var r = recents.filter { $0 != name }
        r.insert(name, at: 0)
        defaults.set(Array(r.prefix(Self.maxRecents)), forKey: Self.recentsKey)
    }

    public func toggleFavorite(_ name: String) {
        var f = favorites
        if let i = f.firstIndex(of: name) { f.remove(at: i) } else { f.append(name) }
        defaults.set(f, forKey: Self.favoritesKey)
    }

    public func isFavorite(_ name: String) -> Bool { favorites.contains(name) }
}
