import SwiftUI

struct EchoCommands: Commands {
    var body: some Commands {
        CommandGroup(replacing: .newItem) {}

        CommandMenu("Echo") {
            Button("Search Sessions") {
                NotificationCenter.default.post(name: .echoOpenSearch, object: nil)
            }
            .keyboardShortcut("k", modifiers: [.command, .shift])

            Divider()

            Button("Save Snapshot") {
                NotificationCenter.default.post(name: .echoSaveSnapshot, object: nil)
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])
        }
    }
}

extension Notification.Name {
    nonisolated static let echoOpenSearch = Notification.Name("echo.openSearch")
    nonisolated static let echoSaveSnapshot = Notification.Name("echo.saveSnapshot")
    nonisolated static let echoSessionCreated = Notification.Name("echo.sessionCreated")
    nonisolated static let echoActivityRecorded = Notification.Name("echo.activityRecorded")
    nonisolated static let echoActivitiesPersisted = Notification.Name("echo.activitiesPersisted")
}
