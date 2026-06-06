import SwiftUI
import AppKit

// MARK: - Palette

enum EchoPalette {
    private static func adaptive(
        dark: NSColor,
        light: NSColor
    ) -> Color {
        Color(nsColor: NSColor(name: nil) { app in
            app.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        })
    }
    
    static let graphite = adaptive(
        dark: NSColor(red: 0.04, green: 0.04, blue: 0.04, alpha: 1.0),
        light: NSColor(red: 0.96, green: 0.96, blue: 0.97, alpha: 1.0)
    )
    
    static let sidebar = adaptive(
        dark: NSColor(red: 0.067, green: 0.067, blue: 0.067, alpha: 1.0),
        light: NSColor(red: 0.92, green: 0.92, blue: 0.92, alpha: 1.0)
    )
    
    static let graphiteElevated = adaptive(
        dark: NSColor(red: 0.09, green: 0.09, blue: 0.09, alpha: 1.0),
        light: NSColor(white: 1.0, alpha: 1.0)
    )
    
    static let stroke = adaptive(
        dark: NSColor(red: 0.15, green: 0.15, blue: 0.15, alpha: 1.0),
        light: NSColor(red: 0.88, green: 0.88, blue: 0.90, alpha: 1.0)
    )
    
    static let strokeBright = adaptive(
        dark: NSColor(red: 0.22, green: 0.22, blue: 0.22, alpha: 1.0),
        light: NSColor(red: 0.80, green: 0.80, blue: 0.82, alpha: 1.0)
    )
    
    static let accent = adaptive(
        dark: NSColor(red: 0.89, green: 0.89, blue: 0.91, alpha: 1.0),
        light: NSColor(red: 0.09, green: 0.09, blue: 0.11, alpha: 1.0)
    )
    
    static let indigo = accent
    
    static let vibrantBlue = Color(red: 0.31, green: 0.45, blue: 0.90)
    
    static let indigoSoft = adaptive(
        dark: NSColor(red: 0.63, green: 0.63, blue: 0.67, alpha: 1.0),
        light: NSColor(red: 0.44, green: 0.44, blue: 0.48, alpha: 1.0)
    )
    
    static let warmHighlight = adaptive(
        dark: NSColor(red: 0.72, green: 0.72, blue: 0.75, alpha: 1.0),
        light: NSColor(red: 0.50, green: 0.50, blue: 0.52, alpha: 1.0)
    )
    
    static let live = adaptive(
        dark: NSColor(red: 0.13, green: 0.77, blue: 0.37, alpha: 1.0),
        light: NSColor(red: 0.08, green: 0.50, blue: 0.24, alpha: 1.0)
    )
    
    static let warning = adaptive(
        dark: NSColor(red: 0.96, green: 0.62, blue: 0.04, alpha: 1.0),
        light: NSColor(red: 0.70, green: 0.32, blue: 0.04, alpha: 1.0)
    )
    
    static let destructive = adaptive(
        dark: NSColor(red: 0.94, green: 0.27, blue: 0.27, alpha: 1.0),
        light: NSColor(red: 0.86, green: 0.15, blue: 0.15, alpha: 1.0)
    )
    
    static let glowBlue = adaptive(
        dark: NSColor(white: 0.75, alpha: 1.0),
        light: NSColor(white: 0.20, alpha: 1.0)
    )
    
    static let glowPurple = adaptive(
        dark: NSColor(white: 0.55, alpha: 1.0),
        light: NSColor(white: 0.40, alpha: 1.0)
    )
    
    static var premiumGradient: LinearGradient {
        LinearGradient(
            colors: [accent, indigoSoft],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

enum EchoDesign {

    static let containerRadius: CGFloat = 24
    static let cardCornerRadius: CGFloat = 16
    static let pillRadius: CGFloat = 10
    static let badgeRadius: CGFloat = 6
    static let cornerRadius: CGFloat = cardCornerRadius
    static let sectionSpacing: CGFloat = 16
    static let cardPadding: CGFloat = 18
    static let subtle = Animation.spring(response: 0.26, dampingFraction: 0.76)

    static var ambientBackground: some View {
        EchoPalette.graphite.ignoresSafeArea()
    }

    static var heroWash: LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(0.02),
                Color.clear
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

// MARK: - Card

struct EchoCard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(EchoPalette.graphiteElevated, in: RoundedRectangle(cornerRadius: EchoDesign.cardCornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: EchoDesign.cardCornerRadius, style: .continuous)
                    .strokeBorder(EchoPalette.stroke, lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.12), radius: 6, y: 3)
    }
}

extension View {
    func echoCard(material: Material = .ultraThinMaterial) -> some View {
        modifier(EchoCard())
    }

    func echoAmbientBackground() -> some View {
        background(EchoDesign.ambientBackground)
    }
}

// MARK: - Subtle hover

struct EchoHoverHighlight: ViewModifier {
    var radius: CGFloat = EchoDesign.cardCornerRadius
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Color.primary.opacity(hovering ? 0.04 : 0))
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(
                        EchoPalette.strokeBright.opacity(hovering ? 1 : 0),
                        lineWidth: 0.5
                    )
            )
            .onHover { hovering in
                self.hovering = hovering
                if hovering {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }
    }
}

struct EchoPointingCursor: ViewModifier {
    func body(content: Content) -> some View {
        content
            .onHover { hovering in
                if hovering {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }
    }
}

extension View {
    func echoHoverHighlight() -> some View {
        modifier(EchoHoverHighlight())
    }

    func echoPointingCursor() -> some View {
        modifier(EchoPointingCursor())
    }
}

// MARK: - Live indicator (static — no pulse)

struct EchoLiveDot: View {
    var isActive: Bool

    var body: some View {
        Circle()
            .fill(isActive ? EchoPalette.live : Color.orange.opacity(0.8))
            .frame(width: 6, height: 6)
    }
}

// MARK: - App icon cache

enum AppIconCache {
    private static let cache = NSCache<NSString, NSImage>()

    static func icon(for bundleId: String) -> NSImage? {
        let key = bundleId as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else {
            return nil
        }
        let image = NSWorkspace.shared.icon(forFile: url.path)
        cache.setObject(image, forKey: key)
        return image
    }
}

struct AppIconView: View {
    let bundleId: String
    var size: CGFloat = 36

    var body: some View {
        Group {
            if let image = AppIconCache.icon(for: bundleId) {
                Image(nsImage: image)
                    .resizable()
            } else {
                Image(systemName: "app.fill")
                    .font(.system(size: size * 0.45))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(width: size, height: size)
    }
}
