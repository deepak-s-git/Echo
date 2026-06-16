import SwiftUI

// MARK: - Settings Shared Components

// MARK: PaneHeader

struct SettingsPaneHeader: View {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(color.opacity(0.12))
                    .frame(width: 44, height: 44)
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(color)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.bottom, 24)
    }
}

// MARK: SettingsGroup

struct SettingsGroup<Content: View>: View {
    let label: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label.uppercased())
                .font(.system(size: 9.5, weight: .bold))
                .foregroundStyle(EchoPalette.indigoSoft)
                .tracking(1.0)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)

            VStack(spacing: 0) {
                content()
            }
            .background(EchoPalette.graphiteElevated,
                        in: RoundedRectangle(cornerRadius: EchoDesign.cardCornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: EchoDesign.cardCornerRadius, style: .continuous)
                    .strokeBorder(EchoPalette.stroke, lineWidth: 0.5)
            )
        }
        .padding(.bottom, 20)
    }
}

// MARK: SettingsRow

struct SettingsRow<Content: View>: View {
    let icon: String?
    let iconColor: Color
    let label: String
    let description: String?
    var showDivider: Bool = true
    @ViewBuilder let control: () -> Content

    init(
        icon: String? = nil,
        iconColor: Color = EchoPalette.indigoSoft,
        label: String,
        description: String? = nil,
        showDivider: Bool = true,
        @ViewBuilder control: @escaping () -> Content
    ) {
        self.icon = icon
        self.iconColor = iconColor
        self.label = label
        self.description = description
        self.showDivider = showDivider
        self.control = control
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                if let icon {
                    ZStack {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(iconColor.opacity(0.12))
                            .frame(width: 28, height: 28)
                        Image(systemName: icon)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(iconColor)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.primary)
                    if let description {
                        Text(description)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()
                control()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            if showDivider {
                Rectangle()
                    .fill(EchoPalette.stroke)
                    .frame(height: 0.5)
                    .padding(.leading, icon != nil ? 56 : 16)
            }
        }
    }
}

// MARK: SettingsToggleRow

struct SettingsToggleRow: View {
    let icon: String?
    let iconColor: Color
    let label: String
    let description: String?
    @Binding var isOn: Bool
    var showDivider: Bool = true

    init(
        icon: String? = nil,
        iconColor: Color = EchoPalette.indigoSoft,
        label: String,
        description: String? = nil,
        isOn: Binding<Bool>,
        showDivider: Bool = true
    ) {
        self.icon = icon
        self.iconColor = iconColor
        self.label = label
        self.description = description
        self._isOn = isOn
        self.showDivider = showDivider
    }

    var body: some View {
        SettingsRow(
            icon: icon,
            iconColor: iconColor,
            label: label,
            description: description,
            showDivider: showDivider
        ) {
            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
                .labelsHidden()
        }
    }
}

// MARK: SliderRow

struct SettingsSliderRow: View {
    let icon: String?
    let iconColor: Color
    let label: String
    var description: String? = nil
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let valueFormatter: (Double) -> String
    var showDivider: Bool = true

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                if let icon {
                    ZStack {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(iconColor.opacity(0.12))
                            .frame(width: 28, height: 28)
                        Image(systemName: icon)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(iconColor)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(label)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.primary)
                            if let description {
                                Text(description)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Text(valueFormatter(value))
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundStyle(iconColor)
                            .frame(minWidth: 54, alignment: .trailing)
                    }
                    Slider(value: $value, in: range, step: step)
                        .tint(iconColor)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            if showDivider {
                Rectangle()
                    .fill(EchoPalette.stroke)
                    .frame(height: 0.5)
                    .padding(.leading, icon != nil ? 56 : 16)
            }
        }
    }
}

// MARK: StatusBadge

struct SettingsStatusBadge: View {
    let isActive: Bool
    let activeLabel: String
    let inactiveLabel: String

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(isActive ? EchoPalette.live : Color.red.opacity(0.75))
                .frame(width: 6, height: 6)
            Text(isActive ? activeLabel : inactiveLabel)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(isActive ? EchoPalette.live : Color.red.opacity(0.75))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(isActive ? EchoPalette.live.opacity(0.10) : Color.red.opacity(0.08))
        )
    }
}

// MARK: DestructiveButton

struct SettingsDestructiveButton: View {
    let label: String
    let icon: String
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                Text(label)
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundStyle(hovering ? Color.red : Color.red.opacity(0.8))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(hovering ? Color.red.opacity(0.10) : Color.red.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.red.opacity(hovering ? 0.25 : 0.12), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(EchoDesign.subtle, value: hovering)
    }
}
