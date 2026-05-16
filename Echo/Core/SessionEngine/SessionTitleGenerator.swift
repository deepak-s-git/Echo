import Foundation

/// Builds human-readable session titles from tracked activity — no AI.
enum SessionTitleGenerator {

    @MainActor
    static func generate(from events: [ActivityEvent], startedAt: Date) -> String {
        guard !events.isEmpty else {
            return timeOfDayPrefix(for: startedAt) + "Session"
        }

        let weights = appDurationWeights(from: events)
        let ranked = weights.sorted { $0.value > $1.value }

        if let repoTitle = repoTitle(from: events) {
            return repoTitle
        }

        if let browserTitle = browserTitle(from: events) {
            return browserTitle
        }

        if let terminalTitle = terminalTitle(from: events) {
            return terminalTitle
        }

        guard let primary = ranked.first else {
            return timeOfDayPrefix(for: startedAt) + "Session"
        }

        if ranked.count >= 2, ranked[1].value >= primary.value * 0.35 {
            let a = resolvedName(bundleId: primary.key)
            let b = resolvedName(bundleId: ranked[1].key)
            return "\(a) & \(b)"
        }

        let appLabel = resolvedName(bundleId: primary.key)
        let verb = workflowVerb(for: primary.key)
        return "\(verb) \(appLabel)"
    }

    @MainActor
    private static func resolvedName(bundleId: String) -> String {
        AppMetadataResolver.displayName(bundleId: bundleId, rawName: nil)
    }

    // MARK: - Duration weights

    private static func appDurationWeights(from events: [ActivityEvent]) -> [String: TimeInterval] {
        var weights: [String: TimeInterval] = [:]

        for event in events {
            switch event.type {
            case .appSwitch:
                weights[event.appBundleId, default: 0] += max(event.duration, 0.5)
            case .appFocus:
                weights[event.appBundleId, default: 0] += 1
            default:
                weights[event.appBundleId, default: 0] += 0.25
            }
        }

        return weights
    }

    // MARK: - Context heuristics

    private static func repoTitle(from events: [ActivityEvent]) -> String? {
        for event in events.reversed() {
            guard let title = event.windowTitle, !title.isEmpty else { continue }
            if let repo = extractRepoName(from: title) {
                return "Working in \(repo)"
            }
        }
        return nil
    }

    private static func browserTitle(from events: [ActivityEvent]) -> String? {
        let browserBundles: Set<String> = [
            "com.apple.Safari",
            "com.google.Chrome",
            "company.thebrowser.Browser",
            "com.brave.Browser",
            "com.microsoft.edgemac",
            "org.mozilla.firefox"
        ]

        for event in events.reversed() {
            guard browserBundles.contains(event.appBundleId) else { continue }
            if let url = event.url, let host = URL(string: url)?.host {
                return "Browsing \(host)"
            }
            if let title = event.windowTitle, !title.isEmpty, title.count < 48 {
                return title
            }
        }
        return nil
    }

    private static func terminalTitle(from events: [ActivityEvent]) -> String? {
        let terminalBundles: Set<String> = [
            "com.apple.Terminal",
            "com.googlecode.iterm2",
            "dev.warp.Warp-Stable",
            "net.kovidgoyal.kitty"
        ]

        for event in events.reversed() {
            guard terminalBundles.contains(event.appBundleId) else { continue }
            if let title = event.windowTitle, !title.isEmpty {
                let trimmed = title
                    .replacingOccurrences(of: " — zsh", with: "")
                    .replacingOccurrences(of: " - zsh", with: "")
                if trimmed.count <= 40 {
                    return trimmed
                }
            }
        }

        if events.contains(where: { terminalBundles.contains($0.appBundleId) }) {
            return "Terminal session"
        }
        return nil
    }

    private static func extractRepoName(from windowTitle: String) -> String? {
        // Xcode: "MyApp — MyApp.xcodeproj"
        if windowTitle.contains(".xcodeproj") || windowTitle.contains(" — ") {
            let parts = windowTitle.components(separatedBy: " — ")
            if let last = parts.last {
                let name = last
                    .replacingOccurrences(of: ".xcodeproj", with: "")
                    .trimmingCharacters(in: .whitespaces)
                if !name.isEmpty, name.count <= 32 { return name }
            }
        }

        // VS Code / Cursor: "file.swift — project"
        if windowTitle.contains(" — ") {
            let parts = windowTitle.components(separatedBy: " — ")
            if let project = parts.last?.trimmingCharacters(in: .whitespaces),
               !project.isEmpty, project.count <= 32 {
                return project
            }
        }

        // Path-like: ~/dev/my-repo/...
        if windowTitle.contains("/") {
            let components = windowTitle.split(separator: "/").map(String.init)
            if let last = components.last, last.count <= 32, !last.contains(".") {
                return last
            }
        }

        return nil
    }

    private static func workflowVerb(for bundleId: String) -> String {
        switch bundleId {
        case "com.apple.dt.Xcode", "com.microsoft.VSCode", "com.todesktop.230313mzl4w4u92":
            return "Building in"
        case "com.apple.Safari", "com.google.Chrome", "company.thebrowser.Browser",
             "com.brave.Browser", "com.microsoft.edgemac":
            return "Research in"
        case "com.figma.Desktop", "com.bohemiancoding.sketch3":
            return "Designing in"
        case "com.apple.Terminal", "com.googlecode.iterm2", "dev.warp.Warp-Stable":
            return "Working in"
        case "com.apple.mail", "com.microsoft.Outlook":
            return "Catching up in"
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
