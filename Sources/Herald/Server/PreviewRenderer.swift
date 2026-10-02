import SwiftUI
import AppKit

/// Renders a template with data offscreen to PNG (`POST /v1/preview`, DESIGN 7.5). The banner is the one
/// `GridBannerView` that live banners draw, so what an agent or the designer sees is what the user gets; only
/// the surroundings are the renderer's: a desktop-like backdrop (the translucent card looks flat on nothing,
/// the same one the Composer preview uses) and the forced appearance.
@MainActor
enum PreviewRenderer {
    enum RenderError: Error, LocalizedError {
        case noImage, encodingFailed
        var errorDescription: String? {
            switch self {
            case .noImage: return "the preview could not be rendered"
            case .encodingFailed: return "the preview image could not be encoded"
            }
        }
    }

    /// Pixels on a side at scale 3 are capped so a runaway grid (width 800, tall rows) cannot ask for a huge bitmap.
    static let maxPixels: CGFloat = 8192

    // MARK: Entry points

    /// The PNG for a plan. `icon` is the issuer's icon; `image` the picture bound to `{image}`, if any.
    static func png(plan: PreviewPlan, appName: String, icon: NSImage, image: NSImage?,
                    appearance: PreviewAppearance, scale: Double, confirmation: BannerConfirmation? = nil,
                    stackCount: Int = 1, stackExpanded: Bool = false) throws -> Data {
        let item = HeraldHistoryItem(id: plan.notification.id ?? "preview", app: plan.notification.app,
                                     notification: plan.notification, deliveredAt: plan.deliveredAt,
                                     fields: plan.fields)
        // The template as asked for (the model maps a v1 one onto its built-in grid and takes its action
        // rules) and the plan's fields, so the preview binds exactly what a delivery would. Nothing is wired
        // to the model's callbacks: a preview never dismisses, runs or sends.
        let model = BannerModel(item: item, appName: appName, icon: icon, image: image,
                                template: plan.template, manifest: plan.manifest, fields: plan.fields)
        // ImageRenderer cannot draw an NSViewRepresentable, so a Rive component shows its static placeholder.
        model.liveAnimations = false
        // A pending inline confirmation replaces the actions row, as in a live banner (DESIGN 8).
        model.confirmation = confirmation
        // The top card of a stack (DESIGN section 9): the stacked-card edges and the count badge, `{stack.count}` filled.
        if stackCount > 1, stackExpanded {
            // The open stack: the banner repeated, newest first, so the list, its scrolling cap and its footer can be seen.
            let stack = StackModel()
            stack.count = stackCount; stack.expanded = true
            stack.members = (0..<stackCount).map { i in
                var n = plan.notification
                n.title = "\(n.title) #\(stackCount - i)"
                let member = BannerModel(item: HeraldHistoryItem(id: "preview-\(i)", app: n.app, notification: n, deliveredAt: plan.deliveredAt,
                                                                  fields: plan.fields.merging(["title": .text(n.title)]) { _, new in new }),
                                         appName: appName, icon: icon, image: image, template: plan.template, manifest: plan.manifest,
                                         fields: plan.fields.merging(["title": .text(n.title)]) { _, new in new })
                member.liveAnimations = false
                return StackListMember(id: "preview-\(i)", model: member)
            }
            stack.width = model.bannerWidth
            return try png(of: StackListView(model: model, stack: stack, scrolls: false), appearance: appearance, scale: scale)
        }
        if stackCount > 1 {
            model.stackCount = stackCount
            return try png(of: StackedCardView(model: model, count: stackCount, reportsHeight: false),
                           appearance: appearance, scale: scale)
        }
        return try png(of: BannerView(model: model), appearance: appearance, scale: scale)
    }

    /// Any view as a PNG with the preview backdrop around it, in the forced appearance, at `scale` (1 to 3)
    /// pixels per point. Callbacks in the view are inert: nothing is hit-tested offscreen.
    static func png<V: View>(of content: V, appearance: PreviewAppearance, scale: Double) throws -> Data {
        let scheme: ColorScheme = appearance == .dark ? .dark : .light
        let framed = content
            .padding(16)
            .background(Backdrop())
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .environment(\.colorScheme, scheme)
        let renderer = ImageRenderer(content: framed)
        renderer.isOpaque = false
        renderer.scale = CGFloat(min(max(scale, PreviewSpec.scaleRange.lowerBound), PreviewSpec.scaleRange.upperBound))

        // Dynamic colours (NSColor.labelColor and the like) read the drawing appearance, which an environment
        // value does not change, so render under the matching NSAppearance too.
        let nsAppearance = NSAppearance(named: appearance == .dark ? .darkAqua : .aqua) ?? NSAppearance.currentDrawing()
        var cg: CGImage?
        nsAppearance.performAsCurrentDrawingAppearance { cg = renderer.cgImage }
        guard let cg, cg.width > 0, cg.height > 0 else { throw RenderError.noImage }
        guard CGFloat(max(cg.width, cg.height)) <= maxPixels else { throw RenderError.noImage }
        let rep = NSBitmapImageRep(cgImage: cg)
        guard let data = rep.representation(using: .png, properties: [:]) else { throw RenderError.encodingFailed }
        return data
    }

    // MARK: Images

    /// The picture for an `image` field: a file path, `data:` URI or http(s) URL, like `history.cacheImage` but
    /// without writing anything (a preview must leave no trace in the history's image cache).
    static func loadImage(_ spec: String?) async -> NSImage? {
        guard let spec, !spec.isEmpty else { return nil }
        if spec.hasPrefix("data:") {
            guard let comma = spec.firstIndex(of: ","), spec[..<comma].contains(";base64"),
                  let data = Data(base64Encoded: String(spec[spec.index(after: comma)...]), options: .ignoreUnknownCharacters),
                  data.count <= HistoryStore.maxImageBytes else { return nil }
            return NSImage(data: data)
        }
        if spec.hasPrefix("http://") || spec.hasPrefix("https://") {
            guard let url = URL(string: spec) else { return nil }
            var req = URLRequest(url: url)
            req.timeoutInterval = 10
            guard let (data, resp) = try? await URLSession.shared.data(for: req),
                  (resp as? HTTPURLResponse)?.statusCode == 200, data.count <= HistoryStore.maxImageBytes else { return nil }
            return NSImage(data: data)
        }
        let path = (spec as NSString).expandingTildeInPath
        let size = (try? FileManager.default.attributesOfItem(atPath: path))?[.size] as? NSNumber
        guard let size, size.intValue <= HistoryStore.maxImageBytes else { return nil }
        return NSImage(contentsOfFile: path)
    }

    /// The stand-in picture for a sample preview (a gradient, like the Composer's), as the `data:` URI the
    /// fields carry. Encoded once.
    static let placeholderImageSpec: String? = {
        let image = BannerSamples.image(width: 320, height: 180)
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return nil }
        return "data:image/png;base64," + png.base64EncodedString()
    }()

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
