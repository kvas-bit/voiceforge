import SwiftUI
#if canImport(VoiceForgeCore)
import VoiceForgeCore
#endif

struct SettingsScene: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gearshape") }
            GenerationSettingsView()
                .tabItem { Label("Generation", systemImage: "slider.horizontal.3") }
            AdvancedSettingsView()
                .tabItem { Label("Advanced", systemImage: "terminal") }
        }
        .padding(20)
    }
}

private struct GeneralSettingsView: View {
    @EnvironmentObject private var viewModel: AppViewModel

    var body: some View {
        Form {
            Section("Output") {
                LabeledContent("Outputs folder") {
                    Text(viewModel.outputLocationDescription)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(VoiceForgeTheme.secondaryText)
                        .textSelection(.enabled)
                        .accessibilityIdentifier("settingsOutputPathText")
                }
                Text("Each render is written to a unique <uuid>.wav inside this folder so history entries never collide and can be replayed independently.")
                    .font(.system(size: 11))
                    .foregroundStyle(VoiceForgeTheme.tertiaryText)
            }

            Section("Reference fields") {
                Button("Reset reference fields") {
                    viewModel.resetPersistedValues()
                }
                .accessibilityIdentifier("resetReferenceFieldsButton")
                Text("Clears the saved reference audio path, transcript, and global tone. Voice presets are kept.")
                    .font(.system(size: 11))
                    .foregroundStyle(VoiceForgeTheme.tertiaryText)
            }
        }
        .formStyle(.grouped)
    }
}

private struct GenerationSettingsView: View {
    @EnvironmentObject private var viewModel: AppViewModel

    var body: some View {
        Form {
            Section("Defaults") {
                Picker("Model", selection: $viewModel.model) {
                    ForEach(viewModel.availableModels, id: \.self) { Text($0).tag($0) }
                }
                HStack {
                    Text("Max new tokens")
                    Spacer()
                    Text("\(Int(viewModel.maxNewTokens))")
                        .font(.system(size: 12, design: .monospaced))
                }
                Slider(value: $viewModel.maxNewTokens, in: 256...4096, step: 64)
            }

            Section("Voice settings (advisory)") {
                Toggle("Speaker boost", isOn: $viewModel.speakerBoost)
                Text("Stability, similarity, and style sliders are stored locally and will be applied if a remote ElevenLabs backend is connected. The current mlx-speech backend ignores them.")
                    .font(.system(size: 11))
                    .foregroundStyle(VoiceForgeTheme.tertiaryText)
            }
        }
        .formStyle(.grouped)
    }
}

private struct AdvancedSettingsView: View {
    var body: some View {
        Form {
            Section("Backend") {
                LabeledContent("CLI", value: "mlx-speech")
                LabeledContent("Invocation", value: "/bin/zsh -lc")
                Text("VoiceForge shells out through /bin/zsh -lc, so mlx-speech needs to be installed and visible to your shell environment before you render.")
                    .font(.system(size: 11))
                    .foregroundStyle(VoiceForgeTheme.tertiaryText)
            }
        }
        .formStyle(.grouped)
    }
}
