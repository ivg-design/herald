import Foundation

// The pure half of the grid renderer (DESIGN 7.2): given a template's grid, its cells, the collapse plan for
// one notification and a way to measure each cell's content, work out the size of every track and the frame of
// every cell. No SwiftUI here, so the arithmetic is unit tested (GridLayoutTests); `GridCanvasLayout` in
// Banners/GridBannerView.swift feeds it real measurements and places the views.
//
// Sizing rules
//   Columns  points: exactly that wide. auto: as wide as the widest cell that sits in it alone (a cell spanning
//            several tracks lends its excess to the auto tracks it covers, but only when none of them is
//            fill). fill: equal shares of what remains of the width.
//   Rows     points: exactly that tall. auto and fill: as tall as their tallest cell, because a banner's height
//            is decided by its content (there is no fixed height for a fill row to share). A tall cell that
//            spans rows lends its excess to the LAST non-points row it covers, so text beside a tall image
//            stays packed at the top.
//   Collapsed tracks (HeraldGridPlan) have zero size and contribute no gap.
//   Auto columns never take more than what is left after the points columns and the gaps; when they want
//   more, the widest ones are trimmed first and the narrow ones keep their natural width.

/// A rectangle in points, origin top-left of the banner.
public struct GridRect: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double
    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x; self.y = y; self.width = width; self.height = height
    }
    public var maxX: Double { x + width }
    public var maxY: Double { y + height }
}

/// How the solver asks the renderer about a cell's content. Both closures take the cell's index in the
/// `cells` array and report the size of the content WITHOUT the cell's own padding, which the solver adds.
public struct GridMeasure {
    /// Natural width of the content, on one line.
    public var idealWidth: (Int) -> Double
    /// Height of the content when it is given `width` points.
    public var height: (Int, Double) -> Double
    public init(idealWidth: @escaping (Int) -> Double, height: @escaping (Int, Double) -> Double) {
        self.idealWidth = idealWidth; self.height = height
    }
}

public struct GridSolution: Equatable, Sendable {
    /// Whole banner, padding included.
    public var width: Double
    public var height: Double
    /// One entry per grid column / row; 0 for collapsed tracks.
    public var colWidths: [Double]
    public var rowHeights: [Double]
    /// Where each track starts, from the banner's top-left corner.
    public var colOrigins: [Double]
    public var rowOrigins: [Double]
    /// One entry per cell, parallel to the `cells` array. nil for a cell that is collapsed, or that lies
    /// outside the grid. A frame includes the cell's padding.
    public var frames: [GridRect?]
}

public enum GridSolver {
    /// Banner widths below or above this are pulled back (the validator reports them as errors).
    public static let widthRange: ClosedRange<Double> = HeraldTemplate.widthRange

    public static func clampedWidth(_ w: Double) -> Double {
        guard w.isFinite else { return 400 }
        return min(max(w, widthRange.lowerBound), widthRange.upperBound)
    }

    public static func solve(grid g: HeraldGrid, cells: [HeraldCell], plan: HeraldGridPlan,
                             width: Double? = nil, measure: GridMeasure) -> GridSolution {
        let total = clampedWidth(width ?? g.width)
        // Clamped as defence in depth: a grid that was built in code, not decoded, can still ask for any count.
        let maxT = HeraldTemplate.maxGridTracks
        let rows = min(max(g.rows, 0), maxT), cols = min(max(g.cols, 0), maxT)
        let pad = max(g.padding, 0), gap = max(g.gap, 0)
        let inner = max(total - 2 * pad, 0)

        let liveCols = (0..<cols).filter { !plan.collapsedCols.contains($0) }
        let liveRows = (0..<rows).filter { !plan.collapsedRows.contains($0) }

        // The cells that are drawn, with the live tracks each one covers.
        struct Live { let index: Int; let cols: [Int]; let rows: [Int]; let padding: Double }
        var live: [Live] = []
        for (i, c) in cells.enumerated() where !plan.collapsedCells.contains(c.id) {
            let cr = c.colRange(in: cols).filter { !plan.collapsedCols.contains($0) }
            let rr = c.rowRange(in: rows).filter { !plan.collapsedRows.contains($0) }
            guard !cr.isEmpty, !rr.isEmpty else { continue }
            live.append(Live(index: i, cols: cr, rows: rr, padding: max(c.padding, 0)))
        }

        // MARK: Columns
        var colW = [Double](repeating: 0, count: cols)
        func colSize(_ c: Int) -> HeraldSize { g.colSize(at: c) }
        let colGaps = gap * Double(max(liveCols.count - 1, 0))
        var fixed = 0.0
        for c in liveCols { if case .points(let p) = colSize(c) { colW[c] = max(p, 0); fixed += colW[c] } }

        var ideal = [Double](repeating: 0, count: cols)
        for l in live where l.cols.count == 1 && colSize(l.cols[0]) == .auto {
            ideal[l.cols[0]] = max(ideal[l.cols[0]], max(measure.idealWidth(l.index), 0) + 2 * l.padding)
        }
        for l in live.filter({ $0.cols.count > 1 }).sorted(by: { $0.cols.count < $1.cols.count }) {
            let sizes = l.cols.map(colSize)
            guard !sizes.contains(.fill), sizes.contains(.auto) else { continue }
            let need = max(measure.idealWidth(l.index), 0) + 2 * l.padding
            let have = l.cols.reduce(0.0) { $0 + (colSize($1) == .auto ? ideal[$1] : colW[$1]) }
                + gap * Double(l.cols.count - 1)
            guard need > have else { continue }
            let autos = l.cols.filter { colSize($0) == .auto }
            for c in autos { ideal[c] += (need - have) / Double(autos.count) }
        }
        let budget = max(inner - colGaps - fixed, 0)
        let autoCols = liveCols.filter { colSize($0) == .auto }
        for (c, w) in waterFill(autoCols.map { ($0, ideal[$0]) }, budget: budget) { colW[c] = w }
        let autoTotal = autoCols.reduce(0.0) { $0 + colW[$1] }
        let fillCols = liveCols.filter { colSize($0) == .fill }
        if !fillCols.isEmpty {
            let share = max(budget - autoTotal, 0) / Double(fillCols.count)
            for c in fillCols { colW[c] = share }
        }

        let colOrigins = origins(count: cols, sizes: colW, collapsed: plan.collapsedCols, gap: gap, start: pad)

        // Each live cell's horizontal extent, then the height its content needs at that width.
        var frames = [GridRect?](repeating: nil, count: cells.count)
        var xs = [Int: (x: Double, w: Double)]()
        var needH = [Int: Double]()
        for l in live {
            let first = l.cols.first!, last = l.cols.last!
            let x = colOrigins[first]
            let w = colOrigins[last] + colW[last] - x
            xs[l.index] = (x, w)
            needH[l.index] = max(measure.height(l.index, max(w - 2 * l.padding, 0)), 0) + 2 * l.padding
        }

        // MARK: Rows
        var rowH = [Double](repeating: 0, count: rows)
        func rowSize(_ r: Int) -> HeraldSize { g.rowSize(at: r) }
        func isPoints(_ r: Int) -> Bool { if case .points = rowSize(r) { return true }; return false }
        for r in liveRows { if case .points(let p) = rowSize(r) { rowH[r] = max(p, 0) } }
        for l in live where l.rows.count == 1 && !isPoints(l.rows[0]) {
            rowH[l.rows[0]] = max(rowH[l.rows[0]], needH[l.index] ?? 0)
        }
        for l in live.filter({ $0.rows.count > 1 }).sorted(by: { $0.rows.count < $1.rows.count }) {
            guard let grow = l.rows.last(where: { !isPoints($0) }) else { continue }
            let have = l.rows.reduce(0.0) { $0 + rowH[$1] } + gap * Double(l.rows.count - 1)
            let need = needH[l.index] ?? 0
            if need > have { rowH[grow] += need - have }
        }
        let rowOrigins = origins(count: rows, sizes: rowH, collapsed: plan.collapsedRows, gap: gap, start: pad)

        for l in live {
            let first = l.rows.first!, last = l.rows.last!
            let y = rowOrigins[first]
            let h = rowOrigins[last] + rowH[last] - y
            let (x, w) = xs[l.index]!
            frames[l.index] = GridRect(x: x, y: y, width: w, height: h)
        }

        let content = liveRows.reduce(0.0) { $0 + rowH[$1] } + gap * Double(max(liveRows.count - 1, 0))
        return GridSolution(width: total, height: 2 * pad + content, colWidths: colW, rowHeights: rowH,
                            colOrigins: colOrigins, rowOrigins: rowOrigins, frames: frames)
    }

    /// Hands out `budget` to tracks that each want some amount: nobody gets more than they want, and when
    /// the wants add up to more than the budget the biggest are trimmed to an equal share while the small
    /// ones keep what they asked for.
    static func waterFill(_ wants: [(Int, Double)], budget: Double) -> [(Int, Double)] {
        var remaining = max(budget, 0)
        var out: [(Int, Double)] = []
        let sorted = wants.sorted { $0.1 < $1.1 }
        for (k, entry) in sorted.enumerated() {
            let give = min(entry.1, remaining / Double(sorted.count - k))
            out.append((entry.0, give))
            remaining -= give
        }
        return out
    }

    /// Start of each track: tracks follow each other with `gap` between live ones; a collapsed track sits
    /// where the next live one would start and takes no space.
    private static func origins(count: Int, sizes: [Double], collapsed: Set<Int>, gap: Double, start: Double) -> [Double] {
        var out = [Double](repeating: start, count: count)
        var pos = start
        var any = false
        for i in 0..<count {
            if collapsed.contains(i) { out[i] = pos; continue }
            if any { pos += gap }
            out[i] = pos
            pos += sizes[i]
            any = true
        }
        return out
    }
}

/// Which of an action row's buttons are drawn and which go behind the "+N" menu. `GridBannerView` lets
/// SwiftUI decide how many fit a row; `maxVisible` is the template's own cap and applies in every layout.
public enum ActionOverflow {
    /// How many of `total` actions are shown outright. nil or a cap beyond the total shows everything; the
    /// cap is at least 1 so a banner never shows only a menu because of a typo.
    public static func visibleCount(total: Int, maxVisible: Int?) -> Int {
        guard total > 0 else { return 0 }
        guard let m = maxVisible else { return total }
        return min(total, max(m, 1))
    }

    /// Label of the overflow menu.
    public static func menuTitle(hidden: Int) -> String { "+\(hidden)" }
}

// MARK: - What a banner binds

/// The data half of a banner, as pure functions so it is unit tested: the fields its bindings read and the
/// action list its buttons show. `BannerModel` calls these whenever its item, template or manifest changes.
public enum BannerData {
    /// What `{image}` holds when a banner was handed a picture but its notification names no image source
    /// (a composer preview): the picture is shown, and the binding counts as present.
    public static let cachedImageToken = "herald-cached-image"

    /// The fields the bindings read.
    ///
    /// Start from `override` (designer samples), else the fields stored with the history item, else resolve them
    /// from the notification (`TemplateResolver.fields`). Unless an `override` is given, the notification's own
    /// title, subtitle and body are laid over the result: a failure line replaces the subtitle of a live banner
    /// without touching the item's stored fields. The template's `extra` values are added as `extra.<key>`, and
    /// `{image}` is present whenever the banner has a picture (`hasPicture`).
    public static func fields(for n: HeraldNotification, stored: [String: HeraldFieldValue]?,
                              override: [String: HeraldFieldValue]?, manifest: HeraldManifest?,
                              extra: [String: String], deliveredAt: Date, hasPicture: Bool) -> [String: HeraldFieldValue] {
        var f = override ?? stored ?? TemplateResolver.fields(for: n, manifest: manifest, extra: extra, deliveredAt: deliveredAt)
        if override == nil {
            for (key, value) in [("title", n.title), ("subtitle", n.subtitle ?? ""), ("body", n.body ?? "")]
            where !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                f[key] = .text(value)
            }
        }
        for (k, v) in extra where !k.isEmpty && !v.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            f["extra.\(k)"] = .text(v)
        }
        if f["image"] == nil, hasPicture { f["image"] = .text(cachedImageToken) }
        return f
    }

    /// The id of the action the notification's `snooze` flag stands for.
    public static let snoozeActionID = "snooze"

    /// The resolved action list: the payload's buttons (with the ids the manifest declared for them), then the
    /// built-in snooze menu when the notification asks for one, all through the template's rules, which can hide,
    /// relabel, restyle and reorder them and add actions of their own.
    public static func actions(for n: HeraldNotification, manifest: HeraldManifest?,
                               rules: [HeraldActionRule], template: HeraldTemplate? = nil) -> [HeraldResolvedAction] {
        let source = ActionResolver.issuerSource(for: n, manifest: manifest)
        let origin: HeraldActionOrigin = ActionRunner.buttonsCameFromTemplate(n, template) ? .template : .issuer
        let issuer = ActionResolver.resolveDetailed(issuer: source.buttons, ids: source.ids, rules: [], issuerOrigin: origin)
        return actions(issuer: issuer, snooze: n.snooze == true, rules: rules)
    }

    /// The same list for issuer buttons that are already chosen (a sample preview's, the Designer's).
    public static func actions(issuer start: [HeraldResolvedAction], snooze: Bool,
                               rules: [HeraldActionRule]) -> [HeraldResolvedAction] {
        var issuer = start
        if snooze, !issuer.contains(where: { $0.action.kind == .snooze }) {
            issuer.append(HeraldResolvedAction(action: HeraldAction(id: snoozeActionID, label: "Snooze", kind: .snooze), origin: .issuer))
        }
        return ActionResolver.resolveDetailed(issuerResolved: issuer, rules: rules)
    }
}

// MARK: - Component values

public enum GridFormat {
    /// A progress value as a fraction of 1: "0.4" and "40" and "40%" all mean 40 percent. A value above 1 is a
    /// percentage; the result is clamped to 0...1. nil when the text is not a number.
    public static func progressFraction(_ text: String) -> Double? {
        var t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let percent = t.hasSuffix("%")
        if percent { t.removeLast() }
        guard let v = Double(t.trimmingCharacters(in: .whitespaces)), v.isFinite else { return nil }
        let f = (percent || v > 1) ? v / 100 : v
        return min(max(f, 0), 1)
    }

    /// The time for a date on the same day as `now`, the date and time for any other day.
    public static func absolute(_ date: Date, now: Date = Date(), calendar: Calendar = .current,
                                locale: Locale = .current) -> String {
        if calendar.isDate(date, inSameDayAs: now) {
            return date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, calendar: calendar,
                                                   timeZone: calendar.timeZone))
        }
        return date.formatted(Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
            .month(.abbreviated).day().hour().minute())
    }

    /// "3 min. ago", "in 2 hr."
    public static func relative(_ date: Date, now: Date = Date(), locale: Locale = .current) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        f.dateTimeStyle = .named
        f.locale = locale
        return f.localizedString(for: date, relativeTo: now)
    }
}
