import Foundation
import GRDB

// MARK: - Session

nonisolated struct Session: Identifiable, Codable, FetchableRecord, PersistableRecord, Sendable, Equatable {
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
    var lifecycleStateRaw: String
    var pausedAt: Date?
    var pausedDuration: TimeInterval
    var tagsJSON: String?
    /// Parent workflow memory; each session row is one continuation segment.
    var workflowThreadId: UUID?

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
        restorePlanJSON: String? = nil,
        lifecycleStateRaw: String = SessionLifecycleState.active.rawValue,
        pausedAt: Date? = nil,
        pausedDuration: TimeInterval = 0,
        tagsJSON: String? = nil,
        workflowThreadId: UUID? = nil
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
        self.lifecycleStateRaw = lifecycleStateRaw
        self.pausedAt = pausedAt
        self.pausedDuration = pausedDuration
        self.tagsJSON = tagsJSON
        self.workflowThreadId = workflowThreadId
    }

    var cluster: WorkflowCluster {
        WorkflowCluster(rawValue: workflowCluster ?? "") ?? .mixed
    }

    var restorePlan: WorkflowRestorePlan? {
        guard let json = restorePlanJSON else { return nil }
        return WorkflowRestorePlan.decode(fromJSON: json)
    }

    var duration: TimeInterval {
        let end = endedAt ?? Date()
        var total = end.timeIntervalSince(startedAt) - pausedDuration
        if let pausedAt, endedAt == nil {
            total -= Date().timeIntervalSince(pausedAt)
        }
        return max(total, 0)
    }

    var isActive: Bool { endedAt == nil && lifecycleStateRaw != SessionLifecycleState.archived.rawValue }

    var lifecycleState: SessionLifecycleState {
        SessionLifecycleState(rawValue: lifecycleStateRaw) ?? .active
    }

    var tags: [String] {
        guard let tagsJSON, let data = tagsJSON.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String].self, from: data)
        else { return [] }
        return decoded
    }

    func encode(to container: inout PersistenceContainer) throws {
        container["id"] = id.uuidString
        container["title"] = title
        container["startedAt"] = startedAt
        container["endedAt"] = endedAt
        container["focusScore"] = focusScore
        container["appCount"] = appCount
        container["tabCount"] = tabCount
        container["snapshotPath"] = snapshotPath
        container["projectTag"] = projectTag
        container["isFavorited"] = isFavorited
        container["workflowCluster"] = workflowCluster
        container["restorePlanJSON"] = restorePlanJSON
        container["lifecycleStateRaw"] = lifecycleStateRaw
        container["pausedAt"] = pausedAt
        container["pausedDuration"] = pausedDuration
        container["tagsJSON"] = tagsJSON
        container["workflowThreadId"] = workflowThreadId?.uuidString
    }

    init(row: Row) throws {
        id = UUID(uuidString: row["id"])!
        title = row["title"]
        startedAt = row["startedAt"]
        endedAt = row["endedAt"]
        focusScore = row["focusScore"]
        appCount = row["appCount"]
        tabCount = row["tabCount"]
        snapshotPath = row["snapshotPath"]
        projectTag = row["projectTag"]
        isFavorited = row["isFavorited"]
        workflowCluster = row["workflowCluster"]
        restorePlanJSON = row["restorePlanJSON"]
        lifecycleStateRaw = row["lifecycleStateRaw"] ?? SessionLifecycleState.active.rawValue
        pausedAt = row["pausedAt"]
        pausedDuration = row["pausedDuration"] ?? 0
        tagsJSON = row["tagsJSON"]
        if let threadKey: String = row["workflowThreadId"] {
            workflowThreadId = UUID(uuidString: threadKey)
        } else {
            workflowThreadId = nil
        }
    }
}

// MARK: - Workflow thread

nonisolated struct WorkflowThread: Identifiable, Codable, FetchableRecord, PersistableRecord, Sendable {
    var id: UUID
    var title: String?
    var createdAt: Date
    var lastActiveAt: Date
    var statusRaw: String
    var tagsJSON: String?
    var totalAccumulatedDuration: TimeInterval

    static let databaseTableName = "workflow_threads"

    init(
        id: UUID = UUID(),
        title: String? = nil,
        createdAt: Date = Date(),
        lastActiveAt: Date = Date(),
        statusRaw: String = WorkflowThreadStatus.idle.rawValue,
        tagsJSON: String? = nil,
        totalAccumulatedDuration: TimeInterval = 0
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.lastActiveAt = lastActiveAt
        self.statusRaw = statusRaw
        self.tagsJSON = tagsJSON
        self.totalAccumulatedDuration = totalAccumulatedDuration
    }

    var status: WorkflowThreadStatus {
        WorkflowThreadStatus(rawValue: statusRaw) ?? .idle
    }

    var tags: [String] {
        guard let tagsJSON, let data = tagsJSON.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String].self, from: data)
        else { return [] }
        return decoded
    }

    func encode(to container: inout PersistenceContainer) throws {
        container["id"] = id.uuidString
        container["title"] = title
        container["createdAt"] = createdAt
        container["lastActiveAt"] = lastActiveAt
        container["statusRaw"] = statusRaw
        container["tagsJSON"] = tagsJSON
        container["totalAccumulatedDuration"] = totalAccumulatedDuration
    }

    init(row: Row) throws {
        id = UUID(uuidString: row["id"])!
        title = row["title"]
        createdAt = row["createdAt"]
        lastActiveAt = row["lastActiveAt"]
        statusRaw = row["statusRaw"] ?? WorkflowThreadStatus.idle.rawValue
        tagsJSON = row["tagsJSON"]
        totalAccumulatedDuration = row["totalAccumulatedDuration"] ?? 0
    }
}

nonisolated enum WorkflowThreadStatus: String, Sendable, Codable {
    case active
    case paused
    case idle
    case archived
}

nonisolated struct WorkflowThreadSummary: Identifiable, Sendable {
    let thread: WorkflowThread
    let segments: [Session]

    var id: UUID { thread.id }

    var displayTitle: String {
        thread.title ?? segments.last?.title ?? "Untitled workflow"
    }

    var activeSegment: Session? {
        segments.first(where: \.isActive)
    }

    var endedSegments: [Session] {
        segments.filter { $0.endedAt != nil }
    }

    var totalDuration: TimeInterval {
        thread.totalAccumulatedDuration + (activeSegment?.duration ?? 0)
    }

    var latestSegmentDuration: TimeInterval {
        activeSegment?.duration ?? segments.first?.duration ?? 0
    }

    var appCount: Int {
        segments.map(\.appCount).max() ?? 0
    }

    var latestActiveLabel: String {
        let date = activeSegment?.startedAt ?? thread.lastActiveAt
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

nonisolated struct WorkflowSegment: Identifiable, Sendable {
    let session: Session

    var id: UUID { session.id }
    var startTime: Date { session.startedAt }
    var endTime: Date? { session.endedAt }
    var duration: TimeInterval { session.duration }

    var timeOfDayLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "ha"
        let start = formatter.string(from: session.startedAt).lowercased()
        if let end = session.endedAt {
            let endStr = formatter.string(from: end).lowercased()
            return "\(start) – \(endStr)"
        }
        return start
    }

    /// Compact log line: `May 17 • 1:03 AM • 3m`
    @MainActor
    var activityLogLabel: String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMM d"
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "h:mm a"
        let date = dateFormatter.string(from: session.startedAt)
        let time = timeFormatter.string(from: session.startedAt)
        let duration = session.isActive ? "active" : session.duration.shortLabel
        return "\(date) • \(time) • \(duration)"
    }
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
    var profileName: String?
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

    init(
        id: UUID,
        sessionId: UUID,
        timestamp: Date,
        type: ActivityType,
        appBundleId: String,
        appName: String,
        windowTitle: String? = nil,
        url: String? = nil,
        profileName: String? = nil,
        duration: TimeInterval = 0
    ) {
        self.id = id
        self.sessionId = sessionId
        self.timestamp = timestamp
        self.type = type
        self.appBundleId = appBundleId
        self.appName = appName
        self.windowTitle = windowTitle
        self.url = url
        self.profileName = profileName
        self.duration = duration
    }

    func encode(to container: inout PersistenceContainer) throws {
        container["id"] = id.uuidString
        container["sessionId"] = sessionId.uuidString
        container["timestamp"] = timestamp
        container["type"] = type.rawValue
        container["appBundleId"] = appBundleId
        container["appName"] = appName
        container["windowTitle"] = windowTitle
        container["url"] = url
        container["profileName"] = profileName
        container["duration"] = duration
    }

    init(row: Row) throws {
        id = UUID(uuidString: row["id"])!
        sessionId = UUID(uuidString: row["sessionId"])!
        timestamp = row["timestamp"]
        type = ActivityType(rawValue: row["type"]) ?? .appFocus
        appBundleId = row["appBundleId"]
        appName = row["appName"]
        windowTitle = row["windowTitle"]
        url = row["url"]
        profileName = row["profileName"]
        duration = row["duration"]
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
    var browserBundleId: String?
    var windowTitle: String?
    var profileName: String?
    var tabIndex: Int?
    var capturedAt: Date?

    nonisolated enum Browser: String, Codable, Sendable {
        case safari, chrome, firefox, arc, brave, edge
    }

    init(
        id: UUID = UUID(),
        url: String,
        title: String,
        faviconURL: String? = nil,
        browser: Browser,
        browserBundleId: String? = nil,
        windowTitle: String? = nil,
        profileName: String? = nil,
        tabIndex: Int? = nil,
        capturedAt: Date? = nil
    ) {
        self.id = id
        self.url = url
        self.title = title
        self.faviconURL = faviconURL
        self.browser = browser
        self.browserBundleId = browserBundleId
        self.windowTitle = windowTitle
        self.profileName = profileName
        self.tabIndex = tabIndex
        self.capturedAt = capturedAt
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

// MARK: - Session lifecycle

nonisolated enum SessionLifecycleState: String, Sendable, Codable {
    case active
    case paused
    case idle
    case recovered
    case ended
    case archived
}

/// App-wide recording mode (UI + engine).
nonisolated enum WorkflowRecordingState: String, Sendable {
    case idle
    case recording
    case paused
    case restoring
}

// MARK: - Global Configuration

/// App-wide constants. Deliberately nonisolated so any actor can read these values.
nonisolated enum EchoConfig {
    static let sessionIdleTimeout: TimeInterval = 300
    static let batchWriteInterval: TimeInterval = 5
    /// Flush to SQLite after this many queued events (in addition to the timer).
    static let batchWriteEventThreshold: Int = 4
    /// Session detail poll interval while viewing a live session.
    static let sessionDetailLiveRefreshInterval: TimeInterval = 8
    /// Minimum gap between silent detail reloads (notification + poll).
    static let sessionDetailReloadThrottle: TimeInterval = 1.5
    /// Max backoff after repeated flush failures (seconds).
    static let flushFailureMaxBackoff: TimeInterval = 30
    static let minSessionDuration: TimeInterval = 30
    static let maxLiveEvents: Int = 100
    static let defaultSessionFetchLimit: Int = 30

    /// Debounces timeline segment recomputation only (not live context).
    static let timelineRebuildInterval: TimeInterval = 0.12
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

// MARK: - Session detail loading

nonisolated enum SessionDetailLoadOutcome: Sendable {
    case loaded(SessionDetailPayload)
    case notFound(SessionDetailDiagnostics)
}

nonisolated struct SessionDetailPayload: Sendable {
    let session: Session
    let memory: WorkflowMemory
    let snapshot: SessionSnapshot?
    let diagnostics: SessionDetailDiagnostics
}

nonisolated struct SessionDetailDiagnostics: Sendable, Equatable {
    var issues: [Issue] = []
    var notes: [String] = []
    var persistedEventCount: Int = 0
    var liveEventCount: Int = 0
    var mergedEventCount: Int = 0
    var hasSnapshot: Bool = false
    var hasPersistedRestorePlan: Bool = false
    var isActiveSession: Bool = false
    var isFinalized: Bool = false

    var hasBlockingIssue: Bool {
        issues.contains { $0.isBlocking }
    }

    nonisolated enum Issue: String, Sendable, CaseIterable, Hashable {
        case repositoryUnavailable
        case sessionNotFoundInDatabase
        case usedSessionStoreFallback
        case noPersistedEvents
        case mergedLiveEvents
        case snapshotMissing
        case snapshotLoadFailed
        case restorePlanMissing
        case restorePlanDecodeFailed
        case restorePlanReconstructed
        case sessionNotFinalized
        case databaseReadFailed

        var isBlocking: Bool {
            switch self {
            case .repositoryUnavailable, .sessionNotFoundInDatabase, .databaseReadFailed:
                return true
            default:
                return false
            }
        }

        var userMessage: String {
            switch self {
            case .repositoryUnavailable:
                return "Database access is not ready yet."
            case .sessionNotFoundInDatabase:
                return "This session was not found in storage."
            case .usedSessionStoreFallback:
                return "Loaded session metadata from the timeline cache."
            case .noPersistedEvents:
                return "No activity events were persisted for this session yet."
            case .mergedLiveEvents:
                return "Included live activity from the current recording."
            case .snapshotMissing:
                return "No session snapshot was saved when this memory ended."
            case .snapshotLoadFailed:
                return "A snapshot exists but could not be read."
            case .restorePlanMissing:
                return "No restore plan was saved for this session."
            case .restorePlanDecodeFailed:
                return "The saved restore plan could not be decoded."
            case .restorePlanReconstructed:
                return "Restore plan was rebuilt from activity data."
            case .sessionNotFinalized:
                return "This session is still recording — memory is reconstructed from live data."
            case .databaseReadFailed:
                return "Reading session data from the database failed."
            }
        }
    }

    mutating func record(_ issue: Issue, note: String? = nil) {
        if !issues.contains(issue) { issues.append(issue) }
        if let note, !notes.contains(note) { notes.append(note) }
    }

    var summaryLine: String {
        if issues.isEmpty {
            return "Memory loaded from \(mergedEventCount) events."
        }
        return issues.map(\.userMessage).prefix(2).joined(separator: " ")
    }
}

nonisolated enum SessionDetailLogger {
    static func log(_ message: String) {
        print("[SessionDetail] \(message)")
    }

    static func log(_ message: String, error: Error) {
        print("[SessionDetail] \(message): \(error.localizedDescription)")
    }
}

// MARK: - Activity persistence logging

nonisolated enum ActivityPersistenceLogger {
    static func log(_ message: String) {
        print("[ActivityPersistence] \(message)")
    }

    static func log(_ message: String, error: Error) {
        print("[ActivityPersistence] \(message): \(error.localizedDescription)")
    }
}

// MARK: - Session Embedding Chunk

nonisolated struct SessionEmbedding: Identifiable, Codable, FetchableRecord, PersistableRecord, Sendable {
    var id: String
    var sessionId: String
    var chunkKind: String
    var vector: Data
    var document: String

    static let databaseTableName = "session_embeddings"

    init(id: String = UUID().uuidString, sessionId: String, chunkKind: String, vector: [Float], document: String) {
        self.id = id
        self.sessionId = sessionId
        self.chunkKind = chunkKind
        self.vector = vector.withUnsafeBufferPointer { Data(buffer: $0) }
        self.document = document
    }

    func floatVector() -> [Float] {
        let floatCount = vector.count / MemoryLayout<Float>.size
        guard floatCount > 0 else { return [] }
        return vector.withUnsafeBytes { buffer in
            let floatBuffer = buffer.bindMemory(to: Float.self)
            return Array(floatBuffer)
        }
    }
}

