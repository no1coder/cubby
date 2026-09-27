import SwiftUI

/// 辅助功能授权失效时的修复引导：仅在失效状态显示，授权恢复后自动消失。
/// 失效时不调用 requestTrust()，避免系统弹窗与设置窗口叠在一起；终端命令只复制，不由应用代为执行。
struct AccessibilityRepairGuide: View {
    private static let refreshInterval: TimeInterval = 1.5
    private static let copiedFeedbackDuration: Duration = .seconds(2)

    @State private var isExpanded = false
    @State private var didCopyCommand = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: Self.refreshInterval)) { _ in
            if AccessibilityAuthorization.status == .stale {
                content
            }
        }
    }

    private var content: some View {
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
                Button("Open Accessibility Settings", action: PasteService.openAccessibilitySettings)
                Button("Grant Access Again", action: PasteService.requestTrust)
            }
            DisclosureGroup("Steps", isExpanded: $isExpanded) {
                steps
            }
            .font(.system(size: FontSize.caption))
        }
    }

    private var steps: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("1. In the Accessibility list, select Cubby and click “−” to remove it.")
            Text("2. Come back here, click “Grant Access Again” and turn on Cubby in the list that appears.")
            Text("3. If it still doesn't work, run this command in Terminal, then repeat step 2:")
            HStack(spacing: 8) {
                Text(AccessibilityAuthorization.resetCommand)
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
        AccessibilityAuthorization.copyResetCommand()
        didCopyCommand = true
        Task { @MainActor in
            try? await Task.sleep(for: Self.copiedFeedbackDuration)
            didCopyCommand = false
        }
    }
}
