import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appStore: AppStore
    @EnvironmentObject var permissionsManager: PermissionsManager

    var body: some View {
        ZStack {
            switch appStore.state {
            case .launching:
                LaunchView()
                    .transition(.opacity)
            case .ready:
                ZStack {
                    Color(red: 0.05, green: 0.05, blue: 0.055)
                        .ignoresSafeArea()
                    
                    ZStack {
                        if appStore.isOnboardingPresented {
                            OnboardingView()
                                .transition(.opacity.combined(with: .scale(scale: 0.98)))
                        } else if !permissionsManager.allGranted {
                            PermissionsView()
                                .transition(.opacity.combined(with: .scale(scale: 1.02)))
                        } else {
                            MainNavigationView()
                                .transition(.opacity)
                        }
                    }
                    .animation(.spring(response: 0.7, dampingFraction: 0.82), value: appStore.isOnboardingPresented)
                    .animation(.spring(response: 0.7, dampingFraction: 0.82), value: permissionsManager.allGranted)
                }
            case .failed(let error):
                ErrorView(error: error)
                    .transition(.opacity)
            }
        }
        .frame(minWidth: 900, maxWidth: 900, minHeight: 620, maxHeight: 620)
        .background(.clear)
        .onReceive(NotificationCenter.default.publisher(for: .echoOpenSearch)) { _ in
            appStore.selectedTab = .search
            appStore.isSearchPresented = true
        }
    }
}
