import AppKit
import ApplicationServices

/// Resolves document / file context for the focused window using Accessibility APIs.
/// Works for any NSDocument-based app: Preview, Xcode, Word, Pages, TextEdit, etc.
///
/// Priority:
///   1. `kAXDocument` attribute  →  full `file://` URL from the OS
///   2. Parse window title       →  strip " — AppName" / " - AppName" suffix
enum DocumentContextResolver {

    struct DocumentContext: Sendable {
        /// Human-readable name, e.g. "Design.pdf" or "AppDelegate.swift"
        let name: String
        /// `file://` URL string when available via AX, nil when parsed from title
        let fileURL: String?
    }

    // MARK: - Public

    /// Reads document context for the currently focused window.
    /// Call on the MainActor (reads AX and NSWorkspace).
    @MainActor
    static func resolveFocused(appName: String) -> DocumentContext? {
        guard AXIsProcessTrusted(),
              let app = NSWorkspace.shared.frontmostApplication
        else { return nil }

        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var focused: AnyObject?
        guard AXUIElementCopyAttributeValue(
            appElement, kAXFocusedWindowAttribute as CFString, &focused
        ) == .success, let window = focused else { return nil }

        return resolve(windowElement: window as! AXUIElement, appName: appName)
    }

    /// Reads document context for a specific AX window element.
    static func resolve(windowElement: AXUIElement, appName: String) -> DocumentContext? {
        // 1. Try kAXDocument — gives a full "file:///…" string (most reliable)
        if let docURL = copyString(windowElement, "AXDocument" as CFString),
           !docURL.isEmpty {
            let name = URL(string: docURL)?.lastPathComponent
                    ?? URL(fileURLWithPath: docURL).lastPathComponent
            if !name.isEmpty { return DocumentContext(name: name, fileURL: docURL) }
        }

        // 2. Parse window title: "Design.pdf — Preview" → "Design.pdf"
        if let title = copyString(windowElement, kAXTitleAttribute as CFString),
           !title.isEmpty {
            let parsed = stripAppSuffix(from: title, appName: appName)
            // Only meaningful if it actually differs and looks like a document name
            if !parsed.isEmpty, parsed != appName, looksLikeDocument(parsed) {
                return DocumentContext(name: parsed, fileURL: nil)
            }
        }

        return nil
    }

    // MARK: - Helpers

    private static func stripAppSuffix(from title: String, appName: String) -> String {
        // Separators in common use: em-dash, en-dash, hyphen
        let seps = [" \u{2014} ", " \u{2013} ", " — ", " – ", " - "]
        for sep in seps {
            if title.hasSuffix(sep + appName) {
                return String(title.dropLast((sep + appName).count))
            }
            // Also handle "Title – App – Another Suffix"
            if let range = title.range(of: sep + appName, options: .backwards) {
                return String(title[..<range.lowerBound])
            }
        }
        return title
    }

    /// Heuristic: a string looks like a document if it has a file extension
    /// or is not just a generic app label.
    private static func looksLikeDocument(_ name: String) -> Bool {
        let ext = (name as NSString).pathExtension
        return !ext.isEmpty
    }

    private static func copyString(_ element: AXUIElement, _ attr: CFString) -> String? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, attr, &value) == .success else { return nil }
        return value as? String
    }
}
