import Foundation

@MainActor
final class ServiceContainer {

    let appStore: AppStore
    let sessionStore: SessionStore
    let activityStore: ActivityStore
    let permissionsManager: PermissionsManager
    let sessionDetailStore: SessionDetailStore
    let sessionControl: SessionControlStore

    private let database: DatabaseManager
    private let sessionRepository: SessionRepository
    private let activityTracker: ActivityTracker
    private let sessionEngine: SessionEngine
    private let idleMonitor: IdleTimeMonitor

    let restoreEngine = WorkflowRestoreEngine()

    init(
        appStore: AppStore,
        sessionStore: SessionStore,
        activityStore: ActivityStore,
        permissionsManager: PermissionsManager,
        sessionDetailStore: SessionDetailStore,
        sessionControl: SessionControlStore
    ) throws {
        let db = try DatabaseManager()
        let tracker = ActivityTracker()
        let idleMonitor = IdleTimeMonitor(threshold: EchoConfig.sessionIdleTimeout)
        let repo = SessionRepository(database: db)

        sessionStore.configure(repository: repo)
        sessionDetailStore.configure(
            repository: repo,
            sessionStore: sessionStore,
            activityStore: activityStore
        )


        let engine = SessionEngine(
            repository: repo,
            activityStore: activityStore,
            sessionStore: sessionStore,
            idleMonitor: idleMonitor
        )

        self.database = db
        self.sessionRepository = repo
        self.activityTracker = tracker
        self.idleMonitor = idleMonitor
        self.appStore = appStore
        self.activityStore = activityStore
        self.sessionStore = sessionStore
        self.permissionsManager = permissionsManager
        self.sessionDetailStore = sessionDetailStore

        self.sessionControl = sessionControl
        self.sessionEngine = engine
        sessionControl.bind(container: self)

        NotificationCenter.default.addObserver(
            forName: .echoSessionFinalized,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.sessionStore.loadRecent()
            }
        }

        NotificationCenter.default.addObserver(
            forName: .echoClearAllData,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.clearAllData()
            }
        }
    }

    func cancelRecording() async {
        await sessionEngine.cancelRecording()
    }

    func startNewSession(workflowName: String) async {
        await sessionEngine.startNewSession(workflowName: workflowName)
        await sessionStore.loadRecent()
    }

    func continuePreviousSession() async {
        await sessionEngine.continuePreviousSession()
        await sessionStore.loadRecent()
    }

    func continueWorkflowThread(id: UUID) async {
        await sessionEngine.continueWorkflowThread(id: id)
        await sessionStore.loadRecent()
    }

    func restoreAndContinue(id: UUID, plan: WorkflowRestorePlan) async {
        await sessionEngine.restoreAndContinueWorkflowThread(id: id, plan: plan)
        await sessionStore.loadRecent()
    }

    func pauseCurrentSession() async {
        await sessionEngine.pauseSession()
    }

    func resumeCurrentSession() async {
        await sessionEngine.resumeSession()
    }

    func endCurrentSession(title: String, tags: [String]) async {
        await sessionEngine.endCurrentSession(
            reason: .userInitiated,
            title: title,
            tags: tags
        )
        await sessionStore.loadRecent()
    }

    func deleteSession(id: UUID) async {
        await sessionEngine.deleteSession(id: id)
        await sessionStore.loadRecent()
    }

    func renameSession(id: UUID, title: String, tags: [String]) async {
        try? await sessionRepository.updateMetadata(
            sessionId: id,
            title: title,
            tags: tags
        )
        await sessionStore.loadRecent()
    }

    func deleteWorkflowThread(id: UUID) async {
        await MainActor.run { sessionStore.removeWorkflowThreadOptimistically(id: id) }
        await sessionEngine.deleteWorkflowThread(id: id)
        await sessionStore.loadRecent()
    }

    func archiveWorkflowThread(id: UUID) async {
        await sessionEngine.archiveWorkflowThread(id: id)
        await sessionStore.loadRecent()
    }

    func unarchiveWorkflowThread(id: UUID) async {
        await sessionEngine.unarchiveWorkflowThread(id: id)
        await sessionStore.loadRecent()
    }

    func renameWorkflowThread(id: UUID, title: String, tags: [String]) async {
        try? await sessionRepository.updateThreadMetadata(
            threadId: id,
            title: title,
            tags: tags
        )
        await sessionStore.loadRecent()
    }

    func start() async {
        await activityTracker.start()
        await sessionEngine.configure(tracker: activityTracker)
        await idleMonitor.start()
        await sessionEngine.start()
        await sessionStore.loadRecent()
        
        let repo = self.sessionRepository
        Task(priority: .utility) {
            await SemanticSearchEngine.shared.indexPendingSessions(repository: repo)
        }
        
        appStore.setReady()
    }

    func teardown() async {
        await sessionEngine.endIfRecording(reason: .appTermination)
        await activityTracker.stop()
        await idleMonitor.stop()
    }

    func clearAllData() async {
        // End any running session first
        await sessionEngine.endIfRecording(reason: .userInitiated)
        // Wipe all DB tables
        try? await sessionRepository.clearAll()
        // Reset UI stores
        activityStore.enterIdleMode()
        await sessionStore.loadRecent()
    }

    func repository() -> SessionRepository { sessionRepository }
}
