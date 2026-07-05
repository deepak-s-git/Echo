import Foundation
import SQLite3

/// Extracts restorable working context from window titles, URLs, and bundle IDs.
nonisolated enum WorkflowContextCapture {

  static func items(from events: [ActivityEvent], tabEligibility: Double? = nil, sessionEndDate: Date? = nil) -> [RestoreItem] {
    let threshold = tabEligibility ?? {
        let delay = UserDefaults.standard.double(forKey: "echo.settings.browserCaptureDelaySeconds")
        let hold = UserDefaults.standard.double(forKey: "echo.settings.tabEligibilitySeconds")
        let actualDelay = delay > 0 ? delay : 5.0
        let actualHold = hold > 0 ? hold : 10.0
        return actualDelay + actualHold
    }()

    var items: [RestoreItem] = []
    var seen = Set<String>()

    let sorted = events.sorted { $0.timestamp < $1.timestamp }
    var eventDurations: [UUID: TimeInterval] = [:]
    
    // Filter events to only appFocus and appSwitch to track actual user focus changes
    let focusEvents = sorted.filter { $0.type == .appFocus || $0.type == .appSwitch }
    
    for i in 0..<focusEvents.count {
        let event = focusEvents[i]
        if i < focusEvents.count - 1 {
            let nextEvent = focusEvents[i + 1]
            eventDurations[event.id] = nextEvent.timestamp.timeIntervalSince(event.timestamp)
        } else {
            let lastEventTimestamp = sessionEndDate ?? sorted.last?.timestamp ?? event.timestamp
            let duration = lastEventTimestamp.timeIntervalSince(event.timestamp)
            eventDurations[event.id] = max(duration, 0.0)
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

    // Capture tab focus intervals for logging
    var urlIntervals: [String: [(start: Date, end: Date, duration: TimeInterval)]] = [:]
    for i in 0..<focusEvents.count {
        let event = focusEvents[i]
        guard BrowserContextService.isBrowser(event.appBundleId) else { continue }
        if let urlString = event.url ?? sanitizedURL(from: event.windowTitle) {
            let normalized = normalizeURL(urlString)
            let start = event.timestamp
            let end: Date
            let duration: TimeInterval
            if i < focusEvents.count - 1 {
                end = focusEvents[i + 1].timestamp
                duration = end.timeIntervalSince(start)
            } else {
                end = sessionEndDate ?? sorted.last?.timestamp ?? start
                duration = max(end.timeIntervalSince(start), 0.0)
            }
            urlIntervals[normalized, default: []].append((start: start, end: end, duration: duration))
        }
    }

    // Collect all browser URLs present in this session (focused and background scraped)
    var allBrowserURLs = Set<String>()
    for event in sorted {
        guard BrowserContextService.isBrowser(event.appBundleId) else { continue }
        if let urlString = event.url ?? sanitizedURL(from: event.windowTitle) {
            allBrowserURLs.insert(normalizeURL(urlString))
        }
    }

    // Emit detailed audit logs for all browser URLs
    SessionDetailLogger.log("[TabAudit] Detailed audit for browser URLs in session:")
    for url in allBrowserURLs.sorted() {
        let intervals = urlIntervals[url] ?? []
        let accumulated = urlDurations[url] ?? 0.0
        let qualified = accumulated >= threshold
        
        SessionDetailLogger.log("[TabAudit] URL: \(url)")
        if intervals.isEmpty {
            SessionDetailLogger.log("  - No active focus intervals (always background tab).")
        } else {
            for interval in intervals {
                SessionDetailLogger.log("  - Interval: Focused \(interval.start) -> \(interval.end) (Duration: \(interval.duration)s)")
            }
        }
        SessionDetailLogger.log("  - Accumulated Focus Duration: \(accumulated)s")
        SessionDetailLogger.log("  - Threshold Value: \(threshold)s")
        SessionDetailLogger.log("  - Qualified for Persistence: \(qualified ? "YES" : "NO")")
        
        let reason: String
        if qualified {
            reason = "Accumulated duration \(accumulated)s meets or exceeds threshold \(threshold)s."
        } else if intervals.isEmpty {
            reason = "Background tab captured via scraper; never actively focused/activated by the user."
        } else {
            reason = "Accumulated duration \(accumulated)s is below threshold \(threshold)s."
        }
        SessionDetailLogger.log("  - Reason for Decision: \(reason)")
    }

    for event in sorted.reversed() {
      let duration = eventDurations[event.id] ?? 0
      items.append(contentsOf: itemsForEvent(event, duration: duration, urlDurations: urlDurations, tabEligibility: threshold, seen: &seen))
    }
    return filterPrefixURLs(items)
  }

  private static func normalizeURL(_ urlString: String) -> String {
    guard let url = URL(string: urlString) else {
        return urlString.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
    var host = url.host ?? ""
    if host.hasPrefix("www.") {
        host = String(host.dropFirst(4))
    }
    let lowerHost = host.lowercased()
    var path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    
    if lowerHost != "youtu.be" {
        path = path.lowercased()
    }
    
    var normalized = "\(lowerHost)/\(path)".trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    
    if let components = URLComponents(string: urlString), let queryItems = components.queryItems {
        if lowerHost.contains("youtube.com") || lowerHost.contains("youtu.be") {
            if let vParam = queryItems.first(where: { $0.name == "v" })?.value {
                normalized += "?v=\(vParam)"
            }
        } else if lowerHost.contains("google.") {
            if let qParam = queryItems.first(where: { $0.name == "q" })?.value {
                normalized += "?q=\(qParam)"
            }
        }
    }
    return normalized
  }

  static func itemsForEvent(_ event: ActivityEvent, duration: TimeInterval, urlDurations: [String: TimeInterval] = [:], tabEligibility: Double? = nil, seen: inout Set<String>) -> [RestoreItem] {
    // Never include Echo itself in restore plans
    let selfBundleId = Bundle.main.bundleIdentifier ?? "com.deepaks.EchoTest2"
    guard event.appBundleId != selfBundleId else { return [] }

    let threshold = tabEligibility ?? {
        let delay = UserDefaults.standard.double(forKey: "echo.settings.browserCaptureDelaySeconds")
        let hold = UserDefaults.standard.double(forKey: "echo.settings.tabEligibilitySeconds")
        let actualDelay = delay > 0 ? delay : 5.0
        let actualHold = hold > 0 ? hold : 10.0
        return actualDelay + actualHold
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
    case "com.google.antigravity-ide", "com.google.antigravity":
      return workspaceItems(event: event, seen: &seen)
    // Apple iWork suite
    case "com.apple.iWork.Pages",
         "com.apple.iWork.Numbers",
         "com.apple.iWork.Keynote",
         "com.apple.TextEdit":
      return documentItems(event: event, seen: &seen)
    // Microsoft Office suite
    case "com.microsoft.Word",
         "com.microsoft.Excel",
         "com.microsoft.Powerpoint",
         "com.microsoft.onenote.mac",
         "com.microsoft.Outlook":
      return documentItems(event: event, seen: &seen)
    // LibreOffice / OpenOffice
    case "org.libreoffice.script",
         "org.openoffice.script":
      return documentItems(event: event, seen: &seen)
    // Adobe creative apps that work on local files
    case "com.adobe.Photoshop",
         "com.adobe.Illustrator",
         "com.adobe.InDesign",
         "com.adobe.Acrobat.Pro",
         "com.adobe.Reader":
      return documentItems(event: event, seen: &seen)
    default:
      if BrowserContextService.isBrowser(event.appBundleId) {
        return browserItems(event: event, duration: duration, urlDurations: urlDurations, tabEligibility: threshold, seen: &seen)
      }
      if isTerminal(event.appBundleId) {
        return terminalItems(event: event, seen: &seen)
      }
      
      // General document fallback: if AX gave us a valid file:// URL, treat as document
      if let path = getFilePath(from: event) ?? extractFilePath(from: event.windowTitle),
         FileManager.default.fileExists(atPath: path) {
          if path.hasSuffix(".xcworkspace") || path.hasSuffix(".xcodeproj") || path.hasSuffix(".code-workspace") {
              return workspaceItems(event: event, seen: &seen)
          }
          return documentItems(event: event, seen: &seen)
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
    let key = "folder:\(path):\(event.appBundleId)"
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
    let key = "doc:\(path):\(event.appBundleId)"
    guard seen.insert(key).inserted else { return [] }
    return [RestoreItem(
      id: UUID(),
      kind: .document,
      label: (path as NSString).lastPathComponent,
      bundleId: event.appBundleId,
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
    var pathOpt = getFilePath(from: event) ?? extractWorkspacePath(from: event.windowTitle)
    
    if pathOpt == nil && (event.appBundleId == "com.google.antigravity-ide" || event.appBundleId == "com.google.antigravity") {
        pathOpt = resolveWorkspacePath(from: event.windowTitle, bundleId: event.appBundleId)
    }
    
    guard let path = pathOpt,
          FileManager.default.fileExists(atPath: path)
    else { return [] }
    
    let resolvedPath: String
    if event.appBundleId == "com.microsoft.VSCode" || event.appBundleId == "com.todesktop.230313mzl4w4u92" || event.appBundleId == "com.google.antigravity-ide" || event.appBundleId == "com.google.antigravity" {
      resolvedPath = resolveProjectRoot(filePath: path, windowTitle: event.windowTitle, bundleId: event.appBundleId)
    } else {
      resolvedPath = path
    }
    
    let key = "ws:\(resolvedPath):\(event.appBundleId)"
    guard seen.insert(key).inserted else { return [] }
    return [RestoreItem(
      id: UUID(),
      kind: .workspace,
      label: (resolvedPath as NSString).lastPathComponent,
      bundleId: event.appBundleId,
      url: nil,
      path: resolvedPath,
      workingDirectory: nil
    )]
  }

  static func resolveWorkspacePath(from windowTitle: String?, bundleId: String) -> String? {
    guard let title = windowTitle, !title.isEmpty else { return nil }
    
    var recentFolders: [String] = []
    
    // Antigravity and Antigravity IDE share the same application support storage directory
    let supportDirName = "Antigravity IDE"
    let homeDir = NSHomeDirectory()
    
    // 1. Read from state.vscdb (SQLite)
    let vscdbPath = "\(homeDir)/Library/Application Support/\(supportDirName)/User/globalStorage/state.vscdb"
    let tempBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    if (try? FileManager.default.createDirectory(at: tempBase, withIntermediateDirectories: true)) != nil {
        let tempURL = tempBase.appendingPathComponent("state.vscdb")
        if FileManager.default.fileExists(atPath: vscdbPath) {
            if (try? FileManager.default.copyItem(at: URL(fileURLWithPath: vscdbPath), to: tempURL)) != nil {
                var db: OpaquePointer?
                if sqlite3_open_v2(tempURL.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK {
                    var statement: OpaquePointer?
                    let query = "SELECT value FROM ItemTable WHERE key = 'history.recentlyOpenedPathsList' LIMIT 1"
                    if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
                        if sqlite3_step(statement) == SQLITE_ROW {
                            var jsonString: String? = nil
                            if let blobPtr = sqlite3_column_blob(statement, 0) {
                                let blobBytes = sqlite3_column_bytes(statement, 0)
                                let data = Data(bytes: blobPtr, count: Int(blobBytes))
                                jsonString = String(data: data, encoding: .utf8)
                            }
                            
                            if let jsonString = jsonString,
                               let jsonData = jsonString.data(using: .utf8) {
                                struct RecentlyOpenedList: Codable {
                                    struct Entry: Codable {
                                        let folderUri: String?
                                        struct WorkspaceInfo: Codable {
                                            let configPath: String?
                                        }
                                        let workspace: WorkspaceInfo?
                                    }
                                    let entries: [Entry]?
                                }
                                
                                if let decoded = try? JSONDecoder().decode(RecentlyOpenedList.self, from: jsonData),
                                   let entries = decoded.entries {
                                    for entry in entries {
                                        if let folderUri = entry.folderUri,
                                           let url = URL(string: folderUri),
                                           url.scheme == "file" {
                                            recentFolders.append(url.path)
                                        } else if let configPath = entry.workspace?.configPath,
                                                  let url = URL(string: configPath),
                                                  url.scheme == "file" {
                                            recentFolders.append(url.path)
                                        }
                                    }
                                }
                            }
                        }
                        sqlite3_finalize(statement)
                    }
                    sqlite3_close(db)
                }
            }
        }
        try? FileManager.default.removeItem(at: tempBase)
    }
    
    // 2. Read from storage.json as fallback
    let storagePath = "\(homeDir)/Library/Application Support/\(supportDirName)/User/globalStorage/storage.json"
    
    if FileManager.default.fileExists(atPath: storagePath),
       let data = try? Data(contentsOf: URL(fileURLWithPath: storagePath)),
       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
       let backupWorkspaces = json["backupWorkspaces"] as? [String: Any],
       let folders = backupWorkspaces["folders"] as? [[String: Any]] {
        for folder in folders {
            if let uriStr = folder["folderUri"] as? String,
               let url = URL(string: uriStr),
               url.scheme == "file" {
                let path = url.path
                if !recentFolders.contains(path) {
                    recentFolders.append(path)
                }
            }
        }
    }
    
    if FileManager.default.fileExists(atPath: storagePath),
       let data = try? Data(contentsOf: URL(fileURLWithPath: storagePath)),
       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
       let profileAssociations = json["profileAssociations"] as? [String: Any],
       let workspaces = profileAssociations["workspaces"] as? [String: Any] {
        for key in workspaces.keys {
            if let url = URL(string: key), url.scheme == "file" {
                let path = url.path
                if !recentFolders.contains(path) {
                    recentFolders.append(path)
                }
            }
        }
    }
    
    let commonDirs = [
        "\(homeDir)/Desktop",
        "\(homeDir)/Documents"
    ]
    for dir in commonDirs {
        if let subdirs = try? FileManager.default.contentsOfDirectory(atPath: dir) {
            for subdir in subdirs {
                let fullPath = (dir as NSString).appendingPathComponent(subdir)
                var isDir: ObjCBool = false
                if FileManager.default.fileExists(atPath: fullPath, isDirectory: &isDir), isDir.boolValue {
                    if !recentFolders.contains(fullPath) {
                        recentFolders.append(fullPath)
                    }
                }
            }
        }
    }
    
    let sortedFolders = recentFolders.sorted {
        let len0 = ($0 as NSString).lastPathComponent.count
        let len1 = ($1 as NSString).lastPathComponent.count
        if len0 != len1 {
            return len0 > len1
        }
        let idx0 = recentFolders.firstIndex(of: $0) ?? 0
        let idx1 = recentFolders.firstIndex(of: $1) ?? 0
        return idx0 < idx1
    }
    
    for folderPath in sortedFolders {
        let folderName = (folderPath as NSString).lastPathComponent
        guard !folderName.isEmpty else { continue }
        
        if title.localizedCaseInsensitiveContains(folderName) {
            return folderPath
        }
    }
    
    return nil
  }

  static func resolveProjectRoot(filePath: String, windowTitle: String?, bundleId: String) -> String {
    guard let title = windowTitle else { return filePath }
    let separators = [" — ", " – ", " - "]
    
    var projectName: String? = nil
    
    if title.contains(".xcodeproj") || title.contains(".xcworkspace") {
      let parts = title.components(separatedBy: " — ")
      if let last = parts.last {
        projectName = last
          .replacingOccurrences(of: ".xcodeproj", with: "")
          .replacingOccurrences(of: ".xcworkspace", with: "")
          .trimmingCharacters(in: .whitespaces)
      }
    }
    
    let fileURL = URL(fileURLWithPath: filePath)
    var isDir: ObjCBool = false
    let fileExists = FileManager.default.fileExists(atPath: filePath, isDirectory: &isDir)
    
    var startURL = fileURL
    if fileExists {
      if !isDir.boolValue {
        startURL = fileURL.deletingLastPathComponent()
      }
    } else {
      if !fileURL.pathExtension.isEmpty {
        startURL = fileURL.deletingLastPathComponent()
      }
    }
    
    var candidates: [String] = [title.trimmingCharacters(in: .whitespaces)]
    for sep in separators {
      if title.contains(sep) {
        let parts = title.components(separatedBy: sep)
        for part in parts {
          let trimmed = part.trimmingCharacters(in: .whitespaces)
          if !trimmed.isEmpty {
            candidates.append(trimmed)
          }
        }
      }
    }
    
    if projectName == nil {
      for candidate in candidates {
        if candidate == "VS Code" || candidate == "Visual Studio Code" || candidate == "Cursor" {
          continue
        }
        
        var current = startURL
        while current.path != "/" {
          if current.lastPathComponent == candidate {
            return current.path
          }
          current = current.deletingLastPathComponent()
        }
      }
    }
    
    if let projName = projectName, !projName.isEmpty {
      var current = startURL
      while current.path != "/" {
        if current.lastPathComponent == projName {
          return current.path
        }
        current = current.deletingLastPathComponent()
      }
    }
    
    let parent = fileURL.deletingLastPathComponent().path
    if parent != "/" && parent != "/Users" {
      return parent
    }
    
    return filePath
  }

  // MARK: - Browser

  private static func browserItems(event: ActivityEvent, duration: TimeInterval, urlDurations: [String: TimeInterval], tabEligibility: Double, seen: inout Set<String>) -> [RestoreItem] {
    if let trackTabs = UserDefaults.standard.object(forKey: "echo.settings.trackBrowserTabs") as? Bool, !trackTabs {
        return []
    }
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
        let key = "doc:\(pdfLabel):"
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
        let key = "doc:\(path):"
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
    
    let normalizedURLString = normalizeURL(url.absoluteString)
    let key = "browser:\(normalizedURLString):\(event.appBundleId)"
    let profile = event.profileName ?? "default"
    let host = url.host?.lowercased() ?? ""
    let titleKey = "title:\(profile):\(host):\(lowerT):\(event.appBundleId)"
    
    guard seen.insert(key).inserted else { return [] }
    guard seen.insert(titleKey).inserted else { return [] }
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
    let terminalAppKey = "terminal_app:\(event.appBundleId)"
    if seen.contains(terminalAppKey) {
        return []
    }

    let cwdOpt: String?
    if let urlStr = event.url, urlStr.hasPrefix("file://"), let url = URL(string: urlStr) {
        cwdOpt = url.path
    } else {
        cwdOpt = extractTerminalDirectory(from: event.windowTitle)
    }
    
    guard let cwd = cwdOpt, FileManager.default.fileExists(atPath: cwd) else { return [] }
    seen.insert(terminalAppKey)
    
    let key = "term:\(cwd):\(event.appBundleId)"
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
    let key = "path:\(path):\(event.appBundleId)"
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

  static func extractWorkspacePath(from title: String?) -> String? {
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
    
    // 1. Try our custom path extraction that searches for /Users/ or /Volumes/
    if let extracted = extractPath(from: title) {
        let clean = extracted.trimmingCharacters(in: .whitespacesAndNewlines)
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: clean, isDirectory: &isDir), isDir.boolValue {
            return clean
        }
    }
    
    // 2. Fallback: split the title by separators and see if any component is a valid directory path starting with /
    let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
    let separators = [" — ", " – ", " - "]
    var components = [trimmed]
    for sep in separators {
        components = components.flatMap { $0.components(separatedBy: sep) }
    }
    
    for component in components {
        let path = component.trimmingCharacters(in: .whitespacesAndNewlines)
        guard path.hasPrefix("/") else { continue }
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue {
            return path
        }
    }
    
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


  private static func filterPrefixURLs(_ items: [RestoreItem]) -> [RestoreItem] {
    let browserItems = items.filter { $0.kind == .browserPage || $0.kind == .url }
    let otherItems = items.filter { $0.kind != .browserPage && $0.kind != .url }
    
    var filteredBrowser: [RestoreItem] = []
    let sortedBrowser = browserItems.sorted { item1, item2 in
        let u1 = item1.url ?? ""
        let u2 = item2.url ?? ""
        return normalizeURL(u1).count > normalizeURL(u2).count
    }
    
    var seenDeeper = Set<String>()
    for item in sortedBrowser {
        guard let u = item.url else {
            filteredBrowser.append(item)
            continue
        }
        let normalized = normalizeURL(u)
        let profile = item.profileName ?? "default"
        let profileKey = "\(profile):\(normalized)"
        
        let isPrefix = seenDeeper.contains { deeper in
            deeper == profileKey || deeper.hasPrefix(profileKey + "/")
        }
        
        if isPrefix {
            continue
        }
        
        seenDeeper.insert(profileKey)
        filteredBrowser.append(item)
    }
    
    let allowedIds = Set(filteredBrowser.map(\.id) + otherItems.map(\.id))
    return items.filter { allowedIds.contains($0.id) }
  }
}
