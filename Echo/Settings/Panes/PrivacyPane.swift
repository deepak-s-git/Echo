import SwiftUI

struct PrivacyPane: View {
    @EnvironmentObject var settings: EchoSettings
    @EnvironmentObject var permissionsManager: PermissionsManager

    @State private var showClearDataAlert = false
    @State private var showClearDataConfirm = false
    @State private var clearDataComplete = false

    // Selected retention as DataRetentionOption
    private var selectedRetention: Binding<DataRetentionOption> {
        Binding(
            get: { DataRetentionOption.from(days: settings.dataRetentionDays) },
            set: { settings.dataRetentionDays = $0.days }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            SettingsPaneHeader(
                icon: "lock.shield.fill",
                title: "Privacy",
                subtitle: "Permissions, data storage & retention",
                color: Color(red: 0.45, green: 0.72, blue: 0.55)
            )

            // MARK: Permissions
            SettingsGroup(label: "Permissions") {
                // Accessibility row
                SettingsRow(
                    icon: "accessibility",
                    iconColor: Color(red: 0.45, green: 0.72, blue: 0.55),
                    label: "Accessibility Access",
                    description: "Required to detect which apps you use",
                    showDivider: false
                ) {
                    HStack(spacing: 10) {
                        SettingsStatusBadge(
                            isActive: permissionsManager.accessibilityGranted,
                            activeLabel: "Granted",
                            inactiveLabel: "Required"
                        )

                        if !permissionsManager.accessibilityGranted {
                            Button("Open Settings") {
                                permissionsManager.requestAccessibility()
                            }
                            .font(.system(size: 12, weight: .medium))
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                }
            }

            // MARK: What Echo Collects
            SettingsGroup(label: "What Echo Records") {
                PrivacyFactRow(
                    icon: "app.badge.checkmark",
                    label: "App names and bundle IDs",
                    isRecorded: true
                )
                PrivacyFactRow(
                    icon: "clock",
                    label: "Time spent in each app",
                    isRecorded: true
                )
                PrivacyFactRow(
                    icon: "safari",
                    label: "Browser tab URLs (if enabled)",
                    isRecorded: true
                )
                PrivacyFactRow(
                    icon: "keyboard",
                    label: "Keystrokes or typed content",
                    isRecorded: false
                )
                PrivacyFactRow(
                    icon: "camera.metering.none",
                    label: "Screen or camera content",
                    isRecorded: false
                )
                PrivacyFactRow(
                    icon: "network",
                    label: "Network or internet access",
                    isRecorded: false,
                    showDivider: false
                )
            }

            // MARK: Storage
            SettingsGroup(label: "Storage") {
                SettingsRow(
                    icon: "internaldrive",
                    iconColor: Color(red: 0.45, green: 0.72, blue: 0.55),
                    label: "Data location",
                    description: "~/Library/Application Support/Echo/echo.sqlite",
                    showDivider: true
                ) {
                    Button {
                        openDatabaseFolder()
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "folder")
                                .font(.system(size: 11))
                            Text("Show")
                                .font(.system(size: 12))
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                SettingsRow(
                    icon: "calendar.badge.clock",
                    iconColor: Color(red: 0.45, green: 0.72, blue: 0.55),
                    label: "Keep data for",
                    showDivider: false
                ) {
                    Picker("", selection: selectedRetention) {
                        ForEach(DataRetentionOption.allCases) { option in
                            Text(option.label).tag(option)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 120)
                }
            }

            // MARK: Danger Zone
            SettingsGroup(label: "Danger Zone") {
                VStack(spacing: 0) {
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.red.opacity(0.10))
                                .frame(width: 28, height: 28)
                            Image(systemName: "trash")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Color.red.opacity(0.8))
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Clear all data")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.primary)
                            Text("Permanently delete all sessions, activities and snapshots")
                                .font(.system(size: 11))
                                .foregroundStyle(.tertiary)
                        }

                        Spacer()

                        SettingsDestructiveButton(label: "Clear Data…", icon: "trash") {
                            showClearDataAlert = true
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
            }
        }
        .alert("Clear All Data?", isPresented: $showClearDataAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Clear Everything", role: .destructive) {
                clearAllData()
            }
        } message: {
            Text("This will permanently delete all recorded sessions, activity events, and snapshots. This action cannot be undone.")
        }
        .alert("Data Cleared", isPresented: $clearDataComplete) {
            Button("OK") {}
        } message: {
            Text("All Echo data has been deleted. The app will start fresh.")
        }
    }

    private func openDatabaseFolder() {
        guard let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first else { return }
        let echoDir = appSupport.appendingPathComponent("Echo")
        NSWorkspace.shared.open(echoDir)
    }

    private func clearAllData() {
        // Post a notification for the app to handle DB clearing
        NotificationCenter.default.post(name: .echoClearAllData, object: nil)
        clearDataComplete = true
    }
}

// MARK: - Privacy Fact Row

private struct PrivacyFactRow: View {
    let icon: String
    let label: String
    let isRecorded: Bool
    var showDivider: Bool = true

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .foregroundStyle(isRecorded ? EchoPalette.indigoSoft : Color.primary.opacity(0.30))
                    .frame(width: 28)

                Text(label)
                    .font(.system(size: 13))
                    .foregroundStyle(isRecorded ? .primary : Color.primary.opacity(0.45))

                Spacer()

                HStack(spacing: 5) {
                    Image(systemName: isRecorded ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(isRecorded ? EchoPalette.live : Color.primary.opacity(0.25))
                    Text(isRecorded ? "Yes" : "Never")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(isRecorded ? EchoPalette.live : Color.primary.opacity(0.30))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            if showDivider {
                Divider().padding(.leading, 56)
            }
        }
    }
}

// MARK: - Notification name extension

extension Notification.Name {
    nonisolated static let echoClearAllData = Notification.Name("echo.clearAllData")
}
