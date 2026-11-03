import Foundation

/// Reads modem state in groups so callers can refresh them at different rates.
/// Only sends read-only queries.
public struct ModemReader: Sendable {
    public enum Group: CaseIterable, Sendable {
        /// Model, firmware, IMEI. Once per connection.
        case device
        /// SIM state, IMSI, ICCID, number.
        case sim
        /// Operator, registration, cell and signal.
        case radio
        /// Data context, APN and IP.
        case data
        case temperature
    }

    public let channel: ATChannel
    /// Per-command reply timeout.
    public let commandTimeout: TimeInterval

    public init(channel: ATChannel, commandTimeout: TimeInterval = 5) {
        self.channel = channel
        self.commandTimeout = commandTimeout
    }

    /// Updates the given groups of `status` and returns the groups whose read timed out;
    /// those keep their previous values. Throws only when the AT interface is lost.
    /// A command answered with `ERROR` just leaves its fields nil.
    @discardableResult
    public func refresh(_ groups: Set<Group>, into status: inout ModemStatus) throws -> Set<Group> {
        var timedOut = Set<Group>()
        for group in Group.allCases where groups.contains(group) {
            do {
                try read(group, into: &status)
            } catch ATError.timeout {
                // One slow command must not discard the groups that did answer.
                timedOut.insert(group)
            }
        }
        return timedOut
    }

    /// Reads every group; groups that timed out are left nil and returned alongside.
    public func readAll() throws -> (status: ModemStatus, timedOut: Set<Group>) {
        var status = ModemStatus()
        let timedOut = try refresh(Set(Group.allCases), into: &status)
        return (status, timedOut)
    }

    private func read(_ group: Group, into status: inout ModemStatus) throws {
        switch group {
        case .device: status.device = try readDevice()
        case .sim: status.sim = try readSIM()
        case .radio:
            let (network, signal) = try readRadio()
            status.network = network
            status.signal = signal
        case .data: status.data = try readData()
        case .temperature: status.temperature = try query("AT+QTEMP").flatMap(ATParsers.temperature)
        }
    }

    // MARK: - Groups

    func readDevice() throws -> DeviceInfo {
        DeviceInfo(
            manufacturer: try query("AT+CGMI").flatMap(ATParsers.bareValue),
            model: try query("AT+CGMM").flatMap(ATParsers.bareValue),
            firmware: try query("AT+QGMR").flatMap(ATParsers.bareValue),
            imei: try query("AT+GSN").flatMap(ATParsers.imei)
        )
    }

    func readSIM() throws -> SIMInfo {
        let pin = try channel.execute("AT+CPIN?", timeout: commandTimeout)
        let state = pin.isOK ? ATParsers.simState(pin.lines) : ATParsers.simState(error: pin.errorMessage)
        guard state == .ready else { return SIMInfo(state: state) }
        return SIMInfo(
            state: state,
            imsi: try query("AT+CIMI").flatMap(ATParsers.imsi),
            iccid: try query("AT+QCCID").flatMap(ATParsers.iccid),
            phoneNumber: try query("AT+CNUM").flatMap(ATParsers.phoneNumber)
        )
    }

    func readRadio() throws -> (NetworkInfo, SignalInfo) {
        let (operatorName, generation) = try query("AT+COPS?").map(ATParsers.operatorInfo) ?? (nil, .none)
        var registration = try query("AT+CEREG?").map { ATParsers.registration($0) } ?? .unknown
        if !registration.isRegistered, generation != .lte {
            // 2G/3G registration only matters when not on LTE.
            let legacy = try query("AT+CREG?").map { ATParsers.registration($0, prefix: "+CREG") } ?? .unknown
            if legacy.isRegistered { registration = legacy }
        }
        let mode = try query("AT+QNWINFO").flatMap(ATParsers.networkMode)
        let cell = try query("AT+QENG=\"servingcell\"").flatMap(ATParsers.servingCell)
        let rssi = try query("AT+CSQ").flatMap(ATParsers.rssi)

        let network = NetworkInfo(
            operatorName: operatorName,
            generation: generation,
            registration: registration,
            mode: mode?.mode,
            plmn: mode?.plmn,
            band: mode?.band,
            earfcn: cell?.earfcn ?? mode?.channel,
            pci: cell?.pci,
            tac: cell?.tac,
            cellID: cell?.cellID,
            bandwidthMHz: cell?.bandwidthMHz,
            radioState: cell?.state
        )
        let signal = SignalInfo(
            rsrp: cell?.rsrp,
            rsrq: cell?.rsrq,
            sinr: cell?.sinr,
            rssi: cell?.rssi ?? rssi
        )
        return (network, signal)
    }

    func readData() throws -> DataInfo {
        let active = try query("AT+CGACT?").map(ATParsers.activeContexts) ?? []
        let apns = try query("AT+CGDCONT?").map(ATParsers.apns) ?? [:]
        let addresses = try query("AT+CGPADDR").map(ATParsers.addresses) ?? [:]
        return ATParsers.dataInfo(active: active, apns: apns, addresses: addresses)
    }

    /// Result lines, or nil when the modem answered with an error.
    private func query(_ command: String) throws -> [String]? {
        let response = try channel.execute(command, timeout: commandTimeout)
        return response.isOK ? response.lines : nil
    }
}
