import Foundation

/// Slower, stability-first session identity — resists rapid-switch title churn.
enum StableWorkflowTitleGenerator {

    @MainActor
    static func generate(
        from events: [ActivityEvent],
        startedAt: Date,
        anchorBundleId: String?,
        previousIdentity: String?
    ) -> String {
        guard !events.isEmpty else {
            return timeOfDayPrefix(for: startedAt) + "Session"
        }

        if isRapidSwitching(events) {
            if let anchorBundleId {
                return singleAppIdentity(
                    bundleId: anchorBundleId,
                    events: events,
                    startedAt: startedAt
                )
            }
            if let previousIdentity, !previousIdentity.isEmpty, !isComboTitle(previousIdentity) {
                return previousIdentity
            }
        }

        if let repo = repoTitle(from: events), !isRapidSwitching(events) {
            return repo
        }

        let weights = appDurationWeights(from: events)
        let ranked = weights.sorted { $0.value > $1.value }
        guard let primary = ranked.first else {
            return timeOfDayPrefix(for: startedAt) + "Session"
        }

        if ranked.count >= 2,
           !isRapidSwitching(events),
           ranked[1].value >= primary.value * 0.35,
           primary.value >= 90,
           ranked[1].value >= 90 {
            let a = AppMetadataResolver.displayName(bundleId: primary.key, rawName: nil)
            let b = AppMetadataResolver.displayName(bundleId: ranked[1].key, rawName: nil)
            return "\(a) & \(b)"
        }

        if let anchorBundleId, weights[anchorBundleId, default: 0] >= primary.value * 0.5 {
            return singleAppIdentity(bundleId: anchorBundleId, events: events, startedAt: startedAt)
        }

        return singleAppIdentity(bundleId: primary.key, events: events, startedAt: startedAt)
    }

    // MARK: - Rapid switch detection

    private static func isRapidSwitching(_ events: [ActivityEvent]) -> Bool {
        let recent = events.suffix(24)
        let focusEvents = recent.filter { $0.type == .appFocus }.count
        if focusEvents >= 4 { return true }

        let recentSwitches = recent.filter { $0.type == .appSwitch }
        let shortBursts = recentSwitches.filter { $0.duration < 8 }.count
        return shortBursts >= 3
    }

    private static func isComboTitle(_ title: String) -> Bool {
        title.contains(" & ")
    }

    // MARK: - Single-app identity

    @MainActor
    private static func singleAppIdentity(
        bundleId: String,
        events: [ActivityEvent],
        startedAt: Date
    ) -> String {
        if let terminal = terminalTitle(from: events, bundleId: bundleId) { return terminal }
        if let browser = browserTitle(from: events, bundleId: bundleId) { return browser }
        if let repo = repoTitle(from: events, bundleId: bundleId) { return repo }

        let name = AppMetadataResolver.displayName(bundleId: bundleId, rawName: nil)
        return "\(workflowVerb(for: bundleId)) \(name)"
    }

    // MARK: - Weights

    private static func appDurationWeights(from events: [ActivityEvent]) -> [String: TimeInterval] {
        var weights: [String: TimeInterval] = [:]
        for event in events {
            switch event.type {
            case .appSwitch:
                weights[event.appBundleId, default: 0] += max(event.duration, 0.5)
            case .appFocus:
                weights[event.appBundleId, default: 0] += 2
            default:
                weights[event.appBundleId, default: 0] += 0.25
            }
        }
        return weights
    }

    // MARK: - Context heuristics (scoped to bundle when anchoring)

    private static func repoTitle(from events: [ActivityEvent], bundleId: String? = nil) -> String? {
        for event in events.reversed() {
            if let bundleId, event.appBundleId != bundleId { continue }
            guard let title = event.windowTitle, !title.isEmpty else { continue }
            if let repo = extractRepoName(from: title) { return "Working in \(repo)" }
        }
        return nil
    }

    private static func browserTitle(from events: [ActivityEvent], bundleId: String? = nil) -> String? {
        let browsers: Set<String> = [
            "com.apple.Safari", "com.google.Chrome", "company.thebrowser.Browser",
            "com.brave.Browser", "com.microsoft.edgemac"
        ]
        for event in events.reversed() {
            if let bundleId, event.appBundleId != bundleId { continue }
            guard browsers.contains(event.appBundleId) else { continue }
            if let title = event.windowTitle, !title.isEmpty, title.count < 48 { return title }
        }
        return nil
    }

    private static func terminalTitle(from events: [ActivityEvent], bundleId: String? = nil) -> String? {
        let terminals: Set<String> = [
            "com.apple.Terminal", "com.googlecode.iterm2", "dev.warp.Warp-Stable"
        ]
        for event in events.reversed() {
            if let bundleId, event.appBundleId != bundleId { continue }
            guard terminals.contains(event.appBundleId) else { continue }
            if let title = event.windowTitle, !title.isEmpty, title.count <= 40 { return title }
        }
        return nil
    }

    private static func extractRepoName(from windowTitle: String) -> String? {
        if windowTitle.contains(".xcodeproj") || windowTitle.contains(" — ") {
            let parts = windowTitle.components(separatedBy: " — ")
            if let last = parts.last?
                .replacingOccurrences(of: ".xcodeproj", with: "")
                .trimmingCharacters(in: .whitespaces),
               !last.isEmpty, last.count <= 32 {
                return last
            }
        }
        return nil
    }

    private static func workflowVerb(for bundleId: String) -> String {
        switch bundleId {
        case "com.apple.dt.Xcode", "com.microsoft.VSCode", "com.todesktop.230313mzl4w4u92",
             "com.google.antigravity-ide", "com.google.antigravity":
            return "Building in"
        case "com.apple.Safari", "com.google.Chrome", "company.thebrowser.Browser",
             "com.brave.Browser", "com.microsoft.edgemac":
            return "Research in"
        case "com.figma.Desktop":
            return "Designing in"
        case "com.apple.Terminal", "com.googlecode.iterm2", "dev.warp.Warp-Stable":
            return "Working in"
        default:
            return "Focused in"
        }
    }

    private static func timeOfDayPrefix(for date: Date) -> String {
        let hour = Calendar.current.component(.hour, from: date)
        switch hour {
        case 5..<12: return "Morning "
        case 12..<17: return "Afternoon "
        case 17..<22: return "Evening "
        default: return "Late night "
        }
    }
}
