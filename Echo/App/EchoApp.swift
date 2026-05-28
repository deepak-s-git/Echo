import SwiftUI
import AppKit
import ServiceManagement

@main
struct EchoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var echoSettings = EchoSettings.shared

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
                .environmentObject(echoSettings)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .commands {
            EchoCommands()
        }

        // Settings window — opens with ⌘,
        Settings {
            SettingsView()
                .environmentObject(echoSettings)
                .environmentObject(appDelegate.permissionsManager)
        }

        MenuBarExtra {
            MenuBarView()
                .environmentObject(appDelegate.appStore)
                .environmentObject(appDelegate.sessionStore)
                .environmentObject(appDelegate.activityStore)
                .environmentObject(appDelegate.sessionControl)
                .environmentObject(echoSettings)
        } label: {
            MenuBarLabel()
        }
        .menuBarExtraStyle(.window)
    }
}
