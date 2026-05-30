import SwiftUI
import AppKit

// MARK: - Palette

enum EchoPalette {
    static let graphite = Color(red: 0.04, green: 0.04, blue: 0.04)          // #0A0A0A - Midnight Base
    static let sidebar = Color(red: 0.067, green: 0.067, blue: 0.067)        // #111111 - Sidebar
    static let graphiteElevated = Color(red: 0.09, green: 0.09, blue: 0.09) // #171717 - Cards/Panels
    static let stroke = Color(red: 0.15, green: 0.15, blue: 0.15)            // #262626 - Borders/Dividers
    static let strokeBright = Color(red: 0.22, green: 0.22, blue: 0.22)      // Active borders
    
    static let accent = Color(red: 0.89, green: 0.89, blue: 0.91)            // #E4E4E7 - Muted Primary Text
    static let indigo = accent                                                // Mapping active accent
    static let indigoSoft = Color(red: 0.63, green: 0.63, blue: 0.67)        // #A1A1AA - Secondary Zinc
    static let warmHighlight = Color(red: 0.72, green: 0.72, blue: 0.75)     // Muted neutral gray
    
    static let live = Color(red: 0.13, green: 0.77, blue: 0.37)              // #22C55E - Success
    static let warning = Color(red: 0.96, green: 0.62, blue: 0.04)           // #F59E0B - Warning
    static let destructive = Color(red: 0.94, green: 0.27, blue: 0.27)       // #EF4444 - Error
    
    static let glowBlue = Color(white: 0.75)
    static let glowPurple = Color(white: 0.55)
    
    static var premiumGradient: LinearGradient {
        LinearGradient(
            colors: [Color(white: 0.88), Color(white: 0.63)],
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
