import Foundation

enum SessionSummaryCompiler {
    nonisolated static func compile(events: [ActivityEvent]) -> String {
        guard !events.isEmpty else { return "No activity recorded" }
        
        var appTimes: [String: TimeInterval] = [:]
        var files = Set<String>()
        var domains = Set<String>()
        var shellCommands = [String]()
        
        for event in events {
            appTimes[event.appName, default: 0] += event.duration
            
            // Files
            if event.type == .fileAccess || (event.url?.hasPrefix("file://") == true) {
                if let urlStr = event.url, let url = URL(string: urlStr) {
                    files.insert(url.lastPathComponent)
                } else if let title = event.windowTitle, title.contains(" — ") {
                    let parts = title.components(separatedBy: " — ")
                    if let first = parts.first, first.contains(".") {
                        files.insert(first)
                    }
                }
            }
            
            // Web domains
            if event.type == .browserTab, let url = event.url, let host = URL(string: url)?.host {
                let cleanHost = host.replacingOccurrences(of: "www.", with: "")
                domains.insert(cleanHost)
            }
            
            // Terminal commands
            if event.type == .terminalCommand, let title = event.windowTitle {
                let cleanCommand = title
                    .replacingOccurrences(of: " — zsh", with: "")
                    .replacingOccurrences(of: " - zsh", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !cleanCommand.isEmpty && !shellCommands.contains(cleanCommand) {
                    shellCommands.append(cleanCommand)
                }
            }
        }
        
        var summaryParts: [String] = []
        
        // 1. Most used apps
        let sortedApps = appTimes.sorted { $0.value > $1.value }.prefix(3)
        if !sortedApps.isEmpty {
            let appList = sortedApps.map { $0.key }.joined(separator: ", ")
            summaryParts.append("Apps used: \(appList).")
        }
        
        // 2. Files
        if !files.isEmpty {
            let fileList = files.prefix(5).joined(separator: ", ")
            summaryParts.append("Files opened: \(fileList).")
        }
        
        // 3. Webpages
        if !domains.isEmpty {
            let webList = domains.prefix(5).joined(separator: ", ")
            summaryParts.append("Websites visited: \(webList).")
        }
        
        // 4. Shell
        if !shellCommands.isEmpty {
            let commandList = shellCommands.prefix(3).joined(separator: "; ")
            summaryParts.append("Commands run: \(commandList).")
        }
        
        return summaryParts.joined(separator: " ")
    }
}
