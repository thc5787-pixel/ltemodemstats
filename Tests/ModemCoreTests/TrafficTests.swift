import Foundation
@testable import ModemCore
import Testing

private let utc: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}()

private func date(_ text: String) -> Date {
    // "2026-11-03 23:59:59"
    let formatter = DateFormatter()
    formatter.calendar = utc
    formatter.timeZone = utc.timeZone
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
    return formatter.date(from: text)!
}

private func counters(_ rx: UInt64, _ tx: UInt64) -> InterfaceCounters {
    InterfaceCounters(rxBytes: rx, txBytes: tx)
}

@Test func firstSampleOnlySetsBaseline() {
    var meter = TrafficMeter(calendar: utc)
    meter.record(counters(6_000_000_000, 1_000_000_000), at: date("2026-11-03 10:00:00"))
    #expect(meter.today(date("2026-11-03 10:00:00")) == TrafficTotals())
    #expect(meter.session == TrafficTotals(rx: 6_000_000_000, tx: 1_000_000_000))
    #expect(meter.rxRate == 0)
}

@Test func accumulatesDeltasAndRates() {
    var meter = TrafficMeter(calendar: utc)
    meter.record(counters(1000, 500), at: date("2026-11-03 10:00:00"))
    meter.record(counters(3000, 900), at: date("2026-11-03 10:00:02"))
    #expect(meter.rxRate == 1000)
    #expect(meter.txRate == 200)
    meter.record(counters(4000, 1000), at: date("2026-11-03 10:00:03"))
    #expect(meter.today(date("2026-11-03 12:00:00")) == TrafficTotals(rx: 3000, tx: 500))
}

@Test func splitsTrafficAcrossMidnight() {
    var meter = TrafficMeter(calendar: utc)
    meter.record(counters(0, 0), at: date("2026-11-03 23:59:58"))
    meter.record(counters(100, 10), at: date("2026-11-03 23:59:59"))
    meter.record(counters(250, 20), at: date("2026-11-04 00:00:01"))
    #expect(meter.history.days["2026-11-03"] == TrafficTotals(rx: 100, tx: 10))
    #expect(meter.history.days["2026-11-04"] == TrafficTotals(rx: 150, tx: 10))
}

@Test func counterResetStartsNewBaseline() {
    var meter = TrafficMeter(calendar: utc)
    meter.record(counters(5000, 5000), at: date("2026-11-03 10:00:00"))
    // Interface recreated after re-plugging: counters restart near zero.
    meter.record(counters(100, 50), at: date("2026-11-03 10:00:01"))
    #expect(meter.today(date("2026-11-03 10:00:01")) == TrafficTotals())
    #expect(meter.rxRate == 0)
    meter.record(counters(300, 60), at: date("2026-11-03 10:00:02"))
    #expect(meter.today(date("2026-11-03 10:00:02")) == TrafficTotals(rx: 200, tx: 10))
}

@Test func missingInterfaceClearsSession() {
    var meter = TrafficMeter(calendar: utc)
    meter.record(counters(100, 100), at: date("2026-11-03 10:00:00"))
    meter.record(nil, at: date("2026-11-03 10:00:01"))
    #expect(meter.session == nil)
    meter.record(counters(200, 200), at: date("2026-11-03 10:00:02"))
    // No delta across the gap: the interface may have been a different one.
    #expect(meter.today(date("2026-11-03 10:00:02")) == TrafficTotals())
}

@Test func billingCycleTotals() {
    let history = TrafficHistory(days: [
        "2026-10-14": TrafficTotals(rx: 1, tx: 0),
        "2026-10-15": TrafficTotals(rx: 10, tx: 0),
        "2026-11-03": TrafficTotals(rx: 100, tx: 5),
        "2026-11-15": TrafficTotals(rx: 1000, tx: 0),
    ])
    let meter = TrafficMeter(history: history, calendar: utc)
    // Cycle starting the 15th, on Nov 3 → Oct 15 … Nov 3.
    #expect(meter.cycle(startDay: 15, containing: date("2026-11-03 12:00:00")) == TrafficTotals(rx: 110, tx: 5))
    // On Nov 15 a new cycle begins.
    #expect(meter.cycle(startDay: 15, containing: date("2026-11-15 00:00:00")).rx == 1000)
    // Calendar month.
    #expect(meter.cycle(startDay: 1, containing: date("2026-11-20 00:00:00")).rx == 1100)
    // Cycle start in January rolls back to December.
    #expect(meter.cycleStart(startDay: 10, containing: date("2027-01-05 00:00:00")) == date("2026-12-10 00:00:00"))
}

@Test func prunesOldDays() {
    var days: [String: TrafficTotals] = [:]
    for day in 0 ..< 405 {
        let key = utc.date(byAdding: .day, value: day, to: date("2025-01-01 00:00:00"))!
        days[TrafficMeter(calendar: utc).dayKey(key)] = TrafficTotals(rx: 1)
    }
    var meter = TrafficMeter(history: TrafficHistory(days: days), calendar: utc)
    meter.record(counters(0, 0), at: date("2026-02-10 00:00:00"))
    meter.record(counters(1, 0), at: date("2026-02-10 00:00:01"))
    #expect(meter.history.days.count == 400)
    #expect(meter.history.days["2025-01-01"] == nil)
    #expect(meter.history.days["2026-02-10"] != nil)
}

@Test func historyRoundTripsThroughFile() throws {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathComponent("traffic.json")
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let history = TrafficHistory(days: ["2026-11-03": TrafficTotals(rx: 6_500_000_000, tx: 1)])
    try history.save(to: url)
    #expect(TrafficHistory.load(from: url) == history)
    #expect(TrafficHistory.load(from: url.appendingPathExtension("missing")) == TrafficHistory())
}

@Test func formatsBytes() {
    #expect(ByteFormat.bytes(0) == "0 B")
    #expect(ByteFormat.bytes(1536) == "1.5 KB")
    #expect(ByteFormat.bytes(6_500_942_618) == "6.1 GB")
    #expect(ByteFormat.bytes(1_064_251_997) == "1015 MB")
    #expect(ByteFormat.rate(1020) == "1020 B/s")
    #expect(ByteFormat.compactRate(1_258_291) == "1.2M")
    #expect(ByteFormat.compactRate(81920) == "\u{2007}80K")
    #expect(ByteFormat.compactRate(512) == "512B")
    #expect(ByteFormat.compactRate(0) == "\u{2007}\u{2007}0B")
    #expect(ByteFormat.compactRate(1000 * 1024) == "1.0M")
    #expect(ByteFormat.compactRate(15 * 1024 * 1024) == "\u{2007}15M")
    // Never five characters, even right below a unit switch.
    #expect(ByteFormat.compactRate(999.6) == "1.0K")
    #expect(ByteFormat.compactRate(1023 * 1024) == "1.0M")
    for value in stride(from: 0.0, through: 3_000_000_000, by: 997.3) where Int(value) % 7 == 0 {
        #expect(ByteFormat.compactRate(value).count == 4)
    }
}
