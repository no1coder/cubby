import SwiftUI

/// 面板顶部的提醒横幅：权限等问题为橙色，更新提醒为强调色（docs/UPDATE-REMINDER-DESIGN.md U9），结构相同：
/// 主按钮去处理；可选的第二个按钮；可忽略的提醒另有「稍后」（询问横幅为「不用了」）
struct WarningBanner: View {
    /// 底色与描边：深色 0.12 底；浅色 0.12 叠在灰玻璃上偏土黄，改为更淡的 0.10 底 + 0.5pt 描边
    private enum Appearance {
        static let darkFill = 0.12
        static let lightFill = 0.10
        static let lightStroke = 0.3
        static let increasedContrastStroke = 0.6
        static let strokeWidth: CGFloat = 0.5
        /// 11pt 的 .secondary 在深色玻璃上约 4.2:1，低于 AA；说明文字改用 primary 0.75（增强对比度 0.9）
        static let detailOpacity = 0.75
        static let increasedContrastDetailOpacity = 0.9
        static let iconSpacing: CGFloat = 10
        static let textSpacing: CGFloat = 2
        static let buttonSpacing: CGFloat = 8
        static let buttonsTopPadding: CGFloat = 4
        static let iconTopPadding: CGFloat = 1
    }

    let warning: PanelWarning
    /// 主按钮标题（例如复制后短暂显示「已复制」）
    let actionTitle: String
    let onAction: () -> Void
    /// nil 表示没有第二个按钮
    let onSecondary: (() -> Void)?
    /// nil 表示不提供「稍后」（如暂停记录：唯一的出口是恢复）
    let onDismiss: (() -> Void)?

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        HStack(alignment: .top, spacing: Appearance.iconSpacing) {
            Image(systemName: warning.symbolName)
                .font(.system(size: FontSize.body))
                .foregroundStyle(tint)
                .padding(.top, Appearance.iconTopPadding)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Appearance.textSpacing) {
                Text(warning.title)
                    .font(.system(size: FontSize.footnote, weight: .semibold))
                Text(warning.detail)
                    .font(.system(size: FontSize.caption))
                    .foregroundStyle(Color.primary.opacity(detailOpacity))
                    .fixedSize(horizontal: false, vertical: true)
                buttons
                    .padding(.top, Appearance.buttonsTopPadding)
            }
            Spacer(minLength: 0)
        }
        .padding(PanelMetrics.inset)
        .background(background)
        .padding(.horizontal, PanelMetrics.inset)
        .padding(.bottom, PanelMetrics.cardSpacing)
    }

    private var buttons: some View {
        HStack(spacing: Appearance.buttonSpacing) {
            Button(actionTitle, action: onAction)
                .buttonStyle(CapsuleButtonStyle())
                .e2eAnchor("banner.\(warning.anchorKey).action")
            if let onSecondary, let title = warning.secondaryActionTitle {
                Button(title, action: onSecondary)
                    .buttonStyle(CapsuleButtonStyle(isPrimary: false))
                    .e2eAnchor("banner.\(warning.anchorKey).secondary")
            }
            if let onDismiss {
                Button(warning.dismissTitle, action: onDismiss)
                    .buttonStyle(CapsuleButtonStyle(isPrimary: false))
                    .e2eAnchor("banner.\(warning.anchorKey).dismiss")
            }
        }
    }

    private var tint: Color {
        warning.style == .informational ? .accentColor : .orange
    }

    private var detailOpacity: Double {
        contrast == .increased ? Appearance.increasedContrastDetailOpacity : Appearance.detailOpacity
    }

    private var background: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
        let isLight = colorScheme == .light
        let strokeOpacity =
            contrast == .increased ? Appearance.increasedContrastStroke : (isLight ? Appearance.lightStroke : 0)
        return
            shape
            .fill(tint.opacity(isLight ? Appearance.lightFill : Appearance.darkFill))
            .overlay(shape.strokeBorder(tint.opacity(strokeOpacity), lineWidth: Appearance.strokeWidth))
    }
}
