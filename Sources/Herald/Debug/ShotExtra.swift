#if DEBUG
import SwiftUI
import AppKit
import HeraldClient

/// The second batch of documentation shots (`Runner.extras`): banners that reproduce the docs' own examples literally, more Designer
/// inspector sections, Rive, the Remove question and the classic Template editor. Sample data only.
@MainActor
extension ScreenshotMode {
    static let showApp = "acme.deploys"
    static let showTemplate = "Showcase"
    static let riveTemplate = "Rive status"

    static func seedExtras(_ c: AppController) {
        c.registry.register(HeraldAppRegistration(app: "example.bidbot", appName: "BidBot"))
        c.registry.register(HeraldAppRegistration(app: showApp, appName: "Acme Deploys"))
        _ = AutoIcon.applyToIconless(registry: c.registry, supportDirectory: c.supportDirectory)
        AppIcons.invalidate()
        let ring = URL(fileURLWithPath: ProcessInfo.processInfo.environment["HERALD_SHOTS_RIVE"] ?? FileManager.default.currentDirectoryPath + "/web/public/rive/status-ring.riv")
        let ringAsset = HeraldAsset(id: "status-ring", type: "rive", path: ring.path)
        _ = try? AssetStore.shared.install(ringAsset, app: showApp)
        let manifest = HeraldManifest(
            app: showApp, appName: "Acme Deploys",
            fields: [HeraldField(key: "title", type: .text, sample: .text("Health check")), HeraldField(key: "body", type: .text, sample: .text("All services are responding.")),
                     HeraldField(key: "image", type: .image), HeraldField(key: "progress", type: .number, sample: .number(0.62)),
                     HeraldField(key: "count", type: .number, sample: .number(3))],
            actions: [HeraldButton(label: "Open log", url: "https://ci.example.com/runs/4821"), HeraldButton(label: "Retry", callback: HeraldCallback(payload: .object(["do": .string("retry")]))),
                      HeraldButton(label: "Roll back", style: "destructive", callback: HeraldCallback(payload: .object(["do": .string("rollback")]))),
                      HeraldButton(label: "Mute for an hour", style: "cancel"), HeraldButton(label: "Open dashboard", url: "https://ci.example.com"),
                      HeraldButton(label: "Dismiss", style: "cancel")],
            actionIDs: ["open-log", "retry", "roll-back", "mute", "dashboard", "dismiss"], assets: [ringAsset], defaultTemplate: showTemplate)
        _ = try? c.putManifest(manifest)

        func cell(_ id: String, _ r: Int, _ col: Int, cols: Int = 1, rows: Int = 1, align: HeraldAlign = .topLeading, _ comp: HeraldComponent) -> HeraldCell {
            HeraldCell(id: id, row: r, col: col, rowSpan: rows, colSpan: cols, align: align, padding: 0, component: comp)
        }
        var sym = HeraldSymbol(name: "checkmark.circle.fill"); sym.placement = nil
        let cells: [HeraldCell] = [
            cell("icon", 0, 0, .issuerIcon(HeraldIssuerIconComponent(size: 22, cornerRadius: 5, shape: .rounded))),
            cell("title", 0, 1, .text(HeraldTextComponent(binding: "{title}", style: .title, maxLines: 2))),
            cell("badge", 0, 2, align: .topTrailing, .badge(HeraldBadgeComponent(binding: "{count}", color: "#2F7DF6", textColor: "#FFFFFF", emptyBehavior: .collapse, symbol: sym))),
            cell("image", 1, 0, cols: 3, .image(HeraldImageComponent(binding: "{image}", fit: .cover, cornerRadius: 10, aspectRatio: 16.0 / 9.0, emptyBehavior: .collapse))),
            cell("body", 2, 0, cols: 3, .text(HeraldTextComponent(binding: "{body}", style: .body, maxLines: 3, markdown: true))),
            cell("progress", 3, 0, cols: 3, .progress(HeraldProgressComponent(binding: "{progress}", color: "#2F7DF6", height: 6, emptyBehavior: .collapse))),
            cell("actions", 4, 0, cols: 3, .actions(HeraldActionsComponent(source: .merged, layout: .row, maxVisible: 3))),
        ]
        var t = HeraldTemplate(name: showTemplate, app: showApp,
                               grid: HeraldGrid(rows: 5, cols: 3, rowSizes: Array(repeating: .auto, count: 5), colSizes: [.auto, .fill, .auto], gap: 6, padding: 12, width: 380),
                               cells: cells)
        t.collapseEmpty = true
        _ = try? c.putTemplate(t)
        let rcells: [HeraldCell] = [
            cell("rive", 0, 0, rows: 2, .rive(HeraldRiveComponent(asset: "status-ring", loop: true, aspectRatio: 1, height: 56))),
            cell("title", 0, 1, .text(HeraldTextComponent(binding: "{title}", style: .title, maxLines: 2))),
            cell("body", 1, 1, .text(HeraldTextComponent(binding: "{body}", style: .body, maxLines: 3))),
        ]
        var rt = HeraldTemplate(name: riveTemplate, app: showApp,
                                grid: HeraldGrid(rows: 2, cols: 2, rowSizes: [.auto, .auto], colSizes: [.auto, .fill], gap: 8, padding: 12, width: 380), cells: rcells)
        rt.collapseEmpty = true
        _ = try? c.putTemplate(rt)
    }

    /// A 16:9 sample picture (soft gradient), written into the sandbox.
    static func samplePicture(_ c: AppController) -> String {
        let f = c.supportDirectory.appendingPathComponent("sample-picture.png")
        let img = BannerSamples.image(width: 640, height: 360)
        if let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) { try? png.write(to: f) }
        return f.path
    }
}

@MainActor
extension Runner {
    func extras() async {
        ScreenshotMode.seedExtras(c)
        await pause(0.5)
        if wantsAny("banner-") { await extraBanners() }
        if wantsAny("designer-") { await extraDesigner() }
        if wantsAny("menu-quiet") { await quietMenu() }
        if wantsAny("settings-apps-remove-dialog") { await removeDialog() }
        if wantsAny("template-editor") { await templateEditor() }
    }

    // MARK: Banners

    func extraBanners() async {
        let bid = "example.bidbot"
        _ = await banner("banner-bid-accepted", Opts(title: "Bid accepted", shows: "The banner the Getting started example sends: title Bid accepted and the body Your bid of $4,200 was accepted., with the app icon, the time and a close button.", section: "banners"),
            HeraldNotification(app: bid, id: "bid-42", title: "Bid accepted", body: "Your bid of $4,200 was accepted.", sound: "none", persistent: true))
        _ = await banner("banner-open-proposal", Opts(title: "Bid accepted with a button", shows: "The same banner after the second Getting started request replaces it: an Open proposal button now sits under the body text.", section: "banners"),
            HeraldNotification(app: bid, id: "bid-42", title: "Bid accepted", body: "Your bid of $4,200 was accepted.", sound: "none", persistent: true,
                               buttons: [HeraldButton(label: "Open proposal", url: "https://example.com/bids/42")]))
        _ = await banner("banner-accept-decline-reply", Opts(title: "Accept and Decline buttons", shows: "The Counter-offer from Acme banner of the callback example: the body They offer $3,900. Accept? and two buttons, Accept and a red Decline (a destructive style).", section: "banners"),
            HeraldNotification(app: bid, id: "bid-43", title: "Counter-offer from Acme", body: "They offer $3,900. Accept?", sound: "none", persistent: true,
                               buttons: [HeraldButton(label: "Accept", callback: HeraldCallback(payload: .object(["decision": .string("accept")]))),
                                         HeraldButton(label: "Decline", style: "destructive", callback: HeraldCallback(payload: .object(["decision": .string("decline")])))]))
        _ = await banner("banner-reply-bidbot", Opts(title: "Reply field for BidBot", shows: "The reply field of the reply example: the banner Counter-offer from Acme with a text field showing the placeholder Message to Acme, a Send button and a close button in place of the Reply button.", section: "banners"),
            HeraldNotification(app: bid, id: "bid-44", title: "Counter-offer from Acme", body: "What should we answer?", sound: "none", persistent: true,
                               buttons: [HeraldButton(label: "Reply", reply: HeraldReply(placeholder: "Message to Acme"))]),
            prepare: { app, id in _ = self.c.banners.setReply(app: app, id: id, BannerReplyPrompt(placeholder: "Message to Acme")) })
        _ = await banner("banner-command-question", Opts(title: "Command question", shows: "The question that replaces the buttons when a command button is pressed: Run this command for BidBot?, the command open ~/Reports/bids.pdf in a box, and the answers Run once, Always allow BidBot and Cancel.", section: "banners"),
            HeraldNotification(app: bid, id: "bid-45", title: "Report ready", sound: "none", persistent: true,
                               buttons: [HeraldButton(label: "Open report", command: "open ~/Reports/bids.pdf")]),
            prepare: { app, id in _ = self.c.banners.presentConfirmation(.appCommand(kind: .command, name: "BidBot", text: "open ~/Reports/bids.pdf"), app: app, id: id) })
        _ = await banner("banner-device-consent", Opts(title: "Device connector request", shows: "The question for an agent with no browser: Let Codex CLI send you notifications?, with the code BDFG-HJKM to match against what the agent printed, and the Approve and Deny answers.", section: "banners"),
            HeraldNotification(app: HeraldIdentity.app, id: UUID().uuidString, title: "Connector request", body: "Approve Codex CLI to send you notifications? Code BDFG-HJKM", sound: "none", persistent: true),
            prepare: { app, id in
                HeraldIdentity.ensureRegistered(registry: self.c.registry, supportDirectory: self.c.supportDirectory, iconPNG: nil)
                _ = self.c.banners.presentConfirmation(.connectorConsent(name: "Codex CLI", host: "its own site", code: "BDFG-HJKM"), app: app, id: id)
            })
        let sa = ScreenshotMode.showApp, st = ScreenshotMode.showTemplate
        let pic = ScreenshotMode.samplePicture(c)
        _ = await banner("banner-image", Opts(title: "Banner with an image", shows: "A banner whose template has an image component: a 16:9 picture above the body text, with the title and app icon on top.", section: "banners"),
            HeraldNotification(app: sa, id: UUID().uuidString, title: "Preview ready", body: "The staging build for **herald-web** is up.", image: pic, sound: "none", persistent: true, template: st))
        _ = await banner("banner-badge", Opts(title: "Banner with a badge", shows: "A banner whose template has a badge component: a blue pill with a check mark and the number 3 at the right of the title.", section: "banners"),
            HeraldNotification(app: sa, id: UUID().uuidString, title: "Deploys finished", body: "Three services were released to production.", sound: "none", persistent: true, metadata: .object(["count": .number(3)]), template: st))
        _ = await banner("banner-progress", Opts(title: "Banner with a progress bar", shows: "A banner whose template has a progress component: a bar filled to 62 percent under the body text.", section: "banners"),
            HeraldNotification(app: sa, id: UUID().uuidString, title: "Deploying herald-web", body: "Uploading the build to production.", sound: "none", persistent: true, metadata: .object(["progress": .number(0.62)]), template: st))
        _ = await banner("banner-overflow", Opts(title: "Actions row with a +N pill", shows: "An actions row that shows three buttons (Open log, Retry, Roll back) and a +3 pill at its end for the buttons that did not fit.", section: "banners"),
            HeraldNotification(app: sa, id: UUID().uuidString, title: "Deploy failed", body: "Step 'migrate' exited with code 2.", sound: "none", persistent: true, template: st,
                               actionIds: ["open-log", "retry", "roll-back", "mute", "dashboard", "dismiss"]))
        // banner-rive: a Rive view does not render in an offscreen capture (the cell stays blank), so it is not taken.
        let agentActions = (c.manifests.get(app: "agent.claude-code")?.actionIDs) ?? []
        _ = await banner("banner-agent", Opts(title: "Banner from the Claude Code agent app", shows: "A banner from the Claude Code agent app drawn with its default agent template: the Claude icon, a title and the message.", section: "banners"),
            HeraldNotification(app: "agent.claude-code", id: UUID().uuidString, title: "Tests pass", body: "All 412 tests passed after the banner refactor. Ready for review.", sound: "none", persistent: true, actionIds: agentActions))
    }

    // MARK: Designer

    /// A designer window as tall as the inspector and palette need, so each is one whole picture; panes are cropped out of it.
    func tallDesigner(app: String, template: String, height: CGFloat = 1900) async -> (NSWindow, DesignerModel)? {
        DesignerWindow.show(controller: c, app: app, template: template)
        guard let w = DesignerWindow.debugWindow, let m = DesignerWindow.debugModel, ShotKit.place(w, size: NSSize(width: 1280, height: height)) else { return nil }
        await pause(1.4)
        return (w, m)
    }

    func extraDesigner() async {
        let titleBarOf: (NSWindow) -> CGFloat = { $0.frame.height - $0.contentLayoutRect.height }
        // The ci template: Actions cell, problems.
        if let (w, m) = await tallDesigner(app: ScreenshotMode.ciApp, template: ScreenshotMode.ciTemplate, height: 800) {
            await shot("designer-actions-cell-selected", w, Opts(title: "An Actions cell selected", shows: "The Cell tab for the selected Actions cell: its position and span, align, and the Actions component settings (Which actions, layout, how many buttons, alignment), beside the grid with the cell outlined.", section: "designer")) { _ in
                m.tab = .cell; m.select(cell: "actions")
            }
            if wants("designer-problems") || wants("designer-inspector-template-checks") {
                m.tab = .cell; m.select(cell: "body")
                m.updateCell("body") { c in if case .text(var t) = c.component { t.binding = "{details} and {title}"; c.component = .text(t) } }
                await pause(0.6)
                if wants("designer-problems") { await shot("designer-problems", w, Opts(title: "Problems badge and list", shows: "The Designer with a problems badge in the preview header (the number of issues, with a warning triangle) and its list open under it, naming the cell and what is wrong.", section: "designer")) { _ in
                    NotificationCenter.default.post(name: Notification.Name("herald.debug.issuesOpen"), object: true)
                } }
                NotificationCenter.default.post(name: Notification.Name("herald.debug.issuesOpen"), object: false)
            }
            w.setContentSize(NSSize(width: 1280, height: 1900)); ShotKit.keepOffscreen(w); await pause(1.0)
            let top = titleBarOf(w) + 34, h = w.frame.height - top
            let inspector = CGRect(x: w.frame.width - 340, y: top, width: 340, height: h)
            await shot("designer-inspector-template-checks", w, Opts(title: "Template tab, Text and Checks", shows: "The Template tab of the inspector from Name down to the Text section and the Checks section that lists the template's problems (here one warning about an undeclared token), in one picture.", section: "designer", crop: inspector, trim: true, round: 12)) { _ in
                m.clearSelection(); m.tab = .template
            }
            m.undo()
            w.close(); await pause(1.2)
        }
        // The showcase issuer: palette, symbol, rich text, Rive, assets.
        if let (w, m) = await tallDesigner(app: ScreenshotMode.showApp, template: ScreenshotMode.showTemplate) {
            let top = titleBarOf(w) + 34, h = w.frame.height - top
            let inspector = CGRect(x: w.frame.width - 340, y: top, width: 340, height: h)
            let palette = CGRect(x: 0, y: top, width: 226, height: h)
            await shot("designer-palette-fields", w, Opts(title: "Palette, Fields and Actions", shows: "The palette from Components down to the Fields section: the issuer's fields (image, progress, count) and the standard ones, and the Actions chips for the issuer's buttons that can be dragged onto the grid.", section: "designer", crop: palette, trim: true, round: 12)) { _ in
                m.clearSelection(); m.tab = .cell
            }
            await shot("designer-symbol-section", w, Opts(title: "Symbol section", shows: "The Cell tab for a badge cell with its Symbol section: the SF Symbol name checkmark.circle.fill, weight, scale, place, rendering mode, colour, variable and effect.", section: "designer", crop: inspector, trim: true, round: 12)) { _ in
                m.tab = .cell; m.select(cell: "badge")
            }
            m.updateCell("body") { c in if case .text(var t) = c.component { t.lines = [HeraldTextLine(runs: [HeraldTextRun(text: "Release "), HeraldTextRun(token: "title", weight: .bold), HeraldTextRun(text: " is live on "), HeraldTextRun(text: "production", italic: true)])]; c.component = .text(t) } }
            await shot("designer-richtext-bar", w, Opts(title: "Rich-text bar", shows: "The Cell tab for a Text component with its rich-text bar (bold, italic, code, underline, strikethrough, size, colour and alignment) above a field holding a styled line with a bold word and an italic word.", section: "designer", crop: inspector, trim: true, round: 12)) { _ in
                m.tab = .cell; m.select(cell: "body")
            }
            m.undo()
            await shot("designer-assets", w, Opts(title: "Assets in the palette", shows: "The palette with the Assets section listing one animation, status-ring.riv, with its size, and the Add... button below it.", section: "designer", crop: palette, trim: true, round: 12)) { _ in
                m.clearSelection(); m.reloadAssets()
            }
            w.close(); await pause(1.2)
        }
        if wants("designer-rive-inspector") {
            DesignerWindow.show(controller: c, app: ScreenshotMode.showApp, template: ScreenshotMode.riveTemplate)
            if let w = DesignerWindow.debugWindow, let m = DesignerWindow.debugModel, ShotKit.place(w, size: NSSize(width: 1280, height: 1100)) {
                await pause(1.5)
                await shot("designer-rive-inspector", w, Opts(title: "Rive cell selected", shows: "The designer with a Rive cell selected: the Rive component settings in the inspector (the animation, artboard, state machine, input bindings, loop, size and the action) next to the grid with the cell outlined. The Rive animation does not render in an offscreen capture, so the cell and the preview show the animation's placeholder area.", section: "designer")) { _ in
                    m.tab = .cell; m.select(cell: "rive")
                }
                w.close(); await pause(1.2)
            }
        }
    }

    // MARK: Menu, alert, editor

    func quietMenu() async {
        guard let menu = ScreenshotMode.statusMenu else { return }
        let saved = AppSettings.shared.quiet.windows
        AppSettings.shared.quiet.windows = [QuietWindow(days: [], start: "00:00", end: "23:59", speech: true, sounds: true, banners: false, speakSummary: true)]
        await pause(0.3)
        menu.delegate?.menuNeedsUpdate?(menu)
        let host = NSHostingView(rootView: ShotMenuView(menu: menu).padding(2))
        let size = host.fittingSize
        let w = ShotWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        w.isOpaque = false; w.backgroundColor = .clear; w.hasShadow = false; w.isReleasedWhenClosed = false
        w.contentView = host
        if ShotKit.place(w, size: size) {
            await shot("menu-quiet", w, Opts(title: "Menu while quiet", shows: "The Herald menu while quiet hours are on: a Quiet until line with the end time and a Resume Now item where Quiet for 1 Hour usually is.", section: "menu", round: 12))
        }
        w.close()
        AppSettings.shared.quiet.windows = saved
    }

    func removeDialog() async {
        ScreenshotMode.sampleRelay(c)
        guard let key = c.relay.keys.first(where: { $0.isOAuth }) else { return }
        let app = CloudApps.appID(for: key)
        c.registry.register(HeraldAppRegistration(app: app, appName: "ChatGPT"))
        guard let rec = c.registry.record(for: app) else { return }
        let a = AppRemovalPrompt.makeAlert(controller: c, record: rec).alert
        a.layout()
        let win = a.window
        win.isReleasedWhenClosed = false
        // The alert's material is vibrancy over nothing offscreen: draw it as the plain window colour instead.
        func flatten(_ v: NSView) { for sub in v.subviews { if let ve = sub as? NSVisualEffectView { ve.isHidden = true }; flatten(sub) } }
        if let frame = win.contentView?.superview { flatten(frame) }
        win.appearance = NSAppearance(named: .aqua)
        win.isOpaque = false; win.backgroundColor = .clear
        win.contentView?.wantsLayer = true
        win.contentView?.layer?.backgroundColor = NSColor(srgbRed: 0.93, green: 0.93, blue: 0.93, alpha: 1).cgColor
        win.contentView?.layer?.cornerRadius = 14; win.contentView?.layer?.masksToBounds = true
        guard ShotKit.place(win) else { return }
        await pause(1.0)
        await shot("settings-apps-remove-dialog", win, Opts(title: "Remove question", shows: "The question Remove makes for a cloud connector that is still approved: Remove ChatGPT from Herald?, what is deleted, and the buttons Remove and Revoke, Remove Only and Cancel. The window's title bar is omitted, as an alert has none.", section: "settings", round: 14))
        win.orderOut(nil)
        c.relay.debugRemoveSample()
    }

    func templateEditor() async {
        let w = ShotWindow(contentRect: NSRect(x: 0, y: 0, width: 980, height: 660), styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        w.title = "Templates \u{2014} GitHub Actions"
        w.isReleasedWhenClosed = false
        w.contentView = NSHostingView(rootView: TemplateEditorView(controller: c, app: ScreenshotMode.ciApp, initialName: nil))
        guard ShotKit.place(w, size: NSSize(width: 980, height: 660)) else { return }
        await pause(1.5)
        await shot("template-editor", w, Opts(title: "Template editor", shows: "The classic Template editor opened from Settings > Apps > Templates...: the template list on the left, the form in the middle and the live preview with its sample-data drawer on the right.", section: "settings"))
        w.close()
    }
}
#endif
