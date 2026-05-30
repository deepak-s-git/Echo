import SwiftUI

// MARK: - SearchView

struct SearchView: View {
    @EnvironmentObject var sessionStore: SessionStore
    @EnvironmentObject var appStore: AppStore
    @State private var query = ""
    @FocusState private var isFocused: Bool

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
                // Premium glassmorphic search bar
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(isFocused ? EchoPalette.glowBlue : .secondary)
                        .scaleEffect(isFocused ? 1.1 : 1.0)
                        .animation(EchoDesign.subtle, value: isFocused)

                    TextField("Search sessions…", text: $query)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14, weight: .medium))
                        .focused($isFocused)
                        .onAppear {
                            if appStore.isSearchPresented { query = "" }
                        }

                    if !query.isEmpty {
                        Button {
                            query = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.tertiary)
                                .font(.system(size: 13))
                        }
                        .buttonStyle(.plain)
                        .echoPointingCursor()
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background {
                    RoundedRectangle(cornerRadius: EchoDesign.pillRadius, style: .continuous)
                        .fill(.ultraThinMaterial)
                }
                .overlay(
                    RoundedRectangle(cornerRadius: EchoDesign.pillRadius, style: .continuous)
                        .strokeBorder(isFocused ? EchoPalette.glowBlue.opacity(0.4) : EchoPalette.stroke, lineWidth: 1.0)
                )
                .shadow(color: isFocused ? EchoPalette.glowBlue.opacity(0.08) : .clear, radius: 8, y: 2)
                .animation(EchoDesign.subtle, value: isFocused)

                if results.isEmpty {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "sparkle.magnifyingglass")
                            .font(.system(size: 32, weight: .thin))
                            .foregroundStyle(EchoPalette.indigo.opacity(0.35))
                        Text("No sessions match")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.secondary)
                        Text("Try searching for tags, app names, or titles.")
                            .font(.system(size: 12))
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity)
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(results) { session in
                                SearchResultCard(session: session) {
                                    appStore.openSessionDetail(session.id)
                                }
                            }
                        }
                    }
                }
            }
            .padding(28)
        }
    }
}

private struct SearchResultCard: View {
    let session: Session
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(EchoPalette.indigo.opacity(0.12))
                        .frame(width: 36, height: 36)
                    Image(systemName: "folder.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(EchoPalette.indigoSoft)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(session.title ?? "Untitled segment")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    
                    HStack(spacing: 6) {
                        Text(session.startedAt.formatted(date: .abbreviated, time: .shortened))
                            .foregroundStyle(.secondary.opacity(0.85))
                        if session.appCount > 0 {
                            Text("·")
                                .foregroundStyle(.tertiary)
                            Text("\(session.appCount) apps")
                                .foregroundStyle(.secondary.opacity(0.85))
                        }
                    }
                    .font(.system(size: 11))
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(hovering ? .secondary : .quaternary)
                    .offset(x: hovering ? 2 : 0)
                    .animation(EchoDesign.subtle, value: hovering)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 14)
            .background {
                RoundedRectangle(cornerRadius: EchoDesign.pillRadius, style: .continuous)
                    .fill(Color.primary.opacity(0.01))
            }
            .overlay(
                RoundedRectangle(cornerRadius: EchoDesign.pillRadius, style: .continuous)
                    .strokeBorder(EchoPalette.stroke, lineWidth: 0.5)
            )
            .scaleEffect(hovering ? 1.005 : 1.0)
            .animation(EchoDesign.subtle, value: hovering)
            .echoHoverHighlight()
            .onHover { hovering = $0 }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - LaunchView

struct LaunchView: View {
    var body: some View {
        ZStack {
            EchoPalette.graphite
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
        .background(EchoDesign.ambientBackground)
    }
}
