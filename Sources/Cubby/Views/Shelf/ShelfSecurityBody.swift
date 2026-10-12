import CubbyCore
import SwiftUI

/// 横条方卡的地址守护内容：敏感值为徽标 + 类型行 + 分组显示的值；被替换进来的为红色说明 + 划掉的值 +「详情」
struct ShelfSecurityBody: View {
    let marker: CardSecurityMarker
    let item: ClipItem
    let palette: CardPalette
    let onDetails: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch marker {
            case .sensitive(let value, let isGuarded):
                SecurityBadge(kind: value.kind, isGuarded: isGuarded)
                SensitiveValueRow(value: value, palette: palette, size: FontSize.footnote, tileSize: 22)
            case .tampered:
                Text(SecurityCopy.tamperedSource)
                    .font(.system(size: FontSize.caption, weight: .semibold))
                    .foregroundStyle(SecurityPalette.redText(colorScheme))
                    .fixedSize(horizontal: false, vertical: true)
                StruckValue(text: item.text ?? "", size: FontSize.footnote)
                Text(SecurityCopy.tamperedNote)
                    .font(.system(size: FontSize.caption))
                    .foregroundStyle(palette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button(SecurityCopy.details, action: onDetails)
                    .buttonStyle(SmallChipButtonStyle())
            }
        }
        .padding(ShelfMetrics.contentPadding)
    }
}
