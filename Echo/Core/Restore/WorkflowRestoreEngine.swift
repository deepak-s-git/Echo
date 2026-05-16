import AppKit
import Foundation

/// Modular workflow restoration — extensible for future layout/workspace restore.
@MainActor
final class WorkflowRestoreEngine {

    private let restorers: [any WorkflowRestoring]

    init(restorers: [any WorkflowRestoring]? = nil) {
        self.restorers = restorers ?? [
            ApplicationRestorer(),
            URLRestorer(),
            FolderRestorer(),
            TerminalDirectoryRestorer()
        ]
    }

    func restore(plan: WorkflowRestorePlan) async -> RestoreResult {
        var succeeded: [RestoreItem] = []
        var failed: [(RestoreItem, String)] = []

        for item in plan.items {
            guard let restorer = restorers.first(where: { $0.canRestore(item) }) else {
                failed.append((item, "No restorer available"))
                continue
            }
            do {
                try await restorer.restore(item)
                succeeded.append(item)
            } catch {
                failed.append((item, error.localizedDescription))
            }
        }

        return RestoreResult(succeeded: succeeded, failed: failed)
    }
}

// MARK: - Protocol

protocol WorkflowRestoring {
    func canRestore(_ item: RestoreItem) -> Bool
    func restore(_ item: RestoreItem) async throws
}

// MARK: - Application

struct ApplicationRestorer: WorkflowRestoring {
    func canRestore(_ item: RestoreItem) -> Bool {
        item.kind == .application && item.bundleId != nil
    }

    func restore(_ item: RestoreItem) async throws {
        guard let bundleId = item.bundleId,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId)
        else { throw RestoreError.targetUnavailable }

        let config = NSWorkspace.OpenConfiguration()
        _ = try await NSWorkspace.shared.openApplication(at: url, configuration: config)
    }
}

// MARK: - URL

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
