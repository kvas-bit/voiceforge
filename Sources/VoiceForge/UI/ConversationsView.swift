import SwiftUI
#if canImport(VoiceForgeCore)
import VoiceForgeCore
#endif

struct ConversationsView: View {
    @EnvironmentObject private var viewModel: AppViewModel

    private var isPlaybackMode: Bool {
        viewModel.conversationIsInPlaybackMode
    }

    private var allLinesCompleted: Bool {
        viewModel.conversationHasGeneratedAudio
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        header
                        globalSettings
                        linesList
                    }
                    .padding(20)
                    .frame(maxWidth: 1040, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .center)
                }
                .onChange(of: viewModel.conversationLines.count) { _, newCount in
                    guard newCount > 0, let lastID = viewModel.conversationLines.last?.id else { return }
                    withAnimation(.easeInOut(duration: 0.2)) {
                        proxy.scrollTo(lastID, anchor: .bottom)
                    }
                }
            }
            if isPlaybackMode || viewModel.conversationIsGenerating {
                ConversationPlaybackBar()
            }
        }
        .navigationTitle("Conversations")
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Conversations")
                    .font(.system(size: 26, weight: .bold))
                    .tracking(-0.5)
                Text(isPlaybackMode
                     ? "Generated. Use the playback bar below to play through lines."
                     : "Add lines, pick a voice for each, then generate.")
                    .font(.system(size: 13))
                    .foregroundStyle(VoiceForgeTheme.secondaryText)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                VoiceForgePill(
                    text: viewModel.conversationIsGenerating
                        ? "Generating"
                        : (isPlaybackMode ? "Playback" : "Editing"),
                    accent: viewModel.conversationIsGenerating
                )
                if !viewModel.conversationLines.isEmpty {
                    Text("\(viewModel.conversationLines.count) line\(viewModel.conversationLines.count == 1 ? "" : "s")")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(VoiceForgeTheme.tertiaryText)
                }
                if allLinesCompleted {
                    Button {
                        viewModel.downloadCurrentConversationToDownloads()
                    } label: {
                        Label("Download WAV", systemImage: "arrow.down.circle")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(VoiceForgeSecondaryButtonStyle())
                    .accessibilityIdentifier("conversationDownloadButton")
                }
                if viewModel.hasConversationLines {
                    Button(isPlaybackMode ? "Start over" : "Clear") {
                        viewModel.resetConversation()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(VoiceForgeTheme.accent)
                    .accessibilityIdentifier("conversationResetButton")
                }
            }
        }
    }

    private var globalSettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Conversation setup")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(VoiceForgeTheme.tertiaryText)

            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Conversation name")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(VoiceForgeTheme.tertiaryText)
                    TextField("Untitled conversation", text: $viewModel.conversationName)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(VoiceForgeTheme.field)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .stroke(VoiceForgeTheme.stroke, lineWidth: 1)
                                )
                        )
                        .accessibilityIdentifier("conversationNameField")
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Model")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(VoiceForgeTheme.tertiaryText)
                    Picker("Model", selection: $viewModel.model) {
                        ForEach(viewModel.availableModels, id: \.self) { model in
                            Text(model).tag(model)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 180, alignment: .leading)
                    .accessibilityIdentifier("conversationModelPicker")
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Max tokens")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(VoiceForgeTheme.tertiaryText)
                        Spacer(minLength: 8)
                        Text("\(Int(viewModel.maxNewTokens))")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(VoiceForgeTheme.tertiaryText)
                    }
                    Slider(value: $viewModel.maxNewTokens, in: 256...4096, step: 64)
                        .frame(width: 180)
                        .accessibilityIdentifier("conversationMaxTokensSlider")
                }
            }

            HStack(spacing: 12) {
                Button {
                    viewModel.generateConversation()
                } label: {
                    HStack {
                        if viewModel.conversationIsGenerating {
                            ProgressView().controlSize(.small)
                        }
                        Text(viewModel.conversationIsGenerating ? "Generating…" : "Generate all lines")
                    }
                }
                .buttonStyle(VoiceForgePrimaryButtonStyle())
                .disabled(viewModel.conversationIsGenerating || viewModel.conversationLines.isEmpty || !allLinesReady)
                .accessibilityIdentifier("conversationGenerateButton")
                .frame(minWidth: 220)

                if viewModel.conversationIsGenerating {
                    Button(role: .destructive) {
                        viewModel.cancelConversationGeneration()
                    } label: {
                        Label("Cancel", systemImage: "stop.fill")
                    }
                    .buttonStyle(VoiceForgeSecondaryButtonStyle())
                    .accessibilityIdentifier("conversationCancelButton")
                }
            }

            if !allLinesReady && !viewModel.conversationLines.isEmpty {
                Text("Some lines are missing script text or a complete voice setup.")
                    .font(.system(size: 11))
                    .foregroundStyle(VoiceForgeTheme.danger)
            }
        }
        .padding(18)
        .voiceForgePanel(fill: VoiceForgeTheme.panel)
    }

    private var allLinesReady: Bool {
        viewModel.conversationLines.allSatisfy { line in
            !line.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !line.referenceAudioPath.isEmpty &&
            !line.referenceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private var linesList: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Lines")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(VoiceForgeTheme.secondaryText)

                Spacer()

                if !isPlaybackMode {
                    addLineButton
                }
            }

            if viewModel.conversationLines.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "text.badge.plus")
                        .font(.system(size: 32))
                        .foregroundStyle(VoiceForgeTheme.tertiaryText)
                    Text("No lines yet")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(VoiceForgeTheme.secondaryText)
                    Text("Add a line to get started.")
                        .font(.system(size: 12))
                        .foregroundStyle(VoiceForgeTheme.tertiaryText)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
                .voiceForgePanel(fill: VoiceForgeTheme.panelMuted)
            } else {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(viewModel.conversationLines.enumerated()), id: \.element.id) { index, line in
                        ConversationLineRow(
                            line: line,
                            index: index,
                            isPlaybackMode: isPlaybackMode,
                            isPlaying: isLinePlaying(index),
                            isCurrentLine: viewModel.conversationPlayer.currentLineIndex == index,
                            onPlay: { viewModel.toggleConversationLinePlayback(at: index) },
                            onDelete: { viewModel.removeConversationLine(at: index) }
                        )
                        .id(line.id)
                        .accessibilityIdentifier("conversationLine-\(index)")
                    }
                }
            }
        }
        .padding(18)
        .voiceForgePanel(fill: VoiceForgeTheme.panel)
    }

    private func isLinePlaying(_ index: Int) -> Bool {
        viewModel.conversationPlayer.currentLineIndex == index &&
        (viewModel.audioPlayer.isPlaying || isCurrentlyPlayingIndex(index))
    }

    private func isCurrentlyPlayingIndex(_ index: Int) -> Bool {
        if case .playing(let playingIdx) = viewModel.conversationPlaybackState {
            return playingIdx == index
        }
        return false
    }

    private var addLineButton: some View {
        Button {
            viewModel.addConversationLine()
        } label: {
            Label("Add line", systemImage: "plus.circle.fill")
                .font(.system(size: 13, weight: .semibold))
        }
        .buttonStyle(VoiceForgeSecondaryButtonStyle())
        .disabled(viewModel.conversationIsGenerating)
        .accessibilityIdentifier("conversationAddLineButton")
    }
}
