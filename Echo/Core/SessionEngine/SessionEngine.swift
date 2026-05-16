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
        await flushPendingEvents()

        do {
            try await repository.save(session)
            await activityStore.sessionDidEnd(session)
            await sessionStore.sessionDidEnd(session)
        } catch {
            print("[SessionEngine] Non-fatal error: \(error)")
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

        // Live UI first — never wait on DB or full title generation.
        await activityStore.applyLiveEvent(event)

        schedulePersistedTitleRefresh(wasFocus: event.type == .appFocus)
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
        var ended = session
        ended.endedAt = Date()
        do {
            let events = try await repository.fetchActivities(sessionId: session.id)
            ended.appCount = Set(events.map(\.appBundleId)).count
            let switches = events.filter { $0.type == .appSwitch }.count
            let rate = events.isEmpty ? 0 : Double(switches) / Double(events.count)
            ended.focusScore = min(max(1 - rate, 0), 1)
            ended.title = await MainActor.run {
                SessionTitleGenerator.generate(from: events, startedAt: session.startedAt)
            }
            try await repository.save(ended)
            await sessionStore.sessionDidEnd(ended)
        } catch {
            print("[SessionEngine] Stale close failed: \(error)")
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
        } catch {
            print("[SessionEngine] Non-fatal error: \(error)")
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

        let events = pendingEvents
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
        pendingEvents.removeAll()
        do {
            try await repository.insertBatch(batch)
        } catch {
            pendingEvents.insert(contentsOf: batch, at: 0)
        }
    }

    // MARK: - Metrics

    private func allEventsForMetrics() -> [ActivityEvent] {
        pendingEvents
    }

    private func uniqueAppCount() -> Int {
        Set(pendingEvents.map(\.appBundleId)).count
    }

    private func computeFocusScore() -> Double {
        let events = allEventsForMetrics()
        guard !events.isEmpty else { return 0 }
        let switches = events.filter { $0.type == .appSwitch }.count
        let switchRate = Double(switches) / Double(events.count)
        return min(max(1 - switchRate, 0), 1)
    }
}

enum SessionEndReason: Sendable {
    case idle
    case appTermination
    case userInitiated
    case boundaryHeuristic
}
