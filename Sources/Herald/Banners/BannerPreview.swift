import SwiftUI
import AppKit

/// Builds a `BannerModel` without a live panel, so the composer, the designer, history and the preview PNG
/// render the exact view real banners use. All callbacks stay no-ops (a preview must never dismiss, run a
/// command or post a callback).
///
/// - `notification`: already template-RESOLVED when it came from a v1 template (the presentation fields are
///   read straight from it); a v2 template needs no such step because it is passed in whole.
/// - `template`: a v2 grid template to draw. nil (or a v1 template) draws the built-in grid for the
///   notification's `layout`.
/// - `fields`: data for the bindings, replacing the notification's own (designer samples, "last real
///   notification"). nil binds the notification (`TemplateResolver.fields`).
/// - `manifest`: gives the notification's buttons their declared action ids, so a template's rules match them.
@MainActor
enum BannerPreviewFactory {
    static func model(for notification: HeraldNotification, appName: String, icon: NSImage,
                      image: NSImage?, deliveredAt: Date = Date(), template: HeraldTemplate? = nil,
                      fields: [String: HeraldFieldValue]? = nil, manifest: HeraldManifest? = nil) -> BannerModel {
        let item = HeraldHistoryItem(id: notification.id ?? "preview", app: notification.app,
                                     notification: notification, deliveredAt: deliveredAt)
        return BannerModel(item: item, appName: appName, icon: icon, image: image,
                           template: template, manifest: manifest, fields: fields)
    }
}

/// A banner on a desktop-like backdrop, optionally forced to one appearance. The translucent card looks
/// flat on a plain window, so the backdrop (a soft gradient in the forced appearance) shows what the
/// banner will look like over a wallpaper. `scheme == nil` follows the surrounding environment.
struct BannerPreviewView: View {
    @ObservedObject var model: BannerModel
    var scheme: ColorScheme? = nil

    var body: some View {
        if let scheme {
            content.environment(\.colorScheme, scheme)
        } else {
            content
        }
    }

    private var content: some View {
        BannerView(model: model)
            .padding(16)
            .background(Backdrop())
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private struct Backdrop: View {
        @Environment(\.colorScheme) private var scheme
        var body: some View {
            LinearGradient(
                colors: scheme == .dark
                    ? [Color(red: 0.10, green: 0.12, blue: 0.22), Color(red: 0.24, green: 0.14, blue: 0.30)]
                    : [Color(red: 0.62, green: 0.78, blue: 0.95), Color(red: 0.93, green: 0.80, blue: 0.88)],
                startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }
}

/// Sample data shared by the SwiftUI previews (and handy for any preview of a banner-shaped view).
@MainActor
enum BannerSamples {
    /// A soft two-colour gradient standing in for a screenshot or product photo.
    static func image(width: CGFloat = 640, height: CGFloat = 360) -> NSImage {
        NSImage(size: NSSize(width: width, height: height), flipped: false) { rect in
            let g = NSGradient(colors: [NSColor(srgbRed: 0.98, green: 0.55, blue: 0.30, alpha: 1),
                                        NSColor(srgbRed: 0.45, green: 0.30, blue: 0.85, alpha: 1)])
            g?.draw(in: rect, angle: 35)
            return true
        }
    }

    static func icon() -> NSImage {
        NSImage(size: NSSize(width: 64, height: 64), flipped: false) { rect in
            NSColor(srgbRed: 0.10, green: 0.55, blue: 0.95, alpha: 1).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 14, yRadius: 14).fill()
            return true
        }
    }

    /// One representative notification per layout, exercising every presentation field.
    static func notification(layout: HeraldLayout, accent: String? = "#0A84FF") -> HeraldNotification {
        var n = HeraldNotification(
            app: "bidbot", id: "sample-\(layout.rawValue)",
            title: "Bid accepted",
            subtitle: "Acme RFP",
            body: "Your bid of $4,200 was accepted. [Open proposal](https://example.com/proposal) to review the terms and next steps with the client.",
            url: "https://example.com/proposal",
            buttons: [HeraldButton(label: "Open", url: "https://example.com/proposal"),
                      HeraldButton(label: "Archive", style: "destructive", command: "bidbot archive 42")],
            snooze: true,
            reminder: HeraldReminder(title: "Follow up on Acme"))
        n.layout = layout
        n.accentColor = accent
        n.showSubtitle = true
        n.showBody = true
        n.showTimestamp = true
        n.maxBodyLines = 4
        return n
    }

    static func model(layout: HeraldLayout, accent: String? = "#0A84FF", withImage: Bool = true) -> BannerModel {
        BannerPreviewFactory.model(for: notification(layout: layout, accent: accent), appName: "BidBot",
                                   icon: icon(), image: withImage && layout != .compact ? image() : nil)
    }
}

extension BannerSamples {
    /// A v2 template over the standard 3 x 4 grid: image, title across two columns, an issuer icon and a count
    /// badge on the right, subtitle, body, and the action row.
    nonisolated static func gridTemplate() -> HeraldTemplate {
        let cells = [
            HeraldCell(id: "image", row: 0, col: 0, rowSpan: 3, component: .image(HeraldImageComponent(binding: "{image}", fit: .cover, cornerRadius: 10, aspectRatio: 1))),
            HeraldCell(id: "title", row: 0, col: 1, colSpan: 2, component: .text(HeraldTextComponent(binding: "{title}", style: .title, maxLines: 2))),
            HeraldCell(id: "badge", row: 0, col: 3, align: .topTrailing, component: .badge(HeraldBadgeComponent(binding: "{count}"))),
            HeraldCell(id: "subtitle", row: 1, col: 1, colSpan: 2, component: .text(HeraldTextComponent(binding: "{subtitle}", style: .subtitle, maxLines: 2))),
            HeraldCell(id: "icon", row: 1, col: 3, align: .topTrailing, component: .issuerIcon(HeraldIssuerIconComponent(size: 22))),
            HeraldCell(id: "body", row: 2, col: 1, colSpan: 2, component: .text(HeraldTextComponent(binding: "{body}", style: .body, maxLines: 3))),
            HeraldCell(id: "time", row: 2, col: 3, align: .topTrailing, component: .timestamp(HeraldTimestampComponent())),
            HeraldCell(id: "actions", row: 3, col: 0, colSpan: 4, component: .actions(HeraldActionsComponent(source: .merged, layout: .row, maxVisible: 3))),
        ]
        let grid = HeraldGrid(rows: 4, cols: 4, rowSizes: [.auto, .auto, .auto, .auto],
                              colSizes: [.points(72), .fill, .fill, .auto], gap: 8, padding: 14, width: 400)
        return HeraldTemplate(name: "sample", app: "bidbot", grid: grid, cells: cells)
    }

    static func gridModel(template: HeraldTemplate = gridTemplate(), withImage: Bool = true,
                          fields: [String: HeraldFieldValue]? = nil) -> BannerModel {
        var n = notification(layout: .imageLeft)
        n.metadata = .object(["count": .number(3)])
        return BannerPreviewFactory.model(for: n, appName: "BidBot", icon: icon(), image: withImage ? image() : nil,
                                          template: template, fields: fields)
    }
}

struct BannerView_Previews: PreviewProvider {
    static var previews: some View {
        ForEach(HeraldLayout.allCases, id: \.self) { layout in
            BannerPreviewView(model: BannerSamples.model(layout: layout), scheme: .light)
                .previewDisplayName("\(layout.rawValue) light")
            BannerPreviewView(model: BannerSamples.model(layout: layout), scheme: .dark)
                .previewDisplayName("\(layout.rawValue) dark")
        }
        // Edge cases: no accent, no image, a pale accent that must be darkened on light, a dark one lightened on dark.
        BannerPreviewView(model: BannerSamples.model(layout: .hero, accent: nil, withImage: false), scheme: .light)
            .previewDisplayName("hero without image")
        BannerPreviewView(model: BannerSamples.model(layout: .imageLeft, accent: "#FFE066"), scheme: .light)
            .previewDisplayName("pale accent on light")
        BannerPreviewView(model: BannerSamples.model(layout: .imageLeft, accent: "#101A4A"), scheme: .dark)
            .previewDisplayName("dark accent on dark")
        BannerPreviewView(model: BannerSamples.gridModel(), scheme: .light).previewDisplayName("grid light")
        BannerPreviewView(model: BannerSamples.gridModel(), scheme: .dark).previewDisplayName("grid dark")
        BannerPreviewView(model: BannerSamples.gridModel(withImage: false), scheme: .light)
            .previewDisplayName("grid without image")
    }
}
