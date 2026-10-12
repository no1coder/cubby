import SwiftUI
import CubbyCore

/// 预览底栏上方的一条地址守护说明：敏感值显示类型标识、类型行与徽标；被替换进来的条目为红色说明与「详情」
struct SecurityPreviewStrip: View {
    let item: ClipItem
    let marker: CardSecurityMarker
    let onDetails: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 8) {
            switch marker {
            case .sensitive(let value, let isGuarded):
                ChainTile(kind: value.kind, size: 20)
                Text(SecurityCopy.checkLine(value.kind))
                    .font(.system(size: FontSize.caption))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                SecurityBadge(kind: value.kind, isGuarded: isGuarded)
            case .tampered:
                Image(systemName: "exclamationmark.shield.fill")
                    .foregroundStyle(SecurityPalette.redText(colorScheme))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(SecurityCopy.tamperedSource)
                        .font(.system(size: FontSize.caption, weight: .semibold))
                        .foregroundStyle(SecurityPalette.redText(colorScheme))
                    Text(SecurityCopy.tamperedNote)
                        .font(.system(size: FontSize.caption))
                        .foregroundStyle(.secondary)
                }
                .lineLimit(1)
                Spacer(minLength: 4)
                Button(SecurityCopy.details, action: onDetails)
                    .buttonStyle(SmallChipButtonStyle())
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(marker.isTampered ? SecurityPalette.red.opacity(0.1) : Color.clear)
        .accessibilityElement(children: .combine)
    }
}
