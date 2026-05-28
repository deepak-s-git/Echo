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
            try Session
                .filter(Column("id") == id.uuidString)
                .fetchOne(db)
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

    func deleteSession(id: UUID) async throws {
        let key = id.uuidString
        try await database.writeAsync { db in
            try db.execute(
                sql: "DELETE FROM activities WHERE sessionId = ?",
                arguments: [key]
            )
            try db.execute(
                sql: "DELETE FROM snapshots WHERE sessionId = ?",
                arguments: [key]
            )
            try db.execute(
                sql: "DELETE FROM sessions WHERE id = ?",
                arguments: [key]
            )
        }
        ActivityPersistenceLogger.log("Deleted session \(key) and related rows")
    }

    func updateMetadata(sessionId: UUID, title: String, tags: [String]) async throws {
        let tagsJSON: String?
        if tags.isEmpty {
            tagsJSON = nil
        } else if let data = try? JSONEncoder().encode(tags) {
            tagsJSON = String(data: data, encoding: .utf8)
        } else {
            tagsJSON = nil
        }
        try await database.writeAsync { db in
            try db.execute(
                sql: "UPDATE sessions SET title = ?, tagsJSON = ? WHERE id = ?",
                arguments: [title, tagsJSON, sessionId.uuidString]
            )
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

    // MARK: - Session detail (Phase 3)

    /// Loads everything needed for Session Detail, never assuming optional data exists.
    func loadSessionDetail(
        sessionId: UUID,
        fallbackSession: Session?,
        liveEvents: [ActivityEvent]
    ) async -> SessionDetailLoadOutcome {
        var diagnostics = SessionDetailDiagnostics()
        diagnostics.isActiveSession = fallbackSession?.isActive == true

        let session: Session
        do {
            if let persisted = try await fetch(id: sessionId) {
                session = persisted
                SessionDetailLogger.log("Session \(sessionId.uuidString) loaded from database")
            } else if let fallbackSession, fallbackSession.id == sessionId {
                session = fallbackSession
                diagnostics.record(.usedSessionStoreFallback, note: "Timeline cache supplied session row")
                SessionDetailLogger.log("Session \(sessionId.uuidString) using SessionStore fallback")
            } else {
                diagnostics.record(.sessionNotFoundInDatabase)
                SessionDetailLogger.log("Session \(sessionId.uuidString) not found in DB or cache")
                return .notFound(diagnostics)
            }
        } catch {
            diagnostics.record(.databaseReadFailed, note: error.localizedDescription)
            SessionDetailLogger.log("Session fetch failed", error: error)

            guard let fallbackSession, fallbackSession.id == sessionId else {
                return .notFound(diagnostics)
            }
            session = fallbackSession
            diagnostics.record(.usedSessionStoreFallback, note: "Used cache after DB error: \(error.localizedDescription)")
        }

        diagnostics.isFinalized = session.endedAt != nil
        if !diagnostics.isFinalized {
            diagnostics.record(.sessionNotFinalized)
        }

        let persistedEvents: [ActivityEvent]
        do {
            persistedEvents = try await fetchActivities(sessionId: sessionId)
            diagnostics.persistedEventCount = persistedEvents.count
            SessionDetailLogger.log(
                "Session \(sessionId.uuidString): \(persistedEvents.count) persisted events"
            )
        } catch {
            diagnostics.record(.databaseReadFailed, note: "activities: \(error.localizedDescription)")
            SessionDetailLogger.log("Activity fetch failed", error: error)
            persistedEvents = []
        }

        if persistedEvents.isEmpty {
            diagnostics.record(.noPersistedEvents)
        }

        diagnostics.liveEventCount = liveEvents.count
        let events = Self.mergeEvents(persisted: persistedEvents, live: liveEvents)
        diagnostics.mergedEventCount = events.count
        if !liveEvents.isEmpty, events.count > persistedEvents.count {
            diagnostics.record(.mergedLiveEvents, note: "Merged \(liveEvents.count) live events")
        }

        let snapshot = await loadSnapshot(sessionId: sessionId, diagnostics: &diagnostics)
        let restorePlan = resolveRestorePlan(session: session, events: events, diagnostics: &diagnostics)

        var memory = WorkflowMemoryBuilder.build(session: session, events: events)
        memory = Self.memory(memory, applying: restorePlan)

        if session.workflowCluster == nil || session.workflowCluster?.isEmpty == true {
            let cluster = WorkflowClusterDetector.detect(from: events)
            SessionDetailLogger.log("Session \(sessionId.uuidString): cluster inferred as \(cluster.rawValue)")
        }

        let payload = SessionDetailPayload(
            session: session,
            memory: memory,
            snapshot: snapshot,
            diagnostics: diagnostics
        )
        SessionDetailLogger.log(
            "Session \(sessionId.uuidString) ready — events=\(events.count) snapshot=\(snapshot != nil) issues=\(diagnostics.issues.count)"
        )
        return .loaded(payload)
    }

    /// Backward-compatible entry point.
    func loadWorkflowMemory(sessionId: UUID) async throws -> WorkflowMemory? {
        let outcome = await loadSessionDetail(
            sessionId: sessionId,
            fallbackSession: nil,
            liveEvents: []
        )
        switch outcome {
        case .loaded(let payload):
            return payload.memory
        case .notFound:
            return nil
        }
    }

    // MARK: - Activities

    @discardableResult
    func insertBatch(_ events: [ActivityEvent]) async throws -> Int {
        guard !events.isEmpty else { return 0 }
        let sessionIds = Set(events.map(\.sessionId.uuidString))
        // `writeAsync` already runs inside a single GRDB transaction — do not nest `inTransaction`.
        let count = try await database.writeAsync { db in
            for event in events {
                try event.insert(db, onConflict: .replace)
            }
            return events.count
        }
        ActivityPersistenceLogger.log(
            "Inserted \(count) events for session(s): \(sessionIds.joined(separator: ", "))"
        )
        return count
    }

    /// Ends every session still marked active in SQLite (crash recovery / duplicate guard).
    func closeAllActiveSessions(endedAt: Date = Date()) async throws -> Int {
        try await database.writeAsync { db in
            try db.execute(
                sql: "UPDATE sessions SET endedAt = ? WHERE endedAt IS NULL",
                arguments: [endedAt]
            )
            return db.changesCount
        }
    }

    func fetchActivities(sessionId: UUID) async throws -> [ActivityEvent] {
        let key = sessionId.uuidString
        let rows = try await database.readAsync { db in
            try ActivityEvent
                .filter(Column("sessionId") == key)
                .order(Column("timestamp").asc)
                .fetchAll(db)
        }
        ActivityPersistenceLogger.log("Fetched \(rows.count) activities for session \(key)")
        return rows
    }

    func activityCount(sessionId: UUID) async throws -> Int {
        let key = sessionId.uuidString
        return try await database.readAsync { db in
            try ActivityEvent
                .filter(Column("sessionId") == key)
                .fetchCount(db)
        }
    }

    // MARK: - Snapshots

    func insertSnapshot(_ snapshot: SessionSnapshot) async throws {
        try await database.writeAsync { db in try snapshot.insert(db) }
        SessionDetailLogger.log("Snapshot saved for session \(snapshot.sessionId.uuidString)")
    }

    func fetchLatestSnapshot(sessionId: UUID) async throws -> SessionSnapshot? {
        try await database.readAsync { db in
            try SessionSnapshot
                .filter(Column("sessionId") == sessionId.uuidString)
                .order(Column("capturedAt").desc)
                .fetchOne(db)
        }
    }

    // MARK: - Workflow threads

    func saveThread(_ thread: WorkflowThread) async throws {
        try await database.writeAsync { db in try thread.save(db) }
    }

    func fetchThread(id: UUID) async throws -> WorkflowThread? {
        try await database.readAsync { db in
            try WorkflowThread.filter(Column("id") == id.uuidString).fetchOne(db)
        }
    }

    func fetchSegments(threadId: UUID) async throws -> [Session] {
        try await database.readAsync { db in
            try Session
                .filter(Column("workflowThreadId") == threadId.uuidString)
                .order(Column("startedAt").desc)
                .fetchAll(db)
        }
    }

    func fetchWorkflowThreads(limit: Int = 40) async throws -> [WorkflowThreadSummary] {
        try await database.readAsync { db in
            let threads = try WorkflowThread
                .order(Column("lastActiveAt").desc)
                .limit(limit)
                .fetchAll(db)
            return try threads.map { thread in
                let segments = try Session
                    .filter(Column("workflowThreadId") == thread.id.uuidString)
                    .order(Column("startedAt").desc)
                    .fetchAll(db)
                return WorkflowThreadSummary(thread: thread, segments: segments)
            }
        }
    }

    func fetchMostRecentContinuableThread() async throws -> WorkflowThread? {
        try await database.readAsync { db in
            try WorkflowThread
                .filter(Column("statusRaw") != WorkflowThreadStatus.archived.rawValue)
                .order(Column("lastActiveAt").desc)
                .fetchOne(db)
        }
    }

    func fetchLastEndedSegment(threadId: UUID) async throws -> Session? {
        try await database.readAsync { db in
            try Session
                .filter(Column("workflowThreadId") == threadId.uuidString)
                .filter(Column("endedAt") != nil)
                .order(Column("endedAt").desc)
                .fetchOne(db)
        }
    }

    func deleteWorkflowThread(id: UUID) async throws {
        let key = id.uuidString
        try await database.writeAsync { db in
            let segmentIds = try String.fetchAll(
                db,
                sql: "SELECT id FROM sessions WHERE workflowThreadId = ?",
                arguments: [key]
            )
            for segmentId in segmentIds {
                try db.execute(sql: "DELETE FROM activities WHERE sessionId = ?", arguments: [segmentId])
                try db.execute(sql: "DELETE FROM snapshots WHERE sessionId = ?", arguments: [segmentId])
            }
            try db.execute(sql: "DELETE FROM sessions WHERE workflowThreadId = ?", arguments: [key])
            try db.execute(sql: "DELETE FROM workflow_threads WHERE id = ?", arguments: [key])
        }
        ActivityPersistenceLogger.log("Deleted workflow thread \(key) and segments")
    }

    func archiveWorkflowThread(id: UUID) async throws {
        try await database.writeAsync { db in
            try db.execute(
                sql: "UPDATE workflow_threads SET statusRaw = ? WHERE id = ?",
                arguments: [WorkflowThreadStatus.archived.rawValue, id.uuidString]
            )
        }
    }

    func updateThreadMetadata(threadId: UUID, title: String, tags: [String]) async throws {
        let tagsJSON: String?
        if tags.isEmpty {
            tagsJSON = nil
        } else if let data = try? JSONEncoder().encode(tags) {
            tagsJSON = String(data: data, encoding: .utf8)
        } else {
            tagsJSON = nil
        }
        try await database.writeAsync { db in
            try db.execute(
                sql: "UPDATE workflow_threads SET title = ?, tagsJSON = ? WHERE id = ?",
                arguments: [title, tagsJSON, threadId.uuidString]
            )
            try db.execute(
                sql: "UPDATE sessions SET title = ? WHERE workflowThreadId = ?",
                arguments: [title, threadId.uuidString]
            )
        }
    }

    func appendSegmentDurationToThread(threadId: UUID, segmentDuration: TimeInterval) async throws {
        try await database.writeAsync { db in
            try db.execute(
                sql: """
                UPDATE workflow_threads
                SET totalAccumulatedDuration = totalAccumulatedDuration + ?,
                    lastActiveAt = ?
                WHERE id = ?
                """,
                arguments: [segmentDuration, Date(), threadId.uuidString]
            )
        }
    }

    // MARK: - Private helpers

    private func loadSnapshot(
        sessionId: UUID,
        diagnostics: inout SessionDetailDiagnostics
    ) async -> SessionSnapshot? {
        do {
            let snapshot = try await fetchLatestSnapshot(sessionId: sessionId)
            if let snapshot {
                diagnostics.hasSnapshot = true
                SessionDetailLogger.log(
                    "Snapshot found for \(sessionId.uuidString) — \(snapshot.browserTabs.count) tabs"
                )
                return snapshot
            }
            diagnostics.record(.snapshotMissing)
            SessionDetailLogger.log("No snapshot for session \(sessionId.uuidString)")
            return nil
        } catch {
            diagnostics.record(.snapshotLoadFailed, note: error.localizedDescription)
            SessionDetailLogger.log("Snapshot load failed", error: error)
            return nil
        }
    }

    private func resolveRestorePlan(
        session: Session,
        events: [ActivityEvent],
        diagnostics: inout SessionDetailDiagnostics
    ) -> WorkflowRestorePlan {
        if let json = session.restorePlanJSON, !json.isEmpty {
            if let plan = session.restorePlan, !plan.items.isEmpty {
                diagnostics.hasPersistedRestorePlan = true
                SessionDetailLogger.log("Restore plan decoded (\(plan.items.count) items)")
                return plan
            }
            diagnostics.record(.restorePlanDecodeFailed, note: "Invalid restorePlanJSON")
            SessionDetailLogger.log("restorePlanJSON present but decode failed for \(session.id.uuidString)")
        } else {
            diagnostics.record(.restorePlanMissing)
        }

        let contexts = events.compactMap { event -> BrowserContextEntry? in
            guard event.type == .browserTab || event.url != nil else { return nil }
            let host = event.url?
                .replacingOccurrences(of: "https://", with: "")
                .replacingOccurrences(of: "http://", with: "")
                .components(separatedBy: "/").first ?? event.appName
            return BrowserContextEntry(
                id: event.id,
                domain: host,
                title: event.windowTitle ?? host,
                urlHost: host,
                browser: event.appName,
                capturedAt: event.timestamp
            )
        }
        let rebuilt = WorkflowRestorePlanBuilder.build(
            session: session,
            events: events,
            browserContexts: contexts
        )
        if !rebuilt.items.isEmpty {
            diagnostics.record(.restorePlanReconstructed, note: "\(rebuilt.items.count) items rebuilt")
        }
        return rebuilt
    }

    nonisolated static func mergeEvents(
        persisted: [ActivityEvent],
        live: [ActivityEvent]
    ) -> [ActivityEvent] {
        guard !live.isEmpty else { return persisted }
        var byId: [UUID: ActivityEvent] = [:]
        for event in persisted { byId[event.id] = event }
        for event in live { byId[event.id] = event }
        return byId.values.sorted { $0.timestamp < $1.timestamp }
    }

    private static func memory(
        _ memory: WorkflowMemory,
        applying restorePlan: WorkflowRestorePlan
    ) -> WorkflowMemory {
        WorkflowMemory(
            session: memory.session,
            events: memory.events,
            cluster: memory.cluster,
            phases: memory.phases,
            appTransitions: memory.appTransitions,
            browserContexts: memory.browserContexts,
            interruptions: memory.interruptions,
            continuityScore: memory.continuityScore,
            restorePlan: restorePlan
        )
    }

    // MARK: - Data Management

    /// Wipes all rows from every table. Used by Privacy > Clear All Data.
    func clearAll() async throws {
        try await database.writeAsync { db in
            // Order matters: delete child rows before parents
            try db.execute(sql: "DELETE FROM activities")
            try db.execute(sql: "DELETE FROM snapshots")
            try db.execute(sql: "DELETE FROM app_usage")
            try db.execute(sql: "DELETE FROM sessions")
            try db.execute(sql: "DELETE FROM workflow_threads")
        }
        ActivityPersistenceLogger.log("Cleared all data from database")
    }

    /// Resets any workflow_threads still flagged `active` back to `idle`.
    /// Called on launch after crash recovery to prevent stuck states.
    func resetActiveThreadStatuses() async throws {
        try await database.writeAsync { db in
            try db.execute(
                sql: "UPDATE workflow_threads SET statusRaw = 'idle' WHERE statusRaw = 'active'"
            )
        }
        ActivityPersistenceLogger.log("Reset active thread statuses on launch")
    }
}
