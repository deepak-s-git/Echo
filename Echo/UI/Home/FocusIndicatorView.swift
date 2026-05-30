import SwiftUI

struct FocusIndicatorView: View {
    let score: Double
    let label: String

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.06), lineWidth: 8)

            Circle()
                .trim(from: 0, to: score)
                .stroke(
                    EchoPalette.premiumGradient,
                    style: StrokeStyle(lineWidth: 8, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            VStack(spacing: 2) {
                Text("\(Int(score * 100))")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text(label)
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 60)
            }
        }
        .frame(width: 80, height: 80)
        .animation(EchoDesign.subtle, value: score)
    }
}
