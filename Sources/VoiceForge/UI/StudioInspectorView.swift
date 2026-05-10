import SwiftUI
#if canImport(VoiceForgeCore)
import VoiceForgeCore
#endif

struct StudioInspectorView: View {
    @EnvironmentObject private var viewModel: AppViewModel

    var body: some View {
        Form {
            Section("Voice") {
                HStack(spacing: 10) {
                    Circle()
                        .fill(VoiceForgeTheme.accentSoft)
                        .frame(width: 36, height: 36)
                        .overlay(
                            Image(systemName: "person.fill")
                                .foregroundStyle(VoiceForgeTheme.accent)
                        )
                    VStack(alignment: .leading, spacing: 2) {
                        Text(currentVoiceName)
                            .font(.system(size: 13, weight: .semibold))
                        Text(currentVoiceDetail)
                            .font(.system(size: 11))
                            .foregroundStyle(VoiceForgeTheme.tertiaryText)
                            .lineLimit(1)
                    }
                    Spacer()
                }
                Menu {
                    Button("From reference clip on disk") {
                        viewModel.chooseReferenceAudio()
                    }
                    if !viewModel.presets.isEmpty {
                        Divider()
                        ForEach(viewModel.presets) { preset in
                            Button(preset.name) {
                                viewModel.selectedPresetID = preset.id
                                viewModel.applyPreset(preset)
                            }
                        }
                    }
                    Divider()
                    Button("Manage voices…") {
                        viewModel.destination = .voices
                    }
                } label: {
                    Label("Choose voice…", systemImage: "chevron.up.chevron.down")
                }
                .accessibilityIdentifier("voicePickerMenu")
            }

            Section("Model") {
                Picker("Model", selection: $viewModel.model) {
                    ForEach(viewModel.availableModels, id: \.self) { model in
                        Text(model).tag(model)
                    }
                }
                .accessibilityIdentifier("modelPicker")
            }

            Section("Global tone") {
                TextField("Tone (e.g. warm narrator)", text: $viewModel.emotionText)
                    .accessibilityIdentifier("emotionField")
                    .onChange(of: viewModel.emotionText) { _, _ in
                        viewModel.persistReferenceFields()
                    }
            }

            Section("Voice settings") {
                LabeledSlider(title: "Stability", value: $viewModel.stability, leading: "Variable", trailing: "Stable")
                LabeledSlider(title: "Similarity", value: $viewModel.similarity, leading: "Low", trailing: "High")
                LabeledSlider(title: "Style", value: $viewModel.styleExaggeration, leading: "None", trailing: "Exaggerated")
                Toggle("Speaker boost", isOn: $viewModel.speakerBoost)
                Text("Stored locally. These map to a remote ElevenLabs backend; the current mlx-speech backend ignores them.")
                    .font(.system(size: 10))
                    .foregroundStyle(VoiceForgeTheme.tertiaryText)
            }

            Section("Generation") {
                HStack {
                    Text("Max tokens")
                    Spacer()
                    Text("\(Int(viewModel.maxNewTokens))")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(VoiceForgeTheme.tertiaryText)
                }
                Slider(value: $viewModel.maxNewTokens, in: 256...4096, step: 64)
                    .accessibilityIdentifier("maxTokensSlider")
                Picker("Edit type", selection: $viewModel.editType) {
                    ForEach(viewModel.editTypes, id: \.self) { type in
                        Text(type.capitalized).tag(type)
                    }
                }
                .accessibilityIdentifier("editTypePicker")
            }

            Section {
                Button {
                    viewModel.generate()
                } label: {
                    HStack {
                        if viewModel.isGenerating {
                            ProgressView().controlSize(.small)
                        }
                        Text(viewModel.isGenerating ? "Generating…" : "Generate")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(VoiceForgePrimaryButtonStyle())
                .disabled(viewModel.isGenerating)
                .accessibilityIdentifier("inspectorGenerateButton")
            }
        }
        .formStyle(.grouped)
    }

    private var currentVoiceName: String {
        if let preset = viewModel.presets.first(where: { $0.id == viewModel.selectedPresetID }) {
            return preset.name
        }
        if !viewModel.referenceAudioPath.isEmpty {
            return URL(fileURLWithPath: viewModel.referenceAudioPath).deletingPathExtension().lastPathComponent
        }
        return "No voice selected"
    }

    private var currentVoiceDetail: String {
        viewModel.referenceAudioPath.isEmpty
            ? "Load a reference clip"
            : viewModel.referenceAudioPath
    }
}

private struct LabeledSlider: View {
    let title: String
    @Binding var value: Double
    let leading: String
    let trailing: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.system(size: 12, weight: .semibold))
                Spacer()
                Text(String(format: "%.0f%%", value * 100))
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(VoiceForgeTheme.tertiaryText)
            }
            Slider(value: $value, in: 0...1)
            HStack {
                Text(leading).font(.system(size: 10)).foregroundStyle(VoiceForgeTheme.tertiaryText)
                Spacer()
                Text(trailing).font(.system(size: 10)).foregroundStyle(VoiceForgeTheme.tertiaryText)
            }
        }
    }
}
