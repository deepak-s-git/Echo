import Foundation
import GRDB

final class SessionRepository: Sendable {

    private let database: DatabaseManager
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

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

    func fetchInterrupted(limit: Int = 5) async throws -> [Session] {
        let cutoff = Date().addingTimeInterval(-EchoConfig.interruptedSessionWindow)
        return try await database.readAsync { db in
            try Session
                .filter(Column("endedAt") != nil)
                .filter(Column("endedAt") >= cutoff)
                .filter(Column("focusScore") >= 0.4)
                .order(Column("endedAt").desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    func saveRestorePlan(_ plan: WorkflowRestorePlan, for sessionId: UUID) async throws {
        let data = try encoder.encode(plan)
        guard let json = String(data: data, encoding: .utf8) else { return }
        try await database.writeAsync { db in
            try db.execute(
                sql: "UPDATE sessions SET restorePlanJSON = ? WHERE id = ?",
                arguments: [json, sessionId.uuidString]
            )
        }
    }

    // MARK: - Workflow memory

    func loadWorkflowMemory(sessionId: UUID) async throws -> WorkflowMemory? {
        guard let session = try await fetch(id: sessionId) else { return nil }
        let events = try await fetchActivities(sessionId: sessionId)
        return WorkflowMemoryBuilder.build(session: session, events: events)
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
