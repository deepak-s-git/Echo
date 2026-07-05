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
            return EchoPalette.indigo
        }
    }

    @AppStorage("SettingsSelectedPane") private var selectedPane: Pane = .general
    @EnvironmentObject var settings: EchoSettings
    @EnvironmentObject var permissionsManager: PermissionsManager

    var body: some View {
        HStack(spacing: 0) {
            // Sidebar column — fixed width, no NavigationSplitView centering
            SettingsSidebar(selectedPane: $selectedPane)
                .frame(width: 196)

            Rectangle()
                .fill(EchoPalette.stroke)
                .frame(width: 0.5)

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
                        .frame(width: 24, height: 24)
                    Circle()
                        .fill(EchoPalette.indigo.opacity(0.65))
                        .frame(width: 6, height: 6)
                }
                Text("Settings")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .tracking(0.3)
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 22)
            .padding(.bottom, 14)

            Rectangle()
                .fill(EchoPalette.stroke)
                .frame(height: 0.5)
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
        .background(EchoPalette.sidebar.opacity(0.55))
        .background(.ultraThinMaterial)
    }
}

// MARK: - Sidebar Row

private struct SettingsSidebarRow: View {
    let pane: SettingsView.Pane
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isSelected
                              ? EchoPalette.accent.opacity(0.16)
                              : Color.primary.opacity(0.04))
                        .frame(width: 24, height: 24)
                    Image(systemName: pane.icon)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(isSelected
                                         ? EchoPalette.accent
                                         : Color.primary.opacity(0.55))
                }
                .scaleEffect(isHovered ? 1.05 : 1.0)
                
                Text(pane.rawValue)
                    .font(.system(size: 12.5, weight: isSelected ? .semibold : .semibold))
                    .foregroundStyle(isSelected ? Color.primary : (isHovered ? Color.primary : Color.primary.opacity(0.70)))
                    .offset(x: isHovered && !isSelected ? 1.5 : 0)
                
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: EchoDesign.pillRadius, style: .continuous)
                        .fill(isSelected ? EchoPalette.indigo.opacity(0.12) : .clear)
                    
                    RoundedRectangle(cornerRadius: EchoDesign.pillRadius, style: .continuous)
                        .fill(isHovered && !isSelected ? Color.primary.opacity(0.04) : .clear)
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: EchoDesign.pillRadius, style: .continuous)
                    .strokeBorder(
                        isSelected ? EchoPalette.strokeBright.opacity(0.5) : (isHovered ? EchoPalette.stroke.opacity(0.3) : .clear),
                        lineWidth: 0.5
                    )
            )
            .overlay(alignment: .leading) {
                Capsule()
                    .fill(EchoPalette.accent)
                    .frame(width: 3, height: isSelected ? 14 : 0)
                    .offset(x: 3)
                    .animation(.spring(response: 0.25, dampingFraction: 0.75), value: isSelected)
            }
            .shadow(color: isSelected ? EchoPalette.indigo.opacity(0.08) : .clear, radius: 4, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                isHovered = hovering
            }
        }
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
            EchoDesign.ambientBackground.ignoresSafeArea()
            
            AmbientGlowView()
                .opacity(0.4)
                .allowsHitTesting(false)
        }
    }
}
