import SwiftUI
import AppKit
import Sparkle

struct AboutPane: View {

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            SettingsPaneHeader(
                icon: "info.circle.fill",
                title: "About",
                subtitle: "Version info, links and acknowledgements",
                color: EchoPalette.indigo
            )

            // MARK: App Identity
            SettingsGroup(label: "App") {
                // Hero
                VStack(spacing: 0) {
                    HStack(spacing: 18) {
                        // App icon placeholder
                        ZStack {
                            RoundedRectangle(cornerRadius: 15, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color(white: 0.14),
                                            Color(white: 0.08)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 60, height: 60)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                                        .strokeBorder(.white.opacity(0.08), lineWidth: 0.5)
                                )
                                .shadow(color: Color.black.opacity(0.35), radius: 6, y: 3)

                            Image("butterfly_logo")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 42, height: 42)
                                .offset(y: 1.0) // Align visual center of gravity
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Echo")
                                .font(.system(size: 22, weight: .bold))
                                .foregroundStyle(.primary)

                            HStack(spacing: 8) {
                                VersionBadge(label: "Version \(appVersion)")
                                VersionBadge(label: "Build \(buildNumber)")
                            }

                            Text("Workflow memory for macOS")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }

                        Spacer()
                    }
                    .padding(20)
                }
            }

            // MARK: Links
            SettingsGroup(label: "Resources") {
                AboutLinkRow(
                    icon: "arrow.up.circle",
                    label: "Check for Updates",
                    description: "You're on the latest version",
                    action: { checkForUpdates() },
                    showDivider: true
                )

                AboutLinkRow(
                    icon: "safari",
                    label: "Visit Website",
                    action: { openURL("https://echo-macos.vercel.app") },
                    showDivider: true
                )

                AboutLinkRow(
                    icon: "lock.doc",
                    label: "Privacy Policy",
                    action: { openURL("https://github.com") },
                    showDivider: true
                )

                AboutLinkRow(
                    icon: "ant",
                    label: "Report a Bug",
                    action: { openURL("https://github.com/deepak-s-git/Echo-Web/issues") },
                    showDivider: false
                )
            }

            // MARK: Acknowledgements
            SettingsGroup(label: "Open Source") {
                AcknowledgementRow(
                    name: "GRDB.swift",
                    description: "A toolkit for SQLite databases",
                    url: "https://github.com/groue/GRDB.swift",
                    showDivider: true
                )
                
                AcknowledgementRow(
                    name: "Sparkle",
                    description: "A software update framework for macOS",
                    url: "https://github.com/sparkle-project/Sparkle",
                    showDivider: false
                )
            }

            // MARK: Copyright
            HStack {
                Spacer()
                Text("© \(currentYear()) Echo. All rights reserved.")
                    .font(.system(size: 11))
                    .foregroundStyle(.quaternary)
                Spacer()
            }
            .padding(.top, 8)
        }
    }

    private func currentYear() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy"
        return formatter.string(from: Date())
    }

    private func openURL(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }

    private func checkForUpdates() {
        print("[Echo] checkForUpdates button clicked!")
        guard let appDelegate = AppDelegate.shared else {
            print("[Echo] Error: AppDelegate.shared is nil.")
            return
        }
        print("[Echo] Found AppDelegate shared instance. updaterController is: \(String(describing: appDelegate.updaterController))")
        if let updaterController = appDelegate.updaterController {
            print("[Echo] Calling updaterController.updater.checkForUpdates()")
            updaterController.updater.checkForUpdates()
        } else {
            print("[Echo] Error: updaterController is nil!")
        }
    }
}

// MARK: - Version Badge

private struct VersionBadge: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .foregroundStyle(EchoPalette.indigoSoft)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(EchoPalette.indigo.opacity(0.10))
            )
    }
}

// MARK: - About Link Row

private struct AboutLinkRow: View {
    let icon: String
    let label: String
    var description: String? = nil
    let action: () -> Void
    var showDivider: Bool = true

    @State private var hovering = false

    var body: some View {
        VStack(spacing: 0) {
            Button(action: action) {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(EchoPalette.indigo.opacity(0.10))
                            .frame(width: 28, height: 28)
                        Image(systemName: icon)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(EchoPalette.indigoSoft)
                    }

                    VStack(alignment: .leading, spacing: 1) {
                        Text(label)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.primary)
                        if let description {
                            Text(description)
                                .font(.system(size: 11))
                                .foregroundStyle(.tertiary)
                        }
                    }

                    Spacer()

                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 11))
                        .foregroundStyle(.quaternary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(hovering ? Color.primary.opacity(0.03) : Color.clear)
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .animation(EchoDesign.subtle, value: hovering)

            if showDivider {
                Rectangle()
                    .fill(EchoPalette.stroke)
                    .frame(height: 0.5)
                    .padding(.leading, 56)
            }
        }
    }
}

// MARK: - Acknowledgement Row

private struct AcknowledgementRow: View {
    let name: String
    let description: String
    let url: String
    var license: String = "MIT"
    var showDivider: Bool = true

    @State private var hovering = false

    var body: some View {
        VStack(spacing: 0) {
            Button {
                if let u = URL(string: url) { NSWorkspace.shared.open(u) }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "chevron.left.forwardslash.chevron.right")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                        .frame(width: 28)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(name)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.primary)
                        Text(description)
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }

                    Spacer()

                    Text(license)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.quaternary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.primary.opacity(0.05)))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(hovering ? Color.primary.opacity(0.03) : Color.clear)
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .animation(EchoDesign.subtle, value: hovering)

            if showDivider {
                Rectangle()
                    .fill(EchoPalette.stroke)
                    .frame(height: 0.5)
                    .padding(.leading, 56)
            }
        }
    }
}
