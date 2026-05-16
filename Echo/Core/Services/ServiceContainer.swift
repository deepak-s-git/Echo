import Foundation

@MainActor
final class ServiceContainer {

    let appStore: AppStore
    let sessionStore: SessionStore
    let activityStore: ActivityStore
    let permissionsManager: PermissionsManager
    let sessionDetailStore: SessionDetailStore
    let continuityStore: ContinuityStore

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
        continuityStore: ContinuityStore
    ) throws {
        let db = try DatabaseManager()
        let tracker = ActivityTracker()
        let idleMonitor = IdleTimeMonitor(threshold: EchoConfig.sessionIdleTimeout)
        let repo = SessionRepository(database: db)

        sessionStore.configure(repository: repo)
        sessionDetailStore.configure(repository: repo)
        continuityStore.configure(repository: repo)

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
        self.continuityStore = continuityStore
        self.sessionEngine = engine
    }

    func start() async {
        await activityTracker.start()
        await sessionEngine.configure(tracker: activityTracker)
        await idleMonitor.start()
        await sessionEngine.start()
        await sessionStore.loadRecent()
        await continuityStore.refresh(
            activeSession: sessionStore.activeSession,
            recent: sessionStore.recentSessions
        )
        appStore.setReady()
    }

    func teardown() async {
        await sessionEngine.endCurrentSession(reason: .appTermination)
        await activityTracker.stop()
        await idleMonitor.stop()
    }

    func repository() -> SessionRepository { sessionRepository }
}
