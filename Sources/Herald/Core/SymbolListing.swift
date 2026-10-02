import Foundation

/// SF Symbol names with their categories, for `GET /v1/symbols`: an agent building a template needs real names for
/// the `symbol` property. Names and search terms come from `SymbolCatalog`; the categories from the system's
/// `categories.plist` (the category keys and icons) and `symbol_categories.plist` (symbol to category keys), both
/// in the same CoreGlyphs bundle. A missing plist only means fewer categories.
public struct SymbolListing: Sendable {
    public struct Category: Equatable, Sendable {
        public var key: String
        public var icon: String
        public var count: Int
    }

    public let catalog: SymbolCatalog
    public let categories: [Category]
    private let byName: [String: [String]]

    public init(catalog: SymbolCatalog, categoryKeys: [(key: String, icon: String)] = [], symbolCategories: [String: [String]] = [:]) {
        self.catalog = catalog
        self.byName = symbolCategories
        var counts: [String: Int] = [:]
        for n in catalog.names { for k in symbolCategories[n] ?? [] { counts[k, default: 0] += 1 } }
        self.categories = categoryKeys.map { Category(key: $0.key, icon: $0.icon, count: $0.key == "all" ? catalog.names.count : counts[$0.key, default: 0]) }
    }

    /// nil when the folder has no symbol list.
    public static func load(from folder: URL = SymbolCatalog.systemFolder) -> SymbolListing? {
        guard let catalog = SymbolCatalog.load(from: folder) else { return nil }
        var keys: [(String, String)] = []
        if let data = try? Data(contentsOf: folder.appendingPathComponent("categories.plist")),
           let list = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [[String: Any]] {
            keys = list.compactMap { d in (d["key"] as? String).map { ($0, d["icon"] as? String ?? "") } }
        }
        var map: [String: [String]] = [:]
        if let data = try? Data(contentsOf: folder.appendingPathComponent("symbol_categories.plist")),
           let m = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: [String]] { map = m }
        return SymbolListing(catalog: catalog, categoryKeys: keys, symbolCategories: map)
    }

    public func categories(of name: String) -> [String] { byName[name] ?? [] }

    /// Matches of `query` (every word, in the name or a search term), optionally inside one category, paged.
    public func search(_ query: String, category: String?, limit: Int, offset: Int) -> (total: Int, names: [String]) {
        var names = query.trimmingCharacters(in: .whitespaces).isEmpty ? catalog.names : catalog.search(query, limit: catalog.names.count)
        if let category, category != "all" { names = names.filter { byName[$0]?.contains(category) ?? false } }
        let page = names.dropFirst(max(0, offset)).prefix(max(0, limit))
        return (names.count, Array(page))
    }
}
