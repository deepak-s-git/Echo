import AppKit
import SQLite3

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

        let script: String
        switch browser {
        case .safari:
            script = """
            try {
                var app = Application('Safari');
                var tab = app.windows[0].currentTab();
                JSON.stringify({url: tab.url(), title: tab.name()});
            } catch(e) { JSON.stringify(null); }
            """
        case .arc:
            script = """
            try {
                var app = Application('Arc');
                var tab = app.windows[0].activeTab();
                JSON.stringify({url: tab.url(), title: tab.name()});
            } catch(e) { JSON.stringify(null); }
            """
        default:
            script = """
            try {
                var app = Application('\(appName)');
                var tab = app.windows[0].activeTab();
                JSON.stringify({url: tab.url(), title: tab.name()});
            } catch(e) { JSON.stringify(null); }
            """
        }

        let result = runJXA(script)
        guard let item = result?.first, let url = item["url"], let title = item["title"] else {
            return nil
        }
        guard isValidTab(url: url, title: title) else {
            return nil
        }
        var profileName: String? = nil
        if browser == .chrome {
            profileName = chromeProfile(forURL: url)
        }

        return BrowserTab(
            id: UUID(),
            url: url,
            title: String(title.prefix(200)),
            faviconURL: nil,
            browser: browser,
            browserBundleId: bundleId,
            windowTitle: title,
            profileName: profileName,
            capturedAt: Date()
        )
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

        let script = """
        try {
            var app = Application('\(appName)');
            var tabs = [];
            if (app.windows.length > 0) {
                var win = app.windows[0];
                for (var j = 0; j < win.tabs.length; j++) {
                    var tab = win.tabs[j];
                    try { tabs.push({url: tab.url(), title: tab.name()}); } catch(e) {}
                }
            }
            JSON.stringify(tabs);
        } catch(e) { JSON.stringify(null); }
        """
        
        guard let result = runJXA(script) else { return nil }
        
        // Gather all valid URLs to resolve the profile for the entire window
        var validURLs: [String] = []
        for item in result {
            guard let url = item["url"], let title = item["title"] else { continue }
            guard isValidTab(url: url, title: title) else { continue }
            validURLs.append(url)
        }

        let resolvedProfile = (browser == .chrome && !validURLs.isEmpty) ? chromeProfile(forURLs: validURLs) : nil

        var tabs: [BrowserTab] = []
        for item in result {
            guard let url = item["url"], let title = item["title"] else { continue }
            guard isValidTab(url: url, title: title) else { continue }
            tabs.append(BrowserTab(
                id: UUID(),
                url: url,
                title: String(title.prefix(200)),
                faviconURL: nil,
                browser: browser,
                browserBundleId: bundleIdFor(browser),
                windowTitle: title,
                profileName: resolvedProfile,
                capturedAt: Date()
            ))
        }
        return tabs.isEmpty ? nil : tabs
    }

    private static func isValidTab(url: String, title: String) -> Bool {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let u = url.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowerT = t.lowercased()
        let lowerU = u.lowercased()
        
        if t.isEmpty || u.isEmpty { return false }
        if lowerT == "new tab" || lowerT == "start page" || lowerT == "favorites" || lowerT == "untitled" { return false }
        if lowerU == "about:blank" || lowerU.hasPrefix("chrome://") || lowerU.hasPrefix("edge://") || lowerU.hasPrefix("brave://") || lowerU.hasPrefix("favorites://") || lowerU.hasPrefix("topsites://") {
            return false
        }
        return true
    }

    // MARK: - Script runner

    private static func bundleIdFor(_ browser: BrowserTab.Browser) -> String? {
        bundleToAppName.first { $0.value.0 == browser }?.key
    }

    struct HistoryMatch {
        let score: Int // 3 = Exact, 2 = Clean Path, 1 = Host, 0 = None
        let lastVisitTime: Double
    }

    /// Determines which Chrome profile directory contains the given URL by querying
    /// each profile's SQLite History database for the URL or host match.
    private static func chromeProfile(forURL url: String) -> String? {
        chromeProfile(forURLs: [url])
    }

    /// Resolves the most likely Chrome profile for a list of URLs from the same window
    /// using a robust majority-voting algorithm across all high-confidence history matches.
    private static func chromeProfile(forURLs urls: [String]) -> String? {
        let base = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Google/Chrome")
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: base, includingPropertiesForKeys: [.isDirectoryKey]
        ) else { return nil }

        let skipDirs: Set<String> = ["System Profile", "Crashpad", "Guest Profile",
                                      "SafetyTips", "ShaderCache", "GrShaderCache",
                                      "BrowserMetrics", "Crowd Deny", "MEIPreload",
                                      "SSLErrorAssistant", "CertificateRevocation",
                                      "FileTypePolicies", "OriginTrials", "ZxcvbnData",
                                      "hyphen-data", "WidevineCdm", "pnacl",
                                      "extensions_crx_cache", "Subresource Filter"]

        let profiles = contents.compactMap { profileURL -> String? in
            let isDir = (try? profileURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            guard isDir else { return nil }
            let profile = profileURL.lastPathComponent
            guard !skipDirs.contains(profile), profile != "System Profile" else { return nil }
            return profile
        }

        var profileVotes: [String: Int] = [:]
        
        // 1. First Pass: Majority-voting based on high-confidence matches (Score >= 2: Exact or Clean Path matches)
        for url in urls {
            var bestProfileForUrl: String? = nil
            var highestScoreForUrl = 0
            var highestTimeForUrl: Double = 0

            for profile in profiles {
                let profileURL = base.appendingPathComponent(profile)
                if let match = checkURLInHistoryDetails(profilePath: profileURL, urlString: url) {
                    if match.score > highestScoreForUrl {
                        highestScoreForUrl = match.score
                        bestProfileForUrl = profile
                        highestTimeForUrl = match.lastVisitTime
                    } else if match.score == highestScoreForUrl && match.score > 0 {
                        if match.lastVisitTime > highestTimeForUrl {
                            bestProfileForUrl = profile
                            highestTimeForUrl = match.lastVisitTime
                        }
                    }
                }
            }

            // Only vote if it is a high-confidence match (Score >= 2)
            if let matchedProfile = bestProfileForUrl, highestScoreForUrl >= 2 {
                profileVotes[matchedProfile, default: 0] += 1
            }
        }

        if let bestProfile = profileVotes.max(by: { $0.value < $1.value })?.key {
            return bestProfile
        }

        // 2. Second Pass: Fallback voting based on any match (Score >= 1, e.g. host match)
        var fallbackVotes: [String: Int] = [:]
        for url in urls {
            var bestProfileForUrl: String? = nil
            var highestScoreForUrl = 0
            var highestTimeForUrl: Double = 0

            for profile in profiles {
                let profileURL = base.appendingPathComponent(profile)
                if let match = checkURLInHistoryDetails(profilePath: profileURL, urlString: url) {
                    if match.score > highestScoreForUrl {
                        highestScoreForUrl = match.score
                        bestProfileForUrl = profile
                        highestTimeForUrl = match.lastVisitTime
                    } else if match.score == highestScoreForUrl && match.score > 0 {
                        if match.lastVisitTime > highestTimeForUrl {
                            bestProfileForUrl = profile
                            highestTimeForUrl = match.lastVisitTime
                        }
                    }
                }
            }

            if let matchedProfile = bestProfileForUrl, highestScoreForUrl > 0 {
                fallbackVotes[matchedProfile, default: 0] += 1
            }
        }

        if let bestProfile = fallbackVotes.max(by: { $0.value < $1.value })?.key {
            return bestProfile
        }

        // 3. Ultimate Fallback: Most recently modified profile folder
        var fallbackCandidates: [(name: String, mtime: Date)] = []
        for profile in profiles {
            let profileURL = base.appendingPathComponent(profile)
            let historyPath = profileURL.appendingPathComponent("History")
            if let mtime = (try? historyPath.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) {
                fallbackCandidates.append((name: profile, mtime: mtime))
            }
        }
        fallbackCandidates.sort { $0.mtime > $1.mtime }
        return fallbackCandidates.first?.name
    }

    private static func checkURLInHistoryDetails(profilePath: URL, urlString: String) -> HistoryMatch? {
        let tempBase = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempBase, withIntermediateDirectories: true)
        
        let tempURL = tempBase.appendingPathComponent("History")
        let tempWalURL = tempBase.appendingPathComponent("History-wal")
        let tempShmURL = tempBase.appendingPathComponent("History-shm")
        
        let historyPath = profilePath.appendingPathComponent("History")
        let walPath = profilePath.appendingPathComponent("History-wal")
        let shmPath = profilePath.appendingPathComponent("History-shm")
        
        guard FileManager.default.fileExists(atPath: historyPath.path) else {
            try? FileManager.default.removeItem(at: tempBase)
            return nil
        }
        
        do {
            try FileManager.default.copyItem(at: historyPath, to: tempURL)
            if FileManager.default.fileExists(atPath: walPath.path) {
                try FileManager.default.copyItem(at: walPath, to: tempWalURL)
            }
            if FileManager.default.fileExists(atPath: shmPath.path) {
                try FileManager.default.copyItem(at: shmPath, to: tempShmURL)
            }
        } catch {
            try? FileManager.default.removeItem(at: tempBase)
            return nil
        }
        
        defer {
            try? FileManager.default.removeItem(at: tempBase)
        }
        
        var db: OpaquePointer?
        guard sqlite3_open_v2(tempURL.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            return nil
        }
        defer {
            sqlite3_close(db)
        }
        
        // A. Exact URL match (Score 3)
        var statementExact: OpaquePointer?
        let queryExact = "SELECT last_visit_time FROM urls WHERE url = ? LIMIT 1"
        if sqlite3_prepare_v2(db, queryExact, -1, &statementExact, nil) == SQLITE_OK {
            sqlite3_bind_text(statementExact, 1, urlString.cString(using: .utf8), -1, nil)
            if sqlite3_step(statementExact) == SQLITE_ROW {
                let lastVisitTime = sqlite3_column_double(statementExact, 0)
                sqlite3_finalize(statementExact)
                return HistoryMatch(score: 3, lastVisitTime: lastVisitTime)
            }
            sqlite3_finalize(statementExact)
        }
        
        // B. Clean URL match (stripped query parameters and fragments) (Score 2)
        var cleanURLString = urlString
        if let urlObj = URL(string: urlString), let host = urlObj.host, let scheme = urlObj.scheme {
            cleanURLString = "\(scheme)://\(host)\(urlObj.path)"
        }
        if cleanURLString != urlString {
            var statementClean: OpaquePointer?
            let queryClean = "SELECT last_visit_time FROM urls WHERE url = ? LIMIT 1"
            if sqlite3_prepare_v2(db, queryClean, -1, &statementClean, nil) == SQLITE_OK {
                sqlite3_bind_text(statementClean, 1, cleanURLString.cString(using: .utf8), -1, nil)
                if sqlite3_step(statementClean) == SQLITE_ROW {
                    let lastVisitTime = sqlite3_column_double(statementClean, 0)
                    sqlite3_finalize(statementClean)
                    return HistoryMatch(score: 2, lastVisitTime: lastVisitTime)
                }
                sqlite3_finalize(statementClean)
            }
        }
        
        // C. Domain/host match fallback (Score 1)
        if let host = URL(string: urlString)?.host {
            var statementLike: OpaquePointer?
            let queryLike = "SELECT last_visit_time FROM urls WHERE url LIKE ? ORDER BY last_visit_time DESC LIMIT 1"
            if sqlite3_prepare_v2(db, queryLike, -1, &statementLike, nil) == SQLITE_OK {
                let likePattern = "%\(host)%"
                sqlite3_bind_text(statementLike, 1, likePattern.cString(using: .utf8), -1, nil)
                if sqlite3_step(statementLike) == SQLITE_ROW {
                    let lastVisitTime = sqlite3_column_double(statementLike, 0)
                    sqlite3_finalize(statementLike)
                    return HistoryMatch(score: 1, lastVisitTime: lastVisitTime)
                }
                sqlite3_finalize(statementLike)
            }
        }
        
        return nil
    }

    private static func checkURLInHistory(profilePath: URL, urlString: String) -> Double? {
        checkURLInHistoryDetails(profilePath: profilePath, urlString: urlString)?.lastVisitTime
    }

    private static func runJXA(_ script: String) -> [[String: String]]? {
        let task = Process()
        task.launchPath = "/usr/bin/osascript"
        task.arguments = ["-l", "JavaScript", "-e", script]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        
        do {
            try task.run()
            task.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let jsonString = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  let jsonData = jsonString.data(using: .utf8) else {
                return nil
            }
            
            if let array = try? JSONSerialization.jsonObject(with: jsonData) as? [[String: String]] {
                return array
            }
            if let obj = try? JSONSerialization.jsonObject(with: jsonData) as? [String: String] {
                return [obj]
            }
            return nil
        } catch {
            return nil
        }
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
