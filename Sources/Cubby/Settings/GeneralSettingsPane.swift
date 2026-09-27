import SwiftUI
import CubbyCore

/// 设置 › 通用
struct GeneralSettingsPane: View {
    @Bindable var settings: AppSettings
    let onShortcutRecordingChange: (Bool) -> Void

    @State private var permissions = PermissionMonitor()

    var body: some View {
        Form {
            Section {
                LabeledContent("Keyboard shortcut") {
                    ShortcutRecorder(
                        hotKey: $settings.hotKey,
                        reservations: screenshotReservation,
                        onRecordingChange: onShortcutRecordingChange
                    )
                }
                Picker("Panel position", selection: $settings.panelPosition) {
                    ForEach(PanelPosition.allCases, id: \.self) { position in
                        Text(position.displayName).tag(position)
                    }
                }
            } header: {
                Text("Shortcut & Panel")
            }

            Section {
                Picker("When you choose an item", selection: $settings.pasteDirectly) {
                    Text("Paste into the current app").tag(true)
                    Text("Copy to the clipboard only").tag(false)
                }
                if settings.pasteDirectly && !permissions.accessibility.isGranted {
                    accessibilityHint
                }
                Picker("Paste text as", selection: $settings.pasteFormat) {
                    ForEach(PasteFormat.allCases, id: \.self) { format in
                        Text(format.displayName).tag(format)
                    }
                }
            } header: {
                Text("Pasting")
            } footer: {
                Text(alternatePasteHint)
                    .foregroundStyle(.secondary)
            }

            ScreenshotSettingsSection(settings: settings, onShortcutRecordingChange: onShortcutRecordingChange)

            Section {
                LaunchAtLoginToggle()
                Toggle(isOn: $settings.checksForUpdatesAutomatically) {
                    Text("Check for updates weekly")
                    Text("Only reads release information from GitHub and never uploads any data")
                }
            } header: {
                Text("Startup & Updates")
            }
        }
        .formStyle(.grouped)
        .task { await permissions.run() }
    }

    /// 面板快捷键不能与截图快捷键相同
    private var screenshotReservation: [ShortcutRecorder.Reservation] {
        settings.screenshotHotKey.map { [.init(hotKey: $0, message: ShortcutReservationCopy.screenshots)] } ?? []
    }

    /// ⇧↩ 与 ⌘↩ 的说明：按另一种格式分别给出完整句子，不拼接格式名
    private var alternatePasteHint: String {
        switch settings.pasteFormat.alternate {
        case .original:
            String(
                localized: "Press ⇧↩ to paste with original formatting, or ⌘↩ to copy only.",
                comment: "Settings footer when the default paste format is plain text"
            )
        case .plainText:
            String(
                localized: "Press ⇧↩ to paste as plain text, or ⌘↩ to copy only.",
                comment: "Settings footer when the default paste format keeps the original formatting"
            )
        }
    }

    /// 选择了直接粘贴但缺少辅助功能权限时的提示
    private var accessibilityHint: some View {
        HStack(spacing: 8) {
            Label("Pasting directly requires Accessibility access", systemImage: "exclamationmark.triangle.fill")
                .font(.callout)
                .foregroundStyle(.orange)
            Spacer(minLength: 8)
            // 授权失效时只能去系统设置，按钮随状态改名
            Button(
                (permissions.accessibility.buttonAction ?? .grantAccess).title,
                action: AccessibilityAuthorization.requestOrOpenSettings
            )
        }
    }
}
