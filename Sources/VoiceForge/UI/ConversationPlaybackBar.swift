import SwiftUI
#if canImport(VoiceForgeCore)
import VoiceForgeCore
#endif

struct ConversationPlaybackBar: View {
    @EnvironmentObject private var viewModel: AppViewModel

    private var currentIndex: Int? {
        viewModel.conversationPlayer.currentLineIndex
    }

    private var totalLines: Int {
        viewModel.conversationLines.count
    }

    private var isPlaying: Bool {
        if case .playing = viewModel.conversationPlaybackState { return true }
        return false
    }

    private var isPaused: Bool {
        if case .paused = viewModel.conversationPlaybackState { return true }
        return false
    }

    private var isFinished: Bool {
        if case .finished = viewModel.conversationPlaybackState { return true }
        return false
    }

    var body: some View {
        HStack(spacing: 16) {
            Button {
                viewModel.conversationPlayer.previous()
            } label: {
                Image(systemName: "backward.fill")
                    .font(.system(size: 14))
            }
            .buttonStyle(.borderless)
            .disabled(currentIndex == nil || currentIndex == 0)
            .help("Previous line")
            .accessibilityIdentifier("conversationPreviousButton")

            Button {
                viewModel.conversationPlayer.togglePlayback()
            } label: {
                Image(systemName: isFinished ? "arrow.clockwise" : (isPlaying ? "pause.fill" : "play.fill"))
                    .font(.system(size: 22))
                    .foregroundStyle(VoiceForgeTheme.accent)
            }
            .buttonStyle(.plain)
            .help(isFinished ? "Replay" : (isPlaying ? "Pause" : "Play"))
            .accessibilityIdentifier("conversationPlayPauseButton")

            Button {
                viewModel.conversationPlayer.advance()
            } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: 14))
            }
            .buttonStyle(.borderless)
            .disabled(currentIndex == nil || currentIndex! >= totalLines - 1)
            .help("Next line")
            .accessibilityIdentifier("conversationNextButton")

            Spacer()

            if let idx = currentIndex {
                Text("\(idx + 1) of \(totalLines)")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(VoiceForgeTheme.secondaryText)
            }

            if !viewModel.conversationName.isEmpty {
                Text(viewModel.conversationName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(VoiceForgeTheme.tertiaryText)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.thinMaterial)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(VoiceForgeTheme.stroke)
                .frame(height: 1)
        }
    }
}