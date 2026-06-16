import SwiftUI

/// Timeline column: list OR session detail — never a trapping NavigationStack.
struct TimelineView: View {
    @EnvironmentObject var sessionStore: SessionStore
    @EnvironmentObject var activityStore: ActivityStore
    @EnvironmentObject var appStore: AppStore
    @EnvironmentObject var continuityStore: ContinuityStore
    @EnvironmentObject var sessionControl: SessionControlStore
    
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

    var body: some View {
        Group {
            if let sessionId = appStore.timelineDetailSessionId {
                SessionDetailView(sessionId: sessionId)
            } else {
                timelineList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            await continuityStore.refresh(
                activeSession: sessionStore.activeSession,
                recent: sessionStore.recentSessions
            )
        }
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
                        Text("Timeline")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(.primary)
                        
                        Spacer()
                        
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
                            Image(systemName: "ellipsis.circle")
                                .font(.system(size: 18))
                                .foregroundStyle(Color.secondary)
                        }
                        .menuStyle(.button)
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, EchoDesign.containerRadius)
                .padding(.top, EchoDesign.containerRadius)
                .padding(.bottom, 12)
                
                // Timeline Statistics metric header badges
                if !isSelectMode && !isSessionSelectMode && !sessionStore.workflowThreads.isEmpty {
                    let totalWorkflows = sessionStore.workflowThreads.count
                    let totalSessions = sessionStore.workflowThreads.map { $0.segments.count }.reduce(0, +)
                    let totalDuration = sessionStore.workflowThreads.map { $0.totalDuration }.reduce(0, +)
                    
                    HStack(spacing: 10) {
                        MetricBadge(label: "\(totalWorkflows) active \(totalWorkflows == 1 ? "workflow" : "workflows")", icon: "folder.fill")
                        MetricBadge(label: "\(totalSessions) \(totalSessions == 1 ? "session" : "sessions")", icon: "clock.arrow.circlepath")
                        if totalDuration > 0 {
                            MetricBadge(label: "Tracked \(totalDuration.sessionDurationFormatted)", icon: "hourglass")
                        }
                    }
                    .padding(.horizontal, EchoDesign.containerRadius)
                    .padding(.bottom, 16)
                }

                if sessionStore.isLoading {
                    Spacer()
                    HStack {
                        Spacer()
                        ProgressView("Loading memories…")
                        Spacer()
                    }
                    Spacer()
                } else if sessionStore.workflowThreads.isEmpty {
                    Spacer()
                    HStack {
                        Spacer()
                        emptyTimeline
                        Spacer()
                    }
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            if activityStore.isRecording && !isSelectMode {
                                SessionControlBar(compact: false)
                                    .padding(.bottom, 4)
                                liveBanner
                            }

                            ForEach(sessionStore.workflowThreads) { summary in
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
                                        isSessionSelectMode: isSessionSelectMode,
                                        sessionSelectThreadId: sessionSelectThreadId,
                                        selectedSessionIds: selectedSessionIds,
                                        onToggleLogs: {
                                            if expandedLogsThreadIds.contains(summary.id) {
                                                expandedLogsThreadIds.remove(summary.id)
                                            } else {
                                                expandedLogsThreadIds.insert(summary.id)
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
                                    .contextMenu {
                                        if !isSelectMode && !isSessionSelectMode {
                                            Button("Rename workflow…") {
                                                appStore.renameThreadDraft = WorkflowThreadRenameDraft(
                                                    threadId: summary.id,
                                                    title: summary.displayTitle,
                                                    tags: summary.thread.tags
                                                )
                                            }
                                            Button("Archive") {
                                                Task { await sessionControl.archiveWorkflowThread(id: summary.id) }
                                            }
                                            Button("Delete workflow…", role: .destructive) {
                                                activeAlert = .deleteSingle(summary)
                                            }
                                        }
                                    }
                                }
                                .contentShape(Rectangle())
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

    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header Row (Clickable to Expand/Collapse)
            HStack(alignment: .top, spacing: 14) {
                // Dynamic Icon based on category cluster of latest segment
                let cluster = summary.segments.first?.cluster ?? .mixed
                ClusterIconView(cluster: cluster)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(summary.displayTitle)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        
                        if summary.segments.count > 1 {
                            let count = summary.segments.count
                            Text("↺ Continued \(count - 1) \(count - 1 == 1 ? "time" : "times")")
                                .font(.system(size: 10, weight: .bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(EchoPalette.indigo.opacity(0.12), in: Capsule())
                                .foregroundStyle(EchoPalette.indigo)
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Last Active: \(summary.latestActiveLabel)")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                        
                        HStack(spacing: 8) {
                            Text("Total Time: \(summary.totalDuration.shortLabel)")
                            Text("·")
                            Text("\(summary.segments.count) \(summary.segments.count == 1 ? "Session" : "Sessions")")
                        }
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        
                        // App Icon Overlapping Stack
                        let bundleIds = summary.bundleIds
                        if !bundleIds.isEmpty {
                            HStack(spacing: -6) {
                                ForEach(Array(bundleIds.prefix(6).enumerated()), id: \.element) { index, bundleId in
                                    AppIconView(bundleId: bundleId, size: 18)
                                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                                .stroke(Color.black.opacity(0.2), lineWidth: 0.5)
                                        )
                                        .shadow(color: .black.opacity(0.1), radius: 1, y: 1)
                                        .zIndex(Double(bundleIds.count - index))
                                }
                                if bundleIds.count > 6 {
                                    Text("+\(bundleIds.count - 6)")
                                        .font(.system(size: 8, weight: .bold))
                                        .foregroundStyle(.secondary)
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1.5)
                                        .background(Color.primary.opacity(0.06), in: Capsule())
                                        .padding(.leading, 4)
                                }
                            }
                            .padding(.top, 4)
                        }
                    }
                }

                Spacer(minLength: 8)

                // 3-dot Menu Button (discoverable card actions)
                Menu {
                    Button("Delete Sessions…") {
                        onStartSessionSelect()
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary.opacity(0.7))
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .disabled(isSessionSelectMode)
                .padding(.top, 6)
                .onTapGesture {} // Prevent card toggle on menu click

                // Rotating Chevron
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary.opacity(0.7))
                    .rotationEffect(.degrees(logsExpanded ? 90 : 0))
                    .padding(.top, 12)
            }
            .padding(EchoDesign.cardPadding)
            .contentShape(Rectangle())
            .onTapGesture {
                onToggleLogs()
            }

            // Expanded Session History
            if logsExpanded && !summary.segments.isEmpty {
                Divider().opacity(0.35)
                    .padding(.horizontal, EchoDesign.cardPadding)

                VStack(alignment: .leading, spacing: 0) {
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
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(chronologicalSegments.enumerated()), id: \.element.id) { index, segment in
                            HStack(spacing: 0) {
                                TimelineNodeView(
                                    isFirst: index == 0,
                                    isLast: index == chronologicalSegments.count - 1,
                                    isActive: segment.isActive
                                )
                                .padding(.leading, EchoDesign.cardPadding)
                                
                                SessionHistoryRow(
                                    index: index + 1,
                                    segment: segment,
                                    showCheckbox: isSessionSelectMode && sessionSelectThreadId == summary.id,
                                    isSelected: selectedSessionIds.contains(segment.id),
                                    onTap: {
                                        if isSessionSelectMode && sessionSelectThreadId == summary.id {
                                            onToggleSessionSelect(segment.id)
                                        } else {
                                            onSelectSegment(segment.id)
                                        }
                                    },
                                    onDelete: { onDeleteSession(segment, index + 1) }
                                )
                            }
                        }
                    }
                }
                .padding(.bottom, 10)
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
    }
}

private struct SessionHistoryRow: View {
    let index: Int
    let segment: Session
    let showCheckbox: Bool
    let isSelected: Bool
    let onTap: () -> Void
    let onDelete: () -> Void
    
    @State private var hovering = false
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                if showCheckbox {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(isSelected ? Color.red : Color.primary.opacity(0.35))
                        .frame(width: 18, height: 18)
                }
                
                VStack(alignment: .leading, spacing: 3) {
                    let displayName = segment.title?.isEmpty == false ? segment.title! : "Session \(index)"
                    HStack(spacing: 6) {
                        Text(displayName)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(segment.isActive ? EchoPalette.live : .primary)
                        
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
                
                if segment.appCount > 0 {
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
                
                Text("Duration: \(segment.duration.shortLabel)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(hovering ? Color.primary.opacity(0.03) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .contextMenu {
            if !showCheckbox {
                Button("Delete Session…", role: .destructive) {
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
            Circle()
                .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                .shadow(color: colors[0].opacity(0.3), radius: 3, y: 1.5)
            
            Image(systemName: cluster.icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
        }
        .frame(width: 32, height: 32)
    }
}

fileprivate struct TimelineNodeView: View {
    let isFirst: Bool
    let isLast: Bool
    let isActive: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            if isFirst {
                Spacer()
                    .frame(height: 22)
            } else {
                Rectangle()
                    .fill(Color.primary.opacity(0.12))
                    .frame(width: 1.5)
            }
            
            Circle()
                .fill(isActive ? EchoPalette.live : Color.primary.opacity(0.25))
                .frame(width: 6, height: 6)
                .padding(.vertical, 4)
                .overlay(
                    Circle()
                        .stroke(isActive ? EchoPalette.live.opacity(0.35) : Color.clear, lineWidth: 3)
                )
            
            if isLast {
                Spacer()
                    .frame(height: 22)
            } else {
                Rectangle()
                    .fill(Color.primary.opacity(0.12))
                    .frame(width: 1.5)
            }
        }
        .frame(width: 16)
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
