import SwiftUI

struct FocusIndicatorView: View {
    let score: Double
    let label: String
    var size: CGFloat = 80
    var animate: Bool = true

    var body: some View {
        ZStack {
            // 1. Central Core Breathing Glow (Isolated animation layer)
            BreathingCoreGlow(size: size, score: score, animate: animate)

            // 2. Concentric Ripple Waves (Isolated staggered animation layers)
            let activeRipples = score > 0.15
            let maxRippleOpacity = activeRipples ? 0.3 * score : 0.0
            
            ForEach(0..<3) { i in
                ConcentricRippleView(index: i, size: size, maxOpacity: maxRippleOpacity, animate: animate)
            }

            // 3. Dual Counter-Rotating Orbits & Sparks (Isolated animation layer)
            RotatingOrbits(score: score, size: size, animate: animate)

            // 4. Classic Ring Shadow Glow (Static backdrop)
            Circle()
                .stroke(
                    EchoPalette.premiumGradient.opacity(0.12 + 0.18 * score),
                    lineWidth: 3.5
                )
                .frame(width: size - 10, height: size - 10)
                .blur(radius: 1.5)

            // Background Ring Track
            Circle()
                .stroke(Color.primary.opacity(0.035), lineWidth: 4.5)
                .frame(width: size - 10, height: size - 10)

            // 5. Context Progress Ring (Static trim representation of focus score)
            Circle()
                .trim(from: 0, to: CGFloat(score))
                .stroke(
                    EchoPalette.premiumGradient,
                    style: StrokeStyle(lineWidth: 4.5, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .frame(width: size - 10, height: size - 10)

            // 6. Core Value Display (Static text metrics)
            VStack(spacing: 0) {
                Text("\(Int(score * 100))")
                    .font(.system(size: size * 0.23, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                
                if !label.isEmpty {
                    Text(label)
                        .font(.system(size: size * 0.085, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: size - 18)
                }
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Isolated GPU-Accelerated Animation Subviews

private struct BreathingCoreGlow: View {
    let size: CGFloat
    let score: Double
    let animate: Bool
    
    @State private var scale: CGFloat = 0.95
    @State private var opacity: Double = 0.5
    
    var body: some View {
        let baseGlowColor = EchoPalette.accent.opacity(0.35 * (0.3 + 0.7 * score))
        Circle()
            .fill(
                RadialGradient(
                    colors: [baseGlowColor, .clear],
                    center: .center,
                    startRadius: 0,
                    endRadius: (size - 10) / 2
                )
            )
            .frame(width: size - 10, height: size - 10)
            .blur(radius: 2)
            .scaleEffect(scale)
            .opacity(opacity)
            .onAppear {
                if animate {
                    let pulseDuration = score > 0.5 ? 2.5 : 1.2
                    withAnimation(.easeInOut(duration: pulseDuration).repeatForever(autoreverses: true)) {
                        scale = 1.05
                        opacity = 0.8
                    }
                }
            }
    }
}

private struct ConcentricRippleView: View {
    let index: Int
    let size: CGFloat
    let maxOpacity: Double
    let animate: Bool
    
    @State private var scale: CGFloat = 1.0
    @State private var opacity: Double = 0.0
    
    var body: some View {
        ZStack {
            Circle()
                .stroke(EchoPalette.indigoSoft.opacity(opacity * 0.45), lineWidth: 3)
                .blur(radius: 1.5)
            Circle()
                .stroke(EchoPalette.indigoSoft.opacity(opacity), lineWidth: 0.8)
        }
        .frame(width: size - 10, height: size - 10)
        .scaleEffect(scale)
        .opacity(opacity)
        .onAppear {
            if animate && maxOpacity > 0.01 {
                startAnimation()
            }
        }
        .onChange(of: animate) { _, newValue in
            if newValue && maxOpacity > 0.01 {
                startAnimation()
            } else {
                scale = 1.0
                opacity = 0.0
            }
        }
    }
    
    private func startAnimation() {
        // Reset state values
        scale = 1.0
        opacity = maxOpacity
        
        let delay = Double(index) * 1.0 // Stagger ripple waves
        
        withAnimation(
            .linear(duration: 3.0)
            .repeatForever(autoreverses: false)
            .delay(delay)
        ) {
            scale = 1.55
            opacity = 0.0
        }
    }
}

private struct RotatingOrbits: View {
    let score: Double
    let size: CGFloat
    let animate: Bool
    
    @State private var rotation: Double = 0.0
    
    var body: some View {
        let activeRipples = score > 0.15
        let isStable = score >= 0.65
        let strokeStyleClockwise = StrokeStyle(
            lineWidth: 2.0,
            lineCap: .round,
            dash: isStable ? [] : [3, 5],
            dashPhase: 0
        )
        let strokeStyleCounter = StrokeStyle(
            lineWidth: 1.2,
            lineCap: .round,
            dash: isStable ? [] : [2, 4],
            dashPhase: 0
        )
        
        ZStack {
            // Clockwise Orbit (Main Accent Flow)
            Circle()
                .trim(from: 0, to: CGFloat(0.12 + 0.10 * score))
                .stroke(
                    LinearGradient(
                        colors: [EchoPalette.accent, EchoPalette.accent.opacity(0.0)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    style: strokeStyleClockwise
                )
                .rotationEffect(.degrees(rotation))
                .frame(width: size + 4, height: size + 4)
            
            // Counter-Clockwise Orbit (Secondary Indigo Flow)
            Circle()
                .trim(from: 0, to: CGFloat(0.08 + 0.08 * score))
                .stroke(
                    LinearGradient(
                        colors: [EchoPalette.indigoSoft, EchoPalette.indigoSoft.opacity(0.0)],
                        startPoint: .bottomTrailing,
                        endPoint: .topLeading
                    ),
                    style: strokeStyleCounter
                )
                .rotationEffect(.degrees(-rotation * 0.75))
                .frame(width: size + 8, height: size + 8)
            
            if activeRipples {
                // Spark 1: Clockwise Orbit Tip
                Circle()
                    .fill(EchoPalette.accent)
                    .frame(width: 4, height: 4)
                    .shadow(color: EchoPalette.accent, radius: 2)
                    .offset(y: -(size + 4) / 2)
                    .rotationEffect(.degrees(rotation))
                
                // Spark 2: Counter-Clockwise Orbit Tip
                Circle()
                    .fill(EchoPalette.indigoSoft)
                    .frame(width: 3, height: 3)
                    .shadow(color: EchoPalette.indigoSoft, radius: 1.5)
                    .offset(y: -(size + 8) / 2)
                    .rotationEffect(.degrees(-rotation * 0.75))
            }
        }
        .onAppear {
            if animate {
                let clockwiseDuration = score > 0.4 ? (6.0 - 3.5 * score) : 8.0
                withAnimation(.linear(duration: clockwiseDuration).repeatForever(autoreverses: false)) {
                    rotation = 360
                }
            }
        }
    }
}


