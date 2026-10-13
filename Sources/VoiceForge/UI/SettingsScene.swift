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
            IntelligenceSettingsView()
                .tabItem { Label("Intelligence", systemImage: "sparkles") }
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
                Picker("Text to speech model", selection: Binding(
                    get: { viewModel.selectedTTSModel },
                    set: { viewModel.selectTTSModel($0) }
                )) {
                    ForEach(TTSModel.allCases) { model in
                        Text(model.displayName).tag(model.rawValue)
                    }
                }
                .accessibilityIdentifier("ttsModelPicker")
                HStack {
                    Text("Max new tokens")
                    Spacer()
                    Text("\(Int(viewModel.maxNewTokens))")
                        .font(.system(size: 12, design: .monospaced))
                }
                Slider(value: $viewModel.maxNewTokens, in: 256...4096, step: 64)
                Text("Drama 3 is the default model; Fish S2 Pro remains available here. A persistent Python helper loads the selected model and reuses it for renders, with a model-specific CLI fallback if the helper cannot start. Drama 3 requires an installed MLX checkpoint.")
                    .font(.system(size: 11))
                    .foregroundStyle(VoiceForgeTheme.tertiaryText)
            }
        }
        .formStyle(.grouped)
    }
}

private struct IntelligenceSettingsView: View {
    @EnvironmentObject private var viewModel: AppViewModel

    var body: some View {
        Form {
            Section("Local prompt intelligence") {
                Toggle("Enable Ollama-assisted suggestions", isOn: Binding(
                    get: { viewModel.ollamaEnabled },
                    set: { viewModel.setOllamaEnabled($0) }
                ))
                .accessibilityIdentifier("ollamaEnabledToggle")

                LabeledContent("Status") {
                    Text(statusText)
                        .font(.system(size: 12))
                        .foregroundStyle(VoiceForgeTheme.secondaryText)
                        .accessibilityIdentifier("ollamaStatusText")
                }

                if viewModel.ollamaEnabled {
                    if viewModel.ollamaModels.isEmpty {
                        Text("No models found. Install one with `ollama pull <model>`.")
                            .font(.system(size: 11))
                            .foregroundStyle(VoiceForgeTheme.tertiaryText)
                    } else {
                        Picker("Model", selection: Binding(
                            get: { viewModel.selectedOllamaModel },
                            set: { viewModel.selectOllamaModel($0) }
                        )) {
                            ForEach(viewModel.ollamaModels) { model in
                                Text(model.name).tag(model.name)
                            }
                        }
                        .accessibilityIdentifier("ollamaModelPicker")
                    }

                    Button("Refresh") {
                        Task { await viewModel.refreshOllamaStatus() }
                    }
                    .accessibilityIdentifier("ollamaRefreshButton")
                }

                Text("Off by default. When enabled, VoiceForge looks for a local Ollama install, uses an already-running server if it finds one, or starts one itself — and only ever stops the server it started. Suggestions in Studio are shown separately and never change your script until you tap Apply.")
                    .font(.system(size: 11))
                    .foregroundStyle(VoiceForgeTheme.tertiaryText)
            }
        }
        .formStyle(.grouped)
    }

    private var statusText: String {
        switch viewModel.ollamaStatus {
        case .idle: return "Off"
        case .starting: return "Starting…"
        case .runningOwned: return "Running (started by VoiceForge)"
        case .runningExternal: return "Running (external server)"
        case .unavailable(let reason): return "Unavailable — \(reason)"
        }
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
