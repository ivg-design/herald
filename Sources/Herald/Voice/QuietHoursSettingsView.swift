import SwiftUI

/// Settings > Voice > Quiet hours (DESIGN section 7.9.1): windows with days, start/end and what each silences.
struct QuietHoursSettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @StateObject private var ticker = ChangeTicker()

    private var status: HeraldQuietStatus { _ = ticker.tick; return QuietHoursCoordinator.shared.status() }
    private static let dayLabels = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    var body: some View {
        Section {
            statusRow
            ForEach(settings.quiet.windows) { w in windowEditor(w.id) }
            HStack {
                Button("Add Window") { settings.quiet.windows.append(QuietWindow()) }
                Spacer()
                Button("Quiet for 1 Hour") { QuietHoursCoordinator.shared.quietFor(minutes: 60) }
                    .disabled(status.active)
            }
        } header: { Text("Quiet hours") }
        footer: {
            Text("A window starts on the days ticked and runs until the end time, past midnight if the end is earlier. Speech held back is logged in History. An app can let urgent notifications break through (Speak per app, below).")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var statusRow: some View {
        let s = status
        if s.active, let until = s.until {
            HStack {
                Image(systemName: "moon.fill").foregroundStyle(.indigo)
                Text("Quiet until \(until.formatted(date: .omitted, time: .shortened))")
                Spacer()
                Button("Resume Now") { QuietHoursCoordinator.shared.resumeNow() }
            }
        } else {
            Text("Not quiet right now.").foregroundStyle(.secondary)
        }
    }

    private func binding(_ id: String) -> Binding<QuietWindow>? {
        guard let i = settings.quiet.windows.firstIndex(where: { $0.id == id }) else { return nil }
        return Binding(get: { settings.quiet.windows[i] }, set: { settings.quiet.windows[i] = $0 })
    }

    @ViewBuilder private func windowEditor(_ id: String) -> some View {
        if let w = binding(id) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 4) {
                    ForEach(Array(QuietDay.all.enumerated()), id: \.offset) { i, day in
                        let on = w.wrappedValue.days.isEmpty || w.wrappedValue.days.contains(day)
                        Button(Self.dayLabels[i]) { toggleDay(w, day) }
                            .buttonStyle(.bordered).tint(on ? .accentColor : .secondary)
                            .controlSize(.small)
                    }
                    Spacer()
                    Button(role: .destructive) { settings.quiet.windows.removeAll { $0.id == id } } label: { Image(systemName: "trash") }
                        .buttonStyle(.borderless)
                }
                // Labels are plain Text and the pickers are label-less: a labelled DatePicker in a grouped Form
                // stretches to the row's full width, which made this section wider than the Settings window.
                HStack(spacing: 8) {
                    Text("From")
                    DatePicker("From", selection: time(w.start), displayedComponents: .hourAndMinute).labelsHidden().fixedSize()
                    Text("until")
                    DatePicker("Until", selection: time(w.end), displayedComponents: .hourAndMinute).labelsHidden().fixedSize()
                    if !QuietEvaluator.isValid(w.wrappedValue) {
                        Text("Start and end must differ").font(.caption).foregroundStyle(.red)
                    }
                    Spacer(minLength: 0)
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 14) {
                        Toggle("Speech", isOn: w.speech)
                        Toggle("Sounds", isOn: w.sounds)
                        Toggle("Banners", isOn: w.banners)
                    }
                    Toggle("Speak queued messages when it ends", isOn: w.speakSummary).disabled(!w.wrappedValue.speech)
                }
                .toggleStyle(.checkbox).font(.caption)
            }
            .padding(.vertical, 4)
        }
    }

    /// Every day ticked is stored as an empty list ("every day"); unticking the last of a list re-ticks all.
    private func toggleDay(_ w: Binding<QuietWindow>, _ day: String) {
        var days = Set(w.wrappedValue.days.isEmpty ? QuietDay.all : w.wrappedValue.days)
        if days.contains(day) { days.remove(day) } else { days.insert(day) }
        if days.isEmpty || days.count == 7 { w.wrappedValue.days = [] }
        else { w.wrappedValue.days = QuietDay.all.filter(days.contains) }
    }

    /// An "HH:MM" string as a Date on today's calendar day for the DatePicker.
    private func time(_ s: Binding<String>) -> Binding<Date> {
        Binding(get: {
            let m = QuietEvaluator.minutes(s.wrappedValue) ?? 0
            return Calendar.current.date(bySettingHour: m / 60, minute: m % 60, second: 0, of: Date()) ?? Date()
        }, set: { d in
            let c = Calendar.current.dateComponents([.hour, .minute], from: d)
            s.wrappedValue = String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
        })
    }
}
