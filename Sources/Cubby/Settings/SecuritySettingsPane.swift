import SwiftUI
import CubbyCore

/// 设置 › 剪贴板安全（SettingsSecurity 设计稿，去掉「发现被替换时」与 IBAN）：总开关与 30 天统计、守护的内容、
/// 提示（粘贴后核对、输入监控）、安全记录、引导到系统设置的「从其他 App 粘贴」
struct SecuritySettingsPane: View {
    @Bindable var settings: AppSettings
    let addressGuard: AddressGuardController

    @State private var inputMonitoringAllowed = InputMonitor.isAuthorized

    /// 输入监控授权的轮询间隔（用户在系统设置里授权后自动更新）
    private static let refreshInterval: Duration = .seconds(1.5)

    var body: some View {
        Form {
            Section {
                GuardHeader(settings: settings, summary: addressGuard.summary)
            }

            Section {
                GuardedKindChips(settings: settings)
            } header: {
                Text("Guarded Content", comment: "Settings › Security section header")
            }
            .disabled(!settings.addressGuardEnabled)

            Section {
                Toggle(isOn: $settings.verifiesPastes) {
                    Text(
                        "Show the check result after pasting an address",
                        comment: "Settings › Security toggle: show the paste check HUD")
                }
                InputMonitoringRow(isAllowed: inputMonitoringAllowed)
            } header: {
                Text("Hints", comment: "Settings › Security section header")
            }
            .disabled(!settings.addressGuardEnabled)

            Section {
                SecurityLogTable(entries: addressGuard.log.entries)
            } header: {
                Text("Security Log", comment: "Settings › Security section header")
            } footer: {
                ReadProtectionFooter()
            }
        }
        .formStyle(.grouped)
        .task { await pollInputMonitoring() }
    }

    /// 页面显示时同步一次；之后轮询授权状态（只是一次本地查询），状态变了才让守护装上 / 拆下按键监听
    private func pollInputMonitoring() async {
        addressGuard.refreshInputMonitoring?()
        while !Task.isCancelled {
            let allowed = InputMonitor.isAuthorized
            if allowed != inputMonitoringAllowed {
                inputMonitoringAllowed = allowed
                addressGuard.refreshInputMonitoring?()
            }
            try? await Task.sleep(for: Self.refreshInterval)
        }
    }
}

/// 顶部：盾牌图标、「地址守护已开启 / 已关闭」、近 30 天统计、总开关
private struct GuardHeader: View {
    @Bindable var settings: AppSettings
    let summary: SecurityLog.Summary

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let isOn = settings.addressGuardEnabled
        HStack(spacing: 14) {
            Image(systemName: isOn ? "checkmark.shield" : "shield.slash")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(isOn ? SecurityPalette.greenText(colorScheme) : Color.secondary)
                .frame(width: 40, height: 40)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(isOn ? SecurityPalette.green.opacity(0.22) : Color.primary.opacity(0.08))
                )
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(isOn ? Self.onTitle : Self.offTitle)
                    .font(.system(size: FontSize.callout, weight: .semibold))
                Text(isOn ? Self.summaryText(summary) : Self.offSubtitle)
                    .font(.system(size: FontSize.footnote))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Toggle(isOn: $settings.addressGuardEnabled) {
                Text("Address guard", comment: "Accessibility label of the address guard switch")
            }
            .toggleStyle(.switch)
            .labelsHidden()
        }
        .padding(.vertical, 4)
    }

    private static var onTitle: String {
        String(localized: "Address guard is on", comment: "Settings › Security header")
    }

    private static var offTitle: String {
        String(localized: "Address guard is off", comment: "Settings › Security header")
    }

    private static var offSubtitle: String {
        String(localized: "Cubby won't check the addresses you copy", comment: "Settings › Security header, guard off")
    }

    /// 「近 30 天发现 1 次替换，已提醒；核验了 42 次粘贴」
    static func summaryText(_ summary: SecurityLog.Summary) -> String {
        let tampered =
            summary.tampered == 0
            ? String(localized: "No replacements in the last 30 days", comment: "Settings › Security summary")
            : String(
                localized: "Found \(summary.tampered) replacements in the last 30 days and warned you",
                comment: "Settings › Security summary. %lld = replacements")
        let verified = String(
            localized: "\(summary.verifiedPastes) pastes verified",
            comment: "Settings › Security summary. %lld = pastes checked after pasting from Cubby")
        return String(
            localized: "\(tampered); \(verified)", comment: "Settings › Security summary: joins the two counts")
    }
}

/// 「更准确地判断是不是你复制的」：输入监控的状态与「去授权」
private struct InputMonitoringRow: View {
    let isAllowed: Bool

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(
                    "Tell more accurately whether you copied it",
                    comment: "Settings › Security: Input Monitoring row title")
                Text(
                    "Needs Input Monitoring. Cubby only notices ⌘C and ⌘X and never records what you type. Without it, very fast replacements may go unnoticed.",
                    comment: "Settings › Security: Input Monitoring row description"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            HStack(spacing: 5) {
                Circle()
                    .fill(isAllowed ? Color.green : Color.orange)
                    .frame(width: 7, height: 7)
                Text(isAllowed ? Self.allowed : Self.notAllowed)
                    .foregroundStyle(isAllowed ? Color.green : Color.orange)
            }
            .font(.system(size: FontSize.footnote))
            .fixedSize()
            if !isAllowed {
                Button("Grant Access", action: InputMonitor.requestAccess)
            }
        }
    }

    private static var allowed: String {
        String(localized: "Allowed", comment: "Permission status, same wording as System Settings")
    }

    private static var notAllowed: String {
        String(localized: "Not allowed", comment: "Input Monitoring status, same wording as System Settings")
    }
}

/// 底部说明：macOS 不告诉应用谁读了剪贴板，引导到系统设置的「从其他 App 粘贴」
private struct ReadProtectionFooter: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(
                "macOS doesn't tell apps who reads the clipboard. To keep other apps from reading it, go to System Settings › Privacy & Security › Paste from Other Apps and set apps you don't recognize to Ask.",
                comment: "Settings › Security footer"
            )
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            Button("Open System Settings") { PasteboardAccess.openSettings() }
                .buttonStyle(.link)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
