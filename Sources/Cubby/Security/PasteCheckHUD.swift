import SwiftUI
import CubbyCore

/// 粘贴核对 HUD（PanelSecurity 设计稿右下）：从 Cubby 粘贴 / 复制敏感值后，确认剪贴板里的就是这条，显示 2 秒
@MainActor
enum PasteCheckHUD {
    static let duration: Duration = .seconds(2)

    /// - Parameter app: 粘贴到的应用；只复制时为 nil
    static func show(
        _ value: SensitiveValue, pasted: Bool, app: String?, at anchor: CGPoint, duration: Duration = duration
    ) {
        let title =
            if !pasted {
                SecurityCopy.copiedMatches
            } else if let app {
                SecurityCopy.pastedMatches(app)
            } else {
                SecurityCopy.pastedMatchesNoApp
            }
        HUDToast.present(PasteCheckView(title: title, value: value.value), duration: duration, at: anchor)
    }
}

private struct PasteCheckView: View {
    let title: String
    let value: String

    /// 宽度随标题伸展（应用名长短不一），超过上限才换行
    private static let minWidth: CGFloat = 330
    private static let maxWidth: CGFloat = 520

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        VStack(alignment: .leading, spacing: 6) {
            Label {
                Text(title)
                    .font(.system(size: FontSize.body, weight: .semibold))
                    .frame(maxWidth: Self.maxWidth - 60, alignment: .leading)
                    .fixedSize(horizontal: true, vertical: true)
            } icon: {
                Image(systemName: "checkmark")
                    .font(.system(size: FontSize.body, weight: .bold))
                    .foregroundStyle(SecurityPalette.green)
            }
            Text(
                AddressText.abbreviated(
                    value, style: AddressText.Style(size: FontSize.footnote, endsColor: .primary))
            )
            .foregroundStyle(Color.primary.opacity(0.75))
            .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(minWidth: Self.minWidth, alignment: .leading)
        .background(shape.fill(.regularMaterial))
        .overlay(shape.strokeBorder(SecurityPalette.green.opacity(0.45), lineWidth: 1))
        .padding(12)
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.4 : 0.15), radius: 14, y: 8)
        .accessibilityElement(children: .combine)
    }
}
