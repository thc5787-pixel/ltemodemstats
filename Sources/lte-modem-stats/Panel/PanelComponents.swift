import AppKit
import ModemCore
import SwiftUI

// Small building blocks shared by the panel sections.

struct PanelSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            content
        }
    }
}

/// Label / value row. Copyable rows copy their value on click.
struct InfoRow: View {
    let label: String
    let value: String?
    var copyable = false
    @Environment(PanelState.self) private var ui

    init(_ label: String, _ value: String?, copyable: Bool = false) {
        self.label = label
        self.value = value
        self.copyable = copyable
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 92, alignment: .leading)
            if copyable, let value {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(value, forType: .string)
                    ui.copiedRow = label
                    Task {
                        try? await Task.sleep(for: .seconds(1.2))
                        if ui.copiedRow == label { ui.copiedRow = nil }
                    }
                } label: {
                    Text(ui.copiedRow == label ? L10n.t("已复制", "Copied") : value)
                        .foregroundStyle(ui.copiedRow == label ? .secondary : .primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .buttonStyle(.plain)
                .help(L10n.t("点击复制", "Click to copy"))
            } else {
                Text(value ?? "—")
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 0)
        }
        .font(.callout)
        .monospacedDigit()
    }
}

struct Metric: View {
    let label: String
    let value: Int?
    let unit: String

    init(_ label: String, _ value: Int?, unit: String) {
        self.label = label
        self.value = value
        self.unit = unit
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value.map(String.init) ?? "—")
                    .font(.title3.weight(.medium))
                    .monospacedDigit()
                Text(unit)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct QuotaBar: View {
    let fraction: Double
    let used: UInt64
    let quotaGB: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ProgressView(value: min(fraction, 1))
                .tint(fraction >= 1 ? .red : fraction >= 0.8 ? .yellow : .accentColor)
            HStack {
                if fraction >= 0.8 {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(fraction >= 1 ? .red : .yellow)
                }
                Text(L10n.t("已用 \(Int((fraction * 100).rounded()))%（\(ByteFormat.bytes(used)) / \(Labels.number(quotaGB)) GB）",
                            "\(Int((fraction * 100).rounded()))% used (\(ByteFormat.bytes(used)) of \(Labels.number(quotaGB)) GB)"))
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}
