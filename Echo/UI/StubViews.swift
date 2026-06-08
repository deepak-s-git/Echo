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
    @EnvironmentObject var sessionStore: SessionStore
    @EnvironmentObject var sessionControl: SessionControlStore

    @State private var newWorkflowName: String = ""
    @State private var isPulseAnimating = false
    @State private var restoringSessionId: UUID? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header: Brand & Live Pulse
            HStack(spacing: 8) {
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(EchoPalette.premiumGradient)
                
                Text("ECHO")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(EchoPalette.premiumGradient)
                
                Spacer()
                
                // Live Status Indicator
                HStack(spacing: 5) {
                    if activityStore.isSessionActive && !activityStore.isSessionPaused {
                        Circle()
                            .fill(EchoPalette.live)
                            .frame(width: 8, height: 8)
                            .scaleEffect(isPulseAnimating ? 1.3 : 0.85)
                            .opacity(isPulseAnimating ? 0.6 : 1.0)
                            .onAppear {
                                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                                    isPulseAnimating = true
                                }
                            }
                        Text("RECORDING")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(EchoPalette.live)
                    } else if activityStore.isSessionPaused {
                        Circle()
                            .fill(EchoPalette.warning)
                            .frame(width: 8, height: 8)
                        Text("PAUSED")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(EchoPalette.warning)
                    } else {
                        Circle()
                            .fill(Color.secondary.opacity(0.5))
                            .frame(width: 8, height: 8)
                        Text("IDLE")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
                )
            }
            .padding(.bottom, 2)

            // Main Active Recording/Capture Card
            VStack(alignment: .leading, spacing: 12) {
                if activityStore.isSessionActive {
                    // Recording Active State
                    VStack(alignment: .center, spacing: 10) {
                        VStack(spacing: 4) {
                            Text(activityStore.sessionDuration.sessionDurationFormatted)
                                .font(.system(size: 26, weight: .bold, design: .monospaced))
                                .foregroundStyle(activityStore.isSessionPaused ? EchoPalette.warning : EchoPalette.indigoSoft)
                                .shadow(color: (activityStore.isSessionPaused ? EchoPalette.warning : EchoPalette.indigoSoft).opacity(0.15), radius: 6)
                            
                            Text(activityStore.workflowTitle)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                        
                        Divider().opacity(0.3)
                        
                        // Current Application Focus Row
                        HStack(spacing: 8) {
                            Image(systemName: activityStore.isSessionPaused ? "pause.circle.fill" : "sparkles")
                                .font(.system(size: 12))
                                .foregroundStyle(activityStore.isSessionPaused ? EchoPalette.warning : EchoPalette.indigoSoft)
                            
                            Text(activityStore.isSessionPaused ? "Recording Paused" : activityStore.focusHeadline)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            
                            Spacer()
                            
                            if !activityStore.isSessionPaused {
                                Text(activityStore.focusLabel)
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.primary.opacity(0.04), in: Capsule())
                            }
                        }
                        .padding(.horizontal, 4)
                        
                        // Recording Controls
                        HStack(spacing: 12) {
                            // Pause / Resume Toggle
                            Button {
                                Task {
                                    if activityStore.isSessionPaused {
                                        await sessionControl.resumeSession()
                                    } else {
                                        await sessionControl.pauseSession()
                                    }
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: activityStore.isSessionPaused ? "play.fill" : "pause.fill")
                                    Text(activityStore.isSessionPaused ? "Resume" : "Pause")
                                }
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(activityStore.isSessionPaused ? EchoPalette.live : .primary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
                                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5))
                            }
                            .buttonStyle(.plain)
                            .echoPointingCursor()
                            
                            // Stop Session
                            Button {
                                appStore.showMainWindow()
                                sessionControl.requestEndSession(
                                    appStore: appStore,
                                    activityStore: activityStore,
                                    sessionStore: sessionStore
                                )
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "square.fill")
                                    Text("Stop")
                                }
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(EchoPalette.destructive)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(EchoPalette.destructive.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(EchoPalette.destructive.opacity(0.25), lineWidth: 0.5))
                            }
                            .buttonStyle(.plain)
                            .echoPointingCursor()
                        }
                    }
                } else {
                    // Recording Idle State (Quick Capture)
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Start Workflow Recording")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.secondary)
                        
                        HStack(spacing: 8) {
                            TextField("Enter workflow name...", text: $newWorkflowName)
                                .textFieldStyle(.plain)
                                .font(.system(size: 12, weight: .medium))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
                            
                            Button {
                                Task {
                                    let name = newWorkflowName.isEmpty ? "Quick Workflow" : newWorkflowName
                                    await sessionControl.startNewSession(workflowName: name, appStore: appStore)
                                    newWorkflowName = ""
                                }
                            } label: {
                                Image(systemName: "record.circle.fill")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(.red)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 7)
                                    .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.red.opacity(0.2), lineWidth: 0.5))
                            }
                            .buttonStyle(.plain)
                            .echoPointingCursor()
                        }
                        
                        // Preset Tag Suggestions
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach([
                                    ("Coding 💻", "Coding"),
                                    ("Research 🔍", "Research"),
                                    ("Design 🎨", "Design"),
                                    ("Writing ✍️", "Writing")
                                ], id: \.1) { label, name in
                                    Button {
                                        Task {
                                            await sessionControl.startNewSession(workflowName: name, appStore: appStore)
                                        }
                                    } label: {
                                        Text(label)
                                            .font(.system(size: 10, weight: .semibold))
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(Color.primary.opacity(0.04), in: Capsule())
                                            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
                                    }
                                    .buttonStyle(.plain)
                                    .echoPointingCursor()
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
            .padding(12)
            .background(EchoPalette.graphiteElevated, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(EchoPalette.stroke, lineWidth: 0.5)
            )

            // Card 3: Recent Memories list
            let recentMemories = sessionStore.recentSessions.prefix(3)
            if !recentMemories.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("RECENT MEMORIES")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 2)
                    
                    VStack(spacing: 8) {
                        ForEach(recentMemories) { session in
                            HStack(spacing: 10) {
                                // Category Icon
                                ZStack {
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .fill(Color.primary.opacity(0.04))
                                        .frame(width: 26, height: 26)
                                    Image(systemName: session.cluster.icon)
                                        .font(.system(size: 11))
                                        .foregroundStyle(EchoPalette.indigoSoft)
                                }
                                
                                // Text details
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(session.title ?? "Untitled segment")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    
                                    HStack(spacing: 5) {
                                        Text(relativeTimeString(for: session.startedAt))
                                            .foregroundStyle(.secondary)
                                        Text("·")
                                            .foregroundStyle(.tertiary)
                                        Text(session.duration.shortLabel)
                                            .foregroundStyle(.secondary)
                                    }
                                    .font(.system(size: 9))
                                }
                                
                                Spacer()
                                
                                // Restore action button
                                Button {
                                    restoreSession(session)
                                } label: {
                                    ZStack {
                                        if restoringSessionId == session.id {
                                            ProgressView()
                                                .scaleEffect(0.6)
                                        } else {
                                            Image(systemName: "arrow.uturn.backward")
                                                .font(.system(size: 10, weight: .bold))
                                                .foregroundStyle(.primary.opacity(0.7))
                                        }
                                    }
                                    .frame(width: 24, height: 24)
                                    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                                    )
                                }
                                .buttonStyle(.plain)
                                .disabled(restoringSessionId != nil)
                                .echoPointingCursor()
                            }
                            .padding(.vertical, 4)
                            .padding(.horizontal, 6)
                        }
                    }
                    .padding(6)
                    .background(Color.primary.opacity(0.015), in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(EchoPalette.stroke, lineWidth: 0.5))
                }
            }

            Divider().opacity(0.3)

            // Card 4: Footer quick actions
            HStack {
                Button("Open Echo") {
                    appStore.showMainWindow()
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.primary.opacity(0.85))
                .echoPointingCursor()
                
                Spacer()
                
                Button("Quit") {
                    NSApp.terminate(nil)
                }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .echoPointingCursor()
            }
            .padding(.horizontal, 4)
        }
        .padding(16)
        .frame(width: 320)
    }

    private func relativeTimeString(for date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func restoreSession(_ session: Session) {
        guard let plan = session.restorePlan else { return }
        restoringSessionId = session.id
        Task {
            let engine = WorkflowRestoreEngine()
            _ = await engine.restore(plan: plan)
            try? await Task.sleep(for: .seconds(1.2))
            await MainActor.run {
                restoringSessionId = nil
            }
        }
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
