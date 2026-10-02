import SwiftUI
import AppKit

/// The browser as the Designer hosts it. `current` reads the Symbol panel's styling live (weight, mode, colours)
/// and `apply` writes the picked name to the component; both are closures over the panel's binding.
struct SymbolBrowserHost: View {
    /// Redraws the preview when anything in the Designer (the styling in the Symbol panel) changes.
    @ObservedObject var designer: DesignerModel
    @ObservedObject var model: SymbolBrowserModel = .shared
    let current: () -> HeraldSymbol
    let apply: (String) -> Void
    var closeAfterUse: (() -> Void)?
    var onClose: (() -> Void)?
    var onFloat: (() -> Void)?

    var body: some View {
        SymbolBrowserView(model: model, style: current(), onUse: { name in
            apply(name)
            model.noteUsed(name)
            closeAfterUse?()
        }, onClose: onClose, onFloat: onFloat)
    }
}

/// The browser's floating panel: a child of the Designer window that never takes focus from another app. It is
/// non-activating, shown with `orderFront` (never `makeKeyAndOrderFront`, never `NSApp.activate`), becomes key
/// only when a text field in it (the search) is clicked, and hides with the app. Closing the Designer closes it.
@MainActor
enum SymbolBrowserPanel {
    private final class Panel: NSPanel {
        override var canBecomeKey: Bool { true }
        override var canBecomeMain: Bool { false }
    }

    private static var panel: Panel?
    private static var host: NSHostingView<AnyView>?

    static var isShown: Bool { panel?.isVisible ?? false }

    /// Shows (or refreshes) the panel as a child of `parent` (the Designer window). Without a parent nothing opens:
    /// the panel belongs to the Designer.
    static func show<Content: View>(parent: NSWindow?, @ViewBuilder content: () -> Content) {
        guard let parent else { return }
        let p: Panel
        if let existing = panel { p = existing } else {
            p = Panel(contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
                      styleMask: [.titled, .closable, .resizable, .utilityWindow, .nonactivatingPanel],
                      backing: .buffered, defer: false)
            p.title = "SF Symbols"
            p.isReleasedWhenClosed = false
            p.isFloatingPanel = false          // a child window orders with its parent, never above other apps
            p.becomesKeyOnlyIfNeeded = true
            p.hidesOnDeactivate = true
            p.worksWhenModal = false
            p.minSize = NSSize(width: 760, height: 460)
            p.setFrameAutosaveName("HeraldSymbolBrowser")
            panel = p
        }
        let hosting = NSHostingView(rootView: AnyView(content()))
        host = hosting
        p.contentView = hosting
        if p.parent !== parent {
            p.parent?.removeChildWindow(p)
            if !p.setFrameUsingName("HeraldSymbolBrowser") {
                p.setContentSize(NSSize(width: 900, height: 600))
                var f = p.frame
                f.origin = NSPoint(x: parent.frame.maxX - f.width - 24, y: parent.frame.maxY - f.height - 60)
                p.setFrameOrigin(f.origin)
            }
            parent.addChildWindow(p, ordered: .above)
        }
        p.orderFront(nil)
    }

    static func close() { panel?.close() }
}
