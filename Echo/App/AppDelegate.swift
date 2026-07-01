import AppKit
import Sparkle

final class AppDelegate: NSObject, NSApplicationDelegate {

    static private(set) var shared: AppDelegate?

    override init() {
        super.init()
        AppDelegate.shared = self
    }

    // MARK: - Sparkle Updater
    var updaterController: SPUStandardUpdaterController?

    // MARK: - Stores (created eagerly so SwiftUI can access them immediately)

    let appStore = AppStore()
    let sessionStore = SessionStore()
    let activityStore = ActivityStore()
    let permissionsManager = PermissionsManager()
    let sessionDetailStore = SessionDetailStore()
    let sessionControl = SessionControlStore()

    // MARK: - Container

    private var container: ServiceContainer?

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false

        print("[Echo] AppDelegate: initializing SPUStandardUpdaterController")
        updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        print("[Echo] AppDelegate: updaterController is \(String(describing: updaterController))")

        do {
            container = try ServiceContainer(
                appStore: appStore,
                sessionStore: sessionStore,
                activityStore: activityStore,
                permissionsManager: permissionsManager,
                sessionDetailStore: sessionDetailStore,
                sessionControl: sessionControl
            )
        } catch {
            // Container failed to init (e.g. DB can't be created).
            // Show error UI without crashing.
            appStore.setFailed(error)
            return
        }

        // Trigger AppleScript prompt on launch synchronously
        let triggerScript = NSAppleScript(source: "tell application \"Google Chrome\" to return 1")
        var errorInfo: NSDictionary?
        triggerScript?.executeAndReturnError(&errorInfo)
        if let error = errorInfo {
            print("AppleScript Trigger Error: \(error)")
        }

        Task { @MainActor in
            await container?.start()
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Task {
            await container?.teardown()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { appStore.showMainWindow() }
        return true
    }
}
