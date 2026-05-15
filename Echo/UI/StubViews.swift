import SwiftUI

// MARK: - HomeView

struct HomeView: View {
    var body: some View {
        EchoPlaceholder(title: "Home", icon: "house.fill")
    }
}

// MARK: - TimelineView

struct TimelineView: View {
    var body: some View {
        EchoPlaceholder(title: "Timeline", icon: "timeline.selection")
    }
}

// MARK: - SearchView

struct SearchView: View {
    var body: some View {
        EchoPlaceholder(title: "Search", icon: "magnifyingglass")
    }
}

// MARK: - LaunchView

struct LaunchView: View {
    var body: some View {
        ZStack {
            Color(NSColor.windowBackgroundColor)
            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(0.8)
                Text("Starting Echo…")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - OnboardingView

struct OnboardingView: View {
    @EnvironmentObject var appStore: AppStore

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "memorychip")
                .font(.system(size: 52, weight: .thin))
                .foregroundStyle(Color.accentColor)
            Text("Welcome to Echo")
                .font(.system(size: 24, weight: .semibold, design: .rounded))
            Text("Echo remembers your workflow so you don't have to.")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
            Button("Get Started") {
                appStore.completeOnboarding()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            Spacer()
        }
        .frame(maxWidth: 400)
        .padding(40)
    }
}

// MARK: - ErrorView

struct ErrorView: View {
    let error: Error

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40, weight: .thin))
                .foregroundStyle(.red)
            Text("Echo couldn't start")
                .font(.system(size: 18, weight: .semibold))
            Text(error.localizedDescription)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(40)
    }
}

// MARK: - PermissionsView

struct PermissionsView: View {
    @EnvironmentObject var permissionsManager: PermissionsManager

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "lock.shield")
                .font(.system(size: 52, weight: .thin))
                .foregroundStyle(Color.accentColor)
            Text("Accessibility Access Required")
                .font(.system(size: 20, weight: .semibold))
            Text("Echo uses Accessibility to detect which apps you use and how long you use them. No keystrokes or content is ever recorded.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            Button("Grant Access") {
                permissionsManager.requestAccessibility()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            Spacer()
        }
        .padding(40)
    }
}

// MARK: - MenuBarView

struct MenuBarView: View {
    @EnvironmentObject var activityStore: ActivityStore
    @EnvironmentObject var appStore: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Current Session")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Text(activityStore.sessionDuration.sessionDurationFormatted)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.accentColor)
            }

            Divider()

            Button("Open Echo") {
                appStore.showMainWindow()
            }
            .buttonStyle(.plain)
            .font(.system(size: 12))

            Button("Quit") {
                NSApp.terminate(nil)
            }
            .buttonStyle(.plain)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(width: 240)
    }
}

// MARK: - MenuBarLabel

struct MenuBarLabel: View {
    var body: some View {
        Image(systemName: "waveform.circle.fill")
    }
}

// MARK: - Placeholder helper

private struct EchoPlaceholder: View {
    let title: String
    let icon: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 32, weight: .thin))
                .foregroundStyle(Color.accentColor.opacity(0.5))
            Text(title)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
    }
}
