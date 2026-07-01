import SwiftUI

struct MiniTimelineView: View, Equatable {
    let segments: [TimelineSegment]
    let focusIntensity: Double
    var isLive: Bool = false
    let accentVibe: AccentVibe

    static func == (lhs: MiniTimelineView, rhs: MiniTimelineView) -> Bool {
        lhs.segments == rhs.segments
            && abs(lhs.focusIntensity - rhs.focusIntensity) < 0.01
            && lhs.accentVibe == rhs.accentVibe
    }

    // Animation & Interaction States
    @State private var isLoaded = false
    @State private var hoveredSegmentId: UUID? = nil

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

    private func centerXForBead(at index: Int, widths: [CGFloat]) -> CGFloat {
        var x: CGFloat = 0
        for i in 0..<index {
            x += widths[i] + 3.5
        }
        return x + widths[index] / 2
    }

    private func cardXOffsetForBead(at index: Int, widths: [CGFloat], totalWidth: CGFloat) -> CGFloat {
        guard index < widths.count else { return 0 }
        let centerX = centerXForBead(at: index, widths: widths)
        let halfWidth: CGFloat = 97.5 + 8 // 97.5 is 195/2, 8 is safety padding from edges
        
        var offset: CGFloat = 0
        if centerX < halfWidth {
            offset = halfWidth - centerX
        } else if centerX > totalWidth - halfWidth {
            offset = (totalWidth - halfWidth) - centerX
        }
        
        // Clamp to ensure the downward pointer remains inside the card's rounded rect bounds
        let maxOffset: CGFloat = 97.5 - 16
        return max(-maxOffset, min(maxOffset, offset))
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
                        PulsingTrackOverlay(isLive: isLive)
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
                    
                    ZStack {
                        // Visual Layer (renders beads and tooltips, pass-through hit testing)
                        HStack(alignment: .center, spacing: 3.5) {
                            ForEach(Array(segments.enumerated()), id: \.element.id) { index, segment in
                                let width = widths[index]
                                let cardOffset = cardXOffsetForBead(at: index, widths: widths, totalWidth: geo.size.width)
                                
                                TimelineBeadVisualView(
                                    segment: segment,
                                    width: width,
                                    isHovered: hoveredSegmentId == segment.id,
                                    isAnyHovered: hoveredSegmentId != nil,
                                    formatDuration: formatDuration,
                                    cardXOffset: cardOffset
                                )
                                .zIndex(hoveredSegmentId == segment.id ? 2 : 1)
                            }
                        }
                        .allowsHitTesting(false)
                        
                        // Hover Detection Layer (completely static, catches hover, transparent)
                        HStack(alignment: .center, spacing: 3.5) {
                            ForEach(Array(segments.enumerated()), id: \.element.id) { index, segment in
                                let width = widths[index]
                                
                                Color.white.opacity(0.0001)
                                    .frame(width: max(6.0, width), height: 40)
                                    .contentShape(Rectangle())
                                    .onHover { hovering in
                                        withAnimation(.spring(response: 0.22, dampingFraction: 0.72)) {
                                            if hovering {
                                                hoveredSegmentId = segment.id
                                            } else if hoveredSegmentId == segment.id {
                                                hoveredSegmentId = nil
                                            }
                                        }
                                    }
                            }
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
                            ScanningLightOverlay(isLive: isLive)
                        )
                }
            }
            .frame(height: 4.5)
        }
        .frame(height: 6)
    }
}

// MARK: - Timeline Bead Subview

private struct TimelineBeadVisualView: View {
    let segment: TimelineSegment
    let width: CGFloat
    let isHovered: Bool
    let isAnyHovered: Bool
    let formatDuration: (TimeInterval) -> String
    let cardXOffset: CGFloat
    
    private var appCategory: String {
        let id = segment.bundleId.lowercased()
        let name = segment.appName.lowercased()
        if id.contains("chrome") || id.contains("safari") || id.contains("browser") || id.contains("arc") {
            return "Research & Documentation"
        } else if id.contains("xcode") || id.contains("vscode") || id.contains("cursor") || name.contains("code") {
            return "Development & Engineering"
        } else if id.contains("terminal") || id.contains("warp") || id.contains("iterm") || name.contains("terminal") {
            return "Command Line & Systems"
        } else if id.contains("finder") {
            return "File Management"
        } else if id.contains("figma") || id.contains("photoshop") || id.contains("illustrator") || name.contains("figma") {
            return "Design & Creative"
        } else if id.contains("slack") || id.contains("discord") || id.contains("message") || name.contains("slack") {
            return "Collaboration & Comms"
        } else if id.contains("spotify") || id.contains("music") {
            return "Media & Audio Background"
        } else {
            return "Utility & Active Task"
        }
    }
    
    private var focusContribution: String {
        let duration = segment.duration
        if duration >= 300 {
            return "High"
        } else if duration >= 60 {
            return "Medium"
        } else {
            return "Low"
        }
    }
    
    private var focusContributionColor: Color {
        switch focusContribution {
        case "High": return Color(nsColor: NSColor(red: 0.13, green: 0.77, blue: 0.37, alpha: 1.0)) // vibrant green
        case "Medium": return Color.orange
        default: return Color.secondary
        }
    }
    
    var body: some View {
        let beadWidth = max(6.0, width)
        let beadHeight: CGFloat = isHovered ? 20.0 : 10.0
        let beadOpacity: Double = isHovered ? 1.0 : (isAnyHovered ? 0.45 : 0.85)
        
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
                            AppIconView(bundleId: segment.bundleId, size: 18)
                                .clipShape(Circle())
                                .transition(.opacity.combined(with: .scale(scale: 0.8)))
                        }
                    }
                )
                .frame(width: beadWidth, height: beadHeight)
                .shadow(color: Color.black.opacity(isHovered ? 0.22 : 0.05), radius: isHovered ? 4 : 1, y: isHovered ? 1.5 : 0.5)
        }
        .frame(width: beadWidth, height: 40)
        .opacity(beadOpacity)
        .overlay(
            Group {
                if isHovered {
                    VStack(spacing: 0) {
                        VStack(alignment: .leading, spacing: 0) {
                            // Header
                            HStack(spacing: 8) {
                                AppIconView(bundleId: segment.bundleId, size: 22)
                                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                                    .shadow(color: .black.opacity(0.1), radius: 1, y: 1)
                                
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(segment.appName)
                                        .font(.system(size: 11.5, weight: .bold))
                                        .foregroundStyle(.primary)
                                    
                                    Text(appCategory)
                                        .font(.system(size: 8.5, weight: .medium))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 10)
                            .padding(.top, 9)
                            .padding(.bottom, 7)
                            
                            // Separator line
                            Rectangle()
                                .fill(Color.primary.opacity(0.08))
                                .frame(height: 0.5)
                            
                            // Details
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 0) {
                                    Text("Time Spent: ")
                                        .foregroundStyle(.secondary)
                                    Text(formatDuration(segment.duration))
                                        .foregroundStyle(.primary)
                                        .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                                }
                                .font(.system(size: 9.5))
                                
                                Text("Part of Workflow Context")
                                    .font(.system(size: 9.5))
                                    .foregroundStyle(EchoPalette.indigoSoft)
                                
                                HStack(spacing: 0) {
                                    Text("Focus Contribution: ")
                                        .foregroundStyle(.secondary)
                                    Text(focusContribution)
                                        .foregroundStyle(focusContributionColor)
                                        .font(.system(size: 9.5, weight: .bold))
                                }
                                .font(.system(size: 9.5))
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                        }
                        .frame(width: 195)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(.ultraThinMaterial)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
                        )
                        .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
                        .offset(x: cardXOffset)
                        
                        // Downward Pointer
                        Image(systemName: "arrowtriangle.down.fill")
                            .font(.system(size: 6))
                            .foregroundStyle(Color(NSColor.windowBackgroundColor))
                            .offset(y: -0.5)
                    }
                    .fixedSize()
                    .offset(y: -96)
                    .transition(.opacity.combined(with: .scale(scale: 0.92).combined(with: .offset(y: 6))))
                    .allowsHitTesting(false)
                }
            },
            alignment: .top
        )
    }
}

private struct PulsingTrackOverlay: View {
    let isLive: Bool
    @State private var pulsePhase: Double = 0.0

    var body: some View {
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
                .onAppear {
                    if isLive {
                        withAnimation(.linear(duration: 3.5).repeatForever(autoreverses: false)) {
                            pulsePhase = 1.0
                        }
                    }
                }
        }
        .clipped()
    }
}

private struct ScanningLightOverlay: View {
    let isLive: Bool
    @State private var pulsePhase: Double = 0.0

    var body: some View {
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
                .onAppear {
                    if isLive {
                        withAnimation(.linear(duration: 3.5).repeatForever(autoreverses: false)) {
                            pulsePhase = 1.0
                        }
                    }
                }
        }
        .clipped()
    }
}
