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
            withAnimation(.spring(response: 0.65, dampingFraction: 0.88)) {
                accessibilityGranted = isTrusted
            }
        }
        if !hasChecked {
            hasChecked = true
        }
    }

    func requestAccessibility() {
        // Trigger the standard macOS system prompt. 
        // The prompt provides an "Open System Settings" button that macOS manages natively.
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    var allGranted: Bool { accessibilityGranted }

    // MARK: - Monitoring

    private func startMonitoring() {
        monitorTask = Task { [weak self] in
            while !Task.isCancelled {
                let delay = self?.accessibilityGranted == true ? 3.0 : 0.5
                try? await Task.sleep(for: .seconds(delay))
                self?.checkAll()
            }
        }
    }
}
