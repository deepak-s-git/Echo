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
        guard let item = result?.first, let url = item["url"], let title = item["title"], !url.isEmpty else {
            return nil
        }
        if title == "New Tab" || url.starts(with: "chrome://newtab") || url.starts(with: "edge://newtab") || url.starts(with: "brave://newtab") {
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
        
        // All tabs in a single Chrome window share the same profile.
        // Resolve once from the first valid URL to avoid redundant file reads.
        var resolvedProfile: String? = nil
        var didResolve = false

        var tabs: [BrowserTab] = []
        for item in result {
            guard let url = item["url"], let title = item["title"], !url.isEmpty else { continue }
            if title == "New Tab" || url.starts(with: "chrome://newtab") || url.starts(with: "edge://newtab") || url.starts(with: "brave://newtab") {
                continue
            }
            if browser == .chrome && !didResolve {
                resolvedProfile = chromeProfile(forURL: url)
                didResolve = true
            }
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

    // MARK: - Script runner

    private static func bundleIdFor(_ browser: BrowserTab.Browser) -> String? {
        bundleToAppName.first { $0.value.0 == browser }?.key
    }

    /// Determines which Chrome profile directory contains the given URL by searching
    /// each profile's session files for the URL string.
    private static func chromeProfile(forURL url: String) -> String? {
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

        struct ProfileCandidate {
            let name: String
            let latestFile: URL
            let mtime: Date
            let data: Data
        }

        var candidates: [ProfileCandidate] = []

        for profileURL in contents {
            let isDir = (try? profileURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            guard isDir else { continue }
            let profile = profileURL.lastPathComponent
            guard !skipDirs.contains(profile),
                  profile != "System Profile" else { continue }

            let sessionsDir = profileURL.appendingPathComponent("Sessions")
            guard let files = try? FileManager.default.contentsOfDirectory(
                at: sessionsDir, includingPropertiesForKeys: [.contentModificationDateKey]
            ) else { continue }

            let tabsFiles = files
                .filter { $0.lastPathComponent.hasPrefix("Tabs_") }
                .sorted { f1, f2 in
                    let d1 = (try? f1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                    let d2 = (try? f2.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                    return d1 > d2
                }

            guard let latestFile = tabsFiles.first,
                  let mtime = (try? latestFile.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate),
                  let data = try? Data(contentsOf: latestFile) else { continue }

            candidates.append(ProfileCandidate(name: profile, latestFile: latestFile, mtime: mtime, data: data))
        }

        // Sort candidates newest-first by session file modification date
        candidates.sort { $0.mtime > $1.mtime }

        // 1. Try exact URL match
        if let urlData = url.data(using: .utf8) {
            for candidate in candidates {
                if candidate.data.range(of: urlData) != nil {
                    return candidate.name
                }
            }
        }

        // 2. Try host/domain match
        if let host = URL(string: url)?.host, let hostData = host.data(using: .utf8) {
            for candidate in candidates {
                if candidate.data.range(of: hostData) != nil {
                    return candidate.name
                }
            }
        }

        // 3. Fallback: most recently modified profile
        return candidates.first?.name
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
