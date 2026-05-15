import Foundation
import GRDB

final class SessionRepository: Sendable {

    private let database: DatabaseManager

    init(database: DatabaseManager) {
        self.database = database
    }

    // MARK: - Sessions

    func save(_ session: Session) async throws {
        try await database.writeAsync { db in try session.save(db) }
    }

    func fetchRecent(limit: Int = EchoConfig.defaultSessionFetchLimit) async throws -> [Session] {
        try await database.readAsync { db in
            try Session
                .order(Column("startedAt").desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    func fetchActive() async throws -> [Session] {
        try await database.readAsync { db in
            try Session
                .filter(Column("endedAt") == nil)
                .order(Column("startedAt").desc)
                .fetchAll(db)
        }
    }

    func fetch(id: UUID) async throws -> Session? {
        try await database.readAsync { db in
            try Session.fetchOne(db, key: id.uuidString)
        }
    }

    // MARK: - Activities

    func insertBatch(_ events: [ActivityEvent]) async throws {
        guard !events.isEmpty else { return }
        try await database.writeAsync { db in
            for event in events { try event.insert(db) }
        }
    }

    func fetchActivities(sessionId: UUID) async throws -> [ActivityEvent] {
        try await database.readAsync { db in
            try ActivityEvent
                .filter(Column("sessionId") == sessionId.uuidString)
                .order(Column("timestamp").asc)
                .fetchAll(db)
        }
    }

    // MARK: - Snapshots

    func insertSnapshot(_ snapshot: SessionSnapshot) async throws {
        try await database.writeAsync { db in try snapshot.insert(db) }
    }

    func fetchLatestSnapshot(sessionId: UUID) async throws -> SessionSnapshot? {
        try await database.readAsync { db in
            try SessionSnapshot
                .filter(Column("sessionId") == sessionId.uuidString)
                .order(Column("capturedAt").desc)
                .fetchOne(db)
        }
    }
}
