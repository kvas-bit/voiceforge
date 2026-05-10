import SwiftUI

struct SettingsWindowView: View {
    @EnvironmentObject private var viewModel: AppViewModel

    var body: some View {
        ZStack {
            VoiceForgeBackground()

            VStack(alignment: .leading, spacing: 20) {
                header

                VStack(alignment: .leading, spacing: 18) {
                    VoiceForgeField(
                        title: "CLI output path",
                        caption: "Every render resolves to the same destination so downstream tools can watch one file."
                    ) {
                        Text(viewModel.outputLocationDescription)
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                            .foregroundStyle(VoiceForgeTheme.primaryText)
                            .textSelection(.enabled)
                            .accessibilityIdentifier("settingsOutputPathText")
                    }

                    VoiceForgeField(
                        title: "Persistence",
                        caption: "Reference audio path, reference transcript, emotion text, history, and saved voices all stay on this Mac."
                    ) {
                        Text("Reset only the current reference fields if you want a clean composer without deleting saved presets.")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(VoiceForgeTheme.secondaryText)
                    }

                    Button("Reset reference fields") {
                        viewModel.resetPersistedValues()
                    }
                    .buttonStyle(VoiceForgeSecondaryButtonStyle())
                    .accessibilityIdentifier("resetReferenceFieldsButton")

                    VoiceForgeField(
                        title: "CLI requirements",
                        caption: nil
                    ) {
                        Text("VoiceForge shells out through `/bin/zsh -lc`, so `mlx-speech` needs to be installed and visible to your shell environment before you render.")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(VoiceForgeTheme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
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
            VoiceForgePill(text: "Workspace settings", accent: true)
            Text("Keep the app predictable.")
                .font(.system(size: 34, weight: .bold))
                .tracking(-0.8)
                .foregroundStyle(VoiceForgeTheme.primaryText)
            Text("This panel is intentionally short. It exposes the fixed output location and the local persistence behavior without hiding core controls behind a settings maze.")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(VoiceForgeTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(24)
        .voiceForgePanel(fill: VoiceForgeTheme.panel)
    }
}
