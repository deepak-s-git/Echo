import SwiftUI
import Combine

@MainActor
final class AppStore: ObservableObject {

    enum AppState {
        case launching
        case ready
        case failed(Error)
    }

    enum NavigationTab: String, CaseIterable {
        case home, timeline, search
    }

    @Published private(set) var state: AppState = .launching
    @Published var selectedTab: NavigationTab = .home
    @Published var isSearchPresented: Bool = false
    @Published var isOnboardingPresented: Bool = false

    /// Timeline detail — replaces list content only (no NavigationStack trap).
    @Published var timelineDetailSessionId: UUID?

    @Published var pendingSessionEnd: SessionEndRequest?
    @Published var renameSessionDraft: SessionRenameDraft?
    @Published var renameThreadDraft: WorkflowThreadRenameDraft?
    @Published var finalizingToast: String?

    init() {
        isOnboardingPresented = !UserDefaults.standard.bool(forKey: "echo.onboardingComplete")
    }

    func setReady() { state = .ready }
    func setFailed(_ error: Error) { state = .failed(error) }

    func showMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first?.makeKeyAndOrderFront(nil)
    }

    func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: "echo.onboardingComplete")
        isOnboardingPresented = false
    }

    func selectTab(_ tab: NavigationTab) {
        if tab != .timeline || selectedTab == .timeline {
            timelineDetailSessionId = nil
        }
        selectedTab = tab
    }

    func openSessionDetail(_ sessionId: UUID) {
        selectedTab = .timeline
        timelineDetailSessionId = sessionId
    }

    func popSessionDetail() {
        timelineDetailSessionId = nil
    }

    func presentEndSession(_ request: SessionEndRequest) {
        pendingSessionEnd = request
    }

    func dismissEndSession() {
        pendingSessionEnd = nil
    }
}

struct SessionEndRequest: Identifiable {
    let id = UUID()
    let sessionId: UUID
    let suggestedTitle: String
}

struct SessionRenameDraft: Identifiable {
    let sessionId: UUID
    var title: String
    var tags: [String]

    var id: UUID { sessionId }
}

struct WorkflowThreadRenameDraft: Identifiable {
    let threadId: UUID
    var title: String
    var tags: [String]

    var id: UUID { threadId }
}
