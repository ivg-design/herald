import SwiftUI
import AppKit
import UniformTypeIdentifiers

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

/// The area all tracks cover, in the canvas coordinate space (reported by one probe cell that spans the whole grid).
/// Its far edges are where the last column and the last row end, and the card is that plus the padding.
struct GridExtentKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next != .zero { value = next }
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
    @State private var extent: CGRect = .zero
    /// The track whose canvas handle is being dragged, with its live size in points (the readout).
    @State private var trackDrag: TrackDrag?

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
                .padding(.horizontal, 72).padding(.top, 40).padding(.bottom, 32)
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

    /// The card's size: the tracks' extent plus the grid's padding on every side (zero until the layout has reported).
    private var cardSize: CGSize {
        guard extent != .zero else { return .zero }
        let p = CGFloat(max(model.grid.padding, 0))
        return CGSize(width: extent.maxX + p, height: extent.maxY + p)
    }

    private func card(_ state: GridRenderState) -> some View {
        let real = model.draft.cells
        let empties = slots.filter { GridEditing.cell(at: $0, in: model.draft) == nil }
        let all = real
            + empties.map { HeraldCell(id: "designer-empty-\($0.row)-\($0.col)", row: $0.row, col: $0.col, component: .spacer) }
            + slots.map { HeraldCell(id: "designer-probe-\($0.row)-\($0.col)", row: $0.row, col: $0.col, component: .spacer) }
            + (model.grid.rows > 0 && model.grid.cols > 0
               ? [HeraldCell(id: "designer-extent", row: 0, col: 0, rowSpan: model.grid.rows, colSpan: model.grid.cols, component: .spacer)] : [])
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
                } else if i < real.count + empties.count + slots.count {
                    SlotProbe(slot: slots[i - real.count - empties.count])
                        .layoutValue(key: GridCellIndexKey.self, value: i)
                } else {
                    ExtentProbe().layoutValue(key: GridCellIndexKey.self, value: i)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.regularMaterial)
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.primary.opacity(0.12)))
                .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
                .padding(-0.5))
        .overlay { CanvasGuides(model: model, origins: origins, card: cardSize, drag: trackDrag).allowsHitTesting(false) }
        .overlay(alignment: .topLeading) {
            TrackRulers(model: model, origins: origins, card: cardSize, drag: $trackDrag)
        }
        .coordinateSpace(name: DesignerCanvasSpace.name)
        .onPreferenceChange(SlotOriginKey.self) { origins = $0 }
        .onPreferenceChange(GridExtentKey.self) { extent = $0 }
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

/// Spans the whole grid and reports the area the tracks cover. It has no size of its own that could move a track
/// (a spanning cell only lends its excess to auto tracks, and this one asks for next to nothing).
private struct ExtentProbe: View {
    var body: some View {
        Color.clear.frame(minWidth: 0, minHeight: 0)
            .background {
                GeometryReader { g in
                    Color.clear.preference(key: GridExtentKey.self, value: g.frame(in: .named(DesignerCanvasSpace.name)))
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
        // The cell is exactly its track (FitToProposal), whatever its content or annotation would like to be.
        FitToProposal {
            Group {
                if empty { EmptyMarker(cell: cell, behavior: model.draft.behavior(for: cell.component)) }
                else if case .spacer = cell.component { SpacerMarker() }
                else { DesignerComponent.view(cell.component, ctx: ctx, align: cell.align) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: cell.align.alignment)
        }
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
        EmptySlotLayout {
            SlotChrome(model: model, rect: SlotRect(slot), cellID: nil, label: "", slotAt: slotAt)
        }
    }
}

/// Sizes the placeholder with `EmptySlotSizing`: the ideal drop target when nothing is proposed, otherwise exactly
/// the track's size (a fixed 16 pt row must not get a 34 pt placeholder that overlaps the row below).
private struct EmptySlotLayout: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let s = EmptySlotSizing.size(width: proposal.width.map(Double.init), height: proposal.height.map(Double.init))
        return CGSize(width: s.width, height: s.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for sub in subviews {
            sub.place(at: bounds.origin, anchor: .topLeading, proposal: ProposedViewSize(bounds.size))
        }
    }
}

/// Sizes its one child with `CellFitSizing`: the proposal where there is one, the child's own size otherwise.
struct FitToProposal: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let own = subviews.first?.sizeThatFits(proposal) ?? .zero
        let s = CellFitSizing.size(proposedWidth: proposal.width.map(Double.init), proposedHeight: proposal.height.map(Double.init),
                                   content: (Double(own.width), Double(own.height)))
        return CGSize(width: s.width, height: s.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for sub in subviews {
            sub.place(at: bounds.origin, anchor: .topLeading, proposal: ProposedViewSize(bounds.size))
        }
    }
}

/// Stand-in for a component with nothing to show: what it is bound to, and what happens to it.
private struct EmptyMarker: View {
    let cell: HeraldCell
    let behavior: HeraldEmptyBehavior

    private var title: String {
        cell.component.referencedTokens.first.map { "{\($0)}" } ?? DesignerPalette.title(for: cell.component.typeName).lowercased()
    }

    private var note: String { behavior == .collapse ? "empty \u{00B7} collapses" : "empty \u{00B7} space kept" }

    /// The labels are an overlay: they are drawn inside whatever size the cell has, never add to it, and the
    /// second line only appears when there is room for it (the tooltip always says it).
    var body: some View {
        RoundedRectangle(cornerRadius: 3).fill(Color.secondary.opacity(behavior == .collapse ? 0.05 : 0.12))
            .frame(minWidth: 34, minHeight: 30)
            .overlay {
                GeometryReader { g in
                    VStack(spacing: 1) {
                        Text(title).font(.system(size: 10, design: .monospaced)).lineLimit(1).minimumScaleFactor(0.7)
                        if g.size.height >= 28 {
                            Text(note).font(.system(size: 8.5)).lineLimit(1).minimumScaleFactor(0.7)
                        }
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
                    .frame(width: g.size.width, height: g.size.height)
                }
            }
            .opacity(behavior == .collapse ? 0.7 : 1)
            .help("\(title): \(note)")
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
        case .stackBadge(let p): StackBadgeComponentView(component: p, ctx: ctx)
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

    /// A drag is over this slot or cell (the canvas draws the landing area and what the drop will do).
    private var targeted: Bool { model.dropTarget?.rect == rect }
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
        .modifier(CellDrag(model: model, payload: cellID.map { DragPayload.cell($0) }, label: label))
        .onDrop(of: DesignerDrag.types, delegate: SlotDropDelegate(model: model, slot: rect.origin))
        .contextMenu { menu }
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
    @ObservedObject var model: DesignerModel
    let payload: DragPayload?
    let label: String
    @ViewBuilder func body(content: Content) -> some View {
        if let payload {
            content.onDrag {
                model.dragging = payload
                return DesignerDrag.provider(payload)
            } preview: {
                DragChipLabel(text: label)
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


// MARK: - Drag and drop (issue #38)

/// What a drag carries: the payload as plain text, in an `NSItemProvider`, so any drop target that reads text
/// sees something sensible and anything else dropped on the canvas is ignored (it does not decode).
enum DesignerDrag {
    static let types: [UTType] = [.plainText]

    static func provider(_ payload: DragPayload) -> NSItemProvider {
        NSItemProvider(object: payload.string as NSString)
    }
}

/// The small pill that follows the pointer while a chip or cell is dragged.
struct DragChipLabel: View {
    let text: String
    var body: some View {
        Text(text).font(.system(size: 11, weight: .medium)).lineLimit(1)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Capsule().fill(Color.accentColor.opacity(0.9))).foregroundStyle(.white)
    }
}

/// The drop target of one slot or cell. It tells the model which slot is under the pointer (the model works out
/// what dropping would do, and the canvas draws it) and applies the payload on drop.
struct SlotDropDelegate: DropDelegate {
    let model: DesignerModel
    let slot: GridSlot

    func validateDrop(info: DropInfo) -> Bool { info.hasItemsConforming(to: DesignerDrag.types) }

    func dropEntered(info: DropInfo) { model.hoverDrop(at: slot) }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        if model.dropTarget?.allowed == false { return DropProposal(operation: .forbidden) }
        if case .cell? = model.dragging { return DropProposal(operation: .move) }
        return DropProposal(operation: .copy)
    }

    func dropExited(info: DropInfo) { model.leaveDrop(at: slot) }

    func performDrop(info: DropInfo) -> Bool {
        guard let item = info.itemProviders(for: DesignerDrag.types).first else { model.endDrag(); return false }
        let model = model, slot = slot
        _ = item.loadObject(ofClass: NSString.self) { object, _ in
            let text = (object as? NSString).map(String.init)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let text, let payload = DragPayload(string: text) else { model.endDrag(); return }
                    model.handle(payload, at: slot)
                }
            }
        }
        return true
    }
}

/// Where a drop would land and what it would do: the target area outlined (red when the drop is refused) with a
/// label, drawn over the card. Looks at nothing but the model's `dropTarget`.
private struct CanvasGuides: View {
    @ObservedObject var model: DesignerModel
    let origins: [GridSlot: CGPoint]
    let card: CGSize
    let drag: TrackDrag?

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let t = model.dropTarget, let f = CanvasGeometry.frame(of: t.rect, origins: origins, card: card, grid: model.grid) {
                let tint: Color = t.allowed ? .accentColor : .red
                RoundedRectangle(cornerRadius: 4, style: .continuous).fill(tint.opacity(0.20))
                    .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(tint, style: StrokeStyle(lineWidth: 2, dash: t.allowed ? [] : [5, 3])))
                    .frame(width: f.width, height: f.height)
                    .offset(x: f.minX, y: f.minY)
                Text(t.verb).font(.system(size: 10.5, weight: .semibold)).foregroundStyle(.white).lineLimit(1).fixedSize()
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(Capsule().fill(tint))
                    .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
                    .position(x: min(max(f.midX, 40), max(card.width - 40, 40)), y: max(f.minY - 12, 10))
            }
            if let d = drag, let f = CanvasGeometry.trackFrame(columns: d.columns, index: d.index, origins: origins, card: card, grid: model.grid) {
                Rectangle().fill(Color.accentColor.opacity(0.9))
                    .frame(width: d.columns ? 1 : card.width, height: d.columns ? card.height : 1)
                    .offset(x: d.columns ? f.start + f.length : 0, y: d.columns ? 0 : f.start + f.length)
            }
        }
        .frame(width: card.width, height: card.height, alignment: .topLeading)
    }
}

// MARK: - Track rulers (issue #38)

/// A handle being dragged: which track, and the size it would have, in points.
struct TrackDrag: Equatable {
    var columns: Bool
    var index: Int
    var points: Double
}

/// Where the tracks sit on the card, worked out from where the slots start (the layout's own answer, so it is
/// right for auto and fill tracks too).
enum CanvasGeometry {
    struct Span: Equatable { var start: CGFloat; var length: CGFloat }

    static func trackFrame(columns: Bool, index i: Int, origins: [GridSlot: CGPoint], card: CGSize, grid g: HeraldGrid) -> Span? {
        let count = columns ? g.cols : g.rows
        guard i >= 0, i < count, card.width > 0, card.height > 0 else { return nil }
        func at(_ k: Int) -> CGFloat? {
            guard let o = origins[columns ? GridSlot(0, k) : GridSlot(k, 0)] else { return nil }
            return columns ? o.x : o.y
        }
        guard let start = at(i) else { return nil }
        let end: CGFloat
        if i + 1 < count { guard let next = at(i + 1) else { return nil }; end = next - CGFloat(max(g.gap, 0)) }
        else { end = (columns ? card.width : card.height) - CGFloat(max(g.padding, 0)) }
        return Span(start: start, length: max(end - start, 0))
    }

    static func frame(of r: SlotRect, origins: [GridSlot: CGPoint], card: CGSize, grid g: HeraldGrid) -> CGRect? {
        guard let c0 = trackFrame(columns: true, index: r.col, origins: origins, card: card, grid: g),
              let c1 = trackFrame(columns: true, index: min(r.lastCol, g.cols - 1), origins: origins, card: card, grid: g),
              let r0 = trackFrame(columns: false, index: r.row, origins: origins, card: card, grid: g),
              let r1 = trackFrame(columns: false, index: min(r.lastRow, g.rows - 1), origins: origins, card: card, grid: g) else { return nil }
        return CGRect(x: c0.start, y: r0.start, width: c1.start + c1.length - c0.start, height: r1.start + r1.length - r0.start)
    }
}

/// The strips above and left of the card: each column and row with its size (points, or fill / auto with what
/// it comes to) and a handle on its trailing edge. Dragging the handle gives the track a fixed size with a live
/// readout and a guide across the card; a double click puts it back (fill / auto); the label's menu sets
/// auto, fill or the current size.
private struct TrackRulers: View {
    @ObservedObject var model: DesignerModel
    let origins: [GridSlot: CGPoint]
    let card: CGSize
    @Binding var drag: TrackDrag?

    static let band: CGFloat = 18
    static let rowBand: CGFloat = 60
    static let gapToCard: CGFloat = 5
    static let handle: CGFloat = 14

    var body: some View {
        let g = model.grid
        let gap = CGFloat(max(g.gap, 0))
        ZStack(alignment: .topLeading) {
            ForEach(0..<max(g.cols, 0), id: \.self) { i in
                if let f = CanvasGeometry.trackFrame(columns: true, index: i, origins: origins, card: card, grid: g) {
                    TrackLabel(model: model, columns: true, index: i, length: f.length, drag: drag)
                        .frame(width: max(f.length - 2, 1), height: Self.band)
                        .offset(x: f.start + 1, y: -(Self.band + Self.gapToCard))
                    TrackHandle(model: model, columns: true, index: i, length: f.length, drag: $drag)
                        .frame(width: Self.handle, height: Self.band)
                        .offset(x: f.start + f.length + (i + 1 < g.cols ? gap / 2 : 0) - Self.handle / 2, y: -(Self.band + Self.gapToCard))
                }
            }
            ForEach(0..<max(g.rows, 0), id: \.self) { i in
                if let f = CanvasGeometry.trackFrame(columns: false, index: i, origins: origins, card: card, grid: g) {
                    TrackLabel(model: model, columns: false, index: i, length: f.length, drag: drag)
                        .frame(width: Self.rowBand, height: max(f.length - 2, 1))
                        .offset(x: -(Self.rowBand + Self.gapToCard), y: f.start + 1)
                    TrackHandle(model: model, columns: false, index: i, length: f.length, drag: $drag)
                        .frame(width: Self.rowBand, height: Self.handle)
                        .offset(x: -(Self.rowBand + Self.gapToCard), y: f.start + f.length + (i + 1 < g.rows ? gap / 2 : 0) - Self.handle / 2)
                }
            }
        }
    }
}

/// The size of one column or row. Clicking opens a menu to make it auto, fill or fixed at what it is now.
private struct TrackLabel: View {
    @ObservedObject var model: DesignerModel
    let columns: Bool
    let index: Int
    /// The track's size on screen now.
    let length: CGFloat
    let drag: TrackDrag?

    private var size: HeraldSize { columns ? model.grid.colSize(at: index) : model.grid.rowSize(at: index) }
    private var live: Bool { drag.map { $0.columns == columns && $0.index == index } ?? false }

    private var text: String {
        if live, let d = drag { return "\(columns ? "W" : "H") \(Int(d.points)) pt" }
        let now = Int(length.rounded())
        switch size {
        case .points(let p): return "\(Int(p.rounded())) pt"
        case .fill: return "fill \u{00B7} \(now)"
        case .auto: return "auto \u{00B7} \(now)"
        }
    }

    var body: some View {
        Menu {
            Button("Auto (fit the content)") { model.edit { _ = GridEditing.setTrack(columns: columns, index: index, size: .auto, in: &$0) } }
            Button("Fill (share what is left)") { model.edit { _ = GridEditing.setTrack(columns: columns, index: index, size: .fill, in: &$0) } }
            Button("Fixed at \(Int(length.rounded())) pt") {
                model.edit { _ = GridEditing.setTrack(columns: columns, index: index, size: .points(Double(length)), in: &$0) }
            }
        } label: {
            Text(text)
                .font(.system(size: 9, weight: live ? .bold : .medium, design: .monospaced))
                .lineLimit(1).minimumScaleFactor(0.55)
                .foregroundStyle(live ? Color.white : Color.primary.opacity(0.85))
                .padding(.horizontal, 3)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(live ? Color.accentColor : Color(nsColor: .windowBackgroundColor).opacity(0.80)))
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden)
        .help("\(columns ? "Column" : "Row") \(index + 1): drag the handle to resize, double-click it to reset")
        .accessibilityLabel("\(columns ? "Column" : "Row") \(index + 1), \(text)")
    }
}

/// The grab point on a track's trailing edge (right of a column, bottom of a row).
private struct TrackHandle: View {
    @ObservedObject var model: DesignerModel
    let columns: Bool
    let index: Int
    /// How long the track is now, along its axis.
    let length: CGFloat
    @Binding var drag: TrackDrag?
    /// Where the pointer and the track's size were when the grab began, so the size follows the pointer's
    /// movement instead of jumping to wherever on the handle it was grabbed.
    @State private var grab: (along: CGFloat, length: CGFloat)?

    private var live: Bool { drag.map { $0.columns == columns && $0.index == index } ?? false }

    var body: some View {
        ZStack {
            Capsule().fill(live ? Color.accentColor : Color.secondary.opacity(0.8))
                .frame(width: columns ? 4 : 16, height: columns ? 14 : 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { model.resetTrack(columns: columns, index: index) }
        .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .named(DesignerCanvasSpace.name))
            .onChanged { v in
                if grab == nil {
                    model.beginGesture()
                    grab = (columns ? v.startLocation.x : v.startLocation.y, length)
                }
                guard let g = grab else { return }
                let along = columns ? v.location.x : v.location.y
                let points = GridEditing.clampedPoints(Double(g.length + (along - g.along)), columns: columns, in: model.grid)
                let next = TrackDrag(columns: columns, index: index, points: points)
                if drag != next { drag = next; model.resizeTrackLive(columns: columns, index: index, points: points) }
            }
            .onEnded { _ in drag = nil; grab = nil })
        .help("Drag to resize, double-click to reset")
        .accessibilityLabel("Resize \(columns ? "column" : "row") \(index + 1)")
    }
}
