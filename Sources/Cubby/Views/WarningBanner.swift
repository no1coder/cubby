import SwiftUI

/// 权限等问题提醒：主按钮去处理；可忽略的提醒另有「稍后」，在本次运行期间收起
struct WarningBanner: View {
    let warning: PanelWarning
    let onAction: () -> Void
    /// nil 表示不提供「稍后」（如暂停记录：唯一的出口是恢复）
    let onDismiss: (() -> Void)?

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbolName)
                .font(.system(size: FontSize.body))
                .foregroundStyle(.orange)
                .padding(.top, 1)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(warning.title)
                    .font(.system(size: FontSize.footnote, weight: .semibold))
                Text(warning.detail)
                    .font(.system(size: FontSize.caption))
                    // 11pt 的 .secondary 在深色玻璃上约 4.2:1，低于 AA；提高到 primary 0.75
                    .foregroundStyle(Color.primary.opacity(contrast == .increased ? 0.9 : 0.75))
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Button(warning.actionTitle, action: onAction)
                        .buttonStyle(CapsuleButtonStyle())
                    if let onDismiss {
                        Button("Not Now", action: onDismiss)
                            .buttonStyle(CapsuleButtonStyle(isPrimary: false))
                    }
                }
                .padding(.top, 4)
            }
            Spacer(minLength: 0)
        }
        .padding(PanelMetrics.inset)
        .background(background)
        .padding(.horizontal, PanelMetrics.inset)
        .padding(.bottom, PanelMetrics.cardSpacing)
    }

    private var symbolName: String {
        warning == .paused ? "pause.circle.fill" : "exclamationmark.triangle.fill"
    }

    /// 深色：橙色 0.12 底；浅色：0.12 叠在灰玻璃上偏土黄，改为更淡的 0.10 底 + 0.5pt 橙色描边
    private var background: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
        let isLight = colorScheme == .light
        let strokeOpacity = contrast == .increased ? 0.6 : (isLight ? 0.3 : 0)
        return
            shape
            .fill(Color.orange.opacity(isLight ? 0.10 : 0.12))
            .overlay(shape.strokeBorder(Color.orange.opacity(strokeOpacity), lineWidth: 0.5))
    }
}
