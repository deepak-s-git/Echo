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
        let focusByBundle = focusDurationByBundle(events)
        let focusByURL = focusDurationByURL(events)

        return plan.items.map { item in
            let key = itemKey(item)
            let duration = focusDuration(for: item, bundleMap: focusByBundle, urlMap: focusByURL)
            let selected = pinnedKeys.contains(key)
                || duration >= minimumFocusDuration
                || item.kind == .browserPage
                || item.kind == .document
                || item.kind == .workspace
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

    private nonisolated static func focusDurationByBundle(_ events: [ActivityEvent]) -> [String: TimeInterval] {
        var map: [String: TimeInterval] = [:]
        for event in events where event.type == .appFocus || event.type == .appSwitch {
            let d = event.duration > 0 ? event.duration : 1
            map[event.appBundleId, default: 0] += d
        }
        return map
    }

    private nonisolated static func focusDurationByURL(_ events: [ActivityEvent]) -> [String: TimeInterval] {
        var map: [String: TimeInterval] = [:]
        for event in events {
            guard event.type == .browserTab, let url = event.url else { continue }
            map[url, default: 0] += event.duration > 0 ? event.duration : 1
        }
        return map
    }

    private nonisolated static func focusDuration(
        for item: RestoreItem,
        bundleMap: [String: TimeInterval],
        urlMap: [String: TimeInterval]
    ) -> TimeInterval {
        if let url = item.url, let d = urlMap[url] { return d }
        if let bundleId = item.bundleId, let d = bundleMap[bundleId] { return d }
        return 0
    }
}
