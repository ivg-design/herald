import Foundation

/// One of Apple's SF Symbols categories (the sidebar of the browser).
public struct SymbolCategory: Hashable, Sendable, Codable, Identifiable {
    public let key: String
    public let title: String
    public let icon: String
    public var id: String { key }
    public init(key: String, title: String, icon: String) { self.key = key; self.title = title; self.icon = icon }
}

/// The SF Symbols available on this Mac, for the Designer's browser: names from the system's CoreGlyphs bundle
/// (`name_availability.plist`), their categories (`symbol_categories.plist` + `categories.plist`), Apple's display
/// order (`symbol_order.plist`) and search terms (`symbol_search.plist`). Reading the bundle needs no symbol API
/// and no window, so it is testable with a stand-in folder. `cached()` keeps a parsed copy in memory and on disk.
public struct SymbolCatalog: Sendable {
    public static let systemFolder = URL(fileURLWithPath: "/System/Library/CoreServices/CoreGlyphs.bundle/Contents/Resources", isDirectory: true)

    /// Names, sorted; locale and direction variants (`.ar`, `.hi`, `.rtl`...) are left out of the grid.
    public let names: [String]
    /// The sidebar's categories in Apple's order (without "all"); only those that hold symbols.
    public let categories: [SymbolCategory]
    private let terms: [String: [String]]
    private let termText: [String: String]
    private let categoryKeys: [String: [String]]
    private let lowerNames: [String]
    private let order: [String: Int]
    private let nameSet: Set<String>

    public init(names: [String], terms: [String: [String]] = [:], categories: [SymbolCategory] = [],
                categoryKeys: [String: [String]] = [:], order: [String: Int] = [:]) {
        self.names = names.sorted()
        self.nameSet = Set(names)
        self.terms = terms
        self.termText = terms.mapValues { $0.joined(separator: " ").lowercased() }
        self.categoryKeys = categoryKeys
        self.order = order
        self.lowerNames = self.names.map { $0.lowercased() }
        let used = Set(categoryKeys.values.joined())
        self.categories = categories.filter { used.contains($0.key) }
    }

    private static let variantSuffixes: Set<String> = ["ar", "hi", "he", "ja", "ko", "th", "zh", "rtl", "ltr", "el", "ru", "bn", "gu", "kn", "ml", "mr", "my", "or", "pa", "ta", "te", "ur", "km", "si", "ku", "ka", "hy", "am", "chr", "ml", "mni", "sat", "sa", "ne", "id", "vi"]

    static let titles: [String: String] = [
        "whatsnew": "What\u{2019}s New", "draw": "Draw", "variable": "Variable", "multicolor": "Multicolor",
        "communication": "Communication", "weather": "Weather", "maps": "Maps", "objectsandtools": "Objects & Tools",
        "devices": "Devices", "cameraandphotos": "Camera & Photos", "gaming": "Gaming", "connectivity": "Connectivity",
        "transportation": "Transportation", "automotive": "Automotive", "accessibility": "Accessibility",
        "privacyandsecurity": "Privacy & Security", "human": "Human", "home": "Home", "fitness": "Fitness",
        "nature": "Nature", "editing": "Editing", "textformatting": "Text Formatting", "media": "Media",
        "keyboard": "Keyboard", "commerce": "Commerce", "time": "Time", "health": "Health", "shapes": "Shapes",
        "arrows": "Arrows", "indices": "Indices", "math": "Math",
    ]

    /// nil when the folder has no symbol list.
    public static func load(from folder: URL = systemFolder) -> SymbolCatalog? {
        func plist(_ file: String) -> Any? {
            guard let d = try? Data(contentsOf: folder.appendingPathComponent(file)) else { return nil }
            return try? PropertyListSerialization.propertyList(from: d, format: nil)
        }
        guard let avail = plist("name_availability.plist") as? [String: Any],
              let symbols = avail["symbols"] as? [String: Any] else { return nil }
        let names = symbols.keys.filter { name in
            guard let last = name.split(separator: ".").last else { return false }
            return !(name.contains(".") && variantSuffixes.contains(String(last)))
        }
        let terms = (plist("symbol_search.plist") as? [String: [String]]) ?? [:]
        let keys = (plist("symbol_categories.plist") as? [String: [String]]) ?? [:]
        var order: [String: Int] = [:]
        for (i, n) in ((plist("symbol_order.plist") as? [String]) ?? []).enumerated() where order[n] == nil { order[n] = i }
        var cats: [SymbolCategory] = []
        for entry in (plist("categories.plist") as? [[String: String]]) ?? [] {
            guard let key = entry["key"], key != "all" else { continue }
            cats.append(SymbolCategory(key: key, title: titles[key] ?? key.capitalized, icon: entry["icon"] ?? "square.grid.2x2"))
        }
        return SymbolCatalog(names: Array(names), terms: terms, categories: cats, categoryKeys: keys, order: order)
    }

    // MARK: Cache

    private struct CacheFile: Codable {
        var stamp: String
        var names: [String]
        var terms: [String: [String]]
        var categories: [SymbolCategory]
        var categoryKeys: [String: [String]]
        var order: [String]
    }

    /// The folder's identity: the bundle's availability file date and the OS build, so a system update reparses.
    static func stamp(of folder: URL) -> String {
        let f = folder.appendingPathComponent("name_availability.plist")
        let date = (try? FileManager.default.attributesOfItem(atPath: f.path)[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        return "2|\(ProcessInfo.processInfo.operatingSystemVersionString)|\(date)"
    }

    public static let defaultCacheURL: URL = FileManager.default
        .urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("Herald/symbol-catalog.json")

    /// Loads the catalog from the cache file when it is current, else parses the bundle and writes the cache.
    public static func load(from folder: URL = systemFolder, cache: URL) -> SymbolCatalog? {
        let stamp = stamp(of: folder)
        if let d = try? Data(contentsOf: cache), let c = try? JSONDecoder().decode(CacheFile.self, from: d), c.stamp == stamp {
            var order: [String: Int] = [:]
            for (i, n) in c.order.enumerated() { order[n] = i }
            return SymbolCatalog(names: c.names, terms: c.terms, categories: c.categories, categoryKeys: c.categoryKeys, order: order)
        }
        guard let fresh = load(from: folder) else { return nil }
        let file = CacheFile(stamp: stamp, names: fresh.names, terms: fresh.terms, categories: fresh.categories,
                             categoryKeys: fresh.categoryKeys, order: fresh.order.sorted { $0.value < $1.value }.map(\.key))
        try? FileManager.default.createDirectory(at: cache.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let d = try? JSONEncoder().encode(file) { try? d.write(to: cache, options: .atomic) }
        return fresh
    }

    private final class Shared: @unchecked Sendable {
        let lock = NSLock()
        var loaded = false
        var value: SymbolCatalog?
    }
    private static let shared = Shared()

    /// The system catalog, parsed once per process (and once per system version on disk).
    public static func cached() -> SymbolCatalog? {
        shared.lock.lock(); defer { shared.lock.unlock() }
        if !shared.loaded { shared.value = load(from: systemFolder, cache: defaultCacheURL); shared.loaded = true }
        return shared.value
    }

    // MARK: Browsing

    /// Names in Apple's order (symbols the order file does not list keep their given order, last).
    public func ordered(_ list: [String]) -> [String] {
        guard !order.isEmpty else { return list }
        return list.enumerated().sorted { a, b in
            let x = order[a.element] ?? Int.max, y = order[b.element] ?? Int.max
            return x != y ? x < y : a.offset < b.offset
        }.map(\.element)
    }

    public func categoryKeys(of name: String) -> [String] { categoryKeys[name] ?? [] }

    /// Names of a category (alphabetical), or all of them.
    public func names(in category: String?) -> [String] {
        guard let category else { return names }
        return names.filter { categoryKeys[$0]?.contains(category) ?? false }
    }

    /// Words a user may type that Apple's own search terms miss: everyday names for what a symbol shows.
    static let synonyms: [String: [String]] = [
        "bin": ["trash"], "garbage": ["trash"], "rubbish": ["trash"], "delete": ["trash"], "recycle": ["trash"],
        "cog": ["gear"], "settings": ["gear"], "preferences": ["gear"], "options": ["gear", "slider"],
        "tick": ["checkmark"], "check": ["checkmark"], "done": ["checkmark"], "ok": ["checkmark"],
        "cross": ["xmark"], "close": ["xmark"], "cancel": ["xmark"], "remove": ["minus", "xmark"],
        "email": ["envelope"], "mail": ["envelope"], "letter": ["envelope"], "inbox": ["tray"],
        "home": ["house"], "like": ["heart", "hand.thumbsup"], "love": ["heart"], "favorite": ["star", "heart"],
        "favourite": ["star", "heart"], "picture": ["photo"], "image": ["photo"], "search": ["magnifyingglass"],
        "find": ["magnifyingglass"], "zoom": ["magnifyingglass"], "magnifier": ["magnifyingglass"],
        "alert": ["bell", "exclamationmark"], "notification": ["bell"], "warning": ["exclamationmark.triangle"],
        "info": ["info.circle"], "help": ["questionmark"], "user": ["person"], "profile": ["person"],
        "people": ["person.2"], "chat": ["message", "bubble"], "comment": ["bubble"], "call": ["phone"],
        "password": ["key", "lock"], "share": ["square.and.arrow.up"],
        "download": ["arrow.down.circle", "square.and.arrow.down"], "upload": ["arrow.up.circle", "square.and.arrow.up"],
        "refresh": ["arrow.clockwise"], "reload": ["arrow.clockwise"], "sync": ["arrow.triangle.2.circlepath"],
        "back": ["chevron.left", "arrow.left"], "forward": ["chevron.right", "arrow.right"], "next": ["chevron.right"],
        "edit": ["pencil"], "write": ["pencil"], "copy": ["doc.on.doc"], "paste": ["doc.on.clipboard"],
        "save": ["square.and.arrow.down", "tray.and.arrow.down"], "volume": ["speaker"], "sound": ["speaker"],
        "mute": ["speaker.slash"], "microphone": ["mic"], "internet": ["globe", "network"], "web": ["globe"],
        "attachment": ["paperclip"], "file": ["doc"], "document": ["doc"], "money": ["dollarsign", "banknote"],
        "buy": ["cart"], "shop": ["cart", "bag"], "price": ["tag"], "label": ["tag"], "location": ["location", "mappin"],
        "plane": ["airplane"], "flight": ["airplane"], "fire": ["flame"], "idea": ["lightbulb"], "light": ["lightbulb"],
        "movie": ["film"], "game": ["gamecontroller"], "ai": ["sparkles"], "magic": ["wand.and.stars", "sparkles"],
        "add": ["plus"], "bug": ["ladybug", "ant"], "time": ["clock"],
    ]

    /// Names matching every word of `query` in the name, in a search term, or through a synonym; name matches
    /// first (prefix, then contains), then term matches, each group in Apple's order. An empty query lists the
    /// whole scope. `category` narrows the scope; `limit` caps the result.
    public func search(_ query: String, category: String? = nil, limit: Int = 300) -> [String] {
        let words = query.lowercased().split(whereSeparator: { $0 == " " || $0 == "." }).map(String.init)
        var starts: [String] = [], contains: [String] = [], viaTerms: [String] = []
        for (i, n) in names.enumerated() {
            if let category, !(categoryKeys[n]?.contains(category) ?? false) { continue }
            if words.isEmpty { starts.append(n); continue }
            let lower = lowerNames[i]
            if words.allSatisfy({ lower.contains($0) }) {
                if lower.hasPrefix(words[0]) { starts.append(n) } else { contains.append(n) }
                continue
            }
            let t = termText[n] ?? ""
            let hit = words.allSatisfy { w in
                if lower.contains(w) || t.contains(w) { return true }
                return (Self.synonyms[w] ?? []).contains { lower.contains($0) || t.contains($0) }
            }
            if hit { viaTerms.append(n) }
        }
        let all = ordered(starts) + ordered(contains) + ordered(viaTerms)
        return limit >= all.count ? all : Array(all.prefix(limit))
    }

    public func contains(_ name: String) -> Bool { nameSet.contains(name) }
}

/// The picker's recent and favourite symbols, remembered in UserDefaults.
public struct SymbolShortlist {
    public static let recentsKey = "designerSymbolRecents"
    public static let favoritesKey = "designerSymbolFavorites"
    public static let maxRecents = 40

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
