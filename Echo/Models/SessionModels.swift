import Foundation
import GRDB

// MARK: - Session

nonisolated struct Session: Identifiable, Codable, FetchableRecord, PersistableRecord, Sendable {
    var id: UUID
    var title: String?
    var startedAt: Date
    var endedAt: Date?
    var focusScore: Double
    var appCount: Int
    var tabCount: Int
    var snapshotPath: String?
    var projectTag: String?
    var isFavorited: Bool
    var workflowCluster: String?
    var restorePlanJSON: String?

    static let databaseTableName = "sessions"

    init(
        id: UUID = UUID(),
        title: String? = nil,
        startedAt: Date = Date(),
        endedAt: Date? = nil,
        focusScore: Double = 0,
        appCount: Int = 0,
        tabCount: Int = 0,
        snapshotPath: String? = nil,
        projectTag: String? = nil,
        isFavorited: Bool = false,
        workflowCluster: String? = nil,
        restorePlanJSON: String? = nil
    ) {
        self.id = id
        self.title = title
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.focusScore = focusScore
        self.appCount = appCount
        self.tabCount = tabCount
        self.snapshotPath = snapshotPath
        self.projectTag = projectTag
        self.isFavorited = isFavorited
        self.workflowCluster = workflowCluster
        self.restorePlanJSON = restorePlanJSON
    }

    var cluster: WorkflowCluster {
        WorkflowCluster(rawValue: workflowCluster ?? "") ?? .mixed
    }

    var restorePlan: WorkflowRestorePlan? {
        guard let json = restorePlanJSON else { return nil }
        return WorkflowRestorePlan.decode(fromJSON: json)
    }

    var duration: TimeInterval {
        (endedAt ?? Date()).timeIntervalSince(startedAt)
    }

    var isActive: Bool { endedAt == nil }
}

// MARK: - Activity Event

nonisolated struct ActivityEvent: Identifiable, Codable, FetchableRecord, PersistableRecord, Sendable {
    var id: UUID
    var sessionId: UUID
    var timestamp: Date
    var type: ActivityType
    var appBundleId: String
    var appName: String
    var windowTitle: String?
    var url: String?
    var duration: TimeInterval

    static let databaseTableName = "activities"

    nonisolated enum ActivityType: String, Codable, Sendable {
        case appFocus
        case appSwitch
        case browserTab
        case terminalCommand
        case fileAccess
        case idle
    }
}

// MARK: - App Usage

nonisolated struct AppUsage: Identifiable, Codable, FetchableRecord, PersistableRecord, Sendable {
    var id: UUID
    var sessionId: UUID
    var bundleId: String
    var appName: String
    var totalDuration: TimeInterval
    var lastSeenAt: Date
    var launchCount: Int

    static let databaseTableName = "app_usage"
}

// MARK: - Snapshot

nonisolated struct SessionSnapshot: Identifiable, FetchableRecord, PersistableRecord, Sendable {
    var id: UUID
    var sessionId: UUID
    var capturedAt: Date
    var windowLayout: Data
    var activeApps: [String]
    var browserTabs: [BrowserTab]
    var thumbnailPath: String?

    static let databaseTableName = "snapshots"

    private static let databaseJSONEncoder = JSONEncoder()
    private static let databaseJSONDecoder = JSONDecoder()

    init(
        id: UUID,
        sessionId: UUID,
        capturedAt: Date,
        windowLayout: Data,
        activeApps: [String],
        browserTabs: [BrowserTab],
        thumbnailPath: String? = nil
    ) {
        self.id = id
        self.sessionId = sessionId
        self.capturedAt = capturedAt
        self.windowLayout = windowLayout
        self.activeApps = activeApps
        self.browserTabs = browserTabs
        self.thumbnailPath = thumbnailPath
    }

    func encode(to container: inout PersistenceContainer) throws {
        container["id"] = id.uuidString
        container["sessionId"] = sessionId.uuidString
        container["capturedAt"] = capturedAt
        container["windowLayout"] = windowLayout
        container["activeApps"] = try Self.databaseJSONEncoder.encode(activeApps)
        container["browserTabs"] = try Self.databaseJSONEncoder.encode(browserTabs)
        container["thumbnailPath"] = thumbnailPath
    }

    init(row: Row) throws {
        id = UUID(uuidString: row["id"])!
        sessionId = UUID(uuidString: row["sessionId"])!
        capturedAt = row["capturedAt"]
        windowLayout = row["windowLayout"]
        activeApps = try Self.databaseJSONDecoder.decode([String].self, from: row["activeApps"])
        browserTabs = try Self.databaseJSONDecoder.decode([BrowserTab].self, from: row["browserTabs"])
        thumbnailPath = row["thumbnailPath"]
    }
}

// MARK: - Browser Tab

nonisolated struct BrowserTab: Codable, Identifiable, Sendable {
    var id: UUID
    var url: String
    var title: String
    var faviconURL: String?
    var browser: Browser

    nonisolated enum Browser: String, Codable, Sendable {
        case safari, chrome, firefox, arc, brave, edge
    }
}

// MARK: - Window Layout

nonisolated struct WindowLayout: Codable, Sendable {
    nonisolated struct WindowFrame: Codable, Sendable {
        var appName: String
        var bundleId: String
        var frame: CGRect
        var isMainWindow: Bool
        var spaceIndex: Int
    }

    var frames: [WindowFrame]
    var capturedAt: Date
    var screenCount: Int
}

// MARK: - Global Configuration

/// App-wide constants. Deliberately nonisolated so any actor can read these values.
nonisolated enum EchoConfig {
    static let sessionIdleTimeout: TimeInterval = 300
    static let batchWriteInterval: TimeInterval = 10
    static let minSessionDuration: TimeInterval = 30
    static let maxLiveEvents: Int = 100
    static let defaultSessionFetchLimit: Int = 30

    /// Debounces timeline segment recomputation only (not live context).
    static let timelineRebuildInterval: TimeInterval = 0.06
    /// Hybrid focus verification poll (catches Spaces swipes, Mission Control, etc.).
    static let trackerVerifyInterval: TimeInterval = 0.2
    /// Ignores duplicate transitions to the same app within this window.
    static let trackerMinTransitionInterval: TimeInterval = 0.08
    /// How often to AX-check window title for same-app space/window changes.
    static let trackerWindowRecheckInterval: TimeInterval = 0.5
    static let maxTimelineSegments: Int = 24
    static let maxFeedDisplayEvents: Int = 20
    static let titleUpdateEventThreshold: Int = 8
    /// Background session title DB write debounce after focus changes.
    static let titlePersistDebounceInterval: TimeInterval = 0.35
    /// Wait for focus to settle before recomputing stable workflow identity.
    static let workflowIdentitySettleInterval: TimeInterval = 2.0
    /// Minimum time between workflow identity changes (anti-flicker).
    static let workflowIdentityMinChangeInterval: TimeInterval = 4.0
    /// Gap between events treated as an interruption in session memory.
    static let interruptionThreshold: TimeInterval = 90
    /// Debounce browser context capture after focusing a browser.
    static let browserContextCaptureDelay: TimeInterval = 1.2
    /// Sessions ended within this window appear as "recently interrupted".
    static let interruptedSessionWindow: TimeInterval = 86_400
}
