import AppKit

/// Lightweight snapshot of the frontmost application (and optionally its focused window).
nonisolated struct FrontmostSnapshot: Sendable, Equatable {
    let bundleId: String
    let displayName: String
    let pid: pid_t
    let windowTitle: String?
    /// file:// URL for document-based apps; nil for everything else.
    let documentURL: String?

    /// Fingerprint used to detect same-app context changes (tab switches, file switches).
    /// Prefers documentURL > windowTitle so switching files in Preview registers correctly.
    var windowFingerprint: String {
        documentURL ?? windowTitle ?? ""
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
            windowTitle: nil,
            documentURL: nil
        )
    }

    /// Includes focused window title + document URL when Accessibility is granted.
    @MainActor
    static func captureWithWindow() -> FrontmostSnapshot? {
        guard let base = captureAppOnly() else { return nil }
        let ctx = WindowContextCapture.focusedWindowContext()
        return FrontmostSnapshot(
            bundleId: base.bundleId,
            displayName: base.displayName,
            pid: base.pid,
            windowTitle: ctx.title,
            documentURL: ctx.documentURL
        )
    }
}
