import Foundation
import Combine
#if canImport(HeraldClient)
import HeraldClient
#endif

// The Designer's model (DESIGN 7.4). Everything in this file is Foundation + HeraldClient only, so the
// grid editing rules (merge, split, move, resize, drop) and the action-rule editing can be unit tested
// without AppKit. The SwiftUI views (GridCanvasView, PaletteView, InspectorView, ActionEditorView,
// DesignerWindow) only call into `DesignerModel`.

// MARK: - Slots

/// One position of the grid.
struct GridSlot: Hashable, Comparable {
    var row: Int
    var col: Int
    init(_ row: Int, _ col: Int) { self.row = row; self.col = col }
    static func < (a: GridSlot, b: GridSlot) -> Bool { (a.row, a.col) < (b.row, b.col) }
}

/// A rectangle of slots: a cell's area, or the user's selection.
struct SlotRect: Hashable {
    var row: Int
    var col: Int
    var rowSpan: Int
    var colSpan: Int

    init(row: Int, col: Int, rowSpan: Int = 1, colSpan: Int = 1) {
        self.row = row; self.col = col; self.rowSpan = rowSpan; self.colSpan = colSpan
    }
    init(_ s: GridSlot) { self.init(row: s.row, col: s.col) }

    var origin: GridSlot { GridSlot(row, col) }
    var area: Int { max(rowSpan, 0) * max(colSpan, 0) }
    var lastRow: Int { row + rowSpan - 1 }
    var lastCol: Int { col + colSpan - 1 }

    func contains(_ s: GridSlot) -> Bool { s.row >= row && s.row <= lastRow && s.col >= col && s.col <= lastCol }
    func contains(_ r: SlotRect) -> Bool { r.row >= row && r.col >= col && r.lastRow <= lastRow && r.lastCol <= lastCol }
    func intersects(_ r: SlotRect) -> Bool {
        row <= r.lastRow && r.row <= lastRow && col <= r.lastCol && r.col <= lastCol
    }
    func union(_ r: SlotRect) -> SlotRect {
        let r0 = min(row, r.row), c0 = min(col, r.col)
        return SlotRect(row: r0, col: c0, rowSpan: max(lastRow, r.lastRow) - r0 + 1, colSpan: max(lastCol, r.lastCol) - c0 + 1)
    }
    var slots: [GridSlot] {
        guard rowSpan > 0, colSpan > 0 else { return [] }
        return (row...lastRow).flatMap { r in (col...lastCol).map { GridSlot(r, $0) } }
    }
    static func bounding(_ a: GridSlot, _ b: GridSlot) -> SlotRect {
        SlotRect(row: min(a.row, b.row), col: min(a.col, b.col),
                 rowSpan: abs(a.row - b.row) + 1, colSpan: abs(a.col - b.col) + 1)
    }
}

// MARK: - Drag payloads

/// What a drag carries. Dragged as a plain string (`herald-designer:<kind>:<value>`) so it needs no
/// registered type; anything else dropped on the canvas is ignored.
enum DragPayload: Equatable {
    /// A component type from the palette ("text", "image", ...).
    case component(String)
    /// A field token from the palette ("sender", "extra.queue").
    case field(String)
    /// A resolved action id from the palette (becomes a button).
    case action(String)
    /// A cell already on the canvas.
    case cell(String)
    /// An animation file of the issuer from the Assets panel (its id: the file name without `.riv`).
    case rive(String)

    static let prefix = "herald-designer:"

    var string: String {
        switch self {
        case .component(let v): return Self.prefix + "component:" + v
        case .field(let v): return Self.prefix + "field:" + v
        case .action(let v): return Self.prefix + "action:" + v
        case .cell(let v): return Self.prefix + "cell:" + v
        case .rive(let v): return Self.prefix + "rive:" + v
        }
    }

    init?(string: String) {
        guard string.hasPrefix(Self.prefix) else { return nil }
        let rest = string.dropFirst(Self.prefix.count)
        guard let colon = rest.firstIndex(of: ":") else { return nil }
        let kind = String(rest[rest.startIndex..<colon]), value = String(rest[rest.index(after: colon)...])
        guard !value.isEmpty else { return nil }
        switch kind {
        case "component": self = .component(value)
        case "field": self = .field(value)
        case "action": self = .action(value)
        case "cell": self = .cell(value)
        case "rive": self = .rive(value)
        default: return nil
        }
    }
}

// MARK: - Grid editing rules

/// Pure editing of a v2 template's grid. Every function works on a template and reports what happened; none
/// of them touches UI state.
enum GridEditing {
    enum RemoveOutcome: Equatable { case removed, replacedWithSpacer, notFound }

    // MARK: Queries

    /// The area a cell covers, clipped to the grid; nil when it lies outside it.
    static func rect(of cell: HeraldCell, in grid: HeraldGrid) -> SlotRect? {
        let rr = cell.rowRange(in: grid.rows), cr = cell.colRange(in: grid.cols)
        guard !rr.isEmpty, !cr.isEmpty else { return nil }
        return SlotRect(row: rr.lowerBound, col: cr.lowerBound, rowSpan: rr.count, colSpan: cr.count)
    }

    static func rect(ofCell id: String, in t: HeraldTemplate) -> SlotRect? {
        guard let g = t.grid, let c = t.cell(withID: id) else { return nil }
        return rect(of: c, in: g)
    }

    static func inBounds(_ r: SlotRect, in g: HeraldGrid) -> Bool {
        r.row >= 0 && r.col >= 0 && r.rowSpan >= 1 && r.colSpan >= 1 && r.row + r.rowSpan <= g.rows && r.col + r.colSpan <= g.cols
    }

    /// The cell covering `slot` (the first one, should a hand-written template overlap).
    static func cell(at slot: GridSlot, in t: HeraldTemplate) -> HeraldCell? {
        guard let g = t.grid else { return nil }
        return t.cells.first { rect(of: $0, in: g)?.contains(slot) == true }
    }

    /// True when `r` fits the grid and no cell other than `excluding` touches it.
    static func isFree(_ r: SlotRect, in t: HeraldTemplate, excluding: Set<String> = []) -> Bool {
        guard let g = t.grid, inBounds(r, in: g) else { return false }
        return !t.cells.contains { c in
            guard !excluding.contains(c.id), let cr = rect(of: c, in: g) else { return false }
            return cr.intersects(r)
        }
    }

    static func newCellID(in t: HeraldTemplate) -> String {
        let used = Set(t.cells.map(\.id))
        var n = 1
        while used.contains("c\(n)") { n += 1 }
        return "c\(n)"
    }

    /// Where a new component of this kind sits in its cell unless the user says otherwise.
    static func defaultAlign(for c: HeraldComponent) -> HeraldAlign {
        switch c {
        case .text, .image, .timestamp, .actions: return .topLeading
        case .issuerIcon, .button, .iconButton, .badge, .progress, .rive, .spacer: return .center
        }
    }

    static func isSpacer(_ c: HeraldComponent) -> Bool { if case .spacer = c { return true }; return false }

    /// Reading order, so the saved cell list reads like the banner.
    static func sortReading(_ t: inout HeraldTemplate) {
        guard let g = t.grid else { return }
        t.cells = t.cells.enumerated().sorted { a, b in
            let ra = rect(of: a.element, in: g)?.origin ?? GridSlot(a.element.row, a.element.col)
            let rb = rect(of: b.element, in: g)?.origin ?? GridSlot(b.element.row, b.element.col)
            return ra == rb ? a.offset < b.offset : ra < rb
        }.map(\.element)
    }

    // MARK: Cells

    /// Puts `component` in the cell at `slot`: replaces the component of the cell already there (keeping its
    /// area and alignment) or creates a 1 x 1 cell. Returns the cell id.
    @discardableResult
    static func place(_ component: HeraldComponent, at slot: GridSlot, in t: inout HeraldTemplate) -> String? {
        guard let g = t.grid, inBounds(SlotRect(slot), in: g) else { return nil }
        if let o = cell(at: slot, in: t), let i = t.cells.firstIndex(where: { $0.id == o.id }) {
            t.cells[i].component = component
            return o.id
        }
        let id = newCellID(in: t)
        t.cells.append(HeraldCell(id: id, row: slot.row, col: slot.col, align: defaultAlign(for: component), component: component))
        sortReading(&t)
        return id
    }

    /// Moves a cell so its top-left corner is at `slot`. Dropped on another cell the two swap components;
    /// dropped on free slots the cell keeps its span, reduced where it would run off the grid or overlap.
    @discardableResult
    static func move(cell id: String, to slot: GridSlot, in t: inout HeraldTemplate) -> Bool {
        guard let g = t.grid, let src = t.cell(withID: id), let srcRect = rect(of: src, in: g),
              inBounds(SlotRect(slot), in: g) else { return false }
        if let occupant = cell(at: slot, in: t) {
            guard occupant.id != id, let a = t.cells.firstIndex(where: { $0.id == id }),
                  let b = t.cells.firstIndex(where: { $0.id == occupant.id }) else { return false }
            let tmp = t.cells[a].component
            t.cells[a].component = t.cells[b].component
            t.cells[b].component = tmp
            return true
        }
        var rs = min(srcRect.rowSpan, g.rows - slot.row), cs = min(srcRect.colSpan, g.cols - slot.col)
        while !isFree(SlotRect(row: slot.row, col: slot.col, rowSpan: rs, colSpan: cs), in: t, excluding: [id]), rs > 1 || cs > 1 {
            if rs >= cs && rs > 1 { rs -= 1 } else if cs > 1 { cs -= 1 } else { rs -= 1 }
        }
        guard let i = t.cells.firstIndex(where: { $0.id == id }) else { return false }
        t.cells[i].row = slot.row; t.cells[i].col = slot.col; t.cells[i].rowSpan = rs; t.cells[i].colSpan = cs
        sortReading(&t)
        return true
    }

    /// Sets a cell's span, reduced to the largest free area not exceeding the request. Returns the span that
    /// was applied.
    @discardableResult
    static func resize(cell id: String, rowSpan: Int, colSpan: Int, in t: inout HeraldTemplate) -> (rowSpan: Int, colSpan: Int)? {
        guard let g = t.grid, let c = t.cell(withID: id), let r = rect(of: c, in: g),
              let i = t.cells.firstIndex(where: { $0.id == id }) else { return nil }
        let wantRows = max(1, min(rowSpan, g.rows - r.row)), wantCols = max(1, min(colSpan, g.cols - r.col))
        var best = (rows: 1, cols: 1)
        for rs in stride(from: wantRows, through: 1, by: -1) {
            for cs in stride(from: wantCols, through: 1, by: -1)
            where isFree(SlotRect(row: r.row, col: r.col, rowSpan: rs, colSpan: cs), in: t, excluding: [id]) {
                if rs * cs > best.rows * best.cols { best = (rs, cs) }
            }
        }
        t.cells[i].rowSpan = best.rows; t.cells[i].colSpan = best.cols
        return (best.rows, best.cols)
    }

    /// The selection grown until it holds whole cells only (a cell cut by the selection joins it).
    static func expanded(_ r: SlotRect, in t: HeraldTemplate) -> SlotRect {
        guard let g = t.grid else { return r }
        var cur = SlotRect(row: max(r.row, 0), col: max(r.col, 0),
                           rowSpan: max(1, min(r.rowSpan, g.rows - max(r.row, 0))),
                           colSpan: max(1, min(r.colSpan, g.cols - max(r.col, 0))))
        var changed = true
        while changed {
            changed = false
            for c in t.cells {
                guard let cr = rect(of: c, in: g), cr.intersects(cur), !cur.contains(cr) else { continue }
                cur = cur.union(cr); changed = true
            }
        }
        return cur
    }

    static func canMerge(_ r: SlotRect, in t: HeraldTemplate) -> Bool { expanded(r, in: t).area >= 2 }

    /// Joins every slot of the selection into one cell. The first real component in reading order survives;
    /// the others are dropped. A selection holding no component becomes a spacer cell, so the merge is kept
    /// (drop a component on it to fill it). Returns the id of the merged cell.
    @discardableResult
    static func merge(_ r: SlotRect, in t: inout HeraldTemplate) -> String? {
        guard let g = t.grid else { return nil }
        let area = expanded(r, in: t)
        guard area.area >= 2, inBounds(area, in: g) else { return nil }
        let covered = t.cells.filter { c in rect(of: c, in: g).map { area.contains($0) } == true }
            .sorted { (rect(of: $0, in: g)!.origin) < (rect(of: $1, in: g)!.origin) }
        let survivor = covered.first { !isSpacer($0.component) } ?? covered.first
        let keepID = survivor?.id ?? newCellID(in: t)
        t.cells.removeAll { c in c.id != keepID && covered.contains { $0.id == c.id } }
        if let i = t.cells.firstIndex(where: { $0.id == keepID }) {
            t.cells[i].row = area.row; t.cells[i].col = area.col
            t.cells[i].rowSpan = area.rowSpan; t.cells[i].colSpan = area.colSpan
        } else {
            t.cells.append(HeraldCell(id: keepID, row: area.row, col: area.col, rowSpan: area.rowSpan,
                                      colSpan: area.colSpan, align: .center, component: .spacer))
        }
        sortReading(&t)
        return keepID
    }

    /// Cuts a merged cell back to one slot (its top-left). The component stays; the other slots are empty
    /// again. A spacer placeholder simply disappears.
    @discardableResult
    static func split(cell id: String, in t: inout HeraldTemplate) -> Bool {
        guard let g = t.grid, let c = t.cell(withID: id), let r = rect(of: c, in: g), r.area > 1,
              let i = t.cells.firstIndex(where: { $0.id == id }) else { return false }
        if isSpacer(c.component) { t.cells.remove(at: i); return true }
        t.cells[i].rowSpan = 1; t.cells[i].colSpan = 1
        return true
    }

    /// Delete on a cell: a merged cell keeps its area as a spacer (delete again to clear it), a one-slot
    /// cell is removed.
    @discardableResult
    static func remove(cell id: String, in t: inout HeraldTemplate) -> RemoveOutcome {
        guard let g = t.grid, let i = t.cells.firstIndex(where: { $0.id == id }) else { return .notFound }
        let area = rect(of: t.cells[i], in: g)?.area ?? 1
        if area > 1, !isSpacer(t.cells[i].component) {
            t.cells[i].component = .spacer
            return .replacedWithSpacer
        }
        t.cells.remove(at: i)
        return .removed
    }

    /// Copies a cell into the first free area of the same size after it (wrapping around), else a single
    /// free slot, else a new row at the bottom. nil when the grid is full and cannot grow.
    @discardableResult
    static func duplicate(cell id: String, in t: inout HeraldTemplate) -> String? {
        guard let g = t.grid, let src = t.cell(withID: id), let r = rect(of: src, in: g) else { return nil }
        let order = (0..<(g.rows * g.cols)).map { GridSlot($0 / max(g.cols, 1), $0 % max(g.cols, 1)) }
        let start = order.firstIndex(of: r.origin) ?? 0
        let rotated = Array(order[(start + 1)...]) + Array(order[..<(start + 1)])
        var target: SlotRect?
        for s in rotated {
            let candidate = SlotRect(row: s.row, col: s.col, rowSpan: r.rowSpan, colSpan: r.colSpan)
            if isFree(candidate, in: t) { target = candidate; break }
        }
        if target == nil, let s = rotated.first(where: { isFree(SlotRect($0), in: t) }) { target = SlotRect(s) }
        if target == nil {
            guard insertRow(at: g.rows, in: &t) else { return nil }
            target = SlotRect(row: g.rows, col: r.col)
        }
        guard let place = target else { return nil }
        var copy = src
        copy.id = newCellID(in: t)
        copy.row = place.row; copy.col = place.col; copy.rowSpan = place.rowSpan; copy.colSpan = place.colSpan
        t.cells.append(copy)
        sortReading(&t)
        return copy.id
    }

    // MARK: Tracks

    /// Pads or trims the size lists to the row and column counts (a hand-written template may disagree).
    static func fixSizes(_ g: inout HeraldGrid) {
        while g.rowSizes.count < g.rows { g.rowSizes.append(.auto) }
        if g.rowSizes.count > g.rows { g.rowSizes.removeLast(g.rowSizes.count - g.rows) }
        while g.colSizes.count < g.cols { g.colSizes.append(.fill) }
        if g.colSizes.count > g.cols { g.colSizes.removeLast(g.colSizes.count - g.cols) }
    }

    /// Inserts an empty row before `index` (`rows` appends). Cells below move down; a cell spanning the
    /// insertion point grows by one row.
    @discardableResult
    static func insertRow(at index: Int, size: HeraldSize = .auto, in t: inout HeraldTemplate) -> Bool {
        guard var g = t.grid, g.rows < HeraldTemplate.maxGridTracks, (0...g.rows).contains(index) else { return false }
        fixSizes(&g)
        g.rowSizes.insert(size, at: index); g.rows += 1
        t.grid = g
        for i in t.cells.indices {
            if t.cells[i].row >= index { t.cells[i].row += 1 }
            else if t.cells[i].row + t.cells[i].rowSpan > index { t.cells[i].rowSpan += 1 }
        }
        return true
    }

    @discardableResult
    static func insertColumn(at index: Int, size: HeraldSize = .fill, in t: inout HeraldTemplate) -> Bool {
        guard var g = t.grid, g.cols < HeraldTemplate.maxGridTracks, (0...g.cols).contains(index) else { return false }
        fixSizes(&g)
        g.colSizes.insert(size, at: index); g.cols += 1
        t.grid = g
        for i in t.cells.indices {
            if t.cells[i].col >= index { t.cells[i].col += 1 }
            else if t.cells[i].col + t.cells[i].colSpan > index { t.cells[i].colSpan += 1 }
        }
        return true
    }

    /// Removes a row. Cells only in it go; a cell spanning it shrinks; cells below move up.
    @discardableResult
    static func removeRow(at index: Int, in t: inout HeraldTemplate) -> Bool {
        guard var g = t.grid, g.rows > 1, (0..<g.rows).contains(index) else { return false }
        fixSizes(&g)
        g.rowSizes.remove(at: index); g.rows -= 1
        t.grid = g
        var kept: [HeraldCell] = []
        for var c in t.cells {
            if c.row > index { c.row -= 1 }
            else if c.row + c.rowSpan > index {
                if c.rowSpan == 1 { continue }
                c.rowSpan -= 1
            }
            kept.append(c)
        }
        t.cells = kept
        return true
    }

    @discardableResult
    static func removeColumn(at index: Int, in t: inout HeraldTemplate) -> Bool {
        guard var g = t.grid, g.cols > 1, (0..<g.cols).contains(index) else { return false }
        fixSizes(&g)
        g.colSizes.remove(at: index); g.cols -= 1
        t.grid = g
        var kept: [HeraldCell] = []
        for var c in t.cells {
            if c.col > index { c.col -= 1 }
            else if c.col + c.colSpan > index {
                if c.colSpan == 1 { continue }
                c.colSpan -= 1
            }
            kept.append(c)
        }
        t.cells = kept
        return true
    }
}

// MARK: - Track sizes

extension GridEditing {
    /// Smallest fixed track the canvas handles produce.
    static let minTrackPoints = 8.0

    /// A dragged size made usable: whole points, at least `minTrackPoints`, and no wider than the banner (a
    /// column) or 800 pt (a row).
    static func clampedPoints(_ v: Double, columns: Bool, in g: HeraldGrid) -> Double {
        guard v.isFinite else { return minTrackPoints }
        let hi = columns ? max(g.width, minTrackPoints) : 800.0
        return min(max(v.rounded(), minTrackPoints), hi)
    }

    /// Gives column or row `index` a size. A fixed size is clamped (`clampedPoints`). False when there is no such track.
    @discardableResult
    static func setTrack(columns: Bool, index: Int, size: HeraldSize, in t: inout HeraldTemplate) -> Bool {
        guard var g = t.grid, index >= 0, index < (columns ? g.cols : g.rows) else { return false }
        fixSizes(&g)
        var s = size
        if case .points(let p) = s { s = .points(clampedPoints(p, columns: columns, in: g)) }
        if columns { g.colSizes[index] = s } else { g.rowSizes[index] = s }
        t.grid = g
        return true
    }
}

// MARK: - Palette content

struct PaletteComponent: Identifiable, Equatable {
    var type: String
    var title: String
    var symbol: String
    var id: String { type }
}

/// One token the user can bind: a manifest field, a standard payload key, a custom key or a template `extra`.
struct TokenSuggestion: Identifiable, Equatable {
    enum Group: String { case issuer = "Issuer fields", standard = "Standard", seen = "Seen in notifications", extra = "Extra (yours)", custom = "Custom" }
    var key: String
    var type: HeraldFieldType?
    var group: Group
    var sample: String?
    var id: String { key }
    var token: String { "{\(key)}" }
}

enum DesignerPalette {
    static let components: [PaletteComponent] = [
        .init(type: "text", title: "Text", symbol: "textformat"),
        .init(type: "image", title: "Image", symbol: "photo"),
        .init(type: "issuerIcon", title: "App icon", symbol: "app.badge"),
        .init(type: "timestamp", title: "Time", symbol: "clock"),
        .init(type: "button", title: "Button", symbol: "capsule"),
        .init(type: "actions", title: "Actions", symbol: "rectangle.split.3x1"),
        .init(type: "iconButton", title: "Icon btn", symbol: "xmark.circle"),
        .init(type: "badge", title: "Badge", symbol: "number.circle"),
        .init(type: "progress", title: "Progress", symbol: "slider.horizontal.3"),
        .init(type: "rive", title: "Rive", symbol: "play.rectangle"),
        .init(type: "spacer", title: "Spacer", symbol: "rectangle.dashed"),
    ]

    static func symbol(for type: String) -> String { components.first { $0.type == type }?.symbol ?? "square" }
    static func title(for type: String) -> String { components.first { $0.type == type }?.title ?? type }

    /// Tokens every notification can carry; the key tells what kind of data it is.
    static let standardTypes: [(key: String, type: HeraldFieldType)] = [
        ("title", .text), ("subtitle", .text), ("body", .text), ("image", .image), ("url", .url),
        ("appName", .text), ("deliveredAt", .date),
    ]

    /// A fresh component of `type`, pre-filled from what the issuer offers.
    static func makeComponent(type: String, manifest: HeraldManifest?, actions: [HeraldResolvedAction]) -> HeraldComponent {
        switch type {
        case "text": return .text(HeraldTextComponent(binding: "{title}", style: .title))
        case "image": return .image(HeraldImageComponent(binding: "{image}", fit: .cover, cornerRadius: 8, aspectRatio: 1))
        case "issuerIcon": return .issuerIcon(HeraldIssuerIconComponent(size: 28))
        case "timestamp": return .timestamp(HeraldTimestampComponent(relative: true))
        case "button":
            if let first = actions.first { return .button(HeraldButtonComponent(actionRef: first.id)) }
            return .button(HeraldButtonComponent(action: HeraldAction(id: "open", label: "Open", kind: .url, url: "{url}")))
        case "actions": return .actions(HeraldActionsComponent(source: .merged, layout: .wrap))
        case "iconButton":
            return .iconButton(HeraldIconButtonComponent(symbol: "xmark", action: HeraldAction(id: "dismiss", label: "Dismiss", kind: .dismiss, style: "cancel"), tooltip: "Dismiss"))
        case "badge":
            let key = manifest?.fields.first { $0.type == .number }?.key ?? "count"
            return .badge(HeraldBadgeComponent(binding: "{\(key)}"))
        case "progress":
            let key = manifest?.fields.first { $0.type == .number && $0.key != "count" }?.key ?? "progress"
            return .progress(HeraldProgressComponent(binding: "{\(key)}"))
        case "rive":
            let asset = manifest?.assets.first { $0.type.lowercased() == "rive" }
            return .rive(HeraldRiveComponent(asset: asset?.id, stateMachine: asset?.stateMachine, aspectRatio: 1))
        default: return .spacer
        }
    }

    /// The component a dragged field becomes on an empty slot.
    static func component(forField key: String, type: HeraldFieldType?) -> HeraldComponent {
        let binding = "{\(key)}"
        let kind = type ?? standardTypes.first { $0.key == key }?.type ?? .text
        switch kind {
        case .image: return .image(HeraldImageComponent(binding: binding, fit: .cover, cornerRadius: 8, aspectRatio: 1))
        case .date: return .timestamp(HeraldTimestampComponent(binding: binding, relative: true))
        case .number: return .badge(HeraldBadgeComponent(binding: binding))
        case .url: return .text(HeraldTextComponent(binding: binding, style: .caption))
        case .text, .bool, .list:
            switch key {
            case "title": return .text(HeraldTextComponent(binding: binding, style: .title, maxLines: 2))
            case "subtitle": return .text(HeraldTextComponent(binding: binding, style: .subtitle, maxLines: 2))
            default: return .text(HeraldTextComponent(binding: binding, style: .body, maxLines: 4))
            }
        }
    }

    /// `existing` with the token `key` added: a blank text or a lone token is replaced, anything longer gets
    /// the token appended after a space (and keeps it only once).
    static func binding(_ existing: String, adding key: String) -> String {
        let token = "{\(key)}"
        let trimmed = existing.trimmingCharacters(in: .whitespacesAndNewlines)
        let tokens = TemplateResolver.placeholders(in: trimmed)
        if existing.contains(token) { return existing }
        if trimmed.isEmpty || (tokens.count == 1 && trimmed == "{\(tokens[0])}") { return token }
        return existing + " " + token
    }

    /// Binds a token into an existing component. A text component whose binding is blank or a lone token
    /// takes the new token in its place; one that already mixes text appends it. Components that bind a
    /// single value (image, time, badge, progress) are re-pointed. nil when the component takes no binding.
    static func bind(token key: String, into component: HeraldComponent) -> HeraldComponent? {
        let token = "{\(key)}"
        switch component {
        case .text(var p):
            p.binding = binding(p.binding, adding: key)
            return .text(p)
        case .image(var p): p.binding = token; return .image(p)
        case .timestamp(var p): p.binding = token; return .timestamp(p)
        case .badge(var p): p.binding = token; return .badge(p)
        case .progress(var p): p.binding = token; return .progress(p)
        default: return nil
        }
    }
}

// MARK: - Action rules

/// A row of the designer's action list: an issuer action (maybe changed by a rule, maybe hidden by one) or
/// an action the user added.
struct DesignerActionRow: Identifiable, Equatable {
    var action: HeraldAction
    /// The issuer's own version; nil for an action the user added.
    var base: HeraldAction?
    var origin: HeraldActionOrigin
    var hidden: Bool
    var id: String { action.id }
    var isRelabeled: Bool { base.map { $0.label != action.label } ?? false }
    var isRestyled: Bool { base.map { ($0.style ?? "default") != (action.style ?? "default") } ?? false }
}

/// Editing of `HeraldTemplate.actionRules`. The designer owns two kinds of rule and leaves every other rule
/// (written by hand or by an agent) alone:
/// - one "override" rule per issuer action: `{match:<id>, hide|relabel|style}`;
/// - the "order" rules `{match:<id>, position:<i>}` at the end of the list, which together fix the order.
enum ActionRules {
    static func same(_ a: String?, _ b: String) -> Bool { a?.caseInsensitiveCompare(b) == .orderedSame }

    static func isOrderRule(_ r: HeraldActionRule) -> Bool {
        r.match != nil && r.position != nil && r.hide == nil && r.relabel == nil && r.style == nil && r.add == nil
    }

    static func isOverride(_ r: HeraldActionRule, for id: String) -> Bool {
        r.add == nil && r.position == nil && same(r.match, id)
    }

    private static func isEmptyOverride(_ r: HeraldActionRule) -> Bool {
        r.hide != true && (r.relabel ?? "").isEmpty && (r.style ?? "").isEmpty
    }

    /// Index to insert a new rule at: before the trailing order rules.
    private static func insertionIndex(_ rules: [HeraldActionRule]) -> Int {
        var i = rules.count
        while i > 0, isOrderRule(rules[i - 1]) { i -= 1 }
        return i
    }

    /// Edits (creating or removing as needed) the override rule of issuer action `id`.
    static func override(_ id: String, in rules: inout [HeraldActionRule], _ body: (inout HeraldActionRule) -> Void) {
        if let i = rules.firstIndex(where: { isOverride($0, for: id) }) {
            var r = rules[i]; body(&r)
            if r.hide == false { r.hide = nil }
            if r.relabel?.isEmpty == true { r.relabel = nil }
            if r.style?.isEmpty == true { r.style = nil }
            if isEmptyOverride(r) { rules.remove(at: i) } else { rules[i] = r }
        } else {
            var r = HeraldActionRule(match: id); body(&r)
            if r.hide == false { r.hide = nil }
            if r.relabel?.isEmpty == true { r.relabel = nil }
            if r.style?.isEmpty == true { r.style = nil }
            if !isEmptyOverride(r) { rules.insert(r, at: insertionIndex(rules)) }
        }
    }

    /// Drops every override of issuer action `id` (back to what the issuer sent).
    static func reset(_ id: String, in rules: inout [HeraldActionRule]) {
        rules.removeAll { isOverride($0, for: id) }
    }

    /// Adds (or replaces, by id) an action of the user's own.
    static func addAction(_ a: HeraldAction, in rules: inout [HeraldActionRule]) {
        if let i = rules.firstIndex(where: { $0.add?.id == a.id }) { rules[i].add = a; return }
        rules.insert(HeraldActionRule(add: a), at: insertionIndex(rules))
    }

    /// Replaces the action `oldID` (and renames it everywhere the rules mention it).
    static func replaceAction(oldID: String, with a: HeraldAction, in rules: inout [HeraldActionRule]) {
        guard let i = rules.firstIndex(where: { $0.add?.id == oldID }) else { addAction(a, in: &rules); return }
        rules[i].add = a
        if oldID != a.id { for j in rules.indices where rules[j].add == nil && same(rules[j].match, oldID) { rules[j].match = a.id } }
    }

    static func removeAction(_ id: String, in rules: inout [HeraldActionRule]) {
        rules.removeAll { $0.add?.id == id || (same($0.match, id) && $0.add == nil) }
    }

    /// Makes the visible actions appear in `ids` order. `natural` is the order without any order rule.
    static func applyOrder(_ ids: [String], natural: [String], in rules: inout [HeraldActionRule]) {
        rules.removeAll(where: isOrderRule)
        guard ids != natural else { return }
        for (i, id) in ids.enumerated() { rules.append(HeraldActionRule(match: id, position: i)) }
    }

    /// The order to keep after the set of visible actions changed: `previous` minus what is gone, with newcomers
    /// at their place in `natural`. Order rules are absolute positions, so they must be rebuilt whenever an
    /// action appears or disappears.
    static func mergeOrder(previous: [String], natural: [String]) -> [String] {
        var out = previous.filter { natural.contains($0) }
        for (i, id) in natural.enumerated() where !out.contains(id) { out.insert(id, at: min(i, out.count)) }
        return out
    }

    /// An action id not in `taken`: `base`, else `base-2`, `base-3`...
    static func uniqueID(_ base: String, taken: Set<String>) -> String {
        let root = base.isEmpty ? "action" : base
        if !taken.contains(root) { return root }
        var n = 2
        while taken.contains("\(root)-\(n)") { n += 1 }
        return "\(root)-\(n)"
    }
}

// MARK: - Empty behaviour

extension HeraldComponent {
    /// The same component with its `emptyBehavior` set (nil = follow the template's `collapseEmpty`).
    /// A spacer has none and is returned as it is.
    func settingEmptyBehavior(_ b: HeraldEmptyBehavior?) -> HeraldComponent {
        switch self {
        case .text(var p): p.emptyBehavior = b; return .text(p)
        case .image(var p): p.emptyBehavior = b; return .image(p)
        case .issuerIcon(var p): p.emptyBehavior = b; return .issuerIcon(p)
        case .timestamp(var p): p.emptyBehavior = b; return .timestamp(p)
        case .button(var p): p.emptyBehavior = b; return .button(p)
        case .actions(var p): p.emptyBehavior = b; return .actions(p)
        case .iconButton(var p): p.emptyBehavior = b; return .iconButton(p)
        case .badge(var p): p.emptyBehavior = b; return .badge(p)
        case .progress(var p): p.emptyBehavior = b; return .progress(p)
        case .rive(var p): p.emptyBehavior = b; return .rive(p)
        case .spacer: return self
        }
    }

    /// Can this component ever be empty? (An issuer icon and a spacer always have something to show.)
    var canBeEmpty: Bool {
        switch self {
        case .issuerIcon, .spacer: return false
        case .timestamp(let p): return !(p.binding ?? "").trimmingCharacters(in: .whitespaces).isEmpty
        default: return true
        }
    }
}

// MARK: - Backend

/// One app that can have templates: a manifest, a registration or a template folder.
struct DesignerIssuer: Identifiable, Equatable {
    var id: String
    var name: String
    var hasManifest: Bool
}

/// Everything the Designer needs from the app, as closures, so the model needs no AppKit and no
/// `AppController`. `DesignerWindow.swift` builds the live one.
struct DesignerBackend {
    var issuers: () -> [DesignerIssuer] = { [] }
    var manifest: (_ app: String) -> HeraldManifest? = { _ in nil }
    var templates: (_ app: String) -> [HeraldTemplate] = { _ in [] }
    /// Creates or replaces a template; false when it could not be written.
    var saveTemplate: (_ t: HeraldTemplate) -> Bool = { _ in true }
    var deleteTemplate: (_ app: String, _ name: String) -> Bool = { _, _ in true }
    /// Makes `name` the issuer's default template (nil clears it); false when it could not be saved.
    var setDefaultTemplate: (_ app: String, _ name: String?) -> Bool = { _, _ in true }
    /// The newest notification in history for the app.
    var lastItem: (_ app: String) -> HeraldHistoryItem? = { _ in nil }
    /// Installed Shortcuts (`GET /v1/shortcuts`, through the in-process controller).
    var shortcuts: () async throws -> [String] = { [] }
    /// File names in Herald's scripts folder.
    var scripts: () -> [String] = { [] }
    /// The scripts folder itself, so the action form can open it.
    var scriptsFolder: () -> URL? = { nil }
    /// Delivers a notification through the controller; returns its id.
    var sendTest: (_ n: HeraldNotification) async throws -> String = { $0.id ?? "" }

    // Animations (issue #33)
    /// Every `.riv` in the app's assets folder (copies of the issuer's assets and files added by hand).
    var assetFiles: (_ app: String) -> [URL] = { _ in [] }
    /// Copies a file into the app's assets folder as `<asset.id>.riv` (`AssetStore.install`); throws a readable error.
    var installAsset: (_ app: String, _ asset: HeraldAsset) throws -> Void = { _, _ in }
    /// Deletes one file from the app's assets folder.
    var removeAssetFile: (_ app: String, _ file: URL) -> Bool = { _, _ in true }
    /// The file a Rive component plays (the app's stored copy, the manifest's file, or its path); nil when unresolved.
    var riveFile: (_ app: String, _ component: HeraldRiveComponent) -> URL? = { _, _ in nil }
    /// What is inside a Rive file (artboards, state machines, inputs), read with the Rive runtime.
    var riveInfo: (_ file: URL) -> RiveFileInfo? = { _ in nil }

    // Template bundles (issue #30)
    var exportBundle: (_ t: HeraldTemplate) throws -> HeraldTemplateBundle.ExportResult = { _ in
        throw HeraldTemplateBundle.BundleError.cannotWrite("export is not available")
    }
    var previewBundle: (_ data: Data, _ intoApp: String?) throws -> TemplateBundleService.Preview = { _, _ in
        throw HeraldTemplateBundle.BundleError.notABundle("import is not available")
    }
    var importBundle: (_ data: Data, _ intoApp: String?, _ conflict: TemplateBundleService.Conflict) throws -> TemplateBundleService.ImportResult = { _, _, _ in
        throw HeraldTemplateBundle.BundleError.notABundle("import is not available")
    }
}

// MARK: - Animations

/// What is inside a Rive file, read once with the Rive runtime (`RiveFileInspector`) and handed to the model
/// through `DesignerBackend.riveInfo`, so the model and its tests need no runtime.
struct RiveFileInfo: Equatable {
    struct Input: Equatable {
        enum Kind: String { case number, bool, trigger }
        var name: String
        var kind: Kind
    }
    struct Machine: Equatable {
        var name: String
        var inputs: [Input]
    }
    struct Artboard: Equatable {
        var name: String
        var width: Double
        var height: Double
        /// The state machine the file marks as its default, if it marks one.
        var defaultMachine: String?
        var machines: [Machine]
        /// Linear animations (played when the artboard has no state machine).
        var animations: [String]

        var aspectRatio: Double? { width > 0 && height > 0 ? width / height : nil }
    }
    var artboards: [Artboard]

    /// The named artboard, else the file's first (what a component with no `artboard` plays).
    func artboard(named name: String?) -> Artboard? {
        if let name, !name.isEmpty, let a = artboards.first(where: { $0.name == name }) { return a }
        return artboards.first
    }

    /// The state machine a component plays: the named one, else the artboard's default, else its first.
    func machine(_ name: String?, artboard artboardName: String?) -> Machine? {
        guard let a = artboard(named: artboardName) else { return nil }
        if let name, !name.isEmpty { return a.machines.first { $0.name == name } }
        return a.machines.first { $0.name == a.defaultMachine } ?? a.machines.first
    }
}

/// One Rive file in the app's assets folder, as the Assets panel lists it.
struct DesignerAsset: Identifiable, Equatable {
    /// The file's name without `.riv`: what a component's `asset` is when the issuer declares it.
    var id: String
    var url: URL
    var bytes: Int
    /// The issuer's manifest declares an asset with this id (so a component names it by id, not by file).
    var declared: Bool
    /// Names of the saved templates, and the draft, whose Rive components play this file.
    var usedBy: [String]

    var file: String { url.lastPathComponent }
}

/// What a drag would do if it were dropped now: shown on the canvas while the pointer is over a slot.
struct DropPreview: Equatable {
    /// The area the drop lands on: the occupying cell's whole area, or the single empty slot.
    var rect: SlotRect
    /// A short description of the effect ("Bind {sender}", "Swap with image").
    var verb: String
    /// False when the drop would be refused; the canvas then outlines the area in red.
    var allowed: Bool
}

/// Which action form is open.
struct ActionEditorRequest: Identifiable, Equatable {
    enum Mode: Equatable {
        /// A new action of the user's own in the template's rules.
        case addToTemplate
        /// Editing one the user added (its current id).
        case editTemplate(String)
        /// Editing the inline action of a button, icon button or Rive cell.
        case inline(cellID: String)
    }
    var id = UUID()
    var mode: Mode
    var action: HeraldAction
}

// MARK: - Model

enum DesignerPreviewSource: String, CaseIterable, Identifiable {
    case sample, lastReal
    var id: String { rawValue }
    var title: String { self == .sample ? "Sample" : "Last real" }
}

enum DesignerAppearance: String, CaseIterable, Identifiable {
    case light, dark
    var id: String { rawValue }
}

/// What the Designer window is doing: laying out a template, or sending a one-off notification (the old
/// Compose window, issue #31).
enum DesignerMode: String, CaseIterable, Identifiable {
    case design, quickSend
    var id: String { rawValue }
    var title: String { self == .design ? "Design" : "Quick send" }
    var windowTitle: String { self == .design ? "Design Template" : "Quick Send" }
}

enum DesignerTab: String, CaseIterable, Identifiable {
    case cell, template, actions
    var id: String { rawValue }
    var title: String { self == .cell ? "Cell" : self == .template ? "Template" : "Actions" }
}

struct DesignerStatus: Equatable {
    enum Kind { case info, error }
    var kind: Kind
    var text: String
}

@MainActor
final class DesignerModel: ObservableObject {
    /// Name of the scratch template "Send test" writes when the draft is unsaved or changed.
    static let testTemplateName = "_designer-test"
    /// Stand-in picture value in sample data; the canvas draws a stock gradient for it and Send test drops it.
    static let sampleImage = "designer:sample-image"
    static let undoLimit = 100

    let backend: DesignerBackend

    // Issuer and template lists.
    @Published private(set) var issuers: [DesignerIssuer] = []
    @Published private(set) var app = ""
    @Published private(set) var manifest: HeraldManifest?
    @Published private(set) var templates: [HeraldTemplate] = []
    @Published private(set) var lastItem: HeraldHistoryItem?

    // The template being edited.
    @Published var draft: HeraldTemplate { didSet { issues = draft.validate(manifest: manifest) } }
    @Published private(set) var issues: [HeraldTemplateIssue] = []
    /// What is on disk under `savedName` (nil for a template that has never been saved).
    @Published private(set) var baseline: HeraldTemplate?
    @Published private(set) var savedName: String?
    /// The disk copy changed while the draft had edits (an agent or another window saved it).
    @Published private(set) var diskChanged = false

    // Selection and UI state.
    @Published private(set) var selection: SlotRect?
    private var anchor: GridSlot?
    @Published var tab: DesignerTab = .cell
    @Published var previewSource: DesignerPreviewSource = .sample
    @Published var appearance: DesignerAppearance = .light
    /// Tokens the user marked "absent" in the preview, to watch the empty-field behaviour.
    @Published var absentTokens: Set<String> = []
    @Published var customTokens: [String] = []
    @Published var status: DesignerStatus?
    @Published var actionEditor: ActionEditorRequest?
    @Published private(set) var sending = false
    @Published private(set) var canUndo = false
    @Published private(set) var canRedo = false

    /// Design a template, or send a one-off notification (issue #31). The quick-send form lives on after a
    /// switch, so a half-written message survives a look at the designer.
    @Published var mode: DesignerMode = .design
    let quickSend: ComposerModel

    /// What a drag in progress carries (set when a drag starts, in this process) and what dropping it on the slot
    /// under the pointer would do (issue #38).
    var dragging: DragPayload?
    @Published private(set) var dropTarget: DropPreview?
    private var hoverSlot: GridSlot?

    /// The Rive files in the issuer's assets folder (issue #33).
    @Published private(set) var assets: [DesignerAsset] = []
    private var infoCache: [String: (stamp: Date?, info: RiveFileInfo?)] = [:]

    /// Asked when an imported template's name is taken: nil cancels the import.
    var chooseConflict: (TemplateBundleService.Preview) -> TemplateBundleService.Conflict? = { _ in .keepBoth }

    /// Asked before unsaved edits are thrown away; the window installs an alert. True lets it go ahead.
    var confirmDiscard: () -> Bool = { true }

    private var undoStack: [HeraldTemplate] = []
    private var redoStack: [HeraldTemplate] = []
    private var lastEditAt: Date?
    private var suppressRefresh = false

    init(backend: DesignerBackend, app: String? = nil, template: String? = nil) {
        self.backend = backend
        self.draft = HeraldTemplate.blank(name: "", app: "")
        self.quickSend = ComposerModel()
        reloadIssuers()
        let start = app.flatMap { a in issuers.contains { $0.id == a } ? a : nil } ?? issuers.first?.id ?? ""
        switchIssuer(start, template: template, force: true)
    }

    // MARK: Derived state

    var isNew: Bool { savedName == nil }
    var isDirty: Bool { baseline.map { $0 != draft } ?? hasNewEdits }
    private var newDraftOrigin: HeraldTemplate?
    private var hasNewEdits: Bool { newDraftOrigin.map { $0 != draft } ?? true }
    var canSave: Bool { (isDirty || isNew) && !draft.name.trimmingCharacters(in: .whitespaces).isEmpty }
    var hasErrors: Bool { issues.contains { $0.isError } }
    var convertedFromV1: Bool { baseline.map { !$0.usesGrid } ?? false }
    var grid: HeraldGrid { draft.grid ?? .standard }
    var defaultTemplateName: String? { manifest?.defaultTemplate }
    func isDefault(_ name: String) -> Bool { manifest?.defaultTemplate == name }
    var currentIssuer: DesignerIssuer? { issuers.first { $0.id == app } }
    var issuerName: String { currentIssuer?.name ?? app }

    // MARK: Issuers and template lists

    func reloadIssuers() {
        issuers = backend.issuers().sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Lists the templates the designer shows: every saved one except its own scratch template.
    private func reloadTemplates() {
        templates = app.isEmpty ? [] : backend.templates(app).filter { !$0.name.hasPrefix("_designer") }
    }

    func switchIssuer(_ id: String, template: String? = nil, force: Bool = false) {
        guard force || id != app else { return }
        guard force || !isDirty || confirmDiscard() else { return }
        app = id
        manifest = backend.manifest(id)
        lastItem = backend.lastItem(id)
        absentTokens = []
        reloadTemplates()
        reloadAssets()
        let pick = templates.first { $0.name == template }
            ?? manifest?.defaultTemplate.flatMap { d in templates.first { $0.name == d } }
            ?? templates.first
        if let pick { load(pick) } else { startNew(from: nil, confirm: false) }
        if lastItem == nil, previewSource == .lastReal { previewSource = .sample }
    }

    func select(template name: String) {
        guard name != savedName, let t = templates.first(where: { $0.name == name }) else { return }
        guard !isDirty || confirmDiscard() else { return }
        load(t)
    }

    /// Opens a template for editing. A v1 template is converted to its grid form (saving writes it as v2).
    func load(_ t: HeraldTemplate) {
        var d = t
        if !t.usesGrid { d = BuiltinTemplates.gridTemplate(for: t) }
        if var g = d.grid { GridEditing.fixSizes(&g); d.grid = g }
        draft = d
        baseline = t; savedName = t.name; newDraftOrigin = nil
        undoStack = []; redoStack = []; lastEditAt = nil; updateUndoFlags()
        selection = nil; anchor = nil
        diskChanged = false; status = nil; tab = .template
    }

    /// A new unsaved template: blank, or a copy of one of the four built-in layouts.
    func startNew(from layout: HeraldLayout?, confirm: Bool = true) {
        guard !confirm || !isDirty || confirmDiscard() else { return }
        let base = layout.map { Self.stem(for: $0) } ?? "template"
        var n = 1
        while templates.contains(where: { $0.name == "\(base)-\(n)" }) { n += 1 }
        var t: HeraldTemplate
        if let layout {
            t = BuiltinTemplates.template(layout: layout, app: app)
            t.name = "\(base)-\(n)"
        } else {
            t = HeraldTemplate.blank(name: "\(base)-\(n)", app: app)
        }
        t.app = app
        draft = t
        baseline = nil; savedName = nil; newDraftOrigin = t
        undoStack = []; redoStack = []; lastEditAt = nil; updateUndoFlags()
        selection = nil; anchor = nil; diskChanged = false; status = nil; tab = .template
    }

    private static func stem(for l: HeraldLayout) -> String {
        switch l {
        case .imageLeft: return "image-left"
        case .imageRight: return "image-right"
        case .hero: return "hero"
        case .compact: return "compact"
        }
    }

    // MARK: Save, duplicate, delete, default

    static func isValidName(_ n: String) -> Bool { !n.isEmpty && !n.contains("/") && !n.contains(":") && !n.hasPrefix(".") && !n.hasPrefix("_") }

    @discardableResult
    func save() -> Bool {
        let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isValidName(name) else { fail("Name must not be empty, start with . or _, or contain / or :."); return false }
        if name != savedName, templates.contains(where: { $0.name == name }) { fail("A template named \u{201C}\(name)\u{201D} already exists."); return false }
        var t = draft
        t.name = name; t.app = app; t.layoutVersion = HeraldTemplate.currentLayoutVersion
        if let first = t.validate(manifest: manifest).first(where: \.isError) {
            fail("Not saved: \(first.message)"); return false
        }
        suppressRefresh = true; defer { suppressRefresh = false }
        guard backend.saveTemplate(t) else { fail("Could not write the template file."); return false }
        if let old = savedName, old != name {
            _ = backend.deleteTemplate(app, old)
            if manifest?.defaultTemplate == old { _ = backend.setDefaultTemplate(app, name); manifest = backend.manifest(app) }
        }
        draft = t; baseline = t; savedName = name; newDraftOrigin = nil; diskChanged = false
        reloadTemplates()
        info("Saved \u{201C}\(name)\u{201D}.")
        return true
    }

    /// Save as: writes the current draft (edits included) under a new name and switches to it; the original
    /// on disk stays as it was.
    func duplicate() {
        var base = draft.name.isEmpty ? "template" : draft.name
        if base.hasSuffix(" copy") { base.removeLast(5) }
        var name = base + " copy", n = 1
        while templates.contains(where: { $0.name == name }) { n += 1; name = base + " copy \(n)" }
        var t = draft
        t.name = name; t.app = app
        suppressRefresh = true; defer { suppressRefresh = false }
        guard backend.saveTemplate(t) else { fail("Could not write the template file."); return }
        reloadTemplates()
        load(t)
        info("Duplicated as \u{201C}\(name)\u{201D}.")
    }

    func deleteSaved() {
        guard let name = savedName else { return }
        suppressRefresh = true; defer { suppressRefresh = false }
        guard backend.deleteTemplate(app, name) else { fail("Could not delete \u{201C}\(name)\u{201D}."); return }
        if manifest?.defaultTemplate == name { _ = backend.setDefaultTemplate(app, nil); manifest = backend.manifest(app) }
        reloadTemplates()
        if let first = templates.first { load(first) } else { startNew(from: nil, confirm: false) }
        info("Deleted \u{201C}\(name)\u{201D}.")
    }

    /// Makes the saved template the issuer's default (what a notification that names none uses).
    func setAsDefault() {
        guard let name = savedName else { fail("Save the template first."); return }
        suppressRefresh = true; defer { suppressRefresh = false }
        guard backend.setDefaultTemplate(app, name) else { fail("Could not save the issuer's default."); return }
        manifest = backend.manifest(app)
        reloadIssuers()
        info("\u{201C}\(name)\u{201D} is now the default for \(issuerName).")
    }

    /// Called when Herald's data changed (a notification arrived, an agent saved a template...).
    func refreshFromDisk() {
        guard !suppressRefresh else { return }
        reloadIssuers()
        manifest = backend.manifest(app)
        lastItem = backend.lastItem(app)
        if lastItem == nil, previewSource == .lastReal { previewSource = .sample }
        reloadTemplates()
        reloadAssets()
        issues = draft.validate(manifest: manifest)
        guard let name = savedName, let onDisk = templates.first(where: { $0.name == name }), onDisk != baseline else { return }
        if isDirty { diskChanged = true } else { load(onDisk); tab = .cell; info("Reloaded \u{201C}\(name)\u{201D}: it changed on disk.") }
    }

    func reloadFromDisk() {
        guard let name = savedName, let onDisk = backend.templates(app).first(where: { $0.name == name }) else { return }
        load(onDisk)
    }

    private func fail(_ s: String) { status = DesignerStatus(kind: .error, text: s) }
    private func info(_ s: String) { status = DesignerStatus(kind: .info, text: s) }

    // MARK: Mode (issue #31)

    /// Switches to quick send. The form starts on `app` (the issuer being designed, by default) the first time.
    func showQuickSend(app forApp: String? = nil) {
        mode = .quickSend
        if let forApp, !forApp.isEmpty { quickSend.app = forApp }
        else if quickSend.app.trimmingCharacters(in: .whitespaces).isEmpty { quickSend.app = app }
    }

    /// Switches back to the designer, optionally to another issuer or template.
    func showDesign(app target: String? = nil, template: String? = nil) {
        mode = .design
        guard let target, !target.isEmpty else { return }
        if target != app { switchIssuer(target, template: template) }
        else if let template { select(template: template) }
    }

    // MARK: Drag and drop (issue #38)

    /// What dropping `payload` on `slot` would do, worked out on a copy of the draft with the same functions
    /// `handle` uses, so the canvas never promises something the drop does not do. nil outside the grid.
    func dropPreview(for payload: DragPayload, at slot: GridSlot) -> DropPreview? {
        guard let g = draft.grid, GridEditing.inBounds(SlotRect(slot), in: g) else { return nil }
        let occupant = GridEditing.cell(at: slot, in: draft)
        let target = occupant.flatMap { GridEditing.rect(of: $0, in: g) } ?? SlotRect(slot)
        func kind(_ c: HeraldComponent) -> String { DesignerPalette.title(for: c.typeName).lowercased() }
        func result(_ verb: String, allowed: Bool = true, rect: SlotRect? = nil) -> DropPreview {
            DropPreview(rect: rect ?? target, verb: verb, allowed: allowed)
        }
        switch payload {
        case .component(let type):
            let title = DesignerPalette.title(for: type).lowercased()
            guard let o = occupant else { return result("Add \(title)") }
            return result("Replace \(kind(o.component)) with \(title)")
        case .field(let key):
            guard let o = occupant else { return result("Add {\(key)}") }
            if DesignerPalette.bind(token: key, into: o.component) == nil {
                return result("A \(kind(o.component)) cannot bind {\(key)}", allowed: false)
            }
            return result("Bind {\(key)}")
        case .action(let id):
            let label = actionRows.first { $0.id == id }?.action.label ?? id
            return result(occupant == nil ? "Add \u{201C}\(label)\u{201D} button" : "Replace with \u{201C}\(label)\u{201D} button")
        case .rive(let id):
            guard assets.contains(where: { $0.id == id }) else { return result("That animation is gone", allowed: false) }
            return result(occupant == nil ? "Add animation" : "Replace \(occupant.map { kind($0.component) } ?? "") with animation")
        case .cell(let id):
            guard draft.cell(withID: id) != nil else { return nil }
            if occupant?.id == id { return result("Already here", allowed: false) }
            var t = draft
            guard GridEditing.move(cell: id, to: slot, in: &t) else { return result("Cannot move here", allowed: false) }
            if let o = occupant { return result("Swap with \(kind(o.component))") }
            return result("Move here", rect: GridEditing.rect(ofCell: id, in: t) ?? SlotRect(slot))
        }
    }

    /// The pointer is over `slot` with a drag: remember what a drop would do (nil clears it).
    func hoverDrop(at slot: GridSlot?) {
        hoverSlot = slot
        guard let slot else { if dropTarget != nil { dropTarget = nil }; return }
        let next = dragging.flatMap { dropPreview(for: $0, at: slot) }
            ?? GridEditing.cell(at: slot, in: draft).flatMap { GridEditing.rect(of: $0, in: grid) }.map { DropPreview(rect: $0, verb: "Drop here", allowed: true) }
            ?? DropPreview(rect: SlotRect(slot), verb: "Drop here", allowed: true)
        if next != dropTarget { dropTarget = next }
    }

    /// The pointer left `slot`. Ignored when it already entered another one (the order SwiftUI reports the two in
    /// is not fixed), so the highlight never flickers off between neighbours.
    func leaveDrop(at slot: GridSlot) {
        guard hoverSlot == slot else { return }
        hoverDrop(at: nil)
    }

    func endDrag() { dragging = nil; hoverSlot = nil; dropTarget = nil }

    // MARK: Track sizes (issue #38)

    /// Live size of column or row `index` while its canvas handle is dragged (call `beginGesture` first).
    func resizeTrackLive(columns: Bool, index: Int, points: Double) {
        liveEdit { _ = GridEditing.setTrack(columns: columns, index: index, size: .points(points), in: &$0) }
    }

    /// Back to the default size: a column fills, a row fits its content.
    func resetTrack(columns: Bool, index: Int) {
        perform { _ = GridEditing.setTrack(columns: columns, index: index, size: columns ? .fill : .auto, in: &$0) }
    }

    // MARK: Animations (issue #33)

    /// Lists the Rive files of the current issuer and who plays them.
    func reloadAssets() {
        guard !app.isEmpty else { assets = []; return }
        let declaredFiles = Set((manifest?.assets ?? []).filter { $0.type.lowercased() == "rive" }
            .map { HeraldTemplateBundle.safeFile(stem: $0.id).lowercased() })
        var users: [HeraldTemplate] = templates.filter { $0.name != savedName }
        users.append(draft)
        let next = backend.assetFiles(app).sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            .map { url -> DesignerAsset in
                let file = url.lastPathComponent
                let used = users.filter { t in
                    HeraldTemplateBundle.riveRefs(in: t).contains { HeraldTemplateBundle.fileName(for: $0).lowercased() == file.lowercased() }
                }
                var seen = Set<String>()
                let names = used.map(\.name).filter { !$0.isEmpty && seen.insert($0).inserted }
                let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue ?? 0
                return DesignerAsset(id: String(file.dropLast(4)), url: url, bytes: size,
                                     declared: declaredFiles.contains(file.lowercased()), usedBy: names)
            }
        if next != assets { assets = next }
    }

    /// Copies a `.riv` into the issuer's assets folder under a free name.
    func addAsset(from url: URL) {
        guard !app.isEmpty else { fail("Choose an issuer first."); return }
        let base = String(HeraldTemplateBundle.safeFile(stem: url.lastPathComponent).dropLast(4))
        let id = HeraldTemplateBundle.uniqueName(base, taken: Set(assets.map(\.id))).replacingOccurrences(of: " ", with: "-")
        do {
            try backend.installAsset(app, HeraldAsset(id: id, type: "rive", path: url.path))
            reloadAssets()
            info("Added \u{201C}\(id).riv\u{201D}.")
        } catch {
            fail(error.localizedDescription)
        }
    }

    /// Deletes an animation file. Templates that play it show a placeholder until it is added again.
    func removeAsset(_ asset: DesignerAsset) {
        guard backend.removeAssetFile(app, asset.url) else { fail("Could not remove \u{201C}\(asset.file)\u{201D}."); return }
        infoCache[asset.url.path] = nil
        reloadAssets()
        info("Removed \u{201C}\(asset.file)\u{201D}.")
    }

    /// The component that plays `asset`: by id when the issuer declares it (the manifest knows its state machine
    /// and inputs), else by file name inside the app's assets folder.
    func riveComponent(for asset: DesignerAsset) -> HeraldRiveComponent {
        let declared = manifest?.assets.first { $0.id == asset.id }
        let inf = riveFileInfo(at: asset.url)
        let machine = declared?.stateMachine ?? inf?.machine(nil, artboard: nil)?.name
        var c = asset.declared ? HeraldRiveComponent(asset: declared?.id ?? asset.id, stateMachine: machine)
                               : HeraldRiveComponent(path: asset.file, stateMachine: machine)
        c.aspectRatio = inf?.artboard(named: nil)?.aspectRatio ?? 1
        return c
    }

    func addRive(assetID: String, at slot: GridSlot) {
        guard let asset = assets.first(where: { $0.id == assetID }) else { fail("That animation is no longer in the assets folder."); return }
        let c = HeraldComponent.rive(riveComponent(for: asset))
        var placed: String?
        perform { placed = GridEditing.place(c, at: slot, in: &$0) }
        if let placed { select(cell: placed); reloadAssets() }
    }

    /// Click on an asset in the panel: an animation in the selected slot (or the first free one).
    func insertAsset(id: String) {
        guard let slot = targetSlot else { fail("The grid is full: merge or remove a cell first."); return }
        addRive(assetID: id, at: slot)
    }

    /// What is inside a Rive file; cached until the file changes.
    func riveFileInfo(at url: URL) -> RiveFileInfo? {
        let stamp = (try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate]) as? Date
        if let hit = infoCache[url.path], hit.stamp == stamp { return hit.info }
        let info = backend.riveInfo(url)
        infoCache[url.path] = (stamp, info)
        return info
    }

    /// Whether the file a component plays exists (the inspector tells "missing" from "unreadable").
    func riveFileFound(for component: HeraldRiveComponent) -> Bool { backend.riveFile(app, component) != nil }

    /// What is inside the file a component plays; nil while the file cannot be found or read.
    func riveFileInfo(for component: HeraldRiveComponent) -> RiveFileInfo? {
        backend.riveFile(app, component).flatMap(riveFileInfo(at:))
    }

    // MARK: Template bundles (issue #30)

    /// The file name an export of the draft starts with.
    var suggestedBundleName: String {
        HeraldTemplateBundle.sanitizedTemplateName(draft.name) + "." + HeraldTemplateBundle.fileExtension
    }

    /// Writes the template being edited, with its animations, to `url`.
    func exportDraft(to url: URL) {
        var t = draft
        t.name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        t.app = app
        t.layoutVersion = HeraldTemplate.currentLayoutVersion
        do {
            let r = try backend.exportBundle(t)
            try r.data.write(to: url, options: .atomic)
            let n = r.assetFiles.count
            var text = "Exported \u{201C}\(t.name)\u{201D} with \(n) animation file\(n == 1 ? "" : "s")."
            if !r.warnings.isEmpty { text += " " + r.warnings.joined(separator: " ") }
            status = DesignerStatus(kind: r.warnings.isEmpty ? .info : .error, text: text)
        } catch {
            fail("Export failed: \(error.localizedDescription)")
        }
    }

    /// What the bundle at `url` holds, for the confirmation. Nil (and a status message) when it is not a bundle.
    func previewBundle(at url: URL) -> (data: Data, preview: TemplateBundleService.Preview)? {
        do {
            let data = try Data(contentsOf: url)
            return (data, try backend.previewBundle(data, nil))
        } catch {
            fail("Import failed: \(error.localizedDescription)")
            return nil
        }
    }

    /// Imports a bundle, for `intoApp` or the app the bundle names, and opens the result. A name that is taken
    /// goes to `chooseConflict`.
    func importBundle(_ data: Data, intoApp: String? = nil) {
        do {
            var conflict = TemplateBundleService.Conflict.keepBoth
            let preview = try backend.previewBundle(data, intoApp)
            if preview.nameTaken {
                guard let chosen = chooseConflict(preview) else { return }
                conflict = chosen
            }
            suppressRefresh = true
            let r = try backend.importBundle(data, intoApp, conflict)
            suppressRefresh = false
            reloadIssuers()
            var note = "Imported \u{201C}\(r.template.name)\u{201D}"
            if let from = r.renamedFrom { note += " (\u{201C}\(from)\u{201D} was taken)" }
            if r.replaced { note += ", replacing the old one" }
            let n = r.assets.installed.count
            note += n > 0 ? "; \(n) animation file\(n == 1 ? "" : "s") added." : "."
            let warn = r.warnings.isEmpty ? "" : " " + r.warnings.joined(separator: " ")
            if r.template.app != app {
                switchIssuer(r.template.app, template: r.template.name, force: false)
                if app != r.template.app { reloadTemplates(); fail(note + " It is under \(r.template.app)." + warn); return }
            } else {
                reloadTemplates(); reloadAssets()
                if !isDirty || confirmDiscard() { load(r.template) } else { note += " It is in the template list." }
            }
            status = DesignerStatus(kind: r.warnings.isEmpty ? .info : .error, text: note + warn)
        } catch {
            suppressRefresh = false
            fail("Import failed: \(error.localizedDescription)")
        }
    }

    // MARK: Undo

    private func snapshot() {
        undoStack.append(draft)
        if undoStack.count > Self.undoLimit { undoStack.removeFirst() }
        redoStack.removeAll()
        updateUndoFlags()
    }

    private func updateUndoFlags() { canUndo = !undoStack.isEmpty; canRedo = !redoStack.isEmpty }

    /// A structural change (merge, move, add, delete, ...): one undo step. Returns whether anything changed.
    @discardableResult
    func perform(_ body: (inout HeraldTemplate) -> Void) -> Bool {
        var copy = draft
        body(&copy)
        guard copy != draft else { return false }
        snapshot(); lastEditAt = nil
        draft = copy
        return true
    }

    /// A property edit (typing, a slider): edits within a second share one undo step.
    func edit(_ body: (inout HeraldTemplate) -> Void) {
        var copy = draft
        body(&copy)
        guard copy != draft else { return }
        let now = Date()
        if lastEditAt.map({ now.timeIntervalSince($0) > 1.0 }) ?? true { snapshot() }
        lastEditAt = now
        draft = copy
    }

    /// Starts an undo step for a gesture that then calls `liveEdit` many times (a span handle drag).
    func beginGesture() { snapshot(); lastEditAt = nil }
    func liveEdit(_ body: (inout HeraldTemplate) -> Void) { var c = draft; body(&c); if c != draft { draft = c } }

    func undo() {
        guard let prev = undoStack.popLast() else { return }
        redoStack.append(draft)
        draft = prev; lastEditAt = nil
        updateUndoFlags(); clampSelection()
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(draft)
        draft = next; lastEditAt = nil
        updateUndoFlags(); clampSelection()
    }

    // MARK: Selection

    /// The cell whose whole area is the selection; nil for an empty slot or a multi-cell selection.
    var selectedCell: HeraldCell? {
        guard let s = selection, let c = GridEditing.cell(at: s.origin, in: draft),
              GridEditing.rect(of: c, in: grid) == s else { return nil }
        return c
    }
    var selectedCellID: String? { selectedCell?.id }
    var selectionIsEmptySlot: Bool { selection.map { $0.area == 1 && GridEditing.cell(at: $0.origin, in: draft) == nil } ?? false }
    var canMerge: Bool { selection.map { GridEditing.canMerge($0, in: draft) } ?? false }
    var canSplit: Bool { selectedCell.flatMap { GridEditing.rect(of: $0, in: grid) }.map { $0.area > 1 } ?? false }

    /// Click: selects the cell under `slot` (or the empty slot). Shift-click extends from the anchor.
    func select(slot: GridSlot, extend: Bool = false) {
        guard GridEditing.inBounds(SlotRect(slot), in: grid) else { return }
        if extend, let a = anchor {
            selection = GridEditing.expanded(.bounding(a, slot), in: draft)
        } else if let c = GridEditing.cell(at: slot, in: draft), let r = GridEditing.rect(of: c, in: grid) {
            selection = r; anchor = r.origin
        } else {
            selection = SlotRect(slot); anchor = slot
        }
        if selection != nil { tab = .cell }
    }

    func select(cell id: String) {
        guard let r = GridEditing.rect(ofCell: id, in: draft) else { return }
        selection = r; anchor = r.origin; tab = .cell
    }

    func clearSelection() { selection = nil; anchor = nil }

    private func clampSelection() {
        guard let s = selection else { return }
        if !GridEditing.inBounds(s, in: grid) { clearSelection() }
        else if s.area == 1 { return }
        else if let c = GridEditing.cell(at: s.origin, in: draft), GridEditing.rect(of: c, in: grid) == s { return }
        else { selection = GridEditing.expanded(s, in: draft) }
    }

    // MARK: Canvas operations

    /// The selection's origin, or the first free slot, as the default place for "add".
    private var targetSlot: GridSlot? {
        if let s = selection { return s.origin }
        let g = grid
        return (0..<(g.rows * g.cols)).map { GridSlot($0 / max(g.cols, 1), $0 % max(g.cols, 1)) }
            .first { GridEditing.cell(at: $0, in: draft) == nil }
    }

    func addComponent(type: String, at slot: GridSlot? = nil) {
        guard let slot = slot ?? targetSlot else { fail("The grid is full: merge or remove a cell first."); return }
        let component = DesignerPalette.makeComponent(type: type, manifest: manifest, actions: baseActions)
        var placed: String?
        perform { placed = GridEditing.place(component, at: slot, in: &$0) }
        if let placed { select(cell: placed) }
    }

    func addField(key: String, type: HeraldFieldType?, at slot: GridSlot) {
        var placed: String?
        let existing = GridEditing.cell(at: slot, in: draft)
        if let existing {
            guard let bound = DesignerPalette.bind(token: key, into: existing.component) else {
                fail("A \(DesignerPalette.title(for: existing.component.typeName).lowercased()) cannot bind a field; drop it on a text, image, time, badge or progress cell.")
                return
            }
            perform { placed = GridEditing.place(bound, at: slot, in: &$0) }
        } else {
            let c = DesignerPalette.component(forField: key, type: type)
            perform { placed = GridEditing.place(c, at: slot, in: &$0) }
        }
        if let placed { select(cell: placed) }
    }

    func addActionButton(actionID: String, at slot: GridSlot) {
        let c = HeraldComponent.button(HeraldButtonComponent(actionRef: actionID))
        var placed: String?
        perform { placed = GridEditing.place(c, at: slot, in: &$0) }
        if let placed { select(cell: placed) }
    }

    func moveCell(_ id: String, to slot: GridSlot) {
        var moved = false
        perform { moved = GridEditing.move(cell: id, to: slot, in: &$0) }
        if moved, let c = GridEditing.cell(at: slot, in: draft) { select(cell: c.id) }
    }

    /// Click on a field in the palette: bind it into the selected cell, or add it at the first free slot.
    func insertField(key: String) {
        guard let slot = targetSlot else { fail("The grid is full: merge or remove a cell first."); return }
        addField(key: key, type: tokenType(key), at: slot)
    }

    /// Click on an action in the palette: a button for it in the selected slot (or the first free one).
    func insertAction(id: String) {
        guard let slot = targetSlot else { fail("The grid is full: merge or remove a cell first."); return }
        addActionButton(actionID: id, at: slot)
    }

    func handle(_ payload: DragPayload, at slot: GridSlot) {
        switch payload {
        case .component(let type): addComponent(type: type, at: slot)
        case .field(let key): addField(key: key, type: tokenType(key), at: slot)
        case .action(let id): addActionButton(actionID: id, at: slot)
        case .cell(let id): moveCell(id, to: slot)
        case .rive(let id): addRive(assetID: id, at: slot)
        }
        endDrag()
    }

    func mergeSelection() {
        guard let s = selection else { return }
        var merged: String?
        perform { merged = GridEditing.merge(s, in: &$0) }
        if let merged { select(cell: merged) }
    }

    func splitSelection() {
        guard let id = selectedCellID else { return }
        let origin = selection?.origin
        perform { GridEditing.split(cell: id, in: &$0) }
        if let origin { select(slot: origin) }
    }

    /// Delete: removes the selected cell's component (a merged cell becomes a spacer first).
    func deleteSelection() {
        guard let id = selectedCellID else { return }
        var outcome = GridEditing.RemoveOutcome.notFound
        let origin = selection?.origin
        perform { outcome = GridEditing.remove(cell: id, in: &$0) }
        if outcome == .removed { clearSelection(); if let origin { selection = SlotRect(origin); anchor = origin } }
        else if outcome == .replacedWithSpacer { select(cell: id) }
    }

    func duplicateSelection() {
        guard let id = selectedCellID else { return }
        var copy: String?
        perform { copy = GridEditing.duplicate(cell: id, in: &$0) }
        if let copy { select(cell: copy) } else { fail("No room for a copy: the grid is full.") }
    }

    /// Live span change from a handle drag (call `beginGesture` first).
    func resizeLive(cell id: String, rowSpan: Int, colSpan: Int) {
        liveEdit { _ = GridEditing.resize(cell: id, rowSpan: rowSpan, colSpan: colSpan, in: &$0) }
        select(cell: id)
    }

    func setSpan(cell id: String, rowSpan: Int, colSpan: Int) {
        perform { _ = GridEditing.resize(cell: id, rowSpan: rowSpan, colSpan: colSpan, in: &$0) }
        select(cell: id)
    }

    func setPosition(cell id: String, row: Int, col: Int) {
        moveCell(id, to: GridSlot(row, col))
    }

    func updateCell(_ id: String, _ body: (inout HeraldCell) -> Void) {
        edit { t in
            guard let i = t.cells.firstIndex(where: { $0.id == id }) else { return }
            body(&t.cells[i])
        }
    }

    func setEmptyBehavior(cell id: String, _ b: HeraldEmptyBehavior?) {
        perform { t in
            guard let i = t.cells.firstIndex(where: { $0.id == id }) else { return }
            t.cells[i].component = t.cells[i].component.settingEmptyBehavior(b)
        }
    }

    /// Is the component of this cell empty with the current preview data?
    func isEmpty(_ cell: HeraldCell) -> Bool {
        !cell.component.hasContent(fields: previewFields, actions: previewActions)
    }

    /// The action a button, icon button or Rive cell runs: an inline one, or the id of a resolved action.
    func actionSlot(cell id: String) -> (inline: HeraldAction?, ref: String?)? {
        switch draft.cell(withID: id)?.component {
        case .button(let p)?: return (p.action, p.actionRef)
        case .iconButton(let p)?: return (p.action, p.actionRef)
        case .rive(let p)?: return (p.action, p.actionRef)
        default: return nil
        }
    }

    func setActionSlot(cell id: String, inline: HeraldAction?, ref: String?) {
        perform { t in
            guard let i = t.cells.firstIndex(where: { $0.id == id }) else { return }
            switch t.cells[i].component {
            case .button(var p): p.action = inline; p.actionRef = ref; t.cells[i].component = .button(p)
            case .iconButton(var p): p.action = inline; p.actionRef = ref; t.cells[i].component = .iconButton(p)
            case .rive(var p): p.action = inline; p.actionRef = ref; t.cells[i].component = .rive(p)
            default: break
            }
        }
    }

    func setComponentType(cell id: String, type: String) {
        let c = DesignerPalette.makeComponent(type: type, manifest: manifest, actions: baseActions)
        perform { t in
            guard let i = t.cells.firstIndex(where: { $0.id == id }) else { return }
            t.cells[i].component = c
            t.cells[i].align = GridEditing.defaultAlign(for: c)
        }
    }

    // Tracks.
    func insertRow(at index: Int) { perform { _ = GridEditing.insertRow(at: index, in: &$0) }; clampSelection() }
    func insertColumn(at index: Int) { perform { _ = GridEditing.insertColumn(at: index, in: &$0) }; clampSelection() }
    func removeRow(at index: Int) { perform { _ = GridEditing.removeRow(at: index, in: &$0) }; clampSelection() }
    func removeColumn(at index: Int) { perform { _ = GridEditing.removeColumn(at: index, in: &$0) }; clampSelection() }

    // MARK: Fields, tokens, preview data

    /// Everything that can be dragged or picked as a token, grouped.
    var tokenSuggestions: [TokenSuggestion] {
        var out: [TokenSuggestion] = []
        var seen = Set<String>()
        func add(_ key: String, _ type: HeraldFieldType?, _ group: TokenSuggestion.Group, _ sample: String?) {
            guard !key.isEmpty, seen.insert(key).inserted else { return }
            out.append(TokenSuggestion(key: key, type: type, group: group, sample: sample))
        }
        let sampleFields = TemplateResolver.sampleFields(manifest: manifest)
        for f in manifest?.fields ?? [] {
            add(f.key, f.type, .issuer, (f.sample ?? sampleFields[f.key]).map(TemplateResolver.string(for:)))
        }
        for s in DesignerPalette.standardTypes { add(s.key, s.type, .standard, sampleFields[s.key].map(TemplateResolver.string(for:))) }
        for k in draft.extra.keys.sorted() { add("extra.\(k)", .text, .extra, draft.extra[k]) }
        if let f = lastItem?.fields {
            for k in f.keys.sorted() where !k.hasPrefix("extra.") && !["app", "id", "priority", "sound"].contains(k) {
                add(k, nil, .seen, TemplateResolver.string(for: f[k]!))
            }
        }
        for k in customTokens { add(k, nil, .custom, nil) }
        for k in draft.referencedTokens { add(k, nil, .custom, nil) }
        return out
    }

    func tokenType(_ key: String) -> HeraldFieldType? {
        manifest?.field(key)?.type ?? DesignerPalette.standardTypes.first { $0.key == key }?.type
    }

    func addCustomToken(_ raw: String) {
        let key = raw.trimmingCharacters(in: CharacterSet(charactersIn: "{} \n\t"))
        guard Self.isTokenName(key), !customTokens.contains(key) else { return }
        customTokens.append(key)
    }

    static func isTokenName(_ s: String) -> Bool {
        !s.isEmpty && s.utf8.count <= 128 && s.allSatisfy { ($0.isASCII && ($0.isLetter || $0.isNumber)) || "_.-".contains($0) }
    }

    /// The data the canvas and the live preview bind to: the manifest's samples, or the newest real
    /// notification's fields, plus the template's own `extra` values, minus tokens marked absent.
    var previewFields: [String: HeraldFieldValue] {
        var f: [String: HeraldFieldValue]
        if previewSource == .lastReal, let item = lastItem {
            f = item.fields ?? TemplateResolver.fields(for: item.notification, manifest: manifest, deliveredAt: item.deliveredAt)
        } else {
            f = TemplateResolver.sampleFields(manifest: manifest)
            for field in manifest?.fields ?? [] where field.type == .image && f[field.key] == nil { f[field.key] = .text(Self.sampleImage) }
            for cell in draft.cells {
                guard case .image(let p) = cell.component else { continue }
                for token in TemplateResolver.placeholders(in: p.binding) where f[token] == nil { f[token] = .text(Self.sampleImage) }
            }
        }
        for (k, v) in draft.extra where !v.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { f["extra.\(k)"] = .text(v) }
        if f["deliveredAt"] == nil { f["deliveredAt"] = .text(ISODate.string(from: lastItem?.deliveredAt ?? Date())) }
        for token in absentTokens { f[token] = nil }
        return f
    }

    /// The issuer's own buttons for the preview, with their declared ids.
    private var issuerSource: (buttons: [HeraldButton], ids: [String]?) {
        if previewSource == .lastReal, let item = lastItem {
            let s = ActionResolver.issuerSource(for: item.notification, manifest: manifest)
            return (s.buttons, s.ids)
        }
        // The sample stands in for an issuer that names every action its manifest declares.
        if manifest != nil { let s = ActionResolver.sampleSource(manifest: manifest); return (s.buttons, s.ids) }
        return ([], nil)
    }

    /// The action list a banner would show with this template and the preview data.
    var previewActions: [HeraldResolvedAction] {
        let s = issuerSource
        return ActionResolver.resolveDetailed(issuer: s.buttons, ids: s.ids, rules: draft.actionRules)
    }

    /// The actions button cells can point at: issuer + template ones, without the preview's hidden ones.
    var baseActions: [HeraldResolvedAction] { previewActions }

    /// Issuer actions as designer rows (including hidden ones), then the user's own, in resolved order.
    var actionRows: [DesignerActionRow] {
        let s = issuerSource
        let ids = s.ids ?? s.buttons.map { HeraldAction.slug($0.label) }
        var base: [String: HeraldAction] = [:]
        var taken = Set<String>()
        for (i, b) in s.buttons.enumerated() {
            var id = ids.indices.contains(i) && !ids[i].isEmpty ? ids[i] : HeraldAction.slug(b.label)
            id = ActionRules.uniqueID(id, taken: taken); taken.insert(id)
            base[id] = HeraldAction(button: b, id: id)
        }
        let resolved = ActionResolver.resolveDetailed(issuer: s.buttons, ids: s.ids, rules: draft.actionRules)
        var rows = resolved.map { DesignerActionRow(action: $0.action, base: $0.origin == .issuer ? base[$0.id] : nil, origin: $0.origin, hidden: false) }
        let shown = Set(resolved.map(\.id))
        for (id, a) in base.sorted(by: { $0.key < $1.key }) where !shown.contains(id) {
            rows.append(DesignerActionRow(action: a, base: a, origin: .issuer, hidden: true))
        }
        return rows
    }

    // MARK: Action rules

    /// Changes the rules and keeps the visible actions in the order they had (`ActionRules.mergeOrder`).
    private func changeActionRules(_ body: @escaping (inout [HeraldActionRule]) -> Void) {
        let before = actionRows.filter { !$0.hidden }.map(\.id)
        let s = issuerSource
        perform { t in
            body(&t.actionRules)
            var plain = t.actionRules
            plain.removeAll(where: ActionRules.isOrderRule)
            let natural = ActionResolver.resolveDetailed(issuer: s.buttons, ids: s.ids, rules: plain).map(\.id)
            ActionRules.applyOrder(ActionRules.mergeOrder(previous: before, natural: natural), natural: natural, in: &t.actionRules)
        }
    }

    func setActionHidden(_ id: String, _ hidden: Bool) {
        changeActionRules { ActionRules.override(id, in: &$0) { $0.hide = hidden ? true : nil } }
    }

    func setActionLabel(_ id: String, label: String, original: String) {
        let value = label.trimmingCharacters(in: .whitespaces)
        edit { ActionRules.override(id, in: &$0.actionRules) { $0.relabel = (value.isEmpty || value == original) ? nil : value } }
    }

    func setActionStyle(_ id: String, style: String, original: String?) {
        perform { ActionRules.override(id, in: &$0.actionRules) { $0.style = style == (original ?? "default") ? nil : style } }
    }

    func resetAction(_ id: String) { changeActionRules { ActionRules.reset(id, in: &$0) } }

    /// Moves a visible action up (-1) or down (+1) the list.
    func moveAction(_ id: String, by delta: Int) {
        var ids = actionRows.filter { !$0.hidden }.map(\.id)
        guard let i = ids.firstIndex(of: id), (0..<ids.count).contains(i + delta) else { return }
        ids.remove(at: i); ids.insert(id, at: i + delta)
        let s = issuerSource
        perform { t in
            var plain = t.actionRules
            plain.removeAll(where: ActionRules.isOrderRule)
            let natural = ActionResolver.resolveDetailed(issuer: s.buttons, ids: s.ids, rules: plain).map(\.id)
            ActionRules.applyOrder(ids, natural: natural, in: &t.actionRules)
        }
    }

    func newActionRequest(kind: HeraldActionKind = .shortcut) -> ActionEditorRequest {
        let taken = Set(actionRows.map(\.id))
        var a = HeraldAction(id: ActionRules.uniqueID(kind.rawValue, taken: taken), label: Self.defaultLabel(kind), kind: kind)
        if kind == .url { a.url = "{url}" }
        if kind == .snooze { a.snoozeMinutes = HeraldAction.defaultSnoozeMinutes }
        return ActionEditorRequest(mode: .addToTemplate, action: a)
    }

    static func defaultLabel(_ k: HeraldActionKind) -> String {
        switch k {
        case .url: return "Open link"
        case .callback: return "Tell \u{201C}issuer\u{201D}"
        case .command: return "Run command"
        case .script: return "Run script"
        case .shortcut: return "Run shortcut"
        case .dismiss: return "Dismiss"
        case .snooze: return "Snooze"
        }
    }

    func openActionEditor(_ r: ActionEditorRequest) { actionEditor = r }

    func editTemplateAction(_ id: String) {
        guard let a = draft.actionRules.compactMap(\.add).first(where: { $0.id == id }) else { return }
        actionEditor = ActionEditorRequest(mode: .editTemplate(id), action: a)
    }

    func editInlineAction(cell id: String) {
        guard let c = draft.cell(withID: id) else { return }
        let a: HeraldAction?
        switch c.component {
        case .button(let p): a = p.action
        case .iconButton(let p): a = p.action
        case .rive(let p): a = p.action
        default: a = nil
        }
        actionEditor = ActionEditorRequest(mode: .inline(cellID: id), action: a ?? HeraldAction(id: "open", label: "Open", kind: .url, url: "{url}"))
    }

    /// Commits the open action form.
    func commitActionEditor(_ request: ActionEditorRequest) {
        var a = request.action
        a.label = a.label.trimmingCharacters(in: .whitespaces)
        switch request.mode {
        case .addToTemplate:
            let taken = Set(actionRows.map(\.id))
            a.id = ActionRules.uniqueID(a.id.isEmpty ? HeraldAction.slug(a.label) : a.id, taken: taken)
            changeActionRules { ActionRules.addAction(a, in: &$0) }
        case .editTemplate(let old):
            if a.id.isEmpty { a.id = old }
            if a.id != old, actionRows.contains(where: { $0.id == a.id }) { a.id = ActionRules.uniqueID(a.id, taken: Set(actionRows.map(\.id))) }
            let before = actionRows.filter { !$0.hidden }.map { $0.id == old ? a.id : $0.id }
            let src = issuerSource
            perform { t in
                ActionRules.replaceAction(oldID: old, with: a, in: &t.actionRules)
                if old != a.id { Self.renameActionRef(old, to: a.id, in: &t) }
                var plain = t.actionRules
                plain.removeAll(where: ActionRules.isOrderRule)
                let natural = ActionResolver.resolveDetailed(issuer: src.buttons, ids: src.ids, rules: plain).map(\.id)
                ActionRules.applyOrder(ActionRules.mergeOrder(previous: before, natural: natural), natural: natural, in: &t.actionRules)
            }
        case .inline(let cellID):
            perform { t in
                guard let i = t.cells.firstIndex(where: { $0.id == cellID }) else { return }
                switch t.cells[i].component {
                case .button(var p): p.action = a; p.actionRef = nil; t.cells[i].component = .button(p)
                case .iconButton(var p): p.action = a; p.actionRef = nil; t.cells[i].component = .iconButton(p)
                case .rive(var p): p.action = a; p.actionRef = nil; t.cells[i].component = .rive(p)
                default: break
                }
            }
        }
        actionEditor = nil
    }

    func removeTemplateAction(_ id: String) {
        changeActionRules { ActionRules.removeAction(id, in: &$0) }
    }

    private static func renameActionRef(_ old: String, to new: String, in t: inout HeraldTemplate) {
        for i in t.cells.indices {
            switch t.cells[i].component {
            case .button(var p) where p.actionRef == old: p.actionRef = new; t.cells[i].component = .button(p)
            case .iconButton(var p) where p.actionRef == old: p.actionRef = new; t.cells[i].component = .iconButton(p)
            case .rive(var p) where p.actionRef == old: p.actionRef = new; t.cells[i].component = .rive(p)
            default: break
            }
        }
    }

    // MARK: Send test

    /// The notification the preview stands for: the newest real one, or the sample fields as a payload (top
    /// level keys, the rest in `metadata`, the issuer's buttons). `sending` drops the stock picture, which no
    /// delivery could load.
    func previewNotification(sending: Bool = false) -> HeraldNotification {
        if previewSource == .lastReal, let item = lastItem { return item.notification }
        let f = previewFields
        func text(_ k: String) -> String? {
            guard let v = f[k] else { return nil }
            let s = TemplateResolver.string(for: v)
            return s.isEmpty || s == Self.sampleImage ? nil : s
        }
        var n = HeraldNotification(app: app, id: "designer-test", title: text("title") ?? "Test notification",
                                   subtitle: text("subtitle"), body: text("body"), image: text("image"), url: text("url"))
        let top: Set<String> = ["title", "subtitle", "body", "image", "url", "app", "appName", "id", "priority", "sound", "deliveredAt"]
        var meta: [String: JSONValue] = [:]
        for (k, v) in f where !top.contains(k) && !k.hasPrefix("extra.") {
            if case .text(let s) = v, s == Self.sampleImage { continue }
            meta[k] = ActionResolver.json(v)
        }
        if !meta.isEmpty { n.metadata = .object(meta) }
        let s = issuerSource
        if !s.buttons.isEmpty { n.buttons = s.buttons }
        return n
    }

    /// The notification "Send test" delivers: `previewNotification`, naming `templateName`, under a fixed id so
    /// the next test replaces the last banner.
    func testNotification(templateName: String) -> HeraldNotification {
        var n = previewNotification(sending: true)
        n.id = "designer-test"; n.template = templateName
        return n
    }

    /// Sends the preview through the controller. An unsaved or changed draft is first written to the
    /// scratch template `_designer-test` (the controller reads templates from disk).
    func sendTest() async {
        guard !sending else { return }
        if let first = issues.first(where: \.isError) { fail("Fix first: \(first.message)"); return }
        sending = true; defer { sending = false }
        var name = savedName ?? ""
        if isDirty || isNew || name.isEmpty {
            var t = draft
            t.name = Self.testTemplateName; t.app = app; t.layoutVersion = HeraldTemplate.currentLayoutVersion
            suppressRefresh = true
            let ok = backend.saveTemplate(t)
            suppressRefresh = false
            guard ok else { fail("Could not write the test template."); return }
            name = Self.testTemplateName
        }
        do {
            let id = try await backend.sendTest(testNotification(templateName: name))
            info("Sent test banner (\(id)).")
        } catch {
            fail("Send test failed: \(error.localizedDescription)")
        }
    }
}
