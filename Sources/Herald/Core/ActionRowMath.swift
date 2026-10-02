import Foundation
import CoreGraphics
import HeraldClient

/// Where the buttons of an `actions` cell go: the pure arithmetic behind `ActionRowLayout`, so the frames can be
/// asserted without a window server. Buttons keep their own size and go left to right; with `wrap` they flow onto
/// further lines when the next one would not fit `width`; each line is then placed by `align`.
public enum ActionRowMath {
    public struct Result: Equatable {
        /// One frame per button, in input order, relative to the top-left of the row.
        public var frames: [CGRect]
        /// The row's size: its natural width for `leading`, the whole `width` for the other alignments.
        public var size: CGSize
    }

    /// `width` is the room the cell gives the row; nil means "as wide as the buttons want".
    public static func arrange(sizes: [CGSize], width: CGFloat?, spacing: CGFloat, lineSpacing: CGFloat,
                               wrap: Bool, align: HeraldActionsAlign) -> Result {
        guard !sizes.isEmpty else { return Result(frames: [], size: .zero) }
        let limit = width.flatMap { $0.isFinite ? $0 : nil }
        // Split into lines.
        var lines: [[Int]] = [[]]
        var x: CGFloat = 0
        for (i, s) in sizes.enumerated() {
            if wrap, let limit, !lines[lines.count - 1].isEmpty, x + s.width > limit {
                lines.append([]); x = 0
            }
            lines[lines.count - 1].append(i)
            x += s.width + spacing
        }
        func used(_ line: [Int]) -> CGFloat { line.reduce(0) { $0 + sizes[$1].width } }
        func natural(_ line: [Int]) -> CGFloat { used(line) + spacing * CGFloat(max(line.count - 1, 0)) }
        let widest = lines.map(natural).max() ?? 0
        let boxWidth = limit.map { align == .leading ? widest : max($0, wrap ? 0 : widest) } ?? widest

        var frames = [CGRect](repeating: .zero, count: sizes.count)
        var y: CGFloat = 0
        for line in lines {
            let height = line.map { sizes[$0].height }.max() ?? 0
            var gap = spacing
            var start: CGFloat = 0
            switch align {
            case .leading: break
            case .center: start = max(0, (boxWidth - natural(line)) / 2)
            case .trailing: start = max(0, boxWidth - natural(line))
            case .spaceBetween: if line.count > 1 { gap = max(spacing, (boxWidth - used(line)) / CGFloat(line.count - 1)) }
            }
            var cx = start
            for i in line {
                frames[i] = CGRect(x: cx, y: y + (height - sizes[i].height) / 2, width: sizes[i].width, height: sizes[i].height)
                cx += sizes[i].width + gap
            }
            y += height + lineSpacing
        }
        let total = lines.map { line in line.map { sizes[$0].height }.max() ?? 0 }.reduce(0, +)
            + lineSpacing * CGFloat(lines.count - 1)
        return Result(frames: frames, size: CGSize(width: boxWidth, height: total))
    }
}
