import SwiftUI
import AppKit
import Combine
#if canImport(HeraldClient)
import HeraldClient
#endif

// The SF Symbols browser (Designer > Symbol panel). It depends on the catalog, the shortlist and `HeraldSymbol`
// only, so the package compiles it (HeraldCore) and a unit test draws it offscreen with ImageRenderer. The app
// hosts it twice: as a sheet and as a non-activating floating child panel of the Designer (SymbolBrowserHost.swift).

// MARK: - State

/// What the sidebar selects.
enum SymbolScope: Hashable {
    case all, recents, favorites
    case category(String)
}

/// What the browser shows for a scope and a search text. Pure, so it is unit tested.
struct SymbolBrowserState: Equatable {
    static let gridSizeRange: ClosedRange<Double> = 52...150
    static let defaultGridSize = 84.0

    var scope: SymbolScope = .all
    var query = ""

    static func clampedGridSize(_ v: Double) -> Double {
        v.isFinite ? min(max(v, gridSizeRange.lowerBound), gridSizeRange.upperBound) : defaultGridSize
    }

    /// The scope's symbols narrowed by the search (names, Apple's keywords and synonyms).
    func visible(catalog: SymbolCatalog, shortlist: SymbolShortlist) -> [String] {
        switch scope {
        case .all: return catalog.search(query, limit: .max)
        case .category(let key): return catalog.search(query, category: key, limit: .max)
        case .recents, .favorites:
            let base = (scope == .recents ? shortlist.recents : shortlist.favorites).filter(catalog.contains)
            guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return base }
            let hits = Set(catalog.search(query, limit: .max))
            return base.filter(hits.contains)
        }
    }
}

@MainActor
final class SymbolBrowserModel: ObservableObject {
    /// One model for the sheet and the panel, so the search, scope and selection are the same in both.
    static let shared = SymbolBrowserModel()
    static let gridSizeKey = "designerSymbolGridSize"

    let catalog: SymbolCatalog?
    let shortlist: SymbolShortlist
    private let defaults: UserDefaults

    @Published var state = SymbolBrowserState() { didSet { if state != oldValue { refresh() } } }
    @Published var selected: String?
    @Published private(set) var results: [String] = []
    /// Bumped when favourites or recents change, so the views redraw.
    @Published private(set) var shortlistVersion = 0
    @Published var gridSize: Double {
        didSet {
            let c = SymbolBrowserState.clampedGridSize(gridSize)
            if c != gridSize { gridSize = c } else { defaults.set(c, forKey: Self.gridSizeKey) }
        }
    }

    init(catalog: SymbolCatalog? = SymbolCatalog.cached(), defaults: UserDefaults = .standard) {
        self.catalog = catalog
        self.defaults = defaults
        self.shortlist = SymbolShortlist(defaults: defaults)
        let saved = defaults.object(forKey: Self.gridSizeKey) as? Double
        self.gridSize = SymbolBrowserState.clampedGridSize(saved ?? SymbolBrowserState.defaultGridSize)
        refresh()
    }

    func refresh() {
        results = catalog.map { state.visible(catalog: $0, shortlist: shortlist) } ?? []
    }

    func toggleFavorite(_ name: String) {
        shortlist.toggleFavorite(name)
        shortlistVersion += 1
        if state.scope == .favorites { refresh() }
    }

    func noteUsed(_ name: String) {
        shortlist.noteUsed(name)
        shortlistVersion += 1
        if state.scope == .recents { refresh() }
    }

    func count(in scope: SymbolScope) -> Int {
        guard let catalog else { return 0 }
        switch scope {
        case .all: return catalog.names.count
        case .category(let k): return catalog.names(in: k).count
        case .recents: return shortlist.recents.filter(catalog.contains).count
        case .favorites: return shortlist.favorites.filter(catalog.contains).count
        }
    }
}

// MARK: - Preview glyph

/// A symbol drawn with the Symbol panel's styling (weight, scale, rendering mode, colours, variable value).
/// Tokens in colours are skipped; the browser has no field values to bind them to.
struct SymbolPreviewGlyph: View {
    let name: String
    let style: HeraldSymbol
    var size: CGFloat

    static func color(_ spec: String) -> Color? {
        let t = spec.trimmingCharacters(in: .whitespaces).lowercased()
        switch t {
        case "accent": return .accentColor
        case "primary": return .primary
        case "secondary": return .secondary
        default: break
        }
        let hex = t.hasPrefix("#") ? String(t.dropFirst()) : t
        guard hex.count == 6, let v = UInt32(hex, radix: 16) else { return nil }
        return Color(red: Double((v >> 16) & 255) / 255, green: Double((v >> 8) & 255) / 255, blue: Double(v & 255) / 255)
    }

    static func weight(_ w: HeraldSymbolWeight?) -> Font.Weight {
        switch w {
        case .ultraLight?: return .ultraLight
        case .thin?: return .thin
        case .light?: return .light
        case .medium?: return .medium
        case .semibold?: return .semibold
        case .bold?: return .bold
        case .heavy?: return .heavy
        case .black?: return .black
        default: return .regular
        }
    }

    var body: some View {
        let colors = (style.colors ?? []).prefix(3).compactMap { Self.color($0) }
        let tint = colors.first ?? Color.primary
        let image = Group {
            if let raw = style.variableValue, let d = Double(raw.trimmingCharacters(in: .whitespaces)) {
                Image(systemName: name, variableValue: min(max(d > 1 && d <= 100 ? d / 100 : d, 0), 1))
            } else { Image(systemName: name) }
        }
        .font(.system(size: size, weight: Self.weight(style.weight)))
        switch style.renderingMode ?? .monochrome {
        case .monochrome: image.symbolRenderingMode(.monochrome).foregroundStyle(tint)
        case .hierarchical: image.symbolRenderingMode(.hierarchical).foregroundStyle(tint)
        case .multicolor: image.symbolRenderingMode(.multicolor)
        case .palette:
            switch colors.count {
            case 0: image.symbolRenderingMode(.palette).foregroundStyle(Color.primary, Color.primary.opacity(0.55))
            case 1: image.symbolRenderingMode(.palette).foregroundStyle(colors[0], colors[0].opacity(0.55))
            case 2: image.symbolRenderingMode(.palette).foregroundStyle(colors[0], colors[1])
            default: image.symbolRenderingMode(.palette).foregroundStyle(colors[0], colors[1], colors[2])
            }
        }
    }
}

// MARK: - View

struct SymbolBrowserView: View {
    @ObservedObject var model: SymbolBrowserModel
    /// The Symbol panel's current styling; its name is ignored (the preview draws the selection).
    var style: HeraldSymbol
    /// Applies the symbol to the component. The host decides whether the browser then closes.
    var onUse: (String) -> Void
    /// A sheet shows "Open as panel" and "Close"; the panel passes nil (its title bar closes it).
    var onClose: (() -> Void)?
    var onFloat: (() -> Void)?
    /// True for an ImageRenderer draw: AppKit-backed controls (scroll view, text field, slider) cannot be drawn.
    var offscreen = false

    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 206)
            Divider()
            VStack(spacing: 0) {
                toolbar
                Divider()
                HStack(spacing: 0) {
                    grid.frame(maxWidth: .infinity, maxHeight: .infinity)
                    Divider()
                    preview.frame(width: 250)
                }
            }
        }
        .frame(minWidth: 760, idealWidth: 940, maxWidth: .infinity, minHeight: 460, idealHeight: 640, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: Sidebar

    @ViewBuilder private func scrolling<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        let c = content()
        if offscreen {
            GeometryReader { g in c.frame(width: g.size.width, height: g.size.height, alignment: .top).clipped() }
        } else { ScrollView { c } }
    }

    private var sidebar: some View {
        scrolling {
            VStack(alignment: .leading, spacing: 1) {
                row("All symbols", icon: "square.grid.2x2", scope: .all)
                row("Recents", icon: "clock", scope: .recents)
                row("Favourites", icon: "star", scope: .favorites)
                Text("CATEGORIES").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                    .padding(.horizontal, 10).padding(.top, 12).padding(.bottom, 3)
                ForEach(model.catalog?.categories ?? []) { c in
                    row(c.title, icon: c.icon, scope: .category(c.key))
                }
                Spacer(minLength: 0)
            }
            .padding(8)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color.primary.opacity(0.04))
    }

    private func row(_ title: String, icon: String, scope: SymbolScope) -> some View {
        let on = model.state.scope == scope
        return Button { model.state.scope = scope } label: {
            HStack(spacing: 7) {
                Image(systemName: icon).frame(width: 18).foregroundStyle(on ? Color.white : Color.accentColor)
                Text(title).lineLimit(1)
                Spacer(minLength: 4)
                Text("\(model.count(in: scope))").font(.system(size: 10).monospacedDigit())
                    .foregroundStyle(on ? Color.white.opacity(0.8) : Color.secondary)
            }
            .font(.system(size: 12))
            .foregroundStyle(on ? Color.white : Color.primary)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 6).fill(on ? Color.accentColor : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Toolbar

    private var toolbar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            if offscreen {
                Text(model.state.query.isEmpty ? "Search names, keywords, synonyms (bin, mail, alert)" : model.state.query)
                    .foregroundStyle(.secondary).font(.system(size: 12)).frame(maxWidth: .infinity, alignment: .leading)
                    .padding(5).background(RoundedRectangle(cornerRadius: 5).stroke(Color.secondary.opacity(0.4)))
            } else {
                TextField("Search names, keywords, synonyms (bin, mail, alert)", text: $model.state.query)
                    .textFieldStyle(.roundedBorder)
            }
            Text("\(model.results.count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            Image(systemName: "square.grid.3x3").font(.caption).foregroundStyle(.secondary)
            if offscreen {
                Capsule().fill(Color.secondary.opacity(0.3)).frame(width: 110, height: 4)
            } else {
                Slider(value: $model.gridSize, in: SymbolBrowserState.gridSizeRange).frame(width: 110).help("Grid size")
            }
            Image(systemName: "square.grid.2x2").foregroundStyle(.secondary)
            if let onFloat {
                Button { onFloat() } label: { Image(systemName: "macwindow.on.rectangle") }
                    .help("Open as a floating panel that stays beside the Designer")
            }
            if let onClose { Button("Close") { onClose() }.keyboardShortcut(.cancelAction) }
        }
        .padding(10)
    }

    // MARK: Grid

    private var grid: some View {
        let names = offscreen ? Array(model.results.prefix(48)) : model.results
        let cell = CGFloat(model.gridSize)
        return Group {
            if model.catalog == nil {
                Text("The system symbol list was not found; type a name in the Symbol panel instead.")
                    .foregroundStyle(.secondary).padding()
            } else if names.isEmpty {
                Text(model.state.scope == .favorites ? "No favourites yet: select a symbol and press the star."
                     : model.state.scope == .recents ? "Symbols you use appear here." : "No symbols match.")
                    .foregroundStyle(.secondary).padding()
            } else {
                scrolling {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: cell, maximum: cell + 30), spacing: 6)], spacing: 6) {
                        ForEach(names, id: \.self) { n in cellView(n, width: cell) }
                    }
                    .padding(10)
                }
            }
        }
    }

    private func cellView(_ n: String, width: CGFloat) -> some View {
        let on = model.selected == n
        return VStack(spacing: 4) {
            SymbolPreviewGlyph(name: n, style: HeraldSymbol(name: n), size: max(width * 0.32, 14)).frame(height: width * 0.46)
            Text(n).font(.system(size: width < 70 ? 8 : 9.5)).lineLimit(2).multilineTextAlignment(.center)
                .truncationMode(.middle).foregroundStyle(on ? Color.white : Color.secondary)
        }
        .padding(.horizontal, 3).padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 7).fill(on ? Color.accentColor : Color.primary.opacity(0.05)))
        .overlay(alignment: .topTrailing) {
            if model.shortlist.isFavorite(n) {
                Image(systemName: "star.fill").font(.system(size: 8)).foregroundStyle(on ? Color.white : Color.yellow).padding(4)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { model.selected = n; onUse(n) }
        .onTapGesture { model.selected = n }
        .help(n)
        .contextMenu {
            Button(model.shortlist.isFavorite(n) ? "Remove from favourites" : "Add to favourites") { model.toggleFavorite(n) }
            Button("Copy name") { Self.copy(n) }
        }
    }

    static func copy(_ s: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(s, forType: .string)
    }

    // MARK: Preview

    private var preview: some View {
        VStack(spacing: 12) {
            if let n = model.selected, model.catalog?.contains(n) ?? true {
                SymbolPreviewGlyph(name: n, style: style, size: 96)
                    .frame(maxWidth: .infinity).frame(height: 150)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.05)))
                Text(n).font(.system(size: 12, design: .monospaced)).multilineTextAlignment(.center)
                    .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                let cats = (model.catalog?.categoryKeys(of: n) ?? []).compactMap { k in model.catalog?.categories.first { $0.key == k }?.title }
                if !cats.isEmpty {
                    Text(cats.prefix(4).joined(separator: " \u{00B7} ")).font(.caption).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                HStack(spacing: 8) {
                    Button { model.toggleFavorite(n) } label: {
                        Image(systemName: model.shortlist.isFavorite(n) ? "star.fill" : "star")
                    }.help(model.shortlist.isFavorite(n) ? "Remove from favourites" : "Add to favourites")
                    Button { Self.copy(n) } label: { Image(systemName: "doc.on.doc") }.help("Copy the name")
                }
                Button { onUse(n) } label: { Text("Use symbol").frame(maxWidth: .infinity) }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                Text("Drawn with the weight, mode and colours of the Symbol panel. Double-click a symbol to use it.")
                    .font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
            } else {
                Image(systemName: "square.dashed").font(.system(size: 48, weight: .ultraLight)).foregroundStyle(.tertiary)
                    .frame(height: 150)
                Text("Select a symbol to preview it with the current weight, mode and colours.")
                    .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
    }
}
