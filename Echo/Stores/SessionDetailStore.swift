import SwiftUI
import Combine

@MainActor
final class SessionDetailStore: ObservableObject {

    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case degraded
        case failed
    }

    @Published private(set) var memory: WorkflowMemory?
    @Published private(set) var diagnostics: SessionDetailDiagnostics?
    @Published private(set) var snapshot: SessionSnapshot?
    @Published private(set) var loadState: LoadState = .idle
    @Published private(set) var isLoading = false
    @Published private(set) var loadError: Error?
    @Published private(set) var isRestoring = false
    @Published private(set) var restoreMessage: String?

    private var repository: SessionRepository?
    private var sessionStore: SessionStore?
    private var activityStore: ActivityStore?
    private let restoreEngine = WorkflowRestoreEngine()

    private var watchedSessionId: UUID?
    private var liveRefreshTask: Task<Void, Never>?
    private var persistenceObserver: NSObjectProtocol?

    init() {
        persistenceObserver = NotificationCenter.default.addObserver(
            forName: .echoActivitiesPersisted,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor [weak self] in
                guard let self,
                      let sessionId = notification.userInfo?["sessionId"] as? UUID,
                      sessionId == self.watchedSessionId
                else { return }
                await self.reload(sessionId: sessionId)
            }
        }
    }

    deinit {
        liveRefreshTask?.cancel()
        if let persistenceObserver {
            NotificationCenter.default.removeObserver(persistenceObserver)
        }
    }

    func configure(
        repository: SessionRepository,
        sessionStore: SessionStore,
        activityStore: ActivityStore
    ) {
        self.repository = repository
        self.sessionStore = sessionStore
        self.activityStore = activityStore
    }

    func load(sessionId: UUID) async {
        watchedSessionId = sessionId
        await performLoad(sessionId: sessionId, showLoading: true)
        startLiveRefreshIfNeeded(sessionId: sessionId)
    }

    func reload(sessionId: UUID) async {
        await performLoad(sessionId: sessionId, showLoading: false)
    }

    func stopWatching() {
        watchedSessionId = nil
        liveRefreshTask?.cancel()
        liveRefreshTask = nil
    }

    func restoreWorkflow() async {
        guard let plan = memory?.restorePlan, !plan.items.isEmpty else {
            restoreMessage = "Nothing to restore for this session."
            return
        }
        isRestoring = true
        defer { isRestoring = false }
        let result = await restoreEngine.restore(plan: plan)
        if result.failed.isEmpty {
            restoreMessage = "Restored \(result.succeeded.count) items from your workflow."
        } else {
            restoreMessage = "Restored \(result.succeeded.count); \(result.failed.count) could not open."
        }
    }

    func clearRestoreMessage() { restoreMessage = nil }

    // MARK: - Private

    private func performLoad(sessionId: UUID, showLoading: Bool) async {
        guard let repository else {
            var diagnostics = SessionDetailDiagnostics()
            diagnostics.record(.repositoryUnavailable)
            self.diagnostics = diagnostics
            memory = nil
            snapshot = nil
            loadError = SessionDetailStoreError.repositoryUnavailable
            loadState = .failed
            SessionDetailLogger.log("Load aborted — repository not configured")
            return
        }

        if showLoading {
            isLoading = true
            loadState = .loading
            loadError = nil
            memory = nil
            snapshot = nil
            diagnostics = nil
        }

        defer { if showLoading { isLoading = false } }

        let fallbackSession = sessionStore?.recentSessions.first { $0.id == sessionId }
        let liveEvents = activityStore?.liveEvents(for: sessionId) ?? []

        let outcome = await repository.loadSessionDetail(
            sessionId: sessionId,
            fallbackSession: fallbackSession,
            liveEvents: liveEvents
        )

        switch outcome {
        case .loaded(let payload):
            memory = payload.memory
            snapshot = payload.snapshot
            diagnostics = payload.diagnostics
            loadState = payload.diagnostics.issues.isEmpty ? .loaded : .degraded
            SessionDetailLogger.log(
                "UI load — events=\(payload.memory.events.count) transitions=\(payload.memory.appTransitions.count) restore=\(payload.memory.restorePlan.items.count)"
            )

        case .notFound(var diagnostics):
            if let fallbackSession {
                let rebuilt = rebuildFromCache(
                    session: fallbackSession,
                    liveEvents: liveEvents,
                    diagnostics: &diagnostics
                )
                memory = rebuilt.memory
                snapshot = rebuilt.snapshot
                self.diagnostics = rebuilt.diagnostics
                loadState = .degraded
                SessionDetailLogger.log("Reconstructed memory from cache only")
                return
            }

            self.diagnostics = diagnostics
            memory = nil
            snapshot = nil
            loadState = .failed
            loadError = SessionDetailStoreError.sessionNotFound(sessionId)
            SessionDetailLogger.log("Load failed — session not found")
        }
    }

    private func startLiveRefreshIfNeeded(sessionId: UUID) {
        liveRefreshTask?.cancel()
        let hasLiveBuffer = !(activityStore?.liveEvents(for: sessionId) ?? []).isEmpty
        let isActive = sessionStore?.recentSessions.first(where: { $0.id == sessionId })?.isActive == true
            || hasLiveBuffer
        guard isActive else { return }

        liveRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(EchoConfig.sessionDetailLiveRefreshInterval))
                guard !Task.isCancelled else { break }
                guard let self, self.watchedSessionId == sessionId else { break }
                await self.reload(sessionId: sessionId)
            }
        }
    }

    private func rebuildFromCache(
        session: Session,
        liveEvents: [ActivityEvent],
        diagnostics: inout SessionDetailDiagnostics
    ) -> (memory: WorkflowMemory, snapshot: SessionSnapshot?, diagnostics: SessionDetailDiagnostics) {
        diagnostics.record(.usedSessionStoreFallback)
        if liveEvents.isEmpty {
            diagnostics.record(.noPersistedEvents)
        } else {
            diagnostics.record(.mergedLiveEvents)
        }
        diagnostics.mergedEventCount = liveEvents.count
        diagnostics.isActiveSession = session.isActive
        diagnostics.isFinalized = !session.isActive

        let plan = session.restorePlan ?? WorkflowRestorePlan.empty
        if plan.items.isEmpty {
            diagnostics.record(.restorePlanMissing)
        }

        var memory = WorkflowMemoryBuilder.build(session: session, events: liveEvents)
        if !plan.items.isEmpty {
            memory = WorkflowMemory(
                session: memory.session,
                events: memory.events,
                cluster: memory.cluster,
                phases: memory.phases,
                appTransitions: memory.appTransitions,
                browserContexts: memory.browserContexts,
                interruptions: memory.interruptions,
                continuityScore: memory.continuityScore,
                restorePlan: plan
            )
        }
        return (memory, nil, diagnostics)
    }
}

enum SessionDetailStoreError: LocalizedError {
    case repositoryUnavailable
    case sessionNotFound(UUID)

    var errorDescription: String? {
        switch self {
        case .repositoryUnavailable:
            return "Session storage is not available."
        case .sessionNotFound(let id):
            return "No session found for id \(id.uuidString)."
        }
    }
}
