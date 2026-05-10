import SwiftUI

enum VoiceForgeTheme {
    static let backgroundTop = Color(red: 0.95, green: 0.952, blue: 0.958)
    static let backgroundBottom = Color(red: 0.9, green: 0.907, blue: 0.918)
    static let panelShell = Color.white.opacity(0.76)
    static let panel = Color(red: 0.985, green: 0.986, blue: 0.989)
    static let panelStrong = Color.white.opacity(0.96)
    static let panelMuted = Color(red: 0.948, green: 0.952, blue: 0.961)
    static let field = Color.white.opacity(0.98)
    static let fieldMuted = Color(red: 0.956, green: 0.961, blue: 0.969)
    static let stroke = Color(red: 0.11, green: 0.13, blue: 0.17).opacity(0.08)
    static let strokeStrong = Color(red: 0.11, green: 0.13, blue: 0.17).opacity(0.14)
    static let primaryText = Color(red: 0.09, green: 0.1, blue: 0.12)
    static let secondaryText = Color(red: 0.33, green: 0.37, blue: 0.43)
    static let tertiaryText = Color(red: 0.48, green: 0.51, blue: 0.58)
    static let accent = Color(red: 0.12, green: 0.43, blue: 0.86)
    static let accentSoft = Color(red: 0.87, green: 0.91, blue: 0.98)
    static let accentStrong = Color(red: 0.08, green: 0.25, blue: 0.53)
    static let sidebar = Color(red: 0.095, green: 0.102, blue: 0.122)
    static let sidebarElevated = Color(red: 0.14, green: 0.147, blue: 0.171)
    static let sidebarText = Color(red: 0.965, green: 0.97, blue: 0.982)
    static let sidebarMutedText = Color(red: 0.68, green: 0.708, blue: 0.765)
    static let ink = Color(red: 0.09, green: 0.11, blue: 0.15)
    static let success = Color(red: 0.17, green: 0.55, blue: 0.39)
    static let danger = Color(red: 0.76, green: 0.25, blue: 0.23)
}

struct VoiceForgeBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [VoiceForgeTheme.backgroundTop, VoiceForgeTheme.backgroundBottom],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(Color.white.opacity(0.62))
                .frame(width: 520, height: 520)
                .blur(radius: 72)
                .offset(x: -420, y: -250)

            Circle()
                .fill(VoiceForgeTheme.accent.opacity(0.14))
                .frame(width: 420, height: 420)
                .blur(radius: 64)
                .offset(x: 460, y: -260)

            Circle()
                .fill(Color(red: 0.58, green: 0.66, blue: 0.84).opacity(0.12))
                .frame(width: 420, height: 420)
                .blur(radius: 72)
                .offset(x: -120, y: 360)

            VStack(spacing: 48) {
                ForEach(0..<12, id: \.self) { _ in
                    Rectangle()
                        .fill(Color.white.opacity(0.18))
                        .frame(height: 1)
                }
            }
            .padding(.horizontal, 28)
            .opacity(0.35)
        }
        .ignoresSafeArea()
    }
}

struct VoiceForgePanelModifier: ViewModifier {
    let fill: Color

    func body(content: Content) -> some View {
        content
            .padding(1.5)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(VoiceForgeTheme.panelShell)
                    .overlay(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .stroke(VoiceForgeTheme.stroke, lineWidth: 1)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 26.5, style: .continuous)
                            .fill(fill)
                            .padding(1.5)
                    )
                    .shadow(color: Color(red: 0.1, green: 0.15, blue: 0.25).opacity(0.08), radius: 34, x: 0, y: 18)
            )
    }
}

extension View {
    func voiceForgePanel(fill: Color = VoiceForgeTheme.panelStrong) -> some View {
        modifier(VoiceForgePanelModifier(fill: fill))
    }
}

struct VoiceForgeField<Content: View>: View {
    let title: String
    let caption: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(VoiceForgeTheme.secondaryText)

            content
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(VoiceForgeTheme.field)
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(VoiceForgeTheme.strokeStrong, lineWidth: 1)
                        )
                )

            if let caption {
                Text(caption)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(VoiceForgeTheme.tertiaryText)
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
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(
                Capsule(style: .continuous)
                    .fill(accent ? VoiceForgeTheme.accent : Color.white.opacity(0.82))
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(accent ? VoiceForgeTheme.accentStrong.opacity(0.2) : VoiceForgeTheme.stroke, lineWidth: 1)
                    )
            )
    }
}

struct VoiceForgePrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Color.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [VoiceForgeTheme.accent, VoiceForgeTheme.accentStrong],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(0.15), lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.8), value: configuration.isPressed)
    }
}

struct VoiceForgeSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(VoiceForgeTheme.primaryText)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(VoiceForgeTheme.field)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(VoiceForgeTheme.strokeStrong, lineWidth: 1)
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .opacity(configuration.isPressed ? 0.95 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.8), value: configuration.isPressed)
    }
}

struct VoiceForgeMetricTile: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(VoiceForgeTheme.tertiaryText)

            Text(value)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(VoiceForgeTheme.primaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(VoiceForgeTheme.fieldMuted)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
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
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(VoiceForgeTheme.accent)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(VoiceForgeTheme.accentSoft.opacity(0.9))
                )

            VStack(alignment: .leading, spacing: 4) {
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
