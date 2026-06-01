import SwiftUI

enum VoiceForgeTheme {
    // Surface tokens – paired with `.containerBackground(.regularMaterial)` so the
    // window itself supplies vibrancy. These colours are layered *on top* of that material.
    static let panelShell = Color(nsColor: .controlBackgroundColor).opacity(0.6)
    static let panel = Color(nsColor: .controlBackgroundColor).opacity(0.92)
    static let panelStrong = Color(nsColor: .controlBackgroundColor).opacity(0.98)
    static let panelMuted = Color(nsColor: .underPageBackgroundColor).opacity(0.6)
    static let field = Color(nsColor: .textBackgroundColor).opacity(0.96)
    static let fieldMuted = Color(nsColor: .textBackgroundColor).opacity(0.78)
    static let stroke = Color(nsColor: .separatorColor).opacity(0.7)
    static let strokeStrong = Color(nsColor: .separatorColor)
    static let primaryText = Color(nsColor: .labelColor)
    static let secondaryText = Color(nsColor: .secondaryLabelColor)
    static let tertiaryText = Color(nsColor: .tertiaryLabelColor)
    static let accent = Color.accentColor
    static let accentSoft = Color.accentColor.opacity(0.18)
    static let accentStrong = Color.accentColor.opacity(0.92)
    static let sidebar = Color(nsColor: .windowBackgroundColor).opacity(0.001) // transparent: NavigationSplitView paints the sidebar
    static let sidebarElevated = Color(nsColor: .controlBackgroundColor).opacity(0.85)
    static let sidebarText = Color(nsColor: .labelColor)
    static let sidebarMutedText = Color(nsColor: .secondaryLabelColor)
    static let ink = Color(nsColor: .labelColor)
    static let success = Color.green
    static let danger = Color.red
    static let tagBackground = Color.accentColor.opacity(0.16)
    static let tagText = Color.accentColor
}

struct VoiceForgeBackground: View {
    var body: some View {
        Rectangle()
            .fill(.background)
            .ignoresSafeArea()
    }
}

struct VoiceForgePanelModifier: ViewModifier {
    let fill: Color

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(fill)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(VoiceForgeTheme.stroke, lineWidth: 1)
                    )
            )
    }
}

extension View {
    func voiceForgePanel(fill: Color = VoiceForgeTheme.panel) -> some View {
        modifier(VoiceForgePanelModifier(fill: fill))
    }
}

struct VoiceForgeField<Content: View>: View {
    let title: String
    let caption: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(VoiceForgeTheme.secondaryText)

            content
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(VoiceForgeTheme.field)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(VoiceForgeTheme.stroke, lineWidth: 1)
                        )
                )

            if let caption {
                Text(caption)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(VoiceForgeTheme.tertiaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct VoiceForgePill: View {
    let text: String
    let accent: Bool

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(accent ? Color.white : VoiceForgeTheme.secondaryText)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule(style: .continuous)
                    .fill(accent ? VoiceForgeTheme.accent : VoiceForgeTheme.fieldMuted)
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(VoiceForgeTheme.stroke, lineWidth: accent ? 0 : 1)
                    )
            )
    }
}

struct VoiceForgePrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Color.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isEnabled ? VoiceForgeTheme.accent : VoiceForgeTheme.accent.opacity(0.35))
            )
            .opacity(isEnabled ? 1 : 0.72)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.85), value: configuration.isPressed)
    }
}

struct VoiceForgeSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(VoiceForgeTheme.primaryText)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(VoiceForgeTheme.fieldMuted)
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .stroke(VoiceForgeTheme.stroke, lineWidth: 1)
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.85), value: configuration.isPressed)
    }
}

struct VoiceForgeMetricTile: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .tracking(1.0)
                .foregroundStyle(VoiceForgeTheme.tertiaryText)

            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(VoiceForgeTheme.primaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(VoiceForgeTheme.fieldMuted)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(VoiceForgeTheme.stroke, lineWidth: 1)
                )
        )
    }
}

struct VoiceForgeInfoRow: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(VoiceForgeTheme.accent)
                .frame(width: 22, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(VoiceForgeTheme.accentSoft)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(VoiceForgeTheme.primaryText)

                Text(detail)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(VoiceForgeTheme.tertiaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
    }
}
