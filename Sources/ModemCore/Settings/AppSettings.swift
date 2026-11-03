import Foundation
import Observation

/// User preferences, persisted in UserDefaults as soon as they change.
@MainActor
@Observable
public final class AppSettings {
    /// Show `↓1.2M ↑80K` next to the signal icon.
    public var showRateInMenuBar: Bool {
        didSet { defaults.set(showRateInMenuBar, forKey: Key.showRate) }
    }

    /// Day of month (1…28) the data plan resets.
    public var billingDay: Int {
        didSet { defaults.set(billingDay, forKey: Key.billingDay) }
    }

    /// Monthly data plan in GB; 0 = no limit.
    public var monthlyQuotaGB: Double {
        didSet { defaults.set(monthlyQuotaGB, forKey: Key.quota) }
    }

    /// Interface language; applied to `L10n` immediately.
    public var language: AppLanguage {
        didSet {
            defaults.set(language.rawValue, forKey: Key.language)
            L10n.apply(language)
        }
    }

    /// Start at login (system state, not a UserDefaults value).
    public var launchAtLogin: Bool {
        didSet {
            guard launchAtLogin != oldValue, !revertingLaunchAtLogin else { return }
            do {
                if launchAtLogin {
                    try loginItem.enable()
                } else {
                    try loginItem.disable()
                }
                launchAtLoginError = nil
            } catch {
                launchAtLoginError = error.localizedDescription
                // Reflect the real state without running the opposite action.
                revertingLaunchAtLogin = true
                launchAtLogin = loginItem.isEnabled
                revertingLaunchAtLogin = false
            }
            launchAtLoginNeedsApproval = loginItem.needsApproval
        }
    }

    /// Registered but not yet allowed in System Settings › Login Items.
    public private(set) var launchAtLoginNeedsApproval = false

    /// Re-reads the login item state (the user may have changed it in System Settings).
    public func refreshLaunchAtLogin() {
        revertingLaunchAtLogin = true
        launchAtLogin = loginItem.isEnabled
        revertingLaunchAtLogin = false
        launchAtLoginNeedsApproval = loginItem.needsApproval
    }

    /// Why the last change to `launchAtLogin` failed.
    public private(set) var launchAtLoginError: String?
    @ObservationIgnored private var revertingLaunchAtLogin = false

    private let defaults: UserDefaults
    private let loginItem: LoginItem

    nonisolated private enum Key {
        static let showRate = "showRateInMenuBar"
        static let billingDay = "billingDay"
        static let quota = "monthlyQuotaGB"
        static let language = "language"
    }

    nonisolated public static let defaultSuite = "com.ltemodemstats.agent"

    /// The saved language, for processes that don't build `AppSettings` (the CLI).
    nonisolated public static func storedLanguage(_ defaults: UserDefaults = UserDefaults(suiteName: defaultSuite) ?? .standard) -> AppLanguage {
        defaults.string(forKey: Key.language).flatMap(AppLanguage.init(rawValue:)) ?? .system
    }

    /// The saved billing day (1…28), for the CLI.
    nonisolated public static func storedBillingDay(_ defaults: UserDefaults = UserDefaults(suiteName: defaultSuite) ?? .standard) -> Int {
        let day = defaults.integer(forKey: Key.billingDay)
        return day == 0 ? 1 : min(max(day, 1), 28)
    }

    public init(defaults: UserDefaults = UserDefaults(suiteName: AppSettings.defaultSuite) ?? .standard,
                loginItem: LoginItem = AppLoginItem()) {
        self.defaults = defaults
        self.loginItem = loginItem
        launchAtLogin = loginItem.isEnabled
        launchAtLoginNeedsApproval = loginItem.needsApproval
        defaults.register(defaults: [
            Key.showRate: true,
            Key.billingDay: 1,
            Key.quota: 0.0,
        ])
        showRateInMenuBar = defaults.bool(forKey: Key.showRate)
        billingDay = min(max(defaults.integer(forKey: Key.billingDay), 1), 28)
        monthlyQuotaGB = max(0, defaults.double(forKey: Key.quota))
        language = Self.storedLanguage(defaults)
        L10n.apply(language)
    }
}
