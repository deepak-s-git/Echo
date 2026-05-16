import Foundation

/// Instant focus copy for the hero card — single-app only, never combo titles.
enum LiveTitleFormatter {

    @MainActor
    static func instantHeadline(
        bundleId: String,
        appName: String,
        windowTitle: String?
    ) -> String {
        let name = AppMetadataResolver.displayName(bundleId: bundleId, rawName: appName)

        if let windowTitle, !windowTitle.isEmpty {
            if let project = shortProjectName(from: windowTitle) {
                return project
            }
        }

        return name
    }

    @MainActor
    static func provisional(
        bundleId: String,
        appName: String,
        windowTitle: String?
    ) -> String {
        let name = AppMetadataResolver.displayName(bundleId: bundleId, rawName: appName)

        if let windowTitle, !windowTitle.isEmpty {
            if windowTitle.contains(".xcodeproj") || windowTitle.contains(" — ") {
                let parts = windowTitle.components(separatedBy: " — ")
                if let project = parts.last?
                    .replacingOccurrences(of: ".xcodeproj", with: "")
                    .trimmingCharacters(in: .whitespaces),
                   !project.isEmpty, project.count <= 36 {
                    return "Working in \(project)"
                }
            }
            if windowTitle.count <= 40 {
                return windowTitle
            }
        }

        return "\(workflowVerb(for: bundleId)) \(name)"
    }

    private static func shortProjectName(from windowTitle: String) -> String? {
        if windowTitle.contains(" — ") {
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
        case "com.apple.dt.Xcode", "com.microsoft.VSCode", "com.todesktop.230313mzl4w4u92":
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
}
