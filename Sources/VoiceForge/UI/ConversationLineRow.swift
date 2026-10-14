import SwiftUI
import UniformTypeIdentifiers
#if canImport(VoiceForgeCore)
import VoiceForgeCore
#endif

struct ConversationLineRow: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @State private var isChoosingReferenceAudio = false
    let line: ConversationLine
    let index: Int
    let isPlaybackMode: Bool
    let sceneMode: Bool
    let isPlaying: Bool
    let isCurrentLine: Bool
    let onPlay: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            headerRow
            if isPlaybackMode {
                playbackRow
            } else {
                editingRow
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isCurrentLine ? VoiceForgeTheme.accentSoft.opacity(0.3) : VoiceForgeTheme.panel)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(isCurrentLine ? VoiceForgeTheme.accent.opacity(0.4) : VoiceForgeTheme.stroke, lineWidth: isCurrentLine ? 1.5 : 1)
                )
        )
        .fileImporter(
            isPresented: $isChoosingReferenceAudio,
            allowedContentTypes: [.audio],
            allowsMultipleSelection: false,
            onCompletion: handleReferenceAudioSelection
        )
    }

    private var headerRow: some View {
        HStack(alignment: .center, spacing: 10) {
            HStack(spacing: 8) {
                Text("\(index + 1)")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(VoiceForgeTheme.tertiaryText)
                    .frame(width: 24, height: 24)
                    .background(
                        Circle().fill(VoiceForgeTheme.fieldMuted)
                    )
                Text("Line \(index + 1)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(VoiceForgeTheme.secondaryText)
            }

            Spacer(minLength: 8)
            statusBadge

            if !isPlaybackMode {
                Button(action: onDelete) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(VoiceForgeTheme.tertiaryText)
                }
                .buttonStyle(.plain)
                .help("Remove this line")
                .accessibilityIdentifier("deleteLineButton-\(index)")
            }
        }
    }

    private var editingRow: some View {
        VStack(alignment: .leading, spacing: 12) {
            if sceneMode, let speakerKey = line.speakerKey {
                Text("Cast voice · \(viewModel.conversationSpeakerDisplayNames[speakerKey] ?? speakerKey)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(VoiceForgeTheme.secondaryText)
            } else {
                voicePicker
            }
            textEditor
        }
    }

    private var playbackRow: some View {
        HStack(spacing: 14) {
            Button(action: onPlay) {
                Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(isPlaying ? VoiceForgeTheme.accent : VoiceForgeTheme.secondaryText)
            }
            .buttonStyle(.plain)
            .help(isPlaying ? "Pause" : "Play this line")
            .accessibilityIdentifier("conversationPlayLine-\(index)")

            VStack(alignment: .leading, spacing: 4) {
                Text(line.text.isEmpty ? "(empty)" : line.text)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(line.text.isEmpty ? VoiceForgeTheme.tertiaryText : VoiceForgeTheme.primaryText)
                    .lineLimit(2)
                    .textSelection(.enabled)
            }

            Spacer()
        }
    }

    private var voicePicker: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Voice")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(VoiceForgeTheme.tertiaryText)

            VStack(alignment: .leading, spacing: 12) {
                let preset = matchedPreset
                let displayName: String = {
                    if let preset { return preset.name }
                    if !line.referenceAudioPath.isEmpty {
                        return URL(fileURLWithPath: line.referenceAudioPath)
                            .deletingPathExtension()
                            .lastPathComponent
                    }
                    return "No voice"
                }()

                HStack(alignment: .center, spacing: 10) {
                    Circle()
                        .fill(VoiceForgeTheme.accentSoft)
                        .frame(width: 34, height: 34)
                        .overlay(
                            Image(systemName: !line.referenceAudioPath.isEmpty ? "waveform" : "person.crop.circle.dashed")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(VoiceForgeTheme.accent)
                        )

                    VStack(alignment: .leading, spacing: 2) {
                        Text(displayName)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(line.referenceAudioPath.isEmpty ? VoiceForgeTheme.tertiaryText : VoiceForgeTheme.primaryText)
                            .lineLimit(1)

                        Text(matchedPreset != nil ? "Saved voice preset" : (line.referenceAudioPath.isEmpty ? "Select a saved voice or import a clip" : "Imported reference clip"))
                            .font(.system(size: 11))
                            .foregroundStyle(VoiceForgeTheme.tertiaryText)
                    }

                    Spacer(minLength: 8)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Picker("Saved voice", selection: savedVoiceSelection) {
                        Text("No voice").tag("none")
                        ForEach(viewModel.presets) { preset in
                            Text(preset.name).tag(preset.id.uuidString)
                        }
                        if matchedPreset == nil && !line.referenceAudioPath.isEmpty {
                            Text("Imported clip").tag(customVoiceSelectionKey)
                        }
                    }
                    .pickerStyle(.menu)
                    .accessibilityIdentifier("conversationVoicePicker-\(index)")

                    HStack(spacing: 8) {
                        Button("Choose file…") {
                            isChoosingReferenceAudio = true
                        }
                        .buttonStyle(VoiceForgeSecondaryButtonStyle())
                        .accessibilityIdentifier("conversationBrowseVoiceButton-\(index)")

                        if !viewModel.referenceAudioPath.isEmpty {
                            Button("Use studio voice") {
                                applyCurrentReferenceToLine()
                            }
                            .buttonStyle(VoiceForgeSecondaryButtonStyle())
                        }
                    }

                    if matchedPreset == nil && !line.referenceAudioPath.isEmpty {
                        TextField(
                            "Type exactly what is said in the clip (or Auto-transcribe)",
                            text: Binding(
                                get: { line.referenceText },
                                set: { updateLineReferenceText($0) }
                            )
                        )
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(VoiceForgeTheme.field)
                        )
                        .accessibilityIdentifier("conversationReferenceTextField-\(index)")
                        Text("An exact transcript improves voice cloning.")
                            .font(.system(size: 10)).foregroundStyle(VoiceForgeTheme.tertiaryText)
                    }
                }

                if !line.referenceAudioPath.isEmpty && line.referenceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Label("This voice setup is incomplete. Reapply it from Voices or save it there first.", systemImage: "exclamationmark.triangle")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(VoiceForgeTheme.danger)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(VoiceForgeTheme.fieldMuted)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(VoiceForgeTheme.stroke, lineWidth: 1)
                    )
            )
        }
    }

    private var textEditor: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Script")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(VoiceForgeTheme.tertiaryText)

            PromptTextEditor(text: Binding(
                get: { line.text },
                set: { updateLineText($0) }
            ), pendingInsertion: "", insertTrigger: 0, accessibilityIdentifier: "conversationScriptEditor-\(index)")
            .frame(minHeight: 96)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(VoiceForgeTheme.field)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(VoiceForgeTheme.stroke, lineWidth: 1)
                    )
            )
            .overlay(alignment: .topLeading) {
                if line.text.isEmpty {
                    Text("Write this line's script")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(VoiceForgeTheme.tertiaryText)
                        .padding(.horizontal, 15)
                        .padding(.vertical, 14)
                        .allowsHitTesting(false)
                }
            }
        }
    }

    private var statusBadge: some View {
        Group {
            switch line.status {
            case .pending:
                Text("Pending")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(VoiceForgeTheme.tertiaryText)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(VoiceForgeTheme.fieldMuted))
            case .generating:
                HStack(spacing: 4) {
                    ProgressView().controlSize(.mini)
                    Text("Generating")
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundStyle(VoiceForgeTheme.accent)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(VoiceForgeTheme.accentSoft))
            case .completed:
                Text("Done")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.green)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.green.opacity(0.15)))
            case .failed:
                Text("Failed")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.red)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.red.opacity(0.15)))
            }
        }
    }

    // MARK: - Line update helpers

    private func updateLineText(_ newText: String) {
        viewModel.updateConversationLineText(at: index, text: newText)
    }

    private func updateLineReferenceText(_ newText: String) {
        if let speakerKey = line.speakerKey, !line.referenceAudioPath.isEmpty {
            viewModel.assignReferenceToSpeaker(
                referenceAudioPath: line.referenceAudioPath,
                referenceText: newText,
                speakerKey: speakerKey
            )
            return
        }
        viewModel.updateConversationLineReferenceText(at: index, text: newText)
    }

    private func applyPresetToLine(_ preset: VoicePreset) {
        viewModel.applyPresetToConversationLine(at: index, preset: preset)
    }

    private func applyCurrentReferenceToLine() {
        viewModel.applyCurrentReferenceToConversationLine(at: index)
    }

    private func clearVoiceFromLine() {
        viewModel.clearVoiceFromConversationLine(at: index)
    }

    private func handleReferenceAudioSelection(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let url = urls.first else {
            if case .failure(let error) = result {
                viewModel.generationError = error.localizedDescription
            }
            return
        }

        let referenceText = line.referenceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? viewModel.referenceText
            : line.referenceText

        if let speakerKey = line.speakerKey {
            viewModel.assignReferenceToSpeaker(
                referenceAudioPath: url.path,
                referenceText: referenceText,
                speakerKey: speakerKey
            )
        } else if viewModel.conversationLines.indices.contains(index) {
            viewModel.conversationLines[index].referenceAudioPath = url.path
            viewModel.conversationLines[index].referenceText = referenceText
        }
    }

    private var matchedPreset: VoicePreset? {
        viewModel.presets.first { preset in
            preset.referenceAudioPath == line.referenceAudioPath &&
            preset.referenceText == line.referenceText
        }
    }

    private var customVoiceSelectionKey: String {
        "custom:\(line.referenceAudioPath)|\(line.referenceText)"
    }

    private var savedVoiceSelection: Binding<String> {
        Binding(
            get: {
                if let matchedPreset { return matchedPreset.id.uuidString }
                if line.referenceAudioPath.isEmpty { return "none" }
                return customVoiceSelectionKey
            },
            set: { selection in
                if selection == "none" {
                    clearVoiceFromLine()
                    return
                }

                guard let preset = viewModel.presets.first(where: { $0.id.uuidString == selection }) else { return }
                applyPresetToLine(preset)
            }
        )
    }
}
