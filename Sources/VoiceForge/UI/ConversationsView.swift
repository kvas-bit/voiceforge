import SwiftUI
import UniformTypeIdentifiers
#if canImport(VoiceForgeCore)
import VoiceForgeCore
#endif

struct ConversationsView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @State private var isEditingCompletedConversation = false

    private var modelIsInPlaybackMode: Bool {
        viewModel.conversationIsInPlaybackMode
    }

    private var isPlaybackMode: Bool {
        ConversationPresentation.isPlaybackMode(
            modelIsInPlaybackMode: modelIsInPlaybackMode,
            isEditingCompletedConversation: isEditingCompletedConversation
        )
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
                        if !isPlaybackMode {
                            importSection
                        }
                        if !viewModel.conversationSpeakerKeys.isEmpty {
                            speakersSection
                        }
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
        .onChange(of: modelIsInPlaybackMode) { _, isInPlaybackMode in
            if !isInPlaybackMode {
                isEditingCompletedConversation = false
            }
        }
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
                if modelIsInPlaybackMode && !viewModel.conversationIsGenerating {
                    Button(isEditingCompletedConversation ? "Done editing" : "Edit") {
                        if !isEditingCompletedConversation {
                            viewModel.conversationPlayer.pause()
                            viewModel.conversationPlaybackState = viewModel.conversationPlayer.state
                        }
                        isEditingCompletedConversation.toggle()
                    }
                    .buttonStyle(VoiceForgeSecondaryButtonStyle())
                    .accessibilityIdentifier("conversationEditButton")
                }
                if viewModel.hasConversationLines {
                    Button(modelIsInPlaybackMode ? "Start over" : "Clear") {
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

    private var importSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Import script")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(VoiceForgeTheme.tertiaryText)
                Spacer()
                Button("Import") {
                    viewModel.importConversationScript(viewModel.conversationScriptDraft)
                }
                .buttonStyle(VoiceForgeSecondaryButtonStyle())
                .disabled(viewModel.conversationScriptDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("conversationImportButton")
            }

            Text("Paste a script like \"Alice: Hello there\" — one speaker turn per line. Indented lines continue the previous speaker's turn.")
                .font(.system(size: 11))
                .foregroundStyle(VoiceForgeTheme.tertiaryText)

            TextEditor(text: $viewModel.conversationScriptDraft)
                .font(.system(size: 12, design: .monospaced))
                .frame(minHeight: 90, maxHeight: 160)
                .padding(8)
                .scrollContentBackground(.hidden)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(VoiceForgeTheme.field)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(VoiceForgeTheme.stroke, lineWidth: 1)
                        )
                )
                .accessibilityIdentifier("conversationScriptEditor")

            if !viewModel.conversationScriptIssues.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(viewModel.conversationScriptIssues.enumerated()), id: \.offset) { _, issue in
                        Text("Line \(issue.lineNumber): \(issue.kind == .missingSpeaker ? "missing speaker name" : "missing dialogue after colon")")
                            .font(.system(size: 11))
                            .foregroundStyle(VoiceForgeTheme.danger)
                    }
                }
            }
        }
        .padding(18)
        .voiceForgePanel(fill: VoiceForgeTheme.panel)
    }

    private var speakersSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Speaker voices")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(VoiceForgeTheme.tertiaryText)
                Spacer()
                if !viewModel.allSpeakersAssigned {
                    Text("Assign a voice to every speaker before generating.")
                        .font(.system(size: 11))
                        .foregroundStyle(VoiceForgeTheme.danger)
                }
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 10)], spacing: 10) {
                ForEach(viewModel.conversationSpeakerKeys, id: \.self) { key in
                    SpeakerAssignmentCard(speakerKey: key)
                }
            }
        }
        .padding(18)
        .voiceForgePanel(fill: VoiceForgeTheme.panel)
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
                    Text(viewModel.selectedTTSModel == TTSModel.drama3.rawValue ? "Drama 3" : "Fish S2 Pro")
                        .font(.system(size: 13, weight: .medium))
                        .accessibilityIdentifier("conversationModelLabel")
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

            if viewModel.selectedTTSModel == TTSModel.drama3.rawValue {
                Toggle("Generate as one scene", isOn: $viewModel.conversationSceneMode)
                    .toggleStyle(.switch)
                if viewModel.conversationSceneMode {
                    TextField("Optional scene direction", text: $viewModel.sceneDirection, axis: .vertical)
                        .lineLimit(2...4)
                        .textFieldStyle(.roundedBorder)
                    if !viewModel.conversationProgress.isEmpty {
                        HStack { ProgressView().controlSize(.small); Text(viewModel.conversationProgress) }
                            .font(.system(size: 11)).foregroundStyle(VoiceForgeTheme.secondaryText)
                    }
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
                        Text(viewModel.conversationIsGenerating ? "Generating…" : (viewModel.conversationSceneMode && viewModel.selectedTTSModel == TTSModel.drama3.rawValue ? "Generate scene" : "Generate all lines"))
                    }
                }
                .buttonStyle(VoiceForgePrimaryButtonStyle())
                .disabled(viewModel.conversationIsGenerating || viewModel.conversationLines.isEmpty || !allLinesReady)
                .accessibilityIdentifier("conversationGenerateButton")
                .frame(minWidth: 220)

                if viewModel.conversationSceneOutputPath != nil {
                    Button("Play scene") { viewModel.playConversationScene() }
                        .buttonStyle(VoiceForgeSecondaryButtonStyle())
                }

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
            (((!line.referenceAudioPath.isEmpty && !line.referenceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) || !line.additionalReferences.isEmpty) && line.additionalReferences.allSatisfy { !$0.audioPath.isEmpty && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
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

// MARK: - Speaker assignment card

private struct SpeakerAssignmentCard: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @State private var isChoosingCustomVoice = false
    let speakerKey: String

    private var displayName: String {
        viewModel.conversationSpeakerDisplayNames[speakerKey] ?? speakerKey
    }

    private var binding: SpeakerVoiceBinding? {
        viewModel.voiceBinding(forSpeakerKey: speakerKey)
    }

    private var matchedPreset: VoicePreset? {
        guard let binding else { return nil }
        return viewModel.presets.first {
            $0.referenceAudioPath == binding.referenceAudioPath && $0.referenceText == binding.referenceText
        }
    }

    private var selection: String {
        if let matchedPreset {
            return matchedPreset.id.uuidString
        }
        return binding == nil ? "unassigned" : "custom"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(displayName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(VoiceForgeTheme.primaryText)

            if viewModel.selectedTTSModel == TTSModel.drama3.rawValue {
                TextField("Character description (optional)", text: Binding(
                    get: { viewModel.characterDescription(for: speakerKey) },
                    set: { viewModel.setCharacterDescription($0, speakerKey: speakerKey) }
                ))
                .textFieldStyle(.roundedBorder)
            }

            Picker("", selection: Binding(
                get: { selection },
                set: { newValue in
                    if newValue == "unassigned" {
                        viewModel.assignReferenceToSpeaker(
                            referenceAudioPath: "",
                            referenceText: "",
                            speakerKey: speakerKey
                        )
                        return
                    }
                    guard let preset = viewModel.presets.first(where: { $0.id.uuidString == newValue }) else { return }
                    viewModel.assignPresetToSpeaker(preset, speakerKey: speakerKey)
                }
            )) {
                Text("No voice").tag("unassigned")
                if binding != nil && matchedPreset == nil {
                    Text("Custom / imported clip").tag("custom")
                }
                ForEach(viewModel.presets) { preset in
                    Text(preset.name).tag(preset.id.uuidString)
                }
            }
            .labelsHidden()
            .accessibilityIdentifier("speakerVoicePicker-\(speakerKey)")

            HStack(spacing: 8) {
                Button("Choose file…") {
                    isChoosingCustomVoice = true
                }
                .buttonStyle(VoiceForgeSecondaryButtonStyle())

                if !viewModel.referenceAudioPath.isEmpty {
                    Button("Use studio voice") {
                        viewModel.assignReferenceToSpeaker(
                            referenceAudioPath: viewModel.referenceAudioPath,
                            referenceText: viewModel.referenceText,
                            speakerKey: speakerKey
                        )
                    }
                    .buttonStyle(VoiceForgeSecondaryButtonStyle())
                    .disabled(viewModel.referenceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }

            Text(binding == nil ? "Not assigned" : (matchedPreset?.name ?? "Custom voice"))
                .font(.system(size: 11))
                .foregroundStyle(binding == nil ? VoiceForgeTheme.danger : VoiceForgeTheme.tertiaryText)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(VoiceForgeTheme.field)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(VoiceForgeTheme.stroke, lineWidth: 1)
                )
        )
        .fileImporter(
            isPresented: $isChoosingCustomVoice,
            allowedContentTypes: [.audio],
            allowsMultipleSelection: false
        ) { result in
            guard case .success(let urls) = result, let url = urls.first else {
                if case .failure(let error) = result {
                    viewModel.generationError = error.localizedDescription
                }
                return
            }
            viewModel.assignReferenceToSpeaker(
                referenceAudioPath: url.path,
                referenceText: viewModel.referenceText,
                speakerKey: speakerKey
            )
        }
    }
}
