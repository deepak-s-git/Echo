import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject var appStore: AppStore
    @EnvironmentObject var permissionsManager: PermissionsManager

    @State private var phase = 0
    @State private var visibleLetters = 0
    
    // Wave ripple animations
    @State private var waveScale1: CGFloat = 0.8
    @State private var waveOpacity1: Double = 0.0
    @State private var waveScale2: CGFloat = 0.8
    @State private var waveOpacity2: Double = 0.0
    
    // Subtitle reveal
    @State private var subtitleOffset: CGFloat = 14.0
    @State private var subtitleOpacity: Double = 0.0
    
    // Logo text animations
    @State private var logoTracking: CGFloat = 28
    @State private var logoScale: CGFloat = 0.85
    @State private var logoBlur: CGFloat = 8
    
    // Feature cards (starts lower at 45pt offset)
    @State private var cardOffsets: [CGFloat] = [45.0, 45.0, 45.0]
    @State private var cardOpacities: [Double] = [0.0, 0.0, 0.0]
    
    // Get started button
    @State private var buttonOpacity: Double = 0.0
    @State private var buttonScale: CGFloat = 0.94
    @State private var buttonHovered = false
    

    
    // Cinematic build-up states
    @State private var ringScale: CGFloat = 0.0
    @State private var waveAmplitudeScale: CGFloat = 0.0
    @State private var logoYOffset: CGFloat = 60.0 // Adjusted upward for spacious gap at bottom in center state
    @State private var visualizerScale: CGFloat = 1.7 // Built up in center as huge
    @State private var gridOpacity: Double = 0.0
    @State private var visualizerOpacity: Double = 0.0
    @State private var monogramScale: CGFloat = 0.0
    @State private var monogramOpacity: Double = 0.0
    
    // Unique Robust Palette: Cybernetic Copper, Warm Amber & Champagne Gold
    private let brandCopper = Color(red: 0.85, green: 0.42, blue: 0.18)
    private let brandAmber = Color(red: 0.95, green: 0.65, blue: 0.15)
    private let brandGold = Color(red: 0.82, green: 0.74, blue: 0.55)
    
    private let logoLetters = ["E", "C", "H", "O"]

    var body: some View {
        ZStack {
            // Deep obsidian charcoal background
            Color(red: 0.05, green: 0.05, blue: 0.055)
                .ignoresSafeArea()
            
            // Background dotted grid & interactive constellation (warm gold accents)
            SwiftUI.TimelineView(.animation) { timeline in
                let time = timeline.date.timeIntervalSinceReferenceDate
                
                BackgroundConstellationView(
                    time: time,
                    accentColor: brandGold
                )
                .opacity(gridOpacity)
            }
            .allowsHitTesting(false)
            


            VStack(spacing: 0) {
                Spacer()

                // MARK: - Combined Logo & Text Container (moves from center up)
                VStack(spacing: 0) {
                    // Central Animation Hub (3D Concentric Orbitals & Wave Ribbons)
                    ZStack {
                        SwiftUI.TimelineView(.animation) { timeline in
                            let time = timeline.date.timeIntervalSinceReferenceDate
                            
                            CentralVisualizerCanvas(
                                time: time,
                                ringScale: ringScale,
                                waveAmplitudeScale: waveAmplitudeScale,
                                visualizerOpacity: visualizerOpacity,
                                copper: brandCopper,
                                amber: brandAmber,
                                gold: brandGold
                            )
                        }
                        .frame(width: 380, height: 220)

                        // Elegant E-Wave Monogram Logo (builds first)
                        MonogramView(copper: brandCopper, amber: brandAmber, gold: brandGold)
                            .scaleEffect(monogramScale)
                            .opacity(monogramOpacity)
                            .shadow(color: brandAmber.opacity(0.35 * monogramOpacity), radius: 10, y: 2)
                    }
                    .frame(height: 230)
                    .scaleEffect(visualizerScale) // Dynamic scale (Stage 1/2: 1.7, Stage 3/4: 1.0)

                    // Logo Text & Subtitle
                    VStack(spacing: 12) {
                        HStack(spacing: logoTracking) {
                            ForEach(0..<logoLetters.count, id: \.self) { idx in
                                Text(logoLetters[idx])
                                    .font(.system(size: 36, weight: .bold, design: .rounded))
                                    .foregroundStyle(
                                        LinearGradient(
                                            colors: [.white, Color(white: 0.85)],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                    )
                                    .shadow(color: brandCopper.opacity(0.25), radius: 6, y: 1.5)
                                    .opacity(idx < visibleLetters ? 1.0 : 0.0)
                                    .scaleEffect(idx < visibleLetters ? 1.0 : 0.75)
                                    .blur(radius: idx < visibleLetters ? 0 : 3)
                            }
                        }
                        .frame(height: 42)
                        .scaleEffect(logoScale)
                        .blur(radius: logoBlur)
                        
                        Text("Recall and continue your working context instantly.")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                            .opacity(subtitleOpacity)
                            .offset(y: subtitleOffset)
                    }
                    .padding(.top, (visualizerScale - 1.0) * 75.0 + 8.0)
                }
                .offset(y: logoYOffset)

                // Spacer between Logo and Cards (Static height to prevent layout jumps)
                Spacer()
                    .frame(height: 24)

                // MARK: - Translucent 3D Hover Feature Cards (Static height bounds)
                HStack(spacing: 18) {
                    FeatureCardView(
                        icon: "cursorarrow.click.2",
                        title: "Capture",
                        description: "Indexes your workspaces, browser logs, and open documents automatically.",
                        glowColor: brandCopper
                    )
                    .opacity(cardOpacities[0])
                    .offset(y: cardOffsets[0])

                    FeatureCardView(
                        icon: "waveform.path",
                        title: "Flow State",
                        description: "Evaluates your attention integrity and visualizes focus rhythm locally.",
                        glowColor: brandAmber
                    )
                    .opacity(cardOpacities[1])
                    .offset(y: cardOffsets[1])

                    FeatureCardView(
                        icon: "arrow.uturn.backward.circle.fill",
                        title: "Resume",
                        description: "Restores your exact workspace and window arrangement in one tap.",
                        glowColor: brandGold
                    )
                    .opacity(cardOpacities[2])
                    .offset(y: cardOffsets[2])
                }
                .padding(.horizontal, 48)
                .frame(height: 124)
                .clipped()

                Spacer()

                // MARK: - Action Button
                Button {
                    if !permissionsManager.allGranted {
                        permissionsManager.requestAccessibility()
                    }
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                        appStore.completeOnboarding()
                    }
                } label: {
                    Text("Get Started")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 240)
                        .padding(.vertical, 12)
                        .background(
                            LinearGradient(
                                colors: [
                                    brandCopper,
                                    brandAmber
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(.white.opacity(0.24), lineWidth: 0.5)
                        )
                        .shadow(color: brandCopper.opacity(buttonHovered ? 0.38 : 0.16), radius: buttonHovered ? 14 : 7, y: 3)
                }
                .buttonStyle(.plain)
                .opacity(buttonOpacity)
                .scaleEffect(buttonScale)
                .onHover { hovering in
                    withAnimation(.spring(response: 0.24, dampingFraction: 0.75)) {
                        buttonHovered = hovering
                        buttonScale = hovering ? 1.03 : 1.0
                    }
                }
                .padding(.bottom, 42)
            }
        }

        .onAppear {
            startAnimationTimeline()
        }
    }

    private func startAnimationTimeline() {
        // Stage 1: Grid fade-in & core visualizer build-up (HUGE at center)
        withAnimation(.easeIn(duration: 0.8)) {
            gridOpacity = 1.0
        }
        
        // Monogram pop-in
        withAnimation(.spring(response: 0.85, dampingFraction: 0.65)) {
            monogramScale = 1.0
            monogramOpacity = 1.0
        }
        
        // Concentric rings expand outward from monogram
        withAnimation(.spring(response: 1.3, dampingFraction: 0.75)) {
            ringScale = 1.0
            visualizerOpacity = 1.0
        }
        
        // Wave amplitude builds up
        withAnimation(.easeOut(duration: 1.4)) {
            waveAmplitudeScale = 1.0
        }

        // Stage 2: Letter-by-letter reveal (staged at t = 1.3s for fluid timing)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) {
            phase = 2
            
            // Staggered letters
            for i in 0..<logoLetters.count {
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.12) {
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.65)) {
                        visibleLetters += 1
                    }
                }
            }
            
            // Compress tracking and fade blur
            withAnimation(.spring(response: 1.15, dampingFraction: 0.72)) {
                logoTracking = 10
                logoScale = 1.0
                logoBlur = 0
            }
            
            // Reveal subtitle
            withAnimation(.spring(response: 0.85, dampingFraction: 0.78)) {
                subtitleOpacity = 1.0
                subtitleOffset = 0
            }
        }

        // Stage 3: Minimize (1.7 -> 1.0) & Slide up (60 -> 0) (at t = 2.6s for buttery overlapping feel)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) {
            phase = 3
            withAnimation(.spring(response: 1.05, dampingFraction: 0.84)) {
                visualizerScale = 1.0
                logoYOffset = 0
            }
        }

        // Stage 4: Cards slide-in (at t = 2.9s, overlapping with logo slide-up)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.9) {
            phase = 4
            for i in 0..<3 {
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.15) {
                    withAnimation(.spring(response: 0.75, dampingFraction: 0.76)) {
                        cardOpacities[i] = 1.0
                        cardOffsets[i] = 0
                    }
                }
            }
        }

        // Stage 5: Get Started Button fade-in (at t = 3.6s, immediately following cards)
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.6) {
            withAnimation(.spring(response: 0.65, dampingFraction: 0.76)) {
                buttonOpacity = 1.0
                buttonScale = 1.0
            }
        }
    }
}

// MARK: - Background Blueprint Dotted Grid & Constellation Canvas

struct BackgroundConstellationView: View {
    let time: Double
    let accentColor: Color
    
    var body: some View {
        Canvas { context, size in
            let width = size.width
            let height = size.height
            
            // 1. Dotted grid
            let gridSpacing: CGFloat = 28
            let gridColor = Color.white.opacity(0.012)
            
            for x in stride(from: CGFloat(0), to: width + gridSpacing, by: gridSpacing) {
                for y in stride(from: CGFloat(0), to: height + gridSpacing, by: gridSpacing) {
                    context.fill(
                        Path(ellipseIn: CGRect(x: x - 0.75, y: y - 0.75, width: 1.5, height: 1.5)),
                        with: .color(gridColor)
                    )
                }
            }
            
            // 2. Deterministic floating particles (warm tint)
            let particleCount = 38
            var particles: [CGPoint] = []
            
            for i in 0..<particleCount {
                let seedX = sin(Double(i) * 1482.13) * 43758.54
                let seedY = cos(Double(i) * 9128.45) * 23456.78
                let fractX = seedX - floor(seedX)
                let fractY = seedY - floor(seedY)
                
                let bx = CGFloat(fractX) * width
                let by = CGFloat(fractY) * height
                
                let driftSpeedX = sin(Double(i) * 0.3) * 0.2
                let driftSpeedY = cos(Double(i) * 0.25) * 0.25
                let px = bx + CGFloat(sin(time * driftSpeedX + Double(i))) * 20
                let py = by + CGFloat(cos(time * driftSpeedY + Double(i * 2))) * 16
                
                particles.append(CGPoint(x: px, y: py))
            }
            
            // 3. Connect nodes
            for i in 0..<particleCount {
                let pi = particles[i]
                for j in (i+1)..<particleCount {
                    let pj = particles[j]
                    let dx = pi.x - pj.x
                    let dy = pi.y - pj.y
                    let dist = sqrt(dx*dx + dy*dy)
                    if dist < 68 {
                        let alpha = (1.0 - dist / 68) * 0.08
                        context.stroke(
                            Path { path in
                                path.move(to: pi)
                                path.addLine(to: pj)
                            },
                            with: .color(accentColor.opacity(alpha)),
                            lineWidth: 0.5
                        )
                    }
                }
            }
            
            // 4. Render nodes
            for i in 0..<particleCount {
                let pt = particles[i]
                let sizeVal: CGFloat = 1.2 + CGFloat(sin(time * 0.8 + Double(i)) * 0.5 + 0.5) * 1.5
                let opacity = 0.12 + sin(time * 0.5 + Double(i)) * 0.08
                
                context.fill(
                    Path(ellipseIn: CGRect(x: pt.x - sizeVal/2, y: pt.y - sizeVal/2, width: sizeVal, height: sizeVal)),
                    with: .color(accentColor.opacity(opacity))
                )
            }
        }
    }
}

// MARK: - Central Visualizer Canvas

private struct CentralVisualizerCanvas: View {
    let time: Double
    let ringScale: CGFloat
    let waveAmplitudeScale: CGFloat
    let visualizerOpacity: Double
    
    // Custom Brand Colors
    let copper: Color
    let amber: Color
    let gold: Color
    
    private func project(
        x: CGFloat,
        y: CGFloat,
        z: CGFloat,
        rotX: Double,
        rotY: Double,
        center: CGPoint
    ) -> CGPoint {
        // Rotate around X-axis
        let cosX = cos(rotX)
        let sinX = sin(rotX)
        let x1 = x
        let y1 = y * cosX - z * sinX
        let z1 = y * sinX + z * cosX
        
        // Rotate around Y-axis
        let cosY = cos(rotY)
        let sinY = sin(rotY)
        let x2 = x1 * cosY + z1 * sinY
        let y2 = y1
        
        return CGPoint(x: center.x + x2, y: center.y + y2)
    }

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            
            // Rings expand dynamically outwards
            let ringConfigs = [
                (radius: CGFloat(52), rotX: 0.65, rotY: 0.35, spin: 1.1, color: copper),
                (radius: CGFloat(74), rotX: -0.45, rotY: 0.60, spin: -0.8, color: amber),
                (radius: CGFloat(96), rotX: 0.80, rotY: -0.25, spin: 1.4, color: gold)
            ]
            
            for config in ringConfigs {
                let currentRadius = config.radius * ringScale
                
                // Ring stroke
                var ringPath = Path()
                let steps = 90
                for i in 0...steps {
                    let angle = Double(i) * 2.0 * .pi / Double(steps)
                    let pt = project(
                        x: currentRadius * cos(angle),
                        y: currentRadius * sin(angle),
                        z: 0,
                        rotX: config.rotX,
                        rotY: config.rotY,
                        center: center
                    )
                    if i == 0 {
                        ringPath.move(to: pt)
                    } else {
                        ringPath.addLine(to: pt)
                    }
                }
                
                context.stroke(
                    ringPath,
                    with: .color(config.color.opacity(0.18 * visualizerOpacity)),
                    lineWidth: 0.75
                )
                
                // Orbiting beads
                let headPt = project(
                    x: currentRadius * cos(config.spin * time),
                    y: currentRadius * sin(config.spin * time),
                    z: 0,
                    rotX: config.rotX,
                    rotY: config.rotY,
                    center: center
                )
                
                let trailLength = 16
                for j in 0..<trailLength {
                    let tailTime = time - Double(j) * 0.022 * (config.spin > 0 ? 1.0 : -1.0)
                    let tAngle = config.spin * tailTime
                    let tailPt = project(
                        x: currentRadius * cos(tAngle),
                        y: currentRadius * sin(tAngle),
                        z: 0,
                        rotX: config.rotX,
                        rotY: config.rotY,
                        center: center
                    )
                    
                    let trailOpacity = (1.0 - Double(j) / Double(trailLength)) * 0.5 * visualizerOpacity
                    let trailRadius = (1.0 - Double(j) / Double(trailLength)) * 3.5 + 0.5
                    
                    context.fill(
                        Path(ellipseIn: CGRect(x: tailPt.x - trailRadius/2, y: tailPt.y - trailRadius/2, width: trailRadius, height: trailRadius)),
                        with: .color(config.color.opacity(trailOpacity))
                    )
                }
                
                // Glowing Head
                context.fill(
                    Path(ellipseIn: CGRect(x: headPt.x - 3.2, y: headPt.y - 3.2, width: 6.4, height: 6.4)),
                    with: .color(.white.opacity(visualizerOpacity))
                )
                context.fill(
                    Path(ellipseIn: CGRect(x: headPt.x - 5.5, y: headPt.y - 5.5, width: 11, height: 11)),
                    with: .color(config.color.opacity(0.35 * visualizerOpacity))
                )
            }
            
            // Soundwave analyzer
            let waveY = center.y + 72
            let waveConfigs = [
                (freq: 3.4, amp: 14.0 * waveAmplitudeScale, speed: 2.3, color: copper.opacity(0.35 * visualizerOpacity), width: CGFloat(1.2)),
                (freq: 4.2, amp: 9.0 * waveAmplitudeScale, speed: -1.8, color: amber.opacity(0.28 * visualizerOpacity), width: CGFloat(0.9)),
                (freq: 2.6, amp: 7.0 * waveAmplitudeScale, speed: 1.4, color: gold.opacity(0.40 * visualizerOpacity), width: CGFloat(1.5))
            ]
            
            for wConfig in waveConfigs {
                var wPath = Path()
                let startX = CGFloat(30)
                let endX = size.width - 30
                let length = endX - startX
                
                wPath.move(to: CGPoint(x: startX, y: waveY))
                
                for x in stride(from: Int(startX), to: Int(endX), by: 4) {
                    let relX = (CGFloat(x) - startX) / length
                    let envelope = sin(relX * .pi)
                    
                    let t = time * wConfig.speed
                    let sine1 = sin(relX * .pi * wConfig.freq + t)
                    let sine2 = cos(relX * .pi * (wConfig.freq * 1.6) - t * 0.7)
                    
                    let y = waveY + (sine1 + sine2 * 0.5) * wConfig.amp * envelope
                    wPath.addLine(to: CGPoint(x: CGFloat(x), y: y))
                }
                
                context.stroke(
                    wPath,
                    with: .color(wConfig.color),
                    lineWidth: wConfig.width
                )
            }
        }
    }
}

// MARK: - Wave-Emitter E-Monogram

private struct MonogramView: View {
    @State private var isBreathing = false
    
    // Custom Brand Colors
    let copper: Color
    let amber: Color
    let gold: Color
    
    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            amber.opacity(0.28),
                            .clear
                        ],
                        center: .center,
                        startRadius: 2,
                        endRadius: 36
                    )
                )
                .frame(width: 72, height: 72)
                .scaleEffect(isBreathing ? 1.14 : 0.96)
                .animation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true), value: isBreathing)
            
            ZStack {
                Arc(startAngle: .degrees(-135), endAngle: .degrees(135), clockwise: false)
                    .stroke(
                        LinearGradient(
                            colors: [.white, gold.opacity(0.5)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        style: StrokeStyle(lineWidth: 2.6, lineCap: .round)
                    )
                    .frame(width: 32, height: 32)
                
                Arc(startAngle: .degrees(-120), endAngle: .degrees(120), clockwise: false)
                    .stroke(
                        LinearGradient(
                            colors: [.white, amber],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        style: StrokeStyle(lineWidth: 2.0, lineCap: .round)
                    )
                    .frame(width: 22, height: 22)
                
                Arc(startAngle: .degrees(-95), endAngle: .degrees(95), clockwise: false)
                    .stroke(
                        LinearGradient(
                            colors: [.white, copper],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        style: StrokeStyle(lineWidth: 1.6, lineCap: .round)
                    )
                    .frame(width: 12, height: 12)
                
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.white)
                    .frame(width: 8, height: 2.2)
                    .offset(x: 3.5)
            }
            .scaleEffect(isBreathing ? 1.04 : 0.98)
            .animation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true), value: isBreathing)
        }
        .onAppear {
            isBreathing = true
        }
    }
}

private struct Arc: Shape {
    let startAngle: Angle
    let endAngle: Angle
    let clockwise: Bool
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addArc(
            center: CGPoint(x: rect.midX, y: rect.midY),
            radius: rect.width / 2,
            startAngle: startAngle - .degrees(90),
            endAngle: endAngle - .degrees(90),
            clockwise: clockwise
        )
        return path
    }
}

// MARK: - Glassmorphic 3D Feature Card

private struct FeatureCardView: View {
    let icon: String
    let title: String
    let description: String
    let glowColor: Color
    
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(glowColor.opacity(0.12))
                        .frame(width: 22, height: 22)
                    
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(glowColor)
                }
                
                Text(title)
                    .font(.system(size: 12.5, weight: .bold))
                    .foregroundStyle(.white)
            }
            
            Text(description)
                .font(.system(size: 10))
                .lineSpacing(3.5)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.015))
                .background(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(isHovered ? glowColor.opacity(0.32) : .white.opacity(0.06), lineWidth: 0.5)
        )
        .scaleEffect(isHovered ? 1.025 : 1.0)
        .shadow(color: isHovered ? glowColor.opacity(0.18) : Color.clear, radius: 12, y: 4)
        .onHover { hovering in
            withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                isHovered = hovering
            }
        }
    }
}
