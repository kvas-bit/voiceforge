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

struct GenerationSettingsView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            modelSection
            if viewModel.selectedTTSModel == TTSModel.drama3.rawValue { drama3SamplingSection }
        }
        .formStyle(.grouped)
        .safeAreaInset(edge: .bottom) {
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(VoiceForgePrimaryButtonStyle())
                    .accessibilityIdentifier("closeGenerationSettingsButton")
            }
            .padding(16)
            .background(.bar)
        }
    }

    private var modelSection: some View {
        Section("Model") {
            modelPicker
            if viewModel.selectedTTSModel != TTSModel.drama3.rawValue { tokenControls }
            Text("Drama 3 is the default model; Fish S2 Pro remains available here.")
                .font(.system(size: 11)).foregroundStyle(VoiceForgeTheme.tertiaryText)
            checkpointLabel
        }
    }

    private var modelPicker: some View {
        Picker("Text to speech model", selection: Binding(get: { viewModel.selectedTTSModel }, set: { viewModel.selectTTSModel($0) })) {
            Text("Fish Audio Drama 3").tag(TTSModel.drama3.rawValue)
            Text("Fish Audio S2 Pro").tag(TTSModel.fishS2Pro.rawValue)
        }.accessibilityIdentifier("ttsModelPicker")
    }

    private var tokenControls: some View {
        VStack(alignment: .leading) {
            Text("Max new tokens: \(Int(viewModel.maxNewTokens))")
            Slider(value: $viewModel.maxNewTokens, in: 256...4096, step: 64)
        }
    }

    private var checkpointLabel: some View {
        Text("Loaded checkpoint: " + viewModel.loadedCheckpoint)
    }

    private var drama3SamplingSection: some View {
        Section("Drama 3 sampling") {
            HStack {
                Button("Fish cloud default") { viewModel.setDrama3Preset(expressive: false) }
                    .accessibilityIdentifier("drama3CloudPresetButton")
                Button("Expressive (1.0/0.9/30)") { viewModel.setDrama3Preset(expressive: true) }
                    .accessibilityIdentifier("drama3ExpressivePresetButton")
            }
            Text("Temperature: " + String(format: "%.2f", viewModel.drama3Temperature))
            Slider(value: $viewModel.drama3Temperature, in: 0...1, step: 0.05)
            Text("Top-p: " + String(format: "%.2f", viewModel.drama3TopP))
            Slider(value: $viewModel.drama3TopP, in: 0...1, step: 0.05)
            Stepper("Top-k: \(viewModel.drama3TopK)", value: $viewModel.drama3TopK, in: 1...100)
            TextField("Seed (blank = random)", text: $viewModel.drama3Seed)
                .accessibilityIdentifier("drama3SeedField")
            Toggle("Normalize English and Chinese text", isOn: $viewModel.drama3Normalize)
            Toggle("Token budget: Auto", isOn: $viewModel.drama3AutoTokenBudget)
            if !viewModel.drama3AutoTokenBudget { Slider(value: $viewModel.maxNewTokens, in: 256...8192, step: 64) }
        }
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
