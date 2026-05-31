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
        let generatedTitle: String?
        if (userTitle == nil || userTitle?.isEmpty == true),
           session.title == nil || session.title?.isEmpty == true {
            generatedTitle = await MainActor.run {
                SessionTitleGenerator.generate(from: events, startedAt: startedAt)
            }
        } else {
            generatedTitle = nil
        }

        var finalized = session
        finalized.appCount = Set(events.map(\.appBundleId)).count
        finalized.focusScore = Self.focusScore(from: events)
        if let generatedTitle { finalized.title = generatedTitle }

        await Self.finalizeMemory(&finalized, events: events, repository: repository)

        do {
            try await repository.save(finalized)
            EchoLog.persistence(
                "Finalize complete — \(finalized.id.uuidString), restore=\(finalized.restorePlan?.items.count ?? 0)"
            )
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

        let tabEligibility = await MainActor.run { EchoSettings.shared.tabEligibilitySeconds }
        let contextual = WorkflowContextCapture.items(from: events, tabEligibility: tabEligibility)
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
        return WorkflowRestorePlan(items: items, createdAt: secondary.createdAt)
    }

    private static func normalizeURL(_ urlString: String) -> String {
        guard let url = URL(string: urlString) else {
            return urlString.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }
        var host = url.host ?? ""
        if host.hasPrefix("www.") {
            host = String(host.dropFirst(4))
        }
        var path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        
        let lowerHost = host.lowercased()
        if lowerHost != "youtu.be" {
            path = path.lowercased()
        }
        
        var normalized = "\(host.lowercased())/\(path)".trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        
        if lowerHost.contains("youtube.com") || lowerHost.contains("youtu.be") {
            if let components = URLComponents(string: urlString) {
                if let vParam = components.queryItems?.first(where: { $0.name == "v" })?.value {
                    normalized += "?v=\(vParam)"
                }
            }
        }
        return normalized
    }
}
