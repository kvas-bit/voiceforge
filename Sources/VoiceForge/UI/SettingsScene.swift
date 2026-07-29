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
            Section("Model") {
                LabeledContent("Engine", value: "Fish Audio S2 Pro (persistent)")
                HStack {
                    Text("Max new tokens")
                    Spacer()
                    Text("\(Int(viewModel.maxNewTokens))")
                        .font(.system(size: 12, design: .monospaced))
                }
                Slider(value: $viewModel.maxNewTokens, in: 256...4096, step: 64)
                Text("VoiceForge uses a persistent Python helper that loads the Fish S2 Pro model once and reuses it for all renders. A direct CLI fallback runs only if the helper cannot start.")
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
                Text("VoiceForge uses a persistent Python helper that loads the model once, then serves sequential requests over JSON-lines. If the helper cannot start, it falls back to direct CLI invocation (no shell). Stderr is isolated from the protocol stream.")
                    .font(.system(size: 11))
                    .foregroundStyle(VoiceForgeTheme.tertiaryText)
            }
        }
        .formStyle(.grouped)
    }
}
