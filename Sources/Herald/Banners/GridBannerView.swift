import SwiftUI
import AppKit

// The v2 banner renderer (DESIGN 7.2). One `GridBannerView` draws every banner: live panels, the composer and
// designer previews, history rows and the `/v1/preview` PNG. A template's grid of cells is laid out by
// `GridCanvasLayout`, which feeds real measurements to the pure `GridSolver` (Core/GridLayout.swift) and
// places each cell's component where the solver says. The card chrome (material, border, tint, height
// report) belongs to `BannerView`, which wraps this view.

// MARK: - Layout

/// Which entry of `GridRenderState.cells` a subview draws.
struct GridCellIndexKey: LayoutValueKey {
    static let defaultValue: Int = -1
}

struct GridCanvasLayout: Layout {
    var grid: HeraldGrid
    var cells: [HeraldCell]
    var plan: HeraldGridPlan
    var width: Double

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let s = solve(subviews)
        return CGSize(width: s.width, height: s.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let s = solve(subviews)
        for sub in subviews {
            let i = sub[GridCellIndexKey.self]
            guard cells.indices.contains(i), let f = s.frames[i] else { continue }
            let pad = max(cells[i].padding, 0)
            sub.place(at: CGPoint(x: bounds.minX + f.x + pad, y: bounds.minY + f.y + pad), anchor: .topLeading,
                      proposal: ProposedViewSize(width: max(f.width - 2 * pad, 0), height: max(f.height - 2 * pad, 0)))
        }
    }

    private func solve(_ subviews: Subviews) -> GridSolution {
        var byCell: [Int: LayoutSubview] = [:]
        for sub in subviews {
            let i = sub[GridCellIndexKey.self]
            if cells.indices.contains(i) { byCell[i] = sub }
        }
        // Only cells that have a subview are drawn; a cell without one (the model collapsed it) is skipped by
        // the plan already, so this just keeps a stray index from reaching the solver.
        let measure = GridMeasure(
            idealWidth: { Double(byCell[$0]?.sizeThatFits(.unspecified).width ?? 0) },
            height: { Double(byCell[$0]?.sizeThatFits(ProposedViewSize(width: CGFloat($1), height: nil)).height ?? 0) })
        return GridSolver.solve(grid: grid, cells: cells, plan: plan, width: width, measure: measure)
    }
}

// MARK: - Render state

/// What one pass of drawing needs, worked out from the model: which cells are empty, what collapses, and the
/// context the components read. Rebuilt on every body evaluation; it is a handful of dictionary lookups.
struct GridRenderState {
    let template: HeraldTemplate
    let grid: HeraldGrid
    var cells: [HeraldCell] { template.cells }
    let plan: HeraldGridPlan
    /// Indices into `cells` of the cells that are drawn (not collapsed).
    let liveIndices: [Int]
    let ctx: GridContext

    @MainActor
    init(model: BannerModel, scheme: ColorScheme) {
        let t = model.grid
        template = t
        grid = t.grid ?? .standard
        let n = model.item.notification
        let ctx = GridContext(
            fields: model.fields, actions: model.actions, notification: n, appName: model.appName, icon: model.icon,
            cachedImage: model.image, deliveredAt: model.item.deliveredAt, accent: model.accent(dark: scheme == .dark),
            scheme: scheme, maxBodyLines: model.maxBodyLines, reminderState: model.reminderState,
            hovering: model.hovering, manifest: model.manifest, offscreen: !model.liveAnimations,
            perform: { [weak model] a, o in model?.perform(a, origin: o) },
            snooze: { [weak model] in model?.onSnooze($0) },
            addReminder: { [weak model] in model?.onReminder() },
            dismiss: { [weak model] in model?.onClose() })
        self.ctx = ctx

        var empty = t.emptyCellIDs(fields: ctx.fields, actions: ctx.actions)
        for c in t.cells {
            switch c.component {
            case .image(let i):
                // Content the fields name but nothing can show (a missing file, a failed download) is empty too.
                if !empty.contains(c.id), ctx.image(forBinding: i.binding) == nil,
                   ctx.remoteImageURL(forBinding: i.binding) == nil {
                    empty.insert(c.id)
                }
            case .actions(let a):
                // Add to Reminders lives in the action row: a notification that has a reminder keeps it alive.
                if n.reminder != nil, a.source != .template { empty.remove(c.id) }
            default:
                break
            }
        }
        let plan = t.plan(emptyCells: empty)
        self.plan = plan
        liveIndices = t.cells.indices.filter { !plan.isCollapsed(cell: t.cells[$0].id) }
    }
}

// MARK: - View

struct GridBannerView: View {
    @ObservedObject var model: BannerModel
    /// True inside a live banner panel: a notification that has speech then carries a replay control, beside the
    /// timestamp (the meta column) or, when the template draws none, in a thin row under the grid.
    var showsReplay = false
    @ObservedObject private var voice = VoiceCoordinator.shared
    @Environment(\.colorScheme) private var scheme
    /// Set by the link action so the banner's tap gesture (open url + dismiss) can tell it was a link click.
    @State private var linkClickedAt: Date = .distantPast

    var body: some View {
        let state = GridRenderState(model: model, scheme: scheme)
        let speech = showsReplay ? voice.speech(app: model.item.app, id: model.item.id) : nil
        let replayCell = speech == nil ? nil : state.liveIndices.first { i in
            if case .timestamp = state.cells[i].component { return true }
            return false
        }
        VStack(spacing: 0) {
            GridCanvasLayout(grid: state.grid, cells: state.cells, plan: state.plan, width: model.bannerWidth) {
                ForEach(state.liveIndices, id: \.self) { i in
                    let cell = state.cells[i]
                    component(of: cell, state.ctx, replay: i == replayCell ? speech : nil)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: cell.align.alignment)
                        .clipped()
                        .modifier(SwallowTaps(active: Self.isInteractive(cell.component)))
                        .layoutValue(key: GridCellIndexKey.self, value: i)
                }
            }
            if let speech, replayCell == nil {
                BannerReplayStrip(app: model.item.app, id: model.item.id, speech: speech, inset: state.grid.padding)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { bannerTapped() }
        .environment(\.openURL, linkAction)
    }

    @ViewBuilder private func component(of cell: HeraldCell, _ ctx: GridContext, replay: HeraldSpeech? = nil) -> some View {
        switch cell.component {
        case .text(let c): TextComponentView(component: c, ctx: ctx, align: cell.align)
        case .image(let c): ImageComponentView(component: c, ctx: ctx)
        case .issuerIcon(let c): IssuerIconComponentView(component: c, ctx: ctx)
        case .timestamp(let c):
            if let replay {
                HStack(spacing: 3) {
                    BannerReplayButton(app: model.item.app, id: model.item.id, speech: replay)
                    TimestampComponentView(component: c, ctx: ctx)
                }
            } else {
                TimestampComponentView(component: c, ctx: ctx)
            }
        case .button(let c): ButtonComponentView(component: c, ctx: ctx)
        case .actions(let c): ActionsComponentView(component: c, ctx: ctx)
        case .iconButton(let c): IconButtonComponentView(component: c, ctx: ctx)
        case .badge(let c): BadgeComponentView(component: c, ctx: ctx)
        case .progress(let c): ProgressComponentView(component: c, ctx: ctx)
        case .rive(let c): RiveSlotView(component: c, ctx: ctx)
        case .spacer: Color.clear.frame(width: 0, height: 0)
        }
    }

    /// A click on a button row's empty space does nothing (v1 behaviour); everywhere else it opens the banner.
    private static func isInteractive(_ c: HeraldComponent) -> Bool {
        switch c {
        case .actions, .button, .iconButton: return true
        default: return false
        }
    }

    // MARK: Links and clicks

    /// Body links open in the default browser, but only for web and mail schemes: a notification body must not
    /// be able to launch an arbitrary `file:` or custom-scheme URL on a stray click. The click is also recorded
    /// so the banner's tap gesture does not additionally open the notification's own url and dismiss.
    private var linkAction: OpenURLAction {
        OpenURLAction { url in
            guard LinkPolicy.isOpenable(url) else { return .discarded }
            linkClickedAt = Date()
            return .systemAction
        }
    }

    /// The tap gesture and the link action can both fire for one click on a link, in either order. One
    /// main-queue hop lets the link action run first, then a link click is ignored here.
    private func bannerTapped() {
        DispatchQueue.main.async {
            if Date().timeIntervalSince(linkClickedAt) < 0.5 { return }
            model.onOpen()
        }
    }
}

/// A do-nothing tap handler over a cell, so a click on a button row's gaps does not reach the banner's own.
private struct SwallowTaps: ViewModifier {
    let active: Bool
    func body(content: Content) -> some View {
        if active { content.contentShape(Rectangle()).onTapGesture {} } else { content }
    }
}

// MARK: - Rive

/// Where a `rive` component is drawn: the live `RiveComponentView`, or a static placeholder for an offscreen
/// render. A click on the animation runs the component's own action (inline, or by reference into the
/// resolved list).
struct RiveSlotView: View {
    let component: HeraldRiveComponent
    let ctx: GridContext

    var body: some View {
        if !ctx.offscreen {
            RiveComponentView(component: component, app: ctx.notification.app, manifest: ctx.manifest,
                              fields: ctx.fields) { _ in
                if let found = ctx.action(inline: component.action, ref: component.actionRef) {
                    ctx.perform(found.action, found.origin)
                }
            }
        } else {
            sizedPlaceholder
        }
    }

    private var name: String {
        if let a = component.asset, !a.isEmpty { return a }
        if let p = component.path, !p.isEmpty { return URL(fileURLWithPath: p).deletingPathExtension().lastPathComponent }
        return "Rive"
    }

    /// A box with the animation's height or aspect ratio, so the layout is the same as with the live view.
    private var sizedPlaceholder: some View {
        let ratio = CGFloat(component.aspectRatio ?? 4)
        return Group {
            if let h = component.height, h > 0 {
                Color.clear.frame(idealWidth: CGFloat(h) * ratio, idealHeight: CGFloat(h)).frame(height: CGFloat(h))
            } else {
                Color.clear.frame(idealWidth: 64, idealHeight: 64 / ratio).aspectRatio(ratio, contentMode: .fit)
            }
        }
        .overlay { RiveComponentPlaceholder(title: name) }
    }
}

// MARK: - Height estimate

/// A rough height for a banner before SwiftUI has measured it, so the off-screen parked panel starts out about
/// the right size. Uses the same solver with character-count guesses in place of text measurement.
@MainActor
enum GridEstimator {
    static func height(for model: BannerModel, scheme: ColorScheme = .light) -> CGFloat {
        let state = GridRenderState(model: model, scheme: scheme)
        let cells = state.cells
        let ctx = state.ctx
        func text(_ i: Int) -> (len: Int, size: Double, lines: Int) {
            switch cells[i].component {
            case .text(let c):
                let len = ctx.bind(c.binding)?.count ?? 1
                let size = c.fontSize ?? (c.style == .caption ? 10 : c.style == .title ? 13 : 12)
                return (len, size, max(c.maxLines ?? GridStyle.defaultLines(c.style, body: ctx.maxBodyLines), 1))
            case .timestamp(let c): return (8, c.fontSize ?? 10, 1)
            case .badge: return (3, 10.5, 1)
            default: return (0, 12, 1)
            }
        }
        let measure = GridMeasure(
            idealWidth: { i in
                switch cells[i].component {
                case .text, .timestamp, .badge: let t = text(i); return Double(t.len) * t.size * 0.55
                case .issuerIcon(let c): return c.size
                case .iconButton(let c): return c.size ?? 18
                case .image(let c): return (c.height ?? 48) * (c.aspectRatio ?? 1)
                case .button: return 70
                default: return 0
                }
            },
            height: { i, w in
                switch cells[i].component {
                case .text, .timestamp, .badge:
                    let t = text(i)
                    let perLine = max(w / (t.size * 0.55), 1)
                    let lines = min(max(Int((Double(t.len) / perLine).rounded(.up)), 1), t.lines)
                    return Double(lines) * t.size * 1.3
                case .image(let c): return c.height ?? (w / (c.aspectRatio ?? 1))
                case .issuerIcon(let c): return c.size
                case .iconButton(let c): return c.size ?? 18
                case .button, .actions: return Double(ActionsComponentView.buttonHeight)
                case .progress(let c): return c.height ?? 4
                case .rive(let c): return c.height ?? (w / (c.aspectRatio ?? 1))
                case .spacer: return 0
                }
            })
        return CGFloat(GridSolver.solve(grid: state.grid, cells: cells, plan: state.plan, width: model.bannerWidth,
                                        measure: measure).height)
    }
}
