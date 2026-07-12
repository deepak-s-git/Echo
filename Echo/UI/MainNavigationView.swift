import SwiftUI

struct MainNavigationView: View {
    @EnvironmentObject var appStore: AppStore
    @EnvironmentObject var sessionControl: SessionControlStore

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 260)
        } detail: {
            Group {
                switch appStore.selectedTab {
                case .home:
                    HomeView()
                case .timeline:
                    TimelineView()
                case .search:
                    SearchView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationSplitViewStyle(.balanced)
        .sheet(item: $appStore.pendingSessionEnd) { request in
            SessionEndSheet(request: request)
                .environmentObject(appStore)
                .environmentObject(sessionControl)
        }
        .overlay(alignment: .top) {
            if let toast = appStore.finalizingToast {
                Text(toast)
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.3), in: Capsule())
                    .overlay(Capsule().strokeBorder(EchoPalette.stroke, lineWidth: 0.5))
                    .padding(.top, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.2), value: appStore.finalizingToast)
    }
}

// MARK: - Sidebar

struct SidebarView: View {
    @EnvironmentObject var appStore: AppStore
    @EnvironmentObject var activityStore: ActivityStore
    @ObservedObject private var settings = EchoSettings.shared

    var body: some View {
        VStack(spacing: 0) {
            EchoWordmark()
                .padding(.top, 28)
                .padding(.bottom, 24)
                .padding(.horizontal, 20)

            VStack(spacing: 4) {
                SidebarItem(tab: .home, icon: "house.fill", label: "Home")
                SidebarItem(tab: .timeline, icon: "timeline.selection", label: "Timeline")
                SidebarItem(tab: .search, icon: "magnifyingglass", label: "Search")
            }
            .padding(.horizontal, 12)

            Spacer()

            if activityStore.isRecording {
                LiveSessionPill()
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)

                SessionControlBar(compact: true)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
            } else {
                HStack(spacing: 10) {
                    Circle()
                        .fill(EchoPalette.live)
                        .frame(width: 6, height: 6)
                        .shadow(color: EchoPalette.live.opacity(0.5), radius: 2)
                        .frame(width: 18)
                    Text("Ready")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
            }

            Divider()
                .opacity(0.4)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)

            SidebarSettingsButton()
                .padding(.horizontal, 12)
                .padding(.bottom, 20)
        }
        .background(EchoPalette.sidebar)
    }
}

// MARK: - Sidebar Item

struct SidebarItem: View {
    @EnvironmentObject var appStore: AppStore
    let tab: AppStore.NavigationTab
    let icon: String
    let label: String

    @ObservedObject private var settings = EchoSettings.shared
    @State private var isHovered = false

    private var isSelected: Bool { appStore.selectedTab == tab }

    var body: some View {
        Button {
            appStore.selectTab(tab)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 18)
                    .foregroundStyle(isSelected ? Color.primary : (isHovered ? Color.primary : Color.primary.opacity(0.65)))
                    .scaleEffect(isHovered && !isSelected ? 1.04 : 1.0)
                    .offset(x: isHovered && !isSelected ? 1.0 : 0)
                
                Text(label)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.primary : (isHovered ? Color.primary : Color.primary.opacity(0.75)))
                
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
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
                    .frame(width: 3, height: isSelected ? 16 : 0)
                    .offset(x: 4)
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

// MARK: - Sidebar Settings Button

struct SidebarSettingsButton: View {
    @State private var isHovered = false

    var body: some View {
        SettingsLink {
            HStack(spacing: 10) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 18)
                    .foregroundStyle(isHovered ? Color.primary : Color.primary.opacity(0.65))
                    .scaleEffect(isHovered ? 1.06 : 1.0)
                    .offset(x: isHovered ? 1.5 : 0)
                
                Text("Settings")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isHovered ? Color.primary : Color.primary.opacity(0.75))
                
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: EchoDesign.pillRadius, style: .continuous)
                    .fill(isHovered ? Color.primary.opacity(0.04) : .clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: EchoDesign.pillRadius, style: .continuous)
                    .strokeBorder(
                        isHovered ? EchoPalette.stroke.opacity(0.3) : .clear,
                        lineWidth: 0.5
                    )
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Echo Wordmark

struct EchoWordmark: View {
    var body: some View {
        HStack(spacing: 10) {
            Image("butterfly_logo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 22, height: 22)
            
            Text("Echo")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .tracking(0.5)
                .foregroundStyle(.primary)
            
            Spacer()
        }
    }
}



// MARK: - Live Session Pill

struct LiveSessionPill: View {
    @EnvironmentObject var activityStore: ActivityStore
    @EnvironmentObject var sessionStore: SessionStore

    private var recordingLabel: String {
        switch activityStore.recordingState {
        case .recording: return "Recording"
        case .paused: return "Paused"
        case .restoring: return "Restoring"
        case .idle: return "Idle"
        }
    }

    private var totalDurationLabel: String {
        let total = activityStore.threadAccumulatedDuration + activityStore.sessionDuration
        return total.sessionDurationFormatted
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                EchoLiveDot(isActive: activityStore.recordingState == .recording || activityStore.recordingState == .restoring)
                Text(recordingLabel)
                    .font(.system(size: 10, weight: .semibold))
                    .textCase(.uppercase)
                    .tracking(0.4)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(totalDurationLabel)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(EchoPalette.indigoSoft)
            }

            Text(activityStore.focusHeadline)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.primary)
                .lineLimit(1)
            Text(activityStore.workflowIdentity)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: EchoDesign.pillRadius, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
    }
}

extension SessionLifecycleState {
    var label: String {
        switch self {
        case .active: return "Live"
        case .paused: return "Paused"
        case .idle: return "Idle"
        case .recovered: return "Recovered"
        case .ended: return "Ended"
        case .archived: return "Archived"
        }
    }
}
