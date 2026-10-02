import Foundation

/// The edits the Designer's Symbol panel makes, kept pure so they are tested: each takes the symbol (nil when the
/// component has none) and returns the new one, with empty settings dropped so the template JSON stays minimal.
public enum SymbolEditing {
    public static func setName(_ s: HeraldSymbol?, _ name: String) -> HeraldSymbol? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        var out = s ?? HeraldSymbol(name: trimmed)
        out.name = trimmed
        return out
    }

    /// Changing the mode keeps the colours that still make sense: palette wants 2 (a second is filled in), a
    /// multicolor symbol uses none, monochrome and hierarchical use one.
    public static func setMode(_ s: HeraldSymbol, _ mode: HeraldSymbolRenderingMode?) -> HeraldSymbol {
        var out = s
        out.renderingMode = (mode == .monochrome) ? nil : mode
        var colors = out.colors ?? []
        switch mode ?? .monochrome {
        case .multicolor: colors = []
        case .monochrome, .hierarchical: colors = Array(colors.prefix(1))
        case .palette:
            if colors.isEmpty { colors = ["accent", "secondary"] }
            else if colors.count == 1 { colors.append("secondary") }
            colors = Array(colors.prefix(3))
        }
        out.colors = colors.isEmpty ? nil : colors
        return out
    }

    public static func setColor(_ s: HeraldSymbol, at index: Int, _ value: String) -> HeraldSymbol {
        var out = s
        var colors = out.colors ?? []
        guard (0..<3).contains(index) else { return s }
        while colors.count <= index { colors.append("accent") }
        let v = value.trimmingCharacters(in: .whitespaces)
        colors[index] = v.isEmpty ? "accent" : v
        out.colors = colors
        return out
    }

    public static func addColor(_ s: HeraldSymbol) -> HeraldSymbol {
        var out = s
        var colors = out.colors ?? []
        guard colors.count < 3 else { return s }
        colors.append(colors.last == "accent" ? "secondary" : "accent")
        out.colors = colors
        return out
    }

    public static func removeColor(_ s: HeraldSymbol, at index: Int) -> HeraldSymbol {
        var out = s
        guard var colors = out.colors, colors.indices.contains(index) else { return s }
        colors.remove(at: index)
        out.colors = colors.isEmpty ? nil : colors
        return out
    }

    /// A number (clamped 0-1) or a `{token}`; blank clears it.
    public static func setVariableValue(_ s: HeraldSymbol, _ text: String) -> HeraldSymbol {
        var out = s
        let t = text.trimmingCharacters(in: .whitespaces)
        if t.isEmpty { out.variableValue = nil }
        else if let d = Double(t) { out.variableValue = d == d.rounded() ? String(Int(min(max(d, 0), 1))) : String(min(max(d, 0), 1)) }
        else { out.variableValue = t }
        return out
    }

    /// A kind picks sensible defaults for what only some kinds use; `nil` removes the effect.
    public static func setEffect(_ s: HeraldSymbol, _ kind: HeraldSymbolEffectKind?) -> HeraldSymbol {
        var out = s
        guard let kind else { out.effect = nil; return out }
        var e = out.effect ?? HeraldSymbolEffect(kind: kind)
        e.kind = kind
        if kind != .variableColor { e.cumulative = nil; e.reversing = nil }
        if kind == .replace { e.trigger = .onChange }
        out.effect = e
        return out
    }

    public static func setTrigger(_ s: HeraldSymbol, _ t: HeraldSymbolTrigger) -> HeraldSymbol {
        var out = s
        guard var e = out.effect else { return s }
        e.trigger = (t == .onAppear) ? nil : t
        out.effect = e
        return out
    }

    public static func setSpeed(_ s: HeraldSymbol, _ speed: Double) -> HeraldSymbol {
        var out = s
        guard var e = out.effect else { return s }
        e.speed = abs(speed - 1) < 0.001 ? nil : min(max(speed, 0.25), 4)
        out.effect = e
        return out
    }

    /// The symbol after a styling change, or nil when nothing but an empty name is left.
    public static func normalized(_ s: HeraldSymbol?) -> HeraldSymbol? {
        guard var out = s, !out.name.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        if out.weight == .regular { out.weight = nil }
        if out.scale == .medium { out.scale = nil }
        if out.placement == .leading { out.placement = nil }
        if out.renderingMode == .monochrome { out.renderingMode = nil }
        if (out.colors ?? []).isEmpty { out.colors = nil }
        return out
    }
}
