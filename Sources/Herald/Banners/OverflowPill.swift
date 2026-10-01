import SwiftUI
import AppKit

@MainActor
final class OverflowPillModel: ObservableObject {
    @Published var count = 0
    var onHistory: () -> Void = {}
    var onDismissAll: () -> Void = {}
}

/// "+N more | Dismiss All": stands in for the banners that do not fit on the screen (or that were not put back
/// on screen at launch), so a busy sender can never leave banners that cannot be reached.
struct OverflowPill: View {
    @ObservedObject var model: OverflowPillModel

    var body: some View {
        HStack(spacing: 8) {
            Button { model.onHistory() } label: { Text("+\(model.count) more") }
                .help("Open History")
            Divider().frame(height: 12)
            Button { model.onDismissAll() } label: { Text("Dismiss All") }
        }
        .buttonStyle(.plain)
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .frame(height: BannerCenter.stubHeight)
        .background(Capsule().fill(.regularMaterial))
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
        .fixedSize()
    }
}

/// The panel that shows one `OverflowPill` in one screen corner.
@MainActor
final class OverflowStub {
    let panel: BannerPanel
    let host: NSHostingView<OverflowPill>
    let model = OverflowPillModel()
    var width: CGFloat = 150

    init() {
        host = NSHostingView(rootView: OverflowPill(model: model))
        panel = BannerPanel(contentRect: NSRect(x: 0, y: 0, width: 150, height: BannerCenter.stubHeight),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.contentView = host
    }

    /// Updates the count and returns the width the pill needs (it grows with the digits).
    func update(count: Int) -> CGFloat {
        model.count = count
        host.layoutSubtreeIfNeeded()
        width = max(110, ceil(host.fittingSize.width))
        return width
    }
}
