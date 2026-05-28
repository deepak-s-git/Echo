import AppKit
import ApplicationServices

/// Reads focused window metadata when Accessibility is granted.
enum WindowContextCapture {

    struct WindowContext: Sendable {
        let title: String?
        /// `file://` URL from kAXDocument attribute — set for document-based apps.
        let documentURL: String?
    }

    @MainActor
    static func focusedWindowContext() -> WindowContext {
        guard AXIsProcessTrusted() else { return WindowContext(title: nil, documentURL: nil) }
        guard let app = NSWorkspace.shared.frontmostApplication else {
            return WindowContext(title: nil, documentURL: nil)
        }

        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var focusedWindow: AnyObject?
        guard AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedWindowAttribute as CFString,
            &focusedWindow
        ) == .success,
              let window = focusedWindow
        else { return WindowContext(title: nil, documentURL: nil) }

        let windowElement = window as! AXUIElement
        let title = copyStringAttribute(windowElement, kAXTitleAttribute as CFString)
        // kAXDocument gives the full file:// URL for document-based apps (Preview, Xcode, etc.)
        let documentURL = copyStringAttribute(windowElement, "AXDocument" as CFString)

        return WindowContext(title: title, documentURL: documentURL)
    }

    private static func copyStringAttribute(_ element: AXUIElement, _ attribute: CFString) -> String? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else {
            return nil
        }
        return value as? String
    }
}
