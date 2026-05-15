import Foundation

/// Global configuration constants for Echo.
/// Deliberately nonisolated so any actor can read these values.
nonisolated enum EchoConfig {
    static let sessionIdleTimeout: TimeInterval = 300
    static let batchWriteInterval: TimeInterval = 10
    static let minSessionDuration: TimeInterval = 30
    static let maxLiveEvents: Int = 100
    static let defaultSessionFetchLimit: Int = 30
}
