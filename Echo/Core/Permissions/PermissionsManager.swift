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
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true]
        let _ = AXIsProcessTrustedWithOptions(options)
    }

    var allGranted: Bool { accessibilityGranted }

    // MARK: - Monitoring

    private func startMonitoring() {
        monitorTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                self?.checkAll()
            }
        }
    }
}
