import AppKit
import ApplicationServices

actor ActivityTracker {

    // MARK: - Public Stream

    private(set) var eventStream: AsyncStream<RawActivityEvent>?
    private var eventContinuation: AsyncStream<RawActivityEvent>.Continuation?

    // MARK: - State

    private var isRunning = false
    private var currentBundleId: String?
    private var appFocusStart: Date = Date()
    private var observerTokens: [NSObjectProtocol] = []
    private var pollTask: Task<Void, Never>?

    // MARK: - Constants

    private let pollInterval: TimeInterval = 3.0

    // MARK: - Lifecycle

    func start() {
        guard !isRunning else { return }
        isRunning = true

        let (stream, continuation) = AsyncStream<RawActivityEvent>.makeStream()
        eventStream = stream
        eventContinuation = continuation

        Task { @MainActor in await self.setupWorkspaceObservers() }
        startPolling()
    }

    func stop() {
        isRunning = false
        pollTask?.cancel()
        pollTask = nil
        eventContinuation?.finish()
        eventContinuation = nil
        eventStream = nil

        let tokens = observerTokens
        Task { @MainActor in
            let center = NSWorkspace.shared.notificationCenter
            tokens.forEach { center.removeObserver($0) }
        }
        observerTokens.removeAll()
    }

    // MARK: - Observer Registration

    @MainActor
    private func setupWorkspaceObservers() async {
        let center = NSWorkspace.shared.notificationCenter

        let activationToken = center.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                    as? NSRunningApplication
            else { return }
            let bundleId = app.bundleIdentifier ?? "unknown"
            let name = app.localizedName ?? "Unknown"
            let pid = app.processIdentifier
            Task { await self?.handleAppActivation(bundleId: bundleId, name: name, pid: pid) }
        }

        let terminationToken = center.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                    as? NSRunningApplication
            else { return }
            let bundleId = app.bundleIdentifier ?? "unknown"
            Task { await self?.handleAppTermination(bundleId: bundleId) }
        }

        await storeTokens([activationToken, terminationToken])
    }

    private func storeTokens(_ tokens: [NSObjectProtocol]) {
        observerTokens.append(contentsOf: tokens)
    }

    // MARK: - Polling

    private func startPolling() {
        pollTask = Task.detached(priority: .utility) { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(await self?.pollInterval ?? 3.0))
                let info: (String, String, pid_t)? = await MainActor.run {
                    guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
                    return (
                        app.bundleIdentifier ?? "unknown",
                        app.localizedName ?? "Unknown",
                        app.processIdentifier
                    )
                }
                if let (bundleId, name, pid) = info {
                    await self?.pollDidObserve(bundleId: bundleId, name: name, pid: pid)
                }
            }
        }
    }

    private func pollDidObserve(bundleId: String, name: String, pid: pid_t) {
        guard bundleId != currentBundleId else { return }
        recordTransition(bundleId: bundleId, name: name, pid: pid)
    }

    // MARK: - Event Handlers

    private func handleAppActivation(bundleId: String, name: String, pid: pid_t) {
        recordTransition(bundleId: bundleId, name: name, pid: pid)
    }

    private func handleAppTermination(bundleId: String) {
        guard bundleId == currentBundleId else { return }
        closeCurrentAppFocus(at: Date())
    }

    // MARK: - Transition Recording

    private func recordTransition(bundleId: String, name: String, pid: pid_t) {
        let now = Date()
        closeCurrentAppFocus(at: now)
        currentBundleId = bundleId
        appFocusStart = now

        emit(RawActivityEvent(
            id: UUID(),
            timestamp: now,
            type: .appFocus,
            appBundleId: bundleId,
            appName: name,
            windowTitle: nil,
            url: nil,
            duration: 0
        ))
    }

    private func closeCurrentAppFocus(at endTime: Date) {
        guard let bundleId = currentBundleId else { return }
        let duration = endTime.timeIntervalSince(appFocusStart)
        guard duration > 0.5 else { return }

        emit(RawActivityEvent(
            id: UUID(),
            timestamp: appFocusStart,
            type: .appSwitch,
            appBundleId: bundleId,
            appName: bundleId,
            windowTitle: nil,
            url: nil,
            duration: duration
        ))
    }

    // MARK: - Emit

    private func emit(_ event: RawActivityEvent) {
        eventContinuation?.yield(event)
    }
}
