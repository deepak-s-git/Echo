import Foundation

@MainActor
enum WorkflowRestoreRunner {
    static func restore(plan: WorkflowRestorePlan) async -> RestoreResult {
        await WorkflowRestoreEngine().restore(plan: plan)
    }
}
