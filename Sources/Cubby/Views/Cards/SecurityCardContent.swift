import SwiftUI
import CubbyCore

/// 列表卡片里的地址守护内容（PanelSecurity 设计稿）：敏感值为「头部 + 类型标识 + 类型行 + 分组显示的值」，
/// 被替换进来的条目为红色记录（来源未知、值划掉、说明与「详情」）
struct SecurityCardContent: View {
    let item: ClipItem
    let marker: CardSecurityMarker
    let palette: CardPalette
    let accessories: CardAccessories
    let onDetails: () -> Void

    var body: some View {
        switch marker {
        case .sensitive(let value, let isGuarded):
            sensitive(value, isGuarded: isGuarded)
        case .tampered:
            TamperedCardBody(item: item, palette: palette, accessories: accessories, onDetails: onDetails)
        }
    }

    private func sensitive(_ value: SensitiveValue, isGuarded: Bool) -> some View {
        VStack(alignment: .leading, spacing: PanelMetrics.cardRowSpacing) {
            HStack(spacing: 7) {
                AppIconView(
                    bundleID: item.source?.bundleID, size: PanelMetrics.sourceIconSize,
                    fallbackSymbol: item.kind.symbolName)
                CardSourceLine(
                    name: item.source?.name ?? TextStats.unknownSource, date: item.createdAt, palette: palette)
                Spacer(minLength: 4)
                SecurityBadge(kind: value.kind, isGuarded: isGuarded)
                accessories
            }
            SensitiveValueRow(value: value, palette: palette, size: FontSize.body)
        }
    }
}

/// 类型标识 + 「以太坊地址 · 校验通过」+ 4 位一组的值（首尾两组加粗）
struct SensitiveValueRow: View {
    let value: SensitiveValue
    let palette: CardPalette
    let size: CGFloat
    var tileSize: CGFloat = 26

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            ChainTile(kind: value.kind, size: tileSize)
            VStack(alignment: .leading, spacing: 1) {
                Text(SecurityCopy.checkLine(value.kind))
                    .font(.system(size: FontSize.caption))
                    .foregroundStyle(palette.secondary)
                    .lineLimit(1)
                Text(AddressText.attributed(value.value, style: AddressText.Style(size: size)))
                    .foregroundStyle(palette.primary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// 「守护中」（绿）、「已核验」（中性）、银行卡号（中性，不带盾牌）
struct SecurityBadge: View {
    let kind: SensitiveKind
    let isGuarded: Bool

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 4) {
            if kind != .bankCard {
                Image(systemName: "shield").font(.system(size: 9, weight: .semibold))
            }
            Text(title)
        }
        .font(.system(size: FontSize.caption, weight: .semibold))
        .foregroundStyle(isGuarded ? SecurityPalette.greenText(colorScheme) : Color.primary.opacity(0.75))
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .background(Capsule().fill(isGuarded ? SecurityPalette.green.opacity(0.2) : Color.primary.opacity(0.1)))
        .fixedSize()
    }

    private var title: String {
        if isGuarded { return SecurityCopy.guarding }
        return kind == .bankCard ? SecurityCopy.shortName(.bankCard) : SecurityCopy.verified
    }
}

/// 被替换进来的条目：红色小图标 +「来源未知 · 替换了上一条」+ 时间；值划掉；「不会出现在 ⌘1–⌘9 里…」+「详情」
struct TamperedCardBody: View {
    let item: ClipItem
    let palette: CardPalette
    let accessories: CardAccessories
    let onDetails: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Image(systemName: "exclamationmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(SecurityPalette.redText(colorScheme))
                    .frame(width: PanelMetrics.sourceIconSize, height: PanelMetrics.sourceIconSize)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous).fill(SecurityPalette.red.opacity(0.25))
                    )
                    .accessibilityHidden(true)
                Text(SecurityCopy.tamperedSource)
                    .font(.system(size: FontSize.caption, weight: .semibold))
                    .foregroundStyle(SecurityPalette.redText(colorScheme))
                    .lineLimit(1)
                Text(TimeFormatting.relative(item.createdAt))
                    .font(.system(size: FontSize.caption))
                    .foregroundStyle(palette.secondary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                accessories
            }
            StruckValue(text: item.text ?? "", size: FontSize.body)
            HStack(spacing: 8) {
                Text(SecurityCopy.tamperedNote)
                    .font(.system(size: FontSize.caption))
                    .foregroundStyle(palette.secondary)
                    .lineLimit(2)
                Spacer(minLength: 4)
                Button(SecurityCopy.details, action: onDetails)
                    .buttonStyle(SmallChipButtonStyle())
            }
        }
    }
}

/// 划掉的值（4 位一组）
struct StruckValue: View {
    let text: String
    let size: CGFloat

    var body: some View {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        Text(verbatim: AddressComparison.groups(value).joined(separator: " "))
            .font(.system(size: size, weight: .medium, design: .monospaced))
            .foregroundStyle(Color.primary.opacity(0.6))
            .strikethrough(true, color: SecurityPalette.red.opacity(0.8))
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// 卡片里的小按钮（22pt 高、6pt 圆角、淡底）
struct SmallChipButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: FontSize.caption))
            .foregroundStyle(Color.primary)
            .padding(.horizontal, 10)
            .frame(height: 22)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.primary.opacity(0.1)))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

extension CardPalette {
    /// 被替换进来的条目：红色淡底与描边
    static func tampered(_ scheme: ColorScheme, increasedContrast: Bool = false) -> CardPalette {
        let standard = CardPalette.standard(scheme, increasedContrast: increasedContrast)
        return CardPalette(
            background: SecurityPalette.red.opacity(scheme == .dark ? 0.1 : 0.08),
            selectedBackground: SecurityPalette.red.opacity(scheme == .dark ? 0.16 : 0.12),
            primary: standard.primary,
            secondary: standard.secondary,
            stroke: SecurityPalette.red.opacity(increasedContrast ? 0.7 : 0.4),
            isCustom: false
        )
    }
}

extension CardSecurityMarker {
    /// 读屏补充说明
    var accessibilityNote: String {
        switch self {
        case .sensitive(let value, let isGuarded):
            [SecurityCopy.checkLine(value.kind), isGuarded ? SecurityCopy.guarding : nil]
                .compactMap { $0 }.joined(separator: " · ")
        case .tampered:
            [SecurityCopy.tamperedSource, SecurityCopy.tamperedNote].joined(separator: " · ")
        }
    }
}
