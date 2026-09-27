import SwiftUI
import CubbyCore

/// 设置 › 隐私
struct PrivacySettingsPane: View {
    @Bindable var settings: AppSettings

    @State private var permissions = PermissionMonitor()

    var body: some View {
        Form {
            Section {
                // 状态统一由 PermissionMonitor 轮询；按钮文案随状态变化（见 PermissionState）
                PermissionRow(
                    title: "Clipboard access",
                    systemImage: "doc.on.clipboard",
                    state: permissions.pasteboard,
                    isBusy: permissions.isRequestingPasteboard
                ) {
                    Task { await permissions.requestPasteboardAccess() }
                }
                PermissionRow(
                    title: "Accessibility",
                    systemImage: "accessibility",
                    state: permissions.accessibility,
                    action: AccessibilityAuthorization.requestOrOpenSettings
                )
                // 只在授权失效时加入：Form 会为内容为空的行保留一行空白
                if permissions.isAccessibilityStale {
                    AccessibilityRepairGuide()
                }
                PermissionRow(
                    title: "Screen Recording",
                    systemImage: "rectangle.dashed.badge.record",
                    state: permissions.screenRecording,
                    action: ScreenRecordingAuthorization.requestOrOpenSettings
                )
            } header: {
                Text("Permissions")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Cubby uses clipboard access to record history and Accessibility to paste directly.")
                    Text("Screen Recording is only used when you take a screenshot.")
                }
                .foregroundStyle(.secondary)
            }

            Section {
                Toggle(isOn: $settings.isPaused) {
                    Text("Pause recording")
                    Text("Nothing you copy while paused is saved")
                }
                Toggle(isOn: $settings.ignoresSecrets) {
                    Text("Don't record likely secrets and tokens")
                    Text("API keys, private keys, JWTs and more, even from a terminal or browser")
                }
            } footer: {
                Label(
                    "Content marked as concealed or transient, like passwords, is never recorded.",
                    systemImage: "lock.fill"
                )
                .foregroundStyle(.secondary)
            }

            IgnoredAppsSection(settings: settings)
        }
        .formStyle(.grouped)
        .task { await permissions.run() }
    }
}
