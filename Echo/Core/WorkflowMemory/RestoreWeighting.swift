import Foundation

/// Filters restore items to meaningful context (focused > threshold or user-pinned).
nonisolated enum RestoreWeighting {

    static let minimumFocusDuration: TimeInterval = 120

    struct SelectableItem: Identifiable, Sendable {
        let item: RestoreItem
        let focusDuration: TimeInterval
        var isSelected: Bool
        var category: Category

        var id: String { RestoreWeighting.itemKey(item) }

        enum Category: String, Sendable {
            case application
            case browserTab
            case file
            case workspace
            case other
        }
    }

    nonisolated static func buildSelectableItems(
        from events: [ActivityEvent],
        plan: WorkflowRestorePlan,
        pinnedKeys: Set<String> = []
    ) -> [SelectableItem] {
        let sorted = events.sorted { $0.timestamp < $1.timestamp }
        var eventDurations: [UUID: TimeInterval] = [:]
        for i in 0..<sorted.count {
            let event = sorted[i]
            if i < sorted.count - 1 {
                let nextEvent = sorted[i + 1]
                eventDurations[event.id] = nextEvent.timestamp.timeIntervalSince(event.timestamp)
            } else {
                eventDurations[event.id] = event.duration > 0 ? event.duration : 60.0
            }
        }

        let focusByBundle = focusDurationByBundle(events, eventDurations: eventDurations)
        let focusByURL = focusDurationByURL(events, eventDurations: eventDurations)
        let focusByPath = focusDurationByPath(events, eventDurations: eventDurations)

        return plan.items.map { item in
            let key = itemKey(item)
            let duration = focusDuration(
                for: item,
                bundleMap: focusByBundle,
                urlMap: focusByURL,
                pathMap: focusByPath
            )
            let selected = pinnedKeys.contains(key)
                || duration >= minimumFocusDuration
            return SelectableItem(
                item: item,
                focusDuration: duration,
                isSelected: selected,
                category: category(for: item.kind)
            )
        }
    }

    nonisolated static func filteredPlan(from items: [SelectableItem]) -> WorkflowRestorePlan {
        let selected = items.filter(\.isSelected).map(\.item)
        return WorkflowRestorePlan(items: selected, createdAt: Date())
    }

    /// When weighting removes everything, restore top meaningful items by focus time.
    nonisolated static func fallbackPlan(
        from events: [ActivityEvent],
        plan: WorkflowRestorePlan,
        limit: Int = 8
    ) -> WorkflowRestorePlan {
        let items = buildSelectableItems(from: events, plan: plan)
            .sorted { $0.focusDuration > $1.focusDuration }
        let top = items.prefix(limit).map(\.item)
        if !top.isEmpty {
            return WorkflowRestorePlan(items: top, createdAt: plan.createdAt)
        }
        return WorkflowRestorePlan(items: Array(plan.items.prefix(limit)), createdAt: plan.createdAt)
    }

    nonisolated static func itemKey(_ item: RestoreItem) -> String {
        switch item.kind {
        case .application: return "app:\(item.bundleId ?? "")"
        case .url, .browserPage: return "url:\(item.url ?? "")"
        case .folder: return "folder:\(item.path ?? "")"
        case .document: return "doc:\(item.path ?? "")"
        case .terminalDirectory: return "term:\(item.workingDirectory ?? "")"
        case .workspace: return "ws:\(item.path ?? "")"
        }
    }

    private nonisolated static func category(for kind: RestoreItem.RestoreKind) -> SelectableItem.Category {
        switch kind {
        case .application: return .application
        case .url, .browserPage: return .browserTab
        case .document, .folder: return .file
        case .workspace, .terminalDirectory: return .workspace
        }
    }

    private nonisolated static func focusDurationByBundle(
        _ events: [ActivityEvent],
        eventDurations: [UUID: TimeInterval]
    ) -> [String: TimeInterval] {
        var map: [String: TimeInterval] = [:]
        for event in events where event.type == .appFocus || event.type == .appSwitch {
            let d = eventDurations[event.id] ?? (event.duration > 0 ? event.duration : 1)
            map[event.appBundleId, default: 0] += d
        }
        return map
    }

    private nonisolated static func focusDurationByURL(
        _ events: [ActivityEvent],
        eventDurations: [UUID: TimeInterval]
    ) -> [String: TimeInterval] {
        var map: [String: TimeInterval] = [:]
        for event in events {
            let isBrowser = event.type == .browserTab || 
                (event.type == .appFocus && (
                    event.appBundleId.contains("Chrome") ||
                    event.appBundleId.contains("Safari") ||
                    event.appBundleId.contains("Arc") ||
                    event.appBundleId.contains("Brave") ||
                    event.appBundleId.contains("Edge")
                ))
            guard isBrowser, let url = event.url else { continue }
            let normalized = normalizeURL(url)
            let d = eventDurations[event.id] ?? (event.duration > 0 ? event.duration : 1)
            map[normalized, default: 0] += d
        }
        return map
    }

    private nonisolated static func normalizeURL(_ urlString: String) -> String {
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

    private nonisolated static func focusDurationByPath(
        _ events: [ActivityEvent],
        eventDurations: [UUID: TimeInterval]
    ) -> [String: TimeInterval] {
        var map: [String: TimeInterval] = [:]
        for event in events where event.type == .appFocus || event.type == .appSwitch {
            guard let path = extractPath(from: event) else { continue }
            let normalized = path.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let d = eventDurations[event.id] ?? (event.duration > 0 ? event.duration : 1)
            map[normalized, default: 0] += d
        }
        return map
    }

    private nonisolated static func extractPath(from event: ActivityEvent) -> String? {
        if let urlStr = event.url, urlStr.hasPrefix("file://"), let url = URL(string: urlStr) {
            return url.path
        }
        guard let title = event.windowTitle else { return nil }
        if title.hasPrefix("/"), FileManager.default.fileExists(atPath: title) {
            return title
        }
        if let range = title.range(of: "/Users/") ?? title.range(of: "/Volumes/") {
            let path = String(title[range.lowerBound...])
            let trimmed = path.components(separatedBy: " — ").first
                ?? path.components(separatedBy: " – ").first
                ?? path
            return trimmed.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        let separators = [" — ", " – ", " - "]
        var candidates = [title]
        for sep in separators {
            candidates = candidates.flatMap { $0.components(separatedBy: sep) }
        }
        for candidate in candidates {
            let trimmed = candidate.trimmingCharacters(in: .whitespaces)
            if trimmed.hasSuffix(".xcworkspace") || trimmed.hasSuffix(".xcodeproj")
                || trimmed.hasSuffix(".code-workspace") {
                return trimmed
            }
            if let range = trimmed.range(of: "/Users/") ?? trimmed.range(of: "/Volumes/") {
                let path = String(trimmed[range.lowerBound...])
                let tr = path.components(separatedBy: " — ").first
                    ?? path.components(separatedBy: " – ").first
                    ?? path
                let trimmedPath = tr.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmedPath.hasSuffix(".xcworkspace") || trimmedPath.hasSuffix(".xcodeproj")
                    || trimmedPath.hasSuffix(".code-workspace") {
                    return trimmedPath
                }
            }
        }
        return nil
    }

    private nonisolated static func focusDuration(
        for item: RestoreItem,
        bundleMap: [String: TimeInterval],
        urlMap: [String: TimeInterval],
        pathMap: [String: TimeInterval]
    ) -> TimeInterval {
        if let url = item.url {
            let normalized = normalizeURL(url)
            if let d = urlMap[normalized] { return d }
        }
        if let path = item.path {
            let normalized = path.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if let d = pathMap[normalized] { return d }
        }
        if let cwd = item.workingDirectory {
            let normalized = cwd.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if let d = pathMap[normalized] { return d }
        }
        if let bundleId = item.bundleId, let d = bundleMap[bundleId] { return d }
        return 0
    }
}
