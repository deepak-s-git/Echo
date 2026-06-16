import SwiftUI

struct FocusIndicatorView: View {
    let score: Double
    let label: String
    var size: CGFloat = 80
    var animate: Bool = true

    @State private var clockwiseRotation: Double = 0
    @State private var counterRotation: Double = 0
    @State private var ripplePhase: Double = 0
    @State private var pulseOpacity: Double = 0.25

    private func rippleScale(index: Int) -> CGFloat {
        let phase = (ripplePhase + Double(index) * 0.33).truncatingRemainder(dividingBy: 1.0)
        return 1.0 + CGFloat(phase * 0.55)
    }

    private func rippleOpacity(index: Int, maxOpacity: Double) -> Double {
        let phase = (ripplePhase + Double(index) * 0.33).truncatingRemainder(dividingBy: 1.0)
        return max(0, 1.0 - phase) * maxOpacity
    }

    var body: some View {
        ZStack {
            // 1. Central Core Breathing Glow
            let glowColor = EchoPalette.accent.opacity(pulseOpacity * (0.3 + 0.7 * score))
            Circle()
                .fill(
                    RadialGradient(
                        colors: [glowColor, .clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: (size - 10) / 2
                    )
                )
                .frame(width: size - 10, height: size - 10)
                .blur(radius: 2)

            // 2. Concentric Ripple Waves (Echo Signal)
            let activeRipples = score > 0.15
            let maxRippleOpacity = activeRipples ? 0.3 * score : 0.0
            
            ForEach(0..<3) { i in
                ZStack {
                    Circle()
                        .stroke(EchoPalette.indigoSoft.opacity(maxRippleOpacity * 0.45), lineWidth: 3)
                        .blur(radius: 1.5)
                    Circle()
                        .stroke(EchoPalette.indigoSoft.opacity(maxRippleOpacity), lineWidth: 0.8)
                }
                .frame(width: size - 10, height: size - 10)
                .scaleEffect(rippleScale(index: i))
                .opacity(rippleOpacity(index: i, maxOpacity: 1.0))
            }

            // 3. Dual Counter-Rotating Orbits
            let isStable = score >= 0.65
            let strokeStyleClockwise = StrokeStyle(
                lineWidth: 2.0,
                lineCap: .round,
                dash: isStable ? [] : [3, 5],
                dashPhase: isStable ? 0 : CGFloat(clockwiseRotation * 0.5)
            )
            let strokeStyleCounter = StrokeStyle(
                lineWidth: 1.2,
                lineCap: .round,
                dash: isStable ? [] : [2, 4],
                dashPhase: isStable ? 0 : CGFloat(counterRotation * 0.3)
            )

            // Outer Orbit Track (Subtle background path)
            Circle()
                .stroke(Color.primary.opacity(0.015), lineWidth: 1.5)
                .frame(width: size + 4, height: size + 4)

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
                .rotationEffect(.degrees(clockwiseRotation))
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
                .rotationEffect(.degrees(counterRotation))
                .frame(width: size + 8, height: size + 8)

            // 4. Preserved Context Flow Particles (Glowing sparks at orbit tips)
            if activeRipples {
                // Spark 1: Clockwise Orbit Tip
                Circle()
                    .fill(EchoPalette.accent)
                    .frame(width: 4, height: 4)
                    .shadow(color: EchoPalette.accent, radius: 2)
                    .offset(y: -(size + 4) / 2)
                    .rotationEffect(.degrees(clockwiseRotation))
                
                // Spark 2: Counter-Clockwise Orbit Tip
                Circle()
                    .fill(EchoPalette.indigoSoft)
                    .frame(width: 3, height: 3)
                    .shadow(color: EchoPalette.indigoSoft, radius: 1.5)
                    .offset(y: -(size + 8) / 2)
                    .rotationEffect(.degrees(counterRotation))
            }

            // 5. Classic Ring Shadow Glow
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

            // 6. Context Progress Ring
            Circle()
                .trim(from: 0, to: CGFloat(score))
                .stroke(
                    EchoPalette.premiumGradient,
                    style: StrokeStyle(lineWidth: 4.5, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .frame(width: size - 10, height: size - 10)

            // 7. Core Value Display
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
        .onAppear {
            if animate {
                startAnimations()
            }
        }
        .onChange(of: animate) { _, newValue in
            if newValue {
                startAnimations()
            } else {
                stopAnimations()
            }
        }
    }

    private func startAnimations() {
        let clockwiseDuration = score > 0.4 ? (6.0 - 3.5 * score) : 8.0
        withAnimation(.linear(duration: clockwiseDuration).repeatForever(autoreverses: false)) {
            clockwiseRotation = 360
        }

        let counterDuration = score > 0.4 ? (8.0 - 4.5 * score) : 11.0
        withAnimation(.linear(duration: counterDuration).repeatForever(autoreverses: false)) {
            counterRotation = -360
        }

        withAnimation(.linear(duration: 3.0).repeatForever(autoreverses: false)) {
            ripplePhase = 1.0
        }

        let pulseDuration = score > 0.5 ? 2.5 : 1.2
        withAnimation(.easeInOut(duration: pulseDuration).repeatForever(autoreverses: true)) {
            pulseOpacity = 0.50
        }
    }

    private func stopAnimations() {
        withAnimation(nil) {
            clockwiseRotation = 0
            counterRotation = 0
            ripplePhase = 0
            pulseOpacity = 0.25
        }
    }
}


