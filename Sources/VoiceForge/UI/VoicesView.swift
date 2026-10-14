import SwiftUI
#if canImport(VoiceForgeCore)
import VoiceForgeCore
#endif

struct VoicesView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @State private var searchText = ""
    @State private var isShowingNewVoice = false

    private var filteredPresets: [VoicePreset] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return viewModel.presets }
        return viewModel.presets.filter { preset in
            preset.name.lowercased().contains(trimmed)
                || preset.referenceText.lowercased().contains(trimmed)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            if viewModel.presets.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 220, maximum: 280), spacing: 16)],
                        alignment: .leading,
                        spacing: 16
                    ) {
                        ForEach(filteredPresets) { preset in
                            VoiceCard(preset: preset)
                                .accessibilityIdentifier("voiceCard-\(preset.name)")
                        }
                    }
                    .padding(20)
                }
                .accessibilityIdentifier("customVoicesList")
            }
        }
        .navigationTitle("Voices")
        .sheet(isPresented: $isShowingNewVoice) {
            NewVoiceSheet()
                .frame(minWidth: 480, minHeight: 320)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Voices")
                        .font(.system(size: 26, weight: .bold))
                        .tracking(-0.5)
                    Text("Your saved reference clips. Pick one as the source voice for the next generation.")
                        .font(.system(size: 13))
                        .foregroundStyle(VoiceForgeTheme.secondaryText)
                }
                Spacer()
                Button {
                    isShowingNewVoice = true
                } label: {
                    Label("New voice", systemImage: "plus")
                }
                .buttonStyle(VoiceForgePrimaryButtonStyle())
                .accessibilityIdentifier("newVoiceButton")
            }

            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(VoiceForgeTheme.tertiaryText)
                TextField("Search voices", text: $searchText)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(VoiceForgeTheme.field)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(VoiceForgeTheme.stroke, lineWidth: 1)
                    )
            )

        }
        .padding(20)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "person.2.crop.square.stack")
                .font(.system(size: 36))
                .foregroundStyle(VoiceForgeTheme.tertiaryText)
            Text("No voices saved yet")
                .font(.system(size: 15, weight: .semibold))
            Text("Add a reference audio clip and transcript to save it as a reusable voice.")
                .font(.system(size: 12))
                .foregroundStyle(VoiceForgeTheme.secondaryText)
                .multilineTextAlignment(.center)
            Button("Add your first voice") {
                isShowingNewVoice = true
            }
            .buttonStyle(VoiceForgePrimaryButtonStyle())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}

private struct VoiceCard: View {
    @EnvironmentObject private var viewModel: AppViewModel
    let preset: VoicePreset
    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack {
                LinearGradient(
                    colors: [VoiceForgeTheme.accentSoft, VoiceForgeTheme.accentSoft.opacity(0.4)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                Image(systemName: "waveform")
                    .font(.system(size: 42, weight: .semibold))
                    .foregroundStyle(VoiceForgeTheme.accent.opacity(0.7))

                if isHovering || viewModel.previewingVoiceID == preset.id {
                    Color.black.opacity(0.18)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    Button {
                        previewPreset()
                    } label: {
                        Image(systemName: viewModel.isPreviewing(voiceID: preset.id) ? "pause.fill" : "play.fill")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(16)
                            .background(Circle().fill(.black.opacity(0.5)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("voicePreviewButton-\(preset.name)")
                }
            }
            .frame(height: 130)

            VStack(alignment: .leading, spacing: 6) {
                Text(preset.name)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                Text(preset.referenceText.isEmpty ? "No transcript" : preset.referenceText)
                    .font(.system(size: 11))
                    .foregroundStyle(VoiceForgeTheme.secondaryText)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    metadataPill("Reference")
                    metadataPill("Local")
                }
            }

            HStack {
                Button("Use") {
                    viewModel.selectedPresetID = preset.id
                    viewModel.applyPreset(preset)
                    viewModel.destination = .studio
                }
                .buttonStyle(VoiceForgeSecondaryButtonStyle())
                .accessibilityIdentifier("usePresetButton-\(preset.name)")

                Spacer()

                Menu {
                    Button("Use in Studio") {
                        viewModel.selectedPresetID = preset.id
                        viewModel.applyPreset(preset)
                        viewModel.destination = .studio
                    }
                    Button(role: .destructive) {
                        if let idx = viewModel.presets.firstIndex(where: { $0.id == preset.id }) {
                            viewModel.deletePresets(at: IndexSet(integer: idx))
                        }
                    } label: {
                        Text("Delete")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .frame(width: 22, height: 22)
                }
                .menuStyle(.borderlessButton)
                .frame(width: 30)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(VoiceForgeTheme.panelStrong)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(VoiceForgeTheme.stroke, lineWidth: 1)
                )
        )
        .onHover { isHovering = $0 }
    }

    private func metadataPill(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold))
            .tracking(0.4)
            .foregroundStyle(VoiceForgeTheme.tertiaryText)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(VoiceForgeTheme.fieldMuted)
            )
    }

    private func previewPreset() {
        let url = URL(fileURLWithPath: preset.referenceAudioPath)
        viewModel.togglePreview(voiceID: preset.id, url: url)
    }
}

private struct NewVoiceSheet: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var isChoosingAdditional = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Save a new voice")
                .font(.system(size: 18, weight: .semibold))

            VoiceForgeField(title: "Name", caption: "Used to find the voice later.") {
                TextField("e.g. Kayden", text: $viewModel.presetName)
                    .textFieldStyle(.plain)
                    .accessibilityIdentifier("presetNameField")
            }

            VoiceForgeField(title: "Reference audio", caption: nil) {
                HStack {
                    TextField("Path to reference clip", text: $viewModel.referenceAudioPath)
                        .textFieldStyle(.plain)
                    Button("Choose…") { viewModel.chooseReferenceAudio() }
                        .buttonStyle(VoiceForgeSecondaryButtonStyle())
                }
            }

            VoiceForgeField(title: "Reference transcript", caption: "An exact transcript improves voice cloning.") {
                TextField("Type exactly what is said in the clip (or Auto-transcribe)", text: $viewModel.referenceText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(3...6)
                    .accessibilityLabel("Reference transcript")
                    .accessibilityIdentifier("referenceTranscriptField")
                if let suggestion = viewModel.mainTranscriptSuggestion {
                    transcriptSuggestion(suggestion, current: viewModel.referenceText, use: viewModel.useMainTranscriptSuggestion, keep: viewModel.keepMainTranscript, id: "mainTranscriptSuggestion")
                }
                HStack {
                    Button("Auto-transcribe") { viewModel.autoTranscribeReference(path: viewModel.referenceAudioPath, applyToMain: true) }
                        .disabled(viewModel.referenceAudioPath.isEmpty)
                        .accessibilityIdentifier("autoTranscribeMainButton")
                    if !viewModel.referenceActionMessage.isEmpty { Text(viewModel.referenceActionMessage).font(.caption).foregroundStyle(VoiceForgeTheme.secondaryText) }
                }
            }

            VoiceForgeField(title: "Additional references", caption: "Each clip keeps its own exact transcript.") {
                ForEach(viewModel.additionalVoiceReferences.indices, id: \.self) { index in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(URL(fileURLWithPath: viewModel.additionalVoiceReferences[index].audioPath).lastPathComponent)
                            .font(.caption).lineLimit(1)
                        TextField("Type exactly what is said in the clip (or Auto-transcribe)", text: $viewModel.additionalVoiceReferences[index].text, axis: .vertical)
                            .accessibilityIdentifier("additionalTranscriptField-\(index)")
                        if let suggestion = viewModel.additionalTranscriptSuggestions[viewModel.additionalVoiceReferences[index].id] {
                            transcriptSuggestion(suggestion, current: viewModel.additionalVoiceReferences[index].text, use: { viewModel.useAdditionalTranscriptSuggestion(id: viewModel.additionalVoiceReferences[index].id) }, keep: { viewModel.keepAdditionalTranscript(id: viewModel.additionalVoiceReferences[index].id) }, id: "additionalTranscriptSuggestion-\(index)")
                        }
                        HStack {
                            Button("Auto-transcribe") { viewModel.autoTranscribeReference(path: viewModel.additionalVoiceReferences[index].audioPath, additionalIndex: index) }
                            Button("Check clip") { viewModel.inspectReferenceClip(viewModel.additionalVoiceReferences[index]) }
                            Button("Remove", role: .destructive) { viewModel.additionalVoiceReferences.remove(at: index) }
                        }.font(.caption)
                    }
                }
                Button("Add reference clip…") { isChoosingAdditional = true }
            }
            if !viewModel.referenceDiagnostics.isEmpty {
                Text(viewModel.referenceDiagnostics.joined(separator: "\n"))
                    .font(.caption).foregroundStyle(VoiceForgeTheme.danger)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(VoiceForgeSecondaryButtonStyle())
                Button("Save voice") {
                    viewModel.saveCurrentAsPreset()
                    dismiss()
                }
                .buttonStyle(VoiceForgePrimaryButtonStyle())
                .disabled(viewModel.presetName.trimmingCharacters(in: .whitespaces).isEmpty)
                .accessibilityIdentifier("saveCurrentReferenceButton")
            }
        }
        .padding(20)
        .fileImporter(isPresented: $isChoosingAdditional, allowedContentTypes: [.audio], allowsMultipleSelection: true) { result in
            guard case .success(let urls) = result else { return }
            for url in urls { viewModel.addVoiceReference(path: url.path) }
        }
    }

    @ViewBuilder
    private func transcriptSuggestion(_ suggestion: TranscriptSuggestion, current: String, use: @escaping () -> Void, keep: @escaping () -> Void, id: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Your transcript: \(current)").font(.caption).accessibilityIdentifier("typedTranscriptShown-\(id)")
            Text("Whisper suggestion: \(suggestion.text)").font(.caption).accessibilityIdentifier(id)
            if suggestion.materiallyDifferent {
                Label("This differs from your transcript (WER \(Int((suggestion.wordErrorRate ?? 0) * 100))%). Check the audio before replacing it.", systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(VoiceForgeTheme.danger)
                    .accessibilityIdentifier("transcriptMismatchWarning-\(id)")
            } else if let differences = suggestion.differenceSummary(comparedTo: current) {
                let hint = "Possible transcript differences: \(differences)"
                Text(hint)
                    .font(.caption).foregroundStyle(VoiceForgeTheme.secondaryText)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(hint)
                    .accessibilityIdentifier("transcriptDifferenceHint-\(id)")
            }
            HStack {
                Button("Use Whisper version", action: use).accessibilityIdentifier("useTranscriptSuggestion-\(id)")
                Button("Keep mine", action: keep).accessibilityIdentifier("keepTranscriptSuggestion-\(id)")
            }.font(.caption)
        }
        .padding(8)
        .background(VoiceForgeTheme.fieldMuted, in: RoundedRectangle(cornerRadius: 8))
    }
}
