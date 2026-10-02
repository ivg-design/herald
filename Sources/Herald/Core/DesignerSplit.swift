import Foundation

/// Where the Designer puts its live preview (issue: the preview was a strip that was easy to miss).
///
/// The preview is a first-class pane that is never smaller than half the design area (`minPreviewFraction`): to the
/// right of the editor when the window is wide enough for both, otherwise on top of it, so on a narrow window the
/// preview takes at least half the height. The divider can be dragged within `[minPreviewFraction, maxPreviewFraction]`
/// and its position is remembered. Pure, so `DesignerSplitTests` pin the numbers.
public struct DesignerSplit: Equatable, Sendable {
    public enum Axis: String, Equatable, Sendable { case horizontal, vertical }

    public static let minPreviewFraction = 0.5
    public static let maxPreviewFraction = 0.75
    public static let defaultPreviewFraction = 0.5
    /// A side-by-side split needs the editor (palette, canvas, inspector) to stay usable at half the width.
    public static let horizontalMinWidth = 1700.0
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
