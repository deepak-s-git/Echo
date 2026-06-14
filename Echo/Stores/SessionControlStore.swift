import SwiftUI
import Combine

@MainActor
final class SessionControlStore: ObservableObject {

    @Published private(set) var isReady = false

    private var container: ServiceContainer?

    func bind(container: ServiceContainer) {
        self.container = container
        isReady = true
    }

    func startNewSession(workflowName: String, appStore: AppStore) async {
        await container?.startNewSession(workflowName: workflowName)
        appStore.selectTab(.home)
    }

    func continuePreviousSession(appStore: AppStore) async {
        await container?.continuePreviousSession()
        appStore.selectTab(.home)
    }

    func continueWorkflowThread(id: UUID, appStore: AppStore) async {
        await container?.continueWorkflowThread(id: id)
        appStore.selectTab(.home)
    }

    func restoreAndContinueWorkflowThread(id: UUID, plan: WorkflowRestorePlan, appStore: AppStore) async {
        await container?.restoreAndContinue(id: id, plan: plan)
        appStore.selectTab(.home)
    }

    func pauseSession() async {
        await container?.pauseCurrentSession()
    }

    func resumeSession() async {
        await container?.resumeCurrentSession()
    }

    func requestEndSession(
        appStore: AppStore,
        activityStore: ActivityStore,
        sessionStore: SessionStore
    ) {
        if activityStore.currentSession == nil, activityStore.isRecording {
            Task { await container?.cancelRecording() }
            return
        }
        guard let session = activityStore.currentSession else { return }
        
        let suggested = SessionTitleGenerator.generate(from: activityStore.recentEvents, startedAt: session.startedAt)
        
        appStore.presentEndSession(SessionEndRequest(
            sessionId: session.id,
            suggestedTitle: suggested
        ))
    }

    func confirmEndSession(
        title: String,
        tags: [String],
        appStore: AppStore
    ) {
        appStore.dismissEndSession()
        appStore.popSessionDetail()
        appStore.selectTab(.home)
        appStore.finalizingToast = "Finalizing workflow…"
        Task {
            await container?.endCurrentSession(title: title, tags: tags)
            await MainActor.run {
                appStore.finalizingToast = nil
            }
        }
    }

    func deleteSession(id: UUID, appStore: AppStore) async {
        await container?.deleteSession(id: id)
        appStore.dismissEndSession()
        appStore.popSessionDetail()
    }

    func deleteSessions(ids: Set<UUID>, appStore: AppStore) async {
        for id in ids {
            await container?.deleteSession(id: id)
        }
        appStore.dismissEndSession()
        appStore.popSessionDetail()
    }

    func renameSession(id: UUID, title: String, tags: [String]) async {
        await container?.renameSession(id: id, title: title, tags: tags)
    }

    func deleteWorkflowThread(id: UUID, appStore: AppStore) async {
        await container?.deleteWorkflowThread(id: id)
        appStore.popSessionDetail()
    }

    func archiveWorkflowThread(id: UUID) async {
        await container?.archiveWorkflowThread(id: id)
    }

    func renameWorkflowThread(id: UUID, title: String, tags: [String]) async {
        await container?.renameWorkflowThread(id: id, title: title, tags: tags)
    }

    func clearAllData() async {
        await container?.clearAllData()
    }
}
