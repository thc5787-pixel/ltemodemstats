import Foundation
import ModemCore

/// Plain-text rendering of `ModemStatus` for `lte-modem-stats status`.
enum StatusText {
    static func render(_ status: ModemStatus) -> String {
        var out: [String] = []

        func section(_ title: String, _ rows: [(String, String?)]) {
            out.append("[\(title)]")
            for (label, value) in rows {
                let width = label.unicodeScalars.reduce(0) { $0 + ($1.value > 0x2E80 ? 2 : 1) }
                out.append("  " + label + String(repeating: " ", count: max(1, 14 - width)) + (value ?? "—"))
            }
        }

        if let device = status.device {
            section(L10n.t("设备", "Device"), [
                (L10n.t("型号", "Model"), [device.manufacturer, device.model].compactMap { $0 }.joined(separator: " ")),
                (L10n.t("固件", "Firmware"), device.firmware),
                ("IMEI", device.imei),
                (L10n.t("温度", "Temperature"), status.temperature.map { "\($0) °C" }),
            ])
        }
        if let sim = status.sim {
            section("SIM", [
                (L10n.t("状态", "State"), Labels.simState(sim.state)),
                (L10n.t("本机号", "Number"), sim.phoneNumber),
                ("IMSI", sim.imsi),
                ("ICCID", sim.iccid),
            ])
        }
        if let network = status.network {
            section(L10n.t("网络", "Network"), [
                (L10n.t("运营商", "Operator"), network.operatorName),
                (L10n.t("制式", "Technology"), [network.generation.displayName, network.mode].compactMap { $0 }.joined(separator: " · ")),
                (L10n.t("注册", "Registration"), Labels.registration(network.registration)),
                (L10n.t("频段", "Band"), network.band),
                (L10n.t("带宽", "Bandwidth"), network.bandwidthMHz.map { "\(Labels.number($0)) MHz" }),
                ("EARFCN", network.earfcn.map(String.init)),
                ("PCI", network.pci.map(String.init)),
                ("TAC", network.tac),
                (L10n.t("小区 ID", "Cell ID"), network.cellID),
                ("PLMN", network.plmn),
                (L10n.t("连接状态", "Radio state"), network.radioState.map(Labels.radioState)),
            ])
        }
        if let signal = status.signal {
            section(L10n.t("信号", "Signal"), [
                (L10n.t("信号格", "Bars"), "\(bars(signal.bars)) (\(signal.bars)/4)"),
                ("RSRP", signal.rsrp.map { "\($0) dBm" }),
                ("RSRQ", signal.rsrq.map { "\($0) dB" }),
                ("SINR", signal.sinr.map { "\($0) dB" }),
                ("RSSI", signal.rssi.map { "\($0) dBm" }),
            ])
        }
        if let data = status.data {
            section(L10n.t("数据", "Data"), [
                (L10n.t("连接", "Connection"), data.connected ? L10n.t("已连接", "Connected") : L10n.t("未连接", "Disconnected")),
                ("APN", data.apn),
                ("IPv4", data.ipv4),
                ("IPv6", data.ipv6),
            ])
        }
        return out.joined(separator: "\n")
    }

    static func bars(_ count: Int) -> String {
        let glyphs = ["▂", "▄", "▆", "█"]
        return glyphs.enumerated().map { $0.offset < count ? $0.element : "·" }.joined()
    }
}
