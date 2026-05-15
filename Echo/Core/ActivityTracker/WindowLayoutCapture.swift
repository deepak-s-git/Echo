import AppKit
import CoreGraphics

struct WindowLayoutCapture {

    static func captureCurrentLayout() -> WindowLayout {
        let options: CGWindowListOption = [.excludeDesktopElements, .optionOnScreenOnly]
        let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []

        let frames = windowList.compactMap { dict -> WindowLayout.WindowFrame? in
            guard
                let boundsDict = dict[kCGWindowBounds as String] as? [String: CGFloat],
                let appName = dict[kCGWindowOwnerName as String] as? String,
                let layer = dict[kCGWindowLayer as String] as? Int,
                layer == 0
            else { return nil }

            let frame = CGRect(
                x: boundsDict["X"] ?? 0,
                y: boundsDict["Y"] ?? 0,
                width: boundsDict["Width"] ?? 0,
                height: boundsDict["Height"] ?? 0
            )

            let bundleId = bundleIdentifier(for: appName)

            return WindowLayout.WindowFrame(
                appName: appName,
                bundleId: bundleId,
                frame: frame,
                isMainWindow: dict[kCGWindowIsOnscreen as String] as? Bool ?? false,
                spaceIndex: 0
            )
        }

        return WindowLayout(
            frames: frames,
            capturedAt: Date(),
            screenCount: NSScreen.screens.count
        )
    }

    private static func bundleIdentifier(for appName: String) -> String {
        NSWorkspace.shared.runningApplications
            .first { $0.localizedName == appName }?
            .bundleIdentifier ?? "unknown"
    }
}
