import ModemCore
import SwiftUI

struct SettingsSection: View {
    @Bindable var settings: AppSettings
    @Bindable var ui: PanelState

    var body: some View {
        DisclosureGroup(L10n.t("设置", "Settings"), isExpanded: $ui.settingsExpanded) {
            // Two columns so every control starts at the same x, whatever the label length.
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                GridRow {
                    Toggle(L10n.t("开机启动", "Launch at login"), isOn: $settings.launchAtLogin)
                        .gridCellColumns(2)
                }
                if let error = settings.launchAtLoginError {
                    GridRow {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .gridCellColumns(2)
                    }
                }
                if settings.launchAtLogin, settings.launchAtLoginNeedsApproval {
                    GridRow {
                        HStack(spacing: 6) {
                            Text(L10n.t("需要在系统设置的“登录项”中允许", "Allow it in System Settings › Login Items"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Button(L10n.t("打开", "Open")) { AppLoginItem.openSystemSettings() }
                                .controlSize(.mini)
                        }
                        .gridCellColumns(2)
                    }
                }
                GridRow {
                    Toggle(L10n.t("菜单栏显示网速", "Show rates in menu bar"), isOn: $settings.showRateInMenuBar)
                        .gridCellColumns(2)
                }
                GridRow {
                    Text(L10n.t("语言", "Language"))
                    Picker(L10n.t("语言", "Language"), selection: $settings.language) {
                        Text(L10n.t("跟随系统", "System")).tag(AppLanguage.system)
                        Text("中文").tag(AppLanguage.chinese)
                        Text("English").tag(AppLanguage.english)
                    }
                    .labelsHidden()
                }
                GridRow {
                    Text(L10n.t("月结日", "Plan resets on"))
                    HStack(spacing: 6) {
                        Text(L10n.t("每月 \(settings.billingDay) 日", "day \(settings.billingDay)"))
                            .monospacedDigit()
                        Stepper(L10n.t("月结日", "Plan resets on"), value: $settings.billingDay, in: 1 ... 28)
                            .labelsHidden()
                    }
                }
                GridRow {
                    Text(L10n.t("月套餐", "Monthly plan"))
                    HStack(spacing: 6) {
                        TextField("0", value: $settings.monthlyQuotaGB, format: .number)
                            .frame(width: 60)
                            .multilineTextAlignment(.trailing)
                        Text(L10n.t("GB（0 = 不限）", "GB (0 = unlimited)"))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.top, 6)
        }
        .font(.callout)
        .controlSize(.small)
    }
}
