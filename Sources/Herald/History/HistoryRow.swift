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
            SpeechReplayButton(item: item).padding(.leading, 4)
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
        let model = resolvedModel()
        BannerView(model: model)
            .frame(width: model.bannerWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func resolvedModel() -> BannerModel {
        if let m = holder.model, holder.built == item { return m }
        let img = item.imagePath.flatMap { NSImage(contentsOfFile: $0) }
        // The template the notification named (saved for its app, else a built-in) and the issuer's manifest, so
        // History draws a v2 notification the way its banner looked.
        let controller = AppController.shared
        let template = controller.templates.template(for: item.notification)
            ?? item.notification.template.flatMap { BuiltinTemplates.named($0, app: item.app) }
        let m = BannerPreviewFactory.model(for: item.notification, appName: appName, icon: icon,
                                           image: img, deliveredAt: item.deliveredAt, template: template,
                                           fields: item.fields, manifest: controller.manifests.get(app: item.app))
        holder.model = m; holder.built = item
        return m
    }
}

/// "BidBot - Oct 1, 3:41 PM - Dismissed - used Archive" style caption.
struct HistoryStatusLine: View {
    let item: HeraldHistoryItem
    let appName: String

    var body: some View {
        Text(text).font(.caption).foregroundStyle(.tertiary).lineLimit(item.followUp == nil ? 1 : 2)
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
        if let note = item.actionNote { parts.append(note) }
        if let f = item.followUp { parts.append(Self.followUpText(f)) }
        return parts.joined(separator: " \u{00B7} ")
    }

    /// "Follow-up ran: Forward, 14:05, after 10 minutes unattended", "Follow-up failed: exit 1", "Follow-up waiting for approval: Forward".
    static func followUpText(_ f: HeraldFollowUpRecord) -> String {
        let when = f.ranAt.formatted(date: .abbreviated, time: .shortened)
        let unattended = f.unattendedSeconds.map { ", unattended \(HeraldFollowUp.describe(seconds: Double($0)))" } ?? ""
        switch f.outcome {
        case .ran: return "Follow-up ran: \(f.action) \u{00B7} \(when)\(unattended)"
        case .failed: return "Follow-up failed: \((f.detail?.isEmpty == false) ? f.detail! : f.action) \u{00B7} \(when)\(unattended)"
        case .waitingForApproval: return "Follow-up waiting for approval: \(f.action) \u{00B7} \(when)\(unattended)"
        }
    }
}
