import SwiftUI
import Combine

@MainActor
final class SessionDetailStore: ObservableObject {

    @Published private(set) var memory: WorkflowMemory?
    @Published private(set) var isLoading = false
    @Published private(set) var loadError: Error?
    @Published private(set) var isRestoring = false
    @Published private(set) var restoreMessage: String?

    private var repository: SessionRepository?
    private let restoreEngine = WorkflowRestoreEngine()

    func configure(repository: SessionRepository) {
        self.repository = repository
    }

    func load(sessionId: UUID) async {
        guard let repository else { return }
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do {
            memory = try await repository.loadWorkflowMemory(sessionId: sessionId)
        } catch {
            loadError = error
            memory = nil
        }
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
}
