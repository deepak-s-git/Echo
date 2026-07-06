import AppKit
import Foundation

/// Modular workflow restoration — extensible for future layout/workspace restore.
@MainActor
final class WorkflowRestoreEngine {

    private let restorers: [any WorkflowRestoring]

    init(restorers: [any WorkflowRestoring]? = nil) {
        self.restorers = restorers ?? [
            BrowserPageRestorer(),
            DocumentRestorer(),
            WorkspaceRestorer(),
            URLRestorer(),
            ApplicationRestorer(),
            FolderRestorer(),
            TerminalDirectoryRestorer()
        ]
    }

    func restore(
        plan: WorkflowRestorePlan,
        progress: (@MainActor (Int, Int) -> Void)? = nil
    ) async -> RestoreResult {
        var succeeded: [RestoreItem] = []
        var skipped: [RestoreItem] = []
        var failed: [(RestoreItem, String)] = []
        let items = plan.items
        let total = items.count

        for (index, item) in items.enumerated() {
            progress?(index, total)
            guard let restorer = restorers.first(where: { $0.canRestore(item) }) else {
                failed.append((item, "No restorer available"))
                continue
            }
            if await restorer.skipReasonIfAlreadyOpen(item) != nil {
                skipped.append(item)
                continue
            }
            do {
                try await restorer.restore(item)
                succeeded.append(item)
                EchoLog.restore("Restored \(item.label)")
            } catch {
                failed.append((item, error.localizedDescription))
                EchoLog.restore("Failed \(item.label)", error: error)
            }
            if index + 1 < items.count {
                try? await Task.sleep(for: .milliseconds(800))
            }
        }
        progress?(total, total)

        return RestoreResult(succeeded: succeeded, skipped: skipped, failed: failed)
    }
}

// MARK: - Protocol

protocol WorkflowRestoring {
    func canRestore(_ item: RestoreItem) -> Bool
    func skipReasonIfAlreadyOpen(_ item: RestoreItem) async -> String?
    func restore(_ item: RestoreItem) async throws
}

extension WorkflowRestoring {
    func skipReasonIfAlreadyOpen(_ item: RestoreItem) async -> String? { nil }
}

// MARK: - Browser page

struct BrowserPageRestorer: WorkflowRestoring {
    func canRestore(_ item: RestoreItem) -> Bool {
        (item.kind == .browserPage || item.kind == .url) && item.url != nil
    }

    func skipReasonIfAlreadyOpen(_ item: RestoreItem) async -> String? {
        guard let url = item.url, let bundleId = item.bundleId,
              BrowserContextService.isBrowser(bundleId)
        else { return nil }
        if let tab = BrowserTabScraper.activeTab(forBundleId: bundleId),
           urlsMatch(tab.url, url) {
            return "tab already open"
        }
        return nil
    }

    func restore(_ item: RestoreItem) async throws {
        guard let urlString = item.url, let url = URL(string: urlString) else {
            throw RestoreError.invalidURL
        }
        EchoLog.restore("[restore] item=\(item.label) profileName=\(item.profileName ?? "nil") bundleId=\(item.bundleId ?? "nil")")

        if let bundleId = item.bundleId,
           let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {

            if bundleId == "company.thebrowser.Browser" {
                let targetSpace = item.profileName ?? ""
                let escapedURL = urlString.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
                let escapedSpace = targetSpace.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
                
                let scriptSource: String
                if !targetSpace.isEmpty {
                    scriptSource = """
                    tell application "Arc"
                        activate
                        if (count of windows) is 0 then
                            make new window
                        end if
                        tell front window
                            try
                                tell space "\(escapedSpace)" to make new tab with properties {URL:"\(escapedURL)"}
                            on error
                                make new tab with properties {URL:"\(escapedURL)"}
                            end try
                        end tell
                    end tell
                    """
                } else {
                    scriptSource = """
                    tell application "Arc"
                        activate
                        if (count of windows) is 0 then
                            make new window
                        end if
                        tell front window
                            make new tab with properties {URL:"\(escapedURL)"}
                        end tell
                    end tell
                    """
                }
                
                if let appleScript = NSAppleScript(source: scriptSource) {
                    var errorInfo: NSDictionary?
                    appleScript.executeAndReturnError(&errorInfo)
                    if let error = errorInfo {
                        EchoLog.restore("[restore] Arc AppleScript failed: \(error)")
                    } else {
                        EchoLog.restore("[restore] Arc AppleScript succeeded for \(urlString)")
                        return
                    }
                }
            }

            let isChromiumProfileRestore = (bundleId == "com.google.Chrome" || bundleId == "com.brave.Browser" || bundleId == "com.microsoft.edgemac")
            if isChromiumProfileRestore, let profileName = item.profileName, !profileName.isEmpty {
                let appName: String
                if bundleId == "com.google.Chrome" {
                    appName = "Google Chrome"
                } else if bundleId == "com.brave.Browser" {
                    appName = "Brave Browser"
                } else {
                    appName = "Microsoft Edge"
                }
                
                EchoLog.restore("[restore] Using open -na for \(appName) profile=\(profileName) url=\(urlString)")
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
                process.arguments = [
                    "-na", appName,
                    "--args",
                    "--profile-directory=\(profileName)",
                    urlString
                ]
                do {
                    try process.run()
                    process.waitUntilExit()
                    EchoLog.restore("[restore] open -na exited with status=\(process.terminationStatus)")
                    return
                } catch {
                    EchoLog.restore("[restore] open -na failed for profile \(profileName) in \(appName)", error: error)
                    // fallback to generic open
                }
            } else {
                EchoLog.restore("[restore] Using generic NSWorkspace path (no profile)")
            }

            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            _ = try await NSWorkspace.shared.open(
                [url],
                withApplicationAt: appURL,
                configuration: config
            )
            return
        }
        NSWorkspace.shared.open(url)
    }

    private func urlsMatch(_ a: String, _ b: String) -> Bool {
        a.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            == b.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
}

// MARK: - Document (Preview)

struct DocumentRestorer: WorkflowRestoring {
    func canRestore(_ item: RestoreItem) -> Bool {
        item.kind == .document && item.path != nil
    }

    func restore(_ item: RestoreItem) async throws {
        guard let path = item.path else { throw RestoreError.targetUnavailable }
        let fileURL = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: path) else {
            throw RestoreError.targetUnavailable
        }
        // Open in the specific app that had the file open (e.g. Pages, Numbers, Keynote)
        if let bundleId = item.bundleId,
           let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
            NSWorkspace.shared.open([fileURL], withApplicationAt: appURL, configuration: .init(), completionHandler: nil)
        } else {
            NSWorkspace.shared.open(fileURL)
        }
    }
}


// MARK: - Workspace (Xcode / Cursor / VS Code)

struct WorkspaceRestorer: WorkflowRestoring {
    func canRestore(_ item: RestoreItem) -> Bool {
        item.kind == .workspace && item.path != nil
    }

    func restore(_ item: RestoreItem) async throws {
        guard let path = item.path else { throw RestoreError.targetUnavailable }
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: path) else {
            throw RestoreError.targetUnavailable
        }
        if let bundleId = item.bundleId,
           let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            _ = try await NSWorkspace.shared.open(
                [url],
                withApplicationAt: appURL,
                configuration: config
            )
            return
        }
        NSWorkspace.shared.open(url)
    }
}

// MARK: - Application

struct ApplicationRestorer: WorkflowRestoring {
    func canRestore(_ item: RestoreItem) -> Bool {
        item.kind == .application && item.bundleId != nil
    }

    func skipReasonIfAlreadyOpen(_ item: RestoreItem) async -> String? {
        guard let bundleId = item.bundleId else { return nil }
        let running = NSWorkspace.shared.runningApplications.first {
            $0.bundleIdentifier == bundleId && !$0.isTerminated
        }
        guard let running else { return nil }
        
        if #available(macOS 14.0, *) {
            NSApplication.shared.yieldActivation(toApplicationWithBundleIdentifier: bundleId)
            running.activate()
        } else {
            running.activate(options: .activateIgnoringOtherApps)
        }
        return "already running"
    }

    func restore(_ item: RestoreItem) async throws {
        guard let bundleId = item.bundleId,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId)
        else { throw RestoreError.targetUnavailable }

        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        _ = try await NSWorkspace.shared.openApplication(at: url, configuration: config)
    }
}

// MARK: - URL (generic fallback)

struct URLRestorer: WorkflowRestoring {
    func canRestore(_ item: RestoreItem) -> Bool {
        item.kind == .url && item.url != nil
    }

    func restore(_ item: RestoreItem) async throws {
        guard let urlString = item.url, let url = URL(string: urlString) else {
            throw RestoreError.invalidURL
        }
        NSWorkspace.shared.open(url)
    }
}

// MARK: - Folder

struct FolderRestorer: WorkflowRestoring {
    func canRestore(_ item: RestoreItem) -> Bool {
        item.kind == .folder && item.path != nil
    }

    func skipReasonIfAlreadyOpen(_ item: RestoreItem) async -> String? {
        guard let path = item.path else { return nil }
        guard let finder = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == "com.apple.finder"
        }) else { return nil }
        
        if #available(macOS 14.0, *) {
            NSApplication.shared.yieldActivation(toApplicationWithBundleIdentifier: "com.apple.finder")
            finder.activate()
        } else {
            finder.activate(options: .activateIgnoringOtherApps)
        }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
        return "finder focused"
    }

    func restore(_ item: RestoreItem) async throws {
        guard let path = item.path else { throw RestoreError.targetUnavailable }
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: path) else {
            throw RestoreError.targetUnavailable
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}

// MARK: - Terminal

struct TerminalDirectoryRestorer: WorkflowRestoring {
    func canRestore(_ item: RestoreItem) -> Bool {
        item.kind == .terminalDirectory && item.workingDirectory != nil
    }

    func restore(_ item: RestoreItem) async throws {
        guard let cwd = item.workingDirectory else { throw RestoreError.targetUnavailable }
        guard FileManager.default.fileExists(atPath: cwd) else { throw RestoreError.targetUnavailable }
        
        let escaped = cwd.replacingOccurrences(of: "\"", with: "\\\"")
        let bundleId = item.bundleId ?? "com.apple.Terminal"
        
        if bundleId == "com.apple.Terminal" {
            let script = """
            tell application "Terminal"
                activate
                do script "cd \\"\(escaped)\\""
            end tell
            """
            try runAppleScript(script)
        } else if bundleId == "com.googlecode.iterm2" {
            let script = """
            tell application "iTerm"
                activate
                try
                    if (count of windows) is 0 then
                        create window with default profile
                    else
                        tell current window
                            create tab with default profile
                        end tell
                    end if
                on error
                    create window with default profile
                end try
                delay 0.1
                tell current session of current window
                    write text "cd \\"\(escaped)\\""
                end tell
            end tell
            """
            try runAppleScript(script)
        } else {
            // Fallback for other terminals (Warp, Hyper, etc.) using open -a
            let appName: String
            if bundleId.lowercased().contains("warp") {
                appName = "Warp"
            } else if bundleId.lowercased().contains("hyper") {
                appName = "Hyper"
            } else {
                appName = "Terminal"
            }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            process.arguments = ["-a", appName, cwd]
            do {
                try process.run()
                process.waitUntilExit()
            } catch {
                throw RestoreError.scriptFailed
            }
        }
    }
    
    private func runAppleScript(_ script: String) throws {
        var errorInfo: NSDictionary?
        guard let appleScript = NSAppleScript(source: script) else {
            throw RestoreError.scriptFailed
        }
        appleScript.executeAndReturnError(&errorInfo)
        if errorInfo != nil {
            throw RestoreError.scriptFailed
        }
    }
}

enum RestoreError: LocalizedError {
    case targetUnavailable
    case invalidURL
    case scriptFailed

    var errorDescription: String? {
        switch self {
        case .targetUnavailable: return "The restore target is no longer available."
        case .invalidURL: return "The URL could not be opened."
        case .scriptFailed: return "Could not restore the terminal directory."
        }
    }
}
