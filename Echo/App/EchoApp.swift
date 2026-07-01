import SwiftUI
import AppKit
import ServiceManagement

@main
struct EchoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var echoSettings = EchoSettings.shared

    private var showInMenuBarBinding: Binding<Bool> {
        Binding<Bool>(
            get: { echoSettings.showInMenuBar },
            set: { newValue in
                if echoSettings.showInMenuBar != newValue {
                    DispatchQueue.main.async {
                        echoSettings.showInMenuBar = newValue
                    }
                }
            }
        )
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appDelegate.appStore)
                .environmentObject(appDelegate.sessionStore)
                .environmentObject(appDelegate.activityStore)
                .environmentObject(appDelegate.permissionsManager)
                .environmentObject(appDelegate.sessionDetailStore)
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
                .environmentObject(appDelegate.appStore)
        }

        MenuBarExtra(isInserted: showInMenuBarBinding) {
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

