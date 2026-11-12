import AppKit
import ModemCore
import SwiftUI

/// Transient UI state of the panel. Lives in an @Observable object instead of `@State`:
/// the macOS 27 SDK implements `@State` as a macro whose plugin ships only with Xcode,
/// so `@State` does not compile with the Command Line Tools.
@MainActor
@Observable
final class PanelState {
    /// Label of the row whose value was just copied.
    /// Time under the pointer in the traffic chart.
    var hoveredRateDate: Date?
    var copiedRow: String?
    var detailsExpanded = false
    var settingsExpanded = false
}

struct PanelView: View {
    let service: ModemService
    let ui: PanelState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if service.connection == .connected {
                signalSection
            }
            trafficSection
            if service.connection == .connected {
                networkSection
                detailsSection
            }
            SettingsSection(settings: service.settings, ui: ui)
            Divider()
            footer
        }
        .padding(14)
        .frame(width: 340)
        .environment(ui)
        // Texts come from L10n, which SwiftUI cannot observe; rebuild on a language change.
        .id(service.settings.language)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: headerIcon.name)
                .foregroundStyle(headerIcon.color)
            VStack(alignment: .leading, spacing: 1) {
                Text(service.status.device?.model ?? "LTE Modem Stats")
                    .font(.headline)
                Text(connectionText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var headerIcon: (name: String, color: Color) {
        switch service.connection {
        case .connected: ("antenna.radiowaves.left.and.right", .green)
        case .connecting: ("ellipsis.circle", .secondary)
        case .notFound: ("cable.connector.slash", .secondary)
        case .busy: ("lock.circle", .orange)
        case .unresponsive, .failed: ("exclamationmark.triangle", .orange)
        }
    }

    private var connectionText: String {
        switch service.connection {
        case .connecting: L10n.t("正在连接…", "Connecting…")
        case .connected:
            [
                service.status.network?.operatorName,
                service.status.network.flatMap { $0.generation == .none ? nil : $0.generation.displayName },
                service.status.network.map { Labels.registration($0.registration) },
                service.status.network?.radioState.map(Labels.radioState),
            ].compactMap { $0 }.joined(separator: " · ")
        case .notFound: L10n.t("未检测到模块（2c7c:0125）", "Modem not found (2c7c:0125)")
        case .busy: L10n.t("AT 接口被其他程序占用，仅统计流量", "AT interface in use by another program; traffic only")
        case .unresponsive: L10n.t("模块无响应", "Modem not responding")
        case let .failed(message): message
        }
    }

    // MARK: - Sections

    private var networkSection: some View {
        let network = service.status.network
        let data = service.status.data
        return PanelSection(L10n.t("网络", "Network")) {
            InfoRow(L10n.t("频段", "Band"), [network?.band, network?.bandwidthMHz.map { "\(Labels.number($0)) MHz" }, network?.mode]
                .compactMap { $0 }.joined(separator: " · ").nilIfEmpty)
            InfoRow("PCI / EARFCN", [network?.pci, network?.earfcn].compactMap { $0.map(String.init) }
                .joined(separator: " / ").nilIfEmpty)
            InfoRow(L10n.t("TAC / 小区", "TAC / Cell"), [network?.tac, network?.cellID].compactMap { $0 }
                .joined(separator: " / ").nilIfEmpty)
            InfoRow(L10n.t("数据", "Data"), data.map { data in
                data.connected ? [data.apn, data.ipv4].compactMap { $0 }.joined(separator: " · ") : L10n.t("未连接", "Disconnected")
            }, copyValue: data?.connected == true ? data?.ipv4 : nil)
            InfoRow("IPv6", data?.ipv6, copyable: true)
        }
    }

    /// Identity details change rarely; collapsed by default to keep the panel short.
    private var detailsSection: some View {
        @Bindable var ui = ui
        let device = service.status.device
        let sim = service.status.sim
        return DisclosureGroup(L10n.t("设备与 SIM", "Device & SIM"), isExpanded: $ui.detailsExpanded) {
            VStack(alignment: .leading, spacing: 4) {
                InfoRow(L10n.t("固件", "Firmware"), device?.firmware)
                InfoRow("IMEI", device?.imei, copyable: true)
                InfoRow(L10n.t("温度", "Temperature"), service.status.temperature.map { "\($0) °C" })
                InfoRow("SIM", sim.map { Labels.simState($0.state) })
                InfoRow(L10n.t("本机号", "Number"), sim?.phoneNumber, copyable: true)
                InfoRow("IMSI", sim?.imsi, copyable: true)
                InfoRow("ICCID", sim?.iccid, copyable: true)
            }
            .padding(.top, 6)
        }
        .font(.callout)
    }

    private var signalSection: some View {
        let signal = service.status.signal
        return PanelSection(L10n.t("信号", "Signal")) {
            HStack(spacing: 0) {
                Metric("RSRP", signal?.rsrp, unit: "dBm")
                Metric("RSRQ", signal?.rsrq, unit: "dB")
                Metric("SINR", signal?.sinr, unit: "dB")
                Metric("RSSI", signal?.rssi, unit: "dBm")
            }
        }
    }

    private var trafficSection: some View {
        let meter = service.meter
        let cycle = service.cycleTotals
        return PanelSection(L10n.t("流量", "Traffic")) {
            if let interface = service.interfaceName, meter.session != nil {
                RateChart(samples: service.rateHistory, rx: meter.rxRate, tx: meter.txRate, ui: ui)
                InfoRow(L10n.t("本次连接", "Session"), meter.session.map(Labels.totals))
                InfoRow(L10n.t("今日", "Today"), Labels.totals(meter.today()))
                InfoRow(L10n.t("本月", "This cycle"), Labels.totals(cycle))
                if let fraction = service.quotaFraction {
                    QuotaBar(fraction: fraction, used: cycle.total, quotaGB: service.settings.monthlyQuotaGB)
                }
                InfoRow(L10n.t("网卡", "Interface"), interface)
            } else {
                Text(L10n.t("未找到模块网卡", "Modem network interface not found"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var footer: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                if let lastUpdate = service.lastUpdate {
                    Text(L10n.t("更新于 ", "Updated ") + lastUpdate.formatted(date: .omitted, time: .standard))
                }
                Text("v" + AppVersion.display)
                    .textSelection(.enabled)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .monospacedDigit()
            Spacer()
            Button(L10n.t("刷新", "Refresh")) { service.refreshNow() }
            Button(L10n.t("退出", "Quit")) { NSApp.terminate(nil) }
        }
        .controlSize(.small)
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
