import AppKit
import Combine
import ApplicationServices

@MainActor
final class PermissionsManager: ObservableObject {

    @Published private(set) var accessibilityGranted: Bool = false
    @Published private(set) var automationGranted: Bool = false
    @Published private(set) var hasChecked: Bool = false

    private var monitorTask: Task<Void, Never>?

    init() {
        checkAll()
        startMonitoring()
    }

    deinit { monitorTask?.cancel() }

    // MARK: - Public

    func checkAll() {
        accessibilityGranted = AXIsProcessTrusted()
        hasChecked = true
    }

    func requestAccessibility() {
        // Open System Settings directly to the Accessibility pane
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)

        // Also trigger the system prompt as a fallback
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    var allGranted: Bool { accessibilityGranted }

    // MARK: - Monitoring

    private func startMonitoring() {
        monitorTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                self?.checkAll()
            }
        }
    }
}
