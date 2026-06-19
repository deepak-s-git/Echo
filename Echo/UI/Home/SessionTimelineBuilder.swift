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

    static func segments(from events: [ActivityEvent], session: Session? = nil) -> [TimelineSegment] {
        let blocks = focusBlocks(from: events, session: session)
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

    private static func focusBlocks(from events: [ActivityEvent], session: Session? = nil) -> [FocusBlock] {
        let focusEvents = events
            .filter { $0.type == .appFocus || $0.type == .appSwitch }
            .sorted { $0.timestamp < $1.timestamp }
            
        guard !focusEvents.isEmpty else { return [] }
        
        let sessionStart = session?.startedAt ?? focusEvents.first!.timestamp
        let sessionEnd = session?.endedAt ?? session?.pausedAt ?? focusEvents.map { $0.timestamp + ($0.type == .appSwitch ? $0.duration : 0) }.max() ?? Date()
        
        struct Interval {
            let appName: String
            let bundleId: String
            var start: Date
            var end: Date
        }
        
        var intervals: [Interval] = []
        
        // 1. Gather all appSwitch intervals (actual focus periods)
        for event in focusEvents where event.type == .appSwitch && event.duration > 0 {
            let eventStart = event.timestamp
            let eventEnd = eventStart.addingTimeInterval(event.duration)
            
            let clippedStart = max(eventStart, sessionStart)
            let clippedEnd = min(eventEnd, sessionEnd)
            
            if clippedEnd > clippedStart {
                intervals.append(Interval(
                    appName: event.appName,
                    bundleId: event.appBundleId,
                    start: clippedStart,
                    end: clippedEnd
                ))
            }
        }
        
        // 2. Handle the active/current focus at the end of the session
        if let lastEvent = focusEvents.last {
            let eventStart = lastEvent.timestamp
            let clippedStart = max(eventStart, sessionStart)
            
            let isAlreadyCovered = intervals.contains { $0.bundleId == lastEvent.appBundleId && $0.start <= clippedStart && $0.end >= sessionEnd }
            if !isAlreadyCovered && sessionEnd > clippedStart {
                intervals.append(Interval(
                    appName: lastEvent.appName,
                    bundleId: lastEvent.appBundleId,
                    start: clippedStart,
                    end: sessionEnd
                ))
            }
        }
        
        // 3. Fallback: if no intervals were extracted, use appFocus timestamps
        if intervals.isEmpty {
            for event in focusEvents {
                let clippedStart = max(event.timestamp, sessionStart)
                let clippedEnd = min(clippedStart.addingTimeInterval(15), sessionEnd)
                if clippedEnd > clippedStart {
                    intervals.append(Interval(
                        appName: event.appName,
                        bundleId: event.appBundleId,
                        start: clippedStart,
                        end: clippedEnd
                    ))
                }
            }
        }
        
        // Sort intervals chronologically
        intervals.sort { $0.start < $1.start }
        
        // Resolve overlaps: each interval's end is capped at the start of the next interval
        if intervals.count > 1 {
            for i in 0..<(intervals.count - 1) {
                if intervals[i].end > intervals[i + 1].start {
                    intervals[i].end = intervals[i + 1].start
                }
            }
        }
        
        // Group consecutive blocks of the same app (sum durations)
        var grouped: [FocusBlock] = []
        for interval in intervals {
            let duration = max(1.0, interval.end.timeIntervalSince(interval.start))
            if let lastIndex = grouped.indices.last, grouped[lastIndex].bundleId == interval.bundleId {
                let existing = grouped[lastIndex]
                grouped[lastIndex] = FocusBlock(
                    id: existing.id,
                    appName: existing.appName,
                    bundleId: existing.bundleId,
                    duration: existing.duration + duration,
                    isSwitch: true
                )
            } else {
                grouped.append(FocusBlock(
                    id: UUID(),
                    appName: interval.appName,
                    bundleId: interval.bundleId,
                    duration: duration,
                    isSwitch: true
                ))
            }
        }
        
        if grouped.count > EchoConfig.maxTimelineSegments {
            grouped = Array(grouped.suffix(EchoConfig.maxTimelineSegments))
        }
        
        return grouped
    }

    private static func color(for bundleId: String) -> Color {
        let cleanId = bundleId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        
        // 1. Compute standard DJB2 hash of the bundle ID
        var hash: UInt32 = 5381
        for byte in cleanId.utf8 {
            hash = ((hash << 5) &+ hash) &+ UInt32(byte)
        }
        
        // 2. Generate Hue deterministically (0.0 to 1.0)
        let hue = Double(hash % 360) / 360.0
        
        // 3. Keep saturation and brightness within highly aesthetic, harmonious ranges
        // Saturation: 60% to 80% (vibrant but cohesive)
        let saturation = 0.60 + Double((hash >> 8) % 20) / 100.0
        // Brightness: 55% to 65% (ideal contrast for readable blocks)
        let brightness = 0.55 + Double((hash >> 16) % 10) / 100.0
        
        // 4. Return deterministic HSB color
        return Color(hue: hue, saturation: saturation, brightness: brightness)
    }
}
