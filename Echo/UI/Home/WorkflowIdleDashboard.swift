import SwiftUI

/// Shown on Home when not recording — explicit session start, no auto-capture.
struct WorkflowIdleDashboard: View {
    @EnvironmentObject var sessionStore: SessionStore
    @EnvironmentObject var appStore: AppStore
    @EnvironmentObject var sessionControl: SessionControlStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Workflow memory")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.4)

            Text("Browse your memories freely, or start recording when you're ready.")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 10) {
                if let thread = sessionStore.continueWorkflowThread {
                    actionButton(
                        title: "Continue Previous Workflow",
                        subtitle: continueSubtitle(for: thread),
                        icon: "arrow.uturn.backward",
                        prominent: true
                    ) {
                        Task { await sessionControl.continuePreviousSession() }
                    }
                }

                actionButton(
                    title: "Start New Workflow",
                    subtitle: "Begin a fresh workflow memory",
                    icon: "record.circle",
                    prominent: sessionStore.continueWorkflowThread == nil
                ) {
                    Task { await sessionControl.startNewSession() }
                }

                actionButton(
                    title: "Browse Memories",
                    subtitle: "Open timeline without recording",
                    icon: "timeline.selection",
                    prominent: false
                ) {
                    appStore.selectTab(.timeline)
                }
            }
        }
        .padding(EchoDesign.cardPadding)
        .echoCard(material: .thinMaterial)
    }

    private func actionButton(
        title: String,
        subtitle: String,
        icon: String,
        prominent: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(prominent ? EchoPalette.indigoSoft : .secondary)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.quaternary)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: EchoDesign.pillRadius, style: .continuous)
                    .fill(prominent ? EchoPalette.indigo.opacity(0.08) : Color.primary.opacity(0.03))
            )
        }
        .buttonStyle(.plain)
    }

    private func continueSubtitle(for thread: WorkflowThread) -> String {
        let title = thread.title ?? "Untitled workflow"
        if thread.totalAccumulatedDuration > 0 {
            return "\(title) · \(thread.totalAccumulatedDuration.shortLabel) total"
        }
        return title
    }
}
