import SwiftUI

struct HomeView: View {
    @EnvironmentObject var activityStore: ActivityStore
    @EnvironmentObject var sessionStore: SessionStore
    @ObservedObject private var settings = EchoSettings.shared

    var body: some View {
        ZStack {
            EchoDesign.ambientBackground
                .ignoresSafeArea()

            if !activityStore.isRecording {
                GeometryReader { geo in
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 0) {
                            Spacer()
                            HStack {
                                Spacer()
                                WorkflowIdleDashboard()
                                    .frame(maxWidth: 640)
                                Spacer()
                            }
                            Spacer()
                        }
                        .frame(minWidth: geo.size.width)
                        .frame(minHeight: geo.size.height)
                    }
                }
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {
                        SessionControlBar(compact: false)

                        HomeHeroSection(
                            focusHeadline: activityStore.focusHeadline,
                            workflowIdentity: activityStore.workflowIdentity,
                            threadTotal: activityStore.threadAccumulatedDuration,
                            blockDuration: activityStore.sessionDuration,
                            appCount: sessionStore.activeSession?.appCount ?? 0,
                            isActive: activityStore.isRecording,
                            isPaused: activityStore.isSessionPaused,
                            focusScore: activityStore.liveFocusScore,
                            focusLabel: activityStore.focusLabel
                        )

                        HomeCurrentAppSection(
                            appName: activityStore.currentAppName,
                            bundleId: activityStore.currentAppBundleId,
                            focusLabel: activityStore.focusLabel
                        )

                        MiniTimelineView(
                            segments: activityStore.timelineSegments,
                            focusIntensity: activityStore.focusIntensity,
                            isLive: true,
                            accentVibe: settings.accentVibe
                        )
                        .equatable()

                        ActivityFeedView(
                            events: activityStore.recentEvents,
                            accentVibe: settings.accentVibe
                        )
                        .equatable()
                    }
                    .padding(28)
                    .padding(.bottom, 12)
                }
            }
        }
    }
}
// MARK: - Hero

private struct HomeHeroSection: View {
    @ObservedObject private var settings = EchoSettings.shared
    let focusHeadline: String
    let workflowIdentity: String
    let threadTotal: TimeInterval
    let blockDuration: TimeInterval
    let appCount: Int
    let isActive: Bool
    let isPaused: Bool
    let focusScore: Double
    let focusLabel: String

    var body: some View {
        HStack(alignment: .top, spacing: 22) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    EchoLiveDot(isActive: isActive && !isPaused)
                    Text(isPaused ? "Paused" : "Recording")
                        .font(.system(size: 10, weight: .semibold))
                        .textCase(.uppercase)
                        .tracking(0.5)
                        .foregroundStyle(.tertiary)
                }

                Text(focusHeadline)
                    .font(.system(size: 32, weight: .semibold, design: .default))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .id(focusHeadline)
                    .animation(nil, value: focusHeadline)

                Text(workflowIdentity)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .animation(.easeOut(duration: 0.25), value: workflowIdentity)

                HStack(spacing: 14) {
                    Label(
                        "Workflow \(threadTotal.sessionDurationFormatted)",
                        systemImage: "clock.arrow.circlepath"
                    )
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.secondary)

                    Label(
                        "Block \(blockDuration.sessionDurationFormatted)",
                        systemImage: "clock"
                    )
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)

                    if appCount > 0 {
                        Label("\(appCount) apps", systemImage: "square.grid.2x2")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(EchoPalette.indigoSoft)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(EchoPalette.indigo.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(EchoPalette.indigo.opacity(0.2), lineWidth: 0.5))
                    }
                }
            }
        }
        .padding(24)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: EchoDesign.cardCornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                EchoDesign.heroWash
                    .clipShape(RoundedRectangle(cornerRadius: EchoDesign.cardCornerRadius, style: .continuous))
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: EchoDesign.cardCornerRadius, style: .continuous)
                .strokeBorder(EchoPalette.strokeBright, lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.06), radius: 16, y: 6)
    }
}

// MARK: - Current app

private struct HomeCurrentAppSection: View {
    @ObservedObject private var settings = EchoSettings.shared
    let appName: String?
    let bundleId: String?
    let focusLabel: String

    private var resolvedAppName: String {
        guard let bundleId else { return appName ?? "Waiting for activity" }
        return AppMetadataResolver.displayName(bundleId: bundleId, rawName: appName)
    }

    var body: some View {
        HStack(spacing: 16) {
            if let bundleId {
                AppIconView(bundleId: bundleId, size: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
                    .frame(width: 48, height: 48)
                    .overlay {
                        Image(systemName: "cursorarrow.click.2")
                            .foregroundStyle(.quaternary)
                    }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("In focus now")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(EchoPalette.indigoSoft)
                    .textCase(.uppercase)
                    .tracking(1.2)

                Text(resolvedAppName)
                    .font(.system(size: 18, weight: .semibold))
                    .id(resolvedAppName)

                Text(focusLabel)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.secondary)
            }

            Spacer()
        }
        .padding(18)
        .echoCard()
    }
}
