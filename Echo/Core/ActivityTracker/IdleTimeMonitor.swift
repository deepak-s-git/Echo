import IOKit
import Foundation

/// Monitors system idle time using IOHIDSystem.
/// Actor-isolated to eliminate data races on isIdle state.
actor IdleTimeMonitor {

    private let threshold: TimeInterval
    private var monitorTask: Task<Void, Never>?
    private(set) var isIdle: Bool = false

    var onIdleStateChange: (@MainActor (Bool) -> Void)?

    init(threshold: TimeInterval) {
        self.threshold = threshold
    }

    func start() {
        guard monitorTask == nil else { return }
        monitorTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                await self?.tick()
            }
        }
    }

    func stop() {
        monitorTask?.cancel()
        monitorTask = nil
    }

    func currentIdleSeconds() -> TimeInterval {
        Self.readIdleTime()
    }

    private func tick() async {
        let idle = Self.readIdleTime()
        let nowIdle = idle >= threshold
        guard nowIdle != isIdle else { return }
        isIdle = nowIdle
        let callback = onIdleStateChange
        let state = nowIdle
        await MainActor.run { callback?(state) }
    }

    nonisolated static func readIdleTime() -> TimeInterval {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(
            kIOMainPortDefault,
            IOServiceMatching("IOHIDSystem"),
            &iterator
        ) == KERN_SUCCESS else { return 0 }
        defer { IOObjectRelease(iterator) }

        let entry = IOIteratorNext(iterator)
        guard entry != 0 else { return 0 }
        defer { IOObjectRelease(entry) }

        var dict: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(
            entry, &dict, kCFAllocatorDefault, 0
        ) == KERN_SUCCESS else { return 0 }

        guard let props = dict?.takeRetainedValue() as? [String: Any],
              let nanos = props["HIDIdleTime"] as? Int64
        else { return 0 }

        return TimeInterval(nanos) / 1_000_000_000
    }
}
