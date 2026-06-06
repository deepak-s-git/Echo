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

    func startNewSession() async {
        await container?.startNewSession()
    }

    func continuePreviousSession() async {
        await container?.continuePreviousSession()
    }

    func continueWorkflowThread(id: UUID) async {
        await container?.continueWorkflowThread(id: id)
    }

    func pauseSession() async {
        await container?.pauseCurrentSession()
    }

    func resumeSession() async {
        await container?.resumeCurrentSession()
    }

    func requestEndSession(
        appStore: AppStore,
        activityStore: ActivityStore
    ) {
        if activityStore.currentSession == nil, activityStore.isRecording {
            Task { await container?.cancelRecording() }
            return
        }
        guard let session = activityStore.currentSession else { return }
        let suggested = activityStore.workflowIdentity
        appStore.presentEndSession(SessionEndRequest(
            sessionId: session.id,
            suggestedTitle: suggested == "Your workflow"
                ? (session.title ?? "Untitled memory")
                : suggested
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
        appStore.dismissEndSession()
        await container?.deleteSession(id: id)
        appStore.popSessionDetail()
    }

    func renameSession(id: UUID, title: String, tags: [String]) async {
        await container?.renameSession(id: id, title: title, tags: tags)
    }

    func deleteWorkflowThread(id: UUID, appStore: AppStore) async {
        appStore.popSessionDetail()
        await container?.deleteWorkflowThread(id: id)
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
