import SwiftUI

/// 加密 Vault 准备 / 迁移期间列表处的占位（docs/HISTORY-ENCRYPTION-DESIGN.md §4）：「正在加密历史…」+ 转圈。
/// 出现后先空白一小会儿再显示，启动很快时不会一闪而过；完成后条目自动出现
struct VaultPreparingPlaceholder: View {
    /// 超过这个时间还没准备好才显示文字与转圈
    static let revealDelay: Duration = .milliseconds(300)

    @State private var isRevealed = false

    var body: some View {
        VStack(spacing: 8) {
            if isRevealed {
                ProgressView()
                    .controlSize(.small)
                    .padding(.bottom, 4)
                Text("Encrypting your history…", comment: "Panel placeholder while the history is being encrypted")
                    .font(.system(size: FontSize.callout, weight: .semibold))
                    .e2eAnchor("panel.vault-placeholder.text")
                Text(
                    "Only happens the first time after an update",
                    comment: "Panel placeholder detail while the history is being encrypted"
                )
                .font(.system(size: FontSize.footnote))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 36)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .e2eAnchor("panel.vault-placeholder")
        .task {
            try? await Task.sleep(for: Self.revealDelay)
            guard !Task.isCancelled else { return }
            isRevealed = true
        }
    }
}
