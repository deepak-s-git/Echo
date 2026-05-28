import SwiftUI
import Combine

// MARK: - EchoSettings

@MainActor
final class EchoSettings: ObservableObject {

    static let shared = EchoSettings()

    private let defaults = UserDefaults.standard

    // MARK: - General

    @Published var idleTimeoutMinutes: Double {
        didSet { defaults.set(idleTimeoutMinutes, forKey: Keys.idleTimeoutMinutes) }
    }

    @Published var minimumSessionSeconds: Double {
        didSet { defaults.set(minimumSessionSeconds, forKey: Keys.minimumSessionSeconds) }
    }

    @Published var showInMenuBar: Bool {
        didSet { defaults.set(showInMenuBar, forKey: Keys.showInMenuBar) }
    }

    @Published var launchAtLogin: Bool {
        didSet {
            defaults.set(launchAtLogin, forKey: Keys.launchAtLogin)
            applyLaunchAtLogin(launchAtLogin)
        }
    }

    // MARK: - Tracking

    @Published var ignoredBundleIds: [String] {
        didSet {
            if let data = try? JSONEncoder().encode(ignoredBundleIds) {
                defaults.set(data, forKey: Keys.ignoredBundleIds)
            }
        }
    }

    @Published var trackBrowserTabs: Bool {
        didSet { defaults.set(trackBrowserTabs, forKey: Keys.trackBrowserTabs) }
    }

    @Published var recordWindowTitles: Bool {
        didSet { defaults.set(recordWindowTitles, forKey: Keys.recordWindowTitles) }
    }

    @Published var browserCaptureDelaySeconds: Double {
        didSet { defaults.set(browserCaptureDelaySeconds, forKey: Keys.browserCaptureDelaySeconds) }
    }

    // MARK: - Privacy

    @Published var dataRetentionDays: Int {
        didSet { defaults.set(dataRetentionDays, forKey: Keys.dataRetentionDays) }
    }

    // MARK: - Appearance

    @Published var appTheme: AppTheme {
        didSet {
            defaults.set(appTheme.rawValue, forKey: Keys.appTheme)
            applyTheme(appTheme)
        }
    }

    @Published var showFocusScoreRing: Bool {
        didSet { defaults.set(showFocusScoreRing, forKey: Keys.showFocusScoreRing) }
    }

    @Published var compactTimeline: Bool {
        didSet { defaults.set(compactTimeline, forKey: Keys.compactTimeline) }
    }

    // MARK: - Notifications

    @Published var notifyOnSessionSaved: Bool {
        didSet { defaults.set(notifyOnSessionSaved, forKey: Keys.notifyOnSessionSaved) }
    }

    @Published var notifyOnIdleWarning: Bool {
        didSet { defaults.set(notifyOnIdleWarning, forKey: Keys.notifyOnIdleWarning) }
    }

    @Published var notifyDailySummary: Bool {
        didSet { defaults.set(notifyDailySummary, forKey: Keys.notifyDailySummary) }
    }

    // MARK: - Init

    init() {
        // General
        idleTimeoutMinutes = defaults.object(forKey: Keys.idleTimeoutMinutes) as? Double ?? 5.0
        minimumSessionSeconds = defaults.object(forKey: Keys.minimumSessionSeconds) as? Double ?? 30.0
        showInMenuBar = defaults.object(forKey: Keys.showInMenuBar) as? Bool ?? true
        launchAtLogin = defaults.object(forKey: Keys.launchAtLogin) as? Bool ?? false

        // Tracking
        if let data = defaults.data(forKey: Keys.ignoredBundleIds),
           let decoded = try? JSONDecoder().decode([String].self, from: data) {
            ignoredBundleIds = decoded
        } else {
            ignoredBundleIds = Self.defaultIgnoredApps
        }
        trackBrowserTabs = defaults.object(forKey: Keys.trackBrowserTabs) as? Bool ?? true
        recordWindowTitles = defaults.object(forKey: Keys.recordWindowTitles) as? Bool ?? true
        browserCaptureDelaySeconds = defaults.object(forKey: Keys.browserCaptureDelaySeconds) as? Double ?? 1.2

        // Privacy
        dataRetentionDays = defaults.object(forKey: Keys.dataRetentionDays) as? Int ?? 90

        // Appearance
        let rawTheme = defaults.string(forKey: Keys.appTheme) ?? AppTheme.system.rawValue
        appTheme = AppTheme(rawValue: rawTheme) ?? .system

        showFocusScoreRing = defaults.object(forKey: Keys.showFocusScoreRing) as? Bool ?? true
        compactTimeline = defaults.object(forKey: Keys.compactTimeline) as? Bool ?? false

        // Notifications
        notifyOnSessionSaved = defaults.object(forKey: Keys.notifyOnSessionSaved) as? Bool ?? false
        notifyOnIdleWarning = defaults.object(forKey: Keys.notifyOnIdleWarning) as? Bool ?? false
        notifyDailySummary = defaults.object(forKey: Keys.notifyDailySummary) as? Bool ?? false
    }

    // MARK: - Computed

    var idleTimeoutSeconds: TimeInterval {
        idleTimeoutMinutes * 60
    }

    var minimumSessionDuration: TimeInterval {
        minimumSessionSeconds
    }

    // MARK: - Helpers

    private func applyTheme(_ theme: AppTheme) {
        let appearance: NSAppearance? = switch theme {
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        case .system: nil
        }
        NSApp.appearance = appearance
    }

    private func applyLaunchAtLogin(_ enabled: Bool) {
        // ServiceManagement-based launch at login (macOS 13+)
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                // Silently fail — user may need to grant permission
                print("[EchoSettings] Launch at login error: \(error)")
            }
        }
    }

    func addIgnoredApp(_ bundleId: String) {
        guard !bundleId.isEmpty, !ignoredBundleIds.contains(bundleId) else { return }
        ignoredBundleIds.append(bundleId)
    }

    func removeIgnoredApp(at offsets: IndexSet) {
        ignoredBundleIds.remove(atOffsets: offsets)
    }

    func removeIgnoredApp(_ bundleId: String) {
        ignoredBundleIds.removeAll { $0 == bundleId }
    }

    // MARK: - Defaults

    static let defaultIgnoredApps: [String] = [
        "com.apple.Music",
        "com.spotify.client",
        "com.apple.Preferences",
        "com.apple.systempreferences",
        "com.apple.screensaver.engine"
    ]

    // MARK: - Keys

    private enum Keys {
        static let idleTimeoutMinutes = "echo.settings.idleTimeoutMinutes"
        static let minimumSessionSeconds = "echo.settings.minimumSessionSeconds"
        static let showInMenuBar = "echo.settings.showInMenuBar"
        static let launchAtLogin = "echo.settings.launchAtLogin"
        static let ignoredBundleIds = "echo.settings.ignoredBundleIds"
        static let trackBrowserTabs = "echo.settings.trackBrowserTabs"
        static let recordWindowTitles = "echo.settings.recordWindowTitles"
        static let browserCaptureDelaySeconds = "echo.settings.browserCaptureDelaySeconds"
        static let dataRetentionDays = "echo.settings.dataRetentionDays"
        static let appTheme = "echo.settings.appTheme"
        static let showFocusScoreRing = "echo.settings.showFocusScoreRing"
        static let compactTimeline = "echo.settings.compactTimeline"
        static let notifyOnSessionSaved = "echo.settings.notifyOnSessionSaved"
        static let notifyOnIdleWarning = "echo.settings.notifyOnIdleWarning"
        static let notifyDailySummary = "echo.settings.notifyDailySummary"
    }
}

// MARK: - AppTheme

enum AppTheme: String, CaseIterable, Identifiable {
    case system = "system"
    case light = "light"
    case dark = "dark"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var icon: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max"
        case .dark: return "moon"
        }
    }
}

// MARK: - DataRetention

enum DataRetentionOption: CaseIterable, Identifiable {
    case days30, days90, days180, year1, forever

    var id: Int { days }

    var days: Int {
        switch self {
        case .days30: return 30
        case .days90: return 90
        case .days180: return 180
        case .year1: return 365
        case .forever: return 0
        }
    }

    var label: String {
        switch self {
        case .days30: return "30 days"
        case .days90: return "90 days"
        case .days180: return "6 months"
        case .year1: return "1 year"
        case .forever: return "Forever"
        }
    }

    static func from(days: Int) -> DataRetentionOption {
        allCases.first { $0.days == days } ?? .days90
    }
}

// MARK: - Import ServiceManagement

import ServiceManagement
