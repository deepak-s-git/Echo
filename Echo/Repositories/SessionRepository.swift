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

    private static func mergeEvents(
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
}
