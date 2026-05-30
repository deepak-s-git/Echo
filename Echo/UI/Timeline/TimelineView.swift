import SwiftUI

/// Timeline column: list OR session detail — never a trapping NavigationStack.
struct TimelineView: View {
    @EnvironmentObject var sessionStore: SessionStore
    @EnvironmentObject var activityStore: ActivityStore
    @EnvironmentObject var appStore: AppStore
    @EnvironmentObject var continuityStore: ContinuityStore
    @EnvironmentObject var sessionControl: SessionControlStore
    @State private var expandedLogsThreadIds: Set<UUID> = []

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

            if sessionStore.isLoading {
                ProgressView("Loading memories…")
            } else if sessionStore.workflowThreads.isEmpty {
                emptyTimeline
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        if activityStore.isRecording {
                            SessionControlBar(compact: false)
                                .padding(.bottom, 4)
                            liveBanner
                        }

                        ForEach(sessionStore.workflowThreads) { summary in
                            WorkflowThreadCard(
                                summary: summary,
                                logsExpanded: expandedLogsThreadIds.contains(summary.id),
                                onToggleLogs: {
                                    if expandedLogsThreadIds.contains(summary.id) {
                                        expandedLogsThreadIds.remove(summary.id)
                                    } else {
                                        expandedLogsThreadIds.insert(summary.id)
                                    }
                                },
                                onSelectSegment: { appStore.openSessionDetail($0) }
                            )
                            .contextMenu {
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
                                    Task {
                                        await sessionControl.deleteWorkflowThread(
                                            id: summary.id,
                                            appStore: appStore
                                        )
                                    }
                                }
                            }
                        }
                    }
                    .padding(EchoDesign.containerRadius)
                }
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
            HStack {
                EchoLiveDot(isActive: activityStore.recordingState == .recording)
                Text(activityStore.isSessionPaused ? "Paused" : "Recording")
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(activityStore.focusHeadline)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                    Text(activityStore.workflowIdentity)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(EchoDesign.cardPadding)
            .background(
                RoundedRectangle(cornerRadius: EchoDesign.cardCornerRadius, style: .continuous)
                    .fill(
                        activityStore.isSessionPaused
                            ? Color.orange.opacity(0.06)
                            : EchoPalette.live.opacity(0.06)
                    )
            )
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
    let onToggleLogs: () -> Void
    let onSelectSegment: (UUID) -> Void

    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                Image(systemName: summary.activeSegment != nil ? "circle.fill" : "circle")
                    .font(.system(size: 8))
                    .foregroundStyle(
                        summary.activeSegment != nil ? EchoPalette.live : Color.secondary.opacity(0.45)
                    )

                VStack(alignment: .leading, spacing: 5) {
                    Text(summary.displayTitle)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    Text("Total · \(summary.totalDuration.shortLabel)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.secondary)

                    HStack(spacing: 6) {
                        Text(summary.latestActiveLabel)
                            .foregroundStyle(.secondary.opacity(0.85))
                        if summary.appCount > 0 {
                            Text("·")
                                .foregroundStyle(.secondary)
                            Text("\(summary.appCount) apps")
                                .foregroundStyle(.secondary.opacity(0.85))
                        }
                    }
                    .font(.system(size: 11))
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.quaternary)
            }
            .padding(EchoDesign.cardPadding)

            if !summary.segments.isEmpty {
                Divider().opacity(0.35)
                    .padding(.horizontal, EchoDesign.cardPadding)

                Button(action: onToggleLogs) {
                    HStack(spacing: 6) {
                        Text("Activity logs")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Image(systemName: logsExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(summary.segments.count)")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(EchoPalette.indigoSoft)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(EchoPalette.indigo.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                    }
                    .padding(.horizontal, EchoDesign.cardPadding)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.plain)

                if logsExpanded {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(summary.segments) { segment in
                            let log = WorkflowSegment(session: segment)
                            Button {
                                onSelectSegment(segment.id)
                            } label: {
                                HStack {
                                    Text(log.activityLogLabel)
                                        .font(.system(size: 12))
                                        .foregroundStyle(.primary.opacity(0.85))
                                    Spacer()
                                }
                                .padding(.horizontal, EchoDesign.cardPadding)
                                .padding(.vertical, 8)
                            }
                            .buttonStyle(.plain)

                            if segment.id != summary.segments.last?.id {
                                Divider().opacity(0.2)
                                    .padding(.leading, EchoDesign.cardPadding)
                            }
                        }
                    }
                    .padding(.bottom, 10)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: EchoDesign.cardCornerRadius, style: .continuous)
                .fill(.thinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: EchoDesign.cardCornerRadius, style: .continuous)
                .strokeBorder(
                    EchoPalette.stroke.opacity(hovering ? 1.2 : 1),
                    lineWidth: 0.5
                )
        )
        .shadow(color: .black.opacity(hovering ? 0.06 : 0.03), radius: hovering ? 10 : 5, y: 2)
        .scaleEffect(hovering ? 1.005 : 1)
        .animation(.easeOut(duration: 0.15), value: hovering)
        .contentShape(Rectangle())
        .echoPointingCursor()
        .onHover { hovering in
            self.hovering = hovering
        }
        .onTapGesture {
            if summary.segments.count == 1, let only = summary.segments.first {
                onSelectSegment(only.id)
            } else {
                onToggleLogs()
            }
        }
    }
}
