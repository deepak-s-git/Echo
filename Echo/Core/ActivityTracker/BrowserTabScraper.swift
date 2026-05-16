import AppKit

/// Fetches browser tab metadata via AppleScript. Privacy: prefer active-tab-only APIs.
struct BrowserTabScraper {

    private static let bundleToAppName: [String: (BrowserTab.Browser, String)] = [
        "com.apple.Safari": (.safari, "Safari"),
        "com.google.Chrome": (.chrome, "Google Chrome"),
        "company.thebrowser.Browser": (.arc, "Arc"),
        "com.brave.Browser": (.brave, "Brave Browser"),
        "com.microsoft.edgemac": (.edge, "Microsoft Edge")
    ]

    // MARK: - Active tab (privacy-first)

    @MainActor
    static func activeTab(forBundleId bundleId: String) -> BrowserTab? {
        guard let (browser, appName) = bundleToAppName[bundleId],
              isRunning(appName: appName)
        else { return nil }

        let source: String
        switch browser {
        case .safari:
            source = """
            tell application "Safari"
                set t to current tab of front window
                return {URL of t, name of t}
            end tell
            """
        default:
            source = """
            tell application "\(appName)"
                set t to active tab of front window
                return {URL of t, title of t}
            end tell
            """
        }

        return runPairScript(source, browser: browser)
    }

    // MARK: - Full scrape (session end snapshot only)

    @MainActor
    static func fetchActiveBrowserTabs() -> [BrowserTab] {
        bundleToAppName.compactMap { bundleId, entry -> BrowserTab? in
            guard isRunning(appName: entry.1) else { return nil }
            return activeTab(forBundleId: bundleId)
        }
    }

    // MARK: - Script runner

    @MainActor
    private static func runPairScript(_ source: String, browser: BrowserTab.Browser) -> BrowserTab? {
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else { return nil }
        let result = script.executeAndReturnError(&error)
        guard error == nil, result.numberOfItems >= 2 else { return nil }

        let url = result.atIndex(1)?.stringValue ?? ""
        let title = result.atIndex(2)?.stringValue ?? ""
        guard !url.isEmpty else { return nil }

        return BrowserTab(
            id: UUID(),
            url: url,
            title: String(title.prefix(200)),
            faviconURL: nil,
            browser: browser
        )
    }

    @MainActor
    private static func isRunning(appName: String) -> Bool {
        NSWorkspace.shared.runningApplications.contains { $0.localizedName == appName }
    }
}
