import SwiftUI

struct QuitSessionAppsSheet: View {
    let request: QuitAppsRequest
    @EnvironmentObject var appStore: AppStore
    
    @State private var selectedApps: Set<String> = []
    @State private var isQuitting = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Quit Session Apps")
                .font(.system(size: 18, weight: .semibold))
            
            Text("Select the apps you want to quit to clear your workspace.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(request.apps) { appInfo in
                        Toggle(isOn: Binding(
                            get: { selectedApps.contains(appInfo.bundleIdentifier) },
                            set: { isOn in
                                if isOn {
                                    selectedApps.insert(appInfo.bundleIdentifier)
                                } else {
                                    selectedApps.remove(appInfo.bundleIdentifier)
                                }
                            }
                        )) {
                            Text(appInfo.appName)
                                .font(.system(size: 14))
                        }
                    }
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 4)
            }
            .frame(maxHeight: 200)
            .padding(12)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            
            HStack {
                Button(selectedApps.count == request.apps.count ? "Deselect All" : "Select All") {
                    if selectedApps.count == request.apps.count {
                        selectedApps.removeAll()
                    } else {
                        selectedApps = Set(request.apps.map { $0.bundleIdentifier })
                    }
                }
                
                Spacer()
                
                Button("Done") {
                    appStore.pendingQuitAppsRequest = nil
                }
                .keyboardShortcut(.cancelAction)
                .disabled(isQuitting)
                
                Button("Quit Selected") {
                    quitApps()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .tint(EchoPalette.accent)
                .disabled(selectedApps.isEmpty || isQuitting)
            }
        }
        .padding(24)
        .frame(width: 440)
        .onAppear {
            selectedApps = Set(request.apps.map { $0.bundleIdentifier })
        }
    }
    
    private func quitApps() {
        isQuitting = true
        let appsToQuit = Array(selectedApps)
        Task {
            await AppQuitter.safelyQuitApps(bundleIdentifiers: appsToQuit)
            await MainActor.run {
                appStore.pendingQuitAppsRequest = nil
            }
        }
    }
}
