import Foundation

enum SessionSummarizer {
    
    enum AppCategory {
        case coding
        case browser
        case terminal
        case design
        case communication
        case writing
        case other
        
        static func from(bundleId: String) -> AppCategory {
            let lower = bundleId.lowercased()
            
            // Coding Editors / IDEs
            if lower.contains("xcode") ||
               lower.contains("vscode") ||
               lower.contains("cursor") ||
               lower.contains("sublimetext") ||
               lower.contains("intellij") ||
               lower.contains("pycharm") ||
               lower.contains("webstorm") ||
               lower.contains("clion") ||
               lower.contains("appcode") ||
               lower.contains("textedit") ||
               lower.contains("antigravity") ||
               lower.contains("android-studio") {
                return .coding
            }
            
            // Browsers
            if lower.contains("safari") ||
               lower.contains("chrome") ||
               lower.contains("browser") || // company.thebrowser.Browser (Arc)
               lower.contains("brave") ||
               lower.contains("edgemac") ||
               lower.contains("firefox") ||
               lower.contains("opera") {
                return .browser
            }
            
            // Terminal
            if lower.contains("terminal") ||
               lower.contains("iterm") ||
               lower.contains("warp") ||
               lower.contains("kitty") ||
               lower.contains("hyper") {
                return .terminal
            }
            
            // Design
            if lower.contains("figma") ||
               lower.contains("sketch") ||
               lower.contains("photoshop") ||
               lower.contains("illustrator") ||
               lower.contains("xd") ||
               lower.contains("canva") {
                return .design
            }
            
            // Communication
            if lower.contains("slack") ||
               lower.contains("teams") ||
               lower.contains("discord") ||
               lower.contains("mail") ||
               lower.contains("outlook") ||
               lower.contains("messages") ||
               lower.contains("whatsapp") ||
               lower.contains("zoom") ||
               lower.contains("webex") {
                return .communication
            }
            
            // Writing
            if lower.contains("notes") ||
               lower.contains("notion") ||
               lower.contains("pages") ||
               lower.contains("word") ||
               lower.contains("obsidian") {
                return .writing
            }
            
            return .other
        }
    }
    
    static func generateSummary(for memory: WorkflowMemory) -> String {
        let selfBundleId = Bundle.main.bundleIdentifier ?? "com.deepaks.EchoTest2"
        let events = memory.events.filter { $0.appBundleId != selfBundleId }
        
        guard !events.isEmpty else {
            return "No activity events captured to summarize."
        }
        
        // 1. Calculate duration per app to rank them
        var appDurations: [String: TimeInterval] = [:]
        var appNames: [String: String] = [:]
        for event in events {
            appDurations[event.appBundleId, default: 0] += event.duration
            appNames[event.appBundleId] = event.appName
        }
        
        // 2. Rank categories by duration
        var categoryDurations: [AppCategory: TimeInterval] = [:]
        for (bundleId, duration) in appDurations {
            let cat = AppCategory.from(bundleId: bundleId)
            categoryDurations[cat, default: 0] += duration
        }
        
        let rankedCategories = categoryDurations.sorted { $0.value > $1.value }
        guard let primaryCategory = rankedCategories.first?.key else {
            return "No distinct workflow detected."
        }
        
        // 3. Find top apps in each category
        var appsByCategory: [AppCategory: [String]] = [:] // bundleIds
        for bundleId in appDurations.keys {
            let cat = AppCategory.from(bundleId: bundleId)
            appsByCategory[cat, default: []].append(bundleId)
        }
        for (cat, ids) in appsByCategory {
            appsByCategory[cat] = ids.sorted { appDurations[$0, default: 0] > appDurations[$1, default: 0] }
        }
        
        // 4. Extract specific details per category
        // Project name
        let projectName = extractProjectName(for: memory, events: events)
        
        // Coding files
        var codingFiles: [String] = []
        let codingEvents = events.filter { AppCategory.from(bundleId: $0.appBundleId) == .coding }
        for event in codingEvents {
            if let title = event.windowTitle, let file = extractFileName(from: title) {
                if !codingFiles.contains(file) {
                    codingFiles.append(file)
                }
            }
        }
        
        // Browser domains
        var browserDomains: [String] = []
        for ctx in memory.browserContexts {
            let domain = ctx.domain.replacingOccurrences(of: "www.", with: "")
            if !browserDomains.contains(domain) && !domain.isEmpty {
                browserDomains.append(domain)
            }
        }
        
        // Terminal commands / directory names
        var terminalDirs: [String] = []
        var terminalCommands: [String] = []
        let terminalEvents = events.filter { AppCategory.from(bundleId: $0.appBundleId) == .terminal }
        for event in terminalEvents {
            if let url = event.url, url.hasPrefix("file://"), let path = URL(string: url)?.path {
                let dirName = (path as NSString).lastPathComponent
                if !dirName.isEmpty && !terminalDirs.contains(dirName) {
                    terminalDirs.append(dirName)
                }
            }
            if let title = event.windowTitle, !title.isEmpty {
                let clean = cleanTerminalTitle(title)
                if !clean.isEmpty && !terminalCommands.contains(clean) {
                    terminalCommands.append(clean)
                }
            }
        }
        
        // Design documents
        var designDocs: [String] = []
        let designEvents = events.filter { AppCategory.from(bundleId: $0.appBundleId) == .design }
        for event in designEvents {
            if let title = event.windowTitle, !title.isEmpty, let doc = extractDocumentName(from: title, appName: event.appName) {
                if !designDocs.contains(doc) {
                    designDocs.append(doc)
                }
            }
        }
        
        // Writing documents
        var writingDocs: [String] = []
        let writingEvents = events.filter { AppCategory.from(bundleId: $0.appBundleId) == .writing }
        for event in writingEvents {
            if let title = event.windowTitle, !title.isEmpty, let doc = extractDocumentName(from: title, appName: event.appName) {
                if !writingDocs.contains(doc) {
                    writingDocs.append(doc)
                }
            }
        }
        
        // 5. Construct pure content narrative (no focus/pauses/durations)
        var sentences: [String] = []
        
        let primaryApps = appsByCategory[primaryCategory, default: []]
        let primaryAppName = primaryApps.first.map { AppMetadataResolver.displayName(bundleId: $0, rawName: appNames[$0]) } ?? "primary apps"
        
        // Sentence 1: Primary action with project and files
        switch primaryCategory {
        case .coding:
            var s = ""
            if let project = projectName {
                s += "You spent this session working on the **\(project)** project, coding in \(primaryAppName)"
            } else {
                s += "You spent this session coding in \(primaryAppName)"
            }
            
            if !codingFiles.isEmpty {
                let fileList = codingFiles.prefix(3).map { "**\($0)**" }.joined(separator: ", ")
                s += " and editing files like \(fileList)"
            }
            s += "."
            sentences.append(s)
            
        case .browser:
            var s = ""
            if let project = projectName {
                s += "You spent this session doing web research and browsing in \(primaryAppName) for the **\(project)** project"
            } else {
                s += "You spent this session doing web research and browsing in \(primaryAppName)"
            }
            
            if !browserDomains.isEmpty {
                let domainList = browserDomains.prefix(3).map { "**\($0)**" }.joined(separator: ", ")
                s += ", visiting sites like \(domainList)"
            }
            s += "."
            sentences.append(s)
            
        case .terminal:
            var s = ""
            if let project = projectName {
                s += "You spent this session working in the terminal using \(primaryAppName) on the **\(project)** project"
            } else {
                s += "You spent this session working in the terminal using \(primaryAppName)"
            }
            
            if !terminalDirs.isEmpty {
                s += " inside the **\(terminalDirs[0])** directory"
            }
            if !terminalCommands.isEmpty {
                let cmdList = terminalCommands.prefix(3).map { "`\($0)`" }.joined(separator: ", ")
                s += ", running commands like \(cmdList)"
            }
            s += "."
            sentences.append(s)
            
        case .design:
            var s = ""
            if let project = projectName {
                s += "You spent this session designing in \(primaryAppName) for the **\(project)** project"
            } else {
                s += "You spent this session designing in \(primaryAppName)"
            }
            
            if !designDocs.isEmpty {
                s += ", editing designs for **\(designDocs[0])**"
            }
            s += "."
            sentences.append(s)
            
        case .communication:
            sentences.append("You spent this session catching up on communications and checking messages in \(primaryAppName).")
            
        case .writing:
            var s = ""
            if let project = projectName {
                s += "You spent this session writing and documenting in \(primaryAppName) for the **\(project)** project"
            } else {
                s += "You spent this session writing and documenting in \(primaryAppName)"
            }
            
            if !writingDocs.isEmpty {
                s += ", editing files like **\(writingDocs[0])**"
            }
            s += "."
            sentences.append(s)
            
        case .other:
            sentences.append("You spent this session focused in \(primaryAppName).")
        }
        
        // Sentence 2: Secondary Tool / Environment
        if rankedCategories.count > 1 {
            let secondary = rankedCategories[1]
            if secondary.value >= 60 { // At least 1 minute of secondary activity
                let secCat = secondary.key
                let secApps = appsByCategory[secCat, default: []]
                let secAppName = secApps.first.map { AppMetadataResolver.displayName(bundleId: $0, rawName: appNames[$0]) } ?? "secondary apps"
                
                switch secCat {
                case .coding:
                    var s = "Additionally, you spent time writing code in \(secAppName)"
                    if !codingFiles.isEmpty {
                        s += " on files like **\(codingFiles[0])**"
                    }
                    s += "."
                    sentences.append(s)
                case .browser:
                    var s = "Additionally, you consulted browser resources in \(secAppName)"
                    if !browserDomains.isEmpty {
                        s += " on **\(browserDomains[0])**"
                    }
                    s += "."
                    sentences.append(s)
                case .terminal:
                    var s = "You also ran command line tasks in \(secAppName)"
                    if !terminalDirs.isEmpty {
                        s += " in the **\(terminalDirs[0])** folder"
                    }
                    s += "."
                    sentences.append(s)
                case .design:
                    var s = "Additionally, you did design work in \(secAppName)"
                    if !designDocs.isEmpty {
                        s += " on **\(designDocs[0])**"
                    }
                    s += "."
                    sentences.append(s)
                case .communication:
                    sentences.append("You also referenced or checked messages in \(secAppName).")
                case .writing:
                    sentences.append("You also spent some time writing documentation in \(secAppName).")
                case .other:
                    break
                }
            }
        }
        
        // Sentence 3: Web references (if browser was NOT primary or secondary, but was visited)
        if primaryCategory != .browser && (rankedCategories.count <= 1 || rankedCategories[1].key != .browser) {
            if !browserDomains.isEmpty {
                let domainList = browserDomains.prefix(3).map { "**\($0)**" }.joined(separator: ", ")
                sentences.append("To support your workflow, you visited reference and documentation sites including \(domainList).")
            }
        }
        
        return sentences.joined(separator: " ")
    }
    
    private static func extractProjectName(for memory: WorkflowMemory, events: [ActivityEvent]) -> String? {
        if let title = memory.session.title {
            if title.hasPrefix("Working in ") {
                return String(title.dropFirst("Working in ".count))
            }
            if title.hasPrefix("Building in ") {
                return String(title.dropFirst("Building in ".count))
            }
            if title.hasPrefix("Designing in ") {
                return String(title.dropFirst("Designing in ".count))
            }
            if title.hasPrefix("Focused in ") {
                return String(title.dropFirst("Focused in ".count))
            }
        }
        
        for event in events.reversed() {
            guard let title = event.windowTitle, !title.isEmpty else { continue }
            if let repo = extractRepoName(from: title) {
                return repo
            }
        }
        
        if let tag = memory.session.projectTag, !tag.isEmpty, tag != memory.cluster.label {
            return tag
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

        return nil
    }
    
    private static func extractFileName(from windowTitle: String) -> String? {
        let clean = windowTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return nil }
        
        // Exclude generic IDE states
        let genericIdeTitles = ["welcome", "workspace", "untitled", "new file", "new tab", "search", "terminal", "debugger", "git"]
        if genericIdeTitles.contains(where: { clean.lowercased().contains($0) }) {
            return nil
        }
        
        // Xcode/VS Code: "filename.swift — project" or "filename.swift - project"
        if clean.contains(" — ") || clean.contains(" - ") {
            let separator = clean.contains(" — ") ? " — " : " - "
            let parts = clean.components(separatedBy: separator)
            if let first = parts.first?.trimmingCharacters(in: .whitespaces) {
                let filename = (first as NSString).lastPathComponent
                if isCodeFile(filename) { return filename }
            }
        }
        
        // Fallback: check if the title contains a filename
        let components = clean.split(separator: " ").map(String.init)
        for comp in components {
            let filename = (comp as NSString).lastPathComponent
            if isCodeFile(filename) { return filename }
        }
        
        // Check last component of path
        if clean.contains("/") {
            let filename = (clean as NSString).lastPathComponent
            if isCodeFile(filename) { return filename }
        }
        
        return nil
    }
    
    private static func isCodeFile(_ filename: String) -> Bool {
        let ext = (filename as NSString).pathExtension.lowercased()
        let codeExtensions: Set<String> = [
            "swift", "py", "js", "ts", "kt", "java", "cpp", "h", "m", 
            "html", "css", "json", "yml", "yaml", "md", "sh", "rb", 
            "go", "rs", "plist", "storyboard", "xib", "c", "cs"
        ]
        return codeExtensions.contains(ext)
    }
    
    private static func cleanTerminalTitle(_ title: String) -> String {
        let clean = title
            .replacingOccurrences(of: " — -zsh — 120×30", with: "")
            .replacingOccurrences(of: " — login — 120×30", with: "")
            .replacingOccurrences(of: " -zsh", with: "")
            .replacingOccurrences(of: " -login", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return clean
    }
    
    private static func extractDocumentName(from windowTitle: String, appName: String) -> String? {
        let clean = windowTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return nil }
        
        // Remove trailing app name if present (e.g. "My Document - Pages")
        let appSuffix = " - \(appName)"
        if clean.hasSuffix(appSuffix) {
            let name = String(clean.dropLast(appSuffix.count))
            if !name.isEmpty { return name }
        }
        
        let appSuffixAlt = " — \(appName)"
        if clean.hasSuffix(appSuffixAlt) {
            let name = String(clean.dropLast(appSuffixAlt.count))
            if !name.isEmpty { return name }
        }
        
        return clean
    }
}
