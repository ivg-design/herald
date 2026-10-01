import SwiftUI
import AppKit

// The Designer's editing canvas (DESIGN 7.4): the template's grid at real banner width, drawn with the same
// layout (`GridCanvasLayout` / `GridSolver`) and the same component views as live banners, so spacing, wrapping
// and styling match what a delivery shows. What differs from a live banner is only what editing needs:
// nothing collapses (empty slots stay visible and droppable, an empty component shows what it is bound to
// and what it does when empty), every cell has a selection/drag/drop layer on top, and components are inert.
//
// The only things used from the renderer are `GridRenderState` (the context a banner draws with),
// `GridCanvasLayout` + `GridCellIndexKey` (the layout) and the component views; `DesignerComponent.view`
// below is the one place that switches over component types.

enum DesignerCanvasSpace { static let name = "designer-canvas" }

/// Where each slot of the grid starts, reported by zero-size probe cells in the canvas coordinate space. Span
/// handles use it to turn the pointer position into a slot.
struct SlotOriginKey: PreferenceKey {
    static var defaultValue: [GridSlot: CGPoint] = [:]
    static func reduce(value: inout [GridSlot: CGPoint], nextValue: () -> [GridSlot: CGPoint]) {
        value.merge(nextValue()) { $1 }
    }
}

// MARK: - Preview models

/// Builds the `BannerModel`s the designer draws from the preview data.
@MainActor
enum DesignerPreview {
    /// The preview fields with the stock-picture marker swapped for a real image the renderer can load.
    static func fields(_ model: DesignerModel) -> [String: HeraldFieldValue] {
        var f = model.previewFields
        if let stock = PreviewRenderer.placeholderImageSpec {
            for (k, v) in f { if case .text(let s) = v, s == DesignerModel.sampleImage { f[k] = .text(stock) } }
        }
        return f
    }

    /// `live` lets Rive components run; the editing canvas draws a placeholder instead.
    static func bannerModel(_ model: DesignerModel, appName: String, icon: NSImage, live: Bool) -> BannerModel {
        let fields = fields(model)
        let note = model.previewNotification()
        let real = model.previewSource == .lastReal ? model.lastItem : nil
        let item = HeraldHistoryItem(id: note.id ?? "designer-preview", app: model.app, notification: note,
                                     deliveredAt: real?.deliveredAt ?? Date(), imagePath: real?.imagePath, fields: fields)
        let cached = real?.imagePath.flatMap { NSImage(contentsOfFile: $0) }
        let bm = BannerModel(item: item, appName: appName, icon: icon, image: cached,
                             template: model.draft, manifest: model.manifest, fields: fields)
        bm.liveAnimations = live
        return bm
    }
}

/// A desktop-like backdrop (the translucent banner card looks flat on a plain window).
struct DesignerBackdrop: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        LinearGradient(
            colors: scheme == .dark
                ? [Color(red: 0.10, green: 0.12, blue: 0.22), Color(red: 0.24, green: 0.14, blue: 0.30)]
                : [Color(red: 0.62, green: 0.78, blue: 0.95), Color(red: 0.93, green: 0.80, blue: 0.88)],
            startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

// MARK: - Canvas

struct GridCanvasView: View {
    @ObservedObject var model: DesignerModel
    let appName: String
    let icon: NSImage
    @Environment(\.colorScheme) private var scheme
    @State private var origins: [GridSlot: CGPoint] = [:]

    var body: some View {
        let banner = DesignerPreview.bannerModel(model, appName: appName, icon: icon, live: false)
        let state = GridRenderState(model: banner, scheme: scheme)
        GeometryReader { geo in
            ScrollView([.horizontal, .vertical]) {
                VStack(spacing: 10) {
                    card(state)
                    Text("\(model.grid.cols) \u{00D7} \(model.grid.rows) grid \u{00B7} \(Int(GridSolver.clampedWidth(model.grid.width))) pt wide")
                        .font(.caption2).foregroundStyle(.white.opacity(0.85))
                        .shadow(color: .black.opacity(0.35), radius: 2)
                }
                .padding(32)
                .frame(minWidth: geo.size.width, minHeight: geo.size.height)
                .background { Color.clear.contentShape(Rectangle()).onTapGesture { model.clearSelection() } }
            }
        }
        .background(DesignerBackdrop())
    }

    private var slots: [GridSlot] {
        let g = model.grid
        return (0..<max(g.rows, 0)).flatMap { r in (0..<max(g.cols, 0)).map { GridSlot(r, $0) } }
    }

    private func card(_ state: GridRenderState) -> some View {
        let real = model.draft.cells
        let empties = slots.filter { GridEditing.cell(at: $0, in: model.draft) == nil }
        let all = real
            + empties.map { HeraldCell(id: "designer-empty-\($0.row)-\($0.col)", row: $0.row, col: $0.col, component: .spacer) }
            + slots.map { HeraldCell(id: "designer-probe-\($0.row)-\($0.col)", row: $0.row, col: $0.col, component: .spacer) }
        let slotAt: (CGPoint) -> GridSlot = { p in slot(at: p) }
        return GridCanvasLayout(grid: model.grid, cells: all, plan: HeraldGridPlan(),
                                width: GridSolver.clampedWidth(model.grid.width)) {
            ForEach(all.indices, id: \.self) { i in
                if i < real.count {
                    DesignerCellView(model: model, cell: real[i], ctx: state.ctx, slotAt: slotAt)
                        .layoutValue(key: GridCellIndexKey.self, value: i)
                } else if i < real.count + empties.count {
                    EmptySlotView(model: model, slot: empties[i - real.count], slotAt: slotAt)
                        .layoutValue(key: GridCellIndexKey.self, value: i)
                } else {
                    SlotProbe(slot: slots[i - real.count - empties.count])
                        .layoutValue(key: GridCellIndexKey.self, value: i)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.regularMaterial)
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.primary.opacity(0.12)))
                .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
                .padding(-0.5))
        .coordinateSpace(name: DesignerCanvasSpace.name)
        .onPreferenceChange(SlotOriginKey.self) { origins = $0 }
    }

    /// The slot under a point in the canvas coordinate space: the last column and row that start at or before it.
    private func slot(at p: CGPoint) -> GridSlot {
        let g = model.grid
        var col = 0, row = 0
        for c in 0..<max(g.cols, 1) { if let o = origins[GridSlot(0, c)], o.x <= p.x + 1 { col = c } }
        for r in 0..<max(g.rows, 1) { if let o = origins[GridSlot(r, 0)], o.y <= p.y + 1 { row = r } }
        return GridSlot(row, col)
    }
}

/// A zero-size cell at every slot: it reports where the slot starts and takes no space.
private struct SlotProbe: View {
    let slot: GridSlot
    var body: some View {
        Color.clear.frame(width: 0, height: 0)
            .background {
                GeometryReader { g in
                    Color.clear.preference(key: SlotOriginKey.self,
                                           value: [slot: g.frame(in: .named(DesignerCanvasSpace.name)).origin])
                }
            }
    }
}

// MARK: - Cells

/// One cell of the template: its component as the banner draws it, with the editing layer on top.
struct DesignerCellView: View {
    @ObservedObject var model: DesignerModel
    let cell: HeraldCell
    let ctx: GridContext
    let slotAt: (CGPoint) -> GridSlot

    /// Empty as the live renderer sees it: no bound value, or a picture nothing can load.
    private var isEmpty: Bool {
        if !cell.component.hasContent(fields: ctx.fields, actions: ctx.actions) { return true }
        if case .image(let i) = cell.component {
            return ctx.image(forBinding: i.binding) == nil && ctx.remoteImageURL(forBinding: i.binding) == nil
        }
        return false
    }

    var body: some View {
        let empty = isEmpty
        let rect = GridEditing.rect(of: cell, in: model.grid) ?? SlotRect(row: cell.row, col: cell.col)
        Group {
            if empty { EmptyMarker(cell: cell, behavior: model.draft.behavior(for: cell.component)) }
            else if case .spacer = cell.component { SpacerMarker() }
            else { DesignerComponent.view(cell.component, ctx: ctx, align: cell.align) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: cell.align.alignment)
        .clipped()
        .allowsHitTesting(false)
        .overlay {
            SlotChrome(model: model, rect: rect, cellID: cell.id,
                       label: "\(cell.id) \u{00B7} \(DesignerPalette.title(for: cell.component.typeName).lowercased())",
                       slotAt: slotAt)
                .padding(-max(cell.padding, 0))
        }
    }
}

/// An empty slot: a droppable, selectable hole in the grid.
struct EmptySlotView: View {
    @ObservedObject var model: DesignerModel
    let slot: GridSlot
    let slotAt: (CGPoint) -> GridSlot

    var body: some View {
        Color.clear.frame(width: 34, height: 34)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay { SlotChrome(model: model, rect: SlotRect(slot), cellID: nil, label: "", slotAt: slotAt) }
    }
}

/// Stand-in for a component with nothing to show: what it is bound to, and what happens to it.
private struct EmptyMarker: View {
    let cell: HeraldCell
    let behavior: HeraldEmptyBehavior

    private var title: String {
        cell.component.referencedTokens.first.map { "{\($0)}" } ?? DesignerPalette.title(for: cell.component.typeName).lowercased()
    }

    var body: some View {
        VStack(spacing: 1) {
            Text(title).font(.system(size: 10, design: .monospaced)).lineLimit(1).minimumScaleFactor(0.7)
            Text(behavior == .collapse ? "empty \u{00B7} collapses" : "empty \u{00B7} space kept")
                .font(.system(size: 8.5)).lineLimit(1).minimumScaleFactor(0.7)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 4)
        .frame(minWidth: 34, minHeight: 30)
        .background(RoundedRectangle(cornerRadius: 3).fill(Color.secondary.opacity(behavior == .collapse ? 0.05 : 0.12)))
        .opacity(behavior == .collapse ? 0.7 : 1)
    }
}

/// A merged region waiting for a component.
private struct SpacerMarker: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 3).fill(Color.secondary.opacity(0.08))
            Text("spacer").font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(minWidth: 22, minHeight: 20)
    }
}

// MARK: - Component rendering

/// The one place that maps a component to the renderer's view for it (mirrors `GridBannerView`).
enum DesignerComponent {
    @MainActor @ViewBuilder
    static func view(_ c: HeraldComponent, ctx: GridContext, align: HeraldAlign) -> some View {
        switch c {
        case .text(let p): TextComponentView(component: p, ctx: ctx, align: align)
        case .image(let p): ImageComponentView(component: p, ctx: ctx)
        case .issuerIcon(let p): IssuerIconComponentView(component: p, ctx: ctx)
        case .timestamp(let p): TimestampComponentView(component: p, ctx: ctx)
        case .button(let p): ButtonComponentView(component: p, ctx: ctx)
        case .actions(let p): ActionsComponentView(component: p, ctx: ctx)
        case .iconButton(let p): IconButtonComponentView(component: p, ctx: ctx)
        case .badge(let p): BadgeComponentView(component: p, ctx: ctx)
        case .progress(let p): ProgressComponentView(component: p, ctx: ctx)
        case .rive(let p): RiveSlotView(component: p, ctx: ctx)
        case .spacer: Color.clear.frame(width: 0, height: 0)
        }
    }
}

// MARK: - Editing layer

/// Selection outline, drag source, drop target and span handles of one slot or cell.
struct SlotChrome: View {
    @ObservedObject var model: DesignerModel
    let rect: SlotRect
    /// nil for an empty slot.
    let cellID: String?
    let label: String
    let slotAt: (CGPoint) -> GridSlot
    @State private var targeted = false

    private var selected: Bool { model.selection?.contains(rect) ?? false }
    private var primary: Bool { model.selection == rect }
    private var hasError: Bool { cellID.map { id in model.issues.contains { $0.cellId == id && $0.isError } } ?? false }

    private var stroke: Color {
        if targeted || selected { return .accentColor }
        if hasError { return .red }
        return Color.secondary.opacity(cellID == nil ? 0.30 : 0.38)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(targeted ? Color.accentColor.opacity(0.22) : selected ? Color.accentColor.opacity(0.09) : .clear)
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .strokeBorder(stroke, style: StrokeStyle(lineWidth: selected || targeted ? 1.5 : 0.75,
                                                         dash: selected || targeted ? [] : [3, 3]))
            if cellID == nil, !selected, !targeted {
                Image(systemName: "plus").font(.system(size: 10, weight: .light)).foregroundStyle(.secondary.opacity(0.5))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            if primary, let id = cellID {
                SpanHandle(model: model, cellID: id, axis: .cols, slotAt: slotAt)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                SpanHandle(model: model, cellID: id, axis: .rows, slotAt: slotAt)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                SpanHandle(model: model, cellID: id, axis: .both, slotAt: slotAt)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { model.select(slot: rect.origin, extend: NSEvent.modifierFlags.contains(.shift)) }
        .modifier(CellDrag(payload: cellID.map { DragPayload.cell($0).string }, label: label))
        .dropDestination(for: String.self, action: { items, _ in drop(items) }, isTargeted: { targeted = $0 })
        .contextMenu { menu }
    }

    private func drop(_ items: [String]) -> Bool {
        guard let payload = items.lazy.compactMap({ DragPayload(string: $0) }).first else { return false }
        model.handle(payload, at: rect.origin)
        return true
    }

    @ViewBuilder private var menu: some View {
        if let id = cellID {
            Button("Duplicate") { model.select(cell: id); model.duplicateSelection() }
            if rect.area > 1 { Button("Split") { model.select(cell: id); model.splitSelection() } }
            Button("Delete") { model.select(cell: id); model.deleteSelection() }
        } else {
            Text("Empty slot")
        }
        if let sel = model.selection, sel.contains(rect), model.canMerge {
            Divider()
            Button("Merge Selected Slots") { model.mergeSelection() }
        }
    }
}

/// Makes a cell draggable (to another cell, to swap or move it); empty slots are not.
private struct CellDrag: ViewModifier {
    let payload: String?
    let label: String
    @ViewBuilder func body(content: Content) -> some View {
        if let payload {
            content.draggable(payload) {
                Text(label).font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Capsule().fill(Color.accentColor.opacity(0.9))).foregroundStyle(.white)
            }
        } else {
            content
        }
    }
}

/// Resizes the selected cell's span by dragging: the right edge (columns), the bottom edge (rows) or the
/// corner (both). The cell snaps to track boundaries and stops at neighbours (`GridEditing.resize`).
struct SpanHandle: View {
    enum Axis { case rows, cols, both }
    @ObservedObject var model: DesignerModel
    let cellID: String
    let axis: Axis
    let slotAt: (CGPoint) -> GridSlot
    @State private var active = false

    private var shape: some View {
        Group {
            switch axis {
            case .both: Circle().fill(Color.accentColor).overlay(Circle().strokeBorder(.white, lineWidth: 1.5)).frame(width: 11, height: 11)
            case .cols: Capsule().fill(Color.accentColor).frame(width: 4, height: 16)
            case .rows: Capsule().fill(Color.accentColor).frame(width: 16, height: 4)
            }
        }
        .padding(axis == .both ? 1 : 0)
        .contentShape(Rectangle().inset(by: -4))
    }

    var body: some View {
        shape
            .help(axis == .both ? "Drag to resize" : axis == .cols ? "Drag to span columns" : "Drag to span rows")
            .gesture(DragGesture(minimumDistance: 2, coordinateSpace: .named(DesignerCanvasSpace.name))
                .onChanged { v in
                    guard let r = GridEditing.rect(ofCell: cellID, in: model.draft) else { return }
                    let s = slotAt(v.location)
                    let rows = axis == .cols ? r.rowSpan : max(1, s.row - r.row + 1)
                    let cols = axis == .rows ? r.colSpan : max(1, s.col - r.col + 1)
                    guard rows != r.rowSpan || cols != r.colSpan else { return }
                    if !active { active = true; model.beginGesture() }
                    model.resizeLive(cell: cellID, rowSpan: rows, colSpan: cols)
                }
                .onEnded { _ in active = false })
    }
}
