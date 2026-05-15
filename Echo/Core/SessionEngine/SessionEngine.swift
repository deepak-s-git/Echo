import Foundation

/// Consumes RawActivityEvents from ActivityTracker, manages session boundaries,
/// and coordinates persistence via SessionRepository.
///
/// Ordering contract: call configure(tracker:) then start(). Both are enforced by ServiceContainer.
actor SessionEngine {

    // MARK: - Dependencies

    private let repository: SessionRepository
    private let activityStore: ActivityStore
    private let sessionStore: SessionStore
    private let idleMonitor: IdleTimeMonitor

    // MARK: - State

    private var currentSession: Session?
    private var pendingEvents: [ActivityEvent] = []
    private var lastActivityTime: Date = Date()
    private var trackerTask: Task<Void, Never>?
    private var batchWriteTask: Task<Void, Never>?

    // MARK: - Init

    init(
        database: DatabaseManager,
        activityStore: ActivityStore,
        sessionStore: SessionStore,
        idleMonitor: IdleTimeMonitor
    ) {
        self.repository = SessionRepository(database: database)
        self.activityStore = activityStore
        self.sessionStore = sessionStore
        self.idleMonitor = idleMonitor
    }

    // MARK: - Configuration (called before start)

    func configure(tracker: ActivityTracker) async {
        guard let stream = await tracker.eventStream else {
            assertionFailure("ActivityTracker must be started before SessionEngine is configured.")
            return
        }
        // Wire idle monitor → session boundary
        await idleMonitor.onIdleStateChange = { [weak self] isIdle in
            if isIdle {
                Task { await self?.endCurrentSession(reason: .idle) }
            }
        }
        beginConsuming(stream)
    }

    // MARK: - Lifecycle

    func start() async {
        await beginNewSession()
        startBatchWriter()
    }

    func endCurrentSession(reason: SessionEndReason) async {
        guard var session = currentSession else { return }
        let now = Date()

        session.endedAt = now
        session.appCount = uniqueAppCount()
        session.focusScore = computeFocusScore()

        currentSession = nil
        await flushPendingEvents()

        do {
            try await repository.save(session)
            await sessionStore.sessionDidEnd(session)
        } catch {
            await appStoreError(error)
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

        // Session boundary by gap (belt-and-suspenders alongside idle monitor)
        if elapsed > EchoConfig.sessionIdleTimeout {
            await endCurrentSession(reason: .idle)
            await beginNewSession()
        }

        lastActivityTime = now

        guard let session = currentSession else { return }
        let event = raw.stamped(sessionId: session.id)

        pendingEvents.append(event)
        await activityStore.append(event)
    }

    // MARK: - Session Management

    private func beginNewSession() async {
        let session = Session()
        currentSession = session
        do {
            try await repository.save(session)
            await activityStore.sessionDidStart(session)
            await sessionStore.sessionDidStart(session)
        } catch {
            await appStoreError(error)
        }
    }

    // MARK: - Batch Writer

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
            // Re-queue on failure so events aren't silently lost.
            pendingEvents.insert(contentsOf: batch, at: 0)
        }
    }

    // MARK: - Metrics

    private func uniqueAppCount() -> Int {
        Set(pendingEvents.map(\.appBundleId)).count
    }

    private func computeFocusScore() -> Double {
        guard !pendingEvents.isEmpty else { return 0 }
        let switches = pendingEvents.filter { $0.type == .appSwitch }.count
        let switchRate = Double(switches) / Double(pendingEvents.count)
        return (1 - switchRate).clamped(to: 0...1)
    }

    // MARK: - Error Channel

    @MainActor
    private func appStoreError(_ error: Error) {
        // Surface to AppStore for non-fatal error display; extend as needed.
        print("[SessionEngine] Non-fatal error: \(error)")
    }
}

// MARK: - SessionEndReason

enum SessionEndReason: Sendable {
    case idle
    case appTermination
    case userInitiated
    case boundaryHeuristic
}

// MARK: - Comparable Clamp

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
