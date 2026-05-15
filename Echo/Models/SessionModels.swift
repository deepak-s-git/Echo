import Foundation
import GRDB

// MARK: - Session

struct Session: Identifiable, Codable, FetchableRecord, PersistableRecord {
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
        isFavorited: Bool = false
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
    }

    var duration: TimeInterval {
        (endedAt ?? Date()).timeIntervalSince(startedAt)
    }

    var isActive: Bool { endedAt == nil }
}

// MARK: - Activity Event

struct ActivityEvent: Identifiable, Codable, FetchableRecord, PersistableRecord {
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

    enum ActivityType: String, Codable {
        case appFocus
        case appSwitch
        case browserTab
        case terminalCommand
        case fileAccess
        case idle
    }
}

// MARK: - App Usage

struct AppUsage: Identifiable, Codable, FetchableRecord, PersistableRecord {
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

struct SessionSnapshot: Identifiable, Codable, FetchableRecord, PersistableRecord {
    var id: UUID
    var sessionId: UUID
    var capturedAt: Date
    var windowLayout: Data
    var activeApps: [String]
    var browserTabs: [BrowserTab]
    var thumbnailPath: String?

    static let databaseTableName = "snapshots"
}

// MARK: - Browser Tab

struct BrowserTab: Codable, Identifiable {
    var id: UUID
    var url: String
    var title: String
    var faviconURL: String?
    var browser: Browser

    enum Browser: String, Codable {
        case safari, chrome, firefox, arc, brave, edge
    }
}

// MARK: - Window Layout

struct WindowLayout: Codable {
    struct WindowFrame: Codable {
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
