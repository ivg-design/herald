import SwiftUI

/// One editable placeholder row in the sample-data drawer.
struct SampleRow: Identifiable, Equatable {
    let id = UUID()
    var key: String
    var value: String
}

/// Pure helpers for the drawer, kept free of SwiftUI so they stay easy to test and reuse.
enum SampleData {
    /// `{token}` names used in the template's text fields, in first-seen order, no duplicates.
    /// Tokenizing is delegated to the resolver so the drawer and the real substitution never disagree.
    /// The built-in fields (title, subtitle, body, app, id) are skipped: the resolver already
    /// fills those from the notification itself, so asking for them here would only confuse.
    static func placeholders(in t: HeraldTemplate) -> [String] {
        let builtin: Set<String> = ["title", "subtitle", "body", "app", "id"]
        var seen: [String] = []
        for text in [t.title, t.subtitle, t.body, t.url].compactMap({ $0 }) {
            for name in TemplateResolver.placeholders(in: text) where !builtin.contains(name) && !seen.contains(name) {
                seen.append(name)
            }
        }
        return seen
    }

    /// Rows -> the `metadata` object the resolver reads. Blank keys are dropped.
    static func metadata(from rows: [SampleRow]) -> JSONValue {
        var o: [String: JSONValue] = [:]
        for r in rows where !r.key.trimmingCharacters(in: .whitespaces).isEmpty {
            o[r.key.trimmingCharacters(in: .whitespaces)] = .string(r.value)
        }
        return .object(o)
    }

    /// Flattens a notification's `metadata` into rows. Scalars are stringified (the resolver only
    /// substitutes strings, so a number like 4200 is shown as the text "4200"); nested values are skipped.
    static func rows(from metadata: JSONValue?) -> [SampleRow] {
        guard case .object(let o)? = metadata else { return [] }
        return o.keys.sorted().compactMap { k in
            switch o[k]! {
            case .string(let s): return SampleRow(key: k, value: s)
            case .number(let n): return SampleRow(key: k, value: n == n.rounded() && abs(n) < 1e15 ? String(Int(n)) : String(n))
            case .bool(let b): return SampleRow(key: k, value: b ? "true" : "false")
            default: return nil
            }
        }
    }

    /// Adds a blank-valued row for every placeholder that has none yet; existing rows are kept untouched.
    static func merge(_ rows: [SampleRow], placeholders: [String]) -> [SampleRow] {
        var out = rows
        for p in placeholders where !out.contains(where: { $0.key == p }) {
            out.append(SampleRow(key: p, value: ""))
        }
        return out
    }
}

/// Key/value editor that drives the editor's live preview. The preview renders the template with
/// these values as `metadata`, so what you see is what a real notification with the same metadata gets.
struct SampleDataDrawer: View {
    @Binding var rows: [SampleRow]
    /// Placeholders the current template uses, so the drawer can flag missing ones.
    let placeholders: [String]
    /// True when history holds at least one notification for this app.
    let canFillFromLast: Bool
    let onFillFromLast: () -> Void

    private var missing: [String] { placeholders.filter { p in !rows.contains { $0.key == p } } }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Sample data").font(.headline)
                Spacer()
                Button("Fill from last notification", action: onFillFromLast)
                    .disabled(!canFillFromLast)
                    .help(canFillFromLast ? "Copy the metadata of this app's newest notification"
                                          : "No notification from this app in history yet")
            }
            Text("Values for {placeholders} in the template. They are sent to the preview as metadata.")
                .font(.caption).foregroundStyle(.secondary)

            if rows.isEmpty {
                Text("No sample values yet.").font(.caption).foregroundStyle(.tertiary)
            }
            ForEach($rows) { $row in
                HStack(spacing: 6) {
                    TextField("key", text: $row.key).frame(width: 110)
                    TextField("value", text: $row.value)
                    Button { rows.removeAll { $0.id == row.id } } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.borderless).help("Remove row")
                }
            }
            HStack {
                Button { rows.append(SampleRow(key: "", value: "")) } label: { Label("Add row", systemImage: "plus") }
                if !missing.isEmpty {
                    Button("Add \(missing.count) used in template") {
                        rows = SampleData.merge(rows, placeholders: placeholders)
                    }
                    .help("Missing: " + missing.joined(separator: ", "))
                }
            }
            .controlSize(.small)
        }
    }
}
