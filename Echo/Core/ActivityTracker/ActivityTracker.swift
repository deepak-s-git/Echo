import AppKit
import ApplicationServices

/// Hybrid focus tracker: NSWorkspace notifications + fast frontmost-app verification.
actor ActivityTracker {

    // MARK: - Public Stream

    private(set) var eventStream: AsyncStream<RawActivityEvent>?
    private var eventContinuation: AsyncStream<RawActivityEvent>.Continuation?

    // MARK: - State

    private var isRunning = false
    private var capturePaused = false
    private var currentBundleId: String?
    private var currentAppName: String?
    private var appFocusStart: Date = Date()

    private var lastVerifiedSnapshot: FrontmostSnapshot?
    private var lastEmittedBundleId: String?
    private var lastEmittedWindowFingerprint: String = ""
    private var lastTransitionTime: Date = .distantPast
    private var lastWindowRecheckTime: Date = .distantPast

    private var pendingFocusEvent: RawActivityEvent?
    private var pendingFocusEmitTask: Task<Void, Never>?

    private var observerTokens: [NSObjectProtocol] = []
    private var verifyPollTask: Task<Void, Never>?
    private var enrichTask: Task<Void, Never>?

    // MARK: - Lifecycle

    func start() {
        guard !isRunning else { return }
        isRunning = true

        let (stream, continuation) = AsyncStream<RawActivityEvent>.makeStream()
        eventStream = stream
        eventContinuation = continuation

        Task { @MainActor in await self.setupWorkspaceObservers() }
        startVerificationPolling()
    }

    func setCapturePaused(_ paused: Bool) {
        capturePaused = paused
    }

    func stop() {
        isRunning = false
        verifyPollTask?.cancel()
        verifyPollTask = nil
        enrichTask?.cancel()
        enrichTask = nil
        pendingFocusEmitTask?.cancel()
        pendingFocusEmitTask = nil
        pendingFocusEvent = nil
        eventContinuation?.finish()
        eventContinuation = nil
        eventStream = nil

        let tokens = observerTokens
        Task { @MainActor in
            let center = NSWorkspace.shared.notificationCenter
            tokens.forEach { center.removeObserver($0) }
        }
        observerTokens.removeAll()
        lastVerifiedSnapshot = nil
    }

    // MARK: - Observers

    @MainActor
    private func setupWorkspaceObservers() async {
        let center = NSWorkspace.shared.notificationCenter

        let names: [NSNotification.Name] = [
            NSWorkspace.didActivateApplicationNotification,
            NSWorkspace.didDeactivateApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification,
            NSWorkspace.didHideApplicationNotification,
            NSWorkspace.didUnhideApplicationNotification
        ]

        var tokens: [NSObjectProtocol] = []
        for name in names {
            let token = center.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                Task { await self?.handleWorkspaceNotification(name, notification) }
            }
            tokens.append(token)
        }

        await storeTokens(tokens)
    }

    private func storeTokens(_ tokens: [NSObjectProtocol]) {
        observerTokens.append(contentsOf: tokens)
    }

    private func handleWorkspaceNotification(
        _ name: NSNotification.Name,
        _ notification: Notification
    ) async {
        switch name {
        case NSWorkspace.didTerminateApplicationNotification:
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                    as? NSRunningApplication,
                  let bundleId = app.bundleIdentifier
            else { return }
            handleAppTermination(bundleId: bundleId)

        case NSWorkspace.didDeactivateApplicationNotification:
            // Prompt verification — Spaces swipes often skip activate on the outgoing app.
            await verifyFrontmostFocus(includeWindow: false)

        default:
            await verifyFrontmostFocus(includeWindow: false)
        }
    }

    // MARK: - Verification polling

    private func startVerificationPolling() {
        let interval = EchoConfig.trackerVerifyInterval
        verifyPollTask = Task.detached(priority: .utility) { [weak self] in
            var tick = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled else { break }
                tick += 1
                // AX window title every ~0.5s; app-only checks every 200ms.
                let windowEvery = max(
                    1,
                    Int((EchoConfig.trackerWindowRecheckInterval / EchoConfig.trackerVerifyInterval).rounded())
                )
                let includeWindow = tick % windowEvery == 0
                await self?.verifyFrontmostFocus(includeWindow: includeWindow)
            }
        }
    }

    /// Single reconciliation entry point for notifications and polling.
    private func verifyFrontmostFocus(includeWindow: Bool) async {
        guard isRunning, !capturePaused else { return }

        let snapshot = await MainActor.run {
            includeWindow ? FrontmostSnapshot.captureWithWindow() : FrontmostSnapshot.captureAppOnly()
        }
        guard let snapshot else { return }

        if let last = lastVerifiedSnapshot, last == snapshot {
            return
        }
        lastVerifiedSnapshot = snapshot

        // Skip ignored apps
        let ignoredIds = await MainActor.run { EchoSettings.shared.ignoredBundleIds }
        let isEcho = snapshot.bundleId == (Bundle.main.bundleIdentifier ?? "com.deepaks.EchoTest2")
        if ignoredIds.contains(snapshot.bundleId) || isEcho {
            closeCurrentAppFocus(at: Date())
            return
        }

        if snapshot.bundleId == currentBundleId {
            await handleSameAppWindowChange(snapshot)
            return
        }

        guard !shouldSkipDuplicateTransition(to: snapshot.bundleId) else { return }

        await recordTransition(
            bundleId: snapshot.bundleId,
            name: snapshot.displayName,
            initialWindowTitle: snapshot.windowTitle,
            initialDocumentURL: snapshot.documentURL
        )
    }

    private func handleSameAppWindowChange(_ snapshot: FrontmostSnapshot) async {
        let fingerprint = snapshot.windowFingerprint
        guard !fingerprint.isEmpty else { return }
        guard fingerprint != lastEmittedWindowFingerprint else { return }

        let now = Date()
        guard now.timeIntervalSince(lastWindowRecheckTime) >= EchoConfig.trackerMinTransitionInterval
        else { return }
        lastWindowRecheckTime = now
        
        if let pending = pendingFocusEvent {
            pendingFocusEvent = RawActivityEvent(
                id: pending.id,
                timestamp: pending.timestamp,
                type: pending.type,
                appBundleId: pending.appBundleId,
                appName: pending.appName,
                windowTitle: snapshot.windowTitle,
                url: snapshot.documentURL,
                profileName: pending.profileName,
                duration: pending.duration
            )
            lastEmittedWindowFingerprint = fingerprint
            return
        }
        
        lastEmittedWindowFingerprint = fingerprint

        guard let bundleId = currentBundleId, let name = currentAppName else { return }

        // For browsers: schedule AppleScript enrichment to capture the actual URL.
        // For document apps that expose kAXDocument: emit immediately with the file URL.
        // For all other apps: emit with window title as-is.
        if BrowserContextService.isBrowser(bundleId) {
            // Emit a placeholder immediately so the UI updates fast, then enrich with URL.
            emit(RawActivityEvent(
                id: UUID(), timestamp: now, type: .appFocus,
                appBundleId: bundleId, appName: name,
                windowTitle: snapshot.windowTitle, url: nil,
                profileName: nil, duration: 0
            ))
            scheduleWindowEnrichment(bundleId: bundleId, name: name, timestamp: now)
        } else {
            emit(RawActivityEvent(
                id: UUID(), timestamp: now, type: .appFocus,
                appBundleId: bundleId, appName: name,
                windowTitle: snapshot.windowTitle,
                url: snapshot.documentURL,   // populated by kAXDocument in captureWithWindow()
                profileName: nil,
                duration: 0
            ))
        }
    }

    private func shouldSkipDuplicateTransition(to bundleId: String) -> Bool {
        let now = Date()
        defer {
            lastTransitionTime = now
            lastEmittedBundleId = bundleId
        }
        guard bundleId == lastEmittedBundleId else { return false }
        return now.timeIntervalSince(lastTransitionTime) < EchoConfig.trackerMinTransitionInterval
    }

    // MARK: - Termination

    private func handleAppTermination(bundleId: String) {
        guard bundleId == currentBundleId else { return }
        closeCurrentAppFocus(at: Date())
        lastVerifiedSnapshot = nil
    }

    // MARK: - Transition Recording

    private func recordTransition(
        bundleId: String,
        name: String,
        initialWindowTitle: String?,
        initialDocumentURL: String? = nil
    ) async {
        guard bundleId != currentBundleId else { return }

        let now = Date()

        closeCurrentAppFocus(at: now)
        currentBundleId = bundleId
        currentAppName = name
        appFocusStart = now
        lastEmittedWindowFingerprint = initialDocumentURL ?? initialWindowTitle ?? ""

        let focusEvent = RawActivityEvent(
            id: UUID(),
            timestamp: now,
            type: .appFocus,
            appBundleId: bundleId,
            appName: name,
            windowTitle: initialWindowTitle,
            url: initialDocumentURL,
            profileName: nil,
            duration: 0
        )

        pendingFocusEvent = focusEvent
        pendingFocusEmitTask?.cancel()

        let delaySeconds = await MainActor.run {
            let isBrowser = BrowserContextService.isBrowser(bundleId)
            if isBrowser {
                return EchoSettings.shared.browserCaptureDelaySeconds + EchoSettings.shared.tabEligibilitySeconds
            } else {
                return EchoSettings.shared.appFocusEligibilitySeconds
            }
        }

        pendingFocusEmitTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delaySeconds))
            guard !Task.isCancelled else { return }
            await self?.emitPendingFocusEvent(matching: bundleId)
        }
    }

    private func emitPendingFocusEvent(matching bundleId: String) {
        guard let event = pendingFocusEvent, event.appBundleId == bundleId else { return }
        pendingFocusEvent = nil
        emit(event)

        scheduleWindowEnrichment(
            bundleId: event.appBundleId,
            name: event.appName,
            timestamp: event.timestamp
        )
    }

    /// Enriches a focus event with URL context after a short delay.
    /// • Browsers  → AppleScript active tab (URL + page title)
    /// • Doc apps  → kAXDocument file URL + cleaned window title
    /// • Other     → plain window title from AX
    private func scheduleWindowEnrichment(bundleId: String, name: String, timestamp: Date) {
        enrichTask?.cancel()
        enrichTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            guard await self?.currentBundleId == bundleId else { return }

            if BrowserContextService.isBrowser(bundleId) {
                // AppleScript: synchronous but fast (~5–20 ms). Run on main actor per existing API.
                var tab: BrowserTab? = nil
                for delayMs in [0, 300, 800, 1500] {
                    if delayMs > 0 {
                        try? await Task.sleep(for: .milliseconds(delayMs))
                    }
                    guard !Task.isCancelled else { return }
                    guard await self?.currentBundleId == bundleId else { return }
                    
                    tab = await MainActor.run {
                        BrowserContextService.captureActiveTab(for: bundleId)
                    }
                    if tab != nil { break }
                }
                guard let tab else { return }
                guard await self?.currentBundleId == bundleId else { return }
                let title = tab.title.isEmpty ? nil : tab.title
                let url   = tab.url.isEmpty   ? nil : tab.url
                await self?.emit(RawActivityEvent(
                    id: UUID(), timestamp: timestamp, type: .appFocus,
                    appBundleId: bundleId, appName: name,
                    windowTitle: title, url: url,
                    profileName: tab.profileName, duration: 0
                ))
                await self?.updateLastEmittedWindowFingerprint(url ?? title ?? "")
            } else {
                // AX: get window title + kAXDocument in one call.
                let ctx = await MainActor.run {
                    WindowContextCapture.focusedWindowContext()
                }
                let title = ctx.title
                let docURL = ctx.documentURL
                guard title != nil || docURL != nil else { return }
                guard await self?.currentBundleId == bundleId else { return }
                await self?.emit(RawActivityEvent(
                    id: UUID(), timestamp: timestamp, type: .appFocus,
                    appBundleId: bundleId, appName: name,
                    windowTitle: title, url: docURL,
                    profileName: nil, duration: 0
                ))
                await self?.updateLastEmittedWindowFingerprint(docURL ?? title ?? "")
            }
        }
    }

    private func updateLastEmittedWindowFingerprint(_ title: String) {
        lastEmittedWindowFingerprint = title
        if let snap = lastVerifiedSnapshot, snap.bundleId == currentBundleId {
            lastVerifiedSnapshot = FrontmostSnapshot(
                bundleId: snap.bundleId,
                displayName: snap.displayName,
                pid: snap.pid,
                windowTitle: title,
                documentURL: snap.documentURL
            )
        }
    }

    private func closeCurrentAppFocus(at endTime: Date) {
        guard let bundleId = currentBundleId else { return }

        pendingFocusEmitTask?.cancel()
        pendingFocusEmitTask = nil

        if pendingFocusEvent != nil {
            pendingFocusEvent = nil
            currentBundleId = nil
            currentAppName = nil
            return
        }

        let duration = endTime.timeIntervalSince(appFocusStart)
        guard duration > 0.5 else { return }

        let name = currentAppName ?? AppMetadataResolver.humanizedBundleId(bundleId)

        emit(RawActivityEvent(
            id: UUID(),
            timestamp: appFocusStart,
            type: .appSwitch,
            appBundleId: bundleId,
            appName: name,
            windowTitle: nil,
            url: nil,
            profileName: nil,
            duration: duration
        ))

        currentBundleId = nil
        currentAppName = nil
    }

    // MARK: - Emit

    private func emit(_ event: RawActivityEvent) {
        eventContinuation?.yield(event)
    }
}
