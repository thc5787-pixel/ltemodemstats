import Foundation

/// Binary units (1 KB = 1024 B), as carriers bill data plans.
public enum ByteFormat {
    private static let units = ["B", "KB", "MB", "GB", "TB"]

    /// `1536` → `"1.5 KB"`.
    public static func bytes(_ value: UInt64) -> String {
        let (number, unit) = scale(Double(value))
        return "\(number) \(units[unit])"
    }

    /// `1536.0` → `"1.5 KB/s"`.
    public static func rate(_ bytesPerSecond: Double) -> String {
        let (number, unit) = scale(bytesPerSecond)
        return "\(number) \(units[unit])/s"
    }

    /// Short form for the menu bar, always 4 characters wide (padded with figure spaces)
    /// so the status item does not jitter: `1258291.0` → `"1.2M"`, `81920.0` → `" 80K"`.
    public static func compactRate(_ bytesPerSecond: Double) -> String {
        var value = max(0, bytesPerSecond)
        var unit = 0
        // Switch units before the value would round to 1000, so it never needs four digits.
        while value >= 999.5, unit < units.count - 1 {
            value /= 1024
            unit += 1
        }
        let number = unit > 0 && value < 9.95 ? String(format: "%.1f", value) : String(Int(value.rounded()))
        let text = number + (unit == 0 ? "B" : String(units[unit].prefix(1)))
        return String(repeating: "\u{2007}", count: max(0, 4 - text.count)) + text
    }

    /// Value and unit index; one decimal below 100, none above.
    static func scale(_ value: Double) -> (String, Int) {
        var value = max(0, value)
        var unit = 0
        while value >= 1024, unit < units.count - 1 {
            value /= 1024
            unit += 1
        }
        if unit == 0 || value >= 100 {
            return (String(Int(value.rounded())), unit)
        }
        return (String(format: "%.1f", value), unit)
    }
}
