import Foundation

nonisolated enum WorkflowMemoryBuilder {

    static func build(session: Session, events: [ActivityEvent]) -> WorkflowMemory {
        let cluster = WorkflowCluster(rawValue: session.workflowCluster ?? "")
            ?? WorkflowClusterDetector.detect(from: events)
        let phases = WorkflowPhaseAnalyzer.phases(from: events)
        let transitions = buildTransitions(from: events)
        let browserContexts = buildBrowserContexts(from: events)
        let interruptions = detectInterruptions(in: events)
        let continuity = computeContinuityScore(
            events: events,
            interruptions: interruptions,
            session: session
        )
        let plan = WorkflowRestorePlanBuilder.build(
            session: session,
            events: events,
            browserContexts: browserContexts
        )

        return WorkflowMemory(
            session: session,
            events: events,
            cluster: cluster,
            phases: phases,
            appTransitions: transitions,
            browserContexts: browserContexts,
            interruptions: interruptions,
            continuityScore: continuity,
            restorePlan: plan
        )
    }

    // MARK: - Transitions

    private static func buildTransitions(from events: [ActivityEvent]) -> [AppTransition] {
        var result: [AppTransition] = []
        var previousBundleId: String?
        var previousAppName: String?

        for event in events.sorted(by: { $0.timestamp < $1.timestamp })
            where event.type == .appFocus || event.type == .appSwitch {
            switch event.type {
            case .appFocus:
                if let prev = previousBundleId, prev == event.appBundleId { continue }
                result.append(AppTransition(
                    id: event.id,
                    fromApp: previousAppName,
                    toApp: event.appName,
                    toBundleId: event.appBundleId,
                    timestamp: event.timestamp,
                    duration: 0
                ))
                previousBundleId = event.appBundleId
                previousAppName = event.appName
            case .appSwitch:
                previousBundleId = event.appBundleId
                previousAppName = event.appName
            default:
                break
            }
        }
        return collapseTransitions(result)
    }

    /// Merges consecutive transitions into the same app (e.g. Cursor → Cursor).
    private static func collapseTransitions(_ transitions: [AppTransition]) -> [AppTransition] {
        guard !transitions.isEmpty else { return [] }
        var collapsed: [AppTransition] = []
        for transition in transitions {
            if let last = collapsed.last,
               last.toBundleId == transition.toBundleId,
               last.fromApp == transition.fromApp {
                continue
            }
            collapsed.append(transition)
        }
        return collapsed
    }

    // MARK: - Browser

    static func browserContexts(from events: [ActivityEvent]) -> [BrowserContextEntry] {
        buildBrowserContexts(from: events)
    }

    private static func buildBrowserContexts(from events: [ActivityEvent]) -> [BrowserContextEntry] {
        var seen = Set<String>()
        return events.compactMap { event -> BrowserContextEntry? in
            guard event.type == .browserTab || event.url != nil else { return nil }
            let host = domain(from: event.url) ?? event.appName
            let lowerHost = host.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            guard !lowerHost.isEmpty && seen.insert(lowerHost).inserted else { return nil }
            let title = event.windowTitle ?? host
            return BrowserContextEntry(
                id: event.id,
                domain: host,
                title: title,
                urlHost: host,
                url: event.url,
                browser: event.appName,
                profileName: event.profileName,
                capturedAt: event.timestamp
            )
        }
    }

    private static func domain(from urlString: String?) -> String? {
        guard let urlString, let url = URL(string: urlString), let host = url.host else {
            return nil
        }
        return host.replacingOccurrences(of: "www.", with: "")
    }

    // MARK: - Interruptions

    private static func detectInterruptions(in events: [ActivityEvent]) -> [WorkflowInterruption] {
        guard events.count >= 2 else { return [] }
        var gaps: [WorkflowInterruption] = []
        let sorted = events.sorted { $0.timestamp < $1.timestamp }

        for i in 1..<sorted.count {
            let gap = sorted[i].timestamp.timeIntervalSince(sorted[i - 1].timestamp)
            if gap >= EchoConfig.interruptionThreshold {
                gaps.append(WorkflowInterruption(
                    id: UUID(),
                    startedAt: sorted[i - 1].timestamp,
                    duration: gap
                ))
            }
        }
        return gaps
    }

  private static func computeContinuityScore(
        events: [ActivityEvent],
        interruptions: [WorkflowInterruption],
        session: Session
    ) -> Double {
        let focus = session.focusScore
        let interruptionPenalty = min(Double(interruptions.count) * 0.08, 0.35)
        let switchCount = events.filter { $0.type == .appSwitch }.count
        let switchPenalty = min(Double(switchCount) * 0.02, 0.25)
        return min(max(focus - interruptionPenalty - switchPenalty, 0.15), 1)
    }
}

// MARK: - Phase analyzer

nonisolated enum WorkflowPhaseAnalyzer {

    static func phases(from events: [ActivityEvent]) -> [WorkflowPhase] {
        var phases: [WorkflowPhase] = []
        var currentBundle: String?
        var currentName: String = ""
        var phaseStart: Date?
        var phaseId = UUID()

        func closePhase(at end: Date) {
            guard let start = phaseStart, let bundle = currentBundle else { return }
            let duration = end.timeIntervalSince(start)
            guard duration >= 30 else { return }
            phases.append(WorkflowPhase(
                id: phaseId,
                title: phaseTitle(for: currentName, bundleId: bundle),
                appName: currentName,
                bundleId: bundle,
                startedAt: start,
                endedAt: end,
                duration: duration
            ))
        }

        for event in events.sorted(by: { $0.timestamp < $1.timestamp }) {
            switch event.type {
            case .appFocus:
                if phaseStart != nil, currentBundle != event.appBundleId {
                    closePhase(at: event.timestamp)
                }
                if currentBundle != event.appBundleId {
                    currentBundle = event.appBundleId
                    currentName = event.appName
                    phaseStart = event.timestamp
                    phaseId = UUID()
                }
            case .appSwitch where event.duration > 0:
                if currentBundle == event.appBundleId {
                    continue
                }
                closePhase(at: event.timestamp)
                currentBundle = nil
                phaseStart = nil
            default:
                break
            }
        }

        if phaseStart != nil {
            let end = events.last?.timestamp ?? Date()
            closePhase(at: end)
        }

        return phases
    }

    private static func phaseTitle(for appName: String, bundleId: String) -> String {
        let cluster = WorkflowClusterDetector.detect(from: [
            ActivityEvent(
                id: UUID(), sessionId: UUID(), timestamp: Date(),
                type: .appFocus, appBundleId: bundleId, appName: appName,
                windowTitle: nil, url: nil, duration: 0
            )
        ])
        return "\(cluster.label) · \(appName)"
    }
}

// MARK: - Restore plan builder

nonisolated enum WorkflowRestorePlanBuilder {

    static func build(
        session: Session,
        events: [ActivityEvent],
        browserContexts: [BrowserContextEntry]
    ) -> WorkflowRestorePlan {
        let threshold = {
            let delay = UserDefaults.standard.double(forKey: "echo.settings.browserCaptureDelaySeconds")
            let hold = UserDefaults.standard.double(forKey: "echo.settings.tabEligibilitySeconds")
            let actualDelay = delay > 0 ? delay : 1.2
            let actualHold = hold > 0 ? hold : 12.0
            return actualDelay + actualHold
        }()

        var items: [RestoreItem] = []
        var seen = Set<String>()

        for item in WorkflowContextCapture.items(from: events, tabEligibility: threshold, sessionEndDate: session.endedAt) {
            let key = restoreKey(item)
            guard seen.insert(key).inserted else { continue }
            if item.kind == .browserPage || item.kind == .url, let u = item.url {
                let host = URL(string: u)?.host?.lowercased() ?? ""
                let profile = item.profileName ?? "default"
                let titleKey = "title:\(profile):\(host):\(item.label.lowercased().trimmingCharacters(in: .whitespacesAndNewlines))"
                _ = seen.insert(titleKey)
            }
            items.append(item)
        }

        let rankedBundles = bundleDurations(from: events)
            .sorted { $0.value > $1.value }
            .prefix(5)

        for (bundleId, _) in rankedBundles {
            let key = "app:\(bundleId)"
            guard seen.insert(key).inserted else { continue }
            let name = AppMetadataResolver.humanizedBundleId(bundleId)
            items.append(RestoreItem(
                id: UUID(),
                kind: .application,
                label: name,
                bundleId: bundleId,
                url: nil,
                path: nil,
                workingDirectory: nil
            ))
        }

        let sorted = events.sorted { $0.timestamp < $1.timestamp }
        var eventDurations: [UUID: TimeInterval] = [:]
        let focusEvents = sorted.filter { $0.type == .appFocus || $0.type == .appSwitch }
        for i in 0..<focusEvents.count {
            let event = focusEvents[i]
            if i < focusEvents.count - 1 {
                let nextEvent = focusEvents[i + 1]
                eventDurations[event.id] = nextEvent.timestamp.timeIntervalSince(event.timestamp)
            } else {
                let lastEventTimestamp = session.endedAt ?? sorted.last?.timestamp ?? event.timestamp
                let duration = lastEventTimestamp.timeIntervalSince(event.timestamp)
                eventDurations[event.id] = max(duration, 0.0)
            }
        }

        var domainDurations: [String: TimeInterval] = [:]
        for event in sorted {
            let d = eventDurations[event.id] ?? 0.0
            let host = domain(from: event.url) ?? event.appName
            domainDurations[host.lowercased(), default: 0] += d
        }

        var urlDurations: [String: TimeInterval] = [:]
        for event in sorted {
            let d = eventDurations[event.id] ?? 0.0
            let urlString = event.url ?? {
                guard let title = event.windowTitle, title.contains(".") else { return nil }
                if title.hasPrefix("http") { return title }
                return "https://\(title)"
            }()
            if let urlString {
                let normalized = normalizeURL(urlString)
                urlDurations[normalized, default: 0] += d
            }
        }

        for ctx in browserContexts.suffix(8) {
            let totalD = domainDurations[ctx.domain.lowercased()] ?? 0.0
            if totalD < threshold { continue }
            guard let url = sanitizedURL(from: ctx) else { continue }
            
            let normalized = normalizeURL(url)
            let urlD = urlDurations[normalized] ?? 0.0
            if urlD < threshold { continue }
            
            let t = ctx.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let u = url.trimmingCharacters(in: .whitespacesAndNewlines)
            let lowerT = t.lowercased()
            let lowerU = u.lowercased()
            
            if t.isEmpty || u.isEmpty { continue }
            if lowerT == "new tab" || lowerT == "start page" || lowerT == "favorites" || lowerT == "untitled" || lowerT == "empty" { continue }
            if lowerU == "about:blank" || lowerU.hasPrefix("chrome://") || lowerU.hasPrefix("edge://") || lowerU.hasPrefix("brave://") || lowerU.hasPrefix("favorites://") || lowerU.hasPrefix("topsites://") {
                continue
            }

            // Detect local PDF or local file in browser context
            let isPDF = lowerT.contains(".pdf") || lowerU.contains(".pdf")
            let isLocal = lowerU.hasPrefix("file://") || lowerU.contains("/users/") || lowerU.contains("/volumes/")

            if isPDF || isLocal {
                let cleanLabel: String
                if isPDF, let range = t.lowercased().range(of: ".pdf") {
                    cleanLabel = String(t[..<range.upperBound])
                } else if isLocal {
                    cleanLabel = (u as NSString).lastPathComponent
                } else {
                    cleanLabel = t
                }
                
                let path = lowerU.hasPrefix("file://") ? URL(string: u)?.path : u
                let key = "doc:\(cleanLabel)"
                guard seen.insert(key).inserted else { continue }
                items.append(RestoreItem(
                    id: UUID(),
                    kind: .document,
                    label: cleanLabel,
                    bundleId: nil, // set to nil to group under Files & Documents!
                    url: url,
                    path: path,
                    workingDirectory: nil
                ))
                continue
            }

            let host = URL(string: url)?.host?.lowercased() ?? ctx.domain.lowercased()
            let profile = ctx.profileName ?? "default"
            let titleKey = "title:\(profile):\(host):\(lowerT)"

            guard seen.insert("page:\(normalizeURL(url))").inserted else { continue }
            guard seen.insert(titleKey).inserted else { continue }

            items.append(RestoreItem(
                id: UUID(),
                kind: .browserPage,
                label: ctx.title,
                bundleId: browserBundleId(for: ctx.browser),
                url: url,
                path: nil,
                workingDirectory: nil,
                profileName: ctx.profileName
            ))
        }

        if let folder = extractProjectPath(from: events), seen.insert("folder:\(folder)").inserted {
            items.append(RestoreItem(
                id: UUID(),
                kind: .folder,
                label: (folder as NSString).lastPathComponent,
                bundleId: nil,
                url: nil,
                path: folder,
                workingDirectory: nil
            ))
        }

        if let cwd = extractTerminalDirectory(from: events), seen.insert("term:\(cwd)").inserted {
            items.append(RestoreItem(
                id: UUID(),
                kind: .terminalDirectory,
                label: "Terminal — \((cwd as NSString).lastPathComponent)",
                bundleId: "com.apple.Terminal",
                url: nil,
                path: nil,
                workingDirectory: cwd
            ))
        }

        let filtered = filterPrefixURLs(items)
        return WorkflowRestorePlan(items: filtered, createdAt: session.endedAt ?? Date())
    }

    private static func restoreKey(_ item: RestoreItem) -> String {
        switch item.kind {
        case .application: return "app:\(item.bundleId ?? "")"
        case .url, .browserPage:
            if let u = item.url {
                return "page:\(normalizeURL(u))"
            }
            return "url:\(item.label)"
        case .folder: return "folder:\(item.path ?? "")"
        case .document: return "doc:\(item.path ?? "")"
        case .terminalDirectory: return "term:\(item.workingDirectory ?? "")"
        case .workspace: return "ws:\(item.path ?? "")"
        }
    }

    private static func browserBundleId(for browserName: String) -> String? {
        let name = browserName.lowercased()
        if name.contains("safari") { return "com.apple.Safari" }
        if name.contains("chrome") { return "com.google.Chrome" }
        if name.contains("arc") { return "company.thebrowser.Browser" }
        if name.contains("brave") { return "com.brave.Browser" }
        if name.contains("edge") { return "com.microsoft.edgemac" }
        return nil
    }

    private static func bundleDurations(from events: [ActivityEvent]) -> [String: TimeInterval] {
        var d: [String: TimeInterval] = [:]
        for e in events {
            if e.type == .appSwitch { d[e.appBundleId, default: 0] += max(e.duration, 1) }
            else { d[e.appBundleId, default: 0] += 1 }
        }
        return d
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

    private static func domain(from urlString: String?) -> String? {
        guard let urlString, let url = URL(string: urlString), let host = url.host else {
            return nil
        }
        return host.replacingOccurrences(of: "www.", with: "")
    }

    private static func sanitizedURL(from ctx: BrowserContextEntry) -> String? {
        if let exactURL = ctx.url, URL(string: exactURL) != nil {
            return exactURL
        }
        guard ctx.title.count < 120 else { return nil }
        if ctx.urlHost.contains(".") { return "https://\(ctx.urlHost)" }
        return nil
    }

    private static func extractProjectPath(from events: [ActivityEvent]) -> String? {
        for event in events.reversed() {
            guard let title = event.windowTitle else { continue }
            if title.contains("/Users/") || title.contains("/Volumes/") {
                if let range = title.range(of: "/Users/") ?? title.range(of: "/Volumes/") {
                    let path = String(title[range.lowerBound...])
                    let trimmed = path.components(separatedBy: " — ").first ?? path
                    if FileManager.default.fileExists(atPath: trimmed) { return trimmed }
                }
            }
        }
        return nil
    }

    private static func extractTerminalDirectory(from events: [ActivityEvent]) -> String? {
        let terminals: Set<String> = [
            "com.apple.Terminal", "com.googlecode.iterm2", "dev.warp.Warp-Stable"
        ]
        for event in events.reversed() where terminals.contains(event.appBundleId) {
            if let title = event.windowTitle, title.hasPrefix("/"), FileManager.default.fileExists(atPath: title) {
                return title
            }
        }
        return nil
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
