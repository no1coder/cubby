import SwiftUI

/// 系统授权因签名变化而失效时的修复引导（辅助功能、屏幕录制共用）。
/// 由调用方仅在失效状态加入（状态由 PermissionMonitor 轮询），授权恢复后随之消失。
/// 失效时不自动向系统申请，避免系统弹窗与设置窗口叠在一起；终端命令只复制，不由应用代为执行。
struct PermissionRepairGuide: View {
    private static let copiedFeedbackDuration: Duration = .seconds(2)

    let removeStep: LocalizedStringKey
    let grantStep: LocalizedStringKey
    let openSettingsTitle: LocalizedStringKey
    let record: SignedGrantRecord
    let openSettings: () -> Void
    let grantAgain: () -> Void

    @State private var isExpanded = false
    @State private var didCopyCommand = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(
                """
                After an update, the old entry in System Settings may still look turned on, \
                but it no longer applies to this version.
                """
            )
            .font(.system(size: FontSize.caption))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button(openSettingsTitle, action: openSettings)
                Button("Grant Access Again", action: grantAgain)
            }
            DisclosureGroup("Steps", isExpanded: $isExpanded) {
                steps
            }
            .font(.system(size: FontSize.caption))
        }
    }

    private var steps: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(removeStep)
            Text(grantStep)
            Text("3. If it still doesn't work, run this command in Terminal, then repeat step 2:")
            HStack(spacing: 8) {
                Text(record.resetCommand)
                    .font(.system(size: FontSize.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                            .fill(Color.primary.opacity(0.06)))
                Button(didCopyCommand ? "Copied" : "Copy Command", action: copyCommand)
                    .disabled(didCopyCommand)
            }
        }
        .foregroundStyle(.secondary)
        .padding(.top, 4)
    }

    private func copyCommand() {
        record.copyResetCommand()
        didCopyCommand = true
        Task { @MainActor in
            try? await Task.sleep(for: Self.copiedFeedbackDuration)
            didCopyCommand = false
        }
    }
}

extension PermissionRepairGuide {
    static var accessibility: PermissionRepairGuide {
        PermissionRepairGuide(
            removeStep: "1. In the Accessibility list, select Cubby and click “−” to remove it.",
            grantStep: "2. Come back here, click “Grant Access Again” and turn on Cubby in the list that appears.",
            openSettingsTitle: "Open Accessibility Settings",
            record: AccessibilityAuthorization.record,
            openSettings: PasteService.openAccessibilitySettings,
            grantAgain: PasteService.requestTrust
        )
    }

    /// 屏幕录制授权后 macOS 常要求重启应用才生效，第 2 步一并说明
    static var screenRecording: PermissionRepairGuide {
        PermissionRepairGuide(
            removeStep: "1. In the Screen Recording list, select Cubby and click “−” to remove it.",
            grantStep: """
                2. Come back here, click “Grant Access Again”, turn on Cubby in the list, \
                then quit and reopen Cubby.
                """,
            openSettingsTitle: "Open Screen Recording Settings",
            record: ScreenRecordingAuthorization.record,
            openSettings: ScreenRecordingAuthorization.openSettings,
            grantAgain: ScreenRecordingAuthorization.requestAgain
        )
    }
}
