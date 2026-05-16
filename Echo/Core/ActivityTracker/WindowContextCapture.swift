import AppKit
import ApplicationServices

/// Reads focused window metadata when Accessibility is granted.
enum WindowContextCapture {

    static func focusedWindowContext() -> (title: String?, url: String?) {
        guard AXIsProcessTrusted() else { return (nil, nil) }
        guard let app = NSWorkspace.shared.frontmostApplication else { return (nil, nil) }

        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var focusedWindow: AnyObject?
        guard AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedWindowAttribute as CFString,
            &focusedWindow
        ) == .success,
              let window = focusedWindow
        else { return (nil, nil) }

        let windowElement = window as! AXUIElement
        let title = copyStringAttribute(windowElement, kAXTitleAttribute as CFString)
        return (title, nil)
    }

    private static func copyStringAttribute(_ element: AXUIElement, _ attribute: CFString) -> String? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else {
            return nil
        }
        return value as? String
    }
}
