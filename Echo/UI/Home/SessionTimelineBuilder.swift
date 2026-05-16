import SwiftUI

struct TimelineSegment: Identifiable, Equatable {
    let id: UUID
    let appName: String
    let bundleId: String
    let duration: TimeInterval
    let color: Color
    let isSwitch: Bool
}

enum SessionTimelineBuilder {

    static func segments(from events: [ActivityEvent]) -> [TimelineSegment] {
        let blocks = focusBlocks(from: events)
        guard !blocks.isEmpty else { return [] }

        return blocks.map { block in
            TimelineSegment(
                id: block.id,
                appName: block.appName,
                bundleId: block.bundleId,
                duration: block.duration,
                color: color(for: block.bundleId),
                isSwitch: block.isSwitch
            )
        }
    }

    /// Returns pixel widths that always fit within `totalWidth` (accounts for spacing).
    static func layoutWidths(
        for segments: [TimelineSegment],
        totalWidth: CGFloat,
        spacing: CGFloat = 2
    ) -> [CGFloat] {
        guard !segments.isEmpty, totalWidth > 0 else { return [] }

        let count = segments.count
        let totalSpacing = spacing * CGFloat(max(0, count - 1))
        let available = max(0, totalWidth - totalSpacing)
        let durationSum = segments.reduce(0) { $0 + $1.duration }
        guard durationSum > 0 else { return [] }

        let minWidth: CGFloat = 3
        var widths = segments.map { segment -> CGFloat in
            let fraction = segment.duration / durationSum
            return max(minWidth, available * fraction)
        }

        var sum = widths.reduce(0, +)
        if sum > available {
            let scale = available / sum
            widths = widths.map { max(minWidth, $0 * scale) }
            sum = widths.reduce(0, +)
        }

        if sum > available, let idx = widths.firstIndex(of: widths.max() ?? 0) {
            widths[idx] = max(minWidth, widths[idx] - (sum - available))
        }

        return widths
    }

    static func focusIntensity(from events: [ActivityEvent]) -> Double {
        guard events.count >= 2 else { return 1 }
        let window = events.suffix(min(12, events.count))
        let switches = window.filter { $0.type == .appSwitch }.count
        let rate = Double(switches) / Double(window.count)
        return min(max(1 - rate * 1.2, 0.15), 1)
    }

    // MARK: - Private

    private struct FocusBlock {
        let id: UUID
        let appName: String
        let bundleId: String
        let duration: TimeInterval
        let isSwitch: Bool
    }

    private static func focusBlocks(from events: [ActivityEvent]) -> [FocusBlock] {
        var blocks: [FocusBlock] = []

        for event in events {
            switch event.type {
            case .appSwitch where event.duration > 0:
                blocks.append(FocusBlock(
                    id: event.id,
                    appName: event.appName,
                    bundleId: event.appBundleId,
                    duration: event.duration,
                    isSwitch: true
                ))
            case .appFocus:
                blocks.append(FocusBlock(
                    id: event.id,
                    appName: event.appName,
                    bundleId: event.appBundleId,
                    duration: max(event.duration, 1.5),
                    isSwitch: false
                ))
            default:
                continue
            }
        }

        if blocks.isEmpty, let last = events.last {
            blocks.append(FocusBlock(
                id: last.id,
                appName: last.appName,
                bundleId: last.appBundleId,
                duration: 20,
                isSwitch: false
            ))
        }

        if blocks.count > EchoConfig.maxTimelineSegments {
            blocks = Array(blocks.suffix(EchoConfig.maxTimelineSegments))
        }

        return blocks
    }

    private static func color(for bundleId: String) -> Color {
        var hash: UInt64 = 5381
        for byte in bundleId.utf8 {
            hash = ((hash << 5) &+ hash) &+ UInt64(byte)
        }
        let hue = Double(hash % 360) / 360.0
        return Color(hue: hue, saturation: 0.22, brightness: 0.72)
    }
}
