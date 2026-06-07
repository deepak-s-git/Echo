import SwiftUI

/// Shown on Home when not recording — explicit session start, no auto-capture.
struct WorkflowIdleDashboard: View {
    @EnvironmentObject var sessionStore: SessionStore
    @EnvironmentObject var appStore: AppStore
    @EnvironmentObject var sessionControl: SessionControlStore
    @State private var showCreateSheet = false
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
