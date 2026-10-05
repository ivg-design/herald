import SwiftUI
import AppKit

// Drawing an SF Symbol with its full styling (HeraldSymbol): weight, scale, rendering mode, colours, variable
// value and, on macOS 14+, a symbol effect. Static renders (`ctx.offscreen`: previews, /v1/preview, history rows)
// show weight, scale, mode, colours and the variable value; effects run only in live banners, and never when the
// user asked for Reduce Motion.

@MainActor
enum SymbolStyle {
    /// The name with `{tokens}` filled in from the fields (a token in the name is how `replace` has something to swap).
    static func resolvedName(_ s: HeraldSymbol, _ ctx: GridContext) -> String {
        s.name.contains("{") ? (ctx.bind(s.name) ?? "") : s.name
    }

    /// Whether this Mac has the symbol (otherwise the caller keeps its current look).
    static func isDrawable(_ s: HeraldSymbol, _ ctx: GridContext) -> Bool {
        let n = resolvedName(s, ctx)
        return !n.isEmpty && HeraldSymbol.isKnown(n)
    }

    static func weight(_ w: HeraldSymbolWeight?, default d: Font.Weight) -> Font.Weight {
        switch w {
        case .ultraLight?: return .ultraLight
        case .thin?: return .thin
        case .light?: return .light
        case .regular?: return .regular
        case .medium?: return .medium
        case .semibold?: return .semibold
        case .bold?: return .bold
        case .heavy?: return .heavy
        case .black?: return .black
        case nil: return d
        }
    }

    static func scale(_ s: HeraldSymbolScale?) -> Image.Scale {
        switch s { case .small?: return .small; case .large?: return .large; default: return .medium }
    }

    /// 0...1 from a number or a `{token}` bound to a numeric field; nil when there is none. Percentages (> 1 up to 100)
    /// are read as percent, like the progress bar.
    static func variableValue(_ s: HeraldSymbol, _ ctx: GridContext) -> Double? {
        guard let raw = s.variableValue, !raw.isEmpty else { return nil }
        let text = raw.contains("{") ? ctx.bind(raw) : raw
        guard let t = text, let d = Double(t.trimmingCharacters(in: .whitespaces)) else { return nil }
        return min(max(d > 1 && d <= 100 ? d / 100 : d, 0), 1)
    }

    /// The colours, tokens filled in, as SwiftUI colours (an unresolvable one is skipped).
    static func colors(_ s: HeraldSymbol, _ ctx: GridContext) -> [Color] {
        (s.colors ?? []).prefix(3).compactMap { spec in
            let resolved = spec.contains("{") ? ctx.bind(spec) : spec
            return ctx.color(resolved)
        }
    }

    /// A string that changes when anything the symbol is bound to changes (the `onChange` trigger).
    static func changeKey(_ s: HeraldSymbol, _ ctx: GridContext) -> String {
        ([resolvedName(s, ctx)] + s.referencedTokens.map { ctx.bind("{\($0)}") ?? "" }).joined(separator: "\u{1}")
    }

    static var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
}

/// The symbol glyph. `tint` is the colour when the symbol names none; `size` the point size before `scale`.
struct SymbolImage: View {
    let symbol: HeraldSymbol
    let ctx: GridContext
    var tint: Color = .primary
    var size: CGFloat = 12
    var defaultWeight: Font.Weight = .regular

    var body: some View {
        let name = SymbolStyle.resolvedName(symbol, ctx)
        let colors = SymbolStyle.colors(symbol, ctx)
        let image = Group {
            if let v = SymbolStyle.variableValue(symbol, ctx) { Image(systemName: name, variableValue: v) }
            else { Image(systemName: name) }
        }
        .font(.system(size: size, weight: SymbolStyle.weight(symbol.weight, default: defaultWeight)))
        .imageScale(SymbolStyle.scale(symbol.scale))
        let styled = Group {
            switch symbol.renderingMode ?? .monochrome {
            case .monochrome:
                image.symbolRenderingMode(.monochrome).foregroundStyle(colors.first ?? tint)
            case .hierarchical:
                image.symbolRenderingMode(.hierarchical).foregroundStyle(colors.first ?? tint)
            case .palette:
                switch colors.count {
                case 0: image.symbolRenderingMode(.palette).foregroundStyle(tint, tint.opacity(0.55))
                case 1: image.symbolRenderingMode(.palette).foregroundStyle(colors[0], colors[0].opacity(0.55))
                case 2: image.symbolRenderingMode(.palette).foregroundStyle(colors[0], colors[1])
                default: image.symbolRenderingMode(.palette).foregroundStyle(colors[0], colors[1], colors[2])
                }
            case .multicolor:
                image.symbolRenderingMode(.multicolor)
            }
        }
        if #available(macOS 14.0, *), let effect = symbol.effect, !ctx.offscreen, !SymbolStyle.reduceMotion {
            styled.modifier(SymbolEffectModifier(effect: effect, changeKey: SymbolStyle.changeKey(symbol, ctx)))
        } else {
            styled
        }
    }
}

/// A button's label with an optional symbol: leading (default), trailing, or only.
struct SymbolLabel: View {
    let text: String
    let symbol: HeraldSymbol?
    let ctx: GridContext
    var tint: Color = .primary

    var body: some View {
        if let s = symbol, SymbolStyle.isDrawable(s, ctx) {
            let glyph = SymbolImage(symbol: s, ctx: ctx, tint: tint, size: 11, defaultWeight: .semibold)
            switch s.placement ?? .leading {
            case .only: glyph
            case .trailing: HStack(spacing: 4) { Text(text); glyph }
            case .leading: HStack(spacing: 4) { glyph; Text(text) }
            }
        } else {
            Text(text)
        }
    }
}

// MARK: - Effects (macOS 14+)

@available(macOS 14.0, *)
private struct SymbolEffectModifier: ViewModifier {
    let effect: HeraldSymbolEffect
    let changeKey: String
    @State private var tick = 0
    @State private var active = false
    @State private var shown = false
    @State private var gone = false

    /// appear and disappear play once, so `repeating` acts as `onAppear` for them (validation says so).
    private var trigger: HeraldSymbolTrigger {
        (effect.kind == .appear || effect.kind == .disappear) && effect.resolvedTrigger == .repeating ? .onAppear : effect.resolvedTrigger
    }
    private var repeating: Bool { trigger == .repeating }
    private var options: SymbolEffectOptions {
        repeating ? SymbolEffectOptions.repeating.speed(effect.resolvedSpeed) : SymbolEffectOptions.speed(effect.resolvedSpeed)
    }

    private func fire() {
        tick += 1
        active = true
        gone = true
        let hold = 1.6 / effect.resolvedSpeed
        DispatchQueue.main.asyncAfter(deadline: .now() + hold) { active = false }
    }

    func body(content: Content) -> some View {
        let driven = Group {
            switch effect.kind {
            case .bounce:
                content.symbolEffect(.bounce, options: options, value: tick)
            case .pulse:
                if repeating { content.symbolEffect(.pulse, options: options, isActive: true) }
                else { content.symbolEffect(.pulse, options: options, value: tick) }
            case .variableColor:
                let base = (effect.cumulative == true) ? VariableColorSymbolEffect.variableColor.cumulative
                                                       : VariableColorSymbolEffect.variableColor.iterative
                let v = (effect.reversing == true) ? base.reversing : base.nonReversing
                content.symbolEffect(v, options: options, isActive: repeating || active)
            case .scale:
                content.symbolEffect(.scale.up, options: options, isActive: repeating || active)
            case .appear:
                content.symbolEffect(.appear, isActive: !shown)
            case .disappear:
                content.symbolEffect(.disappear, isActive: trigger == .onAppear ? shown : gone)
            case .replace:
                content.contentTransition(.symbolEffect(.replace))
            }
        }
        driven
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    shown = true
                    if trigger == .onAppear { fire() }
                }
            }
            // bounce is a one-shot effect: "repeating" replays it on a timer for as long as the view is on screen.
            .task(id: repeating && effect.kind == .bounce) {
                guard repeating, effect.kind == .bounce else { return }
                try? await Task.sleep(nanoseconds: 350_000_000)
                while !Task.isCancelled {
                    tick += 1
                    try? await Task.sleep(nanoseconds: UInt64((1.6 / effect.resolvedSpeed) * 1_000_000_000))
                }
            }
            .onChange(of: changeKey) { _ in if trigger == .onChange { fire() } }
            .onHover { inside in if inside, trigger == .onHover { fire() } }
    }
}
