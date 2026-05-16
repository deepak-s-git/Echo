import SwiftUI

struct MainNavigationView: View {
    @EnvironmentObject var appStore: AppStore

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 260)
        } detail: {
            Group {
                if appStore.showingSessionDetail, let sessionId = appStore.selectedSessionId {
                    SessionDetailView(sessionId: sessionId)
                } else {
                    switch appStore.selectedTab {
                    case .home: HomeView()
                    case .timeline: TimelineView()
                    case .search: SearchView()
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationSplitViewStyle(.prominentDetail)
    }
}

// MARK: - Sidebar

struct SidebarView: View {
    @EnvironmentObject var appStore: AppStore
    @EnvironmentObject var activityStore: ActivityStore

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

            LiveSessionPill()
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
        }
        .background(.ultraThinMaterial)
    }
}

// MARK: - Sidebar Item

struct SidebarItem: View {
    @EnvironmentObject var appStore: AppStore
    let tab: AppStore.NavigationTab
    let icon: String
    let label: String

    private var isSelected: Bool { appStore.selectedTab == tab }

    var body: some View {
        Button {
            appStore.selectedTab = tab
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 18)
                Text(label)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? EchoPalette.indigo.opacity(0.12) : .clear)
            )
            .foregroundStyle(isSelected ? EchoPalette.indigoSoft : Color.primary.opacity(0.7))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Echo Wordmark

struct EchoWordmark: View {
    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(EchoPalette.indigo.opacity(0.12))
                    .frame(width: 28, height: 28)
                Circle()
                    .fill(EchoPalette.indigo.opacity(0.55))
                    .frame(width: 8, height: 8)
            }
            Text("Echo")
                .font(.system(size: 17, weight: .semibold, design: .default))
                .foregroundStyle(.primary)
            Spacer()
        }
    }
}

// MARK: - Live Session Pill

struct LiveSessionPill: View {
    @EnvironmentObject var activityStore: ActivityStore

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                EchoLiveDot(isActive: activityStore.isSessionActive)
                Text(activityStore.isSessionActive ? "Live" : "Idle")
                    .font(.system(size: 10, weight: .semibold))
                    .textCase(.uppercase)
                    .tracking(0.4)
                    .foregroundStyle(.tertiary)
                Spacer()
                Text(activityStore.sessionDuration.sessionDurationFormatted)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(EchoPalette.indigoSoft)
            }

            Text(activityStore.focusHeadline)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.primary.opacity(0.85))
                .lineLimit(1)
            Text(activityStore.workflowIdentity)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
    }
}
