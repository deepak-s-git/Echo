import Foundation

/// Captures lightweight browser context for the frontmost tab only (privacy-first).
nonisolated enum BrowserContextService {

    private static let browserBundles: Set<String> = [
        "com.apple.Safari",
        "com.google.Chrome",
        "company.thebrowser.Browser",
        "com.brave.Browser",
        "com.microsoft.edgemac"
    ]

    static func isBrowser(_ bundleId: String) -> Bool {
        browserBundles.contains(bundleId)
    }

    /// Active tab metadata only — no bulk tab harvesting during normal tracking.
    @MainActor
    static func captureActiveTab(for bundleId: String) -> BrowserTab? {
        guard isBrowser(bundleId) else { return nil }
        return BrowserTabScraper.activeTab(forBundleId: bundleId)
    }

    /// Produces a privacy-safe activity event from tab metadata (domain + title only).
    static func activityEvent(
        from tab: BrowserTab,
        sessionId: UUID,
        bundleId: String,
        appName: String
    ) -> ActivityEvent {
        let urlStr = tab.url.trimmingCharacters(in: .whitespacesAndNewlines)
        return ActivityEvent(
            id: UUID(),
            sessionId: sessionId,
            timestamp: Date(),
            type: .browserTab,
            appBundleId: bundleId,
            appName: appName,
            windowTitle: tab.title,
            url: urlStr,
            profileName: tab.profileName,
            duration: 0
        )
    }
}
