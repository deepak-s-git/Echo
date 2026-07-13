import Foundation
import AppKit
import CoreGraphics

struct SpaceTracker: Sendable {

    private typealias CGSMainConnectionIDType = @convention(c) () -> Int32

    // MARK: - Core Helpers

    /// Returns the CGS connection ID needed for all private API calls.
    private nonisolated static func cgsConnection() -> Int32 {
        let coreGraphics = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_NOW)
        let skyLight = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_NOW)
        guard let sym = dlsym(coreGraphics, "CGSMainConnectionID") ?? dlsym(skyLight, "CGSMainConnectionID") else { return 0 }
        let fn = unsafeBitCast(sym, to: CGSMainConnectionIDType.self)
        return fn()
    }

    /// Returns all displays with their spaces from `CGSCopyManagedDisplaySpaces`.
    private nonisolated static func managedDisplaySpaces() -> [[String: Any]] {
        let skyLight = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_NOW)
        typealias Fn = @convention(c) (Int32) -> Unmanaged<NSArray>?
        guard let sym = dlsym(skyLight, "CGSCopyManagedDisplaySpaces") else { return [] }
        let fn = unsafeBitCast(sym, to: Fn.self)
        guard let result = fn(cgsConnection())?.takeRetainedValue() as? [[String: Any]] else { return [] }
        return result
    }

    /// Returns the ordered array of `ManagedSpaceID`s for the main display (left-to-right).
    nonisolated static func orderedSpaceIDs() -> [Int] {
        for display in managedDisplaySpaces() {
            if let spaces = display["Spaces"] as? [[String: Any]], !spaces.isEmpty {
                return spaces.compactMap { $0["ManagedSpaceID"] as? Int }
            }
        }
        return []
    }

    /// Returns the raw `ManagedSpaceID` and its `type` of the currently active desktop.
    private nonisolated static func currentManagedSpaceInfo() -> (id: Int, type: Int) {
        for display in managedDisplaySpaces() {
            if let cs = display["Current Space"] as? [String: Any],
               let sid = cs["ManagedSpaceID"] as? Int,
               let type = cs["type"] as? Int {
                return (sid, type)
            }
        }
        return (0, 0)
    }

    // MARK: - Ordinal Position API

    /// Returns the **ordinal position** (0, 1, 2, 3...) of the currently active desktop space and whether it is a fullscreen space.
    nonisolated static func activeSpaceInfo() -> (index: Int, isFullScreen: Bool) {
        let current = currentManagedSpaceInfo()
        guard current.id != 0 else { return (0, false) }
        let ordered = orderedSpaceIDs()
        let index = ordered.firstIndex(of: current.id) ?? 0
        return (index, current.type == 4)
    }

    /// Returns just the **ordinal position** (0, 1, 2, 3...) of the currently active desktop space.
    nonisolated static func activeSpaceIndex() -> Int {
        return activeSpaceInfo().index
    }

    /// Legacy alias — returns the ordinal position. All existing callers use this name.
    nonisolated static func activeSpaceID() -> Int {
        return activeSpaceIndex()
    }

}
