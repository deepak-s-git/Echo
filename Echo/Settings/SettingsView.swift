import SwiftUI

// MARK: - Root Settings View

struct SettingsView: View {

    enum Pane: String, CaseIterable, Identifiable {
        case general = "General"
        case tracking = "Tracking"
        case privacy = "Privacy"
        case appearance = "Appearance"
        case notifications = "Notifications"
        case about = "About"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .general: return "gearshape.fill"
            case .tracking: return "waveform.circle.fill"
            case .privacy: return "lock.shield.fill"
            case .appearance: return "paintbrush.pointed.fill"
            case .notifications: return "bell.badge.fill"
            case .about: return "info.circle.fill"
            }
        }

        var accentColor: Color {
            switch self {
            case .general: return .secondary
            case .tracking: return EchoPalette.indigoSoft
            case .privacy: return Color(red: 0.45, green: 0.72, blue: 0.55)
            case .appearance: return Color(red: 0.72, green: 0.48, blue: 0.88)
            case .notifications: return Color(red: 0.95, green: 0.65, blue: 0.30)
            case .about: return EchoPalette.indigo
            }
        }
    }

    @State private var selectedPane: Pane = .general
    @EnvironmentObject var settings: EchoSettings
    @EnvironmentObject var permissionsManager: PermissionsManager

    var body: some View {
        HStack(spacing: 0) {
            // Sidebar column — fixed width, no NavigationSplitView centering
            SettingsSidebar(selectedPane: $selectedPane)
                .frame(width: 196)

            Divider()

            // Detail pane — fills remaining space
            SettingsPaneContainer(pane: selectedPane)
                .frame(minWidth: 500, minHeight: 460)
        }
        .frame(minWidth: 700, minHeight: 460)
        .background(EchoPalette.graphite)
    }
}

// MARK: - Sidebar

private struct SettingsSidebar: View {
    @Binding var selectedPane: SettingsView.Pane

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 9) {
                ZStack {
                    Circle()
                        .fill(EchoPalette.indigo.opacity(0.14))
                        .frame(width: 26, height: 26)
                    Circle()
                        .fill(EchoPalette.indigo.opacity(0.65))
                        .frame(width: 8, height: 8)
                }
                Text("Settings")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 22)
            .padding(.bottom, 14)

            Divider()
                .padding(.horizontal, 12)
                .padding(.bottom, 6)

            // Nav items
            VStack(alignment: .leading, spacing: 2) {
                ForEach(SettingsView.Pane.allCases) { pane in
                    SettingsSidebarRow(
                        pane: pane,
                        isSelected: selectedPane == pane
                    ) {
                        withAnimation(EchoDesign.subtle) {
                            selectedPane = pane
                        }
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 4)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.ultraThinMaterial)
    }
}

// MARK: - Sidebar Row

private struct SettingsSidebarRow: View {
    let pane: SettingsView.Pane
    let isSelected: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isSelected
                              ? pane.accentColor.opacity(0.18)
                              : Color.primary.opacity(0.06))
                        .frame(width: 26, height: 26)
                    Image(systemName: pane.icon)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(isSelected
                                         ? pane.accentColor
                                         : Color.primary.opacity(0.50))
                }
                Text(pane.rawValue)
                    .font(.system(size: 12.5, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .primary : Color.primary.opacity(0.70))
                Spacer(minLength: 0)
            }
            // Pin content to leading edge — prevents Button from centering
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: EchoDesign.pillRadius, style: .continuous)
                    .fill(
                        isSelected
                            ? pane.accentColor.opacity(0.10)
                            : (hovering ? Color.primary.opacity(0.04) : Color.clear)
                    )
            )
        }
        .buttonStyle(.plain)
        .echoPointingCursor()
        .onHover { hovering = $0 }
        .animation(EchoDesign.subtle, value: isSelected)
        .animation(EchoDesign.subtle, value: hovering)
    }
}

// MARK: - Pane Container

private struct SettingsPaneContainer: View {
    let pane: SettingsView.Pane
    @EnvironmentObject var settings: EchoSettings
    @EnvironmentObject var permissionsManager: PermissionsManager

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            Group {
                switch pane {
                case .general:
                    GeneralPane()
                case .tracking:
                    TrackingPane()
                case .privacy:
                    PrivacyPane()
                case .appearance:
                    AppearancePane()
                case .notifications:
                    NotificationsPane()
                case .about:
                    AboutPane()
                }
            }
            .padding(32)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(settingsPaneBackground)
    }

    private var settingsPaneBackground: some View {
        ZStack {
            EchoPalette.graphiteElevated
            LinearGradient(
                colors: [pane.accentColor.opacity(0.08), Color.clear],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .ignoresSafeArea()
    }
}
