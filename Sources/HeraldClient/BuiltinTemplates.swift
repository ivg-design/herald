import Foundation

/// The four v1 layouts as grid templates (DESIGN 7.2: "the legacy v1 layouts become four built-in v2 grid
/// templates so every existing template keeps rendering"). They are generated in code, never stored:
/// `builtin.imageLeft`, `builtin.imageRight`, `builtin.hero` and `builtin.compact`.
///
/// Each reproduces its v1 structure with collapse doing what v1 did by hand: a banner without an image has
/// no image column, without a subtitle no subtitle row, without buttons no action row. Rows are one per v1
/// text line (title, subtitle, body) plus the action row, so the v1 styling of each line is kept; for that
/// reason the grids are 4 rows (hero 5, compact 2) by 4 columns rather than 3 x 4.
///
/// Differences from the v1 look: hero's image is inset by the card padding with rounded corners instead of
/// bleeding to the card edge, and its close button sits in the title row instead of floating over the image.
public enum BuiltinTemplates {
    public static let prefix = "builtin."

    /// `builtin.imageLeft`, `builtin.imageRight`, `builtin.hero`, `builtin.compact`.
    public static let names: [String] = HeraldLayout.allCases.map { name(for: $0) }

    public static func name(for layout: HeraldLayout) -> String { prefix + layout.rawValue }

    /// The layout a `builtin.*` name stands for; nil for any other name.
    public static func layout(forName name: String) -> HeraldLayout? {
        guard name.hasPrefix(prefix) else { return nil }
        return HeraldLayout(rawValue: String(name.dropFirst(prefix.count)))
    }

    public static func isBuiltin(_ name: String) -> Bool { layout(forName: name) != nil }

    /// The built-in template with this name, for `app` (empty by default); nil when the name is not one of the four.
    public static func named(_ name: String, app: String = "") -> HeraldTemplate? {
        layout(forName: name).map { template(layout: $0, app: app) }
    }

    /// All four, in `names` order.
    public static func all(app: String = "") -> [HeraldTemplate] {
        HeraldLayout.allCases.map { template(layout: $0, app: app) }
    }

    /// The grid template for a v1 look. The flags are the v1 template's: a hidden subtitle, body or timestamp
    /// has no cell, `maxBodyLines` limits the body, and `accentColor` colours the title as v1 did.
    public static func template(layout: HeraldLayout, app: String = "", accentColor: String? = nil,
                                showSubtitle: Bool = true, showBody: Bool = true, showTimestamp: Bool = true,
                                maxBodyLines: Int = HeraldTemplate.defaultMaxBodyLines) -> HeraldTemplate {
        let (grid, cells) = build(layout, accent: accentColor, showSubtitle: showSubtitle, showBody: showBody,
                                  showTimestamp: showTimestamp, maxBodyLines: maxBodyLines)
        var t = HeraldTemplate(name: name(for: layout), app: app, grid: grid, cells: cells)
        t.layout = layout
        t.accentColor = accentColor
        t.showSubtitle = showSubtitle; t.showBody = showBody; t.showTimestamp = showTimestamp
        t.maxBodyLines = maxBodyLines
        return t
    }

    /// A v1 template expressed as a grid: everything the template carries (content defaults, buttons, sound...)
    /// is kept and the grid of its `layout` is filled in. A template that already uses a grid is returned as is.
    public static func gridTemplate(for t: HeraldTemplate) -> HeraldTemplate {
        guard !t.usesGrid else { return t }
        let (grid, cells) = build(t.layout, accent: t.accentColor, showSubtitle: t.showSubtitle, showBody: t.showBody,
                                  showTimestamp: t.showTimestamp, maxBodyLines: t.maxBodyLines)
        var out = t
        out.layoutVersion = HeraldTemplate.currentLayoutVersion
        out.grid = grid; out.cells = cells; out.collapseEmpty = true
        return out
    }

    /// The grid for a notification that names no (grid) template: its own resolved v1 presentation fields
    /// (`layout`, `accentColor`, `showSubtitle`, ...) pick and tune the built-in.
    public static func gridTemplate(for n: HeraldNotification) -> HeraldTemplate {
        template(layout: n.layout ?? .imageLeft, app: n.app, accentColor: n.accentColor,
                 showSubtitle: n.showSubtitle ?? true, showBody: n.showBody ?? true,
                 showTimestamp: n.showTimestamp ?? true,
                 maxBodyLines: max(1, min(n.maxBodyLines ?? HeraldTemplate.defaultMaxBodyLines, 30)))
    }

    // MARK: Building

    private static let width = 380.0

    private static func build(_ layout: HeraldLayout, accent: String?, showSubtitle: Bool, showBody: Bool,
                              showTimestamp: Bool, maxBodyLines: Int) -> (HeraldGrid, [HeraldCell]) {
        let lines = max(1, min(maxBodyLines, 30))

        func title(size: Double? = nil, maxLines: Int = 2) -> HeraldComponent {
            .text(HeraldTextComponent(binding: "{title}", style: .title, maxLines: maxLines, color: validAccent(accent), fontSize: size))
        }
        let subtitle = HeraldComponent.text(HeraldTextComponent(binding: "{subtitle}", style: .subtitle, maxLines: 2))
        let body = HeraldComponent.text(HeraldTextComponent(binding: "{body}", style: .body, maxLines: lines, markdown: true))
        let image = HeraldComponent.image(HeraldImageComponent(binding: "{image}", fit: .cover, cornerRadius: 10, aspectRatio: 1))
        let heroImage = HeraldComponent.image(HeraldImageComponent(binding: "{image}", fit: .cover, cornerRadius: 10, aspectRatio: 16.0 / 9.0))
        let icon = HeraldComponent.issuerIcon(HeraldIssuerIconComponent(size: 22, cornerRadius: 5, shape: .rounded))
        let smallIcon = HeraldComponent.issuerIcon(HeraldIssuerIconComponent(size: 18, cornerRadius: 4, shape: .rounded))
        let time = HeraldComponent.timestamp(HeraldTimestampComponent(style: .caption, fontSize: 10))
        let close = HeraldComponent.iconButton(HeraldIconButtonComponent(
            symbol: "xmark", action: HeraldAction(id: "dismiss", label: "Dismiss", kind: .dismiss, style: "cancel"),
            size: 18, tooltip: "Dismiss"))
        let actions = HeraldComponent.actions(HeraldActionsComponent(source: .merged, layout: .wrap))

        func cell(_ id: String, _ row: Int, _ col: Int, rows: Int = 1, cols: Int = 1,
                  align: HeraldAlign = .topLeading, _ component: HeraldComponent) -> HeraldCell {
            HeraldCell(id: id, row: row, col: col, rowSpan: rows, colSpan: cols, align: align, component: component)
        }

        switch layout {
        case .imageLeft, .imageRight:
            // Columns: image 72 | text | text | meta (close, icon, time). Rows: title, subtitle, body, actions.
            let left = layout == .imageLeft
            let textCol = left ? 1 : 0
            var cells = [
                cell("image", 0, left ? 0 : 2, rows: 3, align: .topLeading, image),
                cell("title", 0, textCol, cols: 2, title()),
                cell("close", 0, 3, align: .topTrailing, close),
                cell("icon", 1, 3, align: .topTrailing, icon),
                cell("actions", 3, 0, cols: 4, actions),
            ]
            if showSubtitle { cells.append(cell("subtitle", 1, textCol, cols: 2, subtitle)) }
            if showBody { cells.append(cell("body", 2, textCol, cols: 2, body)) }
            if showTimestamp { cells.append(cell("time", 2, 3, align: .topTrailing, time)) }
            let cols: [HeraldSize] = left ? [.points(72), .fill, .fill, .auto] : [.fill, .fill, .points(72), .auto]
            return (HeraldGrid(rows: 4, cols: 4, rowSizes: Array(repeating: .auto, count: 4), colSizes: cols,
                               gap: 6, padding: 12, width: width), ordered(cells))

        case .hero:
            // Rows: image, title (+ time, close), subtitle (+ icon), body, actions.
            var cells = [
                cell("image", 0, 0, cols: 4, heroImage),
                cell("title", 1, 0, cols: 2, title(size: 14)),
                cell("close", 1, 3, align: .topTrailing, close),
                cell("icon", 2, 3, align: .topTrailing, icon),
                cell("actions", 4, 0, cols: 4, actions),
            ]
            if showSubtitle { cells.append(cell("subtitle", 2, 0, cols: 3, subtitle)) }
            if showBody { cells.append(cell("body", 3, 0, cols: 4, body)) }
            if showTimestamp { cells.append(cell("time", 1, 2, align: .topTrailing, time)) }
            return (HeraldGrid(rows: 5, cols: 4, rowSizes: Array(repeating: .auto, count: 5),
                               colSizes: [.fill, .fill, .auto, .auto], gap: 6, padding: 12, width: width), ordered(cells))

        case .compact:
            // One line: icon | title | time | close, then the actions. No image, subtitle or body, as in v1.
            var cells = [
                cell("icon", 0, 0, align: .center, smallIcon),
                cell("title", 0, 1, align: .leading, title(maxLines: 1)),
                cell("close", 0, 3, align: .center, close),
                cell("actions", 1, 0, cols: 4, actions),
            ]
            if showTimestamp { cells.append(cell("time", 0, 2, align: .center, time)) }
            return (HeraldGrid(rows: 2, cols: 4, rowSizes: [.auto, .auto], colSizes: [.auto, .fill, .auto, .auto],
                               gap: 8, padding: 10, width: width), ordered(cells))
        }
    }

    /// Reading order (row, then column), so the cell list reads like the banner.
    private static func ordered(_ cells: [HeraldCell]) -> [HeraldCell] {
        cells.sorted { ($0.row, $0.col) < ($1.row, $1.col) }
    }

    /// The accent only when it is a usable hex colour; v1 ignored a bad one the same way.
    private static func validAccent(_ s: String?) -> String? {
        guard let s, HeraldTemplate.isValidColor(s, allowKeywords: false) else { return nil }
        return s
    }
}
