import Foundation

/// SF Symbol names with their categories, for `GET /v1/symbols`: an agent building a template needs real names for
/// the `symbol` property. It is a view over `SymbolCatalog` (the Designer's browser reads the same catalog), so the
/// categories, Apple's order and the synonym search are the ones a person sees.
public struct SymbolListing: Sendable {
    public struct Category: Equatable, Sendable {
        public var key: String
        public var title: String
        public var icon: String
        public var count: Int
    }

    public let catalog: SymbolCatalog
    /// "all" first, then Apple's categories in the browser's order, each with its symbol count.
    public let categories: [Category]

    public init(catalog: SymbolCatalog) {
        self.catalog = catalog
        self.categories = [Category(key: "all", title: "All", icon: "square.grid.2x2", count: catalog.names.count)]
            + catalog.categories.map { Category(key: $0.key, title: $0.title, icon: $0.icon, count: catalog.names(in: $0.key).count) }
    }

    /// nil when this Mac has no symbol list.
    public static func load() -> SymbolListing? { SymbolCatalog.cached().map(SymbolListing.init) }

    public func categories(of name: String) -> [String] { catalog.categoryKeys(of: name) }

    /// Matches of `query` (every word, in the name, a search term or a synonym), optionally inside one category, paged.
    public func search(_ query: String, category: String?, limit: Int, offset: Int) -> (total: Int, names: [String]) {
        let scope = (category == nil || category == "all") ? nil : category
        let names = catalog.search(query, category: scope, limit: Int.max)
        return (names.count, Array(names.dropFirst(max(0, offset)).prefix(max(0, limit))))
    }
}
