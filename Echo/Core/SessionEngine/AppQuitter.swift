import AppKit

struct AppQuitter {
    static func safelyQuitApps(bundleIdentifiers: [String]) async {
        for bundleId in bundleIdentifiers {
            guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first else { continue }
            
            let scriptSource = """
            tell application id "\(bundleId)"
                try
                    close every window
                end try
                quit
            end tell
            """
            
            if let script = NSAppleScript(source: scriptSource) {
                var error: NSDictionary?
                // Dispatch to background queue to avoid blocking main thread on AppleScript execution
                await withCheckedContinuation { continuation in
                    DispatchQueue.global(qos: .userInitiated).async {
                        script.executeAndReturnError(&error)
                        if let error = error {
                            print("Failed to gracefully quit \(bundleId) with AppleScript: \(error)")
                            app.terminate()
                        }
                        continuation.resume()
                    }
                }
            } else {
                app.terminate()
            }
        }
    }
}
