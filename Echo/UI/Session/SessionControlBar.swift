import SwiftUI

struct SessionControlBar: View {
    var compact: Bool
    @EnvironmentObject var sessionControl: SessionControlStore
    @EnvironmentObject var appStore: AppStore
    @EnvironmentObject var activityStore: ActivityStore
    @EnvironmentObject var sessionStore: SessionStore
    @ObservedObject private var settings = EchoSettings.shared

    private var hasSession: Bool {
        activityStore.isRecording
    }

    var body: some View {
        if hasSession {
            HStack(spacing: compact ? 6 : 8) {
                if activityStore.isSessionPaused {
                    controlButton("Resume", icon: "play.fill", role: .prominent) {
                        Task { await sessionControl.resumeSession() }
                    }
                } else {
                    controlButton("Pause", icon: "pause.fill", role: .normal) {
                        Task { await sessionControl.pauseSession() }
                    }
                }

                controlButton("End", icon: "stop.fill", role: .destructive) {
                    sessionControl.requestEndSession(
                        appStore: appStore,
                        activityStore: activityStore,
                        sessionStore: sessionStore
                    )
                }
            }
        }
    }

    private enum ButtonRole { case normal, prominent, destructive }

    private func controlButton(
        _ title: String,
        icon: String,
        role: ButtonRole,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                if !compact {
                    Text(title)
                        .font(.system(size: 11, weight: .semibold))
                }
            }
            .frame(maxWidth: compact ? nil : .infinity)
            .padding(.horizontal, compact ? 10 : 12)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: EchoDesign.pillRadius, style: .continuous)
                    .fill(background(for: role))
            )
            .foregroundStyle(foreground(for: role))
        }
        .buttonStyle(.plain)
    }

    private func background(for role: ButtonRole) -> Color {
        switch role {
        case .normal: return Color.primary.opacity(0.05)
        case .prominent: return EchoPalette.indigo.opacity(0.15)
        case .destructive: return Color.red.opacity(0.1)
        }
    }

    private func foreground(for role: ButtonRole) -> Color {
        switch role {
        case .normal: return .primary.opacity(0.8)
        case .prominent: return EchoPalette.indigoSoft
        case .destructive: return .red.opacity(0.85)
        }
    }
}
