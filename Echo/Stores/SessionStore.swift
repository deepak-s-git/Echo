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

    private let continuationKey = "echo.latestContinuationCandidate"
    private var refreshTimer: AnyCancellable?

    struct ContinuationCandidate: Codable {
        let threadId: UUID
        let title: String
        let endTime: Date
        let expirationTime: Date
    }

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

    init() {
        startContinuationTimer()
    }

    func configure(repository: SessionRepository) {
        self.repository = repository
        Task {
            await refreshContinuationThread()
        }
    }

    func saveContinuationCandidate(threadId: UUID, title: String, endTime: Date) {
        let expirationTime = endTime.addingTimeInterval(60 * 60) // 60 minutes
        let candidate = ContinuationCandidate(
            threadId: threadId,
            title: title,
            endTime: endTime,
            expirationTime: expirationTime
        )
        if let data = try? JSONEncoder().encode(candidate) {
            UserDefaults.standard.set(data, forKey: continuationKey)
        }
        Task {
            await refreshContinuationThread()
        }
    }

    func clearContinuationCandidate() {
        UserDefaults.standard.removeObject(forKey: continuationKey)
        continueWorkflowThread = nil
    }

    func loadContinuationCandidate() -> ContinuationCandidate? {
        guard let data = UserDefaults.standard.data(forKey: continuationKey),
              let candidate = try? JSONDecoder().decode(ContinuationCandidate.self, from: data) else {
            return nil
        }
        return candidate
    }

    func getActiveContinuationThread() async -> WorkflowThread? {
        guard let candidate = loadContinuationCandidate() else { return nil }
        
        // 1. Check expiration time
        guard Date() < candidate.expirationTime else {
            clearContinuationCandidate()
            return nil
        }
        
        // 2. Fetch the thread from the repository to verify it still exists and is not archived
        guard let repository else { return nil }
        do {
            if let thread = try await repository.fetchThread(id: candidate.threadId) {
                if thread.status == .archived {
                    return nil
                }
                // Check if it still has at least one ended segment in the database
                if let _ = try await repository.fetchLastEndedSegment(threadId: thread.id) {
                    return thread
                }
            }
        } catch {
            return nil
        }
        
        return nil
    }

    func refreshContinuationThread() async {
        let thread = await getActiveContinuationThread()
        if continueWorkflowThread?.id != thread?.id || continueWorkflowThread?.title != thread?.title || continueWorkflowThread?.lastActiveAt != thread?.lastActiveAt {
            continueWorkflowThread = thread
        }
    }

    private func startContinuationTimer() {
        refreshTimer = Timer.publish(every: 15, on: .main, in: .common)
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
        saveContinuationCandidate(
            threadId: thread.id,
            title: thread.title ?? "Untitled workflow",
            endTime: thread.lastActiveAt
        )
    }

    func removeWorkflowThreadOptimistically(id: UUID) {
        workflowThreads.removeAll { $0.id == id }
        recentSessions.removeAll { $0.workflowThreadId == id }
        if continueWorkflowThread?.id == id {
            continueWorkflowThread = nil
        }
        let candidate = loadContinuationCandidate()
        if candidate?.threadId == id {
            clearContinuationCandidate()
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
