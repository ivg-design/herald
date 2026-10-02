import SwiftUI

// Inspector pieces for buttons: the labelled Style control (issue #60) and the "Which actions" selection of an
// Actions cell (issue #58).

/// What a button's Style means, in the words the inspector shows under it.
enum ActionStyleCopy {
    static let caption = "Destructive draws the label in red and asks for confirmation before running"
    static let options: [(value: String, title: String)] = [
        ("normal", "Normal"), ("prominent", "Prominent"), ("destructive", "Destructive"), ("cancel", "Quiet"),
    ]
}

/// The Style picker of a button, with its explanation. `noneLabel` adds a first option that leaves the style to the
/// action (the button's own `style` is then absent).
struct ActionStyleField: View {
    @Binding var style: String?
    var noneLabel: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            FieldRow("Button style") {
                Picker("", selection: Binding<String?>(
                    get: { style.map { HeraldActionStyle.parse($0).rawValue } },
                    set: { style = $0 })) {
                    if let noneLabel { Text(noneLabel).tag(String?.none) }
                    ForEach(ActionStyleCopy.options, id: \.value) { Text($0.title).tag(String?.some($0.value)) }
                }
                .labelsHidden().fixedSize()
                .heraldHelp(name: "Button style", detail: "normal, prominent, destructive or quiet look; destructive asks before running")
            }
            Text(ActionStyleCopy.caption)
                .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// "Which actions" of an Actions cell: every remaining action, or an ordered choice.
struct WhichActionsEditor: View {
    @ObservedObject var model: DesignerModel
    let id: String

    private enum Mode: Hashable { case rest, chosen }

    var body: some View {
        let b = PayloadBinder<HeraldActionsComponent>.of(model, id)
        let include = b.binding(\.include, nil)
        let chosen = model.draft.cell(withID: id).flatMap { cell -> [String]? in
            if case .actions(let a) = cell.component { return a.includedIDs }
            return nil
        } ?? []
        let rows = model.actionRows.filter { !$0.hidden }
        let claims = model.draft.actionAssignment(actions: model.previewActions).claimants
        let mode: Mode = chosen.isEmpty ? .rest : .chosen

        VStack(alignment: .leading, spacing: 6) {
            FieldRow("Which") {
                Picker("", selection: Binding(get: { mode }, set: { new in
                    switch new {
                    case .rest: include.wrappedValue = nil
                    case .chosen:
                        // Start with the first action no other cell has asked for.
                        let free = rows.first { claims[$0.id].map { !($0.isEmpty) } != true } ?? rows.first
                        include.wrappedValue = free.map { [$0.id] }
                    }
                })) {
                    Text("All the rest").tag(Mode.rest); Text("Chosen").tag(Mode.chosen)
                }.labelsHidden().pickerStyle(.segmented)
                    .heraldHelp(name: "Which actions", detail: "every action no other cell asked for, or an ordered choice")
            }
            if mode == .chosen {
                ForEach(Array(chosen.enumerated()), id: \.offset) { index, actionID in
                    HStack(spacing: 4) {
                        let row = rows.first { $0.id == actionID }
                        VStack(alignment: .leading, spacing: 0) {
                            Text(row?.action.label ?? "\(actionID) (not in the list)").font(.system(size: 12)).lineLimit(1)
                            if let other = claims[actionID]?.first(where: { $0 != id }), claims[actionID]?.first == other {
                                Text("Already drawn in cell \u{201C}\(other)\u{201D}").font(.caption2).foregroundStyle(.orange)
                            } else if row == nil {
                                Text("Nothing shows for it").font(.caption2).foregroundStyle(.orange)
                            }
                        }
                        Spacer(minLength: 0)
                        Button { move(index, by: -1, chosen, include) } label: { Image(systemName: "chevron.up") }
                            .buttonStyle(.borderless).disabled(index == 0)
                            .heraldHelp(name: "Move up", detail: "show this action earlier in the row")
                        Button { move(index, by: 1, chosen, include) } label: { Image(systemName: "chevron.down") }
                            .buttonStyle(.borderless).disabled(index == chosen.count - 1)
                            .heraldHelp(name: "Move down", detail: "show this action later in the row")
                        Button {
                            var ids = chosen; ids.remove(at: index)
                            include.wrappedValue = ids.isEmpty ? nil : ids
                        } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless)
                            .heraldHelp(name: "Remove", detail: "take this action out of this cell")
                    }
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.secondary.opacity(0.10)))
                }
                let remaining = rows.filter { !chosen.contains($0.id) }
                if !remaining.isEmpty {
                    Menu {
                        ForEach(remaining) { r in
                            Button(r.action.label) { include.wrappedValue = chosen + [r.id] }
                        }
                    } label: { Label("Add an action", systemImage: "plus.circle") }
                        .menuStyle(.borderlessButton).fixedSize().controlSize(.small)
                        .heraldHelp(name: "Add an action", detail: "show one more action in this cell")
                }
            }
            Text("An action is drawn in one cell only. Give a Button cell one action and an Actions cell the rest: for example a Button for Mark as Read in column 1, and an Actions cell with Archive, Delete and Spam, aligned right, across columns 2 to 4 of the same row. \u{201C}All the rest\u{201D} takes whatever no other cell has asked for.")
                .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func move(_ index: Int, by delta: Int, _ chosen: [String], _ include: Binding<[String]?>) {
        var ids = chosen
        guard ids.indices.contains(index), ids.indices.contains(index + delta) else { return }
        ids.swapAt(index, index + delta)
        include.wrappedValue = ids
    }
}

/// Alignment, wrapping and spacing of an Actions cell.
struct ActionsArrangementFields: View {
    @ObservedObject var model: DesignerModel
    let id: String

    var body: some View {
        let b = PayloadBinder<HeraldActionsComponent>.of(model, id)
        let layout = b.binding(\.layout, .wrap).wrappedValue
        FieldRow("Align") {
            Picker("", selection: Binding(get: { b.binding(\.align, nil).wrappedValue ?? .leading },
                                          set: { b.binding(\.align, nil).wrappedValue = $0 == .leading ? nil : $0 })) {
                Text("Left").tag(HeraldActionsAlign.leading); Text("Centre").tag(HeraldActionsAlign.center)
                Text("Right").tag(HeraldActionsAlign.trailing); Text("Spread").tag(HeraldActionsAlign.spaceBetween)
            }.labelsHidden().pickerStyle(.segmented)
                .heraldHelp(name: "Align buttons", detail: "left, centre, right, or spread from edge to edge")
        }
        FieldRow("Wrap") {
            Toggle("Flow onto more lines", isOn: Binding(
                get: { layout == .stack ? false : (b.binding(\.wrap, nil).wrappedValue ?? (layout == .wrap)) },
                set: { b.binding(\.wrap, nil).wrappedValue = $0 })).toggleStyle(.checkbox).disabled(layout == .stack)
                .heraldHelp(name: "Wrap", detail: "flow onto more lines when the buttons do not fit")
        }
        FieldRow("Spacing") {
            OptionalNumberField(value: b.binding(\.spacing, nil), placeholder: "6")
                .heraldHelp(name: "Button spacing", detail: "points between buttons; empty uses 6")
        }
    }
}
