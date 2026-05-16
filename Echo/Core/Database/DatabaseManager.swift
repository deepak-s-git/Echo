import Foundation
import GRDB

/// Owns the SQLite connection pool and schema migrations.
/// All query logic lives in Repository types; this class is infrastructure only.
nonisolated final class DatabaseManager: Sendable {

    private let pool: DatabasePool

    // MARK: - Init

    init() throws {
        let url = try Self.databaseURL()
        let config = Configuration()
        // SQL profiling disabled — nested transaction noise and main-thread overhead during capture.
        pool = try DatabasePool(path: url.path, configuration: config)
        try runMigrations()
    }

    // MARK: - Async Interface

    func writeAsync<T: Sendable>(
        _ updates: @escaping @Sendable (Database) throws -> T
    ) async throws -> T {
        try await pool.write(updates)
    }

    func readAsync<T: Sendable>(
        _ value: @escaping @Sendable (Database) throws -> T
    ) async throws -> T {
        try await pool.read(value)
    }

    // MARK: - Migrations

    private func runMigrations() throws {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1_initial") { db in
            try db.create(table: Session.databaseTableName) { t in
                t.column("id", .text).primaryKey()
                t.column("title", .text)
                t.column("startedAt", .datetime).notNull().indexed()
                t.column("endedAt", .datetime).indexed()
                t.column("focusScore", .double).notNull().defaults(to: 0)
                t.column("appCount", .integer).notNull().defaults(to: 0)
                t.column("tabCount", .integer).notNull().defaults(to: 0)
                t.column("snapshotPath", .text)
                t.column("projectTag", .text)
                t.column("isFavorited", .boolean).notNull().defaults(to: false)
            }

            try db.create(table: ActivityEvent.databaseTableName) { t in
                t.column("id", .text).primaryKey()
                t.column("sessionId", .text).notNull().indexed()
                    .references(Session.databaseTableName, onDelete: .cascade)
                t.column("timestamp", .datetime).notNull().indexed()
                t.column("type", .text).notNull()
                t.column("appBundleId", .text).notNull()
                t.column("appName", .text).notNull()
                t.column("windowTitle", .text)
                t.column("url", .text)
                t.column("duration", .double).notNull().defaults(to: 0)
            }

            try db.create(table: AppUsage.databaseTableName) { t in
                t.column("id", .text).primaryKey()
                t.column("sessionId", .text).notNull().indexed()
                    .references(Session.databaseTableName, onDelete: .cascade)
                t.column("bundleId", .text).notNull()
                t.column("appName", .text).notNull()
                t.column("totalDuration", .double).notNull().defaults(to: 0)
                t.column("lastSeenAt", .datetime).notNull()
                t.column("launchCount", .integer).notNull().defaults(to: 1)
            }

            try db.create(table: SessionSnapshot.databaseTableName) { t in
                t.column("id", .text).primaryKey()
                t.column("sessionId", .text).notNull().indexed()
                    .references(Session.databaseTableName, onDelete: .cascade)
                t.column("capturedAt", .datetime).notNull()
                t.column("windowLayout", .blob).notNull()
                t.column("activeApps", .blob).notNull()
                t.column("browserTabs", .blob).notNull()
                t.column("thumbnailPath", .text)
            }
        }

        migrator.registerMigration("v2_workflow_memory") { db in
            try db.alter(table: Session.databaseTableName) { t in
                t.add(column: "workflowCluster", .text)
                t.add(column: "restorePlanJSON", .text)
            }
        }

        migrator.registerMigration("v3_session_control") { db in
            try db.alter(table: Session.databaseTableName) { t in
                t.add(column: "lifecycleStateRaw", .text).defaults(to: "active")
                t.add(column: "pausedAt", .datetime)
                t.add(column: "pausedDuration", .double).notNull().defaults(to: 0)
                t.add(column: "tagsJSON", .text)
            }
        }

        migrator.registerMigration("v4_workflow_threads") { db in
            try db.create(table: WorkflowThread.databaseTableName) { t in
                t.column("id", .text).primaryKey()
                t.column("title", .text)
                t.column("createdAt", .datetime).notNull().indexed()
                t.column("lastActiveAt", .datetime).notNull().indexed()
                t.column("statusRaw", .text).notNull().defaults(to: "idle")
                t.column("tagsJSON", .text)
                t.column("totalAccumulatedDuration", .double).notNull().defaults(to: 0)
            }

            try db.alter(table: Session.databaseTableName) { t in
                t.add(column: "workflowThreadId", .text).indexed()
            }

            let sessions = try Row.fetchAll(db, sql: "SELECT id, title, startedAt, endedAt, tagsJSON FROM sessions")
            for row in sessions {
                let sessionId: String = row["id"]
                let title: String? = row["title"]
                let startedAt: Date = row["startedAt"]
                let endedAt: Date? = row["endedAt"]
                let tagsJSON: String? = row["tagsJSON"]
                let duration: Double
                if let end = endedAt {
                    duration = end.timeIntervalSince(startedAt)
                } else {
                    duration = 0
                }
                try db.execute(
                    sql: """
                    INSERT INTO workflow_threads (id, title, createdAt, lastActiveAt, statusRaw, tagsJSON, totalAccumulatedDuration)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                    """,
                    arguments: [
                        sessionId,
                        title,
                        startedAt,
                        endedAt ?? startedAt,
                        endedAt == nil ? "active" : "idle",
                        tagsJSON,
                        max(duration, 0)
                    ]
                )
                try db.execute(
                    sql: "UPDATE sessions SET workflowThreadId = ? WHERE id = ?",
                    arguments: [sessionId, sessionId]
                )
            }
        }

        try migrator.migrate(pool)
    }

    // MARK: - URL

    private static func databaseURL() throws -> URL {
        guard let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first else {
            throw DatabaseError.cannotLocateAppSupport
        }
        let dir = appSupport.appendingPathComponent("Echo", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("echo.sqlite")
    }
}

// MARK: - DatabaseError

nonisolated enum DatabaseError: Error, LocalizedError {
    case cannotLocateAppSupport

    var errorDescription: String? {
        switch self {
        case .cannotLocateAppSupport:
            return "Cannot locate Application Support directory."
        }
    }
}
