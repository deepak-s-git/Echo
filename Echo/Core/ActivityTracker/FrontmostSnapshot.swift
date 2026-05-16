import AppKit

/// Lightweight snapshot of the frontmost application (and optionally its focused window).
nonisolated struct FrontmostSnapshot: Sendable, Equatable {
    let bundleId: String
    let displayName: String
    let pid: pid_t
    let windowTitle: String?

    var windowFingerprint: String {
        windowTitle ?? ""
    }

    /// Fast path: frontmost app only (no AX).
    @MainActor
    static func captureAppOnly() -> FrontmostSnapshot? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let bundleId = app.bundleIdentifier ?? "unknown"
        return FrontmostSnapshot(
            bundleId: bundleId,
            displayName: AppMetadataResolver.displayName(
                bundleId: bundleId,
                rawName: app.localizedName
            ),
            pid: app.processIdentifier,
            windowTitle: nil
        )
    }

    /// Includes focused window title when Accessibility is granted (for space/window changes).
    @MainActor
    static func captureWithWindow() -> FrontmostSnapshot? {
        guard let base = captureAppOnly() else { return nil }
        let title = WindowContextCapture.focusedWindowContext().title
        return FrontmostSnapshot(
            bundleId: base.bundleId,
            displayName: base.displayName,
            pid: base.pid,
            windowTitle: title
        )
    }
}
