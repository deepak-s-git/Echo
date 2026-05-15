import SwiftUI

struct MainNavigationView: View {
    @EnvironmentObject var appStore: AppStore

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 260)
        } detail: {
            Group {
                switch appStore.selectedTab {
                case .home: HomeView()
                case .timeline: TimelineView()
                case .search: SearchView()
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
                SidebarItem(
                    tab: .home,
                    icon: "house.fill",
                    label: "Home"
                )
                SidebarItem(
                    tab: .timeline,
                    icon: "timeline.selection",
                    label: "Timeline"
                )
                SidebarItem(
                    tab: .search,
                    icon: "magnifyingglass",
                    label: "Search"
                )
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
            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                appStore.selectedTab = tab
            }
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
                    .fill(isSelected ? Color.accentColor.opacity(0.15) : .clear)
            )
            .foregroundStyle(isSelected ? Color.accentColor : Color.primary.opacity(0.7))
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
                    .fill(Color.accentColor.opacity(0.15))
                    .frame(width: 28, height: 28)
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 10, height: 10)
            }
            Text("Echo")
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
            Spacer()
        }
    }
}

// MARK: - Live Session Pill

struct LiveSessionPill: View {
    @EnvironmentObject var activityStore: ActivityStore

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Color.green)
                .frame(width: 6, height: 6)
                .modifier(PulseModifier())

            Text("Session active")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)

            Spacer()

            Text(activityStore.sessionDuration.sessionDurationFormatted)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.accentColor)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.quaternary)
        )
    }
}

// MARK: - Pulse Modifier

struct PulseModifier: ViewModifier {
    @State private var pulsing = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(pulsing ? 1.4 : 1.0)
            .opacity(pulsing ? 0.5 : 1.0)
            .animation(
                .easeInOut(duration: 1.2).repeatForever(autoreverses: true),
                value: pulsing
            )
            .onAppear { pulsing = true }
    }
}
