import Foundation

/// What the status item shows for a given state. Pure, so it can be tested.
public struct MenuBarPresentation: Equatable, Sendable {
    public enum Tint: Equatable, Sendable {
        case none
        /// ≥ 80 % of the monthly plan used.
        case warning
        /// Plan used up.
        case critical
    }

    /// 0…4 filled bars.
    public var bars: Int
    /// False draws every bar dimmed (no usable service).
    public var active: Bool
    /// `"4G"`, `"无卡"`, `"占用"`, …
    public var label: String
    /// `"↓1.2M ↑80K"`, or nil when hidden or no interface.
    public var rates: String?
    public var tint: Tint
    public var tooltip: String

    public init(connection: ModemService.Connection,
                status: ModemStatus,
                rates: (rx: Double, tx: Double)?,
                showRates: Bool,
                quotaFraction: Double?) {
        bars = 0
        active = false
        self.rates = showRates ? rates.map { "↓\(ByteFormat.compactRate($0.rx)) ↑\(ByteFormat.compactRate($0.tx))" } : nil
        tint = switch quotaFraction {
        case let fraction? where fraction >= 1: .critical
        case let fraction? where fraction >= 0.8: .warning
        default: .none
        }

        let detail: String
        switch connection {
        case .connecting:
            label = "…"
            detail = L10n.t("正在连接模块", "Connecting to the modem")
        case .notFound:
            label = L10n.t("无设备", "No modem")
            detail = L10n.t("未检测到模块", "Modem not found")
        case .busy:
            label = L10n.t("占用", "Busy")
            detail = L10n.t("AT 接口被其他程序占用，仅统计流量", "AT interface in use by another program; traffic only")
        case .unresponsive:
            label = "!"
            detail = L10n.t("模块无响应", "Modem not responding")
        case let .failed(message):
            label = "!"
            detail = message
        case .connected:
            let sim = status.sim?.state
            let network = status.network
            if let sim, sim != .ready {
                label = sim == .notInserted ? L10n.t("无卡", "No SIM") : "SIM"
                detail = sim == .notInserted ? L10n.t("未插 SIM 卡", "No SIM card") : L10n.t("SIM 卡需要解锁", "SIM card is locked")
            } else if let network, !network.registration.isRegistered {
                label = L10n.t("无服务", "No service")
                detail = L10n.t("未注册到网络", "Not registered on the network")
            } else {
                active = true
                bars = status.signal?.bars ?? 0
                label = network?.generation.displayName ?? "…"
                detail = [network?.operatorName, network?.band].compactMap { $0 }.joined(separator: " · ")
            }
        }

        var lines = ["LTE Modem Stats", detail]
        switch tint {
        case .warning: lines.append(L10n.t("本月流量已超过套餐 80%", "Over 80% of this month's data plan used"))
        case .critical: lines.append(L10n.t("本月流量已用完套餐", "This month's data plan is used up"))
        case .none: break
        }
        tooltip = lines.filter { !$0.isEmpty }.joined(separator: "\n")
    }
}
