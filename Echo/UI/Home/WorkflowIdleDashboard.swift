import SwiftUI

/// Shown on Home when not recording — explicit session start, no auto-capture.
struct WorkflowIdleDashboard: View {
    @EnvironmentObject var sessionStore: SessionStore
    @EnvironmentObject var appStore: AppStore
    @EnvironmentObject var sessionControl: SessionControlStore
    @State private var showCreateSheet = false
    @State private var showSelectWorkflowSheet = false
    var body: some View {
        VStack(alignment: .leading, spacing: EchoDesign.sectionSpacing) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Workflow Memory")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(EchoPalette.indigoSoft)
                    .textCase(.uppercase)
                    .tracking(1.0)
                
                Text("Recall and continue your working context instantly.")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.primary)
            }
            .padding(.bottom, 4)

            VStack(spacing: 12) {
                if let thread = sessionStore.continueWorkflowThread, let session = sessionStore.continueSession {
                    DashboardActionButton(
                        title: "Continue Previous Workflow",
                        subtitle: continueSubtitle(for: thread, session: session),
                        icon: "arrow.uturn.backward",
                        prominent: true,
                        gradientColor: true
                    ) {
                        Task { await sessionControl.continuePreviousSession(appStore: appStore) }
                    }
                }

                DashboardActionButton(
                    title: "Start New Workflow",
                    subtitle: "Begin a fresh workflow memory segment",
                    icon: "record.circle",
                    prominent: sessionStore.continueWorkflowThread == nil,
                    gradientColor: false
                ) {
                    showCreateSheet = true
                }

                DashboardActionButton(
                    title: "Start a New Session",
                    subtitle: "Record under an existing workflow context",
                    icon: "plus.circle",
                    prominent: false,
                    gradientColor: false
                ) {
                    showSelectWorkflowSheet = true
                }

                DashboardActionButton(
                    title: "Browse Memories",
                    subtitle: "Open timeline without recording",
                    icon: "timeline.selection",
                    prominent: false,
                    gradientColor: false
                ) {
                    appStore.selectTab(.timeline)
                }
            }
        }
        .padding(24)
        .echoCard(material: .thinMaterial)
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

private struct DashboardActionButton: View {
    let title: String
    let subtitle: String
    let icon: String
    let prominent: Bool
    let gradientColor: Bool
    let action: () -> Void
    
    @State private var hovering = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(prominent ? EchoPalette.indigo.opacity(0.12) : Color.primary.opacity(0.04))
                        .frame(width: 40, height: 40)
                    
                    if gradientColor {
                        Image(systemName: icon)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(EchoPalette.premiumGradient)
                    } else {
                        Image(systemName: icon)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(prominent ? EchoPalette.indigoSoft : .secondary)
                    }
                }
                
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary.opacity(0.85))
                        .lineLimit(1)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(hovering ? .secondary : .quaternary)
                    .offset(x: hovering ? 2 : 0)
                    .animation(EchoDesign.subtle, value: hovering)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .background {
                RoundedRectangle(cornerRadius: EchoDesign.pillRadius, style: .continuous)
                    .fill(prominent ? EchoPalette.indigo.opacity(0.06) : Color.primary.opacity(0.02))
            }
            .overlay(
                RoundedRectangle(cornerRadius: EchoDesign.pillRadius, style: .continuous)
                    .strokeBorder(
                        prominent ? EchoPalette.indigo.opacity(0.15) : EchoPalette.stroke,
                        lineWidth: 0.5
                    )
            )
            .scaleEffect(hovering ? 1.008 : 1.0)
            .animation(EchoDesign.subtle, value: hovering)
            .echoHoverHighlight()
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
    
    var body: some View {
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
                                        selectWorkflow(summary.id)
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 240)
            
            HStack {
                Button("Cancel") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)
                .disabled(isWorking)
                
                Spacer()
            }
        }
        .padding(24)
        .frame(width: 440)
        .onAppear {
            isLoadingThreads = true
            Task {
                await sessionStore.loadWorkflowThreads()
                isLoadingThreads = false
            }
        }
    }
    
    private var filteredThreads: [WorkflowThreadSummary] {
        let active = sessionStore.workflowThreads.filter { $0.thread.statusRaw != "archived" }
        if searchText.trimmingCharacters(in: .whitespaces).isEmpty {
            return active
        }
        return active.filter { summary in
            summary.displayTitle.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    private func selectWorkflow(_ id: UUID) {
        isWorking = true
        Task {
            await sessionControl.continueWorkflowThread(id: id, appStore: appStore)
            isPresented = false
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
    
    private func relativeTimeString(for date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
