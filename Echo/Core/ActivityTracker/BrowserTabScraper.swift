import AppKit

/// Fetches open browser tabs via AppleScript for supported browsers.
/// Designed to be called on a background thread; AppleScript execution is synchronous.
struct BrowserTabScraper {

    static func fetchActiveBrowserTabs() -> [BrowserTab] {
        let supported: [(browser: BrowserTab.Browser, appName: String)] = [
            (.safari, "Safari"),
            (.arc,    "Arc"),
            (.chrome, "Google Chrome"),
            (.brave,  "Brave Browser"),
            (.edge,   "Microsoft Edge"),
        ]

        return supported.flatMap { entry -> [BrowserTab] in
            guard isRunning(appName: entry.appName) else { return [] }
            return fetchTabs(browser: entry.browser, appName: entry.appName)
        }
    }

    // MARK: - Per-browser fetch

    private static func fetchTabs(browser: BrowserTab.Browser, appName: String) -> [BrowserTab] {
        switch browser {
        case .safari:
            return runScript(safariScript(), browser: .safari)
        case .chrome, .arc, .brave, .edge:
            // Chromium-family share the same AppleScript dictionary.
            return runScript(chromiumScript(appName: appName), browser: browser)
        case .firefox:
            return [] // Requires native messaging; not supported via AppleScript.
        }
    }

    private static func safariScript() -> String {
        """
        tell application "Safari"
            set tabList to {}
            repeat with w in windows
                repeat with t in tabs of w
                    set end of tabList to {URL of t, name of t}
                end repeat
            end repeat
            return tabList
        end tell
        """
    }

    private static func chromiumScript(appName: String) -> String {
        """
        tell application "\(appName)"
            set tabList to {}
            repeat with w in windows
                repeat with t in tabs of w
                    set end of tabList to {URL of t, title of t}
                end repeat
            end repeat
            return tabList
        end tell
        """
    }

    // MARK: - AppleScript Runner

    private static func runScript(_ source: String, browser: BrowserTab.Browser) -> [BrowserTab] {
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else { return [] }
        let result = script.executeAndReturnError(&error)
        guard error == nil, result.descriptorType != typeNull else { return [] }

        var tabs: [BrowserTab] = []
        let count = result.numberOfItems
        var i = 1
        while i + 1 <= count {
            let url   = result.atIndex(i)?.stringValue ?? ""
            let title = result.atIndex(i + 1)?.stringValue ?? ""
            if !url.isEmpty {
                tabs.append(BrowserTab(id: UUID(), url: url, title: title, faviconURL: nil, browser: browser))
            }
            i += 2
        }
        return tabs
    }

    // MARK: - Helpers

    private static func isRunning(appName: String) -> Bool {
        NSWorkspace.shared.runningApplications
            .contains { $0.localizedName == appName }
    }
}
