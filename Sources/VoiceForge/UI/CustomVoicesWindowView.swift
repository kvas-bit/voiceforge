import SwiftUI

struct CustomVoicesWindowView: View {
    @EnvironmentObject private var viewModel: AppViewModel

    var body: some View {
        ZStack {
            VoiceForgeBackground()

            VStack(alignment: .leading, spacing: 20) {
                header

                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .top, spacing: 12) {
                        VoiceForgeField(
                            title: "Preset name",
                            caption: "Save the current reference pair under a voice label you can reuse later."
                        ) {
                            TextField("Preset name", text: $viewModel.presetName)
                                .textFieldStyle(.plain)
                                .foregroundStyle(VoiceForgeTheme.primaryText)
                                .accessibilityIdentifier("presetNameField")
                        }

                        Button("Save current reference") {
                            viewModel.saveCurrentAsPreset()
                        }
                        .buttonStyle(VoiceForgePrimaryButtonStyle())
                        .padding(.top, 24)
                        .accessibilityIdentifier("saveCurrentReferenceButton")
                    }

                    if viewModel.presets.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("No saved voices yet.")
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                .foregroundStyle(VoiceForgeTheme.primaryText)
                            Text("Load a reference in the main window, give it a name here, and save it for one-click reuse.")
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundStyle(VoiceForgeTheme.secondaryText)
                        }
                        .padding(18)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .fill(VoiceForgeTheme.panelMuted)
                        )
                    } else {
                        List {
                            ForEach(viewModel.presets) { preset in
                                HStack(alignment: .top, spacing: 14) {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(preset.name)
                                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                                            .foregroundStyle(VoiceForgeTheme.primaryText)
                                        Text(preset.referenceAudioPath)
                                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                                            .foregroundStyle(VoiceForgeTheme.secondaryText)
                                            .lineLimit(1)
                                        Text(preset.referenceText)
                                            .font(.system(size: 12, weight: .medium, design: .rounded))
                                            .foregroundStyle(VoiceForgeTheme.secondaryText)
                                            .lineLimit(2)
                                    }

                                    Spacer(minLength: 10)

                                    Button("Use") {
                                        viewModel.applyPreset(preset)
                                    }
                                    .buttonStyle(VoiceForgeSecondaryButtonStyle())
                                    .accessibilityIdentifier("usePresetButton-\(preset.name)")
                                }
                                .padding(.vertical, 8)
                                .listRowBackground(Color.clear)
                            }
                            .onDelete(perform: viewModel.deletePresets)
                        }
                        .scrollContentBackground(.hidden)
                        .listStyle(.plain)
                        .background(Color.clear)
                        .accessibilityIdentifier("customVoicesList")
                    }
                }
                .padding(24)
                .voiceForgePanel(fill: Color.white.opacity(0.84))

                Spacer(minLength: 0)
            }
            .padding(24)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            VoiceForgePill(text: "Custom voices", accent: true)
            Text("Build a reusable voice shelf.")
                .font(.system(size: 34, weight: .bold))
                .tracking(-0.8)
                .foregroundStyle(VoiceForgeTheme.primaryText)
            Text("This window is for the repeatable part of the workflow: capture a reference once, then recall it instantly when you need another variation.")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(VoiceForgeTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(24)
        .voiceForgePanel(fill: VoiceForgeTheme.panel)
    }
}
