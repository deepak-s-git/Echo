import SwiftUI

struct AppearancePane: View {
    @EnvironmentObject var settings: EchoSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            SettingsPaneHeader(
                icon: "paintbrush.pointed.fill",
                title: "Appearance",
                subtitle: "Theme, display options and visual preferences",
                color: Color(red: 0.72, green: 0.48, blue: 0.88)
            )

            let purple = Color(red: 0.72, green: 0.48, blue: 0.88)

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

            // MARK: Session UI
            SettingsGroup(label: "Session View") {
                SettingsToggleRow(
                    icon: "circle.dotted",
                    iconColor: purple,
                    label: "Show focus score ring",
                    description: "Circular focus quality indicator on the home dashboard",
                    isOn: $settings.showFocusScoreRing,
                    showDivider: true
                )

                SettingsToggleRow(
                    icon: "timeline.selection",
                    iconColor: purple,
                    label: "Compact timeline",
                    description: "Denser timeline layout showing more entries",
                    isOn: $settings.compactTimeline,
                    showDivider: false
                )
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
                                        ? Color(red: 0.72, green: 0.48, blue: 0.88)
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
                        .foregroundStyle(isSelected ? Color(red: 0.72, green: 0.48, blue: 0.88) : .secondary)
                    Text(theme.label)
                        .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? Color(red: 0.72, green: 0.48, blue: 0.88) : .primary)
                }

                // Selected dot
                Circle()
                    .fill(isSelected ? Color(red: 0.72, green: 0.48, blue: 0.88) : Color.clear)
                    .frame(width: 5, height: 5)
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(EchoDesign.subtle, value: isSelected)
        .animation(EchoDesign.subtle, value: hovering)
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

            if settings.showFocusScoreRing {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(EchoPalette.live)
                    Text("Focus score ring visible on dashboard")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: EchoDesign.pillRadius, style: .continuous)
                .fill(Color(red: 0.72, green: 0.48, blue: 0.88).opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: EchoDesign.pillRadius, style: .continuous)
                .strokeBorder(Color(red: 0.72, green: 0.48, blue: 0.88).opacity(0.10), lineWidth: 0.5)
        )
    }
}
