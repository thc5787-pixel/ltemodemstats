import Foundation

/// Localized display texts for modem states, shared by the panel and the CLI.
public enum Labels {
    public static func number(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }

    public static func totals(_ totals: TrafficTotals) -> String {
        "\(ByteFormat.bytes(totals.total))（↓ \(ByteFormat.bytes(totals.rx)) ↑ \(ByteFormat.bytes(totals.tx))）"
    }

    public static func simState(_ state: SIMInfo.State) -> String {
        switch state {
        case .ready: L10n.t("就绪", "Ready")
        case .pinRequired: L10n.t("需要 PIN", "PIN required")
        case .pukRequired: L10n.t("需要 PUK", "PUK required")
        case .notInserted: L10n.t("未插卡", "Not inserted")
        case .error: L10n.t("异常", "Error")
        }
    }

    public static func registration(_ registration: Registration) -> String {
        switch registration {
        case .home: L10n.t("已注册", "Registered")
        case .roaming: L10n.t("已注册（漫游）", "Registered (roaming)")
        case .searching: L10n.t("搜索中", "Searching")
        case .denied: L10n.t("被拒绝", "Denied")
        case .notRegistered: L10n.t("未注册", "Not registered")
        case .unknown: L10n.t("未知", "Unknown")
        }
    }

    public static func radioState(_ state: String) -> String {
        switch state {
        case "NOCONN": L10n.t("空闲", "Idle")
        case "CONNECT": L10n.t("传输中", "Active")
        case "LIMSRV": L10n.t("受限服务", "Limited service")
        case "SEARCH": L10n.t("搜索中", "Searching")
        default: state
        }
    }
}
