import SwiftUI
import AppKit

/// The row that replaces a banner's actions after Reply is pressed: one text field, Send and a cancel button, drawn by
/// `BannerView` under the grid exactly where the inline confirmation goes (DESIGN 8).
///
/// Focus: nothing here activates Herald or takes the keyboard. The panel becomes key only when the user clicks the field
/// (`BannerCenter.setReply` allows it for as long as this row is up, and the panel is `becomesKeyOnlyIfNeeded`), and gives it
/// up when the row goes away. In a preview the field is a static stand-in because `ImageRenderer` cannot draw AppKit controls.
struct BannerReplyView: View {
    let prompt: BannerReplyPrompt
    let inset: Double
    /// Already contrast-adjusted for the current appearance.
    let accent: Color?
    /// False in a preview: the field is drawn as text.
    let editable: Bool
    let send: (String) -> Void
    let cancel: () -> Void

    @State private var text = ""

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        HStack(spacing: 6) {
            field
            Button("Send") { submit() }
                .buttonStyle(BannerButtonStyle(kind: "prominent", accent: accent))
                .disabled(editable && trimmed.isEmpty)
                .accessibilityIdentifier("herald.reply.send")
            Button { cancel() } label: {
                Image(systemName: "xmark").font(.system(size: 10, weight: .semibold)).frame(width: 16, height: 16)
            }
            .buttonStyle(BannerButtonStyle(kind: "cancel", accent: nil))
            .accessibilityLabel("Cancel reply")
            .accessibilityIdentifier("herald.reply.cancel")
        }
        .padding(.horizontal, inset)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.04))
        .overlay(alignment: .top) { Rectangle().fill(Color.primary.opacity(0.10)).frame(height: 0.5) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Reply")
    }

    @ViewBuilder private var field: some View {
        if editable {
            TextField(prompt.placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .onSubmit { submit() }
                .onExitCommand { cancel() }
                .accessibilityLabel(prompt.placeholder)
                .accessibilityIdentifier("herald.reply.field")
        } else {
            let shown = prompt.sample.isEmpty ? prompt.placeholder : prompt.sample
            Text(shown)
                .font(.system(size: 12.5))
                .foregroundStyle(prompt.sample.isEmpty ? .secondary : .primary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
    }

    private func submit() {
        guard editable, !trimmed.isEmpty else { return }
        send(text)
    }
}
