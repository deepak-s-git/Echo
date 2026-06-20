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
        dark: NSColor(red: 0.045, green: 0.045, blue: 0.05, alpha: 1.0),
        light: NSColor(red: 0.96, green: 0.96, blue: 0.97, alpha: 1.0)
    )
    
    static let sidebar = adaptive(
        dark: NSColor(red: 0.06, green: 0.06, blue: 0.065, alpha: 1.0),
        light: NSColor(red: 0.92, green: 0.92, blue: 0.93, alpha: 1.0)
    )
    
    static let graphiteElevated = adaptive(
        dark: NSColor(red: 0.09, green: 0.09, blue: 0.10, alpha: 1.0),
        light: NSColor(white: 1.0, alpha: 1.0)
    )
    
    static let stroke = adaptive(
        dark: NSColor(red: 0.18, green: 0.15, blue: 0.13, alpha: 1.0),
        light: NSColor(red: 0.86, green: 0.85, blue: 0.83, alpha: 1.0)
    )
    
    static let strokeBright = adaptive(
        dark: NSColor(red: 0.28, green: 0.23, blue: 0.19, alpha: 1.0),
        light: NSColor(red: 0.76, green: 0.74, blue: 0.70, alpha: 1.0)
    )
    
    static let accent = adaptive(
        dark: NSColor(red: 0.85, green: 0.42, blue: 0.18, alpha: 1.0), // Cybernetic Copper
        light: NSColor(red: 0.75, green: 0.32, blue: 0.08, alpha: 1.0)
    )
    
    static let indigo = accent
    
    static let indigoSoft = adaptive(
        dark: NSColor(red: 0.82, green: 0.74, blue: 0.55, alpha: 1.0), // Champagne Gold
        light: NSColor(red: 0.65, green: 0.57, blue: 0.38, alpha: 1.0)
    )
    
    static let warmHighlight = adaptive(
        dark: NSColor(red: 0.95, green: 0.65, blue: 0.15, alpha: 1.0), // Warm Amber
        light: NSColor(red: 0.80, green: 0.50, blue: 0.05, alpha: 1.0)
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
    
    static let glowBlue = accent
    
    static let glowPurple = indigoSoft
    
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
    var material: Material? = nil
    
    func body(content: Content) -> some View {
        if let material = material {
            content
                .background(material, in: RoundedRectangle(cornerRadius: EchoDesign.cardCornerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: EchoDesign.cardCornerRadius, style: .continuous)
                        .strokeBorder(EchoPalette.stroke, lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.12), radius: 6, y: 3)
        } else {
            content
                .background(EchoPalette.graphiteElevated, in: RoundedRectangle(cornerRadius: EchoDesign.cardCornerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: EchoDesign.cardCornerRadius, style: .continuous)
                        .strokeBorder(EchoPalette.stroke, lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.12), radius: 6, y: 3)
        }
    }
}

extension View {
    func echoCard(material: Material? = nil) -> some View {
        modifier(EchoCard(material: material))
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
extension View {
    func echoHoverHighlight() -> some View {
        modifier(EchoHoverHighlight())
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
    private static let cache = NSCache<NSString, AnyObject>()
    private static let failureSentinel = NSObject()

    static func cachedIcon(for bundleId: String) -> NSImage? {
        let key = bundleId as NSString
        if let cached = cache.object(forKey: key) {
            if cached === failureSentinel { return nil }
            return cached as? NSImage
        }
        return nil
    }

    static func loadIcon(for bundleId: String) async -> NSImage? {
        let key = bundleId as NSString
        
        if let cached = cache.object(forKey: key) {
            if cached === failureSentinel { return nil }
            return cached as? NSImage
        }

        let appUrl = await MainActor.run {
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId)
        }
        
        guard let url = appUrl else {
            cache.setObject(failureSentinel, forKey: key)
            return nil
        }
        
        let image = await MainActor.run {
            NSWorkspace.shared.icon(forFile: url.path)
        }
        
        cache.setObject(image, forKey: key)
        return image
    }
}

struct AppIconView: View {
    let bundleId: String
    var size: CGFloat = 36
    @State private var iconImage: NSImage?

    init(bundleId: String, size: CGFloat = 36) {
        self.bundleId = bundleId
        self.size = size
        self._iconImage = State(initialValue: AppIconCache.cachedIcon(for: bundleId))
    }

    var body: some View {
        Group {
            if let image = iconImage {
                Image(nsImage: image)
                    .resizable()
            } else {
                Image(systemName: "app.fill")
                    .font(.system(size: size * 0.45))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(width: size, height: size)
        .task(id: bundleId) {
            if let cached = AppIconCache.cachedIcon(for: bundleId) {
                self.iconImage = cached
                return
            }
            let image = await AppIconCache.loadIcon(for: bundleId)
            if !Task.isCancelled {
                self.iconImage = image
            }
        }
    }
}

extension WorkflowCluster {
    var colors: [Color] {
        switch self {
        case .coding:
            return [Color(red: 0.25, green: 0.35, blue: 0.95), Color(red: 0.15, green: 0.55, blue: 0.90)]
        case .research:
            return [Color(red: 0.12, green: 0.63, blue: 0.63), Color(red: 0.08, green: 0.55, blue: 0.40)]
        case .writing:
            return [Color(red: 0.95, green: 0.60, blue: 0.10), Color(red: 0.90, green: 0.45, blue: 0.08)]
        case .design:
            return [Color(red: 0.95, green: 0.25, blue: 0.55), Color(red: 0.90, green: 0.20, blue: 0.35)]
        case .communication:
            return [Color(red: 0.60, green: 0.30, blue: 0.95), Color(red: 0.45, green: 0.20, blue: 0.85)]
        case .mixed:
            return [Color(red: 0.45, green: 0.50, blue: 0.60), Color(red: 0.30, green: 0.35, blue: 0.45)]
        }
    }
}

