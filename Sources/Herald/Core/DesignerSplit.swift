import Foundation

/// Where the Designer puts its live preview (issue: the preview was a strip that was easy to miss).
///
/// The preview is a first-class pane that starts at half of the centre column (`defaultPreviewFraction`) and can be
/// dragged anywhere from a quarter (`minPreviewFraction`) to three quarters. The divider can be dragged within `[minPreviewFraction, maxPreviewFraction]`
/// and its position is remembered. Pure, so `DesignerSplitTests` pin the numbers.
public struct DesignerSplit: Equatable, Sendable {
    public enum Axis: String, Equatable, Sendable { case horizontal, vertical }

    public static let minPreviewFraction = 0.25
    public static let maxPreviewFraction = 0.75
    public static let defaultPreviewFraction = 0.5
    /// A side-by-side split needs the editor (palette, canvas, inspector) to stay usable at half the width.
    public static let horizontalMinWidth = Double.infinity
    /// The divider's thickness; it comes out of the editor's share, never the preview's.
    public static let dividerThickness = 8.0
    /// The editor never gets less than this along the split axis.
    public static let minEditorLength = 280.0

    public var axis: Axis
    public var fraction: Double

    public init(axis: Axis, fraction: Double) {
        self.axis = axis
        self.fraction = Self.clamped(fraction)
    }

    public static func clamped(_ f: Double) -> Double {
        guard f.isFinite else { return defaultPreviewFraction }
        return min(max(f, minPreviewFraction), maxPreviewFraction)
    }

    public static func axis(forWidth width: Double) -> Axis { width >= horizontalMinWidth ? .horizontal : .vertical }

    /// The split for a design area of this size and a remembered fraction.
    public static func make(width: Double, fraction: Double) -> DesignerSplit {
        DesignerSplit(axis: axis(forWidth: width), fraction: fraction)
    }

    /// Length of the preview pane along the axis for a design area of `total` points (the divider is not part of it).
    public func previewLength(total: Double) -> Double {
        let usable = max(total - Self.dividerThickness, 0)
        // The editor keeps its minimum unless that would take the preview below its half.
        let ceiling = max(usable - Self.minEditorLength, usable * Self.minPreviewFraction)
        return min(usable * fraction, ceiling).rounded()
    }

    /// Length of the editor pane: what is left, never below `minEditorLength` unless the area itself is smaller.
    public func editorLength(total: Double) -> Double {
        max(total - Self.dividerThickness - previewLength(total: total), 0)
    }

    /// The fraction after the divider was dragged to `editorLength` (the editor's size along the axis).
    public static func fraction(forEditorLength editor: Double, total: Double) -> Double {
        let usable = max(total - dividerThickness, 1)
        let maxEditor = max(usable * (1 - minPreviewFraction), 0)
        let minEditor = min(minEditorLength, maxEditor)
        let e = min(max(editor, minEditor), maxEditor)
        return clamped(1 - e / usable)
    }

    // MARK: Persistence

    public static let defaultsKey = "designerPreviewFraction"

    public static func load(from defaults: UserDefaults = .standard) -> Double {
        defaults.object(forKey: defaultsKey) == nil ? defaultPreviewFraction : clamped(defaults.double(forKey: defaultsKey))
    }

    public static func save(_ fraction: Double, to defaults: UserDefaults = .standard) {
        defaults.set(clamped(fraction), forKey: defaultsKey)
    }
}

/// Sidebar widths and zoom of the two surfaces (editor grid, live preview), remembered per window.
public struct DesignerPanes: Equatable, Sendable {
    public static let leftRange: ClosedRange<Double> = 180...360
    public static let rightRange: ClosedRange<Double> = 280...480
    public static let defaultLeft = 226.0
    public static let defaultRight = 340.0
    /// The centre column never gets narrower than this: the window's minimum width must cover both sidebars plus it.
    public static let minCenter = 460.0

    public enum Pane: String, Sendable { case editor, preview }

    public var left = defaultLeft
    public var right = defaultRight
    public var editorZoom = 1.0
    public var previewZoom = 1.0

    public init() {}

    public static func clampLeft(_ v: Double, window: Double = .infinity) -> Double {
        min(max(v.isFinite ? v : defaultLeft, leftRange.lowerBound), min(leftRange.upperBound, max(window - minCenter - leftRange.lowerBound, leftRange.lowerBound)))
    }
    public static func clampRight(_ v: Double, window: Double = .infinity) -> Double {
        min(max(v.isFinite ? v : defaultRight, rightRange.lowerBound), min(rightRange.upperBound, max(window - minCenter - leftRange.lowerBound, rightRange.lowerBound)))
    }

    public func zoom(_ pane: Pane) -> Double { pane == .editor ? editorZoom : previewZoom }
    public mutating func setZoom(_ pane: Pane, _ z: Double) {
        let c = DesignerZoom.clamped(z)
        if pane == .editor { editorZoom = c } else { previewZoom = c }
    }

    private static func key(_ n: String) -> String { "designer.\(n)" }

    public static func load(from d: UserDefaults = .standard) -> DesignerPanes {
        var p = DesignerPanes()
        func num(_ k: String) -> Double? { d.object(forKey: key(k)) == nil ? nil : d.double(forKey: key(k)) }
        if let v = num("left") { p.left = clampLeft(v) }
        if let v = num("right") { p.right = clampRight(v) }
        if let v = num("editorZoom") { p.editorZoom = DesignerZoom.clamped(v) }
        if let v = num("previewZoom") { p.previewZoom = DesignerZoom.clamped(v) }
        return p
    }

    public func save(to d: UserDefaults = .standard) {
        d.set(left, forKey: Self.key("left")); d.set(right, forKey: Self.key("right"))
        d.set(editorZoom, forKey: Self.key("editorZoom")); d.set(previewZoom, forKey: Self.key("previewZoom"))
    }
}

/// Zoom of a Designer surface: 50 % to 300 %, stepped by the keyboard and the popover's buttons.
public enum DesignerZoom {
    public static let range: ClosedRange<Double> = 0.5...3.0
    public static let steps: [Double] = [0.5, 0.67, 0.75, 0.9, 1, 1.1, 1.25, 1.5, 2, 2.5, 3]

    public static func clamped(_ z: Double) -> Double { z.isFinite ? min(max(z, range.lowerBound), range.upperBound) : 1 }
    public static func zoomIn(_ z: Double) -> Double { steps.first { $0 > z + 0.001 } ?? range.upperBound }
    public static func zoomOut(_ z: Double) -> Double { steps.last { $0 < z - 0.001 } ?? range.lowerBound }
    /// A pinch: the zoom at the start of the gesture times the gesture's magnification.
    public static func pinched(from start: Double, magnification m: Double) -> Double { clamped(start * (m.isFinite && m > 0 ? m : 1)) }
    public static func label(_ z: Double) -> String { "\(Int((clamped(z) * 100).rounded()))%" }
}
