import SwiftUI

// The Actions tab's "Follow-up" block: run one action when the banner is still up after a while. The logic
// (set, clear, units, candidates, the issuer's declaration) lives in DesignerModel so it is unit-tested; this
// view only draws it. The inspector is about 340 pt wide, so everything stacks and wraps instead of sitting side by side.

struct FollowUpBlock: View {
    @ObservedObject var model: DesignerModel
    @State private var amount = ""
    @State private var unit = DesignerModel.FollowUpUnit.minutes

    private static let newActionTag = "\u{0}new"

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PaletteHeader(title: "Follow-up")
            if model.followUpModes.contains(.issuer) {
                // The issuer declares one: a single choice, so the two can never both seem to apply.
                Picker("", selection: Binding(get: { model.followUpMode }, set: { model.setFollowUpMode($0); syncFields() })) {
                    ForEach(model.followUpModes) { Text(model.followUpModeTitle($0)).tag($0) }
                }
                .labelsHidden().pickerStyle(.menu).controlSize(.small)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel("Follow-up")
                .heraldHelp(name: "Follow-up", detail: "Off runs nothing. The issuer's runs the follow-up this app declares. My own replaces it with an action you choose")
            } else {
                Toggle(isOn: Binding(get: { model.followUpIsOn }, set: { model.setFollowUpMode($0 ? .own : .off); syncFields() })) {
                    Text("If not dismissed").font(.system(size: 12))
                }
                .toggleStyle(.switch).controlSize(.small)
                .accessibilityLabel("Follow-up if not dismissed")
                .heraldHelp(name: "If not dismissed", detail: "Run one action when the banner is still up after the time below. The banner stays")
            }

            if model.followUpMode == .own {
                FieldRow("After") {
                    TextField("", text: $amount)
                        .multilineTextAlignment(.trailing).frame(width: 64).controlSize(.small)
                        .onSubmit(commitAmount)
                        .accessibilityLabel("Follow-up delay")
                        .heraldHelp(name: "Follow-up delay", detail: "How long the banner may stay up before the follow-up runs: 5 seconds to 7 days")
                    Picker("", selection: $unit) {
                        ForEach(DesignerModel.FollowUpUnit.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden().pickerStyle(.menu).controlSize(.small).fixedSize()
                    .onChange(of: unit) { _ in commitAmount() }
                    .accessibilityLabel("Delay unit")
                    .heraldHelp(name: "Delay unit", detail: "Seconds, minutes or hours")
                }
                if let message = delayMessage {
                    Text(message).font(.caption2).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                }

                FieldRow("Run") {
                    Picker("", selection: Binding(get: { model.followUpRunSelection ?? "" }, set: pickRun)) {
                        if model.followUpRunSelection == nil { Text("Choose an action").tag("") }
                        let issuer = model.followUpChoices.filter { $0.origin == .issuer }
                        let yours = model.followUpChoices.filter { $0.origin != .issuer }
                        if !issuer.isEmpty {
                            Section("From the issuer") { ForEach(issuer) { Text($0.title).tag($0.id) } }
                        }
                        Section("Your actions") {
                            ForEach(yours) { Text($0.title).tag($0.id) }
                            if let a = model.followUpInlineAction { Text(a.label).tag(a.id) }
                        }
                        Divider()
                        Text("New Shortcut action\u{2026}").tag(Self.newActionTag)
                    }
                    .labelsHidden().pickerStyle(.menu).controlSize(.small)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel("Follow-up action")
                    .heraldHelp(name: "Follow-up action", detail: "The shortcut, script, command or callback to run. Links, apps, replies, snooze and dismiss cannot follow up")
                }
                if model.followUpInlineAction != nil {
                    FieldRow("") {
                        Button("Edit this action\u{2026}") { model.editFollowUpAction() }
                            .buttonStyle(.borderless).controlSize(.small)
                            .heraldHelp(name: "Edit follow-up action", detail: "Change the shortcut, script, command or callback this follow-up runs")
                    }
                }
                if let problem = actionProblem {
                    Text(problem).font(.caption2).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                }
            }
            Text(model.followUpExplanation)
                .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .onAppear(perform: syncFields)
        .onChange(of: model.ownFollowUpAfter) { _ in syncFields() }
    }

    private func pickRun(_ id: String) {
        if id == Self.newActionTag { model.openActionEditor(model.newFollowUpActionRequest()); return }
        guard !id.isEmpty, id != model.followUpRunSelection else { return }
        if model.followUpChoices.contains(where: { $0.id == id }) { model.setFollowUpAction(ref: id) }
    }

    /// Only the follow-up's own issues, as the validator words them.
    private var delayMessage: String? { model.issues.first { $0.path == "followUp.after" }?.message }
    private var actionProblem: String? {
        if model.followUpRunSelection == nil { return "Choose what to run." }
        return model.issues.first { $0.path.hasPrefix("followUp.") && $0.path != "followUp.after" }?.message
    }

    private func syncFields() {
        let d = model.followUpAfterDisplay
        amount = d.value.rounded() == d.value ? String(Int(d.value)) : String(d.value)
        unit = d.unit
    }

    private func commitAmount() {
        let v = Double(amount.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")) ?? model.followUpAfterDisplay.value
        model.setFollowUpAfter(v, unit: unit)
        syncFields()
    }
}
