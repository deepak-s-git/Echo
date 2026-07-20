import SwiftUI
import Combine

/// UI-facing store for session list state.
/// Does not hold a database reference; receives updates from SessionEngine and loads via repository.
@MainActor
final class SessionStore: ObservableObject {

    @Published private(set) var recentSessions: [Session] = []
    @Published private(set) var selectedSession: Session?
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var loadError: Error?

    private var repository: SessionRepository?
    private(set) var recoveredSessionIds: Set<UUID> = []
    @Published private(set) var continueSession: Session?
    @Published private(set) var continueWorkflowThread: WorkflowThread?
    @Published private(set) var workflowThreads: [WorkflowThreadSummary] = []

    private var refreshTimer: AnyCancellable?

    var activeSession: Session? {
        recentSessions.first(where: \.isActive)
    }

    func isRecovered(_ sessionId: UUID) -> Bool {
        recoveredSessionIds.contains(sessionId)
    }

    func lifecycleState(for session: Session) -> SessionLifecycleState {
        if session.endedAt != nil {
            return session.lifecycleState == .archived ? .archived : .ended
        }
        if recoveredSessionIds.contains(session.id) {
            return .recovered
        }
        if session.lifecycleState == .paused { return .paused }
        if session.lifecycleState == .active { return .active }
        return session.lifecycleState
    }

    func setContinueWorkflowThread(_ thread: WorkflowThread?) {
        continueWorkflowThread = thread
    }

    func loadWorkflowThreads() async {
        guard let repository else { return }
        do {
            workflowThreads = try await repository.fetchWorkflowThreads()
            await refreshContinuationThread()
        } catch {
            loadError = error
        }
    }

    func fetchActivities(sessionId: UUID) async -> [ActivityEvent] {
        guard let repository else { return [] }
        return (try? await repository.fetchActivities(sessionId: sessionId)) ?? []
    }

    init() {
        startContinuationTimer()
    }

    func configure(repository: SessionRepository) {
        self.repository = repository
        Task {
            await refreshContinuationThread()
        }
    }

    func refreshContinuationThread() async {
        guard let repository else { return }
        do {
            let session = try await repository.fetchLatestEligibleSession()
            if let session, let threadId = session.workflowThreadId {
                if let thread = try await repository.fetchThread(id: threadId), thread.status != .archived {
                    if self.continueSession?.id != session.id || self.continueWorkflowThread?.id != thread.id || self.continueWorkflowThread?.lastActiveAt != thread.lastActiveAt {
                        self.continueSession = session
                        self.continueWorkflowThread = thread
                    }
                    return
                }
            }
            if self.continueSession != nil || self.continueWorkflowThread != nil {
                self.continueSession = nil
                self.continueWorkflowThread = nil
            }
        } catch {
            if self.continueSession != nil || self.continueWorkflowThread != nil {
                self.continueSession = nil
                self.continueWorkflowThread = nil
            }
        }
    }

    private func startContinuationTimer() {
        refreshTimer = Timer.publish(every: 15, on: .main, in: .default)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self = self else { return }
                Task {
                    await self.refreshContinuationThread()
                    self.objectWillChange.send()
                }
            }
    }

    func loadRecent() async {
        guard let repository else { return }
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do {
            async let sessions = repository.fetchRecent()
            async let threads = repository.fetchWorkflowThreads()
            recentSessions = try await sessions
            workflowThreads = try await threads
            await refreshContinuationThread()
        } catch {
            loadError = error
        }
    }

    func workflowThreadDidUpdate(_ thread: WorkflowThread) {
        if let idx = workflowThreads.firstIndex(where: { $0.id == thread.id }) {
            let summary = workflowThreads[idx]
            workflowThreads[idx] = WorkflowThreadSummary(thread: thread, segments: summary.segments)
        } else {
            workflowThreads.insert(WorkflowThreadSummary(thread: thread, segments: []), at: 0)
        }
    }

    func workflowThreadDidEnd(_ thread: WorkflowThread) {
        workflowThreadDidUpdate(thread)
    }

    func removeWorkflowThreadOptimistically(id: UUID) {
        workflowThreads.removeAll { $0.id == id }
        recentSessions.removeAll { $0.workflowThreadId == id }
        if continueWorkflowThread?.id == id {
            continueWorkflowThread = nil
            continueSession = nil
        }
    }

    func select(_ session: Session) { selectedSession = session }
    func deselect() { selectedSession = nil }

    func performSemanticSearch(query: String) async -> [SemanticSearchEngine.SearchResult] {
        guard let repository else { return [] }
        return await SemanticSearchEngine.shared.search(query: query, repository: repository)
    }

    func searchSessions(query: String, limit: Int = 30) async -> [Session] {
        guard let repository else { return [] }
        return (try? await repository.searchSessions(query: query, limit: limit)) ?? []
    }

    func searchWorkflowThreads(query: String, limit: Int = 30) async -> [WorkflowThreadSummary] {
        guard let repository else { return [] }
        return (try? await repository.searchWorkflowThreads(query: query, limit: limit)) ?? []
    }

    func fetchSessions(ids: [UUID]) async -> [Session] {
        guard let repository else { return [] }
        return (try? await repository.fetchSessions(ids: ids)) ?? []
    }

    func sessionDidStart(_ session: Session) {
        recentSessions.removeAll { $0.id == session.id }
        recentSessions.insert(session, at: 0)
    }

    func sessionDidResume(_ session: Session) {
        recoveredSessionIds.insert(session.id)
        recentSessions.removeAll { $0.id == session.id }
        recentSessions.insert(session, at: 0)
    }

    func sessionDidUpdate(_ session: Session) {
        if let idx = recentSessions.firstIndex(where: { $0.id == session.id }) {
            recentSessions[idx] = session
        }
    }

    func sessionDidEnd(_ session: Session) {
        recoveredSessionIds.remove(session.id)
        if let idx = recentSessions.firstIndex(where: { $0.id == session.id }) {
            recentSessions[idx] = session
        }
    }
}
