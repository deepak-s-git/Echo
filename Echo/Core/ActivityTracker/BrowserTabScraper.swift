import AppKit

/// Fetches browser tab metadata via AppleScript. Privacy: prefer active-tab-only APIs.
struct BrowserTabScraper {

    private static let bundleToAppName: [String: (BrowserTab.Browser, String)] = [
        "com.apple.Safari": (.safari, "Safari"),
        "com.google.Chrome": (.chrome, "Google Chrome"),
        "company.thebrowser.Browser": (.arc, "Arc"),
        "com.brave.Browser": (.brave, "Brave Browser"),
        "com.microsoft.edgemac": (.edge, "Microsoft Edge"),
        "ai.perplexity.comet": (.chrome, "Comet")
    ]

    // MARK: - Active tab (privacy-first)

    @MainActor
    static func activeTab(forBundleId bundleId: String) -> BrowserTab? {
        guard let (browser, appName) = bundleToAppName[bundleId],
              isRunning(bundleId: bundleId) || isRunning(appName: appName)
        else { return nil }

        let source: String
        switch browser {
        case .safari:
            source = """
            tell application "Safari"
                set w to front window
                set t to current tab of w
                return {URL of t, name of t}
            end tell
            """
        case .arc:
            source = """
            tell application "Arc"
                set t to active tab of front window
                return {URL of t, title of t}
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

        return runPairScript(source, browser: browser, bundleId: bundleId)
    }

    // MARK: - Full scrape (session end snapshot only)

    @MainActor
    static func fetchActiveBrowserTabs() -> [BrowserTab] {
        fetchAllBrowserTabsForRestore()
    }

    /// All tabs from front windows of running browsers (restore + snapshots).
    @MainActor
    static func fetchAllBrowserTabsForRestore() -> [BrowserTab] {
        bundleToAppName.flatMap { bundleId, entry -> [BrowserTab] in
            guard isRunning(bundleId: bundleId) || isRunning(appName: entry.1) else { return [] }
            return tabsForRestore(bundleId: bundleId)
        }
    }

    /// Tabs from the front window of a browser (active tab; list scrape when available).
    @MainActor
    static func tabsForRestore(bundleId: String) -> [BrowserTab] {
        guard let (browser, appName) = bundleToAppName[bundleId],
              isRunning(bundleId: bundleId) || isRunning(appName: appName)
        else { return [] }

        if let listed = runChromeStyleTabList(appName: appName, browser: browser), !listed.isEmpty {
            return listed
        }
        if let active = activeTab(forBundleId: bundleId) {
            return [active]
        }
        return []
    }

    @MainActor
    private static func runChromeStyleTabList(appName: String, browser: BrowserTab.Browser) -> [BrowserTab]? {
        let source = """
        tell application "\(appName)"
            set out to {}
            repeat with w in windows
                repeat with t in tabs of w
                    try
                        set end of out to {URL of t, title of t}
                    end try
                end repeat
            end repeat
            return out
        end tell
        """
        let tabs = runTabListScript(source, browser: browser)
        return tabs.isEmpty ? nil : tabs
    }

    // MARK: - Script runner

    @MainActor
    private static func runPairScript(
        _ source: String,
        browser: BrowserTab.Browser,
        bundleId: String?
    ) -> BrowserTab? {
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
            browser: browser,
            browserBundleId: bundleIdFor(browser),
            windowTitle: title,
            capturedAt: Date()
        )
    }

    private static func bundleIdFor(_ browser: BrowserTab.Browser) -> String? {
        bundleToAppName.first { $0.value.0 == browser }?.key
    }

    @MainActor
    private static func runTabListScript(_ source: String, browser: BrowserTab.Browser) -> [BrowserTab] {
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else { return [] }
        let result = script.executeAndReturnError(&error)
        guard error == nil else { return [] }

        var tabs: [BrowserTab] = []
        let count = result.numberOfItems
        for i in 1...count {
            guard let item = result.atIndex(i) else { continue }
            let url = item.atIndex(1)?.stringValue ?? ""
            let title = item.atIndex(2)?.stringValue ?? ""
            if !url.isEmpty {
                tabs.append(BrowserTab(
                    id: UUID(),
                    url: url,
                    title: String(title.prefix(200)),
                    faviconURL: nil,
                    browser: browser,
                    browserBundleId: bundleIdFor(browser),
                    windowTitle: title,
                    capturedAt: Date()
                ))
            }
        }
        return tabs
    }

    @MainActor
    private static func isRunning(appName: String) -> Bool {
        NSWorkspace.shared.runningApplications.contains { $0.localizedName == appName }
    }

    @MainActor
    private static func isRunning(bundleId: String) -> Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == bundleId }
    }
}
