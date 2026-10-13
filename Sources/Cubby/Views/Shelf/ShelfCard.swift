import CubbyCore
import SwiftUI

/// 底部横条里的方卡（docs/UI-UPGRADE-PLAN.md 第 3 节）：顶部 34pt 类型色条（类型名 · 时间 · 来源图标），
/// 中部内容（可选的译文行），底部元信息 + ⌘N；选中时带外环光晕（上浮 6pt 由 ShelfCardRow 处理，悬停工具条随之上浮）。
/// 卡片内部的尺寸照设计稿（12pt 正文等）
struct ShelfCard: View {
    let item: ClipItem
    let index: Int
    let isSelected: Bool
    let keywords: [String]
    let imageSource: ClipImageSource?
    var translation: CardTranslationDecoration?
    var isOnClothesline = false
    /// ⌥↩ 行内问题上的按钮
    var onInlineAction: () -> Void = {}
    /// 地址守护的标记（敏感值、被替换进来的红色记录）
    var security: CardSecurityMarker?
    var onShowDetails: () -> Void = {}

    static let width: CGFloat = 214
    /// 选中卡片上浮的距离
    static let lift: CGFloat = 6

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let style = CardStyle(item: item)
        let palette =
            security?.isTampered == true
            ? .tampered(colorScheme, increasedContrast: contrast == .increased)
            : style.palette(colorScheme, increasedContrast: contrast == .increased)
        let shape = RoundedRectangle(cornerRadius: Radius.card, style: .continuous)

        VStack(spacing: 0) {
            ShelfTypeBar(item: item, style: style, palette: palette, translatedLanguages: translatedLanguages)
            content(style: style, palette: palette)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .clipped()
            if let line = translation?.line, translation?.peek == nil {
                TranslationLineView(line: line, keywords: keywords)
                    .padding(.horizontal, ShelfMetrics.contentPadding)
                    .e2eAnchor("list.line.\(item.id)")
            }
            metaRow(style: style, palette: palette)
        }
        .frame(width: Self.width)
        .frame(maxHeight: .infinity)
        .overlay { if translation?.inline?.isRunning == true { InlineRunningOverlay() } }
        .clipShape(shape)
        .cardSurface(palette, isSelected: isSelected)
        .contentShape(shape)
        .animation(.easeOut(duration: Motion.selection), value: isSelected)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityHint(
            Text("Press Return to paste, or Space to preview.", comment: "VoiceOver hint for a clipboard card"))
    }

    private var translatedLanguages: [String] {
        translation?.cachedLanguages ?? []
    }

    @ViewBuilder
    private func content(style: CardStyle, palette: CardPalette) -> some View {
        if let peek = translation?.peek {
            PeekContent(peek: peek, item: item, imageSource: imageSource)
                .padding(ShelfMetrics.contentPadding)
                .e2eAnchor("list.peek.\(item.id)")
        } else if let security {
            ShelfSecurityBody(marker: security, item: item, palette: palette, onDetails: onShowDetails)
        } else {
            ShelfCardBody(item: item, style: style, palette: palette, keywords: keywords, imageSource: imageSource)
                .overlay(alignment: .topTrailing) { if isOnClothesline { ClotheslineBadge() } }
        }
    }

    /// 底部一行：元信息 + ⌘N；按住 ⌥ 时换成预览说明，⌥↩ 进行中换成进度，失败时换成原因与操作
    @ViewBuilder
    private func metaRow(style: CardStyle, palette: CardPalette) -> some View {
        HStack(spacing: 6) {
            if let peek = translation?.peek {
                PeekMetaRow(peek: peek, isOptionHeld: translation?.isOptionHeld ?? false)
            } else if let job = translation?.inline, job.isRunning {
                InlineProgressRow(job: job)
                    .e2eAnchor("list.inline.\(item.id)")
            } else if let job = translation?.inline, case .failed(let issue) = job.phase {
                InlineIssueRow(issue: issue, plan: job.plan, action: translation?.inlineAction, perform: onInlineAction)
                    .e2eAnchor("list.inlineIssue.\(item.id)")
            } else {
                Text(verbatim: ShelfCardBody.metadata(for: item, style: style))
                    .font(.system(size: FontSize.caption2))
                    .foregroundStyle(palette.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 4)
            if index < 9 {
                QuickPasteKeyCap(number: index + 1, isSelected: isSelected, palette: palette)
            }
        }
        .padding(.horizontal, ShelfMetrics.contentPadding)
        .padding(.top, ShelfMetrics.metaTop)
        .padding(.bottom, ShelfMetrics.metaBottom)
    }

    private var accessibilityLabel: String {
        [
            item.source?.name ?? TextStats.unknownSource, item.title, security?.accessibilityNote,
            TimeFormatting.relative(item.createdAt),
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
    }
}

/// 横条卡片的尺寸常量（照设计稿：内容内边距 10、色条 34、元信息一行 7 / 8 的上下留白）
enum ShelfMetrics {
    static let barHeight: CGFloat = 34
    static let contentPadding: CGFloat = 10
    static let metaTop: CGFloat = 7
    static let metaBottom: CGFloat = 8
    /// 卡片之间的间距
    static let cardSpacing: CGFloat = 14
    /// 顶部一行的搜索框宽度
    static let searchWidth: CGFloat = 260
    /// 分类分段控件里每一项的最小宽度
    static let segmentWidth: CGFloat = 56
}

/// 顶部的类型色条：半透明的类型色（文本琥珀、链接蓝、图片橙、文件绿、代码中性深色），不是纯色块
private struct ShelfTypeBar: View {
    let item: ClipItem
    let style: CardStyle
    let palette: CardPalette
    let translatedLanguages: [String]

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let tint = ShelfTypeTint(item: item, style: style, isDark: colorScheme == .dark)
        HStack(spacing: 6) {
            Text(tint.name)
                .font(.system(size: FontSize.footnote, weight: .semibold))
                .foregroundStyle(tint.label ?? palette.primary)
            Text(TimeFormatting.relative(item.createdAt))
                .font(.system(size: FontSize.caption))
                .foregroundStyle((tint.label ?? palette.primary).opacity(0.75))
                .lineLimit(1)
            Spacer(minLength: 4)
            if !translatedLanguages.isEmpty {
                TranslationChip(languages: translatedLanguages)
                    .e2eAnchor("list.chip.\(item.id)")
            }
            if item.isFavorite {
                Image(systemName: "star.fill")
                    .font(.system(size: FontSize.caption2))
                    .foregroundStyle(palette.isCustom ? palette.primary : Color.yellow)
                    .accessibilityHidden(true)
            }
            // 颜色方卡的色条叠在颜色上，不放来源图标（设计稿）
            if !style.isColor {
                AppIconView(
                    bundleID: item.source?.bundleID, size: PanelMetrics.sourceIconSize,
                    fallbackSymbol: item.kind.symbolName)
            }
        }
        .padding(.horizontal, ShelfMetrics.contentPadding)
        .frame(height: ShelfMetrics.barHeight)
        .background(tint.fill)
    }
}

/// 各类型的色条颜色与标签色（浅色外观下标签用深一级的同色，深色外观用卡片前景色）
private struct ShelfTypeTint {
    let name: String
    let fill: Color
    let label: Color?

    init(item: ClipItem, style: CardStyle, isDark: Bool) {
        switch (style, item.kind) {
        case (.code, _):
            name = String(localized: "Code", comment: "Badge on a code card whose language is not recognized")
            fill = isDark ? Color(red: 0.2, green: 0.25, blue: 0.35) : Color.white.opacity(0.07)
            label = nil
        case (.color, _):
            name = item.kind.displayName
            fill = Color.black.opacity(isDark ? 0.18 : 0.15)
            label = nil
        default:
            name = item.kind.displayName
            let (rgb, dark, light, labelRGB) = Self.palette(for: item.kind)
            fill = Color(red: rgb.0, green: rgb.1, blue: rgb.2).opacity(isDark ? dark : light)
            label = isDark ? nil : Color(red: labelRGB.0, green: labelRGB.1, blue: labelRGB.2)
        }
    }

    /// （类型色，深色透明度，浅色透明度，浅色外观的标签色）
    private static func palette(
        for kind: ClipKind
    ) -> ((Double, Double, Double), Double, Double, (Double, Double, Double)) {
        switch kind {
        case .text: ((0.95, 0.67, 0.13), 0.34, 0.22, (0.54, 0.36, 0))
        case .link: ((0.18, 0.49, 0.96), 0.38, 0.16, (0.04, 0.32, 0.76))
        case .image: ((0.91, 0.53, 0.23), 0.4, 0.2, (0.64, 0.28, 0.05))
        case .file: ((0.19, 0.82, 0.35), 0.26, 0.16, (0.07, 0.46, 0.23))
        case .color: ((0, 0, 0), 0.18, 0.15, (0, 0, 0))
        }
    }
}
