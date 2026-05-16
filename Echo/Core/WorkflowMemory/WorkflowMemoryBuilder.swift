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
        events.compactMap { event -> BrowserContextEntry? in
            guard event.type == .browserTab || event.url != nil else { return nil }
            let host = domain(from: event.url) ?? event.appName
            let title = event.windowTitle ?? host
            return BrowserContextEntry(
                id: event.id,
                domain: host,
                title: title,
                urlHost: host,
                browser: event.appName,
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
        var items: [RestoreItem] = []
        var seen = Set<String>()

        for item in WorkflowContextCapture.items(from: events) {
            let key = restoreKey(item)
            guard seen.insert(key).inserted else { continue }
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

        for ctx in browserContexts.suffix(8) {
            guard let url = sanitizedURL(from: ctx), seen.insert("url:\(url)").inserted else { continue }
            items.append(RestoreItem(
                id: UUID(),
                kind: .browserPage,
                label: ctx.title,
                bundleId: browserBundleId(for: ctx.browser),
                url: url,
                path: nil,
                workingDirectory: nil
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

        return WorkflowRestorePlan(items: items, createdAt: session.endedAt ?? Date())
    }

    private static func restoreKey(_ item: RestoreItem) -> String {
        switch item.kind {
        case .application: return "app:\(item.bundleId ?? "")"
        case .url, .browserPage: return "url:\(item.url ?? "")"
        case .folder: return "folder:\(item.path ?? "")"
        case .document: return "doc:\(item.path ?? "")"
        case .terminalDirectory: return "term:\(item.workingDirectory ?? "")"
        case .workspace: return "ws:\(item.path ?? "")"
        }
    }

    private static func browserBundleId(for browserName: String) -> String? {
        switch browserName.lowercased() {
        case "safari": return "com.apple.Safari"
        case "google chrome": return "com.google.Chrome"
        case "arc": return "company.thebrowser.Browser"
        default: return nil
        }
    }

    private static func bundleDurations(from events: [ActivityEvent]) -> [String: TimeInterval] {
        var d: [String: TimeInterval] = [:]
        for e in events {
            if e.type == .appSwitch { d[e.appBundleId, default: 0] += max(e.duration, 1) }
            else { d[e.appBundleId, default: 0] += 1 }
        }
        return d
    }

    private static func sanitizedURL(from ctx: BrowserContextEntry) -> String? {
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
}
