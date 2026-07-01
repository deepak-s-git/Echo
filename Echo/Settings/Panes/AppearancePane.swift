import SwiftUI

struct AppearancePane: View {
    @EnvironmentObject var settings: EchoSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            SettingsPaneHeader(
                icon: "paintbrush.pointed.fill",
                title: "Appearance",
                subtitle: "Theme, display options and visual preferences",
                color: EchoPalette.indigo
            )
            // MARK: Theme
            SettingsGroup(label: "Theme") {
                HStack(alignment: .top, spacing: 16) {
                    ForEach(AppTheme.allCases) { theme in
                        ThemeCard(
                            theme: theme,
                            isSelected: settings.appTheme == theme
                        ) {
                            settings.appTheme = theme
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 18)
            }

            // MARK: Accent Palette
            SettingsGroup(label: "Accent Palette") {
                HStack(spacing: 20) {
                    ForEach(AccentVibe.allCases) { vibe in
                        AccentVibeCard(
                            vibe: vibe,
                            isSelected: settings.accentVibe == vibe
                        ) {
                            settings.accentVibe = vibe
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }

            // MARK: Preview
            AppearancePreviewCard(settings: settings)
        }
    }
}

// MARK: - Theme Card

private struct ThemeCard: View {
    let theme: AppTheme
    let isSelected: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                // Mini preview — fills parent width
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(themeBackground)
                        .frame(height: 66)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(
                                    isSelected
                                        ? EchoPalette.indigo
                                        : Color.primary.opacity(hovering ? 0.14 : 0.06),
                                    lineWidth: isSelected ? 2 : 0.5
                                )
                        )

                    // Mini UI skeleton
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(themeSecondary.opacity(0.35))
                                .frame(width: 28, height: 4)
                            Spacer()
                            Circle()
                                .fill(Color(red: 0.45, green: 0.62, blue: 0.48))
                                .frame(width: 4, height: 4)
                        }
                        RoundedRectangle(cornerRadius: 3)
                            .fill(themeSecondary.opacity(0.15))
                            .frame(height: 16)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(themeSecondary.opacity(0.10))
                            .frame(height: 10)
                    }
                    .padding(10)
                }

                // Label
                HStack(spacing: 5) {
                    Image(systemName: theme.icon)
                        .font(.system(size: 11))
                        .foregroundStyle(isSelected ? EchoPalette.indigo : .secondary)
                    Text(theme.label)
                        .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? EchoPalette.indigo : .primary)
                }

                // Selected dot
                Circle()
                    .fill(isSelected ? EchoPalette.indigo : Color.clear)
                    .frame(width: 5, height: 5)
            }
            .scaleEffect(hovering ? 1.025 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: hovering)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(EchoDesign.subtle, value: isSelected)
    }

    private var themeBackground: Color {
        switch theme {
        case .system: return Color(NSColor.windowBackgroundColor)
        case .light: return Color(red: 0.96, green: 0.96, blue: 0.97)
        case .dark: return Color(red: 0.11, green: 0.11, blue: 0.13)
        }
    }

    private var themeSecondary: Color {
        switch theme {
        case .system, .light: return .black
        case .dark: return .white
        }
    }
}

// MARK: - Appearance Preview Card

private struct AppearancePreviewCard: View {
    let settings: EchoSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "eye")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                Text("Current theme: **\(settings.appTheme.label)**")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                Image(systemName: "paintpalette")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                Text("Accent palette: **\(settings.accentVibe.label)**")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: EchoDesign.pillRadius, style: .continuous)
                .fill(EchoPalette.indigo.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: EchoDesign.pillRadius, style: .continuous)
                .strokeBorder(EchoPalette.indigo.opacity(0.10), lineWidth: 0.5)
        )
    }
}

// MARK: - Accent Vibe Card

private struct AccentVibeCard: View {
    let vibe: AccentVibe
    let isSelected: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                // Color swatch
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(nsColor: vibe.primaryColorDark),
                                    Color(nsColor: vibe.secondaryColorDark)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 32, height: 32)
                        .overlay(
                            Circle()
                                .strokeBorder(
                                    isSelected
                                        ? Color.primary
                                        : Color.clear,
                                    lineWidth: 2
                                )
                        )
                        .shadow(color: Color(nsColor: vibe.primaryColorDark).opacity(hovering ? 0.4 : 0.2), radius: 4, y: 2)
                }
                .scaleEffect(hovering ? 1.15 : 1.0)
                .animation(.spring(response: 0.25, dampingFraction: 0.6), value: hovering)

                Text(vibe.label)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .primary : .secondary)
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
