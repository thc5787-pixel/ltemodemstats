import Foundation

/// Everything shown in the menu bar panel. Each section is nil until it has been read;
/// each field is nil when the modem did not report it.
public struct ModemStatus: Codable, Equatable, Sendable {
    public var device: DeviceInfo?
    public var sim: SIMInfo?
    public var network: NetworkInfo?
    public var signal: SignalInfo?
    public var data: DataInfo?
    /// Highest of the module's temperature sensors, °C.
    public var temperature: Int?

    public init() {}
}

public struct DeviceInfo: Codable, Equatable, Sendable {
    public var manufacturer: String?
    public var model: String?
    public var firmware: String?
    public var imei: String?
}

public struct SIMInfo: Codable, Equatable, Sendable {
    public enum State: String, Codable, Sendable {
        case ready, pinRequired, pukRequired, notInserted, error
    }

    public var state: State
    public var imsi: String?
    public var iccid: String?
    public var phoneNumber: String?
}

public enum Registration: String, Codable, Sendable {
    case notRegistered, home, searching, denied, unknown, roaming

    /// 3GPP `<stat>` of `+CREG` / `+CEREG`.
    init(stat: Int) {
        switch stat {
        case 0: self = .notRegistered
        case 1: self = .home
        case 2: self = .searching
        case 3: self = .denied
        case 5: self = .roaming
        default: self = .unknown
        }
    }

    public var isRegistered: Bool { self == .home || self == .roaming }
}

public enum RadioGeneration: String, Codable, Sendable {
    case lte = "4G", umts = "3G", gsm = "2G", none

    public var displayName: String {
        self == .none ? L10n.t("无服务", "No service") : rawValue
    }

    /// `<AcT>` of `+COPS`.
    init(accessTechnology: Int) {
        switch accessTechnology {
        case 7: self = .lte
        case 2, 4, 5, 6: self = .umts
        case 0, 1, 3: self = .gsm
        default: self = .none
        }
    }

    /// `<act>` of `+QNWINFO`: `"FDD LTE"`, `"WCDMA"`, `"GSM"`, `"HSPA+"`, …
    init(networkMode: String) {
        let mode = networkMode.uppercased()
        if mode.contains("LTE") {
            self = .lte
        } else if ["WCDMA", "HSDPA", "HSUPA", "HSPA", "TDSCDMA", "TD-SCDMA", "UMTS", "EVDO", "HDR"].contains(where: mode.contains) {
            self = .umts
        } else if ["GSM", "GPRS", "EDGE", "CDMA"].contains(where: mode.contains) {
            self = .gsm
        } else {
            self = .none
        }
    }
}

public struct NetworkInfo: Codable, Equatable, Sendable {
    public var operatorName: String?
    public var generation: RadioGeneration
    /// LTE registration (`+CEREG`), the one that matters on LTE-only SIMs.
    public var registration: Registration
    /// `"FDD LTE"`, `"TDD LTE"`, …
    public var mode: String?
    /// `"46011"`.
    public var plmn: String?
    /// `"LTE BAND 3"`.
    public var band: String?
    public var earfcn: Int?
    public var pci: Int?
    /// Hex, as the modem reports it.
    public var tac: String?
    public var cellID: String?
    /// Downlink bandwidth, MHz.
    public var bandwidthMHz: Double?
    /// `"NOCONN"` (idle), `"CONNECT"` (traffic), `"LIMSRV"`, `"SEARCH"`.
    public var radioState: String?
}

public struct SignalInfo: Codable, Equatable, Sendable {
    public var rsrp: Int?
    public var rsrq: Int?
    public var sinr: Int?
    /// dBm.
    public var rssi: Int?

    /// 0…4, from RSRP on LTE, otherwise from RSSI.
    public var bars: Int {
        if let rsrp {
            switch rsrp {
            case (-85)...: return 4
            case (-95)...: return 3
            case (-105)...: return 2
            case (-115)...: return 1
            default: return 0
            }
        }
        if let rssi {
            switch rssi {
            case (-75)...: return 4
            case (-85)...: return 3
            case (-95)...: return 2
            case (-105)...: return 1
            default: return 0
            }
        }
        return 0
    }
}

public struct DataInfo: Codable, Equatable, Sendable {
    public var connected: Bool
    public var apn: String?
    public var ipv4: String?
    public var ipv6: String?
}
