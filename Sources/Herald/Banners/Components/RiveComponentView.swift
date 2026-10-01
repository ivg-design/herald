import SwiftUI
import AppKit
import RiveRuntime

/// The `rive` grid component: a Rive animation inside a banner cell (DESIGN 7.7).
///
/// ```swift
/// RiveComponentView(component: rive, app: item.notification.app, manifest: manifest, fields: fields) { actionID in
///     run(actionID)   // the id of `rive.action` / `rive.actionRef`, on a click
/// }
/// ```
///
/// What it does:
///  * Loads the `.riv` named by `component.asset` (a manifest asset, copied into Application Support/Herald/assets/<app>/)
///    or `component.path`, through `AssetStore` (so the extension and the 10 MB cap are checked first).
///  * Plays the state machine `component.stateMachine` (else the manifest asset's, else the file's default, else its
///    first; a file with only linear animations plays the first one, and `component.loop` picks loop or one shot).
///  * Binds `component.inputBindings` (`inputName` -> `{token}`, a literal, or `hover` / `pressed`). Number, boolean and
///    trigger inputs are told apart by the state machine itself: a number takes the token's number (a list its length,
///    a boolean 1/0), a boolean its truthiness, a trigger fires when the bound value changes to something truthy
///    (so a bell can ring when `{count}` goes up on a same-id update). A token that is absent leaves the input alone.
///    `hover` and `pressed` follow the pointer (an NSTrackingArea, so they work in a non-activating banner panel).
///  * Calls `onAction` with the click action's id when the animation is clicked. Without an action the view lets
///    clicks fall through to the banner body (it still tracks hover). Rive's own pointer listeners keep working.
///  * Never throws or crashes the banner: a file that cannot be found, is too big, is not a Rive file, or names a
///    missing artboard / state machine renders a dashed placeholder with the reason.
///
/// Sizing: the view proposes `component.height` and `component.aspectRatio` (width / height), falling back to the
/// artboard's own proportions. The animation is scaled to fit (`contain`), centred.
///
/// An NSViewRepresentable does not draw under SwiftUI's `ImageRenderer`; offscreen previews should use
/// `RiveComponentPlaceholder` for this component instead.
struct RiveComponentView: NSViewRepresentable {
    var component: HeraldRiveComponent
    /// The notification's app id: where the manifest asset copies live.
    var app: String
    var manifest: HeraldManifest? = nil
    /// The resolved fields of the notification (`TemplateResolver.fields(for:manifest:)`, or sample fields).
    var fields: [String: HeraldFieldValue] = [:]
    var assets: AssetStore = .shared
    var onAction: (String) -> Void = { _ in }

    final class Coordinator {
        var onAction: (String) -> Void = { _ in }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> RiveHostView {
        let view = RiveHostView()
        context.coordinator.onAction = onAction
        view.onAction = { [weak coordinator = context.coordinator] id in coordinator?.onAction(id) }
        view.apply(config)
        return view
    }

    func updateNSView(_ view: RiveHostView, context: Context) {
        context.coordinator.onAction = onAction
        view.apply(config)
    }

    static func dismantleNSView(_ view: RiveHostView, coordinator: Coordinator) {
        view.tearDown()
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: RiveHostView, context: Context) -> CGSize? {
        nsView.fittingSize(for: proposal)
    }

    private var config: RiveHostView.Config {
        .init(component: component, app: app, manifest: manifest, fields: fields, assets: assets)
    }
}

/// What a Rive component shows where `RiveComponentView` cannot run (offscreen `ImageRenderer` previews).
struct RiveComponentPlaceholder: View {
    var title: String

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: "play.rectangle")
            Text(title).lineLimit(1)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 3])).foregroundStyle(.tertiary))
    }
}

// MARK: - Host view

/// Owns the RiveViewModel and its RiveView (or the placeholder), the pointer tracking, and the input binding.
final class RiveHostView: NSView {
    struct Config {
        var component: HeraldRiveComponent
        var app: String
        var manifest: HeraldManifest?
        var fields: [String: HeraldFieldValue]
        var assets: AssetStore
    }

    /// What decides that the animation has to be loaded again; everything else only re-binds inputs.
    private struct LoadKey: Equatable {
        var app: String
        var asset: String?
        var path: String?
        var stateMachine: String?
        var artboard: String?
        var loop: Bool?
        var manifestAssetPath: String?
        var manifestStateMachine: String?
    }

    enum InputKind: String { case number, bool, trigger }

    private enum LoadError: LocalizedError {
        case artboard(String, [String])
        case stateMachine(String, [String])
        case nothingToPlay
        case rive(String)

        var errorDescription: String? {
            switch self {
            case .artboard(let n, let all): return "no artboard \u{201C}\(n)\u{201D}" + Self.available(all)
            case .stateMachine(let n, let all): return "no state machine \u{201C}\(n)\u{201D}" + Self.available(all)
            case .nothingToPlay: return "the file has no state machine or animation"
            case .rive(let why): return why
            }
        }

        private static func available(_ all: [String]) -> String {
            var seen = Set<String>()
            let names = all.filter { seen.insert($0).inserted }
            return names.isEmpty ? "" : " (available: \(names.prefix(6).joined(separator: ", "))\(names.count > 6 ? ", ..." : ""))"
        }
    }

    var onAction: (String) -> Void = { _ in }

    private var config: Config?
    private var loadKey: LoadKey?
    private(set) var viewModel: RiveViewModel?
    private var riveView: RiveView?
    private var placeholder: RiveLoadFailureView?
    /// The state machine's inputs by name, as found in the file (empty while the placeholder shows).
    private(set) var inputKinds: [String: InputKind] = [:]
    /// The values last written to the state machine from data bindings.
    private(set) var applied: [String: HeraldFieldValue] = [:]
    /// Why the animation is not showing (the placeholder's text); nil while it plays.
    private(set) var loadError: String?
    private var artboardSize: CGSize?
    private var pressing = false
    private var cursorPushed = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(true)
    }

    required init?(coder: NSCoder) { nil }

    // MARK: Config

    func apply(_ new: Config) {
        config = new
        let asset = new.component.asset.flatMap { id in new.manifest?.assets.first { $0.id == id } }
        let key = LoadKey(app: new.app, asset: new.component.asset, path: new.component.path,
                          stateMachine: new.component.stateMachine, artboard: new.component.artboard,
                          loop: new.component.loop, manifestAssetPath: asset?.path,
                          manifestStateMachine: asset?.stateMachine)
        if key != loadKey {
            loadKey = key
            load(new, manifestAsset: asset)
        }
        applyInputs()
        updateAccessibility()
        window?.invalidateCursorRects(for: self)
    }

    private var clickActionID: String? {
        guard let c = config?.component else { return nil }
        if let id = c.action?.id, !id.isEmpty { return id }
        if let ref = c.actionRef, !ref.isEmpty { return ref }
        return nil
    }

    /// Whether this view has to receive mouse buttons (a click action, or a `pressed` input); a view that only
    /// tracks hover is invisible to hit testing so the banner body keeps its own click.
    private var isInteractive: Bool {
        guard viewModel != nil else { return false }
        if clickActionID != nil { return true }
        return config?.component.inputBindings.values.contains { RiveInputBinding.pointerKeyword($0) == "pressed" } ?? false
    }

    // MARK: Loading

    private func load(_ cfg: Config, manifestAsset: HeraldAsset?) {
        clearContent()
        loadError = nil
        do {
            let url = try cfg.assets.resolve(cfg.component, app: cfg.app, manifest: cfg.manifest)
            let data = try Data(contentsOf: url)
            let file: RiveFile
            do { file = try RiveFile(data: data, loadCdn: true) }
            catch { throw LoadError.rive("\u{201C}\(url.lastPathComponent)\u{201D}: \(error.localizedDescription)") }

            let artboardName = cfg.component.artboard.flatMap { $0.isEmpty ? nil : $0 }
            if let name = artboardName, !file.artboardNames().contains(name) {
                throw LoadError.artboard(name, file.artboardNames())
            }
            let artboard: RiveArtboard
            do { artboard = try artboardName.map { try file.artboard(fromName: $0) } ?? file.artboard() }
            catch { throw LoadError.rive(error.localizedDescription) }

            let stateMachines = artboard.stateMachineNames()
            let animations = artboard.animationNames()
            let wanted = [cfg.component.stateMachine, manifestAsset?.stateMachine]
                .compactMap { $0 }.first { !$0.isEmpty }
            var machine: String?
            var animation: String?
            if let wanted {
                guard stateMachines.contains(wanted) else { throw LoadError.stateMachine(wanted, stateMachines) }
                machine = wanted
            } else if let first = stateMachines.first {
                machine = artboard.defaultStateMachine()?.name() ?? first
            } else if let first = animations.first {
                animation = first
            } else {
                throw LoadError.nothingToPlay
            }

            let model = RiveModel(riveFile: file)
            let vm: RiveViewModel
            if let machine {
                vm = RiveViewModel(model, stateMachineName: machine, fit: .contain, alignment: .center,
                                   autoPlay: true, artboardName: artboardName)
            } else {
                vm = RiveViewModel(model, animationName: animation, fit: .contain, alignment: .center,
                                   autoPlay: true, artboardName: artboardName)
            }
            let view = vm.createRiveView()
            view.frame = bounds
            view.autoresizingMask = [.width, .height]
            addSubview(view)
            if animation != nil, let loop = cfg.component.loop {
                vm.play(animationName: nil, loop: loop ? .loop : .oneShot, direction: .autoDirection)
            }

            viewModel = vm
            riveView = view
            artboardSize = CGSize(width: artboard.width(), height: artboard.height())
            if let machine, let instance = try? artboard.stateMachine(fromName: machine) {
                inputKinds = Self.inputKinds(of: instance)
            }
        } catch {
            loadError = error.localizedDescription
            showPlaceholder(error.localizedDescription)
        }
        needsLayout = true
    }

    private static func inputKinds(of machine: RiveStateMachineInstance) -> [String: InputKind] {
        var out: [String: InputKind] = [:]
        for name in machine.inputNames() {
            guard let input = try? machine.input(fromName: name) else { continue }
            if input.isTrigger() { out[name] = .trigger }
            else if input.isBoolean() { out[name] = .bool }
            else if input.isNumber() { out[name] = .number }
        }
        return out
    }

    private func clearContent() {
        popCursor()
        pressing = false
        viewModel?.pause()
        viewModel?.deregisterView()
        riveView?.removeFromSuperview()
        placeholder?.removeFromSuperview()
        viewModel = nil; riveView = nil; placeholder = nil
        inputKinds = [:]; applied = [:]; artboardSize = nil
    }

    private func showPlaceholder(_ message: String) {
        let p = RiveLoadFailureView(message: message)
        p.frame = bounds
        p.autoresizingMask = [.width, .height]
        addSubview(p)
        placeholder = p
        toolTip = message
    }

    /// Releases the animation. Called when SwiftUI removes the component (a banner closing).
    func tearDown() {
        clearContent()
        loadKey = nil
        config = nil
    }

    // MARK: Inputs

    /// Binds every non-pointer input from the current fields. Only values that changed are written, so a redraw
    /// (hover, a timer) never re-fires a trigger.
    private func applyInputs() {
        guard let vm = viewModel, let cfg = config else { return }
        for (name, binding) in cfg.component.inputBindings.sorted(by: { $0.key < $1.key }) {
            guard let kind = inputKinds[name],
                  let value = RiveInputBinding.value(for: binding, fields: cfg.fields),
                  applied[name] != value else { continue }
            applied[name] = value
            switch kind {
            case .number: if let d = RiveInputBinding.number(from: value) { vm.setInput(name, value: d) }
            case .bool: vm.setInput(name, value: RiveInputBinding.truthy(value))
            case .trigger: if RiveInputBinding.truthy(value) { vm.triggerInput(name) }
            }
        }
    }

    /// Drives every input bound to the pointer keyword: a boolean follows `active`, a number is 1 or 0, a trigger
    /// fires when `active` becomes true.
    private func setPointer(_ keyword: String, active: Bool) {
        guard let vm = viewModel, let c = config?.component else { return }
        for (name, binding) in c.inputBindings where RiveInputBinding.pointerKeyword(binding) == keyword {
            switch inputKinds[name] {
            case .bool?: vm.setInput(name, value: active)
            case .number?: vm.setInput(name, value: active ? 1.0 : 0.0)
            case .trigger?: if active { vm.triggerInput(name) }
            case nil: break
            }
        }
    }

    // MARK: Pointer

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard isInteractive, bounds.contains(convert(point, from: superview)) else { return nil }
        return self
    }

    override func mouseEntered(with event: NSEvent) {
        setPointer("hover", active: true)
        if clickActionID != nil, !cursorPushed { NSCursor.pointingHand.push(); cursorPushed = true }
    }

    override func mouseExited(with event: NSEvent) {
        if pressing { pressing = false; setPointer("pressed", active: false) }
        setPointer("hover", active: false)
        popCursor()
    }

    override func mouseDown(with event: NSEvent) {
        pressing = true
        setPointer("pressed", active: true)
        riveView?.mouseDown(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        riveView?.mouseDragged(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        riveView?.mouseUp(with: event)
        let wasPressing = pressing
        pressing = false
        setPointer("pressed", active: false)
        if wasPressing, bounds.contains(convert(event.locationInWindow, from: nil)), let id = clickActionID {
            onAction(id)
        }
    }

    private func popCursor() {
        if cursorPushed { NSCursor.pop(); cursorPushed = false }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { popCursor(); pressing = false }
    }

    // MARK: Accessibility

    private func updateAccessibility() {
        guard let c = config?.component else { return }
        let name = c.asset ?? c.path.map { ($0 as NSString).lastPathComponent } ?? "Animation"
        setAccessibilityRole(clickActionID != nil ? .button : .image)
        setAccessibilityLabel(placeholder == nil ? name : "\(name), unavailable")
    }

    override func accessibilityPerformPress() -> Bool {
        guard let id = clickActionID else { return false }
        onAction(id)
        return true
    }

    // MARK: Sizing

    /// The size to ask SwiftUI for: `height` and `aspectRatio` from the component, else the artboard's proportions.
    func fittingSize(for proposal: ProposedViewSize) -> CGSize {
        let c = config?.component
        let artboardAspect = artboardSize.flatMap { $0.height > 0 ? $0.width / $0.height : nil }
        let aspect = c?.aspectRatio.flatMap { $0 > 0 ? $0 : nil } ?? artboardAspect ?? 4
        let fixedHeight = c?.height.flatMap { $0 > 0 ? $0 : nil }
        func finite(_ v: CGFloat?) -> CGFloat? { v.flatMap { $0.isFinite && $0 > 0 ? $0 : nil } }

        var width = finite(proposal.width)
        var height = fixedHeight ?? (placeholder != nil ? 44 : nil)
        if height == nil, width == nil {
            // Nothing proposed: the artboard's own size, or a modest default.
            if let s = artboardSize, s.width > 0, s.height > 0 { return Self.clamp(s) }
            height = finite(proposal.height) ?? 64
        }
        if height == nil, let w = width { height = w / aspect }
        if width == nil, let h = height { width = h * aspect }
        return Self.clamp(CGSize(width: width ?? 64, height: height ?? 64))
    }

    private static func clamp(_ s: CGSize) -> CGSize {
        CGSize(width: min(max(s.width, 1), 2000), height: min(max(s.height, 1), 2000))
    }

    override func layout() {
        super.layout()
        riveView?.frame = bounds
        placeholder?.frame = bounds
    }
}

// MARK: - Placeholder

/// A dashed rounded rectangle with a warning symbol and the reason a Rive file did not load.
private final class RiveLoadFailureView: NSView {
    private let icon = NSImageView()
    private let label = NSTextField(wrappingLabelWithString: "")

    init(message: String) {
        super.init(frame: .zero)
        icon.image = NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: "Animation unavailable")
        icon.contentTintColor = .systemOrange
        icon.imageScaling = .scaleProportionallyDown
        label.stringValue = message
        label.font = .systemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        label.maximumNumberOfLines = 3
        label.lineBreakMode = .byTruncatingTail
        label.isSelectable = false
        addSubview(icon)
        addSubview(label)
        toolTip = message
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 8, yRadius: 8)
        path.lineWidth = 1
        path.setLineDash([4, 3], count: 2, phase: 0)
        NSColor.tertiaryLabelColor.setStroke()
        path.stroke()
    }

    override func layout() {
        super.layout()
        let pad: CGFloat = 8, iconSize: CGFloat = 16
        let showText = bounds.width >= 64
        label.isHidden = !showText
        if !showText {
            icon.frame = NSRect(x: (bounds.width - iconSize) / 2, y: (bounds.height - iconSize) / 2, width: iconSize, height: iconSize)
            return
        }
        let textX = pad + iconSize + 6
        let availableWidth = max(bounds.width - textX - pad, 1)
        let size = label.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: availableWidth, height: .greatestFiniteMagnitude))
            ?? NSSize(width: availableWidth, height: 14)
        let textHeight = min(size.height, max(bounds.height - 2 * 4, 1))
        label.frame = NSRect(x: textX, y: (bounds.height - textHeight) / 2, width: availableWidth, height: textHeight)
        icon.frame = NSRect(x: pad, y: (bounds.height - iconSize) / 2, width: iconSize, height: iconSize)
    }
}
