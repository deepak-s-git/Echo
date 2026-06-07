import SwiftUI

struct ContinuityPanel: View {
    @EnvironmentObject var continuityStore: ContinuityStore
    @EnvironmentObject var activityStore: ActivityStore
    @EnvironmentObject var appStore: AppStore
    @EnvironmentObject var sessionStore: SessionStore
    @EnvironmentObject var sessionControl: SessionControlStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.uturn.backward.circle")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(EchoPalette.indigoSoft)
                Text("Continuity")
                    .font(.system(size: 12, weight: .semibold))
                    .textCase(.uppercase)
                    .tracking(0.4)
                    .foregroundStyle(.secondary)
            }

            if continuityStore.canResumeCurrent(active: sessionStore.activeSession) {
                continuityButton(
                    title: "Resume Current Session",
                    subtitle: activityStore.workflowIdentity,
                    icon: "play.circle"
                ) {
                    if let id = sessionStore.activeSession?.id {
                        appStore.openSessionDetail(id)
                    }
                }
            }

            if let thread = sessionStore.continueWorkflowThread, let session = sessionStore.continueSession {
                continuityButton(
                    title: "Continue Previous Workflow",
                    subtitle: "Workflow: \(thread.title ?? "Untitled") · Latest Session: \(session.title ?? "Untitled") · Ended \(relativeTimeString(for: session.endedAt ?? thread.lastActiveAt))",
                    icon: "clock.arrow.circlepath"
                ) {
                    Task { await sessionControl.continuePreviousSession(appStore: appStore) }
                }
            } else if let previous = continuityStore.previousSession {
                continuityButton(
                    title: "View last workflow",
                    subtitle: previous.title ?? "Recent memory",
                    icon: "clock.arrow.circlepath"
                ) {
                    appStore.openSessionDetail(previous.id)
                }
            }

            if !continuityStore.interruptedSessions.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Recently interrupted")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.tertiary)

                    ForEach(continuityStore.interruptedSessions.prefix(3)) { session in
                        Button {
                            appStore.openSessionDetail(session.id)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(session.title ?? "Interrupted session")
                                        .font(.system(size: 12, weight: .medium))
                                        .lineLimit(1)
                                    if let ended = session.endedAt {
                                        Text(ended, style: .relative)
                                            .font(.system(size: 10))
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.quaternary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(20)
        .echoCard()
        .task {
            await sessionStore.refreshContinuationThread()
            await continuityStore.refresh(
                activeSession: sessionStore.activeSession,
                recent: sessionStore.recentSessions
            )
        }
    }

    private func relativeTimeString(for date: Date) -> String {
        let diff = Date().timeIntervalSince(date)
        let minutes = Int(diff / 60)
        if minutes <= 0 {
            return "just now"
        } else if minutes == 1 {
            return "1 minute ago"
        } else {
            return "\(minutes) minutes ago"
        }
    }

    private func continuityButton(
        title: String,
        subtitle: String,
        icon: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(EchoPalette.indigoSoft)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.primary.opacity(0.03))
            )
        }
        .buttonStyle(.plain)
    }
}
