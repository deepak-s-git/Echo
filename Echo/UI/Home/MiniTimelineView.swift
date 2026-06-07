import SwiftUI

struct MiniTimelineView: View, Equatable {
    let segments: [TimelineSegment]
    let focusIntensity: Double

    static func == (lhs: MiniTimelineView, rhs: MiniTimelineView) -> Bool {
        lhs.segments == rhs.segments
            && abs(lhs.focusIntensity - rhs.focusIntensity) < 0.01
    }

    // Animation & Interaction States
    @State private var isLoaded = false
    @State private var hoveredSegmentId: UUID? = nil
    @State private var pulsePhase: Double = 0.0

    private func totalMinutes() -> Int {
        let totalSecs = segments.reduce(0) { $0 + $1.duration }
        return Int(totalSecs / 60)
    }

    private func hoveredColor() -> Color {
        guard let hoveredSegmentId = hoveredSegmentId else { return .clear }
        return segments.first(where: { $0.id == hoveredSegmentId })?.color ?? .clear
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        if duration < 60 {
            return "\(Int(duration))s"
        }
        let mins = Int(duration / 60)
        let secs = Int(duration.truncatingRemainder(dividingBy: 60))
        return secs > 0 ? "\(mins)m \(secs)s" : "\(mins)m"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Interactive Header
            HStack(alignment: .firstTextBaseline) {
                Text("Focus rhythm")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.secondary)

                Spacer()

                Text("\(Int(focusIntensity * 100))% steady")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(EchoPalette.indigoSoft)
            }
            .frame(height: 16)


            // Neon Beads on a String Timeline Panel
            ZStack(alignment: .center) {

                // Central horizontal thread (the string)
                Capsule()
                    .fill(Color.primary.opacity(0.08))
                    .frame(height: 2)
                    .padding(.horizontal, 4)
                    .overlay(
                        GeometryReader { trackGeo in
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [.clear, EchoPalette.accent.opacity(0.35), .clear],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: 45)
                                .offset(x: -45 + (trackGeo.size.width + 90) * pulsePhase)
                        }
                        .clipped()
                    )

                // Dynamic Time Ticks
                let totalMins = totalMinutes()
                HStack {
                    Text("0m")
                    Spacer()
                    if totalMins > 1 {
                        Text("\(totalMins / 2)m")
                    }
                    Spacer()
                    Text("\(totalMins)m")
                }
                .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                .foregroundStyle(.primary.opacity(0.18))
                .padding(.horizontal, 4)
                .offset(y: 28)

                GeometryReader { geo in
                    let widths = SessionTimelineBuilder.layoutWidths(
                        for: segments,
                        totalWidth: geo.size.width,
                        spacing: 3.5
                    )
                    
                    HStack(alignment: .center, spacing: 3.5) {
                        ForEach(Array(zip(segments, widths)), id: \.0.id) { segment, width in
                            TimelineBeadView(
                                segment: segment,
                                width: width,
                                isHovered: hoveredSegmentId == segment.id,
                                isAnyHovered: hoveredSegmentId != nil,
                                formatDuration: formatDuration,
                                onHover: { hovering in
                                    withAnimation(.spring(response: 0.22, dampingFraction: 0.72)) {
                                        hoveredSegmentId = hovering ? segment.id : nil
                                    }
                                }
                            )
                        }
                    }
                    .frame(width: geo.size.width, height: 60, alignment: .center)
                }
                .frame(height: 60)
            }
            .frame(height: 76)

            continuityBar
        }
        .padding(18)
        .echoCard()
        .onAppear {
            withAnimation(.spring(response: 0.65, dampingFraction: 0.72).delay(0.08)) {
                isLoaded = true
            }
            withAnimation(.linear(duration: 3.5).repeatForever(autoreverses: false)) {
                pulsePhase = 1.0
            }
        }
    }

    private var continuityBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "waveform")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.tertiary)
            
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.035))
                    
                    // Upgraded continuity bar with rich gradient and animated flow pulse
                    let gradient = LinearGradient(
                        colors: [EchoPalette.indigoSoft.opacity(0.65), EchoPalette.accent],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    
                    Capsule()
                        .fill(gradient)
                        .frame(width: max(0, geo.size.width * focusIntensity))
                        .overlay(
                            // Smooth scanning light overlay representing continuous attention stream
                            GeometryReader { innerGeo in
                                Capsule()
                                    .fill(
                                        LinearGradient(
                                            colors: [.clear, .white.opacity(0.4), .clear],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .frame(width: 35)
                                    .offset(x: -35 + (innerGeo.size.width + 70) * pulsePhase)
                            }
                            .clipped()
                        )
                }
            }
            .frame(height: 4.5)
        }
        .frame(height: 6)
    }
}

// MARK: - Timeline Bead Subview

private struct TimelineBeadView: View {
    let segment: TimelineSegment
    let width: CGFloat
    let isHovered: Bool
    let isAnyHovered: Bool
    let formatDuration: (TimeInterval) -> String
    let onHover: (Bool) -> Void
    
    var body: some View {
        let beadWidth = max(6.0, width)
        let beadHeight: CGFloat = isHovered ? 20.0 : 10.0
        let beadOpacity: Double = isHovered ? 1.0 : (isAnyHovered ? 0.45 : 0.85)
        let shadowOpacity: Double = isHovered ? 0.6 : 0.0
        
        ZStack {
            
            Capsule(style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            segment.color.opacity(0.9),
                            segment.color.opacity(0.6)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.35),
                                    Color.white.opacity(0.05),
                                    Color.white.opacity(0.25)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 0.8
                        )
                )
                .overlay(
                    Group {
                        if beadWidth >= 28 && isHovered {
                            AppIconView(bundleId: segment.bundleId, size: 12)
                                .clipShape(Circle())
                                .transition(.opacity.combined(with: .scale(scale: 0.8)))
                        }
                    }
                )
        }
        .frame(width: beadWidth, height: beadHeight)
        .shadow(color: Color.black.opacity(isHovered ? 0.22 : 0.05), radius: isHovered ? 4 : 1, y: isHovered ? 1.5 : 0.5)
        .opacity(beadOpacity)
        .onHover(perform: onHover)
        .overlay(
            Group {
                if isHovered {
                    VStack(spacing: 0) {
                        HStack(spacing: 6) {
                            AppIconView(bundleId: segment.bundleId, size: 14)
                                .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                            
                            Text(segment.appName)
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                            
                            Text("•")
                                .foregroundStyle(.white.opacity(0.3))
                            
                            Text(formatDuration(segment.duration))
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white.opacity(0.8))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color(nsColor: NSColor(white: 0.08, alpha: 0.90)))
                                .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5)
                        )
                        
                        Image(systemName: "arrowtriangle.down.fill")
                            .font(.system(size: 6))
                            .foregroundStyle(Color(nsColor: NSColor(white: 0.08, alpha: 0.90)))
                            .offset(y: -1)
                    }
                    .fixedSize()
                    .offset(y: -38)
                    .transition(.opacity.combined(with: .scale(scale: 0.9).combined(with: .offset(y: 4))))
                }
            },
            alignment: .top
        )
    }
}

