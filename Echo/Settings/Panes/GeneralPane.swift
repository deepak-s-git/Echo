import SwiftUI

struct GeneralPane: View {
    @EnvironmentObject var settings: EchoSettings
    @EnvironmentObject var appStore: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            SettingsPaneHeader(
                icon: "gearshape.fill",
                title: "General",
                subtitle: "App behavior, session timing & menu bar",
                color: EchoPalette.indigo
            )

            let steelBlue = EchoPalette.indigo

            // MARK: Session Timing
            SettingsGroup(label: "Session Timing") {
                SettingsSliderRow(
                    icon: "moon.zzz",
                    iconColor: steelBlue,
                    label: "Idle timeout",
                    value: $settings.idleTimeoutMinutes,
                    range: 5...60,
                    step: 5,
                    valueFormatter: { v in
                        "\(Int(v)) min"
                    },
                    showDivider: true
                )

                SettingsSliderRow(
                    icon: "timer",
                    iconColor: steelBlue,
                    label: "Minimum session duration",
                    value: $settings.minimumSessionSeconds,
                    range: 10...300,
                    step: 10,
                    valueFormatter: { v in
                        v < 60 ? "\(Int(v))s" : "\(Int(v / 60))m \(Int(v.truncatingRemainder(dividingBy: 60)))s"
                    },
                    showDivider: false
                )
            }

            // MARK: Startup
            SettingsGroup(label: "Startup") {
                SettingsToggleRow(
                    icon: "power",
                    iconColor: steelBlue,
                    label: "Launch at login",
                    description: "Automatically start Echo when you log in",
                    isOn: $settings.launchAtLogin,
                    showDivider: false
                )
            }

            // MARK: Menu Bar
            SettingsGroup(label: "Menu Bar") {
                SettingsToggleRow(
                    icon: "menubar.rectangle",
                    iconColor: steelBlue,
                    label: "Show in menu bar",
                    description: "Always-visible status and quick controls",
                    isOn: $settings.showInMenuBar,
                    showDivider: false
                )
            }

            // MARK: Developer Settings
            #if DEBUG
            SettingsGroup(label: "Developer Settings") {
                HStack(spacing: 12) {
                    Image(systemName: "ladybug.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(steelBlue)
                        .frame(width: 18)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Onboarding Intro")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.primary)
                        Text("Relaunches the cinematic first-launch animation immediately.")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    Button("Play Animation") {
                        UserDefaults.standard.set(false, forKey: "echo.onboardingComplete")
                        appStore.isOnboardingPresented = true
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.vertical, 4)
            }
            #endif

            // MARK: Info card
            IdleTimeoutInfoCard(minutes: settings.idleTimeoutMinutes, steelBlue: steelBlue)
        }
    }
}

// MARK: - Info Card

private struct IdleTimeoutInfoCard: View {
    let minutes: Double
    let steelBlue: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "info.circle")
                .font(.system(size: 14))
                .foregroundStyle(steelBlue)

            Text("Sessions automatically end after **\(Int(minutes)) minute\(minutes == 1 ? "" : "s")** of inactivity. You can also end them manually anytime.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: EchoDesign.pillRadius, style: .continuous)
                .fill(steelBlue.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: EchoDesign.pillRadius, style: .continuous)
                .strokeBorder(steelBlue.opacity(0.12), lineWidth: 0.5)
        )
    }
}
