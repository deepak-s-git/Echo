import SwiftUI
import AppKit

@main
struct EchoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appDelegate.appStore)
                .environmentObject(appDelegate.sessionStore)
                .environmentObject(appDelegate.activityStore)
                .environmentObject(appDelegate.permissionsManager)
                .environmentObject(appDelegate.sessionDetailStore)
                .environmentObject(appDelegate.continuityStore)
                .environmentObject(appDelegate.sessionControl)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .commands {
            EchoCommands()
        }

        MenuBarExtra {
            MenuBarView()
                .environmentObject(appDelegate.appStore)
                .environmentObject(appDelegate.sessionStore)
                .environmentObject(appDelegate.activityStore)
                .environmentObject(appDelegate.sessionControl)
        } label: {
            MenuBarLabel()
        }
        .menuBarExtraStyle(.window)
    }
}
