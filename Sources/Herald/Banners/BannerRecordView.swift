import SwiftUI

/// The row that replaces a banner's actions after Record is pressed (a voice reply): a red dot and the elapsed time while
/// recording with Stop and Cancel, then the length with Send and Cancel. Drawn by `BannerView` under the grid where the inline
/// reply field goes (DESIGN 8, 11). Nothing here activates Herald or takes the keyboard; the buttons work on the
/// non-activating panel. Recording only ever starts from the Record button, never by itself.
struct BannerRecordView: View {
    let prompt: BannerRecordPrompt
    let inset: Double
    let accent: Color?
    let stop: () -> Void
    let send: () -> Void
    let cancel: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            status
            Spacer(minLength: 4)
            switch prompt.phase {
            case .requestingPermission:
                EmptyView()
            case .recording:
                Button("Stop") { stop() }
                    .buttonStyle(BannerButtonStyle(kind: "prominent", accent: accent))
                    .accessibilityIdentifier("herald.record.stop")
                cancelButton
            case .recorded:
                Button("Send") { send() }
                    .buttonStyle(BannerButtonStyle(kind: "prominent", accent: accent))
                    .accessibilityIdentifier("herald.record.send")
                cancelButton
            case .sending:
                ProgressView().controlSize(.small)
            case .failed:
                cancelButton
            }
        }
        .padding(.horizontal, inset)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.04))
        .overlay(alignment: .top) { Rectangle().fill(Color.primary.opacity(0.10)).frame(height: 0.5) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Voice reply")
    }

    private var cancelButton: some View {
        Button { cancel() } label: {
            Image(systemName: "xmark").font(.system(size: 10, weight: .semibold)).frame(width: 16, height: 16)
        }
        .buttonStyle(BannerButtonStyle(kind: "cancel", accent: nil))
        .accessibilityLabel("Cancel voice reply")
        .accessibilityIdentifier("herald.record.cancel")
    }

    @ViewBuilder private var status: some View {
        switch prompt.phase {
        case .requestingPermission:
            Text("Waiting for microphone access\u{2026}").font(.system(size: 12.5)).foregroundStyle(.secondary)
        case .recording:
            HStack(spacing: 6) {
                Circle().fill(Color.red).frame(width: 9, height: 9)
                Text(prompt.elapsedText).font(.system(size: 12.5, design: .monospaced))
                Text("of \(Int(prompt.maxSeconds)) s").font(.caption).foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Recording \(prompt.elapsedText)")
        case .recorded:
            Text("Recorded \(prompt.elapsedText)").font(.system(size: 12.5))
        case .sending:
            Text("Transcribing on this Mac and sending\u{2026}").font(.system(size: 12.5)).foregroundStyle(.secondary)
        case .failed(let why):
            Text(why).font(.caption).foregroundStyle(.orange).lineLimit(2)
        }
    }
}
