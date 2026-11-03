import Foundation

/// Interface language choice, stored in settings.
public enum AppLanguage: String, CaseIterable, Sendable {
    case system, chinese = "zh", english = "en"
}

/// Inline two-language strings: `L10n.t("设备", "Device")`.
/// Without an app bundle, `.lproj` resources are awkward; the app is small enough
/// to keep both texts next to each other.
public enum L10n {
    public enum Resolved: Sendable { case chinese, english }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var _current: Resolved = resolve(.system)

    /// The language in effect. Read from any thread (error texts are built off the main thread).
    public static var current: Resolved {
        lock.withLock { _current }
    }

    public static func apply(_ language: AppLanguage) {
        let resolved = resolve(language)
        lock.withLock { _current = resolved }
    }

    public static func t(_ chinese: String, _ english: String) -> String {
        current == .chinese ? chinese : english
    }

    /// `.system` follows the first preferred language: Chinese if it is any `zh-*`, else English.
    public static func resolve(_ language: AppLanguage,
                               preferred: [String] = Locale.preferredLanguages) -> Resolved {
        switch language {
        case .chinese: return .chinese
        case .english: return .english
        case .system: return preferred.first?.hasPrefix("zh") == true ? .chinese : .english
        }
    }
}
