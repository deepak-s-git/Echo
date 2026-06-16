import SwiftUI

struct ActivityFeedView: View, Equatable {
    let events: [ActivityEvent]

    static func == (lhs: ActivityFeedView, rhs: ActivityFeedView) -> Bool {
        lhs.events.count == rhs.events.count
            && lhs.events.last?.id == rhs.events.last?.id
    }

    private var displayEvents: [ActivityEvent] {
        let focusedOnly = events.filter { $0.type == .appFocus }
        return Array(focusedOnly.suffix(EchoConfig.maxFeedDisplayEvents).reversed())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Live activity")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(events.count) events")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(EchoPalette.indigoSoft)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(EchoPalette.indigo.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(EchoPalette.indigo.opacity(0.24), lineWidth: 0.5))
            }

            if displayEvents.isEmpty {
                emptyState
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(displayEvents) { event in
                        ActivityFeedRow(event: event)
                    }
                }
            }
        }
        .padding(18)
        .echoCard()
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 24, weight: .thin))
                .foregroundStyle(EchoPalette.indigo.opacity(0.4))
            Text("Switch apps to begin your feed")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }
}

private struct ActivityFeedRow: View {
    let event: ActivityEvent
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 12) {
            AppIconView(bundleId: event.appBundleId, size: 26)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(AppMetadataResolver.displayName(
                        bundleId: event.appBundleId,
                        rawName: event.appName
                    ))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.primary)
                    Spacer()
                    Text(event.timestamp, style: .time)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.secondary)
                }

                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary.opacity(0.85))
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: EchoDesign.pillRadius, style: .continuous)
                .fill(hovering ? Color.primary.opacity(0.03) : .clear)
        )
        .onHover { hovering = $0 }
    }

    private var subtitle: String {
        switch event.type {
        case .appFocus:
            let text = [event.windowTitle, event.url]
                .compactMap { $0 }
                .filter { !$0.isEmpty }
                .joined(separator: " • ")
            if !text.isEmpty { return text }
            return "Now in focus"
        case .appSwitch:
            return "Focused for \(event.duration.shortLabel)"
        default:
            return event.type.rawValue
        }
    }
}
