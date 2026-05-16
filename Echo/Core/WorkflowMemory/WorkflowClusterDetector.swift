import Foundation

nonisolated enum WorkflowClusterDetector {

    private static let coding: Set<String> = [
        "com.apple.dt.Xcode", "com.microsoft.VSCode", "com.todesktop.230313mzl4w4u92",
        "com.apple.Terminal", "com.googlecode.iterm2", "dev.warp.Warp-Stable"
    ]
    private static let research: Set<String> = [
        "com.apple.Safari", "com.google.Chrome", "company.thebrowser.Browser",
        "com.brave.Browser", "com.microsoft.edgemac", "com.apple.finder"
    ]
    private static let writing: Set<String> = [
        "com.apple.Notes", "com.apple.TextEdit", "com.notion.id", "com.apple.iWork.Pages"
    ]
    private static let design: Set<String> = [
        "com.figma.Desktop", "com.bohemiancoding.sketch3", "com.adobe.Photoshop"
    ]
    private static let communication: Set<String> = [
        "com.apple.mail", "com.microsoft.Outlook", "com.tinyspeck.slackmacgap",
        "com.hnc.Discord", "com.apple.MobileSMS"
    ]

    static func detect(from events: [ActivityEvent]) -> WorkflowCluster {
        var scores: [WorkflowCluster: Double] = [:]
        let weights = appWeights(from: events)

        for (bundleId, weight) in weights {
            if coding.contains(bundleId) { scores[.coding, default: 0] += weight }
            if research.contains(bundleId) { scores[.research, default: 0] += weight }
            if writing.contains(bundleId) { scores[.writing, default: 0] += weight }
            if design.contains(bundleId) { scores[.design, default: 0] += weight }
            if communication.contains(bundleId) { scores[.communication, default: 0] += weight }
        }

        guard let top = scores.max(by: { $0.value < $1.value }), top.value > 0 else {
            return .mixed
        }

        let total = scores.values.reduce(0, +)
        if top.value / total < 0.45 { return .mixed }
        return top.key
    }

    static func signature(from events: [ActivityEvent]) -> [String] {
        let weights = appWeights(from: events)
        return weights.sorted { $0.value > $1.value }.prefix(4).map(\.key)
    }

    private static func appWeights(from events: [ActivityEvent]) -> [String: Double] {
        var weights: [String: Double] = [:]
        for event in events {
            switch event.type {
            case .appSwitch: weights[event.appBundleId, default: 0] += max(event.duration, 1)
            case .appFocus, .browserTab: weights[event.appBundleId, default: 0] += 2
            default: weights[event.appBundleId, default: 0] += 0.5
            }
        }
        return weights
    }
}
