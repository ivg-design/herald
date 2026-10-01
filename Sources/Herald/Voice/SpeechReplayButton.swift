import SwiftUI

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
