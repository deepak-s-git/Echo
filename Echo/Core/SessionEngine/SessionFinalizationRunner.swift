import Foundation

/// Heavy segment finalization off the main actor and SessionEngine hot path.
nonisolated enum SessionFinalizationRunner {

    static func finalize(
        session: Session,
        queuedBatch: [ActivityEvent],
        userTitle: String?,
        repository: SessionRepository
    ) async {
        EchoLog.persistence("Finalizing segment \(session.id.uuidString) in background")

        if !queuedBatch.isEmpty {
            do {
                _ = try await repository.insertBatch(queuedBatch)
            } catch {
                EchoLog.persistence("Background flush failed", error: error)
            }
        }

        let events = (try? await repository.fetchActivities(sessionId: session.id)) ?? []
        let startedAt = session.startedAt
        
        // Always generate the AI summary for the session card
        let compiledContext = SessionSummaryCompiler.compile(events: events)
        let aiSummary = await LocalSummarizerService.shared.summarize(activityText: compiledContext)
        
        // Generate a relatable workflow title only if no title is specified
        var generatedTitle: String? = nil
        if (userTitle == nil || userTitle?.isEmpty == true),
           session.title == nil || session.title?.isEmpty == true {
            generatedTitle = await MainActor.run {
                SessionTitleGenerator.generate(from: events, startedAt: startedAt)
            }
        }

        var finalized = session
        finalized.appCount = Set(events.map(\.appBundleId)).count
        finalized.focusScore = Self.focusScore(from: events)
        finalized.summary = aiSummary
        if let generatedTitle { finalized.title = generatedTitle }

        await Self.finalizeMemory(&finalized, events: events, repository: repository)

        do {
            try await repository.save(finalized)
            EchoLog.persistence(
                "Finalize complete — \(finalized.id.uuidString), restore=\(finalized.restorePlan?.items.count ?? 0)"
            )
            // Compute vector embedding chunks in the background
            Task {
                await SemanticSearchEngine.shared.indexSession(finalized, activities: events, repository: repository)
            }
        } catch {
            EchoLog.persistence("Finalize save failed", error: error)
        }
    }

  private static func focusScore(from events: [ActivityEvent]) -> Double {
        guard !events.isEmpty else { return 0 }
        let switches = events.filter { $0.type == .appSwitch }.count
        return min(max(1 - Double(switches) / Double(events.count), 0), 1)
    }

    private static func finalizeMemory(
        _ session: inout Session,
        events: [ActivityEvent],
        repository: SessionRepository
    ) async {
        let cluster = WorkflowClusterDetector.detect(from: events)
        session.workflowCluster = cluster.rawValue
        session.projectTag = cluster.label

        let memory = WorkflowMemoryBuilder.build(session: session, events: events)
        session.tabCount = memory.browserContexts.count

        let tabs = await captureBrowserTabs(events: events)
        EchoLog.browserCapture("Snapshot tabs: \(tabs.count)")

        let tabEligibility = await MainActor.run {
            EchoSettings.shared.browserCaptureDelaySeconds + EchoSettings.shared.tabEligibilitySeconds
        }
        let contextual = WorkflowContextCapture.items(from: events, tabEligibility: tabEligibility, sessionEndDate: session.endedAt)
        let plan = mergeRestorePlan(primary: contextual, secondary: memory.restorePlan, tabs: tabs)

        do {
            let data = try JSONEncoder().encode(plan)
            if let json = String(data: data, encoding: .utf8) {
                session.restorePlanJSON = json
            }
        } catch {
            EchoLog.restore("Restore plan encode failed", error: error)
        }

        let layoutData = (try? JSONEncoder().encode(
            WindowLayout(frames: [], capturedAt: Date(), screenCount: 1)
        )) ?? Data()
        let apps = WorkflowClusterDetector.signature(from: events)
        let snapshot = SessionSnapshot(
            id: UUID(),
            sessionId: session.id,
            capturedAt: Date(),
            windowLayout: layoutData,
            activeApps: apps,
            browserTabs: tabs,
            thumbnailPath: nil
        )
        do {
            try await repository.insertSnapshot(snapshot)
            session.snapshotPath = snapshot.id.uuidString
        } catch {
            EchoLog.persistence("Snapshot insert failed", error: error)
        }
    }

    @MainActor
    private static func captureBrowserTabs(events: [ActivityEvent]) -> [BrowserTab] {
        var tabs = BrowserTabScraper.fetchAllBrowserTabsForRestore()
        if tabs.isEmpty {
            let bundles = Set(
                events.filter { BrowserContextService.isBrowser($0.appBundleId) }.map(\.appBundleId)
            )
            for bundleId in bundles {
                tabs.append(contentsOf: BrowserTabScraper.tabsForRestore(bundleId: bundleId))
            }
        }
        var seen = Set<String>()
        return tabs.filter { seen.insert($0.url.lowercased()).inserted }
    }

    private static func mergeRestorePlan(
        primary: [RestoreItem],
        secondary: WorkflowRestorePlan,
        tabs: [BrowserTab]
    ) -> WorkflowRestorePlan {
        let defaultChromeProfile = tabs.first(where: { $0.browser == .chrome })?.profileName
        let defaultBraveProfile = tabs.first(where: { $0.browser == .brave })?.profileName
        let defaultEdgeProfile = tabs.first(where: { $0.browser == .edge })?.profileName
        
        // Build a URL-to-Profile map from the active tabs scraped at finalization (highly accurate window-level voting)
        var urlToProfileMap: [String: String] = [:]
        for tab in tabs {
            if let profile = tab.profileName {
                let normalized = normalizeURL(tab.url)
                urlToProfileMap[normalized] = profile
            }
        }
        
        var seen = Set<String>()
        var items: [RestoreItem] = []
        for var item in primary + secondary.items {
            if item.kind == .browserPage || item.kind == .url {
                let t = item.label.trimmingCharacters(in: .whitespacesAndNewlines)
                let u = (item.url ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let lowerT = t.lowercased()
                let lowerU = u.lowercased()
                
                if t.isEmpty || u.isEmpty { continue }
                if lowerT == "new tab" || lowerT == "start page" || lowerT == "favorites" || lowerT == "untitled" || lowerT == "empty" { continue }
                if lowerU == "about:blank" || lowerU.hasPrefix("chrome://") || lowerU.hasPrefix("edge://") || lowerU.hasPrefix("brave://") || lowerU.hasPrefix("favorites://") || lowerU.hasPrefix("topsites://") {
                    continue
                }

                // Try to resolve the profile using our snapshot tab profile map first (overcoming active write delays)
                if let uStr = item.url {
                    let normalized = normalizeURL(uStr)
                    if let resolved = urlToProfileMap[normalized] {
                        item.profileName = resolved
                    }
                }

                if item.bundleId == "com.google.Chrome" && item.profileName == nil {
                    item.profileName = defaultChromeProfile
                } else if item.bundleId == "com.brave.Browser" && item.profileName == nil {
                    item.profileName = defaultBraveProfile
                } else if item.bundleId == "com.microsoft.edgemac" && item.profileName == nil {
                    item.profileName = defaultEdgeProfile
                }
            }
            let key: String
            switch item.kind {
            case .application: key = "app:\(item.bundleId ?? "")"
            case .url, .browserPage:
                if let u = item.url {
                    key = "page:\(normalizeURL(u))"
                } else {
                    key = "url:\(item.label)"
                }
            case .folder: key = "folder:\(item.path ?? "")"
            case .document: key = "doc:\(item.path ?? "")"
            case .terminalDirectory: key = "term:\(item.workingDirectory ?? "")"
            case .workspace: key = "ws:\(item.path ?? "")"
            }
            guard seen.insert(key).inserted else { continue }
            items.append(item)
        }
        let filtered = filterPrefixURLs(items)
        return WorkflowRestorePlan(items: filtered, createdAt: secondary.createdAt)
    }

    private static func normalizeURL(_ urlString: String) -> String {
        guard let url = URL(string: urlString) else {
            return urlString.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }
        var host = url.host ?? ""
        if host.hasPrefix("www.") {
            host = String(host.dropFirst(4))
        }
        let lowerHost = host.lowercased()
        var path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        
        if lowerHost != "youtu.be" {
            path = path.lowercased()
        }
        
        var normalized = "\(lowerHost)/\(path)".trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        
        if let components = URLComponents(string: urlString), let queryItems = components.queryItems {
            if lowerHost.contains("youtube.com") || lowerHost.contains("youtu.be") {
                if let vParam = queryItems.first(where: { $0.name == "v" })?.value {
                    normalized += "?v=\(vParam)"
                }
            } else if lowerHost.contains("google.") {
                if let qParam = queryItems.first(where: { $0.name == "q" })?.value {
                    normalized += "?q=\(qParam)"
                }
            }
        }
        return normalized
    }

    private static func filterPrefixURLs(_ items: [RestoreItem]) -> [RestoreItem] {
        let browserItems = items.filter { $0.kind == .browserPage || $0.kind == .url }
        let otherItems = items.filter { $0.kind != .browserPage && $0.kind != .url }
        
        var filteredBrowser: [RestoreItem] = []
        let sortedBrowser = browserItems.sorted { item1, item2 in
            let u1 = item1.url ?? ""
            let u2 = item2.url ?? ""
            return normalizeURL(u1).count > normalizeURL(u2).count
        }
        
        var seenDeeper = Set<String>()
        for item in sortedBrowser {
            guard let u = item.url else {
                filteredBrowser.append(item)
                continue
            }
            let normalized = normalizeURL(u)
            let profile = item.profileName ?? "default"
            let profileKey = "\(profile):\(normalized)"
            
            let isPrefix = seenDeeper.contains { deeper in
                deeper == profileKey || deeper.hasPrefix(profileKey + "/")
            }
            
            if isPrefix {
                continue
            }
            
            seenDeeper.insert(profileKey)
            filteredBrowser.append(item)
        }
        
        let allowedIds = Set(filteredBrowser.map(\.id) + otherItems.map(\.id))
        return items.filter { allowedIds.contains($0.id) }
    }
}
