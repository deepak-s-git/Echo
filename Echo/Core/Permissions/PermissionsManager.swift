import SwiftUI
import AppKit
import Combine
import ApplicationServices

@MainActor
final class PermissionsManager: ObservableObject {

    @Published private(set) var accessibilityGranted: Bool = false
    @Published private(set) var automationGranted: Bool = false
    @Published private(set) var hasChecked: Bool = false

    private var monitorTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    init() {
        checkAll()
        startMonitoring()
        
        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.checkAll()
            }
            .store(in: &cancellables)
    }

    deinit { monitorTask?.cancel() }

    // MARK: - Public

    func checkAll() {
        let isTrusted = AXIsProcessTrusted()
        if isTrusted != accessibilityGranted {
            withAnimation(.spring(response: 0.75, dampingFraction: 0.85)) {
                accessibilityGranted = isTrusted
            }
        }
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
                try? await Task.sleep(for: .seconds(0.5))
                self?.checkAll()
            }
        }
    }
}
