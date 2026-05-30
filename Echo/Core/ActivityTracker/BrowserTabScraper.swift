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
            let sessionMap = sessionURLsForProfiles()
            profileName = chromeProfile(forURLs: [url], sessionMap: sessionMap)
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
            var flatTabs = [];
            for (var i = 0; i < app.windows.length; i++) {
                var win = app.windows[i];
                try {
                    for (var j = 0; j < win.tabs.length; j++) {
                        var tab = win.tabs[j];
                        try {
                            flatTabs.push({
                                url: tab.url(),
                                title: tab.name(),
                                windowIndex: i.toString()
                            });
                        } catch(e) {}
                    }
                } catch(e) {}
            }
            JSON.stringify(flatTabs);
        } catch(e) { JSON.stringify(null); }
        """
        
        guard let result = runJXA(script) else { return nil }
        
        // Pre-compute session-based URL map once for all windows
        let sessionMap = (browser == .chrome) ? sessionURLsForProfiles() : [:]
        
        // Group the scraped tabs by windowIndex to perform window-level profile resolution
        let groupedByWindow = Dictionary(grouping: result, by: { $0["windowIndex"] ?? "0" })
        var resolvedWindowProfiles: [String: String?] = [:]
        
        for (windowIndex, windowItems) in groupedByWindow {
            var validURLs: [String] = []
            for item in windowItems {
                guard let url = item["url"], let title = item["title"] else { continue }
                guard isValidTab(url: url, title: title) else { continue }
                validURLs.append(url)
            }
            let profile = (browser == .chrome && !validURLs.isEmpty) ? chromeProfile(forURLs: validURLs, sessionMap: sessionMap) : nil
            resolvedWindowProfiles[windowIndex] = profile
        }

        var tabs: [BrowserTab] = []
        for item in result {
            guard let url = item["url"], let title = item["title"] else { continue }
            guard isValidTab(url: url, title: title) else { continue }
            let wIndex = item["windowIndex"] ?? "0"
            let resolvedProfile = resolvedWindowProfiles[wIndex] ?? nil
            
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

    // MARK: - Session-Based Chrome Profile Resolution

    /// Reads each Chrome profile's most recent SNSS Session file to build
    /// a map of which normalized hosts are currently open in each profile.
    /// This is the ground-truth source for window-to-profile assignment.
    private static func sessionURLsForProfiles() -> [String: Set<String>] {
        let base = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Google/Chrome")
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: base, includingPropertiesForKeys: [.isDirectoryKey]
        ) else { return [:] }

        let profileDirs = contents.compactMap { url -> String? in
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            guard isDir else { return nil }
            let name = url.lastPathComponent
            // Only consider real profile directories
            guard name == "Default" || name.hasPrefix("Profile ") else { return nil }
            return name
        }

        var result: [String: Set<String>] = [:]
        let httpBytes  = [UInt8]("http://".utf8)
        let httpsBytes = [UInt8]("https://".utf8)

        for profileDir in profileDirs {
            let sessionsDir = base.appendingPathComponent(profileDir).appendingPathComponent("Sessions")
            guard let sessionFiles = try? FileManager.default.contentsOfDirectory(
                at: sessionsDir,
                includingPropertiesForKeys: [.contentModificationDateKey]
            ) else { continue }

            // Find the most recently modified Session_ file (not Tabs_)
            let sessionOnlyFiles = sessionFiles.filter { $0.lastPathComponent.hasPrefix("Session_") }
            guard let newestSession = sessionOnlyFiles.max(by: {
                let d1 = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let d2 = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return d1 < d2
            }) else { continue }

            guard let data = try? Data(contentsOf: newestSession) else { continue }
            let bytes = [UInt8](data)
            var hosts = Set<String>()

            // Scan the raw bytes for http:// and https:// URL patterns
            var i = 0
            while i < bytes.count {
                var prefixLen = 0
                if i + httpsBytes.count <= bytes.count,
                   Array(bytes[i..<i+httpsBytes.count]) == httpsBytes {
                    prefixLen = httpsBytes.count
                } else if i + httpBytes.count <= bytes.count,
                          Array(bytes[i..<i+httpBytes.count]) == httpBytes {
                    prefixLen = httpBytes.count
                }

                guard prefixLen > 0 else { i += 1; continue }

                // Read until a non-URL byte (space, control char, null, quote, etc.)
                var end = i + prefixLen
                while end < bytes.count {
                    let b = bytes[end]
                    if b < 0x21 || b == 0x22 || b == 0x27 || b == 0x3C ||
                       b == 0x3E || b == 0x7B || b == 0x7D || b == 0x7F { break }
                    end += 1
                }
                let urlLen = end - i
                if urlLen > prefixLen + 3, urlLen < 2048,
                   let urlStr = String(bytes: bytes[i..<end], encoding: .utf8),
                   let urlObj = URL(string: urlStr),
                   let host = urlObj.host {
                    // Normalize: strip www. and lowercase
                    var h = host.lowercased()
                    if h.hasPrefix("www.") { h = String(h.dropFirst(4)) }
                    // Skip noise domains
                    if !h.contains("googlevideo.com") &&
                       !h.contains("doubleclick.net") &&
                       !h.contains("adtrafficquality") &&
                       !h.contains("gstatic.com") {
                        hosts.insert(h)
                    }
                }
                i = end
            }

            if !hosts.isEmpty {
                result[profileDir] = hosts
            }
        }
        return result
    }

    /// Resolves the Chrome profile for a window's URLs using session file data.
    /// Profiles that exclusively own a host get strong votes; shared hosts get weaker votes.
    private static func chromeProfileFromSessions(
        forWindowURLs urls: [String],
        sessionMap: [String: Set<String>]
    ) -> String? {
        guard !sessionMap.isEmpty else { return nil }

        // Extract normalized hosts from the window's URLs
        var windowHosts = Set<String>()
        for urlStr in urls {
            guard let urlObj = URL(string: urlStr), let host = urlObj.host else { continue }
            var h = host.lowercased()
            if h.hasPrefix("www.") { h = String(h.dropFirst(4)) }
            windowHosts.insert(h)
        }
        guard !windowHosts.isEmpty else { return nil }

        // For each host, determine how many profiles claim it
        var hostOwnerCount: [String: Int] = [:]
        for host in windowHosts {
            var count = 0
            for (_, hosts) in sessionMap {
                if hosts.contains(host) { count += 1 }
            }
            hostOwnerCount[host] = count
        }

        // Score each profile: exclusive hosts = +3, shared hosts = +1
        var profileScores: [String: Int] = [:]
        for (profileDir, profileHosts) in sessionMap {
            var score = 0
            for host in windowHosts {
                if profileHosts.contains(host) {
                    let owners = hostOwnerCount[host] ?? 1
                    score += (owners == 1) ? 3 : 1
                }
            }
            if score > 0 {
                profileScores[profileDir] = score
            }
        }

        // Return the profile with the highest score, with tie-breaking by profile name for stability
        let sorted = profileScores.sorted {
            if $0.value != $1.value { return $0.value > $1.value }
            return $0.key < $1.key
        }
        return sorted.first?.key
    }

    // MARK: - Chrome Profile Resolution (Session-first, History-fallback)

    /// Resolves the most likely Chrome profile for a set of URLs from the same window.
    /// Uses session-based resolution first, falls back to History DB queries.
    private static func chromeProfile(forURLs urls: [String], sessionMap: [String: Set<String>] = [:]) -> String? {
        // 1. PRIMARY: Session-based resolution (reads current tab state per profile)
        if let sessionResult = chromeProfileFromSessions(forWindowURLs: urls, sessionMap: sessionMap) {
            return sessionResult
        }

        // 2. SECONDARY: Fall back to History DB voting
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
        
        // High-confidence History matches (Score >= 2: Exact or Clean Path)
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

            if let matchedProfile = bestProfileForUrl, highestScoreForUrl >= 2 {
                profileVotes[matchedProfile, default: 0] += 1
            }
        }

        if let bestProfile = profileVotes.max(by: { $0.value < $1.value })?.key {
            return bestProfile
        }

        // 3. ULTIMATE FALLBACK: Most recently modified profile folder
        var fallbackCandidates: [(name: String, mtime: Date)] = []
        for profile in profiles {
            let profileURL = base.appendingPathComponent(profile)
            var filesToCheck = [
                profileURL.appendingPathComponent("History"),
                profileURL.appendingPathComponent("History-wal"),
                profileURL.appendingPathComponent("Preferences"),
                profileURL.appendingPathComponent("Sessions")
            ]
            
            if let sessionsContents = try? FileManager.default.contentsOfDirectory(at: profileURL.appendingPathComponent("Sessions"), includingPropertiesForKeys: [.contentModificationDateKey]) {
                filesToCheck.append(contentsOf: sessionsContents)
            }
            
            var maxMtime = Date.distantPast
            for file in filesToCheck {
                if let mtime = (try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) {
                    if mtime > maxMtime {
                        maxMtime = mtime
                    }
                }
            }
            if maxMtime > Date.distantPast {
                fallbackCandidates.append((name: profile, mtime: maxMtime))
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
            let data = try Data(contentsOf: historyPath)
            try data.write(to: tempURL)
        } catch {
            try? FileManager.default.removeItem(at: tempBase)
            return nil
        }
        
        if FileManager.default.fileExists(atPath: walPath.path) {
            if let data = try? Data(contentsOf: walPath) {
                try? data.write(to: tempWalURL)
            }
        }
        if FileManager.default.fileExists(atPath: shmPath.path) {
            if let data = try? Data(contentsOf: shmPath) {
                try? data.write(to: tempShmURL)
            }
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
