import SwiftUI
#if canImport(VoiceForgeCore)
import VoiceForgeCore
#endif

struct PlaybackDockView: View {
    @EnvironmentObject private var viewModel: AppViewModel

    private var currentTitle: String {
        if viewModel.isGenerating { return "Generating…" }
        if let lastOutputURL = viewModel.lastOutputURL {
            let outputPath = lastOutputURL.path
            if let item = viewModel.history.first(where: { $0.outputPath == outputPath }) {
                return item.name
            }
            return lastOutputURL.lastPathComponent
        }
        return "No render yet"
    }

    var body: some View {
        HStack(spacing: 14) {
            Button {
                viewModel.audioPlayer.togglePlayback()
            } label: {
                Image(systemName: viewModel.audioPlayer.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(viewModel.lastOutputURL == nil ? VoiceForgeTheme.tertiaryText : VoiceForgeTheme.accent)
            }
            .buttonStyle(.plain)
            .disabled(viewModel.lastOutputURL == nil)
            .accessibilityIdentifier("playOutputButton")

            VStack(alignment: .leading, spacing: 4) {
                Text(currentTitle)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(VoiceForgeTheme.primaryText)
                    .lineLimit(1)
                WaveformView(active: viewModel.audioPlayer.isPlaying || viewModel.isGenerating)
                    .frame(height: 26)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 6) {
                if viewModel.isGenerating {
                    Button(role: .destructive) {
                        viewModel.cancelGeneration()
                    } label: {
                        Label("Cancel", systemImage: "stop.fill")
                    }
                    .help("Cancel the current generation (⌘.)")
                    .accessibilityIdentifier("dockCancelButton")
                } else {
                    Button {
                        viewModel.generate()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help("Regenerate")
                    .disabled(viewModel.sourceText.isEmpty)
                }

                Button {
                    viewModel.saveOutputAs()
                } label: {
                    Image(systemName: "square.and.arrow.down")
                }
                .help("Save as…")
                .disabled(viewModel.lastOutputURL == nil)
                .accessibilityIdentifier("saveOutputButton")

                Button {
                    viewModel.revealOutputInFinder()
                } label: {
                    Image(systemName: "folder")
                }
                .help("Reveal in Finder")
                .disabled(viewModel.lastOutputURL == nil)
                .accessibilityIdentifier("revealOutputButton")
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
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

private struct WaveformView: View {
    let active: Bool
    private let bars = Array(0..<64)

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            GeometryReader { geo in
                let barWidth = max((geo.size.width - CGFloat(bars.count - 1) * 2) / CGFloat(bars.count), 1)
                HStack(spacing: 2) {
                    ForEach(bars, id: \.self) { i in
                        let phase = Double(i) * 0.4 + time * (active ? 5 : 0)
                        let h = active
                            ? (sin(phase) * 0.4 + 0.55) * geo.size.height
                            : (0.25 + sin(Double(i) * 0.6) * 0.1) * geo.size.height
                        RoundedRectangle(cornerRadius: 1, style: .continuous)
                            .fill(active ? VoiceForgeTheme.accent : VoiceForgeTheme.tertiaryText.opacity(0.45))
                            .frame(width: barWidth, height: max(2, h))
                    }
                }
                .frame(maxHeight: .infinity, alignment: .center)
            }
        }
    }
}
