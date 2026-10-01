import SwiftUI
import AppKit

/// A speaker button plus the spoken text for a history entry that carries `speech`; renders nothing otherwise.
/// Plays the cached WAV again, or re-synthesizes the text when the file was pruned.
struct SpeechReplayButton: View {
    let item: HeraldHistoryItem

    var body: some View {
        if let speech = item.speech {
            HStack(spacing: 6) {
                Button {
                    VoiceCoordinator.shared.replay(app: item.app, id: item.id, speech: speech)
                } label: {
                    Image(systemName: "speaker.wave.2.fill")
                }
                .buttonStyle(.borderless)
                .help("Play again")
                Text(speech.text)
                    .font(.caption).foregroundStyle(.secondary)
                    .lineLimit(2)
                    .textSelection(.enabled)
                if let d = speech.durationSeconds {
                    Text(String(format: "%.1fs", d)).font(.caption2).foregroundStyle(.tertiary)
                }
            }
        }
    }
}

/// The replay control of a live banner (a small speaker in its meta column). Pressing it plays the cached WAV
/// again, or re-synthesizes the text when the file was pruned, even while Herald is muted.
struct BannerReplayButton: View {
    let app: String
    let id: String
    let speech: HeraldSpeech

    var body: some View {
        Button {
            VoiceCoordinator.shared.replay(app: app, id: id, speech: speech)
        } label: {
            Image(systemName: "speaker.wave.2.fill")
                .font(.system(size: 10, weight: .semibold))
                .frame(width: 16, height: 14)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help("Play again")
        .accessibilityLabel("Play the spoken message again")
    }
}

/// The thin row under a banner's grid that holds the replay control when the template draws no timestamp
/// (the control normally sits beside the timestamp, in the meta column).
struct BannerReplayStrip: View {
    let app: String
    let id: String
    let speech: HeraldSpeech
    let inset: Double

    var body: some View {
        HStack(spacing: 6) {
            BannerReplayButton(app: app, id: id, speech: speech)
            Text(speech.text).font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, inset).padding(.bottom, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Tells its parent whether it sits inside a live banner panel. History rows, the composer and the designer
/// draw the same `BannerView`, but only a live banner gets the replay control (History has its own).
struct LiveBannerProbe: NSViewRepresentable {
    @Binding var isLive: Bool

    func makeNSView(context: Context) -> ProbeView {
        let v = ProbeView()
        v.report = { live in if isLive != live { isLive = live } }
        return v
    }

    func updateNSView(_ nsView: ProbeView, context: Context) {}

    final class ProbeView: NSView {
        var report: (Bool) -> Void = { _ in }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            let live = window is BannerPanel
            DispatchQueue.main.async { [weak self] in self?.report(live) }
        }
    }
}
