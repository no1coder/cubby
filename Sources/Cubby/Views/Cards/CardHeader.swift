import CubbyCore
import SwiftUI

/// 卡片头部一行：18pt 来源图标 + 应用名（11pt semibold）+ 相对时间，右侧为附加标记与 ⌘N 键帽。
/// 图标不再单独占左侧一列，正文因此占满卡片宽度
struct CardHeader: View {
    let item: ClipItem
    let palette: CardPalette
    let accessories: CardAccessories

    var body: some View {
        HStack(spacing: 7) {
            AppIconView(
                bundleID: item.source?.bundleID,
                size: PanelMetrics.sourceIconSize,
                fallbackSymbol: item.kind.symbolName,
                fallbackTint: palette.isCustom ? palette.primary : nil
            )
            CardSourceLine(name: item.source?.name ?? TextStats.unknownSource, date: item.createdAt, palette: palette)
            Spacer(minLength: 4)
            accessories
        }
    }
}

/// 「应用名 时间」：名称 semibold，时间次要色；空间不够时先截断名称
struct CardSourceLine: View {
    let name: String
    let date: Date
    let palette: CardPalette

    var body: some View {
        HStack(spacing: 6) {
            Text(name)
                .font(.system(size: FontSize.caption, weight: .semibold))
                .foregroundStyle(palette.primary.opacity(0.86))
                .lineLimit(1)
            Text(TimeFormatting.relative(date))
                .font(.system(size: FontSize.caption))
                .foregroundStyle(palette.secondary)
                .lineLimit(1)
                .layoutPriority(1)
        }
    }
}

/// 卡片右上角的附加标记：缓存译文的「译」角标、代码语言徽标、收藏星标与 ⌘N 键帽
struct CardAccessories: View {
    let item: ClipItem
    let index: Int
    let isSelected: Bool
    let palette: CardPalette
    var translatedLanguages: [String] = []
    var badge: String?

    private static let quickPasteCount = 9

    var body: some View {
        HStack(spacing: 5) {
            if !translatedLanguages.isEmpty {
                TranslationChip(languages: translatedLanguages)
                    .e2eAnchor("list.chip.\(item.id)")
            }
            if let badge {
                CodeBadge(text: badge)
            }
            if item.isFavorite {
                Image(systemName: "star.fill")
                    .font(.system(size: FontSize.caption2))
                    .foregroundStyle(palette.isCustom ? palette.primary : Color.yellow)
                    .accessibilityHidden(true)
            }
            if index < Self.quickPasteCount {
                QuickPasteKeyCap(number: index + 1, isSelected: isSelected, palette: palette)
            }
        }
        .fixedSize()
    }
}

/// ⌘N 键帽：普通为淡底，选中卡片上为实心强调色
struct QuickPasteKeyCap: View {
    let number: Int
    let isSelected: Bool
    let palette: CardPalette

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Text(verbatim: "⌘\(number)")
            .font(.system(size: FontSize.caption2, weight: .semibold))
            .monospacedDigit()
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundStyle(isSelected ? Color.white : palette.primary.opacity(0.75))
            .background(
                RoundedRectangle(cornerRadius: Radius.key, style: .continuous)
                    .fill(isSelected ? Color.accentColor : fill)
            )
            .accessibilityHidden(true)
    }

    private var fill: Color {
        if palette.isCustom { return Color.white.opacity(0.12) }
        return colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.06)
    }
}

/// 代码卡的语言徽标（如「Swift」）：紫色淡底 + 浅紫字，两种外观相同（代码卡总是深底）
struct CodeBadge: View {
    let text: String

    var body: some View {
        Text(verbatim: text)
            .font(.system(size: FontSize.caption2, weight: .semibold))
            .foregroundStyle(Color(red: 0.85, green: 0.65, blue: 1))
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(
                RoundedRectangle(cornerRadius: Radius.key, style: .continuous)
                    .fill(Color(red: 0.75, green: 0.35, blue: 0.95).opacity(0.2))
            )
    }
}
