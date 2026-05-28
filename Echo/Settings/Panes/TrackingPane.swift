import SwiftUI
import AppKit

struct TrackingPane: View {
    @EnvironmentObject var settings: EchoSettings
    @State private var showAddSheet = false
    @State private var newBundleId = ""
    @State private var showRunningAppPicker = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            SettingsPaneHeader(
                icon: "waveform.circle.fill",
                title: "Tracking",
                subtitle: "What Echo watches and what it ignores",
                color: EchoPalette.indigoSoft
            )

            // MARK: Activity Capture
            SettingsGroup(label: "Activity Capture") {
                SettingsToggleRow(
                    icon: "safari",
                    iconColor: EchoPalette.indigoSoft,
                    label: "Track browser tabs",
                    description: "Capture active URLs from Safari, Chrome, Arc & more",
                    isOn: $settings.trackBrowserTabs,
                    showDivider: true
                )

                SettingsToggleRow(
                    icon: "text.cursor",
                    iconColor: EchoPalette.indigoSoft,
                    label: "Record window titles",
                    description: "Helps identify project context — no keystroke data is read",
                    isOn: $settings.recordWindowTitles,
                    showDivider: true
                )

                SettingsSliderRow(
                    icon: "clock.badge.checkmark",
                    iconColor: EchoPalette.indigoSoft,
                    label: "Browser tab capture delay",
                    value: $settings.browserCaptureDelaySeconds,
                    range: 0.5...5.0,
                    step: 0.1,
                    valueFormatter: { String(format: "%.1fs", $0) },
                    showDivider: false
                )
            }

            // MARK: Ignored Apps
            SettingsGroup(label: "Ignored Apps") {
                // Explanation row
                HStack(spacing: 12) {
                    Image(systemName: "eye.slash")
                        .font(.system(size: 13))
                        .foregroundStyle(.tertiary)
                        .frame(width: 28, height: 28)

                    Text("Activity from these apps will not be recorded.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)

                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

                Divider().padding(.leading, 56)

                // App list
                if settings.ignoredBundleIds.isEmpty {
                    HStack {
                        Spacer()
                        Text("No apps ignored")
                            .font(.system(size: 12))
                            .foregroundStyle(.quaternary)
                            .italic()
                        Spacer()
                    }
                    .padding(.vertical, 20)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(settings.ignoredBundleIds.enumerated()), id: \.element) { idx, bundleId in
                            IgnoredAppRow(
                                bundleId: bundleId,
                                showDivider: idx < settings.ignoredBundleIds.count - 1
                            ) {
                                withAnimation(EchoDesign.subtle) {
                                    settings.removeIgnoredApp(bundleId)
                                }
                            }
                        }
                    }
                }

                Divider().padding(.leading, 16)

                // Add buttons
                HStack(spacing: 10) {
                    Button {
                        showRunningAppPicker = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "plus.circle.fill")
                                .foregroundStyle(EchoPalette.indigoSoft)
                            Text("Add running app…")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(EchoPalette.indigoSoft)
                        }
                    }
                    .buttonStyle(.plain)

                    Text("or")
                        .font(.system(size: 11))
                        .foregroundStyle(.quaternary)

                    Button {
                        showAddSheet = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "keyboard")
                                .foregroundStyle(.secondary)
                            Text("Enter bundle ID…")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)

                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
        // MARK: - Sheet: Enter bundle ID
        .sheet(isPresented: $showAddSheet) {
            AddBundleIdSheet(isPresented: $showAddSheet) { bundleId in
                withAnimation(EchoDesign.subtle) {
                    settings.addIgnoredApp(bundleId)
                }
            }
        }
        // MARK: - Sheet: Pick running app
        .sheet(isPresented: $showRunningAppPicker) {
            RunningAppPickerSheet(isPresented: $showRunningAppPicker) { bundleId in
                withAnimation(EchoDesign.subtle) {
                    settings.addIgnoredApp(bundleId)
                }
            }
        }
    }
}

// MARK: - Ignored App Row

private struct IgnoredAppRow: View {
    let bundleId: String
    let showDivider: Bool
    let onRemove: () -> Void

    @State private var hovering = false

    private var appName: String {
        AppMetadataResolver.humanizedBundleId(bundleId)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                AppIconView(bundleId: bundleId, size: 28)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                VStack(alignment: .leading, spacing: 1) {
                    Text(appName)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.primary)
                    Text(bundleId)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.quaternary)
                        .lineLimit(1)
                }

                Spacer()

                if hovering {
                    Button(action: onRemove) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(Color.red.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .animation(EchoDesign.subtle, value: hovering)
            .onHover { hovering = $0 }

            if showDivider {
                Divider().padding(.leading, 56)
            }
        }
    }
}

// MARK: - Add Bundle ID Sheet

private struct AddBundleIdSheet: View {
    @Binding var isPresented: Bool
    let onConfirm: (String) -> Void

    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 6) {
                Image(systemName: "keyboard")
                    .font(.system(size: 28, weight: .thin))
                    .foregroundStyle(EchoPalette.indigoSoft)
                Text("Add by Bundle ID")
                    .font(.system(size: 16, weight: .semibold))
                Text("Enter the app's bundle identifier\n(e.g. com.spotify.client)")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            TextField("com.example.App", text: $text)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 13, design: .monospaced))
                .focused($focused)
                .onSubmit { confirm() }

            HStack(spacing: 12) {
                Button("Cancel") { isPresented = false }
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(.bordered)

                Button("Add") { confirm() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(28)
        .frame(width: 340)
        .onAppear { focused = true }
    }

    private func confirm() {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        onConfirm(trimmed)
        isPresented = false
    }
}

// MARK: - Running App Picker Sheet

private struct RunningAppPickerSheet: View {
    @Binding var isPresented: Bool
    let onSelect: (String) -> Void

    @EnvironmentObject var settings: EchoSettings
    @State private var searchText = ""

    private var runningApps: [(name: String, bundleId: String)] {
        NSWorkspace.shared.runningApplications
            .compactMap { app -> (String, String)? in
                guard let bundleId = app.bundleIdentifier,
                      !bundleId.isEmpty,
                      let name = app.localizedName,
                      !name.isEmpty,
                      app.activationPolicy == .regular
                else { return nil }
                guard !settings.ignoredBundleIds.contains(bundleId) else { return nil }
                return (name, bundleId)
            }
            .filter {
                searchText.isEmpty ||
                $0.0.localizedCaseInsensitiveContains(searchText) ||
                $0.1.localizedCaseInsensitiveContains(searchText)
            }
            .sorted { $0.0 < $1.0 }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 6) {
                Text("Running Apps")
                    .font(.system(size: 16, weight: .semibold))
                Text("Select an app to add to the ignore list")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 20)
            .padding(.bottom, 14)

            Divider()

            // Search
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.tertiary)
                    .font(.system(size: 13))
                TextField("Search apps…", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(Color.primary.opacity(0.04))

            Divider()

            // List
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(runningApps, id: \.bundleId) { app in
                        RunningAppRow(name: app.name, bundleId: app.bundleId) {
                            onSelect(app.bundleId)
                            isPresented = false
                        }
                        Divider().padding(.leading, 50)
                    }
                }
            }
            .frame(height: 280)

            Divider()

            Button("Cancel") { isPresented = false }
                .buttonStyle(.bordered)
                .padding(16)
        }
        .frame(width: 360)
    }
}

private struct RunningAppRow: View {
    let name: String
    let bundleId: String
    let onSelect: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                AppIconView(bundleId: bundleId, size: 28)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                VStack(alignment: .leading, spacing: 1) {
                    Text(name)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.primary)
                    Text(bundleId)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                Image(systemName: "plus.circle")
                    .font(.system(size: 14))
                    .foregroundStyle(EchoPalette.indigoSoft.opacity(hovering ? 1 : 0.4))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(hovering ? Color.primary.opacity(0.04) : Color.clear)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(EchoDesign.subtle, value: hovering)
    }
}
