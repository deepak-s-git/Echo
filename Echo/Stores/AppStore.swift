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
    @Published var selectedSessionId: UUID?
    @Published var showingSessionDetail: Bool = false

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

    func openSessionDetail(_ sessionId: UUID) {
        selectedSessionId = sessionId
        showingSessionDetail = true
        selectedTab = .timeline
    }

    func closeSessionDetail() {
        showingSessionDetail = false
        selectedSessionId = nil
    }
}
