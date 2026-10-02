import SwiftUI
import AppKit

/// The second row of a banner that is asking the user something (DESIGN 8, issue #40): "Run this command for
/// Acme? Run once / Always allow Acme / Cancel", or the Reminders error with OK / Open Privacy Settings. It
/// replaces the actions row until it is answered and is drawn by `BannerView`, so live panels, previews and the
/// `/v1/preview` PNG all show the same row. It replaces what used to be a modal `NSAlert` plus
/// `NSApp.activate`, which took the keyboard from whatever the user was typing in: pressing a button here is a
/// click on a non-activating, never-key panel and changes nothing about who is frontmost.
struct BannerConfirmationView: View {
    let confirmation: BannerConfirmation
    /// The grid's padding, so the row lines up with the banner's own text.
    let inset: Double
    /// True in a live panel, where a long command scrolls. `ImageRenderer` cannot draw a `ScrollView`, so a
    /// preview shows the first lines instead.
    let scrolls: Bool
    /// Already contrast-adjusted for the current appearance.
    let accent: Color?
    let answer: (ConfirmationChoice) -> Void

    /// The tallest the command box grows before it scrolls (about eight lines).
    static let commandMaxHeight: CGFloat = 112

    @State private var commandHeight: CGFloat = 0

    private var tint: Color {
        Color(nsColor: confirmation.tone == .error ? .systemRed : .systemOrange)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(tint)
                Text(confirmation.title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            Text(confirmation.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(6)
                .fixedSize(horizontal: false, vertical: true)
            if let command = confirmation.command, !command.isEmpty { commandBox(command) }
            FlowLayout(spacing: 6, lineSpacing: 6) {
                ForEach(confirmation.buttons) { button in
                    Button(button.title) { answer(button.choice) }
                        .buttonStyle(BannerButtonStyle(kind: Self.styleKind(button.role), accent: accent))
                        .accessibilityLabel(button.title)
                        .accessibilityIdentifier("herald.confirmation.\(button.choice.rawValue)")
                }
            }
            .padding(.top, 2)
        }
        .padding(.horizontal, inset)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.09))
        .overlay(alignment: .top) { Rectangle().fill(tint.opacity(0.28)).frame(height: 0.5) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(confirmation.title)
    }

    /// `BannerButtonStyle`'s kinds: the safe answer is tinted, the lasting permission and Cancel are quiet.
    static func styleKind(_ role: BannerConfirmationButton.Role) -> String {
        role == .primary ? "default" : "cancel"
    }

    /// The text that will run or be sent, verbatim and in monospace. Never truncated: a long command scrolls.
    @ViewBuilder private func commandBox(_ text: String) -> some View {
        let content = Text(text)
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(6)
        if scrolls {
            ScrollView(.vertical) {
                content.background(GeometryReader { g in
                    Color.clear.preference(key: CommandHeightKey.self, value: g.size.height)
                })
            }
            .onPreferenceChange(CommandHeightKey.self) { commandHeight = $0 }
            .frame(height: min(max(commandHeight, 26), Self.commandMaxHeight))
            .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        } else {
            content
                .frame(maxHeight: Self.commandMaxHeight, alignment: .top)
                .clipped()
                .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
    }
}

private struct CommandHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}
