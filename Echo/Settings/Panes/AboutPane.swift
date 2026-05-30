import SwiftUI

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
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            EchoPalette.indigo,
                                            EchoPalette.indigoSoft.opacity(0.7)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 60, height: 60)
                                .shadow(color: EchoPalette.indigo.opacity(0.3), radius: 10, y: 4)

                            // Echo logo glyph
                            ZStack {
                                Circle()
                                    .fill(.white.opacity(0.15))
                                    .frame(width: 36, height: 36)
                                Circle()
                                    .fill(.white.opacity(0.9))
                                    .frame(width: 10, height: 10)
                            }
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
                    action: { openURL("https://github.com") },
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
                    action: { openURL("https://github.com") },
                    showDivider: false
                )
            }

            // MARK: Acknowledgements
            SettingsGroup(label: "Open Source") {
                AcknowledgementRow(
                    name: "GRDB.swift",
                    description: "A toolkit for SQLite databases",
                    url: "https://github.com/groue/GRDB.swift",
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
        // Stub — would integrate Sparkle or a custom update mechanism
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
            .echoPointingCursor()
            .onHover { hovering = $0 }
            .animation(EchoDesign.subtle, value: hovering)

            if showDivider {
                Divider().padding(.leading, 56)
            }
        }
    }
}

// MARK: - Acknowledgement Row

private struct AcknowledgementRow: View {
    let name: String
    let description: String
    let url: String
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

                    Text("MIT")
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
            .echoPointingCursor()
            .onHover { hovering = $0 }
            .animation(EchoDesign.subtle, value: hovering)

            if showDivider {
                Divider().padding(.leading, 56)
            }
        }
    }
}
