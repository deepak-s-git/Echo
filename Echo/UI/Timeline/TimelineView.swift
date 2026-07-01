import SwiftUI

/// Timeline column: list OR session detail — never a trapping NavigationStack.
struct TimelineView: View {
    @EnvironmentObject var sessionStore: SessionStore
    @EnvironmentObject var activityStore: ActivityStore
    @EnvironmentObject var appStore: AppStore
    @EnvironmentObject var sessionControl: SessionControlStore
    @ObservedObject private var settings = EchoSettings.shared
    
    @State private var expandedLogsThreadIds: Set<UUID> = []
    
    // Alerts & Confirmations
    private enum ActiveAlert: Identifiable {
        case deleteSingle(WorkflowThreadSummary)
        case eraseAll
        case bulkDelete(count: Int)
        case deleteSession(Session, index: Int)
        case bulkDeleteSessions(count: Int)
        
        var id: String {
            switch self {
            case .deleteSingle(let summary):
                return "delete-single-\(summary.id.uuidString)"
            case .eraseAll:
                return "erase-all"
            case .bulkDelete(let count):
                return "bulk-delete-\(count)"
            case .deleteSession(let segment, let index):
                return "delete-session-\(segment.id.uuidString)-\(index)"
            case .bulkDeleteSessions(let count):
                return "bulk-delete-sessions-\(count)"
            }
        }
    }
    
    @State private var activeAlert: ActiveAlert? = nil
    
    // Multi-select Select Mode (Workflows)
    @State private var isSelectMode = false
    @State private var selectedThreadIds = Set<UUID>()
    
    // Multi-select Session Select Mode
    @State private var isSessionSelectMode = false
    @State private var sessionSelectThreadId: UUID? = nil
    @State private var selectedSessionIds = Set<UUID>()
    
    // Filter State
    @State private var selectedClusterFilter: WorkflowCluster? = nil
    @State private var isFilterExpanded = false
    @State private var showArchived = false

    private var activeThreads: [WorkflowThreadSummary] {
        sessionStore.workflowThreads.filter { summary in
            if showArchived {
                return summary.thread.statusRaw == "archived"
            } else {
                return summary.thread.statusRaw != "archived"
            }
        }
    }

    var filteredThreads: [WorkflowThreadSummary] {
        activeThreads.filter { summary in
            let cluster = summary.segments.first?.cluster ?? .mixed
            return selectedClusterFilter == nil || cluster == selectedClusterFilter
        }
    }

    var body: some View {
        Group {
            if let sessionId = appStore.timelineDetailSessionId {
                SessionDetailView(sessionId: sessionId)
            } else {
                timelineList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var timelineList: some View {
        ZStack {
            EchoDesign.ambientBackground.ignoresSafeArea()
            
            // Subtle rotating ambient backdrop glow
            AmbientGlowView()
                .opacity(0.6)
                .offset(y: -100)
                .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 0) {
                // Top Header Bar
                HStack(spacing: 16) {
                    if isSelectMode {
                        Text("Select Workflows")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(.primary)
                        
                        Spacer()
                        
                        Button("Cancel") {
                            withAnimation(EchoDesign.subtle) {
                                isSelectMode = false
                                selectedThreadIds.removeAll()
                            }
                        }
                        .buttonStyle(.bordered)
                        
                        Button(action: {
                            activeAlert = .bulkDelete(count: selectedThreadIds.count)
                        }) {
                            Text("Delete Selected (\(selectedThreadIds.count))")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color.red)
                        .disabled(selectedThreadIds.isEmpty)
                    } else if isSessionSelectMode {
                        Text("Delete Sessions")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(.primary)
                        
                        Spacer()
                        
                        Button("Cancel") {
                            withAnimation(EchoDesign.subtle) {
                                isSessionSelectMode = false
                                sessionSelectThreadId = nil
                                selectedSessionIds.removeAll()
                            }
                        }
                        .buttonStyle(.bordered)
                        
                        Button(action: {
                            activeAlert = .bulkDeleteSessions(count: selectedSessionIds.count)
                        }) {
                            Text("Delete Selected (\(selectedSessionIds.count))")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color.red)
                        .disabled(selectedSessionIds.isEmpty)
                    } else {
                        HStack(alignment: .center, spacing: 10) {
                            Text("Timeline")
                                .font(.system(size: 24, weight: .bold))
                                .foregroundStyle(.primary)
                            
                            let threads = activeThreads
                            if !threads.isEmpty {
                                let totalWorkflows = threads.count
                                let totalSessions = threads.map { $0.segments.count }.reduce(0, +)
                                let totalDuration = threads.map { $0.totalDuration }.reduce(0, +)
                                
                                HStack(spacing: 6) {
                                    InlineMetricBadge(label: "\(totalWorkflows) \(showArchived ? "archived" : "active")", icon: "network", color: EchoPalette.accent)
                                    InlineMetricBadge(label: "\(totalSessions) sessions", icon: "clock.arrow.circlepath", color: EchoPalette.indigoSoft)
                                    if totalDuration > 0 {
                                        InlineMetricBadge(label: totalDuration.sessionDurationFormatted, icon: "clock", color: .secondary)
                                    }
                                }
                                .transition(.opacity)
                            }
                        }
                        
                        Spacer()
                        
                        HStack(spacing: 8) {
                            // Filter Button
                            Button(action: {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                                    isFilterExpanded.toggle()
                                }
                            }) {
                                Image(systemName: "line.3.horizontal.decrease.circle")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(selectedClusterFilter != nil || isFilterExpanded ? EchoPalette.accent : Color.secondary)
                                    .frame(width: 28, height: 28)
                                    .background(Color.primary.opacity(selectedClusterFilter != nil || isFilterExpanded ? 0.08 : 0.04), in: RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                            
                            // Ellipsis/Menu Button
                            Menu {
                                Button(action: {
                                    withAnimation(EchoDesign.subtle) {
                                        isSelectMode = true
                                        selectedThreadIds.removeAll()
                                    }
                                }) {
                                    Label("Delete Workflows", systemImage: "checklist")
                                }
                                
                                Button(role: .destructive, action: {
                                    activeAlert = .eraseAll
                                }) {
                                    Label("Erase Timeline", systemImage: "trash")
                                }
                            } label: {
                                Image(systemName: "ellipsis")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(Color.secondary)
                                    .frame(width: 28, height: 28)
                                    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                            }
                            .menuStyle(.button)
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, EchoDesign.containerRadius)
                .padding(.top, EchoDesign.containerRadius)
                .padding(.bottom, 12)
                
                // Collapsible Filter Bar
                if isFilterExpanded {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            FilterPill(label: "Show Archived", isSelected: showArchived, clusterColor: Color.gray) {
                                withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                                    showArchived.toggle()
                                }
                            }
                            
                            Divider()
                                .frame(height: 12)
                                .opacity(0.3)
                            
                            FilterPill(label: "All", isSelected: selectedClusterFilter == nil) {
                                withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                                    selectedClusterFilter = nil
                                }
                            }
                            
                            ForEach(WorkflowCluster.allCases, id: \.self) { cluster in
                                FilterPill(label: cluster.label, isSelected: selectedClusterFilter == cluster, clusterColor: cluster.colors.first ?? EchoPalette.accent) {
                                    withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                                        selectedClusterFilter = cluster
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, EchoDesign.containerRadius)
                    }
                    .padding(.bottom, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

                if sessionStore.isLoading {
                    Spacer()
                    HStack {
                        Spacer()
                        ProgressView("Loading memories…")
                        Spacer()
                    }
                    Spacer()
                } else if activeThreads.isEmpty {
                    Spacer()
                    HStack {
                        Spacer()
                        emptyTimeline
                        Spacer()
                    }
                    Spacer()
                } else if filteredThreads.isEmpty {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                            .font(.system(size: 36, weight: .thin))
                            .foregroundStyle(EchoPalette.indigo.opacity(0.35))
                        Text("No matching workflows")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.secondary)
                        Text("Try adjusting your category filter.")
                            .font(.system(size: 13))
                            .foregroundStyle(.tertiary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                        
                        Button("Reset filter") {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                                selectedClusterFilter = nil
                            }
                        }
                        .buttonStyle(.bordered)
                        .padding(.top, 8)
                    }
                    .frame(maxWidth: .infinity)
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            if activityStore.isRecording && !isSelectMode {
                                VStack(spacing: 0) {
                                    SessionControlBar(compact: false)
                                        .padding(.bottom, 4)
                                    liveBanner
                                }
                                .transition(.move(edge: .top).combined(with: .opacity))
                            }

                            ForEach(filteredThreads) { summary in
                                HStack(spacing: 12) {
                                    if isSelectMode {
                                        let isSelected = selectedThreadIds.contains(summary.id)
                                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                            .font(.system(size: 18, weight: .medium))
                                            .foregroundStyle(isSelected ? Color.red : Color.primary.opacity(0.35))
                                            .frame(width: 24, height: 24)
                                    }

                                    WorkflowThreadCard(
                                        summary: summary,
                                        logsExpanded: expandedLogsThreadIds.contains(summary.id) || (isSessionSelectMode && sessionSelectThreadId == summary.id),
                                        isSelectMode: isSelectMode,
                                        isSessionSelectMode: isSessionSelectMode,
                                        sessionSelectThreadId: sessionSelectThreadId,
                                        selectedSessionIds: selectedSessionIds,
                                        onToggleLogs: {
                                            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                                if expandedLogsThreadIds.contains(summary.id) {
                                                    expandedLogsThreadIds.remove(summary.id)
                                                } else {
                                                    expandedLogsThreadIds.insert(summary.id)
                                                }
                                            }
                                        },
                                        onSelectSegment: { appStore.openSessionDetail($0) },
                                        onDeleteWorkflow: {
                                            activeAlert = .deleteSingle(summary)
                                        },
                                        onDeleteSession: { segment, index in
                                            activeAlert = .deleteSession(segment, index: index)
                                        },
                                        onStartSessionSelect: {
                                            withAnimation(EchoDesign.subtle) {
                                                isSessionSelectMode = true
                                                sessionSelectThreadId = summary.id
                                                selectedSessionIds.removeAll()
                                            }
                                        },
                                        onToggleSessionSelect: { id in
                                            if selectedSessionIds.contains(id) {
                                                selectedSessionIds.remove(id)
                                            } else {
                                                selectedSessionIds.insert(id)
                                            }
                                        }
                                    )
                                    .disabled(isSelectMode || (isSessionSelectMode && sessionSelectThreadId != summary.id))
                                    .opacity((isSessionSelectMode && sessionSelectThreadId != summary.id) ? 0.4 : 1.0)
                                }
                                .contentShape(Rectangle())
                                .transition(.opacity.combined(with: .scale(scale: 0.95)))
                                .onTapGesture {
                                    if isSelectMode {
                                        if selectedThreadIds.contains(summary.id) {
                                            selectedThreadIds.remove(summary.id)
                                        } else {
                                            selectedThreadIds.insert(summary.id)
                                        }
                                    }
                                }
                            }
                        }
                        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: filteredThreads.map(\.id))
                        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: activityStore.isRecording)
                        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isSelectMode)
                        .padding(.horizontal, EchoDesign.containerRadius)
                        .padding(.bottom, EchoDesign.containerRadius)
                    }
                }
            }
        }
        .alert(item: $activeAlert) { alertType in
            switch alertType {
            case .deleteSession(let segment, let index):
                let displayName = segment.title?.isEmpty == false ? segment.title! : "Session \(index)"
                return Alert(
                    title: Text("Delete \(displayName)"),
                    message: Text("Are you sure you want to permanently delete \"\(displayName)\"? This will erase all its recorded activities and cannot be undone."),
                    primaryButton: .destructive(Text("Delete")) {
                        Task {
                            await sessionControl.deleteSession(
                                id: segment.id,
                                appStore: appStore
                            )
                        }
                    },
                    secondaryButton: .cancel()
                )
            case .deleteSingle(let summary):
                return Alert(
                    title: Text("Delete Workflow"),
                    message: Text("Are you sure you want to permanently delete \"\(summary.displayTitle)\"? This will erase all its recorded sessions and cannot be undone."),
                    primaryButton: .destructive(Text("Delete")) {
                        Task {
                            await sessionControl.deleteWorkflowThread(
                                id: summary.id,
                                appStore: appStore
                            )
                        }
                    },
                    secondaryButton: .cancel()
                )
            case .eraseAll:
                return Alert(
                    title: Text("Erase Entire Timeline"),
                    message: Text("Are you sure you want to permanently delete all workflows and sessions? This will completely clear your database and cannot be undone."),
                    primaryButton: .destructive(Text("Erase All")) {
                        Task {
                            await sessionControl.clearAllData()
                        }
                    },
                    secondaryButton: .cancel()
                )
            case .bulkDelete(let count):
                return Alert(
                    title: Text("Delete Selected Workflows"),
                    message: Text("Are you sure you want to permanently delete the \(count) selected workflows and all their sessions? This cannot be undone."),
                    primaryButton: .destructive(Text("Delete")) {
                        let ids = selectedThreadIds
                        withAnimation(EchoDesign.subtle) {
                            isSelectMode = false
                            selectedThreadIds.removeAll()
                        }
                        Task {
                            for id in ids {
                                await sessionControl.deleteWorkflowThread(
                                    id: id,
                                    appStore: appStore
                                )
                            }
                        }
                    },
                    secondaryButton: .cancel()
                )
            case .bulkDeleteSessions(let count):
                return Alert(
                    title: Text("Delete Selected Sessions"),
                    message: Text("Are you sure you want to permanently delete the \(count) selected sessions? This will erase all their recorded activities and cannot be undone."),
                    primaryButton: .destructive(Text("Delete")) {
                        let ids = selectedSessionIds
                        withAnimation(EchoDesign.subtle) {
                            isSessionSelectMode = false
                            sessionSelectThreadId = nil
                            selectedSessionIds.removeAll()
                        }
                        Task {
                            await sessionControl.deleteSessions(ids: ids, appStore: appStore)
                        }
                    },
                    secondaryButton: .cancel()
                )
            }
        }
        .sheet(item: $appStore.renameSessionDraft) { draft in
            SessionRenameSheet(draft: draft)
                .environmentObject(appStore)
                .environmentObject(sessionControl)
        }
        .sheet(item: $appStore.renameThreadDraft) { draft in
            WorkflowThreadRenameSheet(draft: draft)
                .environmentObject(appStore)
                .environmentObject(sessionControl)
        }
    }

    private var liveBanner: some View {
        Button {
            if let id = activityStore.currentSession?.id {
                appStore.openSessionDetail(id)
            }
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(activityStore.isSessionPaused ? Color.orange.opacity(0.12) : EchoPalette.live.opacity(0.12))
                        .frame(width: 28, height: 28)
                    
                    EchoLiveDot(isActive: activityStore.recordingState == .recording)
                }
                
                VStack(alignment: .leading, spacing: 3) {
                    Text(activityStore.isSessionPaused ? "Recording Paused" : "Active Recording Session")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.primary)
                    Text("Session is actively tracking background activities")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 3) {
                    Text(activityStore.focusHeadline)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(activityStore.isSessionPaused ? .orange : EchoPalette.live)
                        .lineLimit(1)
                    Text(activityStore.workflowIdentity)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary.opacity(0.5))
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .background(
                RoundedRectangle(cornerRadius: EchoDesign.cardCornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: EchoDesign.cardCornerRadius, style: .continuous)
                    .strokeBorder(
                        activityStore.isSessionPaused
                            ? Color.orange.opacity(0.3)
                            : EchoPalette.live.opacity(0.3),
                        lineWidth: 0.5
                    )
            )
            .shadow(color: (activityStore.isSessionPaused ? Color.orange : EchoPalette.live).opacity(0.04), radius: 6, y: 2)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }

    private var emptyTimeline: some View {
        VStack(spacing: 12) {
            Image(systemName: "timeline.selection")
                .font(.system(size: 36, weight: .thin))
                .foregroundStyle(EchoPalette.indigo.opacity(0.35))
            Text("Your workflow memories will gather here")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
            Text("Start a workflow from Home when you're ready to record.")
                .font(.system(size: 13))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }
}

// MARK: - Workflow thread card

private struct WorkflowThreadCard: View {
    let summary: WorkflowThreadSummary
    let logsExpanded: Bool
    let isSelectMode: Bool
    let isSessionSelectMode: Bool
    let sessionSelectThreadId: UUID?
    let selectedSessionIds: Set<UUID>
    let onToggleLogs: () -> Void
    let onSelectSegment: (UUID) -> Void
    let onDeleteWorkflow: () -> Void
    let onDeleteSession: (Session, Int) -> Void
    let onStartSessionSelect: () -> Void
    let onToggleSessionSelect: (UUID) -> Void

    @EnvironmentObject var appStore: AppStore
    @EnvironmentObject var sessionControl: SessionControlStore

    @ObservedObject private var settings = EchoSettings.shared
    @State private var hovering = false
    @State private var hoveredSessionId: UUID? = nil
    @State private var isVisible = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header Row (Clickable to Expand/Collapse)
            HStack(alignment: .center, spacing: 14) {
                // Dynamic Icon based on category cluster of latest segment
                let cluster = summary.segments.first?.cluster ?? .mixed
                ClusterIconView(cluster: cluster)

                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .center, spacing: 8) {
                        Text(summary.displayTitle)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        
                        if summary.thread.statusRaw == "archived" {
                            Text("Archived")
                                .font(.system(size: 9, weight: .bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.primary.opacity(0.1))
                                .cornerRadius(5)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 5)
                                        .stroke(Color.primary.opacity(0.15), lineWidth: 0.5)
                                )
                                .foregroundStyle(.secondary)
                        } else if summary.activeSegment != nil {
                            Text("Active")
                                .font(.system(size: 9, weight: .bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.green.opacity(0.12))
                                .cornerRadius(5)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 5)
                                        .stroke(Color.green.opacity(0.25), lineWidth: 0.5)
                                )
                                .foregroundStyle(Color.green)
                        } else if summary.segments.count > 1 {
                            let count = summary.segments.count
                            Text("Continued \(count - 1) \(count - 1 == 1 ? "time" : "times")")
                                .font(.system(size: 9, weight: .bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(EchoPalette.accent.opacity(0.12))
                                .cornerRadius(5)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 5)
                                        .stroke(EchoPalette.accent.opacity(0.25), lineWidth: 0.5)
                                )
                                .foregroundStyle(EchoPalette.accent)
                        }
                    }

                    Text("Last Active: \(summary.latestActiveLabel)  ·  Total Time: \(summary.totalDuration.shortLabel)  ·  \(summary.segments.count) \(summary.segments.count == 1 ? "Session" : "Sessions")")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                // App Icon Overlapping Stack and actions
                HStack(spacing: 12) {
                    let bundleIds = summary.bundleIds
                    if !bundleIds.isEmpty {
                        HStack(spacing: -6) {
                            ForEach(Array(bundleIds.prefix(5).enumerated()), id: \.element) { index, bundleId in
                                AppIconView(bundleId: bundleId, size: 18)
                                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                                            .stroke(Color.black.opacity(0.2), lineWidth: 0.5)
                                    )
                                    .shadow(color: .black.opacity(0.1), radius: 1, y: 1)
                                    .zIndex(Double(bundleIds.count - index))
                            }
                            if bundleIds.count > 5 {
                                Text("+\(bundleIds.count - 5)")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1.5)
                                    .background(Color.primary.opacity(0.06), in: Capsule())
                                    .padding(.leading, 4)
                            }
                        }
                    }

                    // 3-dot Menu Button (discoverable card actions)
                    Menu {
                        if !isSelectMode && !isSessionSelectMode {
                            Button("Rename workflow") {
                                appStore.renameThreadDraft = WorkflowThreadRenameDraft(
                                    threadId: summary.id,
                                    title: summary.displayTitle,
                                    tags: summary.thread.tags
                                )
                            }
                            
                            if summary.thread.statusRaw == "archived" {
                                Button("Unarchive") {
                                    Task { await sessionControl.unarchiveWorkflowThread(id: summary.id) }
                                }
                            } else {
                                Button("Archive") {
                                    Task { await sessionControl.archiveWorkflowThread(id: summary.id) }
                                }
                            }
                            
                            Divider()
                            
                            Button("Delete Sessions") {
                                onStartSessionSelect()
                            }
                            
                            Button("Delete workflow", role: .destructive) {
                                onDeleteWorkflow()
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.secondary.opacity(0.7))
                            .frame(width: 24, height: 24)
                            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
                    }
                    .menuStyle(.button)
                    .buttonStyle(.plain)
                    .disabled(isSessionSelectMode)
                    .onTapGesture {} // Prevent card toggle on menu click

                    // Expand Chevron
                    Image(systemName: logsExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.secondary.opacity(0.7))
                        .frame(width: 24, height: 24)
                }
            }
            .padding(EchoDesign.cardPadding)
            .contentShape(Rectangle())
            .onTapGesture {
                onToggleLogs()
            }

            // Expanded Session History
            if logsExpanded && !summary.segments.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    Divider().opacity(0.35)
                        .padding(.horizontal, EchoDesign.cardPadding)

                    HStack(spacing: 6) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Session History")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, EchoDesign.cardPadding)
                    .padding(.top, 12)
                    .padding(.bottom, 6)

                    let chronologicalSegments = summary.segments.sorted(by: { $0.startedAt < $1.startedAt })
                    let hasActive = chronologicalSegments.contains(where: { $0.isActive })
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(chronologicalSegments.enumerated()), id: \.element.id) { index, segment in
                            let isLastItem = index == chronologicalSegments.count - 1
                            let isLatest = isLastItem && !segment.isActive
                            
                            HStack(alignment: .top, spacing: 0) {
                                TimelineNodeView(
                                    isFirst: index == 0,
                                    isLast: isLastItem,
                                    isActive: segment.isActive,
                                    isLatest: isLatest,
                                    isPathActive: hasActive,
                                    isPathLatest: !hasActive,
                                    isHovered: hoveredSessionId == segment.id
                                )
                                .padding(.leading, EchoDesign.cardPadding)
                                
                                SessionHistoryRow(
                                    index: index + 1,
                                    segment: segment,
                                    showCheckbox: isSessionSelectMode && sessionSelectThreadId == summary.id,
                                    isSelected: selectedSessionIds.contains(segment.id),
                                    isLatest: isLastItem, // Highlight the latest chronological session text
                                    isHoveredFromParent: hoveredSessionId == segment.id,
                                    onHoverChange: { isHovering in
                                        if isHovering {
                                            hoveredSessionId = segment.id
                                        } else if hoveredSessionId == segment.id {
                                            hoveredSessionId = nil
                                        }
                                    },
                                    onTap: {
                                        if isSessionSelectMode && sessionSelectThreadId == summary.id {
                                            onToggleSessionSelect(segment.id)
                                        } else {
                                            onSelectSegment(segment.id)
                                        }
                                    },
                                    onDelete: { onDeleteSession(segment, index + 1) },
                                    onRename: {
                                        appStore.renameSessionDraft = SessionRenameDraft(
                                            sessionId: segment.id,
                                            title: segment.title ?? "",
                                            tags: segment.tags
                                        )
                                    }
                                )
                                .padding(.trailing, EchoDesign.cardPadding)
                                .padding(.vertical, 4)
                            }
                        }
                    }
                }
                .padding(.bottom, 10)
                .compositingGroup()
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .move(edge: .top)).combined(with: .scale(scale: 0.98)),
                    removal: .opacity.combined(with: .scale(scale: 0.98))
                ))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: EchoDesign.cardCornerRadius, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: EchoDesign.cardCornerRadius, style: .continuous)
                .strokeBorder(
                    EchoPalette.stroke,
                    lineWidth: 0.5
                )
                .opacity(hovering ? 0 : 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: EchoDesign.cardCornerRadius, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [EchoPalette.indigo.opacity(0.6), Color.purple.opacity(0.3)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.5
                )
                .opacity(hovering ? 1 : 0)
        )
        .shadow(color: .black.opacity(hovering ? 0.08 : 0.03), radius: hovering ? 12 : 5, y: 2)
        .scaleEffect(hovering ? 1.004 : 1)
        .animation(.easeOut(duration: 0.2), value: hovering)
        .onHover { hovering in
            self.hovering = hovering
        }
        .clipShape(RoundedRectangle(cornerRadius: EchoDesign.cardCornerRadius, style: .continuous))
        .opacity(isVisible ? 1.0 : 0.0)
        .offset(y: isVisible ? 0 : 8)
        .onAppear {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                isVisible = true
            }
        }
    }
}

private struct SessionHistoryRow: View {
    let index: Int
    let segment: Session
    let showCheckbox: Bool
    let isSelected: Bool
    var isLatest: Bool = false
    let isHoveredFromParent: Bool
    let onHoverChange: (Bool) -> Void
    let onTap: () -> Void
    let onDelete: () -> Void
    let onRename: () -> Void
    
    @ObservedObject private var settings = EchoSettings.shared
    @State private var hovering = false
    
    var body: some View {
        Button(action: onTap) {
            let appItems = segment.restorePlan?.items.filter { $0.kind == .application } ?? []
            let bundleIds: [String] = {
                var ids: [String] = []
                for item in appItems {
                    if let bid = item.bundleId, !ids.contains(bid) {
                        ids.append(bid)
                    }
                }
                return ids
            }()
            
            HStack(spacing: 12) {
                if showCheckbox {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(isSelected ? EchoPalette.accent : Color.primary.opacity(0.35))
                        .frame(width: 18, height: 18)
                }
                
                VStack(alignment: .leading, spacing: 3) {
                    let displayName = segment.title?.isEmpty == false ? segment.title! : "Session \(index)"
                    HStack(spacing: 6) {
                        Text(displayName)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(segment.isActive ? EchoPalette.live : (isHoveredFromParent ? EchoPalette.accent : .primary))
                        
                        if segment.isActive {
                            Text("LIVE")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(Color.white)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1.5)
                                .background(EchoPalette.live, in: RoundedRectangle(cornerRadius: 3))
                        }
                    }
                    
                    Text(formatSessionTimeRange(segment))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                if !bundleIds.isEmpty {
                    HStack(spacing: -4) {
                        ForEach(Array(bundleIds.prefix(3).enumerated()), id: \.element) { idx, bundleId in
                            AppIconView(bundleId: bundleId, size: 14)
                                .clipShape(Circle())
                                .overlay(Circle().stroke(Color.primary.opacity(0.12), lineWidth: 0.5))
                                .shadow(color: .black.opacity(0.08), radius: 0.5, y: 0.5)
                                .zIndex(Double(bundleIds.count - idx))
                        }
                        
                        if bundleIds.count > 3 {
                            Text("+\(bundleIds.count - 3)")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(.secondary)
                                .padding(.leading, 2)
                        }
                    }
                    .padding(.trailing, 4)
                } else if segment.appCount > 0 {
                    HStack(spacing: 3) {
                        Image(systemName: "square.grid.2x2")
                            .font(.system(size: 8))
                        Text("\(segment.appCount) apps")
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.primary.opacity(0.04), in: Capsule())
                }
                
                HStack(spacing: 4) {
                    Image(systemName: "hourglass")
                        .font(.system(size: 8))
                    Text(segment.duration.shortLabel)
                        .font(.system(size: 9, weight: .bold))
                }
                .foregroundStyle(segment.isActive ? EchoPalette.live : EchoPalette.accent)
                .padding(.horizontal, 6)
                .padding(.vertical, 3.5)
                .background((segment.isActive ? EchoPalette.live : EchoPalette.accent).opacity(0.08), in: Capsule())
            }
            .padding(.vertical, 9)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(hovering ? Color.primary.opacity(0.06) : Color.primary.opacity(0.02))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(hovering ? Color.primary.opacity(0.15) : Color.primary.opacity(0.05), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(hovering ? 0.04 : 0.01), radius: 1.5, y: 1)
            .scaleEffect(hovering ? 1.008 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.75), value: hovering)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            self.hovering = hovering
            onHoverChange(hovering)
        }
        .contextMenu {
            if !showCheckbox {
                Button("Rename Session") {
                    onRename()
                }
                Button("Delete Session", role: .destructive) {
                    onDelete()
                }
            }
        }
    }
    
    private func formatSessionTimeRange(_ segment: Session) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMM d" // e.g., Jun 6
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "h:mm a" // e.g., 4:17 PM
        
        let dateStr = dateFormatter.string(from: segment.startedAt)
        let startStr = timeFormatter.string(from: segment.startedAt)
        
        if let endedAt = segment.endedAt {
            let endStr = timeFormatter.string(from: endedAt)
            return "\(dateStr) • \(startStr) - \(endStr)"
        } else {
            return "\(dateStr) • \(startStr) - Active"
        }
    }
}

// MARK: - Premium UI Helpers

fileprivate extension WorkflowThreadSummary {
    var bundleIds: [String] {
        let appItems = segments.flatMap { $0.restorePlan?.items ?? [] }.filter { $0.kind == .application }
        var unique = [String]()
        for item in appItems {
            if let bid = item.bundleId, !unique.contains(bid) {
                unique.append(bid)
            }
        }
        return unique
    }
}

fileprivate struct ClusterIconView: View {
    let cluster: WorkflowCluster
    
    var colors: [Color] {
        switch cluster {
        case .coding:
            return [Color(red: 0.25, green: 0.35, blue: 0.95), Color(red: 0.15, green: 0.55, blue: 0.90)]
        case .research:
            return [Color(red: 0.12, green: 0.63, blue: 0.63), Color(red: 0.08, green: 0.55, blue: 0.40)]
        case .writing:
            return [Color(red: 0.95, green: 0.60, blue: 0.10), Color(red: 0.90, green: 0.45, blue: 0.08)]
        case .design:
            return [Color(red: 0.95, green: 0.25, blue: 0.55), Color(red: 0.90, green: 0.20, blue: 0.35)]
        case .communication:
            return [Color(red: 0.60, green: 0.30, blue: 0.95), Color(red: 0.45, green: 0.20, blue: 0.85)]
        case .mixed:
            return [Color(red: 0.45, green: 0.50, blue: 0.60), Color(red: 0.30, green: 0.35, blue: 0.45)]
        }
    }
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                .shadow(color: colors[0].opacity(0.25), radius: 4, y: 2)
            
            Image(systemName: cluster.icon)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
        }
        .frame(width: 36, height: 36)
    }
}

fileprivate struct TimelineNodeView: View {
    let isFirst: Bool
    let isLast: Bool
    let isActive: Bool
    let isLatest: Bool
    let isPathActive: Bool
    let isPathLatest: Bool
    var isHovered: Bool = false
    
    @ObservedObject private var settings = EchoSettings.shared
    @State private var animatePulse = false
    
    var body: some View {
        ZStack(alignment: .top) {
            // The vertical timeline line
            VStack(spacing: 0) {
                // Line from top to circle center (aligned at y = 25)
                if isFirst {
                    Color.clear
                        .frame(width: 2, height: 25)
                } else {
                    Rectangle()
                        .fill(isHovered ? EchoPalette.accent.opacity(0.85) : (isPathActive ? EchoPalette.live.opacity(0.35) : (isPathLatest ? EchoPalette.accent.opacity(0.65) : Color.primary.opacity(0.10))))
                        .frame(width: 2, height: 25)
                }
                
                // Line from circle center to bottom of row
                if isLast {
                    Color.clear
                        .frame(width: 2)
                } else {
                    Rectangle()
                        .fill(isHovered ? EchoPalette.accent.opacity(0.85) : (isPathActive ? EchoPalette.live.opacity(0.35) : (isPathLatest ? EchoPalette.accent.opacity(0.65) : Color.primary.opacity(0.10))))
                        .frame(width: 2)
                }
            }
            
            // The Node circle centered at y = 25 (since the outer circle frame is 14x14, top padding is 18)
            ZStack {
                if isActive {
                    // Active (Live) Concentric Glow Node
                    Circle()
                        .strokeBorder(EchoPalette.live.opacity(0.3), lineWidth: 1.5)
                        .frame(width: 14, height: 14)
                    
                    Circle()
                        .fill(EchoPalette.live)
                        .frame(width: 6, height: 6)
                        .scaleEffect(animatePulse ? 1.2 : 0.8)
                        .shadow(color: EchoPalette.live.opacity(0.7), radius: animatePulse ? 4.5 : 2.0)
                } else if isLatest {
                    // Latest saved session (dynamic Accent Vibe) Concentric Glow Node
                    ZStack {
                        // Outer pulsating radar wave
                        Circle()
                            .stroke(EchoPalette.accent.opacity(animatePulse ? 0 : (isHovered ? 0.8 : 0.6)), lineWidth: isHovered ? 2.0 : 1.5)
                            .frame(width: 14, height: 14)
                            .scaleEffect(animatePulse ? (isHovered ? 1.9 : 1.7) : 1.0)
                        
                        Circle()
                            .strokeBorder(EchoPalette.accent.opacity(isHovered ? 0.55 : 0.35), lineWidth: 1.5)
                            .frame(width: 14, height: 14)
                        
                        Circle()
                            .fill(EchoPalette.accent)
                            .frame(width: 6, height: 6)
                            .shadow(color: EchoPalette.accent.opacity(isHovered ? 0.95 : 0.8), radius: animatePulse ? (isHovered ? 6.0 : 4.0) : (isHovered ? 3.0 : 1.5))
                    }
                } else if isHovered {
                    // Hovered Accent Concentric Node
                    Circle()
                        .strokeBorder(EchoPalette.accent.opacity(0.35), lineWidth: 1.5)
                        .frame(width: 14, height: 14)
                    
                    Circle()
                        .fill(EchoPalette.accent)
                        .frame(width: 6, height: 6)
                        .shadow(color: EchoPalette.accent.opacity(0.6), radius: 2.5)
                } else {
                    // Clean Modern Concentric Default Node
                    Circle()
                        .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1.2)
                        .frame(width: 14, height: 14)
                    
                    Circle()
                        .fill(Color.primary.opacity(0.35))
                        .frame(width: 5, height: 5)
                }
            }
            .padding(.top, 18)
        }
        .frame(width: 20)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                animatePulse = true
            }
        }
    }
}

fileprivate struct MetricBadge: View {
    let label: String
    let icon: String
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 8))
            Text(label)
                .font(.system(size: 9, weight: .bold))
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 3.5)
        .background(
            Capsule()
                .fill(Color.primary.opacity(0.04))
        )
        .overlay(
            Capsule()
                .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
        )
    }
}

fileprivate struct InlineMetricBadge: View {
    let label: String
    let icon: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 8))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3.5)
        .background(
            Capsule()
                .fill(Color.primary.opacity(0.04))
        )
        .overlay(
            Capsule()
                .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
        )
    }
}

fileprivate struct FilterPill: View {
    let label: String
    let isSelected: Bool
    var clusterColor: Color = EchoPalette.accent
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if isSelected && label != "All" {
                    Circle()
                        .fill(clusterColor)
                        .frame(width: 5, height: 5)
                }
                Text(label)
                    .font(.system(size: 11, weight: .bold))
            }
            .foregroundStyle(isSelected ? Color.white : Color.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(isSelected ? clusterColor.opacity(0.85) : Color.primary.opacity(0.04))
            )
            .overlay(
                Capsule()
                    .stroke(isSelected ? clusterColor.opacity(0.3) : Color.primary.opacity(0.06), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }
}
