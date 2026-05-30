import Foundation

/// Extracts restorable working context from window titles, URLs, and bundle IDs.
nonisolated enum WorkflowContextCapture {

  static func items(from events: [ActivityEvent], tabEligibility: Double? = nil) -> [RestoreItem] {
    let threshold = tabEligibility ?? {
        let val = UserDefaults.standard.double(forKey: "echo.settings.tabEligibilitySeconds")
        return val > 0 ? val : 12.0
    }()

    var items: [RestoreItem] = []
    var seen = Set<String>()

    let sorted = events.sorted { $0.timestamp < $1.timestamp }
    var eventDurations: [UUID: TimeInterval] = [:]
    
    for i in 0..<sorted.count {
        let event = sorted[i]
        if i < sorted.count - 1 {
            let nextEvent = sorted[i + 1]
            eventDurations[event.id] = nextEvent.timestamp.timeIntervalSince(event.timestamp)
        } else {
            eventDurations[event.id] = 60.0
        }
    }

    var urlDurations: [String: TimeInterval] = [:]
    for event in sorted {
        let d = eventDurations[event.id] ?? 0.0
        let urlString = event.url ?? sanitizedURL(from: event.windowTitle)
        if let urlString {
            let normalized = normalizeURL(urlString)
            urlDurations[normalized, default: 0] += d
        }
    }

    for event in sorted.reversed() {
      let duration = eventDurations[event.id] ?? 0
      items.append(contentsOf: itemsForEvent(event, duration: duration, urlDurations: urlDurations, tabEligibility: threshold, seen: &seen))
    }
    return items
  }

  private static func normalizeURL(_ urlString: String) -> String {
    guard let url = URL(string: urlString) else {
        return urlString.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
    var host = url.host ?? ""
    if host.hasPrefix("www.") {
        host = String(host.dropFirst(4))
    }
    let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    return "\(host)/\(path)".lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "/"))
  }

  static func itemsForEvent(_ event: ActivityEvent, duration: TimeInterval, urlDurations: [String: TimeInterval] = [:], tabEligibility: Double? = nil, seen: inout Set<String>) -> [RestoreItem] {
    let threshold = tabEligibility ?? {
        let val = UserDefaults.standard.double(forKey: "echo.settings.tabEligibilitySeconds")
        return val > 0 ? val : 12.0
    }()

    switch event.appBundleId {
    case "com.apple.finder":
      return finderItems(event: event, seen: &seen)
    case "com.apple.Preview":
      return documentItems(event: event, seen: &seen)
    case "com.apple.dt.Xcode":
      return workspaceItems(event: event, seen: &seen)
    case "com.microsoft.VSCode", "com.todesktop.230313mzl4w4u92":
      return workspaceItems(event: event, seen: &seen)
    default:
      if BrowserContextService.isBrowser(event.appBundleId) {
        return browserItems(event: event, duration: duration, urlDurations: urlDurations, tabEligibility: threshold, seen: &seen)
      }
      if isTerminal(event.appBundleId) {
        return terminalItems(event: event, seen: &seen)
      }
      return pathItems(event: event, seen: &seen)
    }
  }

  private static func getFilePath(from event: ActivityEvent) -> String? {
    if let urlStr = event.url, urlStr.hasPrefix("file://"), let url = URL(string: urlStr) {
      return url.path
    }
    return nil
  }

  // MARK: - Finder

  private static func finderItems(event: ActivityEvent, seen: inout Set<String>) -> [RestoreItem] {
    guard let path = getFilePath(from: event) ?? extractPath(from: event.windowTitle),
          FileManager.default.fileExists(atPath: path) else { return [] }
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

  private static func documentItems(event: ActivityEvent, seen: inout Set<String>) -> [RestoreItem] {
    guard let path = getFilePath(from: event) ?? extractFilePath(from: event.windowTitle),
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
    event: ActivityEvent,
    seen: inout Set<String>
  ) -> [RestoreItem] {
    let pathOpt = getFilePath(from: event) ?? extractWorkspacePath(from: event.windowTitle)
    guard let path = pathOpt,
          FileManager.default.fileExists(atPath: path)
    else { return [] }
    let key = "ws:\(path)"
    guard seen.insert(key).inserted else { return [] }
    return [RestoreItem(
      id: UUID(),
      kind: .workspace,
      label: (path as NSString).lastPathComponent,
      bundleId: event.appBundleId,
      url: nil,
      path: path,
      workingDirectory: nil
    )]
  }

  // MARK: - Browser

  private static func browserItems(event: ActivityEvent, duration: TimeInterval, urlDurations: [String: TimeInterval], tabEligibility: Double, seen: inout Set<String>) -> [RestoreItem] {
    let checkURLString = event.url ?? sanitizedURL(from: event.windowTitle)
    var totalDuration = duration
    if let checkURLString {
        let normalized = normalizeURL(checkURLString)
        if let agg = urlDurations[normalized] {
            totalDuration = agg
        }
    }

    if totalDuration < tabEligibility {
        return []
    }

    // 1. Detect local PDF opened in browser via title or url
    let isPDF: Bool
    let pdfLabel: String
    if let title = event.windowTitle, title.lowercased().contains(".pdf") {
        isPDF = true
        if let range = title.lowercased().range(of: ".pdf") {
            pdfLabel = String(title[..<range.upperBound])
        } else {
            pdfLabel = title
        }
    } else if let urlStr = event.url, urlStr.lowercased().contains(".pdf") {
        isPDF = true
        if let url = URL(string: urlStr) {
            pdfLabel = url.lastPathComponent
        } else {
            pdfLabel = "Document.pdf"
        }
    } else {
        isPDF = false
        pdfLabel = ""
    }

    if isPDF {
        let path = event.url?.hasPrefix("file://") == true ? URL(string: event.url!)?.path : nil
        let key = "doc:\(pdfLabel)"
        guard seen.insert(key).inserted else { return [] }
        return [RestoreItem(
          id: UUID(),
          kind: .document,
          label: pdfLabel,
          bundleId: nil, // Group under Files & Documents!
          url: event.url,
          path: path,
          workingDirectory: nil
        )]
    }

    let urlString = event.url ?? sanitizedURL(from: event.windowTitle)
    guard let urlString, let url = URL(string: urlString) else { return [] }
    
    // Check if the URL is a local file (e.g. PDF opened in browser)
    let lowerU = urlString.lowercased()
    if urlString.hasPrefix("file://") || lowerU.contains("/users/") || lowerU.contains("/volumes/") {
        let path: String
        if urlString.hasPrefix("file://") {
            path = url.path
        } else {
            path = urlString
        }
        let key = "doc:\(path)"
        guard seen.insert(key).inserted else { return [] }
        return [RestoreItem(
          id: UUID(),
          kind: .document,
          label: (path as NSString).lastPathComponent,
          bundleId: nil, // set to nil so it groups under Files & Documents!
          url: nil,
          path: path,
          workingDirectory: nil
        )]
    }
    
    let label = event.windowTitle ?? url.host ?? "Page"
    
    let t = label.trimmingCharacters(in: .whitespacesAndNewlines)
    let u = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
    let lowerT = t.lowercased()
    
    if t.isEmpty || u.isEmpty { return [] }
    if lowerT == "new tab" || lowerT == "start page" || lowerT == "favorites" || lowerT == "untitled" { return [] }
    if lowerU == "about:blank" || lowerU.hasPrefix("chrome://") || lowerU.hasPrefix("edge://") || lowerU.hasPrefix("brave://") || lowerU.hasPrefix("favorites://") || lowerU.hasPrefix("topsites://") {
        return []
    }
    
    let key = "browser:\(url.absoluteString)"
    guard seen.insert(key).inserted else { return [] }
    return [RestoreItem(
      id: UUID(),
      kind: .browserPage,
      label: String(t.prefix(120)),
      bundleId: event.appBundleId,
      url: url.absoluteString,
      path: nil,
      workingDirectory: nil,
      profileName: event.profileName
    )]
  }

  // MARK: - Terminal

  private static func terminalItems(
    event: ActivityEvent,
    seen: inout Set<String>
  ) -> [RestoreItem] {
    guard let cwd = extractTerminalDirectory(from: event.windowTitle) else { return [] }
    let key = "term:\(cwd)"
    guard seen.insert(key).inserted else { return [] }
    return [RestoreItem(
      id: UUID(),
      kind: .terminalDirectory,
      label: "Terminal — \((cwd as NSString).lastPathComponent)",
      bundleId: event.appBundleId,
      url: nil,
      path: nil,
      workingDirectory: cwd
    )]
  }

  private static func pathItems(
    event: ActivityEvent,
    seen: inout Set<String>
  ) -> [RestoreItem] {
    guard let path = getFilePath(from: event) ?? extractPath(from: event.windowTitle),
          FileManager.default.fileExists(atPath: path) else { return [] }
    let key = "path:\(path)"
    guard seen.insert(key).inserted else { return [] }
    if path.hasSuffix(".xcworkspace") || path.hasSuffix(".xcodeproj") || path.hasSuffix(".code-workspace") {
      return [RestoreItem(
        id: UUID(),
        kind: .workspace,
        label: (path as NSString).lastPathComponent,
        bundleId: event.appBundleId,
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
