import SwiftUI

struct TimelineView: View {
    @EnvironmentObject var sessionStore: SessionStore
    @EnvironmentObject var activityStore: ActivityStore
    @EnvironmentObject var appStore: AppStore
    @EnvironmentObject var continuityStore: ContinuityStore

    var body: some View {
        ZStack {
            EchoDesign.ambientBackground.ignoresSafeArea()

            if sessionStore.isLoading {
                ProgressView("Loading memories…")
            } else if sessionStore.recentSessions.isEmpty {
                emptyTimeline
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        if activityStore.isSessionActive {
                            liveBanner
                        }
                        ForEach(sessionStore.recentSessions) { session in
                            SessionHistoryCard(session: session) {
                                appStore.openSessionDetail(session.id)
                            }
                        }
                    }
                    .padding(24)
                }
            }
        }
        .task {
            await continuityStore.refresh(
                activeSession: sessionStore.activeSession,
                recent: sessionStore.recentSessions
            )
        }
    }

    private var liveBanner: some View {
        Button {
            if let id = activityStore.currentSession?.id {
                appStore.openSessionDetail(id)
            }
        } label: {
            HStack {
                EchoLiveDot(isActive: true)
                Text("Recording now")
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(activityStore.focusHeadline)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                    Text(activityStore.workflowIdentity)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            .padding(14)
            .echoCard(material: .thinMaterial)
        }
        .buttonStyle(.plain)
    }

    private var emptyTimeline: some View {
        VStack(spacing: 12) {
            Image(systemName: "timeline.selection")
                .font(.system(size: 36, weight: .thin))
                .foregroundStyle(EchoPalette.indigo.opacity(0.35))
            Text("Your workflow memories will gather here")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }
}

private struct SessionHistoryCard: View {
    let session: Session
    let onSelect: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Image(systemName: session.cluster.icon)
                            .font(.system(size: 10))
                            .foregroundStyle(EchoPalette.indigoSoft)
                        Text(session.title ?? "Untitled memory")
                            .font(.system(size: 15, weight: .semibold))
                            .lineLimit(1)
                    }

                    HStack(spacing: 12) {
                        Text(session.startedAt, style: .date)
                        Text(session.startedAt, style: .time)
                        if session.isActive {
                            Text("Active")
                                .font(.system(size: 10, weight: .bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(EchoPalette.live.opacity(0.15)))
                                .foregroundStyle(EchoPalette.live)
                        } else {
                            Text(session.duration.shortLabel)
                        }
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text("\(Int(session.focusScore * 100))%")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(EchoPalette.indigoSoft)
                    Text("continuity")
                        .font(.system(size: 10))
                        .foregroundStyle(.quaternary)
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.quaternary)
            }
            .padding(18)
            .echoCard()
            .background(hovering ? Color.primary.opacity(0.02) : .clear)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
