import AppKit

/// Resolves human-readable app names from bundle IDs. Never surfaces raw bundle IDs in UI.
nonisolated enum AppMetadataResolver {

    private static let cache = NSCache<NSString, NSString>()

    private static let knownNames: [String: String] = [
        "com.apple.dt.Xcode": "Xcode",
        "com.microsoft.VSCode": "VS Code",
        "com.todesktop.230313mzl4w4u92": "Cursor",
        "com.apple.Safari": "Safari",
        "com.google.Chrome": "Chrome",
        "company.thebrowser.Browser": "Arc",
        "com.brave.Browser": "Brave",
        "com.microsoft.edgemac": "Edge",
        "com.apple.Terminal": "Terminal",
        "com.googlecode.iterm2": "iTerm",
        "com.figma.Desktop": "Figma",
        "com.notion.id": "Notion",
        "com.apple.mail": "Mail",
        "com.apple.Notes": "Notes",
        "com.spotify.client": "Spotify",
        "com.apple.finder": "Finder",
        "com.google.antigravity": "Antigravity IDE",
        "com.google.antigravity-ide": "Antigravity IDE"
    ]

    static func displayName(bundleId: String, rawName: String?) -> String {
        if let known = knownNames[bundleId] { return known }

        if let cached = cache.object(forKey: bundleId as NSString) {
            return cached as String
        }

        if let raw = rawName, !looksLikeBundleId(raw) {
            cache.setObject(raw as NSString, forKey: bundleId as NSString)
            return raw
        }

        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
            let name = FileManager.default.displayName(atPath: url.path)
            if !looksLikeBundleId(name) {
                cache.setObject(name as NSString, forKey: bundleId as NSString)
                return name
            }
        }

        let humanized = humanizedBundleId(bundleId)
        cache.setObject(humanized as NSString, forKey: bundleId as NSString)
        return humanized
    }

    static func looksLikeBundleId(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return true }
        if trimmed.contains(" ") { return false }
        if trimmed.hasPrefix("com.") || trimmed.hasPrefix("org.") || trimmed.hasPrefix("io.") {
            return true
        }
        return trimmed.contains(".") && trimmed == trimmed.lowercased()
    }

    static func humanizedBundleId(_ bundleId: String) -> String {
        if let known = knownNames[bundleId] { return known }
        let segment = bundleId.split(separator: ".").last.map(String.init) ?? bundleId
        guard !segment.isEmpty else { return "App" }
        return segment.prefix(1).uppercased() + segment.dropFirst()
    }
}
