import SwiftUI
import Combine

// MARK: - EchoSettings

@MainActor
final class EchoSettings: ObservableObject {

    static let shared = EchoSettings()

    private let defaults = UserDefaults.standard

    typealias Keys = EchoSettingsKeys

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

    @Published var tabEligibilitySeconds: Double {
        didSet { defaults.set(tabEligibilitySeconds, forKey: Keys.tabEligibilitySeconds) }
    }

    @Published var appFocusEligibilitySeconds: Double {
        didSet { defaults.set(appFocusEligibilitySeconds, forKey: Keys.appFocusEligibilitySeconds) }
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

    @Published var accentVibe: AccentVibe {
        didSet { defaults.set(accentVibe.rawValue, forKey: Keys.accentVibe) }
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
        #if DEBUG
        idleTimeoutMinutes = defaults.object(forKey: Keys.idleTimeoutMinutes) as? Double ?? 30.0
        #else
        idleTimeoutMinutes = defaults.object(forKey: Keys.idleTimeoutMinutes) as? Double ?? 30.0
        #endif
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
        browserCaptureDelaySeconds = defaults.object(forKey: Keys.browserCaptureDelaySeconds) as? Double ?? 5.0
        tabEligibilitySeconds = defaults.object(forKey: Keys.tabEligibilitySeconds) as? Double ?? 10.0
        appFocusEligibilitySeconds = defaults.object(forKey: Keys.appFocusEligibilitySeconds) as? Double ?? 12.0

        // Privacy
        dataRetentionDays = defaults.object(forKey: Keys.dataRetentionDays) as? Int ?? 90

        // Appearance
        let rawTheme = defaults.string(forKey: Keys.appTheme) ?? AppTheme.system.rawValue
        appTheme = AppTheme(rawValue: rawTheme) ?? .system

        let rawVibe = defaults.string(forKey: Keys.accentVibe) ?? AccentVibe.copper.rawValue
        accentVibe = AccentVibe(rawValue: rawVibe) ?? .copper

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

// MARK: - AccentVibe

enum AccentVibe: String, CaseIterable, Identifiable {
    case copper = "copper"
    case frost = "frost"
    case sunset = "sunset"
    case forest = "forest"
    case neon = "neon"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .copper: return "Cybernetic Copper"
        case .frost: return "Nordic Frost"
        case .sunset: return "Sunset Rose"
        case .forest: return "Forest Mint"
        case .neon: return "Neon Noir"
        }
    }

    var primaryColorDark: NSColor {
        switch self {
        case .copper: return NSColor(red: 0.85, green: 0.42, blue: 0.18, alpha: 1.0)
        case .frost: return NSColor(red: 0.28, green: 0.58, blue: 0.88, alpha: 1.0)
        case .sunset: return NSColor(red: 0.92, green: 0.32, blue: 0.48, alpha: 1.0)
        case .forest: return NSColor(red: 0.18, green: 0.72, blue: 0.46, alpha: 1.0)
        case .neon: return NSColor(red: 0.72, green: 0.28, blue: 0.95, alpha: 1.0)
        }
    }

    var primaryColorLight: NSColor {
        switch self {
        case .copper: return NSColor(red: 0.75, green: 0.32, blue: 0.08, alpha: 1.0)
        case .frost: return NSColor(red: 0.18, green: 0.48, blue: 0.78, alpha: 1.0)
        case .sunset: return NSColor(red: 0.82, green: 0.22, blue: 0.38, alpha: 1.0)
        case .forest: return NSColor(red: 0.08, green: 0.55, blue: 0.32, alpha: 1.0)
        case .neon: return NSColor(red: 0.60, green: 0.15, blue: 0.85, alpha: 1.0)
        }
    }

    var secondaryColorDark: NSColor {
        switch self {
        case .copper: return NSColor(red: 0.82, green: 0.74, blue: 0.55, alpha: 1.0)
        case .frost: return NSColor(red: 0.52, green: 0.80, blue: 0.92, alpha: 1.0)
        case .sunset: return NSColor(red: 0.96, green: 0.65, blue: 0.42, alpha: 1.0)
        case .forest: return NSColor(red: 0.62, green: 0.88, blue: 0.74, alpha: 1.0)
        case .neon: return NSColor(red: 0.22, green: 0.82, blue: 0.92, alpha: 1.0)
        }
    }

    var secondaryColorLight: NSColor {
        switch self {
        case .copper: return NSColor(red: 0.65, green: 0.57, blue: 0.38, alpha: 1.0)
        case .frost: return NSColor(red: 0.38, green: 0.62, blue: 0.75, alpha: 1.0)
        case .sunset: return NSColor(red: 0.80, green: 0.50, blue: 0.30, alpha: 1.0)
        case .forest: return NSColor(red: 0.42, green: 0.72, blue: 0.58, alpha: 1.0)
        case .neon: return NSColor(red: 0.08, green: 0.62, blue: 0.72, alpha: 1.0)
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
