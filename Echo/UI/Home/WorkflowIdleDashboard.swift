import SwiftUI

/// Shown on Home when not recording — explicit session start, no auto-capture.
struct WorkflowIdleDashboard: View {
    @EnvironmentObject var sessionStore: SessionStore
    @EnvironmentObject var appStore: AppStore
    @EnvironmentObject var sessionControl: SessionControlStore
    @State private var showCreateSheet = false
    @State private var showSelectWorkflowSheet = false
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            // Header with Ambient Glow & Modern Typography
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "circle.grid.2x1.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(EchoPalette.indigoSoft)
                    Text("Workflow Memory")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(EchoPalette.indigoSoft)
                        .tracking(1.5)
                        .textCase(.uppercase)
                }
                
                Text("Recall and continue your working context instantly.")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.primary)
            }
            .padding(.bottom, 2)

            // 1. Resume Workflow (Hero Action with App Icon Stack)
            if let thread = sessionStore.continueWorkflowThread, let session = sessionStore.continueSession {
                let appItems = session.restorePlan?.items.filter { $0.kind == .application } ?? []
                let bundleIds = appItems.compactMap { $0.bundleId }
                
                HeroActionButton(
                    title: "Continue Previous Workflow",
                    subtitle: continueSubtitle(for: thread, session: session),
                    icon: "arrow.uturn.backward",
                    bundleIds: bundleIds
                ) {
                    Task { await sessionControl.continuePreviousSession(appStore: appStore) }
                }
            }

            // 2. Record Section (Grid of 2 upgraded gradient cards)
            VStack(alignment: .leading, spacing: 8) {
                Text("Record Activity")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                    .tracking(0.5)
                    .textCase(.uppercase)
                
                HStack(spacing: 12) {
                    GridActionButton(
                        title: "Start New Workflow",
                        subtitle: "Begin a fresh topic context from scratch",
                        icon: "sparkles",
                        gradientColors: [Color.orange, Color.pink]
                    ) {
                        showCreateSheet = true
                    }
                    
                    GridActionButton(
                        title: "Record in Existing",
                        subtitle: "Start a session under an active project",
                        icon: "folder.badge.plus",
                        gradientColors: [Color(red: 0.18, green: 0.72, blue: 0.72), EchoPalette.indigoSoft]
                    ) {
                        showSelectWorkflowSheet = true
                    }
                }
            }

            // 3. History Section
            VStack(alignment: .leading, spacing: 8) {
                Text("History")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                    .tracking(0.5)
                    .textCase(.uppercase)
                
                SubtleActionButton(
                    title: "Browse Memories",
                    subtitle: "Open timeline without recording",
                    icon: "timeline.selection"
                ) {
                    appStore.selectTab(.timeline)
                }
            }

            // 4. Quick Stats Footer
            if !sessionStore.workflowThreads.isEmpty {
                HStack(spacing: 16) {
                    let activeCount = sessionStore.workflowThreads.filter { $0.thread.statusRaw != "archived" }.count
                    HStack(spacing: 4) {
                        Image(systemName: "circle.grid.2x1")
                            .font(.system(size: 9))
                        Text("\(activeCount) active \(activeCount == 1 ? "workflow" : "workflows")")
                    }
                    
                    let totalDuration = sessionStore.workflowThreads.map { $0.thread.totalAccumulatedDuration }.reduce(0, +)
                    if totalDuration > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "clock")
                                .font(.system(size: 9))
                            Text("Total tracked: \(totalDuration.sessionDurationFormatted)")
                        }
                    }
                }
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 4)
                .padding(.top, 4)
            }
        }
        .padding(24)
        .echoCard(material: .ultraThinMaterial)
        .background {
            AmbientGlowView()
                .offset(y: -20)
                .allowsHitTesting(false)
        }
        .sheet(isPresented: $showCreateSheet) {
            WorkflowCreateSheet(isPresented: $showCreateSheet)
                .environmentObject(appStore)
                .environmentObject(sessionControl)
        }
        .sheet(isPresented: $showSelectWorkflowSheet) {
            SelectWorkflowSheet(isPresented: $showSelectWorkflowSheet)
                .environmentObject(appStore)
                .environmentObject(sessionControl)
                .environmentObject(sessionStore)
        }
        .onAppear {
            Task {
                await sessionStore.refreshContinuationThread()
            }
        }
    }

    private func continueSubtitle(for thread: WorkflowThread, session: Session) -> String {
        let threadTitle = thread.title ?? "Untitled workflow"
        let sessionTitle = session.title ?? "Untitled session"
        let diff = Date().timeIntervalSince(session.endedAt ?? thread.lastActiveAt)
        let minutes = Int(diff / 60)
        let timeString: String
        if minutes <= 0 {
            timeString = "just now"
        } else if minutes == 1 {
            timeString = "1 minute ago"
        } else {
            timeString = "\(minutes) minutes ago"
        }
        return "Workflow: \(threadTitle) · Latest Session: \(sessionTitle) · Ended \(timeString)"
    }
}

struct WorkflowCreateSheet: View {
    @EnvironmentObject var appStore: AppStore
    @EnvironmentObject var sessionControl: SessionControlStore
    @Binding var isPresented: Bool
    
    @State private var workflowName: String = ""
    @State private var isWorking = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Start New Workflow")
                .font(.system(size: 18, weight: .semibold))
            
            Text("Give your workflow a permanent identity.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            
            TextField("Workflow Name", text: $workflowName)
                .textFieldStyle(.roundedBorder)
                .disabled(isWorking)
            
            HStack {
                Button("Cancel") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)
                .disabled(isWorking)
                
                Spacer()
                
                let displayName = workflowName.trimmingCharacters(in: .whitespacesAndNewlines)
                Button(displayName.isEmpty ? "Create Workflow" : "Create Workflow \(displayName)") {
                    isWorking = true
                    Task {
                        let name = workflowName.trimmingCharacters(in: .whitespacesAndNewlines)
                        await sessionControl.startNewSession(workflowName: name.isEmpty ? "Untitled workflow" : name, appStore: appStore)
                        isPresented = false
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(isWorking || workflowName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 400)
        .onAppear {
            workflowName = ""
        }
    }
}

private struct HeroActionButton: View {
    let title: String
    let subtitle: String
    let icon: String
    let bundleIds: [String]
    let action: () -> Void
    
    @State private var hovering = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(
                            colors: [EchoPalette.indigo.opacity(hovering ? 0.25 : 0.15), EchoPalette.indigo.opacity(hovering ? 0.08 : 0.04)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                        .frame(width: 44, height: 44)
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(EchoPalette.indigoSoft)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(title)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.primary)
                        
                        Text("RESUME LATEST")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(EchoPalette.indigoSoft)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(EchoPalette.indigo.opacity(0.12))
                            )
                            .overlay(
                                Capsule()
                                    .stroke(EchoPalette.indigoSoft.opacity(0.3), lineWidth: 0.5)
                            )
                    }
                    
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary.opacity(0.85))
                        .lineLimit(1)
                    
                    if !bundleIds.isEmpty {
                        HStack(spacing: -6) {
                            ForEach(Array(bundleIds.prefix(8).enumerated()), id: \.element) { index, bundleId in
                                AppIconView(bundleId: bundleId, size: 20)
                                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                                            .stroke(Color.black.opacity(0.2), lineWidth: 0.5)
                                    )
                                    .shadow(color: .black.opacity(0.1), radius: 1, y: 1)
                                    .zIndex(Double(bundleIds.count - index))
                            }
                            if bundleIds.count > 8 {
                                Text("+\(bundleIds.count - 8)")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(Color.primary.opacity(0.06), in: Capsule())
                                    .padding(.leading, 4)
                            }
                        }
                        .padding(.top, 2)
                    }
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary.opacity(0.6))
                    .offset(x: hovering ? 3 : 0)
                    .animation(.spring(response: 0.25, dampingFraction: 0.7), value: hovering)
            }
            .padding(.vertical, 16)
            .padding(.horizontal, 20)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: EchoDesign.cardCornerRadius, style: .continuous)
                        .fill(Color.primary.opacity(hovering ? 0.025 : 0.005))
                    
                    if hovering {
                        RoundedRectangle(cornerRadius: EchoDesign.cardCornerRadius, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [EchoPalette.indigo.opacity(0.06), Color.purple.opacity(0.02)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: EchoDesign.cardCornerRadius, style: .continuous)
                    .strokeBorder(
                        hovering ? LinearGradient(colors: [EchoPalette.indigoSoft.opacity(0.5), Color.purple.opacity(0.25)], startPoint: .topLeading, endPoint: .bottomTrailing) :
                        LinearGradient(colors: [EchoPalette.stroke, EchoPalette.stroke.opacity(0.5)], startPoint: .top, endPoint: .bottom),
                        lineWidth: 0.5
                    )
            )
            .shadow(color: hovering ? EchoPalette.indigoSoft.opacity(0.05) : Color.clear, radius: 10, y: 3)
            .scaleEffect(hovering ? 1.005 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.75), value: hovering)
            .echoPointingCursor()
            .onHover { hovering = $0 }
        }
        .buttonStyle(.plain)
    }
}

private struct GridActionButton: View {
    let title: String
    let subtitle: String
    let icon: String
    let gradientColors: [Color]
    let action: () -> Void
    
    @State private var hovering = false
    
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 14) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(
                            colors: [gradientColors[0].opacity(hovering ? 0.2 : 0.1), gradientColors[1].opacity(hovering ? 0.08 : 0.04)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                        .frame(width: 44, height: 44)
                    
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(LinearGradient(
                            colors: [gradientColors[0], gradientColors[1]],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary.opacity(0.85))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                
                Spacer(minLength: 0)
            }
            .padding(18)
            .frame(maxWidth: .infinity, minHeight: 136)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: EchoDesign.cardCornerRadius, style: .continuous)
                        .fill(Color.primary.opacity(hovering ? 0.02 : 0.005))
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: EchoDesign.cardCornerRadius, style: .continuous)
                    .strokeBorder(
                        hovering ? LinearGradient(colors: [gradientColors[0].opacity(0.5), gradientColors[1].opacity(0.2)], startPoint: .topLeading, endPoint: .bottomTrailing) :
                        LinearGradient(colors: [EchoPalette.stroke, EchoPalette.stroke.opacity(0.5)], startPoint: .top, endPoint: .bottom),
                        lineWidth: 0.5
                    )
            )
            .shadow(color: hovering ? gradientColors[0].opacity(0.04) : Color.clear, radius: 8, y: 3)
            .scaleEffect(hovering ? 1.008 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.75), value: hovering)
            .echoPointingCursor()
            .onHover { hovering = $0 }
        }
        .buttonStyle(.plain)
    }
}

private struct SubtleActionButton: View {
    let title: String
    let subtitle: String
    let icon: String
    let action: () -> Void
    
    @State private var hovering = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(hovering ? EchoPalette.indigo.opacity(0.12) : Color.primary.opacity(0.04))
                        .frame(width: 36, height: 36)
                        .animation(.spring(response: 0.25, dampingFraction: 0.75), value: hovering)
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(hovering ? EchoPalette.indigoSoft : .secondary)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary.opacity(0.85))
                        .lineLimit(1)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(hovering ? EchoPalette.indigoSoft : Color.secondary.opacity(0.3))
                    .offset(x: hovering ? 2 : 0)
                    .animation(.spring(response: 0.25, dampingFraction: 0.75), value: hovering)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 16)
            .background {
                RoundedRectangle(cornerRadius: EchoDesign.pillRadius, style: .continuous)
                    .fill(Color.primary.opacity(hovering ? 0.015 : 0.005))
            }
            .overlay(
                RoundedRectangle(cornerRadius: EchoDesign.pillRadius, style: .continuous)
                    .strokeBorder(hovering ? EchoPalette.indigoSoft.opacity(0.3) : EchoPalette.stroke, lineWidth: 0.5)
            )
            .scaleEffect(hovering ? 1.003 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.75), value: hovering)
            .echoPointingCursor()
            .onHover { hovering = $0 }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - SelectWorkflowSheet

struct SelectWorkflowSheet: View {
    @EnvironmentObject var sessionStore: SessionStore
    @EnvironmentObject var appStore: AppStore
    @EnvironmentObject var sessionControl: SessionControlStore
    @Binding var isPresented: Bool
    
    @State private var searchText = ""
    @State private var isWorking = false
    @State private var isLoadingThreads = false
    
    @State private var selectedWorkflowThread: WorkflowThreadSummary? = nil
    @State private var selectedSession: Session? = nil
    @State private var selectableRestoreItems: [RestoreWeighting.SelectableItem] = []
    @State private var isLoadingActivities = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let thread = selectedWorkflowThread {
                if let session = selectedSession {
                    restoreChecklistStage(thread: thread, session: session)
                } else {
                    sessionListStage(thread: thread)
                }
            } else {
                workflowListStage()
            }
        }
        .padding(24)
        .frame(width: 440, height: 440)
        .onAppear {
            isLoadingThreads = true
            Task {
                await sessionStore.loadWorkflowThreads()
                isLoadingThreads = false
            }
        }
    }
    
    // MARK: - Stages
    
    private func workflowListStage() -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Record under Existing Workflow")
                .font(.system(size: 16, weight: .bold))
            
            Text("Choose an active workflow thread to start a new session segment under.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            
            // Search Bar
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                TextField("Search workflows…", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
            
            // Workflow List
            VStack {
                if isLoadingThreads {
                    Spacer()
                    ProgressView()
                        .controlSize(.small)
                    Spacer()
                } else {
                    let filtered = filteredThreads
                    if filtered.isEmpty {
                        Spacer()
                        VStack(spacing: 8) {
                            Image(systemName: "folder.badge.questionmark")
                                .font(.system(size: 28, weight: .thin))
                                .foregroundStyle(.secondary.opacity(0.6))
                            Text(searchText.isEmpty ? "No workflows available" : "No matching workflows")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        Spacer()
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 8) {
                                ForEach(filtered) { summary in
                                    WorkflowSelectionCard(summary: summary) {
                                        withAnimation(EchoDesign.subtle) {
                                            selectedWorkflowThread = summary
                                        }
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(maxHeight: .infinity)
            
            HStack {
                Button("Cancel") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)
                .disabled(isWorking)
                
                Spacer()
            }
            .padding(.top, 4)
        }
    }
    
    private func sessionListStage(thread: WorkflowThreadSummary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with back button
            HStack(spacing: 8) {
                Button {
                    withAnimation(EchoDesign.subtle) {
                        selectedWorkflowThread = nil
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 11, weight: .bold))
                        Text("Workflows")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(EchoPalette.indigoSoft)
                }
                .buttonStyle(.plain)
                .echoPointingCursor()
                
                Spacer()
            }
            .padding(.bottom, 4)
            
            Text(thread.displayTitle)
                .font(.system(size: 16, weight: .bold))
                .lineLimit(1)
            
            Text("Select a previous session to restore, or start a new segment.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            
            // Start New Session Card
            Button {
                isWorking = true
                Task {
                    await sessionControl.continueWorkflowThread(id: thread.id, appStore: appStore)
                    isPresented = false
                }
            } label: {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(EchoPalette.indigo.opacity(0.12))
                            .frame(width: 32, height: 32)
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(EchoPalette.indigoSoft)
                    }
                    
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Start New Session under this Workflow")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.primary)
                        Text("Begin recording a fresh segment from scratch")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(Color.primary.opacity(0.02), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5))
            }
            .buttonStyle(.plain)
            .echoPointingCursor()
            .padding(.vertical, 4)
            
            Text("PAST SESSIONS")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.secondary)
                .tracking(0.5)
                .padding(.top, 4)
            
            // List of Sessions
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(thread.segments) { session in
                        Button {
                            isLoadingActivities = true
                            selectedSession = session
                            Task {
                                let events = await sessionStore.fetchActivities(sessionId: session.id)
                                let plan = session.restorePlan ?? WorkflowRestorePlan.empty
                                withAnimation(EchoDesign.subtle) {
                                    self.selectableRestoreItems = RestoreWeighting.buildSelectableItems(from: events, plan: plan)
                                    isLoadingActivities = false
                                }
                            }
                        } label: {
                            HStack(spacing: 12) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .fill(Color.primary.opacity(0.04))
                                        .frame(width: 28, height: 28)
                                    Image(systemName: "clock.arrow.circlepath")
                                        .font(.system(size: 12))
                                        .foregroundStyle(.secondary)
                                }
                                
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(session.title ?? "Untitled Session")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    
                                    HStack(spacing: 6) {
                                        Text(session.duration.sessionDurationFormatted)
                                        Text("·")
                                        Text("\(session.appCount) apps")
                                        if let ended = session.endedAt {
                                            Text("·")
                                            Text(relativeTimeString(for: ended))
                                        }
                                    }
                                    .font(.system(size: 9))
                                    .foregroundStyle(.secondary)
                                }
                                
                                Spacer()
                                
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(.quaternary)
                            }
                            .padding(.vertical, 6)
                            .padding(.horizontal, 10)
                            .background(Color.primary.opacity(0.01), in: RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.04), lineWidth: 0.5))
                        }
                        .buttonStyle(.plain)
                        .echoPointingCursor()
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(maxHeight: 180)
            
            Spacer(minLength: 0)
        }
    }
    
    private func restoreChecklistStage(thread: WorkflowThreadSummary, session: Session) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with back button
            HStack(spacing: 8) {
                Button {
                    withAnimation(EchoDesign.subtle) {
                        selectedSession = nil
                        selectableRestoreItems = []
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 11, weight: .bold))
                        Text("Sessions")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(EchoPalette.indigoSoft)
                }
                .buttonStyle(.plain)
                .echoPointingCursor()
                
                Spacer()
            }
            .padding(.bottom, 4)
            
            Text("Restore: \(session.title ?? "Untitled Session")")
                .font(.system(size: 16, weight: .bold))
                .lineLimit(1)
            
            Text("Choose which apps and tabs to restore and continue.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            
            VStack {
                if isLoadingActivities {
                    Spacer()
                    ProgressView()
                        .controlSize(.small)
                    Spacer()
                } else if selectableRestoreItems.isEmpty {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "doc.badge.gearshape")
                            .font(.system(size: 24, weight: .thin))
                            .foregroundStyle(.secondary.opacity(0.6))
                        Text("No restorable items found for this session.")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 6) {
                            ForEach(0..<selectableRestoreItems.count, id: \.self) { idx in
                                let item = selectableRestoreItems[idx]
                                Button {
                                    selectableRestoreItems[idx].isSelected.toggle()
                                } label: {
                                    HStack(spacing: 10) {
                                        Image(systemName: item.isSelected ? "checkmark.square.fill" : "square")
                                            .font(.system(size: 14))
                                            .foregroundStyle(item.isSelected ? EchoPalette.indigoSoft : .secondary)
                                        
                                        if let bundleId = item.item.bundleId {
                                            AppIconView(bundleId: bundleId, size: 20)
                                                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                                        } else {
                                            Image(systemName: systemImage(for: item.item.kind))
                                                .font(.system(size: 11))
                                                .frame(width: 20, height: 20)
                                                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 4))
                                        }
                                        
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(item.item.label)
                                                .font(.system(size: 11, weight: .medium))
                                                .foregroundStyle(.primary)
                                                .lineLimit(1)
                                            
                                            let subText = item.item.url ?? item.item.path ?? item.item.workingDirectory ?? ""
                                            if !subText.isEmpty {
                                                Text(subText)
                                                    .font(.system(size: 9))
                                                    .foregroundStyle(.secondary)
                                                    .lineLimit(1)
                                            }
                                        }
                                        Spacer()
                                    }
                                    .padding(.vertical, 6)
                                    .padding(.horizontal, 10)
                                    .background(Color.primary.opacity(0.01), in: RoundedRectangle(cornerRadius: 6))
                                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.primary.opacity(0.04), lineWidth: 0.5))
                                }
                                .buttonStyle(.plain)
                                .echoPointingCursor()
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(maxHeight: 200)
            
            Divider().opacity(0.3)
            
            HStack {
                Button("Cancel") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)
                .disabled(isWorking)
                
                Spacer()
                
                let selected = selectableRestoreItems.filter(\.isSelected)
                
                Button {
                    isWorking = true
                    Task {
                        var plan = RestoreWeighting.filteredPlan(from: selectableRestoreItems)
                        if plan.items.isEmpty {
                            plan = RestoreWeighting.fallbackPlan(from: [], plan: session.restorePlan ?? WorkflowRestorePlan.empty)
                        }
                        await sessionControl.restoreAndContinueWorkflowThread(
                            id: thread.id,
                            plan: plan,
                            appStore: appStore
                        )
                        isPresented = false
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.clockwise.circle.fill")
                            .font(.system(size: 12))
                        Text("Restore & Continue")
                            .font(.system(size: 12, weight: .bold))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(EchoPalette.indigo.opacity(selected.isEmpty ? 0.08 : 0.16))
                    .foregroundStyle(selected.isEmpty ? .secondary : EchoPalette.indigoSoft)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(EchoPalette.indigo.opacity(selected.isEmpty ? 0.1 : 0.3), lineWidth: 0.5)
                    )
                }
                .buttonStyle(.plain)
                .disabled(isWorking)
                .echoPointingCursor()
            }
            .padding(.top, 4)
        }
    }
    
    // MARK: - Helpers
    
    private var filteredThreads: [WorkflowThreadSummary] {
        let active = sessionStore.workflowThreads.filter { $0.thread.statusRaw != "archived" }
        if searchText.trimmingCharacters(in: .whitespaces).isEmpty {
            return active
        }
        return active.filter { summary in
            summary.displayTitle.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    private func systemImage(for kind: RestoreItem.RestoreKind) -> String {
        switch kind {
        case .application: return "app.fill"
        case .url, .browserPage: return "globe"
        case .folder: return "folder"
        case .document: return "doc.text"
        case .terminalDirectory: return "terminal"
        case .workspace: return "macwindow"
        }
    }
}

// MARK: - WorkflowSelectionCard

struct WorkflowSelectionCard: View {
    let summary: WorkflowThreadSummary
    let action: () -> Void
    
    @State private var hovering = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(hovering ? EchoPalette.indigo.opacity(0.12) : Color.primary.opacity(0.04))
                        .frame(width: 34, height: 34)
                    
                    Image(systemName: "rectangle.stack.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(hovering ? EchoPalette.indigoSoft : .secondary)
                }
                
                VStack(alignment: .leading, spacing: 3) {
                    Text(summary.displayTitle)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    
                    HStack(spacing: 6) {
                        let count = summary.segments.count
                        Text("\(count) \(count == 1 ? "session" : "sessions")")
                        Text("·")
                        Text("Active \(relativeTimeString(for: summary.thread.lastActiveAt))")
                    }
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(hovering ? .secondary : .quaternary)
                    .offset(x: hovering ? 1 : 0)
                    .animation(EchoDesign.subtle, value: hovering)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(hovering ? Color.primary.opacity(0.015) : Color.clear)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(hovering ? EchoPalette.stroke : Color.clear, lineWidth: 0.5)
            )
            .scaleEffect(hovering ? 1.005 : 1.0)
            .animation(EchoDesign.subtle, value: hovering)
            .echoPointingCursor()
            .onHover { hovering = $0 }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Ambient Glow

struct AmbientGlowView: View {
    @State private var rotation: Double = 0.0
    
    var body: some View {
        ZStack {
            // First glowing blob (Vibrant Indigo/Blue Gradient)
            Circle()
                .fill(LinearGradient(
                    colors: [
                        Color(red: 0.25, green: 0.35, blue: 0.95),
                        Color(red: 0.15, green: 0.55, blue: 0.90)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
                .frame(width: 340, height: 340)
                .blur(radius: 55)
                .opacity(0.24)
                .offset(x: -70, y: -50)
            
            // Second glowing blob (Vibrant Purple/Pink Gradient)
            Circle()
                .fill(LinearGradient(
                    colors: [
                        Color(red: 0.60, green: 0.25, blue: 0.85),
                        Color(red: 0.90, green: 0.20, blue: 0.65)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
                .frame(width: 300, height: 300)
                .blur(radius: 50)
                .opacity(0.18)
                .offset(x: 70, y: 50)
        }
        .rotationEffect(.degrees(rotation))
        .onAppear {
            DispatchQueue.main.async {
                withAnimation(.linear(duration: 30.0).repeatForever(autoreverses: false)) {
                    rotation = 360.0
                }
            }
        }
    }
}

// MARK: - Fileprivate Helpers

fileprivate func relativeTimeString(for date: Date) -> String {
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .abbreviated
    return formatter.localizedString(for: date, relativeTo: Date())
}
