import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appStore: AppStore
    @EnvironmentObject var permissionsManager: PermissionsManager
    @EnvironmentObject var settings: EchoSettings

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
                                .transition(
                                    .asymmetric(
                                        insertion: .opacity.combined(with: .scale(scale: 0.98)),
                                        removal: .opacity
                                            .combined(with: .scale(scale: 1.05))
                                            .combined(with: .offset(y: -20))
                                    )
                                )
                                .zIndex(3)
                        } else if !permissionsManager.allGranted {
                            PermissionsView()
                                .transition(
                                    .asymmetric(
                                        insertion: .opacity
                                            .combined(with: .scale(scale: 1.05))
                                            .combined(with: .offset(y: -20)),
                                        removal: .opacity
                                            .combined(with: .scale(scale: 0.95))
                                            .combined(with: .offset(y: 20))
                                    )
                                )
                                .zIndex(2)
                        } else {
                            MainNavigationView()
                                .transition(
                                    .asymmetric(
                                        insertion: .opacity
                                            .combined(with: .scale(scale: 0.92))
                                            .combined(with: .offset(y: 24)),
                                        removal: .opacity
                                            .combined(with: .scale(scale: 1.05))
                                            .combined(with: .offset(y: -24))
                                    )
                                )
                                .zIndex(1)
                        }
                    }
                    .animation(.spring(response: 0.65, dampingFraction: 0.88), value: appStore.isOnboardingPresented)
                    .animation(.spring(response: 0.65, dampingFraction: 0.88), value: permissionsManager.allGranted)
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
