import Foundation

/// Decides which reader groups are due. Pure, so it can be tested without a modem.
public struct ModemSchedule: Sendable {
    /// Signal and cell, every 5 s.
    public var signalInterval: TimeInterval = 5
    /// SIM, data and temperature change rarely.
    public var slowInterval: TimeInterval = 30
    /// Wait between attempts to open the AT interface while disconnected.
    public var reconnectInterval: TimeInterval = 10

    public init() {}

    /// `lastRun` holds when each group last completed; a missing entry means "never".
    /// `.device` is read once per connection.
    public func due(at now: Date, lastRun: [ModemReader.Group: Date]) -> Set<ModemReader.Group> {
        var groups = Set<ModemReader.Group>()
        for group in ModemReader.Group.allCases {
            guard let last = lastRun[group] else {
                groups.insert(group)
                continue
            }
            let interval: TimeInterval? = switch group {
            case .device: nil
            case .radio: signalInterval
            case .sim, .data, .temperature: slowInterval
            }
            if let interval, now.timeIntervalSince(last) >= interval {
                groups.insert(group)
            }
        }
        return groups
    }
}
