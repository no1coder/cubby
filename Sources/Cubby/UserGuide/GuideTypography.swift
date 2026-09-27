import AppKit

/// 使用说明的字体、颜色与间距。字号取自 FontSize 阶梯；一、二级标题用系统文字样式（与关于页、引导页的标题一致）
@MainActor
enum GuideTypography {
    static let body = NSFont.systemFont(ofSize: FontSize.callout)
    static let bodyBold = NSFont.systemFont(ofSize: FontSize.callout, weight: .semibold)
    static let code = NSFont.monospacedSystemFont(ofSize: FontSize.body, weight: .regular)
    static let codeBlock = NSFont.monospacedSystemFont(ofSize: FontSize.footnote, weight: .regular)
    /// 键帽字体与 ShortcutKeyCap 一致：12pt 圆体半粗
    static let key = rounded(NSFont.systemFont(ofSize: FontSize.footnote, weight: .semibold))
    static let listMarker = NSFont.monospacedDigitSystemFont(ofSize: FontSize.callout, weight: .regular)

    static let lineSpacing: CGFloat = 4
    static let paragraphSpacing: CGFloat = 12
    /// 同一列表内相邻两项的间距
    static let listItemSpacing: CGFloat = 6
    /// 每级列表的缩进；项目符号位于缩进前 markerWidth 处
    static let listIndent: CGFloat = 24
    static let markerWidth: CGFloat = 20
    /// 引用块左侧竖条与文字的距离、竖条宽度
    static let quoteInset: CGFloat = 14
    static let quoteBarWidth: CGFloat = 3
    /// 代码块、表格单元格的内边距
    static let blockPadding: CGFloat = 8
    static let tableCellPadding: CGFloat = 6

    static let text = NSColor.labelColor
    static let secondaryText = NSColor.secondaryLabelColor
    static let separator = NSColor.separatorColor
    static let quoteBar = NSColor.controlAccentColor.withAlphaComponent(0.6)
    static let quoteBackground = NSColor.labelColor.withAlphaComponent(0.04)
    static let headerBackground = NSColor.labelColor.withAlphaComponent(0.04)

    static func heading(level: Int) -> NSFont {
        switch level {
        case 1: NSFont.systemFont(ofSize: NSFont.preferredFont(forTextStyle: .title1).pointSize, weight: .bold)
        case 2: NSFont.systemFont(ofSize: NSFont.preferredFont(forTextStyle: .title2).pointSize, weight: .bold)
        default: NSFont.systemFont(ofSize: FontSize.title, weight: .semibold)
        }
    }

    /// 标题上方与下方的间距
    static func headingSpacing(level: Int) -> (before: CGFloat, after: CGFloat) {
        switch level {
        case 1: (0, 14)
        case 2: (24, 10)
        default: (18, 6)
        }
    }

    static func bold(_ font: NSFont) -> NSFont {
        NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
    }

    static func italic(_ font: NSFont) -> NSFont {
        NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
    }

    private static func rounded(_ font: NSFont) -> NSFont {
        guard let descriptor = font.fontDescriptor.withDesign(.rounded) else { return font }
        return NSFont(descriptor: descriptor, size: font.pointSize) ?? font
    }
}
