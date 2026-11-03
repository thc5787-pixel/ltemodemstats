import AppKit
import Charts
import ModemCore
import SwiftUI

/// Download / upload rate over the last five minutes. Two series: legend above
/// (with current values), validated blue/orange pair, hover shows both values.
struct RateChart: View {
    let samples: [ModemService.RateSample]
    let rx: Double
    let tx: Double
    let ui: PanelState

    static let download = Color(nsColor: .dynamic(light: 0x2A78D6, dark: 0x3987E5))
    static let upload = Color(nsColor: .dynamic(light: 0xEB6834, dark: 0xD95926))

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            legend
            if samples.count < 2 {
                Text(L10n.t("正在收集网速…", "Collecting rates…"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 72)
            } else {
                chart.frame(height: 72).padding(.bottom, 6)
            }
        }
    }

    /// While hovering, the legend shows the hovered point instead of the live rate.
    private var hovered: ModemService.RateSample? {
        guard let date = ui.hoveredRateDate else { return nil }
        return samples.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
    }

    private var legend: some View {
        let point = hovered
        return HStack(spacing: 14) {
            LegendItem(color: Self.download, label: L10n.t("下载", "Down"), value: ByteFormat.rate(point?.rx ?? rx))
            LegendItem(color: Self.upload, label: L10n.t("上传", "Up"), value: ByteFormat.rate(point?.tx ?? tx))
            Spacer(minLength: 0)
            Text(point.map { $0.date.formatted(date: .omitted, time: .standard) } ?? L10n.t("最近 5 分钟", "Last 5 min"))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    private var yMax: Double {
        max(samples.map { max($0.rx, $0.tx) }.max() ?? 0, 1024) * 1.1
    }

    private var chart: some View {
        Chart {
            ForEach(samples, id: \.date) { sample in
                // Upload first so download, the one people watch, draws on top where they overlap.
                LineMark(x: .value(L10n.t("时间", "Time"), sample.date), y: .value(L10n.t("网速", "Rate"), sample.tx),
                         series: .value("direction", "up"))
                    .foregroundStyle(Self.upload)
                LineMark(x: .value(L10n.t("时间", "Time"), sample.date), y: .value(L10n.t("网速", "Rate"), sample.rx),
                         series: .value("direction", "down"))
                    .foregroundStyle(Self.download)
            }
            .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            if let point = hovered {
                RuleMark(x: .value(L10n.t("时间", "Time"), point.date))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .foregroundStyle(Color.secondary.opacity(0.5))
                PointMark(x: .value(L10n.t("时间", "Time"), point.date), y: .value(L10n.t("网速", "Rate"), point.rx))
                    .symbolSize(30).foregroundStyle(Self.download)
                PointMark(x: .value(L10n.t("时间", "Time"), point.date), y: .value(L10n.t("网速", "Rate"), point.tx))
                    .symbolSize(30).foregroundStyle(Self.upload)
            }
        }
        .chartLegend(.hidden)
        .chartYScale(domain: 0 ... yMax)
        .chartXScale(domain: (samples.last!.date.addingTimeInterval(-ModemService.rateWindow)) ... samples.last!.date)
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Color.secondary.opacity(0.3))
                AxisValueLabel {
                    if let rate = value.as(Double.self) {
                        Text(ByteFormat.compactRate(rate).trimmingCharacters(in: CharacterSet(charactersIn: "\u{2007}")))
                    }
                }
                .font(.caption2)
                .foregroundStyle(Color.secondary)
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case let .active(location):
                            guard let plot = proxy.plotFrame else { return }
                            ui.hoveredRateDate = proxy.value(atX: location.x - geometry[plot].origin.x)
                        case .ended:
                            ui.hoveredRateDate = nil
                        }
                    }
            }
        }
    }
}

struct LegendItem: View {
    let color: Color
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 1)
                .fill(color)
                .frame(width: 10, height: 3)
            Text(label)
                .foregroundStyle(.secondary)
            Text(value)
                .monospacedDigit()
        }
        .font(.callout)
    }
}

private extension NSColor {
    /// A color that follows the light / dark appearance.
    static func dynamic(light: UInt32, dark: UInt32) -> NSColor {
        NSColor(name: nil) { appearance in
            let hex = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                           green: CGFloat((hex >> 8) & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255,
                           alpha: 1)
        }
    }
}
