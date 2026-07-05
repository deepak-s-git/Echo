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
            ZStack {
                ContentView()
                    .id(echoSettings.accentVibe.rawValue + echoSettings.appTheme.rawValue)
                    .transition(.opacity)
            }
            .animation(.easeInOut(duration: 0.35), value: echoSettings.accentVibe.rawValue + echoSettings.appTheme.rawValue)
            .environmentObject(appDelegate.appStore)
                .environmentObject(appDelegate.sessionStore)
                .environmentObject(appDelegate.activityStore)
                .environmentObject(appDelegate.permissionsManager)
                .environmentObject(appDelegate.sessionDetailStore)
                .environmentObject(appDelegate.sessionControl)
                .environmentObject(echoSettings)
                .tint(EchoPalette.accent)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .commands {
            EchoCommands()
        }

        // Settings window — opens with ⌘,
        Settings {
            ZStack {
                SettingsView()
                    .id(echoSettings.accentVibe.rawValue + echoSettings.appTheme.rawValue)
                    .transition(.opacity)
            }
            .animation(.easeInOut(duration: 0.35), value: echoSettings.accentVibe.rawValue + echoSettings.appTheme.rawValue)
            .environmentObject(echoSettings)
                .environmentObject(appDelegate.permissionsManager)
                .environmentObject(appDelegate.appStore)
                .tint(EchoPalette.accent)
        }

        MenuBarExtra(isInserted: showInMenuBarBinding) {
            MenuBarView()
                .environmentObject(appDelegate.appStore)
                .environmentObject(appDelegate.sessionStore)
                .environmentObject(appDelegate.activityStore)
                .environmentObject(appDelegate.sessionControl)
                .environmentObject(echoSettings)
                .tint(EchoPalette.accent)
        } label: {
            MenuBarLabel()
        }
        .menuBarExtraStyle(.window)
    }
}

