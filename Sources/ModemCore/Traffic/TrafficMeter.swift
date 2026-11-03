import Foundation

public struct TrafficTotals: Codable, Equatable, Sendable {
    public var rx: UInt64 = 0
    public var tx: UInt64 = 0
    public var total: UInt64 { rx + tx }

    public init(rx: UInt64 = 0, tx: UInt64 = 0) {
        self.rx = rx
        self.tx = tx
    }

    static func + (lhs: Self, rhs: Self) -> Self {
        Self(rx: lhs.rx + rhs.rx, tx: lhs.tx + rhs.tx)
    }
}

/// Daily byte totals, keyed by local date `yyyy-MM-dd`.
public struct TrafficHistory: Codable, Equatable, Sendable {
    public var days: [String: TrafficTotals] = [:]

    public init(days: [String: TrafficTotals] = [:]) {
        self.days = days
    }

    public static func load(from url: URL) -> TrafficHistory {
        guard let data = try? Data(contentsOf: url),
              let history = try? JSONDecoder().decode(TrafficHistory.self, from: data) else { return TrafficHistory() }
        return history
    }

    public func save(to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: url, options: .atomic)
    }

    public static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LTE Modem Stats/traffic.json")
    }
}

/// Turns periodic interface counter samples into rates and daily totals.
public struct TrafficMeter: Sendable {
    public private(set) var history: TrafficHistory
    /// Bytes per second over the last sample interval.
    public private(set) var rxRate: Double = 0
    public private(set) var txRate: Double = 0
    /// Counters of the interface itself, i.e. traffic since it came up.
    public private(set) var session: TrafficTotals?

    private var last: (counters: InterfaceCounters, date: Date)?
    private let calendar: Calendar
    /// Days older than this are dropped from history.
    private let keepDays = 400

    public init(history: TrafficHistory = TrafficHistory(), calendar: Calendar = .current) {
        self.history = history
        self.calendar = calendar
    }

    /// Feeds one sample; nil means the interface is gone.
    public mutating func record(_ counters: InterfaceCounters?, at date: Date) {
        defer { last = counters.map { ($0, date) } }
        session = counters.map { TrafficTotals(rx: $0.rxBytes, tx: $0.txBytes) }

        guard let counters, let last,
              counters.rxBytes >= last.counters.rxBytes, counters.txBytes >= last.counters.txBytes
        else {
            // First sample, interface gone, or counters reset (interface recreated): new baseline.
            rxRate = 0
            txRate = 0
            return
        }

        let delta = TrafficTotals(rx: counters.rxBytes - last.counters.rxBytes,
                                  tx: counters.txBytes - last.counters.txBytes)
        let seconds = date.timeIntervalSince(last.date)
        rxRate = seconds > 0 ? Double(delta.rx) / seconds : 0
        txRate = seconds > 0 ? Double(delta.tx) / seconds : 0

        let key = dayKey(date)
        history.days[key] = (history.days[key] ?? TrafficTotals()) + delta
        if history.days.count > keepDays {
            for oldKey in history.days.keys.sorted().dropLast(keepDays) {
                history.days[oldKey] = nil
            }
        }
    }

    public func today(_ date: Date = Date()) -> TrafficTotals {
        history.days[dayKey(date)] ?? TrafficTotals()
    }

    /// Total of the billing cycle containing `date`; the cycle starts on `startDay` (1…28) each month.
    public func cycle(startDay: Int, containing date: Date = Date()) -> TrafficTotals {
        let start = cycleStart(startDay: startDay, containing: date)
        let from = dayKey(start)
        let to = dayKey(date)
        return history.days
            .filter { $0.key >= from && $0.key <= to }
            .values
            .reduce(TrafficTotals(), +)
    }

    public func cycleStart(startDay: Int, containing date: Date) -> Date {
        let day = min(max(startDay, 1), 28)
        var components = calendar.dateComponents([.year, .month, .day], from: date)
        if components.day! < day {
            components.month! -= 1
        }
        components.day = day
        return calendar.date(from: components)!
    }

    func dayKey(_ date: Date) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
    }
}
