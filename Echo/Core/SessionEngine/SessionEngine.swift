import Foundation

/// Consumes RawActivityEvents from ActivityTracker, manages session boundaries,
/// and coordinates persistence via SessionRepository.
actor SessionEngine {

    private let repository: SessionRepository
    private let activityStore: ActivityStore
    private let sessionStore: SessionStore
    private let idleMonitor: IdleTimeMonitor
    private var activityTracker: ActivityTracker?

    private var currentSession: Session?
    private var isSessionPaused = false
    private var pendingEvents: [ActivityEvent] = []
    private var lastActivityTime: Date = Date()
    private var trackerTask: Task<Void, Never>?
    private var batchWriteTask: Task<Void, Never>?
    private var titlePersistTask: Task<Void, Never>?
    private var browserCaptureTask: Task<Void, Never>?
    private var eventsSinceTitlePersist = 0
    private var consecutiveFlushFailures = 0
    private var flushBackoffUntil: Date?
    private var isRecoveredSession = false
    private var isRecordingEnabled = false
    private var currentWorkflowThreadId: UUID?
    private var recordingThread: WorkflowThread?

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
        activityTracker = tracker
        guard let stream = await tracker.eventStream else {
            assertionFailure("ActivityTracker must be started before SessionEngine is configured.")
            return
        }
        await idleMonitor.setOnIdleStateChange { [weak self] isIdle in
            guard isIdle else { return }
            Task { await self?.handleIdleTimeout() }
        }
        beginConsuming(stream)
    }

    func start() async {
        startBatchWriter()
        await prepareOnLaunch()
    }

    func startNewSession() async {
        guard !isRecordingEnabled else { return }
        isRecordingEnabled = true
        await idleMonitor.setMonitoringEnabled(true)
        await activityTracker?.setCapturePaused(false)
        await beginNewWorkflow()
        EchoLog.lifecycle("User started new workflow")
    }

    func continuePreviousSession(restoreContext: Bool = true) async {
        guard !isRecordingEnabled else { return }
        isRecordingEnabled = true
        await idleMonitor.setMonitoringEnabled(true)
        await activityTracker?.setCapturePaused(false)

        if let thread = await findContinueThread() {
            await armRecording(on: thread)
            if restoreContext, let lastSegment = try? await repository.fetchLastEndedSegment(threadId: thread.id) {
                await restoreContextFromLastSegment(lastSegment)
            }
            EchoLog.lifecycle("Continued workflow \(thread.id.uuidString) — awaiting first activity")
            return
        }
        await beginNewWorkflow()
        EchoLog.lifecycle("Continue fell back to new workflow")
    }

    func cancelRecording() async {
        guard isRecordingEnabled else { return }
        isRecordingEnabled = false
        currentSession = nil
        currentWorkflowThreadId = nil
        recordingThread = nil
        pendingEvents = []
        await activityTracker?.setCapturePaused(true)
        await idleMonitor.setMonitoringEnabled(false)
        await activityStore.enterIdleMode()
        EchoLog.lifecycle("Recording cancelled (no segment)")
    }

    func deleteSession(id: UUID) async {
        if currentSession?.id == id {
            currentSession = nil
            currentWorkflowThreadId = nil
            recordingThread = nil          // must clear — beginNewWorkflow guards on this
            isRecordingEnabled = false
            isSessionPaused = false
            await activityTracker?.setCapturePaused(true)
            await idleMonitor.setMonitoringEnabled(false)
            await activityStore.enterIdleMode()
        }
        do {
            try await repository.deleteSession(id: id)
            await sessionStore.loadRecent()
            ActivityPersistenceLogger.log("Deleted session \(id.uuidString)")
        } catch {
            ActivityPersistenceLogger.log("Delete session failed", error: error)
        }
    }

    func deleteWorkflowThread(id: UUID) async {
        // Match on EITHER currentWorkflowThreadId OR recordingThread.id — deleteSession
        // nil-s currentWorkflowThreadId first, so checking only that would always miss.
        let isActive = currentWorkflowThreadId == id || recordingThread?.id == id
        if isActive {
            currentSession = nil
            currentWorkflowThreadId = nil
            recordingThread = nil
            isRecordingEnabled = false
            isSessionPaused = false
            await activityTracker?.setCapturePaused(true)
            await idleMonitor.setMonitoringEnabled(false)
            await activityStore.enterIdleMode()
        }
        do {
            try await repository.deleteWorkflowThread(id: id)
            await sessionStore.loadRecent()
            ActivityPersistenceLogger.log("Deleted workflow thread \(id.uuidString)")
        } catch {
            ActivityPersistenceLogger.log("Delete workflow thread failed", error: error)
        }
    }

    func archiveWorkflowThread(id: UUID) async {
        try? await repository.archiveWorkflowThread(id: id)
        await sessionStore.loadRecent()
    }

    private func handleIdleTimeout() async {
        guard isRecordingEnabled else { return }

        if currentSession == nil {
            // Recording was armed (thread ready, waiting for first event) but the user
            // went idle before any activity arrived — cancel cleanly so startNewSession
            // can be called again without being blocked by isRecordingEnabled = true.
            await cancelRecording()
            EchoLog.lifecycle("Idle timeout fired before segment started — recording cancelled")
            return
        }

        guard !isSessionPaused else { return }
        await endCurrentSession(reason: .idle)
    }

    func pauseSession() async {
        guard var session = currentSession, !isSessionPaused else { return }
        isSessionPaused = true
        session.lifecycleStateRaw = SessionLifecycleState.paused.rawValue
        session.pausedAt = Date()
        currentSession = session
        await activityTracker?.setCapturePaused(true)
        await idleMonitor.setMonitoringEnabled(false)
        await flushPendingEvents()
        do {
            try await repository.save(session)
            await sessionStore.sessionDidUpdate(session)
            await activityStore.sessionDidPause()
            ActivityPersistenceLogger.log("Paused session \(session.id.uuidString)")
        } catch {
            ActivityPersistenceLogger.log("Pause save failed", error: error)
        }
    }

    func resumeSession() async {
        guard var session = currentSession, isSessionPaused else { return }
        if let pausedAt = session.pausedAt {
            session.pausedDuration += Date().timeIntervalSince(pausedAt)
        }
        session.pausedAt = nil
        session.lifecycleStateRaw = SessionLifecycleState.active.rawValue
        isSessionPaused = false
        currentSession = session
        if isRecordingEnabled {
            await activityTracker?.setCapturePaused(false)
            await idleMonitor.setMonitoringEnabled(true)
        }
        do {
            try await repository.save(session)
            await sessionStore.sessionDidUpdate(session)
            await activityStore.sessionDidResumeCapture()
            ActivityPersistenceLogger.log("Resumed session \(session.id.uuidString)")
        } catch {
            ActivityPersistenceLogger.log("Resume save failed", error: error)
        }
    }

    func endCurrentSession(
        reason: SessionEndReason,
        title: String? = nil,
        tags: [String] = []
    ) async {
        if currentSession == nil {
            await cancelRecording()
            return
        }
        guard var session = currentSession else { return }
        let now = Date()

        if isSessionPaused, let pausedAt = session.pausedAt {
            session.pausedDuration += now.timeIntervalSince(pausedAt)
            session.pausedAt = nil
            isSessionPaused = false
            await activityTracker?.setCapturePaused(false)
        }

        session.endedAt = now
        session.lifecycleStateRaw = SessionLifecycleState.ended.rawValue
        if let title, !title.isEmpty {
            session.title = title
        }
        if !tags.isEmpty {
            session.tagsJSON = Self.encodeTags(tags)
        }

        let sessionId = session.id
        let threadId = currentWorkflowThreadId
        let segmentDuration = session.duration
        let queuedBatch = pendingEvents

        currentSession = nil
        currentWorkflowThreadId = nil
        recordingThread = nil
        pendingEvents = []
        isRecordingEnabled = false
        isRecoveredSession = false
        titlePersistTask?.cancel()
        browserCaptureTask?.cancel()
        await activityTracker?.setCapturePaused(true)
        await idleMonitor.setMonitoringEnabled(false)

        if queuedBatch.isEmpty {
            let persisted = (try? await repository.fetchActivities(sessionId: session.id)) ?? []
            if persisted.isEmpty {
                try? await repository.deleteSession(id: session.id)
                EchoLog.lifecycle("Removed empty segment \(session.id.uuidString)")
            }
        }

        await activityStore.enterIdleMode()
        await sessionStore.sessionDidEnd(session)

        let repo = repository
        let capturedTitle = title
        let capturedThreadId = threadId
        let capturedDuration = segmentDuration
        let sessionSnapshot = session
        let batch = queuedBatch
        let endedAt = now

        if batch.isEmpty,
           (try? await repository.fetchActivities(sessionId: session.id))?.isEmpty != false {
            EchoLog.lifecycle("Skip finalize for empty segment \(session.id.uuidString)")
            return
        }

        Task.detached(priority: .utility) {
            if let capturedThreadId {
                try? await repo.appendSegmentDurationToThread(
                    threadId: capturedThreadId,
                    segmentDuration: capturedDuration
                )
                if var thread = try? await repo.fetchThread(id: capturedThreadId) {
                    thread.statusRaw = WorkflowThreadStatus.idle.rawValue
                    if let capturedTitle, !capturedTitle.isEmpty { thread.title = capturedTitle }
                    thread.lastActiveAt = endedAt
                    try? await repo.saveThread(thread)
                }
            }
            await SessionFinalizationRunner.finalize(
                session: sessionSnapshot,
                queuedBatch: batch,
                userTitle: capturedTitle,
                repository: repo
            )
            await MainActor.run {
                NotificationCenter.default.post(name: .echoSessionFinalized, object: nil)
            }
        }

        EchoLog.lifecycle("Ended segment \(sessionId.uuidString) — UI idle, finalize detached")
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
        guard isRecordingEnabled, !isSessionPaused else { return }
        guard isMeaningful(raw) else { return }

        if currentSession == nil {
            await ensureSegmentStarted(trigger: raw)
        }
        guard let session = currentSession else { return }

        let now = Date()
        lastActivityTime = now
        let sessionId = session.id

        let event = await MainActor.run {
            var stamped = raw.stamped(sessionId: sessionId)
            stamped.appName = AppMetadataResolver.displayName(
                bundleId: stamped.appBundleId,
                rawName: stamped.appName
            )
            return stamped
        }

        if shouldSkipRedundantFocus(event) { return }

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

    private func prepareOnLaunch() async {
        ActivityPersistenceLogger.log("Launch — idle mode (no auto-recording)")

        // Hard-reset ALL in-memory recording state — guarantees a clean slate
        // regardless of how the previous run ended (crash, Xcode stop, force-quit, etc.)
        isRecordingEnabled = false
        isSessionPaused = false
        isRecoveredSession = false
        currentSession = nil
        recordingThread = nil
        currentWorkflowThreadId = nil
        pendingEvents = []
        consecutiveFlushFailures = 0
        flushBackoffUntil = nil
        titlePersistTask?.cancel()
        titlePersistTask = nil
        browserCaptureTask?.cancel()
        browserCaptureTask = nil

        await activityTracker?.setCapturePaused(true)
        await idleMonitor.setMonitoringEnabled(false)

        // Close any sessions that are still marked active in the DB (crash recovery)
        do {
            let actives = try await repository.fetchActive()
            for stale in actives {
                await closeStaleSession(stale)
            }
            // Also reset any workflow threads still flagged active
            if !actives.isEmpty {
                try? await repository.resetActiveThreadStatuses()
            }
        } catch {
            ActivityPersistenceLogger.log("Launch orphan cleanup failed", error: error)
        }

        let continueThread = try? await repository.fetchMostRecentContinuableThread()
        await MainActor.run {
            sessionStore.setContinueWorkflowThread(continueThread)
            activityStore.enterIdleMode()
        }
    }

    private func findContinueThread() async -> WorkflowThread? {
        if let cached = await MainActor.run(body: { sessionStore.continueWorkflowThread }) {
            return cached
        }
        return try? await repository.fetchMostRecentContinuableThread()
    }

    private func armRecording(on thread: WorkflowThread) async {
        if currentSession != nil { return }
        do {
            let orphans = try await repository.fetchActive()
            for orphan in orphans { await closeStaleSession(orphan) }
        } catch {
            EchoLog.lifecycle("Orphan cleanup failed", error: error)
        }

        var updatedThread = thread
        updatedThread.statusRaw = WorkflowThreadStatus.active.rawValue
        updatedThread.lastActiveAt = Date()
        try? await repository.saveThread(updatedThread)

        recordingThread = updatedThread
        currentWorkflowThreadId = thread.id
        pendingEvents = []
        eventsSinceTitlePersist = 0
        isRecoveredSession = false
        isSessionPaused = false

        await activityStore.beginRecording(
            threadTitle: thread.title,
            threadAccumulated: thread.totalAccumulatedDuration
        )
        await sessionStore.workflowThreadDidUpdate(updatedThread)
        await MainActor.run { sessionStore.setContinueWorkflowThread(nil) }
    }

    private func ensureSegmentStarted(trigger: RawActivityEvent) async {
        guard currentSession == nil, let thread = recordingThread else { return }

        let startedAt = Date()
        var session = Session(startedAt: startedAt, workflowThreadId: thread.id)
        session.title = thread.title
        session.tagsJSON = thread.tagsJSON
        session.lifecycleStateRaw = SessionLifecycleState.active.rawValue
        session.title = await MainActor.run {
            SessionTitleGenerator.generate(from: [], startedAt: startedAt)
        }

        currentSession = session
        lastActivityTime = startedAt

        do {
            try await repository.save(session)
            await activityStore.segmentDidStart(session)
            await sessionStore.sessionDidStart(session)
            EchoLog.lifecycle("Segment \(session.id.uuidString) started on first activity")
        } catch {
            EchoLog.lifecycle("Segment create failed", error: error)
        }
    }

    private func isMeaningful(_ raw: RawActivityEvent) -> Bool {
        switch raw.type {
        case .appFocus, .appSwitch, .browserTab, .fileAccess, .terminalCommand:
            return true
        case .idle:
            return false
        }
    }

    private func restoreContextFromLastSegment(_ segment: Session) async {
        guard let plan = segment.restorePlan, !plan.items.isEmpty else { return }
        let events = (try? await repository.fetchActivities(sessionId: segment.id)) ?? []
        let weighted = RestoreWeighting.buildSelectableItems(from: events, plan: plan)
        var filtered = RestoreWeighting.filteredPlan(from: weighted)
        if filtered.items.isEmpty {
            filtered = RestoreWeighting.fallbackPlan(from: events, plan: plan)
        }
        await activityStore.setRestoring(true)
        _ = await WorkflowRestoreRunner.restore(plan: filtered)
        await activityStore.setRestoring(false)
        EchoLog.restore(
            "Restored context from segment \(segment.id.uuidString) — \(filtered.items.count) items"
        )
    }

    func endIfRecording(reason: SessionEndReason) async {
        guard currentSession != nil else { return }
        await endCurrentSession(reason: reason)
    }

    private func closeStaleSession(_ session: Session) async {
        if currentSession?.id == session.id {
            await flushPendingEvents()
        }
        var ended = session
        ended.endedAt = Date()
        ended.lifecycleStateRaw = SessionLifecycleState.ended.rawValue
        let events = await allEventsForSession(session.id)
        ended.appCount = Set(events.map(\.appBundleId)).count
        ended.focusScore = focusScore(from: events)
        ended.title = await MainActor.run {
            SessionTitleGenerator.generate(from: events, startedAt: session.startedAt)
        }
        await finalizeSessionMemory(&ended, events: events)
        do {
            try await repository.save(ended)
            await sessionStore.sessionDidEnd(ended)
            ActivityPersistenceLogger.log("Closed stale session \(session.id.uuidString) — \(events.count) events")
        } catch {
            ActivityPersistenceLogger.log("Stale close save failed", error: error)
        }
    }

    private func beginNewWorkflow() async {
        if currentSession != nil || recordingThread != nil { return }

        do {
            let orphans = try await repository.fetchActive()
            for orphan in orphans { await closeStaleSession(orphan) }
        } catch {
            EchoLog.lifecycle("Orphan cleanup failed", error: error)
        }

        let startedAt = Date()
        let title = await MainActor.run {
            SessionTitleGenerator.generate(from: [], startedAt: startedAt)
        }
        let thread = WorkflowThread(
            title: title,
            statusRaw: WorkflowThreadStatus.active.rawValue
        )

        do {
            try await repository.saveThread(thread)
            recordingThread = thread
            currentWorkflowThreadId = thread.id
            pendingEvents = []
            eventsSinceTitlePersist = 0
            isRecoveredSession = false
            isSessionPaused = false
            await activityStore.beginRecording(threadTitle: title, threadAccumulated: 0)
            await sessionStore.workflowThreadDidUpdate(thread)
            await MainActor.run { sessionStore.setContinueWorkflowThread(nil) }
            EchoLog.lifecycle("Armed new workflow \(thread.id.uuidString) — awaiting first activity")
        } catch {
            EchoLog.lifecycle("Begin workflow failed", error: error)
        }
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
        if let until = flushBackoffUntil, Date() < until {
            return
        }

        let batch = pendingEvents
        let sessionIds = Set(batch.map(\.sessionId))
        pendingEvents.removeAll()
        ActivityPersistenceLogger.log("Flushing \(batch.count) events…")
        do {
            let count = try await repository.insertBatch(batch)
            consecutiveFlushFailures = 0
            flushBackoffUntil = nil
            for sessionId in sessionIds {
                notifyActivitiesPersisted(sessionId: sessionId)
            }
            ActivityPersistenceLogger.log("Flush succeeded — persisted \(count) events")
        } catch {
            consecutiveFlushFailures += 1
            let backoff = min(
                EchoConfig.flushFailureMaxBackoff,
                pow(2.0, Double(min(consecutiveFlushFailures, 5)))
            )
            flushBackoffUntil = Date().addingTimeInterval(backoff)
            pendingEvents.insert(contentsOf: batch, at: 0)
            ActivityPersistenceLogger.log(
                "Flush failed — re-queued \(batch.count) events (backoff \(Int(backoff))s)",
                error: error
            )
        }
    }

    private func shouldSkipRedundantFocus(_ event: ActivityEvent) -> Bool {
        guard event.type == .appFocus else { return false }
        guard let lastIdx = pendingEvents.lastIndex(where: { $0.type == .appFocus }) else { return false }
        let last = pendingEvents[lastIdx]
        guard last.appBundleId == event.appBundleId else { return false }
        
        let isRedundant = event.timestamp.timeIntervalSince(last.timestamp) < EchoConfig.trackerMinTransitionInterval
        if isRedundant {
            if event.url != nil {
                pendingEvents[lastIdx].url = event.url
            }
            if event.windowTitle != nil {
                pendingEvents[lastIdx].windowTitle = event.windowTitle
            }
        }
        return isRedundant
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

        let tabs = await MainActor.run {
            BrowserTabScraper.tabsForRestore(bundleId: bundleId)
        }
        guard !tabs.isEmpty else { return }

        for tab in tabs {
            let browserEvent = BrowserContextService.activityEvent(
                from: tab,
                sessionId: sessionId,
                bundleId: bundleId,
                appName: appName
            )
            pendingEvents.append(browserEvent)
        }
        ActivityPersistenceLogger.log(
            "Queued \(tabs.count) browser tab(s) for \(sessionId.uuidString)"
        )
        if let last = tabs.last {
            let liveEvent = BrowserContextService.activityEvent(
                from: last,
                sessionId: sessionId,
                bundleId: bundleId,
                appName: appName
            )
            await activityStore.applyLiveEvent(liveEvent)
        }
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

        let contextual = WorkflowContextCapture.items(from: events)
        let plan = mergeRestorePlan(primary: contextual, secondary: memory.restorePlan)

        do {
            let data = try JSONEncoder().encode(plan)
            if let json = String(data: data, encoding: .utf8) {
                session.restorePlanJSON = json
                SessionDetailLogger.log(
                    "Restore plan persisted for \(session.id.uuidString) (\(memory.restorePlan.items.count) items)"
                )
            }
        } catch {
            SessionDetailLogger.log("Restore plan encode failed for \(session.id.uuidString)", error: error)
        }

        let tabs = await captureBrowserTabsForSnapshot(events: events)
        SessionDetailLogger.log("Snapshot browser tabs: \(tabs.count)")
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

    private func mergeRestorePlan(
        primary: [RestoreItem],
        secondary: WorkflowRestorePlan
    ) -> WorkflowRestorePlan {
        var seen = Set<String>()
        var items: [RestoreItem] = []
        for item in primary + secondary.items {
            let key = restoreKey(item)
            guard seen.insert(key).inserted else { continue }
            items.append(item)
        }
        return WorkflowRestorePlan(items: items, createdAt: secondary.createdAt)
    }

    private func restoreKey(_ item: RestoreItem) -> String {
        switch item.kind {
        case .application: return "app:\(item.bundleId ?? "")"
        case .url, .browserPage: return "url:\(item.url ?? "")"
        case .folder: return "folder:\(item.path ?? "")"
        case .document: return "doc:\(item.path ?? "")"
        case .terminalDirectory: return "term:\(item.workingDirectory ?? "")"
        case .workspace: return "ws:\(item.path ?? "")"
        }
    }

    private func captureBrowserTabsForSnapshot(events: [ActivityEvent]) async -> [BrowserTab] {
        await MainActor.run {
            var tabs = BrowserTabScraper.fetchAllBrowserTabsForRestore()
            if tabs.isEmpty {
                let browserBundles = Set(
                    events.filter { BrowserContextService.isBrowser($0.appBundleId) }
                        .map(\.appBundleId)
                )
                for bundleId in browserBundles {
                    tabs.append(contentsOf: BrowserTabScraper.tabsForRestore(bundleId: bundleId))
                }
            }
            var seen = Set<String>()
            return tabs.filter { tab in
                let key = tab.url.lowercased()
                return seen.insert(key).inserted
            }
        }
    }

    private static func encodeTags(_ tags: [String]) -> String? {
        guard let data = try? JSONEncoder().encode(tags) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

nonisolated enum SessionEndReason: Sendable {
    case idle
    case appTermination
    case userInitiated
    case boundaryHeuristic
}
