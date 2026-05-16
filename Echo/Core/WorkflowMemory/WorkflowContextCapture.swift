import Foundation

/// Extracts restorable working context from window titles, URLs, and bundle IDs.
nonisolated enum WorkflowContextCapture {

  static func items(from events: [ActivityEvent]) -> [RestoreItem] {
    var items: [RestoreItem] = []
    var seen = Set<String>()

    for event in events.reversed() {
      items.append(contentsOf: itemsForEvent(event, seen: &seen))
    }
    return items
  }

  static func itemsForEvent(_ event: ActivityEvent, seen: inout Set<String>) -> [RestoreItem] {
    switch event.appBundleId {
    case "com.apple.finder":
      return finderItems(title: event.windowTitle, seen: &seen)
    case "com.apple.Preview":
      return documentItems(title: event.windowTitle, seen: &seen)
    case "com.apple.dt.Xcode":
      return workspaceItems(title: event.windowTitle, bundleId: event.appBundleId, seen: &seen)
    case "com.microsoft.VSCode", "com.todesktop.230313mzl4w4u92":
      return workspaceItems(title: event.windowTitle, bundleId: event.appBundleId, seen: &seen)
    default:
      if BrowserContextService.isBrowser(event.appBundleId) {
        return browserItems(event: event, seen: &seen)
      }
      if isTerminal(event.appBundleId) {
        return terminalItems(title: event.windowTitle, bundleId: event.appBundleId, seen: &seen)
      }
      return pathItems(title: event.windowTitle, bundleId: event.appBundleId, seen: &seen)
    }
  }

  // MARK: - Finder

  private static func finderItems(title: String?, seen: inout Set<String>) -> [RestoreItem] {
    guard let path = extractPath(from: title), FileManager.default.fileExists(atPath: path) else { return [] }
    let key = "folder:\(path)"
    guard seen.insert(key).inserted else { return [] }
    return [RestoreItem(
      id: UUID(),
      kind: .folder,
      label: (path as NSString).lastPathComponent,
      bundleId: "com.apple.finder",
      url: nil,
      path: path,
      workingDirectory: nil
    )]
  }

  // MARK: - Preview / documents

  private static func documentItems(title: String?, seen: inout Set<String>) -> [RestoreItem] {
    guard let path = extractFilePath(from: title),
          FileManager.default.fileExists(atPath: path)
    else { return [] }
    let key = "doc:\(path)"
    guard seen.insert(key).inserted else { return [] }
    return [RestoreItem(
      id: UUID(),
      kind: .document,
      label: (path as NSString).lastPathComponent,
      bundleId: "com.apple.Preview",
      url: nil,
      path: path,
      workingDirectory: nil
    )]
  }

  // MARK: - IDE workspaces

  private static func workspaceItems(
    title: String?,
    bundleId: String,
    seen: inout Set<String>
  ) -> [RestoreItem] {
    guard let path = extractWorkspacePath(from: title),
          FileManager.default.fileExists(atPath: path)
    else { return [] }
    let key = "ws:\(path)"
    guard seen.insert(key).inserted else { return [] }
    return [RestoreItem(
      id: UUID(),
      kind: .workspace,
      label: (path as NSString).lastPathComponent,
      bundleId: bundleId,
      url: nil,
      path: path,
      workingDirectory: nil
    )]
  }

  // MARK: - Browser

  private static func browserItems(event: ActivityEvent, seen: inout Set<String>) -> [RestoreItem] {
    let urlString = event.url ?? sanitizedURL(from: event.windowTitle)
    guard let urlString, let url = URL(string: urlString) else { return [] }
    let key = "browser:\(url.absoluteString)"
    guard seen.insert(key).inserted else { return [] }
    let label = event.windowTitle ?? url.host ?? "Page"
    return [RestoreItem(
      id: UUID(),
      kind: .browserPage,
      label: String(label.prefix(120)),
      bundleId: event.appBundleId,
      url: url.absoluteString,
      path: nil,
      workingDirectory: nil
    )]
  }

  // MARK: - Terminal

  private static func terminalItems(
    title: String?,
    bundleId: String,
    seen: inout Set<String>
  ) -> [RestoreItem] {
    guard let cwd = extractTerminalDirectory(from: title) else { return [] }
    let key = "term:\(cwd)"
    guard seen.insert(key).inserted else { return [] }
    return [RestoreItem(
      id: UUID(),
      kind: .terminalDirectory,
      label: "Terminal — \((cwd as NSString).lastPathComponent)",
      bundleId: bundleId,
      url: nil,
      path: nil,
      workingDirectory: cwd
    )]
  }

  private static func pathItems(
    title: String?,
    bundleId: String,
    seen: inout Set<String>
  ) -> [RestoreItem] {
    guard let path = extractPath(from: title), FileManager.default.fileExists(atPath: path) else { return [] }
    let key = "path:\(path)"
    guard seen.insert(key).inserted else { return [] }
    if path.hasSuffix(".xcworkspace") || path.hasSuffix(".xcodeproj") || path.hasSuffix(".code-workspace") {
      return [RestoreItem(
        id: UUID(),
        kind: .workspace,
        label: (path as NSString).lastPathComponent,
        bundleId: bundleId,
        url: nil,
        path: path,
        workingDirectory: nil
      )]
    }
    return []
  }

  // MARK: - Parsing helpers

  private static func extractPath(from title: String?) -> String? {
    guard let title else { return nil }
    if let range = title.range(of: "/Users/") ?? title.range(of: "/Volumes/") {
      let path = String(title[range.lowerBound...])
      let trimmed = path.components(separatedBy: " — ").first
        ?? path.components(separatedBy: " – ").first
        ?? path
      return trimmed.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    return nil
  }

  private static func extractFilePath(from title: String?) -> String? {
    guard let title else { return nil }
    if title.hasPrefix("/"), FileManager.default.fileExists(atPath: title) { return title }
    return extractPath(from: title)
  }

  private static func extractWorkspacePath(from title: String?) -> String? {
    guard let title else { return nil }
    let separators = [" — ", " – ", " - "]
    var candidates = [title]
    for sep in separators {
      candidates = candidates.flatMap { $0.components(separatedBy: sep) }
    }
    for candidate in candidates {
      let trimmed = candidate.trimmingCharacters(in: .whitespaces)
      if trimmed.hasSuffix(".xcworkspace") || trimmed.hasSuffix(".xcodeproj")
        || trimmed.hasSuffix(".code-workspace"),
        FileManager.default.fileExists(atPath: trimmed) {
        return trimmed
      }
      if let path = extractPath(from: trimmed),
         path.hasSuffix(".xcworkspace") || path.hasSuffix(".xcodeproj")
           || path.hasSuffix(".code-workspace") {
        return path
      }
    }
    return extractPath(from: title)
  }

  private static func extractTerminalDirectory(from title: String?) -> String? {
    guard let title else { return nil }
    let trimmed = title.trimmingCharacters(in: .whitespaces)
    if trimmed.hasPrefix("/"), FileManager.default.fileExists(atPath: trimmed) { return trimmed }
    return nil
  }

  private static func sanitizedURL(from title: String?) -> String? {
    guard let title, title.contains(".") else { return nil }
    if title.hasPrefix("http") { return title }
    return "https://\(title)"
  }

  private static func isTerminal(_ bundleId: String) -> Bool {
    [
      "com.apple.Terminal",
      "com.googlecode.iterm2",
      "dev.warp.Warp-Stable",
      "co.zeit.hyper"
    ].contains(bundleId)
  }
}
