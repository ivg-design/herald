import SwiftUI

/// How many notifications History keeps per app (issue #26). The store enforces it (`HistoryStore.capPerApp`);
/// this is the preference behind it.
///
/// TODO(integrator): host `HistoryCapSettingsView(history: controller.history)` as a Section in SettingsView,
/// and create the store in AppController with `HistoryStore(directory: ..., cap: HistoryCapSetting.value)`.
enum HistoryCapSetting {
    static let key = "historyCapPerApp"
    static let choices = [100, 250, 500, 1000, 2500, 5000, 10_000]

    /// A development instance (HERALD_SUPPORT_DIR) keeps its preferences away from the installed Herald's,
    /// the same way the quiet-hours setting does.
    private static var defaults: UserDefaults {
        if ProcessInfo.processInfo.environment["HERALD_SUPPORT_DIR"]?.isEmpty == false,
           let suite = UserDefaults(suiteName: "com.ivg.herald.voice-dev") { return suite }
        return .standard
    }

    /// The saved cap, or the built-in default (1000) when none was chosen.
    static var value: Int {
        let saved = defaults.integer(forKey: key)
        return saved > 0 ? min(saved, HistoryStore.maxCap) : HistoryStore.cap
    }

    static func save(_ cap: Int) { defaults.set(cap, forKey: key) }
}

/// A Settings section: "Keep per app" with the usual choices. Lowering it deletes the oldest items beyond the
/// new limit, so the change asks first when it would delete anything.
struct HistoryCapSettingsView: View {
    let history: HistoryStore
    @State private var cap = HistoryCapSetting.value
    @State private var pending: Int?

    private var choices: [Int] { Array(Set(HistoryCapSetting.choices + [cap])).sorted() }

    /// How many items a smaller cap would delete across all apps.
    private func overflow(_ newCap: Int) -> Int {
        history.counts().values.reduce(0) { $0 + max(0, $1.total - newCap) }
    }

    var body: some View {
        Section {
            Picker("Keep per app", selection: Binding(get: { cap }, set: choose)) {
                ForEach(choices, id: \.self) { Text("\($0) notifications").tag($0) }
            }
            Text("The oldest notifications of an app beyond this number are deleted from History, with their cached images.")
                .font(.caption).foregroundStyle(.secondary)
        } header: {
            Text("History")
        }
        .alert("Delete older history?", isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } })) {
            Button("Delete", role: .destructive) { if let p = pending { apply(p) }; pending = nil }
            Button("Cancel", role: .cancel) { pending = nil }
        } message: {
            Text("Keeping \(pending ?? 0) per app deletes \(pending.map(overflow) ?? 0) older notifications now.")
        }
    }

    private func choose(_ new: Int) {
        if overflow(new) > 0 { pending = new } else { apply(new) }
    }

    private func apply(_ new: Int) {
        cap = new
        HistoryCapSetting.save(new)
        history.capPerApp = new
        NotificationCenter.default.post(name: .heraldChanged, object: nil)
    }
}
