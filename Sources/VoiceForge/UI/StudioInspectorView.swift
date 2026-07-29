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
                            .accessibilityIdentifier("studioVoiceNameText")
                        Text(currentVoiceDetail)
                            .font(.system(size: 11))
                            .foregroundStyle(VoiceForgeTheme.tertiaryText)
                            .lineLimit(1)
                            .accessibilityIdentifier("studioVoiceDetailText")
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
                HStack {
                    Text("Engine")
                    Spacer()
                    Text("Fish S2 Pro")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(VoiceForgeTheme.tertiaryText)
                }
                .accessibilityIdentifier("modelLabel")
            }

            Section("Global tone") {
                TextField("Tone (e.g. warm narrator)", text: $viewModel.emotionText)
                    .accessibilityIdentifier("emotionField")
                    .onChange(of: viewModel.emotionText) { _, _ in
                        viewModel.persistReferenceFields()
                    }
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
            }

            // Generate / Cancel
            Section {
                if viewModel.isGenerating {
                    Button(role: .destructive) {
                        viewModel.cancelGeneration()
                    } label: {
                        HStack {
                            ProgressView().controlSize(.small)
                            Text("Cancel — \(viewModel.generationPhase.rawValue.capitalized)")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(VoiceForgePrimaryButtonStyle())
                    .accessibilityIdentifier("inspectorCancelButton")
                } else {
                    Button {
                        viewModel.generate()
                    } label: {
                        Text("Generate")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(VoiceForgePrimaryButtonStyle())
                    .disabled(viewModel.sourceText.isEmpty || viewModel.referenceAudioPath.isEmpty || viewModel.referenceText.isEmpty)
                    .accessibilityIdentifier("inspectorGenerateButton")
                }
            }

            // Latest render result
            if let outputURL = viewModel.lastOutputURL {
                Section("Latest render") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "waveform.circle.fill")
                                .font(.title3)
                                .foregroundStyle(VoiceForgeTheme.accent)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(outputURL.lastPathComponent)
                                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                    .lineLimit(1)
                                if let size = fileSize(outputURL.path) {
                                    Text(size)
                                        .font(.system(size: 10))
                                        .foregroundStyle(VoiceForgeTheme.tertiaryText)
                                }
                            }
                            Spacer()
                        }

                        HStack(spacing: 8) {
                            Button {
                                OutputPlaybackControl.toggle(
                                    url: outputURL,
                                    player: viewModel.audioPlayer
                                )
                            } label: {
                                Image(systemName: viewModel.audioPlayer.isPlaying(url: outputURL) ? "pause.fill" : "play.fill")
                            }
                            .accessibilityIdentifier("inspectorPlayOutputButton")

                            Button {
                                viewModel.saveOutputAs()
                            } label: {
                                Image(systemName: "square.and.arrow.down")
                            }

                            Button {
                                viewModel.revealOutputInFinder()
                            } label: {
                                Image(systemName: "folder")
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .accessibilityIdentifier("latestRenderCard")
                }
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

    private func fileSize(_ path: String) -> String? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let size = attrs[.size] as? Int64 else { return nil }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
}
