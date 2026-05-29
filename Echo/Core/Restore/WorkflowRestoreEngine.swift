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
            if restorer.skipReasonIfAlreadyOpen(item) != nil {
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
                try? await Task.sleep(for: .milliseconds(150))
            }
        }
        progress?(total, total)

        return RestoreResult(succeeded: succeeded, skipped: skipped, failed: failed)
    }
}

// MARK: - Protocol

protocol WorkflowRestoring {
    func canRestore(_ item: RestoreItem) -> Bool
    func skipReasonIfAlreadyOpen(_ item: RestoreItem) -> String?
    func restore(_ item: RestoreItem) async throws
}

extension WorkflowRestoring {
    func skipReasonIfAlreadyOpen(_ item: RestoreItem) -> String? { nil }
}

// MARK: - Browser page

struct BrowserPageRestorer: WorkflowRestoring {
    func canRestore(_ item: RestoreItem) -> Bool {
        (item.kind == .browserPage || item.kind == .url) && item.url != nil
    }

    func skipReasonIfAlreadyOpen(_ item: RestoreItem) -> String? {
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

            if bundleId == "com.google.Chrome", let profileName = item.profileName, !profileName.isEmpty {
                EchoLog.restore("[restore] Using open -na for profile=\(profileName) url=\(urlString)")
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
                process.arguments = [
                    "-na", "Google Chrome",
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
                    EchoLog.restore("[restore] open -na failed for profile \(profileName)", error: error)
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
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: path) else {
            throw RestoreError.targetUnavailable
        }
        NSWorkspace.shared.open(url)
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
            _ = try await NSWorkspace.shared.open(
                [url],
                withApplicationAt: appURL,
                configuration: NSWorkspace.OpenConfiguration()
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

    func skipReasonIfAlreadyOpen(_ item: RestoreItem) -> String? {
        guard let bundleId = item.bundleId else { return nil }
        let running = NSWorkspace.shared.runningApplications.first {
            $0.bundleIdentifier == bundleId && !$0.isTerminated
        }
        guard let running else { return nil }
        running.activate()
        return "already running"
    }

    func restore(_ item: RestoreItem) async throws {
        guard let bundleId = item.bundleId,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId)
        else { throw RestoreError.targetUnavailable }

        let config = NSWorkspace.OpenConfiguration()
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

    func skipReasonIfAlreadyOpen(_ item: RestoreItem) -> String? {
        guard let path = item.path else { return nil }
        guard let finder = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == "com.apple.finder"
        }) else { return nil }
        finder.activate()
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
        let escaped = cwd.replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
        tell application "Terminal"
            activate
            do script "cd \\"\(escaped)\\""
        end tell
        """
        var error: NSDictionary?
        guard let appleScript = NSAppleScript(source: script) else {
            throw RestoreError.scriptFailed
        }
        appleScript.executeAndReturnError(&error)
        if error != nil { throw RestoreError.scriptFailed }
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
