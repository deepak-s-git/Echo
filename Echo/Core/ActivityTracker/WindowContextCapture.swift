import AppKit
import ApplicationServices

/// Reads focused window metadata when Accessibility is granted.
enum WindowContextCapture {

    struct WindowContext: Sendable {
        let title: String?
        /// `file://` URL from kAXDocument attribute — set for document-based apps.
        let documentURL: String?
    }
    nonisolated static func focusedWindowContext(for pid: pid_t) -> WindowContext {
        guard AXIsProcessTrusted() else { return WindowContext(title: nil, documentURL: nil) }

        let appElement = AXUIElementCreateApplication(pid)
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
    nonisolated static func allOpenWindowsContexts(for pid: pid_t) -> [WindowContext] {
        guard AXIsProcessTrusted() else { return [] }

        let appElement = AXUIElementCreateApplication(pid)
        var windowsRef: AnyObject?
        let result = AXUIElementCopyAttributeValue(
            appElement,
            kAXWindowsAttribute as CFString,
            &windowsRef
        )
        guard result == .success,
              let windows = windowsRef as? [AXUIElement]
        else { return [] }

        var results: [WindowContext] = []
        for windowElement in windows {
            let title = copyStringAttribute(windowElement, kAXTitleAttribute as CFString)
            let documentURL = copyStringAttribute(windowElement, "AXDocument" as CFString)
            results.append(WindowContext(title: title, documentURL: documentURL))
        }
        return results
    }

    nonisolated private static func copyStringAttribute(_ element: AXUIElement, _ attribute: CFString) -> String? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else {
            return nil
        }
        return value as? String
    }
}
