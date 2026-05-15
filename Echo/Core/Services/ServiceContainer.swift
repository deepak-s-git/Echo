import Foundation

/// Owns and wires all background services and stores.
/// AppDelegate holds one instance; SwiftUI views receive stores via @EnvironmentObject.
@MainActor
final class ServiceContainer {

    // MARK: - Stores (injected from AppDelegate)
    let appStore: AppStore
    let sessionStore: SessionStore
    let activityStore: ActivityStore
    let permissionsManager: PermissionsManager

    // MARK: - Services (private, internal to the container)
    private let database: DatabaseManager
    private let activityTracker: ActivityTracker
    private let sessionEngine: SessionEngine
    private let idleMonitor: IdleTimeMonitor

    // MARK: - Init

    init(
        appStore: AppStore,
        sessionStore: SessionStore,
        activityStore: ActivityStore,
        permissionsManager: PermissionsManager
    ) throws {
        let db = try DatabaseManager()
        let tracker = ActivityTracker()
        let idleMonitor = IdleTimeMonitor(threshold: EchoConfig.sessionIdleTimeout)

        let repo = SessionRepository(database: db)

        // Wire the repository into the session store now that DB is ready
        sessionStore.configure(repository: repo)

        let engine = SessionEngine(
            repository: repo,
            activityStore: activityStore,
            sessionStore: sessionStore,
            idleMonitor: idleMonitor
        )

        self.database = db
        self.activityTracker = tracker
        self.idleMonitor = idleMonitor
        self.appStore = appStore
        self.activityStore = activityStore
        self.sessionStore = sessionStore
        self.permissionsManager = permissionsManager
        self.sessionEngine = engine
    }

    // MARK: - Startup

    func start() async {
        await sessionEngine.configure(tracker: activityTracker)
        await activityTracker.start()
        await idleMonitor.start()
        await sessionEngine.start()
        await sessionStore.loadRecent()
        appStore.setReady()
    }

    // MARK: - Teardown

    func teardown() async {
        await sessionEngine.endCurrentSession(reason: .appTermination)
        await activityTracker.stop()
        await idleMonitor.stop()
    }
}
