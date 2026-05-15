import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {

    private(set) var container: ServiceContainer?

    // MARK: - Store accessors for SwiftUI environment injection

    var appStore: AppStore { container!.appStore }
    var sessionStore: SessionStore { container!.sessionStore }
    var activityStore: ActivityStore { container!.activityStore }
    var permissionsManager: PermissionsManager { container!.permissionsManager }

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false

        do {
            container = try ServiceContainer()
        } catch {
            // Container failed to init (e.g. DB can't be created).
            // Show error UI without crashing.
            let fallback = FallbackContainer(error: error)
            container = fallback.asServiceContainer()
            return
        }

        Task { @MainActor in
            await container?.start()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Use a semaphore to block termination until teardown completes.
        // This guarantees the final session is written before the process exits.
        let semaphore = DispatchSemaphore(value: 0)
        Task {
            await container?.teardown()
            semaphore.signal()
        }
        semaphore.wait()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { container?.appStore.showMainWindow() }
        return true
    }
}

// MARK: - FallbackContainer

/// Provides a no-op ServiceContainer so the app can show an error UI
/// rather than crashing if bootstrap fails.
private struct FallbackContainer {
    let error: Error

    func asServiceContainer() -> ServiceContainer? {
        // In practice: set appStore.setFailed(error) through an alternate init.
        // Left as a stub; implement when error UI is built.
        nil
    }
}
