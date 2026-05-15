import Foundation
import GRDB

/// Owns the SQLite connection pool and schema migrations.
/// All query logic lives in Repository types; this class is infrastructure only.
final class DatabaseManager: Sendable {

    private let pool: DatabasePool

    // MARK: - Init

    init() throws {
        let url = try Self.databaseURL()
        var config = Configuration()
        #if DEBUG
        config.prepareDatabase { db in
            db.trace(options: .profile) { print("[DB] \($0)") }
        }
        #endif
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

enum DatabaseError: Error, LocalizedError {
    case cannotLocateAppSupport

    var errorDescription: String? {
        switch self {
        case .cannotLocateAppSupport:
            return "Cannot locate Application Support directory."
        }
    }
}
