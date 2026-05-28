import SwiftUI

struct NotificationsPane: View {
    @EnvironmentObject var settings: EchoSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            SettingsPaneHeader(
                icon: "bell.badge.fill",
                title: "Notifications",
                subtitle: "Control when Echo alerts you",
                color: Color(red: 0.95, green: 0.65, blue: 0.30)
            )

            let orange = Color(red: 0.95, green: 0.65, blue: 0.30)

            // MARK: Session Events
            SettingsGroup(label: "Session Events") {
                SettingsToggleRow(
                    icon: "checkmark.seal",
                    iconColor: orange,
                    label: "Session saved",
                    description: "Notify when a session finishes saving to disk",
                    isOn: $settings.notifyOnSessionSaved,
                    showDivider: true
                )

                SettingsToggleRow(
                    icon: "moon.zzz",
                    iconColor: orange,
                    label: "Idle timeout warning",
                    description: "Notify 1 minute before a session ends due to inactivity",
                    isOn: $settings.notifyOnIdleWarning,
                    showDivider: false
                )
            }

            // MARK: Daily
            SettingsGroup(label: "Daily") {
                SettingsToggleRow(
                    icon: "chart.bar.doc.horizontal",
                    iconColor: orange,
                    label: "Daily summary",
                    description: "End-of-day digest with focus time and top apps",
                    isOn: $settings.notifyDailySummary,
                    showDivider: false
                )
            }

            // MARK: Coming Soon Banner
            ComingSoonBanner(color: orange)
        }
    }
}

// MARK: - Coming Soon Banner

private struct ComingSoonBanner: View {
    let color: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 16))
                .foregroundStyle(color.opacity(0.8))

            VStack(alignment: .leading, spacing: 3) {
                Text("Notifications coming soon")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                Text("These preferences are saved and will activate when notification support ships in an upcoming release.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: EchoDesign.pillRadius, style: .continuous)
                .fill(color.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: EchoDesign.pillRadius, style: .continuous)
                .strokeBorder(color.opacity(0.15), lineWidth: 0.5)
        )
    }
}
