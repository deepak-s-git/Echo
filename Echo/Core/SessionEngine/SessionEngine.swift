import Foundation

/// Consumes RawActivityEvents from ActivityTracker, manages session boundaries,
/// and coordinates persistence via SessionRepository.
actor SessionEngine {

    private let repository: SessionRepository
    private let activityStore: ActivityStore
    private let sessionStore: SessionStore
    private let idleMonitor: IdleTimeMonitor

    private var currentSession: Session?
    private var pendingEvents: [ActivityEvent] = []
    private var lastActivityTime: Date = Date()
    private var trackerTask: Task<Void, Never>?
    private var batchWriteTask: Task<Void, Never>?
    private var titlePersistTask: Task<Void, Never>?
    private var browserCaptureTask: Task<Void, Never>?
    private var eventsSinceTitlePersist = 0

    init(
        repository: SessionRepository,
        activityStore: ActivityStore,
        sessionStore: SessionStore,
        idleMonitor: IdleTimeMonitor
    ) {
        self.repository = repository
        self.activityStore = activityStore
        self.sessionStore = sessionStore
        self.idleMonitor = idleMonitor
    }

    func configure(tracker: ActivityTracker) async {
        guard let stream = await tracker.eventStream else {
            assertionFailure("ActivityTracker must be started before SessionEngine is configured.")
            return
        }
        await idleMonitor.setOnIdleStateChange { [weak self] isIdle in
            if isIdle {
                Task { await self?.endCurrentSession(reason: .idle) }
            }
        }
        beginConsuming(stream)
    }

    func start() async {
        startBatchWriter()
        await restoreOrBeginSession()
    }

    func endCurrentSession(reason: SessionEndReason) async {
        guard var session = currentSession else { return }
        let now = Date()

        session.endedAt = now
        session.appCount = uniqueAppCount()
        session.focusScore = computeFocusScore()
        if session.title == nil || session.title?.isEmpty == true {
            let events = pendingEvents
            let startedAt = session.startedAt
            session.title = await MainActor.run {
                SessionTitleGenerator.generate(from: events, startedAt: startedAt)
            }
        }

        currentSession = nil
        titlePersistTask?.cancel()
        browserCaptureTask?.cancel()
        await flushPendingEvents()

        do {
            let events = await allEventsForSession(session.id)
            session.appCount = Set(events.map(\.appBundleId)).count
            session.focusScore = focusScore(from: events)
            await finalizeSessionMemory(&session, events: events)
            try await repository.save(session)
            await activityStore.sessionDidEnd(session)
            await sessionStore.sessionDidEnd(session)
            ActivityPersistenceLogger.log(
                "Ended session \(session.id.uuidString) — \(events.count) events, reason=\(reason)"
            )
        } catch {
            ActivityPersistenceLogger.log("Session end failed", error: error)
        }
    }

    // MARK: - Stream Consumption

    private func beginConsuming(_ stream: AsyncStream<RawActivityEvent>) {
        trackerTask = Task { [weak self] in
            for await event in stream {
                guard !Task.isCancelled else { break }
                await self?.process(raw: event)
            }
        }
    }

    private func process(raw: RawActivityEvent) async {
        let now = Date()
        let elapsed = now.timeIntervalSince(lastActivityTime)

        if elapsed > EchoConfig.sessionIdleTimeout {
            await endCurrentSession(reason: .idle)
            await beginNewSession()
        }

        lastActivityTime = now
        await ensureActiveSession()

        guard let session = currentSession else { return }
        let sessionId = session.id

        let event = await MainActor.run {
            var stamped = raw.stamped(sessionId: sessionId)
            stamped.appName = AppMetadataResolver.displayName(
                bundleId: stamped.appBundleId,
                rawName: stamped.appName
            )
            return stamped
        }

        pendingEvents.append(event)
        ActivityPersistenceLogger.log(
            "Queued \(event.type.rawValue) for session \(sessionId.uuidString) — pending=\(pendingEvents.count)"
        )

        // Live UI first — never wait on DB or full title generation.
        await activityStore.applyLiveEvent(event)

        if pendingEvents.count >= EchoConfig.batchWriteEventThreshold {
            await flushPendingEvents()
        }

        schedulePersistedTitleRefresh(wasFocus: event.type == .appFocus)

        if event.type == .appFocus, BrowserContextService.isBrowser(event.appBundleId) {
            scheduleBrowserCapture(
                bundleId: event.appBundleId,
                appName: event.appName,
                sessionId: sessionId
            )
        }
    }

    // MARK: - Session Management

    private func restoreOrBeginSession() async {
        do {
            let actives = try await repository.fetchActive()
            for stale in actives.dropFirst() {
                await closeStaleSession(stale)
            }
            if let candidate = actives.first {
                let idleSeconds = await idleMonitor.currentIdleSeconds()
                let stored = try? await repository.fetchActivities(sessionId: candidate.id)
                let reference = stored?.last?.timestamp ?? candidate.startedAt
                let gap = Date().timeIntervalSince(reference)

                if idleSeconds < EchoConfig.sessionIdleTimeout,
                   gap < EchoConfig.sessionIdleTimeout {
                    await resumeSession(candidate)
                    return
                }

                await closeStaleSession(candidate)
            }
        } catch {
            print("[SessionEngine] Restore failed: \(error)")
        }

        await beginNewSession()
    }

    private func resumeSession(_ session: Session) async {
        currentSession = session
        lastActivityTime = session.startedAt

        do {
            let stored = try await repository.fetchActivities(sessionId: session.id)
            pendingEvents = stored
            if let last = stored.last {
                lastActivityTime = last.timestamp
            }
            await activityStore.restore(session: session, events: stored)
            await sessionStore.sessionDidResume(session)
        } catch {
            print("[SessionEngine] Resume hydration failed: \(error)")
            await activityStore.sessionDidStart(session)
        }
    }

    private func closeStaleSession(_ session: Session) async {
        if currentSession?.id == session.id {
            await flushPendingEvents()
        }
        var ended = session
        ended.endedAt = Date()
        do {
            let events = await allEventsForSession(session.id)
            ended.appCount = Set(events.map(\.appBundleId)).count
            ended.focusScore = focusScore(from: events)
            ended.title = await MainActor.run {
                SessionTitleGenerator.generate(from: events, startedAt: session.startedAt)
            }
            await finalizeSessionMemory(&ended, events: events)
            try await repository.save(ended)
            await sessionStore.sessionDidEnd(ended)
            ActivityPersistenceLogger.log("Closed stale session \(session.id.uuidString) — \(events.count) events")
        } catch {
            ActivityPersistenceLogger.log("Stale close failed", error: error)
        }
    }

    private func beginNewSession() async {
        var session = Session()
        let startedAt = session.startedAt
        session.title = await MainActor.run {
            SessionTitleGenerator.generate(from: [], startedAt: startedAt)
        }
        currentSession = session
        pendingEvents = []
        eventsSinceTitlePersist = 0
        lastActivityTime = Date()

        do {
            try await repository.save(session)
            await activityStore.sessionDidStart(session)
            await sessionStore.sessionDidStart(session)
            ActivityPersistenceLogger.log("Began session \(session.id.uuidString)")
        } catch {
            ActivityPersistenceLogger.log("Begin session save failed", error: error)
        }
    }

    private func ensureActiveSession() async {
        guard currentSession == nil else { return }
        await beginNewSession()
    }

    // MARK: - Title persistence (background — does not block live path)

    private func schedulePersistedTitleRefresh(wasFocus: Bool) {
        eventsSinceTitlePersist += 1

        let delay: TimeInterval
        if wasFocus {
            delay = EchoConfig.workflowIdentitySettleInterval
        } else if eventsSinceTitlePersist >= EchoConfig.titleUpdateEventThreshold {
            delay = EchoConfig.titlePersistDebounceInterval
        } else {
            return
        }

        titlePersistTask?.cancel()
        titlePersistTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            await self?.persistTitleRefresh()
        }
    }

    private func persistTitleRefresh() async {
        guard var session = currentSession else { return }
        eventsSinceTitlePersist = 0

        let startedAt = session.startedAt
        let title = await activityStore.computeStableWorkflowIdentity(startedAt: startedAt)
        guard session.title != title else { return }

        session.title = title
        session.appCount = uniqueAppCount()
        currentSession = session

        await activityStore.applyPersistedSession(session)

        do {
            try await repository.save(session)
            await sessionStore.sessionDidUpdate(session)
        } catch {
            print("[SessionEngine] Title persist failed: \(error)")
        }
    }

    // MARK: - Batch Writer (persistence only)

    private func startBatchWriter() {
        batchWriteTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(EchoConfig.batchWriteInterval))
                await self?.flushPendingEvents()
            }
        }
    }

    private func flushPendingEvents() async {
        guard !pendingEvents.isEmpty else { return }
        let batch = pendingEvents
        let sessionIds = Set(batch.map(\.sessionId))
        pendingEvents.removeAll()
        ActivityPersistenceLogger.log("Flushing \(batch.count) events…")
        do {
            let count = try await repository.insertBatch(batch)
            for sessionId in sessionIds {
                notifyActivitiesPersisted(sessionId: sessionId)
            }
            ActivityPersistenceLogger.log("Flush succeeded — persisted \(count) events")
        } catch {
            pendingEvents.insert(contentsOf: batch, at: 0)
            ActivityPersistenceLogger.log("Flush failed — re-queued \(batch.count) events", error: error)
        }
    }

    private func notifyActivitiesPersisted(sessionId: UUID) {
        NotificationCenter.default.post(
            name: .echoActivitiesPersisted,
            object: nil,
            userInfo: ["sessionId": sessionId]
        )
    }

    /// Persisted rows plus any still-queued events for this session.
    private func allEventsForSession(_ sessionId: UUID) async -> [ActivityEvent] {
        let persisted = (try? await repository.fetchActivities(sessionId: sessionId)) ?? []
        let queued = pendingEvents.filter { $0.sessionId == sessionId }
        let merged = SessionRepository.mergeEvents(persisted: persisted, live: queued)
        ActivityPersistenceLogger.log(
            "allEventsForSession \(sessionId.uuidString): persisted=\(persisted.count) queued=\(queued.count) merged=\(merged.count)"
        )
        return merged
    }

    // MARK: - Metrics

    private func uniqueAppCount() -> Int {
        Set(pendingEvents.map(\.appBundleId)).count
    }

    private func computeFocusScore() -> Double {
        focusScore(from: pendingEvents)
    }

    private func focusScore(from events: [ActivityEvent]) -> Double {
        guard !events.isEmpty else { return 0 }
        let switches = events.filter { $0.type == .appSwitch }.count
        let switchRate = Double(switches) / Double(events.count)
        return min(max(1 - switchRate, 0), 1)
    }

    // MARK: - Browser context

    private func scheduleBrowserCapture(bundleId: String, appName: String, sessionId: UUID) {
        browserCaptureTask?.cancel()
        browserCaptureTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(EchoConfig.browserContextCaptureDelay))
            guard !Task.isCancelled else { return }
            await self?.captureBrowserContext(bundleId: bundleId, appName: appName, sessionId: sessionId)
        }
    }

    private func captureBrowserContext(bundleId: String, appName: String, sessionId: UUID) async {
        guard currentSession?.id == sessionId else { return }

        let tab = await MainActor.run {
            BrowserContextService.captureActiveTab(for: bundleId)
        }
        guard let tab else { return }

        let browserEvent = BrowserContextService.activityEvent(
            from: tab,
            sessionId: sessionId,
            bundleId: bundleId,
            appName: appName
        )
        pendingEvents.append(browserEvent)
        ActivityPersistenceLogger.log(
            "Queued browser context for session \(sessionId.uuidString) — pending=\(pendingEvents.count)"
        )
        await activityStore.applyLiveEvent(browserEvent)
        if pendingEvents.count >= EchoConfig.batchWriteEventThreshold {
            await flushPendingEvents()
        }
    }

    // MARK: - Session memory finalization

    private func finalizeSessionMemory(_ session: inout Session, events: [ActivityEvent]) async {
        let cluster = WorkflowClusterDetector.detect(from: events)
        session.workflowCluster = cluster.rawValue
        session.projectTag = cluster.label

        let memory = WorkflowMemoryBuilder.build(session: session, events: events)
        session.tabCount = memory.browserContexts.count

        do {
            let data = try JSONEncoder().encode(memory.restorePlan)
            if let json = String(data: data, encoding: .utf8) {
                session.restorePlanJSON = json
                SessionDetailLogger.log(
                    "Restore plan persisted for \(session.id.uuidString) (\(memory.restorePlan.items.count) items)"
                )
            }
        } catch {
            SessionDetailLogger.log("Restore plan encode failed for \(session.id.uuidString)", error: error)
        }

        let tabs = await MainActor.run { BrowserTabScraper.fetchActiveBrowserTabs() }
        let layoutData = (try? JSONEncoder().encode(WindowLayout(frames: [], capturedAt: Date(), screenCount: 1))) ?? Data()
        let apps = WorkflowClusterDetector.signature(from: events)
        let snapshot = SessionSnapshot(
            id: UUID(),
            sessionId: session.id,
            capturedAt: Date(),
            windowLayout: layoutData,
            activeApps: apps,
            browserTabs: tabs,
            thumbnailPath: nil
        )
        do {
            try await repository.insertSnapshot(snapshot)
            session.snapshotPath = snapshot.id.uuidString
        } catch {
            SessionDetailLogger.log("Snapshot insert failed for \(session.id.uuidString)", error: error)
        }
    }
}

nonisolated enum SessionEndReason: Sendable {
    case idle
    case appTermination
    case userInitiated
    case boundaryHeuristic
}
