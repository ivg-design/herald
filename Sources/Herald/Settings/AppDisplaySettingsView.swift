import SwiftUI
import AppKit

// Per-app banner placement and mute (issue #28), for Settings > Apps.

/// Display, screen corner and banner mute of one app. Changes are written to the app registry and announced with
/// `controller.changed()`, which makes `BannerCenter` move the banners that are up and apply the mute.
struct AppDisplaySettingsView: View {
    let controller: AppController
    let app: String

    /// Re-read after every edit (the record is a value, the registry the source of truth).
    @State private var record: AppRecord?
    /// What the pickers list. Read once per appearance: displays do not come and go while the pane is open often,
    /// and `refreshDisplays()` covers the screen-change notification.
    @State private var displays: [BannerDisplays.Choice] = BannerDisplays.choices()

    init(controller: AppController, app: String) {
        self.controller = controller
        self.app = app
        _record = State(initialValue: controller.registry.record(for: app))
    }

    private var screenChoice: String { record?.screen ?? BannerDisplay.main }
    private var appDefaultCorner: HeraldCorner { record?.registration.defaults?.corner ?? .topRight }

    var body: some View {
        Section {
            Picker("Display", selection: Binding(get: { screenChoice }, set: { v in
                edit { $0.screen = (v == BannerDisplay.main) ? nil : v }
            })) {
                ForEach(BannerDisplays.choices(including: record?.screen)) { Text($0.name).tag($0.id) }
            }
            Picker("Screen corner", selection: Binding(get: { record?.corner }, set: { v in edit { $0.corner = v } })) {
                Text("App default (\(Self.title(appDefaultCorner)))").tag(HeraldCorner?.none)
                ForEach(HeraldCorner.allCases, id: \.self) { Text(Self.title($0)).tag(HeraldCorner?.some($0)) }
            }
            Toggle("Mute banners", isOn: Binding(get: { record?.mutedBanners ?? false }, set: { v in
                edit { $0.mutedBanners = v }
            }))
            Picker("Stack notifications", selection: Binding(get: { record?.stacking }, set: { v in edit { $0.stacking = v } })) {
                Text("Default (\(AppSettings.shared.stacking.title))").tag(StackingLevel?.none)
                ForEach(StackingLevel.allCases, id: \.self) { Text($0.title).tag(StackingLevel?.some($0)) }
            }
        } header: { Text("Banners") } footer: {
            Text(footer)
        }
        .onAppear { reload() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
            displays = BannerDisplays.choices()
        }
    }

    private var footer: String {
        var text = "Banners of every app that picks the same display and corner stack together."
        if record?.mutedBanners == true {
            text = "No banners for this app: its notifications go to History, unread. Sounds follow the app's sound setting."
        }
        if let s = record?.screen, s != BannerDisplay.main, !displays.contains(where: { $0.id == s }) {
            text += " The chosen display is not connected, so banners appear on the main display."
        }
        return text
    }

    private func reload() { record = controller.registry.record(for: app) }

    private func edit(_ change: @escaping (inout AppRecord) -> Void) {
        controller.registry.update(app, change)
        reload()
        controller.changed()
    }

    static func title(_ c: HeraldCorner) -> String {
        switch c {
        case .topRight: return "Top right"
        case .topLeft: return "Top left"
        case .bottomRight: return "Bottom right"
        case .bottomLeft: return "Bottom left"
        }
    }
}
