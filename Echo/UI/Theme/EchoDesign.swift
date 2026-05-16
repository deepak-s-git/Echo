import SwiftUI
import AppKit

// MARK: - Palette

enum EchoPalette {
    static let graphite = Color(red: 0.11, green: 0.11, blue: 0.12)
    static let graphiteElevated = Color(red: 0.15, green: 0.15, blue: 0.16)
    static let indigo = Color(red: 0.38, green: 0.40, blue: 0.52)
    static let indigoSoft = Color(red: 0.48, green: 0.50, blue: 0.60)
    static let warmHighlight = Color(red: 0.72, green: 0.64, blue: 0.54)
    static let live = Color(red: 0.45, green: 0.62, blue: 0.48)
    static let stroke = Color.white.opacity(0.08)
    static let strokeBright = Color.white.opacity(0.12)
}

enum EchoDesign {

    static let cornerRadius: CGFloat = 14
    static let cardCornerRadius: CGFloat = 18
    static let subtle = Animation.easeOut(duration: 0.22)

    static var ambientBackground: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            LinearGradient(
                colors: [
                    EchoPalette.graphite.opacity(0.35),
                    Color.clear,
                    EchoPalette.indigo.opacity(0.06)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    static var heroWash: LinearGradient {
        LinearGradient(
            colors: [
                EchoPalette.indigo.opacity(0.14),
                EchoPalette.warmHighlight.opacity(0.05),
                Color.clear
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

// MARK: - Card

struct EchoCard: ViewModifier {
    var material: Material = .ultraThinMaterial

    func body(content: Content) -> some View {
        content
            .background(material, in: RoundedRectangle(cornerRadius: EchoDesign.cardCornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: EchoDesign.cardCornerRadius, style: .continuous)
                    .strokeBorder(EchoPalette.stroke, lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
    }
}

extension View {
    func echoCard(material: Material = .ultraThinMaterial) -> some View {
        modifier(EchoCard(material: material))
    }

    func echoAmbientBackground() -> some View {
        background(EchoDesign.ambientBackground)
    }
}

// MARK: - Subtle hover

struct EchoHoverHighlight: ViewModifier {
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: EchoDesign.cardCornerRadius, style: .continuous)
                    .fill(Color.primary.opacity(hovering ? 0.03 : 0))
            )
            .onHover { hovering = $0 }
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
