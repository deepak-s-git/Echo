import Foundation

/// Emitted by ActivityTracker before session assignment.
/// SessionEngine stamps the sessionId and produces ActivityEvent.
nonisolated struct RawActivityEvent: Sendable {
    let id: UUID
    let timestamp: Date
    let type: ActivityEvent.ActivityType
    let appBundleId: String
    let appName: String
    let windowTitle: String?
    let url: String?
    let profileName: String?
    let spaceIndex: Int?
    let isFullScreen: Bool?
    let duration: TimeInterval

    func stamped(sessionId: UUID) -> ActivityEvent {
        return ActivityEvent(
            id: id,
            sessionId: sessionId,
            timestamp: timestamp,
            type: type,
            appBundleId: appBundleId,
            appName: appName,
            windowTitle: windowTitle,
            url: url,
            profileName: profileName,
            spaceIndex: spaceIndex,
            isFullScreen: isFullScreen,
            duration: duration
        )
    }
}
