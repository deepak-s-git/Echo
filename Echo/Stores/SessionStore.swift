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
    @Published private(set) var continueWorkflowThread: WorkflowThread?
    @Published private(set) var workflowThreads: [WorkflowThreadSummary] = []

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
        } catch {
            loadError = error
        }
    }

    init() {}

    func configure(repository: SessionRepository) {
        self.repository = repository
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
        continueWorkflowThread = thread
    }

    func removeWorkflowThreadOptimistically(id: UUID) {
        workflowThreads.removeAll { $0.id == id }
        recentSessions.removeAll { $0.workflowThreadId == id }
        if continueWorkflowThread?.id == id {
            continueWorkflowThread = nil
        }
    }

    func select(_ session: Session) { selectedSession = session }
    func deselect() { selectedSession = nil }

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
