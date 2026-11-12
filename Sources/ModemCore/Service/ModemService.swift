import Foundation
import Observation

/// Drives polling and publishes everything the menu bar shows. AT I/O (blocking USB
/// transfers) runs off the main thread; all published state lives on the main actor.
@MainActor
@Observable
public final class ModemService {
    public enum Connection: Equatable, Sendable {
        case connecting
        case connected
        /// No QDC507 on the USB bus.
        case notFound
        /// Another program holds the AT interface.
        case busy
        /// Interface open, but three commands in a row timed out.
        case unresponsive
        case failed(String)
    }

    /// One traffic-rate sample, bytes per second.
    public struct RateSample: Equatable, Sendable {
        public let date: Date
        public let rx: Double
        public let tx: Double
    }

    public private(set) var connection: Connection = .connecting
    public private(set) var status = ModemStatus()
    public private(set) var meter: TrafficMeter
    public private(set) var interfaceName: String?
    /// Per-second rates over the last `rateWindow` seconds.
    public private(set) var rateHistory: [RateSample] = []
    public private(set) var lastUpdate: Date?
    /// Traffic of the current billing cycle; updated every tick.
    public private(set) var cycleTotals = TrafficTotals()
    public let settings: AppSettings

    public static let rateWindow: TimeInterval = 300

    private let reader: ModemReader
    private let historyURL: URL
    private var lastRun: [ModemReader.Group: Date] = [:]
    private var lastAttempt: Date?
    private var atInFlight = false
    private var consecutiveTimeouts = 0
    private var lastSave = Date()
    /// System index of `interfaceName`; a different index under the same name is another NIC.
    private var interfaceIndex: UInt32 = 0
    private var lastInterfaceSearch: Date?
    /// `.device` is read once per connection; after a timeout it is retried from this time on.
    private var deviceRetryAt: Date?
    private var unsavedTraffic = false
    private var timer: Timer?
    /// Rounds in a row each group timed out; its values are dropped once they are this stale.
    private var groupTimeouts: [ModemReader.Group: Int] = [:]
    private static let staleAfterTimeouts = 2
    /// Sum of the billing cycle without today, so the per-second update only adds today.
    @ObservationIgnored private var cycleBase: (startDay: Int, today: String, totals: TrafficTotals)?
    @ObservationIgnored private var handoffObservers: [NSObjectProtocol] = []
    @ObservationIgnored private var loanEnd: Task<Void, Never>?

    public init(settings: AppSettings,
                channel: ATChannel = ATChannel(),
                historyURL: URL = TrafficHistory.defaultURL) {
        self.settings = settings
        self.reader = ModemReader(channel: channel)
        self.historyURL = historyURL
        self.meter = TrafficMeter(history: TrafficHistory.load(from: historyURL))
        updateCycleTotals(at: Date())
    }

    // MARK: - Derived values for the UI

    /// Share of the monthly plan used, or nil without a plan.
    public var quotaFraction: Double? {
        guard settings.monthlyQuotaGB > 0 else { return nil }
        return Double(cycleTotals.total) / (settings.monthlyQuotaGB * 1024 * 1024 * 1024)
    }

    // MARK: - Lifecycle

    public func start() {
        guard timer == nil else { return }
        observeHandoff()
        tick()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// Saves traffic history and releases the AT interface.
    public func stop() {
        timer?.invalidate()
        timer = nil
        handoffObservers.forEach(DistributedNotificationCenter.default().removeObserver)
        handoffObservers = []
        loanEnd?.cancel()
        saveHistory()
        // Also stops an in-flight poll and keeps it from reopening the interface.
        reader.channel.shutdown()
    }

    /// Re-reads every group now (device info included).
    public func refreshNow() {
        lastRun = [:]
        deviceRetryAt = nil
        lastAttempt = nil
        pollModem(at: Date())
    }

    // MARK: - Polling

    // MARK: - CLI handoff

    private func observeHandoff() {
        let center = DistributedNotificationCenter.default()
        handoffObservers = [
            center.addObserver(forName: ATHandoff.release, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.lendInterface() }
            },
            center.addObserver(forName: ATHandoff.done, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.reclaimInterface() }
            },
        ]
    }

    /// The CLI wants the AT interface: release it (an in-flight poll ends as `.busy`).
    private func lendInterface() {
        reader.channel.suspend()
        loanEnd?.cancel()
        loanEnd = Task { [weak self] in
            try? await Task.sleep(for: .seconds(ATHandoff.maxLoan))
            guard !Task.isCancelled else { return }
            self?.reclaimInterface()
        }
    }

    private func reclaimInterface() {
        loanEnd?.cancel()
        loanEnd = nil
        reader.channel.resume()
        // Reconnect on the next tick instead of after the reconnect interval.
        lastAttempt = nil
    }

    private func tick() {
        let now = Date()
        sampleTraffic(at: now)
        updateCycleTotals(at: now)
        pollModem(at: now)
        if unsavedTraffic, now.timeIntervalSince(lastSave) >= 60 {
            saveHistory()
        }
    }

    private func sampleTraffic(at now: Date) {
        let previous = (interfaceName, interfaceIndex)
        locateInterface(at: now)
        if previous != (interfaceName, interfaceIndex) {
            // Another NIC: its counters are not comparable with the old one's.
            meter.record(nil, at: now)
        }
        let counters = interfaceName.flatMap(NetworkInterfaces.counters(for:))
        meter.record(counters, at: now)
        if meter.rxRate > 0 || meter.txRate > 0 { unsavedTraffic = true }

        if counters != nil {
            rateHistory.append(RateSample(date: now, rx: meter.rxRate, tx: meter.txRate))
        }
        rateHistory.removeAll { now.timeIntervalSince($0.date) > Self.rateWindow }
    }

    private func updateCycleTotals(at now: Date) {
        let startDay = settings.billingDay
        let today = meter.dayKey(now)
        if cycleBase?.startDay != startDay || cycleBase?.today != today {
            // Once a day or after a settings change: today is the only day that still grows.
            let cycle = meter.cycle(startDay: startDay, containing: now)
            let todayTotals = meter.today(now)
            cycleBase = (startDay, today, TrafficTotals(rx: cycle.rx - todayTotals.rx, tx: cycle.tx - todayTotals.tx))
        }
        let totals = cycleBase!.totals + meter.today(now)
        if totals != cycleTotals { cycleTotals = totals }
    }

    /// Keeps `interfaceName` pointing at the modem's NIC. A vanished name, or the same name
    /// with a new index (another adapter took it), drops it; while it's missing, the IORegistry
    /// is searched every few seconds rather than every tick.
    private func locateInterface(at now: Date) {
        if let name = interfaceName, if_nametoindex(name) != interfaceIndex {
            interfaceName = nil
            interfaceIndex = 0
        }
        guard interfaceName == nil else { return }
        if let lastInterfaceSearch, now.timeIntervalSince(lastInterfaceSearch) < 5 { return }
        lastInterfaceSearch = now
        if let name = NetworkInterfaces.modemInterface() {
            interfaceName = name
            interfaceIndex = if_nametoindex(name)
        }
    }

    private func pollModem(at now: Date) {
        guard !atInFlight else { return }
        let schedule = ModemSchedule()
        if connection != .connected {
            if let lastAttempt, now.timeIntervalSince(lastAttempt) < schedule.reconnectInterval { return }
            lastAttempt = now
            lastRun = [:]
        }
        var groups = schedule.due(at: now, lastRun: lastRun)
        if let deviceRetryAt, now < deviceRetryAt { groups.remove(.device) }
        guard !groups.isEmpty else { return }

        atInFlight = true
        let reader = reader
        let snapshot = status
        Task.detached(priority: .utility) {
            var updated = snapshot
            let outcome: Result<(ModemStatus, Set<ModemReader.Group>), ATError>
            do {
                let timedOut = try reader.refresh(groups, into: &updated)
                outcome = .success((updated, timedOut))
            } catch let error as ATError {
                outcome = .failure(error)
            } catch {
                outcome = .failure(.notConnected(error.localizedDescription))
            }
            await self.finishPoll(outcome, groups: groups, startedAt: now)
        }
    }

    private func finishPoll(_ outcome: Result<(ModemStatus, Set<ModemReader.Group>), ATError>,
                            groups: Set<ModemReader.Group>, startedAt: Date) {
        atInFlight = false
        switch outcome {
        case let .success((newStatus, timedOut)):
            // Timed-out groups also wait a full interval, so a slow command is not hammered.
            for group in groups { lastRun[group] = startedAt }
            if timedOut.contains(.device) {
                // Read once per connection, so "wait an interval" would mean never: retry later.
                lastRun[.device] = nil
                deviceRetryAt = startedAt.addingTimeInterval(30)
            }
            guard timedOut != groups else {
                // Nothing answered. One such round is not a disconnect; three in a row is.
                consecutiveTimeouts += 1
                if consecutiveTimeouts >= 3 { disconnect(.unresponsive) }
                return
            }
            var newStatus = newStatus
            for group in groups {
                guard timedOut.contains(group) else {
                    groupTimeouts[group] = nil
                    continue
                }
                let count = groupTimeouts[group, default: 0] + 1
                groupTimeouts[group] = count
                // Old values of a group that keeps timing out would look live next to fresh ones.
                if count >= Self.staleAfterTimeouts { ModemReader.clear(group, in: &newStatus) }
            }
            status = newStatus
            connection = .connected
            consecutiveTimeouts = 0
            lastUpdate = Date()

        case .failure(.timeout):
            // `refresh` reports timeouts per group; kept for exhaustiveness.
            consecutiveTimeouts += 1
            if consecutiveTimeouts >= 3 { disconnect(.unresponsive) }

        case .failure(.deviceNotFound):
            disconnect(.notFound)
        case .failure(.busy):
            disconnect(.busy)
        case let .failure(.notConnected(message)):
            disconnect(.failed(message))
        }
    }

    private func disconnect(_ reason: Connection) {
        connection = reason
        consecutiveTimeouts = 0
        groupTimeouts = [:]
        lastRun = [:]
        deviceRetryAt = nil
        // Stale values would look live; keep nothing from the lost connection.
        status = ModemStatus()
        reader.channel.close()
    }

    private func saveHistory() {
        guard unsavedTraffic else { return }
        do {
            try meter.history.save(to: historyURL)
            unsavedTraffic = false
            lastSave = Date()
        } catch {
            // Retried on the next minute tick.
            lastSave = Date()
        }
    }
}
