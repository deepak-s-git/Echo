import SwiftUI

struct ActivityFeedView: View, Equatable {
    let events: [ActivityEvent]

    static func == (lhs: ActivityFeedView, rhs: ActivityFeedView) -> Bool {
        lhs.events.count == rhs.events.count
            && lhs.events.last?.id == rhs.events.last?.id
    }

    private var displayEvents: [ActivityEvent] {
        Array(events.suffix(EchoConfig.maxFeedDisplayEvents).reversed())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Live activity")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(events.count) events")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.quaternary)
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
            AppIconView(bundleId: event.appBundleId, size: 28)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(AppMetadataResolver.displayName(
                        bundleId: event.appBundleId,
                        rawName: event.appName
                    ))
                        .font(.system(size: 13, weight: .medium))
                    Spacer()
                    Text(event.timestamp, style: .time)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.quaternary)
                }

                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 2)
        .background(hovering ? Color.primary.opacity(0.03) : .clear)
        .onHover { hovering = $0 }
    }

    private var subtitle: String {
        switch event.type {
        case .appFocus:
            if let title = event.windowTitle, !title.isEmpty { return title }
            return "Now in focus"
        case .appSwitch:
            return "Focused for \(event.duration.shortLabel)"
        default:
            return event.type.rawValue
        }
    }
}
