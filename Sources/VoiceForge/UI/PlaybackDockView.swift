import SwiftUI
#if canImport(VoiceForgeCore)
import VoiceForgeCore
#endif

struct PlaybackDockView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @State private var scrubTarget: TimeInterval?

    private var currentTitle: String {
        if viewModel.isGenerating {
            switch viewModel.generationPhase {
            case .prewarming: return "Prewarming…"
            case .generating: return "Generating…"
            case .validating: return "Validating…"
            default: return "Working…"
            }
        }
        if let lastOutputURL = viewModel.lastOutputURL {
            let outputPath = lastOutputURL.path
            if let item = viewModel.history.first(where: { $0.outputPath == outputPath }) {
                return item.name
            }
            return lastOutputURL.lastPathComponent
        }
        return "No render yet"
    }

    private var timeString: String {
        let t = viewModel.audioPlayer.currentTime
        let d = viewModel.audioPlayer.duration
        if d > 0 {
            return "\(formatTime(t)) / \(formatTime(d))"
        }
        return formatTime(t)
    }

    var body: some View {
        HStack(spacing: 14) {
            // Play/Pause
            Button {
                if let url = viewModel.lastOutputURL {
                    OutputPlaybackControl.toggle(url: url, player: viewModel.audioPlayer)
                }
            } label: {
                Image(systemName: isLatestOutputPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(viewModel.lastOutputURL == nil
                        ? VoiceForgeTheme.tertiaryText : VoiceForgeTheme.accent)
            }
            .buttonStyle(.plain)
            .disabled(viewModel.lastOutputURL == nil)
            .accessibilityIdentifier("playOutputButton")

            // Title + waveform
            VStack(alignment: .leading, spacing: 4) {
                Text(currentTitle)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(VoiceForgeTheme.primaryText)
                    .lineLimit(1)

                WaveformTimelineView(
                    waveform: viewModel.audioPlayer.waveform,
                    progress: viewModel.audioPlayer.duration > 0
                        ? viewModel.audioPlayer.currentTime / viewModel.audioPlayer.duration
                        : 0,
                    isActive: viewModel.audioPlayer.isPlaying || viewModel.isGenerating,
                    onSeek: { fraction in
                        let target = fraction * viewModel.audioPlayer.duration
                        viewModel.audioPlayer.seek(to: target)
                    }
                )
                .frame(height: 30)

                Text(timeString)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(VoiceForgeTheme.tertiaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Actions
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

    private func formatTime(_ t: TimeInterval) -> String {
        let m = Int(t) / 60
        let s = Int(t) % 60
        return String(format: "%d:%02d", m, s)
    }

    private var isLatestOutputPlaying: Bool {
        guard let url = viewModel.lastOutputURL else { return false }
        return viewModel.audioPlayer.isPlaying(url: url)
    }
}

// MARK: - Waveform timeline with seek

struct WaveformTimelineView: View {
    let waveform: [Float]
    let progress: Double
    let isActive: Bool
    let onSeek: (Double) -> Void

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let barCount = waveform.isEmpty ? 64 : waveform.count

            ZStack(alignment: .leading) {
                // Waveform bars
                HStack(spacing: 1) {
                    let barWidth = max(1, (w - CGFloat(barCount - 1)) / CGFloat(barCount))
                    ForEach(0..<barCount, id: \.self) { i in
                        let value: Float = waveform.isEmpty
                            ? sin(Float(i) * 0.1) * 0.3 + 0.4
                            : waveform[i]
                        let barH = max(2, CGFloat(value) * h)
                        RoundedRectangle(cornerRadius: 1)
                            .fill(Double(i) / Double(barCount) <= progress
                                ? VoiceForgeTheme.accent
                                : VoiceForgeTheme.tertiaryText.opacity(0.35))
                            .frame(width: barWidth, height: barH)
                            .frame(maxHeight: .infinity, alignment: .center)
                    }
                }

                // Progress indicator
                Rectangle()
                    .fill(VoiceForgeTheme.accent.opacity(0.3))
                    .frame(width: 2)
                    .offset(x: w * progress)
                    .allowsHitTesting(false)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        let frac = max(0, min(1, v.location.x / w))
                        onSeek(frac)
                    }
            )
        }
    }
}
