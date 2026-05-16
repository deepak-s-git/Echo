import SwiftUI

// MARK: - SearchView

struct SearchView: View {
    @EnvironmentObject var sessionStore: SessionStore
    @EnvironmentObject var appStore: AppStore
    @State private var query = ""

    private var results: [Session] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return sessionStore.recentSessions }
        return sessionStore.recentSessions.filter {
            ($0.title ?? "").lowercased().contains(q)
        }
    }

    var body: some View {
        ZStack {
            EchoDesign.ambientBackground.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 20) {
                TextField("Search sessions", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 14))
                    .onAppear {
                        if appStore.isSearchPresented { query = "" }
                    }

                if results.isEmpty {
                    Spacer()
                    Text("No sessions match")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                    Spacer()
                } else {
                    List(results) { session in
                        Button {
                            appStore.openSessionDetail(session.id)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(session.title ?? "Untitled")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(.primary)
                                Text(session.startedAt, style: .date)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                    }
                    .listStyle(.plain)
                }
            }
            .padding(28)
        }
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
                .foregroundStyle(EchoPalette.indigoSoft)
            Text("Welcome to Echo")
                .font(.system(size: 24, weight: .semibold))
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
                .foregroundStyle(EchoPalette.indigoSoft)
            Text("Accessibility Access Required")
                .font(.system(size: 20, weight: .semibold))
            Text("Echo uses Accessibility to detect which apps you use and how long you use them. No keystrokes or content is ever recorded.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)

            VStack(spacing: 12) {
                Button("Open System Settings") {
                    permissionsManager.requestAccessibility()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Text("Toggle the switch for **Echo** (or **Xcode** if running in debug mode) in Privacy & Security → Accessibility.")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
            }

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
            VStack(alignment: .leading, spacing: 4) {
                Text(activityStore.focusHeadline)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Text(activityStore.workflowIdentity)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                HStack {
                    EchoLiveDot(isActive: activityStore.isSessionActive)
                    Text(activityStore.sessionDuration.sessionDurationFormatted)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(EchoPalette.indigoSoft)
                    Spacer()
                    Text(activityStore.focusLabel)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
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
