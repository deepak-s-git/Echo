import SwiftUI

struct TimelineView: View {
    @EnvironmentObject var sessionStore: SessionStore
    @EnvironmentObject var activityStore: ActivityStore

    var body: some View {
        ZStack {
            EchoDesign.ambientBackground.ignoresSafeArea()

            if sessionStore.isLoading {
                ProgressView("Loading sessions…")
            } else if sessionStore.recentSessions.isEmpty {
                emptyTimeline
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        if activityStore.isSessionActive {
                            liveBanner
                        }
                        ForEach(sessionStore.recentSessions) { session in
                            SessionHistoryCard(session: session)
                        }
                    }
                    .padding(24)
                }
            }
        }
    }

    private var liveBanner: some View {
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

    private var emptyTimeline: some View {
        VStack(spacing: 12) {
            Image(systemName: "timeline.selection")
                .font(.system(size: 36, weight: .thin))
                .foregroundStyle(EchoPalette.indigo.opacity(0.35))
            Text("Your timeline will appear here")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }
}

private struct SessionHistoryCard: View {
    let session: Session
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(session.title ?? "Untitled session")
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)

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
                Text("focus")
                    .font(.system(size: 10))
                    .foregroundStyle(.quaternary)
            }
        }
        .padding(18)
        .echoCard()
        .background(hovering ? Color.primary.opacity(0.02) : .clear)
        .onHover { hovering = $0 }
    }
}
