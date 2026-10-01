import SwiftUI
import AppKit

/// Stable selection key: item ids are only unique per app, so the app is part of the key.
struct HistoryKey: Hashable {
    let app: String
    let id: String
    init(_ item: HeraldHistoryItem) { app = item.app; id = item.id }
}

/// One row of the History list: the notification drawn by the SAME `BannerView` live banners use (via
/// `BannerPreviewFactory`, whose callbacks are no-ops), then a status line.
///
/// The preview is hit-test transparent: its close/snooze/action buttons are inert in a history row and
/// must not swallow the click that opens the url or selects the row.
struct HistoryRow: View {
    let item: HeraldHistoryItem
    let appName: String
    let icon: NSImage

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HistoryRowPreview(item: item, appName: appName, icon: icon)
                .allowsHitTesting(false)
            HStack(spacing: 6) {
                if item.dismissedAt == nil {
                    Circle().fill(Color.accentColor).frame(width: 7, height: 7).help("Not dismissed yet")
                }
                HistoryStatusLine(item: item, appName: appName)
            }
            .padding(.leading, 4)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

/// Owns the preview `BannerModel` so it is built once per row instead of on every SwiftUI re-render,
/// and rebuilt only when the stored item actually changes (e.g. re-delivered under the same id).
struct HistoryRowPreview: View {
    let item: HeraldHistoryItem
    let appName: String
    let icon: NSImage
    @StateObject private var holder = Holder()

    @MainActor
    final class Holder: ObservableObject {
        var model: BannerModel?
        var built: HeraldHistoryItem?
    }

    var body: some View {
        BannerView(model: resolvedModel())
            .frame(width: BannerView.width, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func resolvedModel() -> BannerModel {
        if let m = holder.model, holder.built == item { return m }
        let img = item.imagePath.flatMap { NSImage(contentsOfFile: $0) }
        let m = BannerPreviewFactory.model(for: item.notification, appName: appName, icon: icon,
                                           image: img, deliveredAt: item.deliveredAt)
        holder.model = m; holder.built = item
        return m
    }
}

/// "BidBot - Oct 1, 3:41 PM - Dismissed - used Archive" style caption.
struct HistoryStatusLine: View {
    let item: HeraldHistoryItem
    let appName: String

    var body: some View {
        Text(text).font(.caption).foregroundStyle(.tertiary).lineLimit(1)
    }

    private var text: String {
        var parts = [appName, item.deliveredAt.formatted(date: .abbreviated, time: .shortened)]
        if let marker = item.snoozeMarker() {
            parts.append(marker)
        } else if item.dismissedAt == nil {
            parts.append("Active")
        } else if let a = item.actionUsed {
            switch a {
            case "open": parts.append("Opened")
            case "timeout": parts.append("Timed out")
            default: parts.append("Used \(a)")
            }
        } else {
            parts.append("Dismissed")
        }
        return parts.joined(separator: " \u{00B7} ")
    }
}
