import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appStore: AppStore
    @EnvironmentObject var permissionsManager: PermissionsManager

    var body: some View {
        Group {
            switch appStore.state {
            case .launching:
                LaunchView()
            case .ready:
                if appStore.isOnboardingPresented {
                    OnboardingView()
                } else if !permissionsManager.allGranted {
                    PermissionsView()
                } else {
                    MainNavigationView()
                }
            case .failed(let error):
                ErrorView(error: error)
            }
        }
        .frame(minWidth: 900, minHeight: 620)
        .background(.clear)
    }
}
