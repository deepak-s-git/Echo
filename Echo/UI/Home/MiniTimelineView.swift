import SwiftUI

struct MiniTimelineView: View, Equatable {
    let segments: [TimelineSegment]
    let focusIntensity: Double

    static func == (lhs: MiniTimelineView, rhs: MiniTimelineView) -> Bool {
        lhs.segments == rhs.segments
            && abs(lhs.focusIntensity - rhs.focusIntensity) < 0.01
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Focus rhythm")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(focusIntensity * 100))% steady")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(EchoPalette.indigoSoft)
            }

            GeometryReader { geo in
                let widths = SessionTimelineBuilder.layoutWidths(
                    for: segments,
                    totalWidth: geo.size.width,
                    spacing: 2
                )
                HStack(spacing: 2) {
                    ForEach(Array(zip(segments, widths)), id: \.0.id) { segment, width in
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(segment.color.opacity(0.85))
                            .frame(width: width, height: 14)
                            .help(segment.appName)
                    }
                }
                .frame(width: geo.size.width, alignment: .leading)
            }
            .frame(height: 14)
            .clipped()

            continuityBar
        }
        .padding(18)
        .echoCard()
    }

    private var continuityBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "waveform.path")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.quaternary)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.05))
                    Capsule()
                        .fill(EchoPalette.indigo.opacity(0.55))
                        .frame(width: max(0, geo.size.width * focusIntensity))
                }
            }
            .frame(height: 3)
        }
    }
}
